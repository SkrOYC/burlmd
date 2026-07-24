//! Debounced background sync worker (ticket SYNC-C003): a dedicated
//! `std::thread` that pushes local commits to the configured Git remote
//! after a period of inactivity, retries transient network failures with
//! exponential backoff, and runs the fetch+merge conflict path (re-index +
//! notify) when a push is rejected as non-fast-forward — the sequence
//! `architecture/flows/flow-sync-push.md` documents end to end.
//!
//! ## Why a dedicated thread, not `async`
//! `tech-spec/guidelines.md`'s Rust section is explicit: "Avoid async/await
//! unless absolutely necessary (e.g., long-running sync operations on a
//! dedicated thread)" — this ticket is exactly that named carve-out. There
//! is no `tokio` (or any other async executor) anywhere in this crate; the
//! scheduler is plain `std::thread` + `std::sync::mpsc` + `Duration`-based
//! `recv_timeout` waits, nothing else.
//!
//! ## Threading model
//! [`SyncScheduler::start`] spawns one background thread that loops on
//! `Receiver::recv_timeout`, waking either when a [`Command`] arrives
//! (sent by `notify_activity()`/`stop()`) or when the *soonest* of three
//! independent absolute deadlines elapses:
//!
//! - the **debounce deadline** — set to `now + SyncConfig::debounce` on
//!   every `notify_activity()` call. This is true debounce, not throttle:
//!   rapid repeated activity keeps pushing the deadline further out, so the
//!   worker only fires once activity actually goes quiet for the full
//!   window, exactly matching the Gherkin ("5 seconds of inactivity");
//! - the **periodic poll deadline** (`SyncConfig::poll_interval`) — fires a
//!   sync cycle even with no new activity, so a commit made just before the
//!   app lost focus (no further `notify_activity()` calls at all) still
//!   eventually syncs;
//! - the **backoff deadline** — only set while a retry is pending after a
//!   network failure (see below).
//!
//! Because every deadline is an absolute `Instant` rather than a relative
//! sleep, waking early for an unrelated reason (e.g. an activity ping
//! arriving mid-backoff-wait) and simply recomputing the remaining wait on
//! the next loop iteration is always correct — nothing needs to be
//! cancelled or restarted by hand.
//!
//! `stop()` sends [`Command::Stop`] over the same channel `notify_activity`
//! uses, so it interrupts a `recv_timeout` wait immediately — including one
//! that is mid-backoff with seconds left on the clock — then joins the
//! thread. `Drop` also calls `stop()`, so a `SyncScheduler` going out of
//! scope can never leak a running background thread.
//!
//! ## Dependency injection
//! [`SyncDeps`] holds every side-effecting operation as a boxed `Fn`
//! closure rather than a locally-defined trait object — deliberately: this
//! crate has an FFI scanner (`flutter_rust_bridge`, `rust_input:
//! crate::api`) that (per `api::auth`'s `GitHubOAuthEndpoints` doc comment)
//! empirically treats certain trait shapes as exposable regardless of
//! visibility. `sync` sits entirely outside `crate::api` so that trap does
//! not actually apply here, but plain closures are the simplest injection
//! seam anyway and match this crate's existing precedent (`api::auth`'s
//! `store: impl FnOnce(&OAuthTokens) -> Result<(), AppError>` parameter).
//!
//! `SyncDeps::default()` wires `push`/`pull` straight to
//! `git::operations::{push, pull}` — their signatures match the closure
//! types exactly, so the function items coerce directly with no adapter
//! needed. `credentials` and `reindex` are documented, *intentional*
//! no-ops by default:
//!
//! - **`credentials`**: `git::operations` (SYNC-C001) accepts an optional
//!   [`GitCredentials`], and `api::auth` (SYNC-C002) stores GitHub OAuth
//!   tokens in the OS Keychain — but `api::auth` currently exposes no
//!   public "read the stored token back out" accessor (only
//!   `store_tokens_in_keyring`, private to that module). Adding one is a
//!   change to `rust/src/api/auth.rs`, a file this ticket's scope line
//!   (`rust/src/sync/scheduler.rs` only) does not cover, so real keychain
//!   retrieval is left as an injectable closure for the caller who
//!   constructs the production `SyncScheduler` to supply. See the deviation
//!   note in the epic file.
//! - **`reindex`**: no re-index-notes/notes_fts function exists anywhere in
//!   this crate as of this ticket (verified by grep across `rust/src`) —
//!   Epic B never added one. Wiring a real one is therefore deferred the
//!   same way; the hook exists and is unconditionally called on the
//!   conflict path per `flow-sync-push.md`, it just does nothing by
//!   default until that function exists to wire in.
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use crate::error::AppError;
use crate::git::operations::{self, GitCredentials};

/// Everything about *when* the scheduler fires and how it recovers from
/// failure. Every timing knob is a `Duration` field (not a hardcoded
/// constant) precisely so tests can shrink them to milliseconds instead of
/// waiting on real 5-second/multi-minute clocks.
#[derive(Clone)]
pub struct SyncConfig {
    /// The local Workspace directory containing the `.git` repository to
    /// sync (passed straight through to `git::operations::{push, pull}`).
    pub repo_path: PathBuf,
    /// The configured remote name, e.g. `"origin"`.
    pub remote: String,
    /// The branch to push/pull, e.g. `"main"`.
    pub branch: String,
    /// How long the worker waits for *inactivity* before pushing — the
    /// Gherkin's "5 seconds of inactivity". Reset by every
    /// [`SyncScheduler::notify_activity`] call.
    pub debounce: Duration,
    /// How often the worker attempts a sync cycle even without an
    /// intervening `notify_activity()` call — the "every X minutes" half
    /// of the ticket's description.
    pub poll_interval: Duration,
    /// The delay before the first retry after a `NetworkError`, and the
    /// unit the exponential backoff doubles from.
    pub backoff_base: Duration,
    /// The ceiling the doubling backoff delay never exceeds.
    pub backoff_cap: Duration,
}

impl SyncConfig {
    /// Sensible production defaults: 5s debounce (the literal Gherkin
    /// value), a 5-minute poll interval, and a 1s-doubling-to-60s-cap
    /// backoff. Every field remains publicly settable so tests can override
    /// them with millisecond-scale values.
    pub fn new(repo_path: PathBuf, remote: impl Into<String>, branch: impl Into<String>) -> Self {
        Self {
            repo_path,
            remote: remote.into(),
            branch: branch.into(),
            debounce: Duration::from_secs(5),
            poll_interval: Duration::from_secs(5 * 60),
            backoff_base: Duration::from_secs(1),
            backoff_cap: Duration::from_secs(60),
        }
    }
}

/// A credentials lookup, called once per sync cycle so a freshly-refreshed
/// token is always used rather than one captured at `start()` time.
pub type CredentialsFn = Box<dyn Fn() -> Option<GitCredentials> + Send>;
/// The shape of `git::operations::push` and `git::operations::pull` alike,
/// so both closure slots below share one alias.
pub type GitOpFn =
    Box<dyn Fn(&Path, &str, &str, Option<&GitCredentials>) -> Result<(), AppError> + Send>;
/// Triggered once, unconditionally, after a rejected push's follow-up pull
/// completes (regardless of whether that pull itself succeeded or produced
/// conflict markers) — per `flow-sync-push.md`'s "Trigger re-index of notes
/// and notes_fts tables" step.
pub type ReindexFn = Box<dyn Fn() -> Result<(), AppError> + Send>;
/// Triggered alongside `reindex`, carrying the follow-up pull's own result
/// so the caller can distinguish "merged cleanly, nothing to review" from
/// `Err(AppError::GitConflict)` ("conflict markers are now in the working
/// tree, `flow-conflict-resolution.md`'s Suggestion-node path should take
/// over") from any other error the pull itself hit.
pub type ConflictHookFn = Box<dyn Fn(Result<(), AppError>) + Send>;

/// The scheduler's side-effecting operations, injected rather than hard
/// wired — see the module doc comment for the full rationale and for what
/// `default()` does and does not wire up.
pub struct SyncDeps {
    pub credentials: CredentialsFn,
    pub push: GitOpFn,
    pub pull: GitOpFn,
    pub reindex: ReindexFn,
    pub on_conflict: ConflictHookFn,
}

impl Default for SyncDeps {
    fn default() -> Self {
        Self {
            // No public "read the stored OAuth token back out of the OS
            // Keychain" accessor exists yet (see the module doc comment) —
            // callers wiring a real scheduler must supply their own.
            credentials: Box::new(|| None),
            push: Box::new(operations::push),
            pull: Box::new(operations::pull),
            // No notes/notes_fts re-index function exists yet in this
            // crate (see the module doc comment) — deferred.
            reindex: Box::new(|| Ok(())),
            on_conflict: Box::new(|_result| {}),
        }
    }
}

/// Observable state, polled via [`SyncScheduler::status`] /
/// [`SyncScheduler::last_error`] rather than logged — this codebase has no
/// logging framework, and `println!`/`eprintln!` debug output must never
/// ship (see `tech-spec/guidelines.md` and this ticket's own "log-free"
/// instruction for unexpected errors).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SyncStatus {
    /// No sync cycle is in flight and the last one (if any) succeeded.
    Idle,
    /// A push/pull cycle is currently running.
    Syncing,
    /// The last push failed with a `NetworkError`; a backoff retry is
    /// scheduled.
    Retrying,
    /// The last push was rejected as non-fast-forward and the follow-up
    /// pull left real `<<<<<<<` conflict markers in the working tree.
    Conflict,
    /// The last cycle failed with something other than a network error or
    /// a git conflict; see [`SyncScheduler::last_error`] for detail.
    Error,
}

enum Command {
    Activity,
    Stop,
}

/// Owns the dedicated background thread. See the module doc comment for
/// the full threading/debounce/backoff design.
pub struct SyncScheduler {
    sender: mpsc::Sender<Command>,
    // `Mutex<Option<JoinHandle>>` rather than a bare `JoinHandle` so
    // `stop()` can be called through `&self` (needed for `Drop::drop`,
    // which only ever hands out `&mut self` but must still be safely
    // callable after an explicit `stop()` already ran) and is idempotent:
    // the second call finds `None` and no-ops instead of double-joining.
    handle: Mutex<Option<thread::JoinHandle<()>>>,
    status: Arc<Mutex<SyncStatus>>,
    last_error: Arc<Mutex<Option<AppError>>>,
}

impl SyncScheduler {
    /// Spawns the background thread and returns immediately; the thread
    /// itself just waits (see the module doc comment) until the first
    /// `notify_activity()`/poll-interval tick actually gives it work.
    pub fn start(config: SyncConfig, deps: SyncDeps) -> Self {
        let (sender, receiver) = mpsc::channel();
        let status = Arc::new(Mutex::new(SyncStatus::Idle));
        let last_error = Arc::new(Mutex::new(None));

        let thread_status = Arc::clone(&status);
        let thread_last_error = Arc::clone(&last_error);
        let handle = thread::Builder::new()
            .name("burlmd-sync".to_string())
            .spawn(move || run(config, deps, receiver, thread_status, thread_last_error))
            .expect("spawning the sync scheduler background thread should not fail");

        Self {
            sender,
            handle: Mutex::new(Some(handle)),
            status,
            last_error,
        }
    }

    /// Call on explicit save / local commit. Resets the debounce timer —
    /// rapid successive calls keep postponing the push until a full
    /// `SyncConfig::debounce` window passes with no further call.
    pub fn notify_activity(&self) {
        // The receiving thread may have already exited (e.g. a prior
        // `stop()`); `send` failing in that case just means there is
        // nothing left to notify, not a bug the caller needs to handle.
        let _ = self.sender.send(Command::Activity);
    }

    /// Signals the background thread to exit — interrupting any in-progress
    /// debounce or backoff wait immediately, even one with seconds left on
    /// the clock — and joins it. Idempotent: safe to call more than once,
    /// and called again (no-op the second time) by `Drop`.
    pub fn stop(&self) {
        let _ = self.sender.send(Command::Stop);
        if let Ok(mut guard) = self.handle.lock() {
            if let Some(handle) = guard.take() {
                let _ = handle.join();
            }
        }
    }

    /// The scheduler's current state. See [`SyncStatus`].
    pub fn status(&self) -> SyncStatus {
        self.status
            .lock()
            .map(|s| s.clone())
            .unwrap_or(SyncStatus::Error)
    }

    /// The most recent error observed by a sync cycle, if any. Cleared back
    /// to `None` the next time a cycle succeeds cleanly.
    pub fn last_error(&self) -> Option<AppError> {
        self.last_error.lock().ok().and_then(|e| e.clone())
    }
}

impl Drop for SyncScheduler {
    fn drop(&mut self) {
        self.stop();
    }
}

fn set_status(status: &Arc<Mutex<SyncStatus>>, value: SyncStatus) {
    if let Ok(mut guard) = status.lock() {
        *guard = value;
    }
}

fn set_last_error(last_error: &Arc<Mutex<Option<AppError>>>, value: Option<AppError>) {
    if let Ok(mut guard) = last_error.lock() {
        *guard = value;
    }
}

/// The background thread's whole life cycle: wait for whichever deadline
/// or [`Command`] comes first, act on it, repeat until [`Command::Stop`]
/// (or the sender being dropped, which `SyncScheduler::stop`'s channel
/// send would otherwise make unreachable, but a defensive exit-on-hangup
/// keeps this loop from spinning forever if that ever changes).
fn run(
    config: SyncConfig,
    deps: SyncDeps,
    receiver: mpsc::Receiver<Command>,
    status: Arc<Mutex<SyncStatus>>,
    last_error: Arc<Mutex<Option<AppError>>>,
) {
    let mut next_poll = Instant::now() + config.poll_interval;
    let mut debounce_deadline: Option<Instant> = None;
    let mut backoff_delay = config.backoff_base;
    let mut backoff_deadline: Option<Instant> = None;

    loop {
        let now = Instant::now();
        let mut wait = next_poll.saturating_duration_since(now);
        if let Some(dd) = debounce_deadline {
            wait = wait.min(dd.saturating_duration_since(now));
        }
        if let Some(bd) = backoff_deadline {
            wait = wait.min(bd.saturating_duration_since(now));
        }

        match receiver.recv_timeout(wait) {
            Ok(Command::Activity) => {
                debounce_deadline = Some(Instant::now() + config.debounce);
            }
            Ok(Command::Stop) | Err(RecvTimeoutError::Disconnected) => break,
            Err(RecvTimeoutError::Timeout) => {
                let now = Instant::now();

                // Precedence: a due backoff retry first (it represents
                // already-known-pending work), then a due debounce window,
                // then the periodic poll — checked in this order so at
                // most one sync cycle runs per wake, and so an activity
                // ping that arrives during an active backoff wait doesn't
                // also race a coincidentally-due poll tick into a second,
                // redundant cycle on the same wake.
                let due = if backoff_deadline.is_some_and(|bd| now >= bd) {
                    backoff_deadline = None;
                    true
                } else if debounce_deadline.is_some_and(|dd| now >= dd) {
                    debounce_deadline = None;
                    true
                } else if now >= next_poll {
                    next_poll = now + config.poll_interval;
                    true
                } else {
                    false
                };

                if due {
                    run_sync_cycle(
                        &config,
                        &deps,
                        &status,
                        &last_error,
                        &mut backoff_delay,
                        &mut backoff_deadline,
                    );
                }
            }
        }
    }
}

/// One push attempt, and everything `flow-sync-push.md` says should happen
/// based on its outcome. Never panics on a failed push/pull — every branch
/// records state via `status`/`last_error` for the caller to observe
/// instead ("log-free" per this ticket's instructions).
fn run_sync_cycle(
    config: &SyncConfig,
    deps: &SyncDeps,
    status: &Arc<Mutex<SyncStatus>>,
    last_error: &Arc<Mutex<Option<AppError>>>,
    backoff_delay: &mut Duration,
    backoff_deadline: &mut Option<Instant>,
) {
    set_status(status, SyncStatus::Syncing);
    let credentials = (deps.credentials)();

    match (deps.push)(
        &config.repo_path,
        &config.remote,
        &config.branch,
        credentials.as_ref(),
    ) {
        Ok(()) => {
            *backoff_delay = config.backoff_base;
            *backoff_deadline = None;
            set_last_error(last_error, None);
            set_status(status, SyncStatus::Idle);
        }
        Err(AppError::NetworkError(msg)) => {
            // Push Failure (Network Error) -> schedule a retry with
            // exponential backoff, without blocking this thread (the wait
            // happens back in `run`'s `recv_timeout`, which stays
            // responsive to `notify_activity`/`stop` the whole time).
            set_last_error(last_error, Some(AppError::NetworkError(msg)));
            set_status(status, SyncStatus::Retrying);
            *backoff_deadline = Some(Instant::now() + *backoff_delay);
            *backoff_delay = (*backoff_delay * 2).min(config.backoff_cap);
        }
        Err(AppError::AuthExpired) => {
            // Push Failure (expired/invalid credentials) -> deliberately
            // do NOT enter the backoff retry loop: retrying against the
            // same stale credentials is guaranteed to fail again, forever,
            // which would otherwise spin silently in the background
            // without ever giving the user a chance to re-authenticate.
            // Record the failure via status/last_error and let the next
            // natural trigger (an explicit `notify_activity()` — e.g.
            // after the caller refreshes credentials via `deps.credentials`
            // — or the periodic poll tick) attempt the push again.
            set_last_error(last_error, Some(AppError::AuthExpired));
            set_status(status, SyncStatus::Error);
            *backoff_delay = config.backoff_base;
            *backoff_deadline = None;
        }
        Err(AppError::GitConflict) => {
            // Push Failure (Conflict, non-fast-forward) -> fetch + merge
            // upstream (`pull`'s own contract: leaves raw conflict markers
            // in the working tree on a real overlap and returns
            // `AppError::GitConflict`, without aborting the merge), then
            // unconditionally fire the re-index and conflict-notification
            // hooks, per `flow-sync-push.md`'s Conflict branch.
            //
            // Note `pull` failing with `AuthExpired` falls into the
            // `Err(other)` arm below just like any other non-conflict
            // pull failure: no backoff is scheduled either way, since the
            // whole conflict branch unconditionally resets the backoff
            // state below regardless of `pull_result` — the same
            // "surface it and wait for the next natural trigger" behavior
            // the standalone push `AuthExpired` arm above documents.
            let pull_result = (deps.pull)(
                &config.repo_path,
                &config.remote,
                &config.branch,
                credentials.as_ref(),
            );

            let reindex_result = (deps.reindex)();
            let reindex_failed = reindex_result.is_err();
            if let Err(reindex_err) = reindex_result {
                set_last_error(last_error, Some(reindex_err));
            }
            (deps.on_conflict)(pull_result.clone());

            // A conflict is a distinct scenario from a network failure;
            // don't carry over a network backoff delay into it.
            *backoff_delay = config.backoff_base;
            *backoff_deadline = None;

            match pull_result {
                Ok(()) if !reindex_failed => {
                    set_last_error(last_error, None);
                    set_status(status, SyncStatus::Idle);
                }
                Ok(()) => {
                    // The merge itself completed cleanly, but the
                    // notes/notes_fts re-index that must follow it (per
                    // `flow-sync-push.md`) failed above: the on-disk index
                    // is now desynced from the freshly-merged notes.
                    // `last_error` already holds that reindex failure from
                    // above — leave it alone and report a real Error
                    // status rather than Idle, which would otherwise
                    // silently mask a failure with real user-visible
                    // consequences (stale/missing search results) behind
                    // an apparently-successful sync cycle.
                    set_status(status, SyncStatus::Error);
                }
                Err(AppError::GitConflict) => {
                    set_last_error(last_error, Some(AppError::GitConflict));
                    set_status(status, SyncStatus::Conflict);
                }
                Err(other) => {
                    set_last_error(last_error, Some(other));
                    set_status(status, SyncStatus::Error);
                }
            }
        }
        Err(other) => {
            // Unexpected error: no backoff loop (there is nothing
            // known-transient to retry against), just surface it and let
            // the next natural trigger (activity or the periodic poll)
            // try again.
            set_last_error(last_error, Some(other));
            set_status(status, SyncStatus::Error);
            *backoff_delay = config.backoff_base;
            *backoff_deadline = None;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{git, init_bare};
    use std::process::Command as StdCommand;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Mutex as StdMutex;
    use tempfile::tempdir;

    fn rev_parse(dir: &Path, rev: &str) -> String {
        let out = StdCommand::new("git")
            .args(["rev-parse", rev])
            .current_dir(dir)
            .output()
            .unwrap();
        String::from_utf8_lossy(&out.stdout).trim().to_string()
    }

    /// Polls `check` until it returns `true` or `timeout` elapses, sleeping
    /// briefly between attempts. Used instead of one fixed `sleep` so the
    /// tests below tolerate scheduling jitter without waiting the full
    /// worst-case timeout on every (usually much faster) run.
    fn wait_until(timeout: Duration, mut check: impl FnMut() -> bool) -> bool {
        let deadline = Instant::now() + timeout;
        loop {
            if check() {
                return true;
            }
            if Instant::now() >= deadline {
                return false;
            }
            thread::sleep(Duration::from_millis(5));
        }
    }

    /// A `poll_interval` long enough that no test below ever observes a
    /// second, periodic-tick-triggered sync cycle interfering with the
    /// debounce/backoff behavior actually under test.
    fn no_interference_poll_interval() -> Duration {
        Duration::from_secs(3600)
    }

    /// Gherkin: Given active local commits, When 5 seconds of inactivity
    /// pass, Then the background worker automatically pushes to the Remote
    /// Repo. (Debounce shortened to milliseconds so the test doesn't take
    /// 5 real seconds.)
    #[test]
    fn gherkin_pushes_after_debounce_inactivity_elapses() {
        let bare_parent = tempdir().unwrap();
        let bare = bare_parent.path().join("remote.git");
        init_bare(&bare);

        let work_parent = tempdir().unwrap();
        let work = work_parent.path().join("work");
        operations::clone_repo(&bare.to_string_lossy(), &work, None).unwrap();
        std::fs::write(work.join("note.md"), b"hello\n").unwrap();
        operations::commit_all(&work, "add note", "Test", "test@example.com").unwrap();
        let local_head = rev_parse(&work, "HEAD");

        let mut config = SyncConfig::new(work.clone(), "origin", "main");
        config.debounce = Duration::from_millis(80);
        config.poll_interval = no_interference_poll_interval();

        let scheduler = SyncScheduler::start(config, SyncDeps::default());
        scheduler.notify_activity();

        let pushed = wait_until(Duration::from_secs(3), || {
            rev_parse(&bare, "main") == local_head
        });
        scheduler.stop();

        assert!(
            pushed,
            "expected the debounced worker to push the local commit to the bare remote"
        );
    }

    /// Rapid successive `notify_activity()` calls within the debounce
    /// window must keep postponing the push (true debounce, not a fixed
    /// throttle) — and once the worker does fire, it must push exactly
    /// once, not once per activity ping.
    #[test]
    fn rapid_activity_debounces_to_a_single_push() {
        let bare_parent = tempdir().unwrap();
        let bare = bare_parent.path().join("remote.git");
        init_bare(&bare);

        let work_parent = tempdir().unwrap();
        let work = work_parent.path().join("work");
        operations::clone_repo(&bare.to_string_lossy(), &work, None).unwrap();
        std::fs::write(work.join("note.md"), b"hello\n").unwrap();
        operations::commit_all(&work, "add note", "Test", "test@example.com").unwrap();

        let push_calls = Arc::new(AtomicUsize::new(0));
        let push_calls_thread = Arc::clone(&push_calls);

        let mut config = SyncConfig::new(work.clone(), "origin", "main");
        config.debounce = Duration::from_millis(80);
        config.poll_interval = no_interference_poll_interval();

        let deps = SyncDeps {
            push: Box::new(move |repo_path, remote, branch, creds| {
                push_calls_thread.fetch_add(1, Ordering::SeqCst);
                operations::push(repo_path, remote, branch, creds)
            }),
            ..SyncDeps::default()
        };

        let scheduler = SyncScheduler::start(config, deps);

        // Four activity pings, each well inside the 80ms debounce window of
        // the previous one, so the deadline keeps getting pushed out.
        for _ in 0..4 {
            scheduler.notify_activity();
            thread::sleep(Duration::from_millis(20));
        }

        // Give the final debounce window (from the last ping) time to
        // elapse and the push to run, then a further grace period during
        // which a bug that pushed once per ping would have already shown
        // up as call_count > 1.
        wait_until(Duration::from_secs(2), || {
            push_calls.load(Ordering::SeqCst) >= 1
        });
        thread::sleep(Duration::from_millis(150));
        scheduler.stop();

        assert_eq!(
            push_calls.load(Ordering::SeqCst),
            1,
            "rapid activity within the debounce window must collapse to exactly one push"
        );
    }

    /// A rejected (non-fast-forward) push must trigger a follow-up pull;
    /// when that pull's merge genuinely overlaps (real conflict markers,
    /// same shape as `git::operations`'s own conflict test), both the
    /// re-index hook and the conflict-notification hook must fire, and the
    /// working tree must actually contain the raw markers afterward.
    #[test]
    fn rejected_push_triggers_pull_reindex_and_conflict_hook_on_a_real_conflict() {
        let bare_parent = tempdir().unwrap();
        let bare = bare_parent.path().join("remote.git");
        init_bare(&bare);

        // Seed a common ancestor both clones diverge from.
        let seed_parent = tempdir().unwrap();
        let seed = seed_parent.path().join("seed");
        operations::clone_repo(&bare.to_string_lossy(), &seed, None).unwrap();
        std::fs::write(seed.join("shared.md"), b"base\n").unwrap();
        operations::commit_all(&seed, "seed", "Seed", "seed@example.com").unwrap();
        operations::push(&seed, "origin", "main", None).unwrap();

        // Clone B (the one the scheduler will run against) *before* A
        // pushes, so both diverge from the same ancestor.
        let work_parent = tempdir().unwrap();
        let work = work_parent.path().join("b");
        operations::clone_repo(&bare.to_string_lossy(), &work, None).unwrap();

        // Clone A diverges and pushes upstream first.
        let a_parent = tempdir().unwrap();
        let a = a_parent.path().join("a");
        operations::clone_repo(&bare.to_string_lossy(), &a, None).unwrap();
        std::fs::write(a.join("shared.md"), b"from a\n").unwrap();
        operations::commit_all(&a, "a changes shared.md", "A", "a@example.com").unwrap();
        operations::push(&a, "origin", "main", None).unwrap();

        // B, unaware of A's push, diverges independently and has an
        // unpushed local commit — "active local commits" from the Gherkin.
        std::fs::write(work.join("shared.md"), b"from b\n").unwrap();
        operations::commit_all(&work, "b changes shared.md", "B", "b@example.com").unwrap();

        let reindex_calls = Arc::new(AtomicUsize::new(0));
        let reindex_calls_thread = Arc::clone(&reindex_calls);
        let conflict_results: Arc<StdMutex<Vec<Result<(), AppError>>>> =
            Arc::new(StdMutex::new(Vec::new()));
        let conflict_results_thread = Arc::clone(&conflict_results);

        let mut config = SyncConfig::new(work.clone(), "origin", "main");
        config.debounce = Duration::from_millis(50);
        config.poll_interval = no_interference_poll_interval();

        let deps = SyncDeps {
            reindex: Box::new(move || {
                reindex_calls_thread.fetch_add(1, Ordering::SeqCst);
                Ok(())
            }),
            on_conflict: Box::new(move |result| {
                conflict_results_thread.lock().unwrap().push(result);
            }),
            ..SyncDeps::default()
        };

        let scheduler = SyncScheduler::start(config, deps);
        scheduler.notify_activity();

        let settled = wait_until(Duration::from_secs(3), || {
            reindex_calls.load(Ordering::SeqCst) >= 1
        });
        scheduler.stop();

        assert!(settled, "expected the re-index hook to fire");
        assert_eq!(reindex_calls.load(Ordering::SeqCst), 1);

        let results = conflict_results.lock().unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0], Err(AppError::GitConflict));

        let contents = std::fs::read_to_string(work.join("shared.md")).unwrap();
        assert!(
            contents.contains("<<<<<<<")
                && contents.contains("=======")
                && contents.contains(">>>>>>>"),
            "expected raw conflict markers to survive in the working tree, got: {contents}"
        );
    }

    /// A push that always fails with `AppError::NetworkError` must be
    /// retried with growing delays between attempts (exponential backoff),
    /// rather than either giving up or retrying immediately in a hot loop.
    #[test]
    fn network_failure_retries_with_growing_backoff_delays() {
        let work_parent = tempdir().unwrap();
        let work = work_parent.path().join("work");
        std::fs::create_dir_all(&work).unwrap();
        git(&work, &["init", "--initial-branch=main", "-q"]);
        git(&work, &["config", "user.name", "Test"]);
        git(&work, &["config", "user.email", "test@example.com"]);
        std::fs::write(work.join("note.md"), b"hello\n").unwrap();
        operations::commit_all(&work, "add note", "Test", "test@example.com").unwrap();

        let call_times: Arc<StdMutex<Vec<Instant>>> = Arc::new(StdMutex::new(Vec::new()));
        let call_times_thread = Arc::clone(&call_times);

        let mut config = SyncConfig::new(work.clone(), "origin", "main");
        config.debounce = Duration::from_millis(20);
        config.poll_interval = no_interference_poll_interval();
        config.backoff_base = Duration::from_millis(40);
        config.backoff_cap = Duration::from_secs(2);

        let deps = SyncDeps {
            push: Box::new(move |_, _, _, _| {
                call_times_thread.lock().unwrap().push(Instant::now());
                Err(AppError::NetworkError("test induced failure".to_string()))
            }),
            ..SyncDeps::default()
        };

        let scheduler = SyncScheduler::start(config, deps);
        scheduler.notify_activity();

        wait_until(Duration::from_millis(600), || {
            call_times.lock().unwrap().len() >= 4
        });
        scheduler.stop();

        let times = call_times.lock().unwrap().clone();
        assert!(
            times.len() >= 3,
            "expected at least 3 retry attempts, got {}",
            times.len()
        );
        assert_eq!(
            scheduler.status(),
            SyncStatus::Retrying,
            "a persistently failing push must leave the scheduler in Retrying, not silently Idle"
        );
        assert!(matches!(
            scheduler.last_error(),
            Some(AppError::NetworkError(_))
        ));

        let deltas: Vec<Duration> = times.windows(2).map(|w| w[1] - w[0]).collect();
        // Generous tolerance throughout: real thread scheduling jitter
        // means exact doubling isn't guaranteed, but a genuinely
        // exponential backoff should still show a clear upward trend
        // rather than roughly-constant or shrinking gaps. Compare the
        // first observed gap against the last: it must have grown
        // substantially.
        let first = deltas.first().unwrap();
        let last = deltas.last().unwrap();
        assert!(
            *last > *first,
            "expected backoff delays to grow, first={first:?} last={last:?} all={deltas:?}"
        );
    }

    /// `stop()` must interrupt an in-progress backoff wait promptly rather
    /// than block until that wait's (potentially long) deadline elapses.
    #[test]
    fn stop_joins_promptly_even_while_a_long_backoff_is_pending() {
        let work_parent = tempdir().unwrap();
        let work = work_parent.path().join("work");
        std::fs::create_dir_all(&work).unwrap();
        git(&work, &["init", "--initial-branch=main", "-q"]);
        git(&work, &["config", "user.name", "Test"]);
        git(&work, &["config", "user.email", "test@example.com"]);
        std::fs::write(work.join("note.md"), b"hello\n").unwrap();
        operations::commit_all(&work, "add note", "Test", "test@example.com").unwrap();

        let mut config = SyncConfig::new(work.clone(), "origin", "main");
        config.debounce = Duration::from_millis(10);
        config.poll_interval = no_interference_poll_interval();
        // A deliberately long backoff so a non-interruptible implementation
        // would make this test obviously fail (or hang for seconds).
        config.backoff_base = Duration::from_secs(5);
        config.backoff_cap = Duration::from_secs(5);

        let call_count = Arc::new(AtomicUsize::new(0));
        let call_count_thread = Arc::clone(&call_count);
        let deps = SyncDeps {
            push: Box::new(move |_, _, _, _| {
                call_count_thread.fetch_add(1, Ordering::SeqCst);
                Err(AppError::NetworkError("test induced failure".to_string()))
            }),
            ..SyncDeps::default()
        };

        let scheduler = SyncScheduler::start(config, deps);
        scheduler.notify_activity();

        // Give the first failure (and entry into the 5s backoff wait) time
        // to happen.
        wait_until(Duration::from_secs(1), || {
            call_count.load(Ordering::SeqCst) >= 1
        });

        let before_stop = Instant::now();
        scheduler.stop();
        let stop_elapsed = before_stop.elapsed();

        assert!(
            stop_elapsed < Duration::from_millis(500),
            "stop() should interrupt a pending 5s backoff wait almost immediately, took {stop_elapsed:?}"
        );
    }

    /// A push that fails with `AppError::AuthExpired` must NOT be retried
    /// with backoff — retrying against the same stale/invalid credentials
    /// would just fail again, forever, silently, in the background. The
    /// scheduler must instead surface the failure via `status()`/
    /// `last_error()` and make exactly one attempt until the next explicit
    /// trigger (`notify_activity()` or a periodic poll tick).
    #[test]
    fn auth_expired_push_failure_does_not_backoff_retry() {
        let work_parent = tempdir().unwrap();
        let work = work_parent.path().join("work");
        std::fs::create_dir_all(&work).unwrap();
        git(&work, &["init", "--initial-branch=main", "-q"]);
        git(&work, &["config", "user.name", "Test"]);
        git(&work, &["config", "user.email", "test@example.com"]);
        std::fs::write(work.join("note.md"), b"hello\n").unwrap();
        operations::commit_all(&work, "add note", "Test", "test@example.com").unwrap();

        let push_calls = Arc::new(AtomicUsize::new(0));
        let push_calls_thread = Arc::clone(&push_calls);

        let mut config = SyncConfig::new(work.clone(), "origin", "main");
        config.debounce = Duration::from_millis(20);
        config.poll_interval = no_interference_poll_interval();
        // Deliberately short: if a bug mistakenly schedules a backoff
        // retry anyway, it would fire well within this test's wait window
        // below and be caught by the final call-count assertion.
        config.backoff_base = Duration::from_millis(30);
        config.backoff_cap = Duration::from_millis(30);

        let deps = SyncDeps {
            push: Box::new(move |_, _, _, _| {
                push_calls_thread.fetch_add(1, Ordering::SeqCst);
                Err(AppError::AuthExpired)
            }),
            ..SyncDeps::default()
        };

        let scheduler = SyncScheduler::start(config, deps);
        scheduler.notify_activity();

        let attempted = wait_until(Duration::from_secs(1), || {
            push_calls.load(Ordering::SeqCst) >= 1
        });
        assert!(attempted, "expected the push to be attempted at least once");

        // A generous window well past the (short) configured backoff delay:
        // a correct implementation schedules no retry at all, so the call
        // count must stay at exactly 1 for the whole window.
        thread::sleep(Duration::from_millis(300));
        scheduler.stop();

        assert_eq!(
            push_calls.load(Ordering::SeqCst),
            1,
            "AuthExpired must not trigger a backoff retry"
        );
        assert_eq!(scheduler.status(), SyncStatus::Error);
        assert_eq!(scheduler.last_error(), Some(AppError::AuthExpired));
    }

    /// If the re-index hook fails, that failure must not be silently
    /// swallowed just because the follow-up pull happened to auto-merge
    /// cleanly (no real conflict markers) — `status()`/`last_error()` must
    /// still reflect the reindex failure rather than reporting `Idle`,
    /// which would otherwise leave the on-disk index desynced from the
    /// merged notes with no signal to the caller at all.
    #[test]
    fn reindex_failure_on_a_clean_auto_merge_is_not_masked() {
        let bare_parent = tempdir().unwrap();
        let bare = bare_parent.path().join("remote.git");
        init_bare(&bare);

        // Seed a common ancestor both clones diverge from.
        let seed_parent = tempdir().unwrap();
        let seed = seed_parent.path().join("seed");
        operations::clone_repo(&bare.to_string_lossy(), &seed, None).unwrap();
        std::fs::write(seed.join("shared.md"), b"base\n").unwrap();
        operations::commit_all(&seed, "seed", "Seed", "seed@example.com").unwrap();
        operations::push(&seed, "origin", "main", None).unwrap();

        // Clone B (the one the scheduler will run against) *before* A
        // pushes, so both diverge from the same ancestor.
        let work_parent = tempdir().unwrap();
        let work = work_parent.path().join("b");
        operations::clone_repo(&bare.to_string_lossy(), &work, None).unwrap();

        // Clone A diverges (a *different* new file, so the eventual merge
        // has no real content overlap) and pushes upstream first.
        let a_parent = tempdir().unwrap();
        let a = a_parent.path().join("a");
        operations::clone_repo(&bare.to_string_lossy(), &a, None).unwrap();
        std::fs::write(a.join("from_a.md"), b"from a\n").unwrap();
        operations::commit_all(&a, "a adds a new file", "A", "a@example.com").unwrap();
        operations::push(&a, "origin", "main", None).unwrap();

        // B, unaware of A's push, diverges independently with an unrelated
        // new file and has an unpushed local commit.
        std::fs::write(work.join("from_b.md"), b"from b\n").unwrap();
        operations::commit_all(&work, "b adds a different new file", "B", "b@example.com").unwrap();

        let mut config = SyncConfig::new(work.clone(), "origin", "main");
        config.debounce = Duration::from_millis(50);
        config.poll_interval = no_interference_poll_interval();

        let deps = SyncDeps {
            reindex: Box::new(|| {
                Err(AppError::DatabaseError(
                    "notes_fts reindex failed".to_string(),
                ))
            }),
            ..SyncDeps::default()
        };

        let scheduler = SyncScheduler::start(config, deps);
        scheduler.notify_activity();

        let settled = wait_until(Duration::from_secs(3), || {
            !matches!(scheduler.status(), SyncStatus::Idle | SyncStatus::Syncing)
        });
        scheduler.stop();

        assert!(
            settled,
            "expected the scheduler to leave Idle/Syncing once the cycle finished"
        );
        assert_eq!(
            scheduler.status(),
            SyncStatus::Error,
            "a failed reindex on an otherwise-clean auto-merge must not report Idle"
        );
        assert_eq!(
            scheduler.last_error(),
            Some(AppError::DatabaseError(
                "notes_fts reindex failed".to_string()
            )),
            "the reindex failure must not be masked by the clean merge result"
        );
    }
}
