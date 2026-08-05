//! Local Workspace bootstrap (ADR-005, `flow-workspace-bootstrap.md`).
//!
//! Implements the domain logic behind `open_or_create_local_workspace` and
//! `open_workspace`, which converge on identical post-conditions per
//! `flow-workspace-bootstrap.md`'s "Three bootstrap paths, one
//! post-condition": the Workspace directory exists, a Git repository is
//! present (initialized if absent, adopted unchanged if present — ADR-005
//! decision 8), and a `workspaces` row exists with `provider = 'local'` and
//! `remote_url = NULL`.
//!
//! Root key generation and opening the encrypted index are the caller's
//! responsibility, via `db::connection` — this module never touches OS
//! Keychain, the network, or authentication state directly. That is not an
//! oversight: `WSPC-D004`'s STOP conditions forbid all three, and
//! `flow-workspace-bootstrap.md` contains no such step.
//!
//! `flow-workspace-bootstrap.md` names a fourth post-condition alongside
//! those three — "bundle indexed" — and [`converge`] establishes it too, in
//! `index::scan`'s two phases: `scan_bundle` off the connection, then
//! `write_scanned_bundle` under it. `WSPC-D004` deferred that to `WSPC-D005`
//! because no rebuild existed yet; one does, and leaving the call unwired made
//! the post-condition false on every path *and* left `WSPC-D006`'s rename
//! rewriting no Links at all in a bundle that had never been scanned (it
//! seeds its affected set from the `links` table). See [`converge`] for why
//! it runs on the reuse branch as well, why it is synchronous, and why nothing
//! here holds the connection across the filesystem.
//!
//! `#[frb]` async wrappers live in `api::ffi_api`, matching the pattern
//! `draft.rs` already establishes for `NoteState`/`NoteMetadata`: this module
//! owns the domain logic and is exercised directly in tests against an
//! injected `Connection`, so hermetic tests never touch the process-wide
//! `db::connection` singleton or the OS Keychain — only a real, on-disk
//! SQLCipher file and a real `gix` repository, both in a tempdir.

use std::path::{Path, PathBuf};

use flutter_rust_bridge::frb;
use rusqlite::{Connection, OptionalExtension};

use crate::error::AppError;

/// A Workspace: the bundle on disk plus its `workspaces` row
/// (`contracts/ffi_api.rs`).
#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceInfo {
    pub id: String,
    pub name: String,
    /// `"local"` until the user connects a Remote (CAP-SYNC-01), then the
    /// provider name. Matches `workspaces.provider` in `schema.sql`.
    pub provider: String,
    pub remote_url: Option<String>,
    /// Absolute path to the bundle root on disk.
    pub local_path: String,
}

/// Resolves the default local Workspace directory (`guidelines.md`
/// "Workspace location"): `$XDG_DATA_HOME/burlmd/workspace`, falling back to
/// `~/.local/share/burlmd/workspace` (`~/Library/Application
/// Support/burlmd/workspace` on macOS) when `XDG_DATA_HOME` is unset. A
/// sibling of the default index path resolved by
/// `db::connection::default_db_path`, under the same shared `burlmd/`
/// parent — the index is derived state and lives outside the bundle it
/// indexes, never within it.
pub fn default_workspace_dir() -> Result<PathBuf, AppError> {
    Ok(crate::db::connection::xdg_data_home()?
        .join("burlmd")
        .join("workspace"))
}

/// Where this bootstrap's **SQL** runs, and — far more to the point — where it
/// does *not*.
///
/// [`converge`] performs three O(bundle) filesystem phases (a repository init,
/// the scratch sweep, and a full read-and-derive scan of every Note) around a
/// handful of statements. Taking a `&Connection` made all of it run inside the
/// caller's `with_connection` closure, holding the process-wide mutex — the one
/// a keystroke's tier 1 draft write waits on — across the lot. This handle is
/// what lets the filesystem phases run *outside* the mutex while the statements
/// still reach the right connection, without the hermetic tests losing their
/// injected one.
///
/// The two variants mirror `workspace::persist::Workspace`'s `DbHandle`
/// exactly, including that the injected arm enters the connection scope: a test
/// connection contends with nothing, but every hermetic test in this crate runs
/// against one, and a rule enforced only on the arm no test takes is not
/// enforced.
pub(crate) enum IndexHandle<'a> {
    /// `db::connection`'s process-wide `Mutex<Connection>`.
    Process,
    /// An injected connection — hermetic tests only, which is why this is
    /// `dead_code`-exempt rather than `#[cfg(test)]`: keeping the variant
    /// compiled in both profiles means [`IndexHandle::with`] has one shape to
    /// read rather than two.
    #[cfg_attr(not(test), allow(dead_code))]
    Injected(&'a Connection),
}

impl IndexHandle<'_> {
    fn with<T>(&self, f: impl FnOnce(&Connection) -> Result<T, AppError>) -> Result<T, AppError> {
        match self {
            IndexHandle::Process => crate::db::connection::with_connection(f),
            IndexHandle::Injected(conn) => {
                let _scope = crate::db::connection::ConnectionScope::enter();
                f(conn)
            }
        }
    }
}

/// Opens the local Workspace at `path` (or the default location from
/// [`default_workspace_dir`] when `path` is `None`), creating and
/// initializing it if absent (ADR-005 decision 1). The domain entry point
/// behind `api::ffi_api::open_or_create_local_workspace`. Unlike
/// [`open_workspace`], this is the one entry point that creates `dir`
/// when it doesn't exist yet.
pub(crate) fn open_or_create_local_workspace(
    path: Option<String>,
) -> Result<WorkspaceInfo, AppError> {
    open_or_create_local_workspace_with(&IndexHandle::Process, path)
}

/// [`open_or_create_local_workspace`] against an injected connection, for
/// hermetic tests.
#[cfg_attr(not(test), allow(dead_code))]
pub(crate) fn open_or_create_local_workspace_impl(
    conn: &Connection,
    path: Option<String>,
) -> Result<WorkspaceInfo, AppError> {
    open_or_create_local_workspace_with(&IndexHandle::Injected(conn), path)
}

fn open_or_create_local_workspace_with(
    index: &IndexHandle,
    path: Option<String>,
) -> Result<WorkspaceInfo, AppError> {
    let dir = match path {
        Some(p) => PathBuf::from(p),
        None => default_workspace_dir()?,
    };
    std::fs::create_dir_all(&dir).map_err(|e| AppError::IoError(e.to_string()))?;
    let canonical = canonicalize_workspace_dir(&dir)?;
    converge(index, &canonical)
}

/// Opens an existing Workspace directory the application did not create,
/// including one populated by another tool (CAP-WS-05). The domain entry
/// point behind `api::ffi_api::open_workspace`.
///
/// Unlike [`open_or_create_local_workspace`], this does **not** create
/// `dir` — the ticket description is explicit that `open_workspace` "does
/// not create the directory" (only `open_or_create_local_workspace` does),
/// and silently creating an empty directory at a caller-supplied path that
/// doesn't exist (a typo, an unmounted volume, a stale recent-Workspace
/// entry) would shadow the real bundle with a fresh empty one instead of
/// reporting the mistake (WSPC-D004 review finding #1).
pub(crate) fn open_workspace(path: String) -> Result<WorkspaceInfo, AppError> {
    open_workspace_with(&IndexHandle::Process, path)
}

/// [`open_workspace`] against an injected connection, for hermetic tests.
#[cfg_attr(not(test), allow(dead_code))]
pub(crate) fn open_workspace_impl(
    conn: &Connection,
    path: String,
) -> Result<WorkspaceInfo, AppError> {
    open_workspace_with(&IndexHandle::Injected(conn), path)
}

fn open_workspace_with(index: &IndexHandle, path: String) -> Result<WorkspaceInfo, AppError> {
    let dir = PathBuf::from(&path);
    if !dir.is_dir() {
        return Err(AppError::NotFound(format!(
            "workspace directory does not exist: {path}"
        )));
    }
    let canonical = canonicalize_workspace_dir(&dir)?;
    converge(index, &canonical)
}

/// Resolves `dir` to its canonical, absolute form (symlinks followed,
/// `.`/`..` and trailing slashes normalized). Both entry points above call
/// this *after* confirming `dir` exists (creating it first, in
/// [`open_or_create_local_workspace_impl`]'s case) and *before* `converge`
/// reads or writes `workspaces.local_path` — that column has no `UNIQUE`
/// constraint, so [`converge`]'s reuse-by-`local_path` lookup is only
/// correct if every caller agrees on one spelling of the same directory.
/// Without this, `/x/ws`, `/x/ws/`, a relative spelling, and a
/// symlink-indirected path would each mint a separate `workspaces` row for
/// what is really one bundle, splitting its index across two id spaces —
/// which ADR-005 decision 7 requires not happen (WSPC-D004 review
/// finding #2).
///
/// # A root that is not valid UTF-8 is refused
///
/// This is the same rule `index::scan::walk_bundle` applies to an *entry* name,
/// applied to the bundle root, and for the same reason: on Unix a path is
/// bytes, `to_string_lossy` does not fail — it substitutes `U+FFFD` — and
/// [`converge`] stores what it returns in `workspaces.local_path`. A mangled
/// value there names no directory on this filesystem, and that column is the
/// root every later path resolution in this application is joined onto, so one
/// lossy conversion at bootstrap poisons every Note path derived from it for
/// the life of the row.
///
/// It is also **strictly worse than the entry-name case, because it cannot
/// self-repair.** A skipped entry is indexed by the next scan once its name is
/// valid; a mangled root is matched by `converge`'s reuse-by-`local_path`
/// lookup on the next open — the same directory canonicalizes to the same
/// bytes and mangles to the same string — so the broken row is found, reused,
/// and never rewritten. There is no later moment at which this gets better,
/// which is why it is refused at the one moment it can be.
///
/// The path arrives as a `String` and is therefore valid UTF-8 as supplied; the
/// case this catches is what `canonicalize` **resolves it to**, which a symlink
/// or an `XDG_DATA_HOME` full of arbitrary bytes chooses rather than the
/// caller. The bytes on disk are untouched — nothing is renamed, nothing is
/// created — and a user who moves the bundle somewhere representable opens it
/// normally.
fn canonicalize_workspace_dir(dir: &Path) -> Result<PathBuf, AppError> {
    let canonical = std::fs::canonicalize(dir)
        .map_err(|e| AppError::IoError(format!("resolve workspace path {}: {e}", dir.display())))?;
    if canonical.to_str().is_none() {
        return Err(AppError::IoError(format!(
            "the workspace path {} resolves to {}, which is not valid UTF-8: recording it \
             would store a mangled local_path that names no directory and that every later \
             path resolution is joined onto. Move the bundle to a path this application can \
             represent.",
            dir.display(),
            canonical.display()
        )));
    }
    Ok(canonical)
}

/// The convergent bootstrap logic shared by both entry points
/// (`flow-workspace-bootstrap.md`, ADR-005 decision 8): initializes a Git
/// repository in `dir` or adopts existing history unchanged, and writes (or
/// reuses) the `workspaces` row, then indexes the bundle. `dir` must already
/// exist and be canonicalized — both callers above guarantee this before
/// calling in.
///
/// **No Note under `dir` is written or otherwise modified.** Notes are now
/// *read*, because indexing them is what the fourth post-condition means, but
/// the rebuild derives rows from bytes it never writes back. The side effects
/// on a foreign directory are exactly three, and none of them is content:
/// `.git/`, a `.gitignore` extended with burlmd's own scratch patterns
/// (`git::operations::init_repo`) plus the single commit that records it, and
/// the removal of any `.burlmd-trash.*` or `.{stem}.{pid}.{n}.tmp` file a
/// previous kill left behind ([`sweep_scratch_files`]) — which are burlmd's,
/// not the bundle's. That commit is made only on the open that actually writes
/// the file, so a repeat open of an already-converged bundle adds nothing to
/// history.
///
/// # Nothing here holds the connection across the filesystem
///
/// Three of the four phases below are O(bundle) file I/O: the repository init,
/// the scratch sweep (which recurses the whole tree), and the full scan (which
/// reads and parses every Note in the Workspace). All three used to run inside
/// the caller's `with_connection` closure, because this function took a
/// `&Connection` and the caller was obliged to hold one to call it — so opening
/// a Workspace held the process-wide connection mutex for the length of a whole
/// bundle walk, which is exactly what `SPK-WSPC-D001` §6.2.7 forbids and what a
/// keystroke's own tier 1 draft write would then have queued behind.
///
/// So the connection is reached through an [`IndexHandle`] and acquired twice,
/// briefly, for statements only. Two acquisitions rather than one is the
/// accepted cost: nothing between them can invalidate the `workspaces` row this
/// function just established, and bootstrap is a single-threaded moment at
/// application start.
///
/// # Everything after the row is resolved runs under the lifecycle lock
///
/// The `workspaces` row is resolved first, with nothing held, precisely so that
/// its id can key `workspace::persist::with_lifecycle_lock_id` around the rest.
/// Three things needed that lock, and none of them is hypothetical: FRB 2.12's
/// default handler dispatches every `#[frb] async fn` on its own thread, and
/// `open_workspace` is one of them, so a bootstrap genuinely runs alongside
/// whatever the previously-open Workspace is still doing.
///
/// - **The scan and the write are one unit.** This is the same defect the
///   `reindex_workspace` fix closed (`api::ffi_api::reindex_workspace`), one
///   function over: `scan_bundle` walks the whole bundle off the connection and
///   `write_scanned_bundle` replaces the Workspace's rows from that snapshot, so
///   a `rename_note` completing in the O(bundle) window between them has already
///   moved the file and rewritten its rows — and the write phase then reinstates
///   the old concept id, drops the new one, and leaves the index naming a file
///   that no longer exists.
/// - **The sweep must not race a deletion's rollback.** See
///   [`sweep_scratch_files`]: a `.burlmd-trash.*` entry is a live rollback
///   record for an in-flight `delete_note`, not only debris a kill left behind.
/// - **The `.gitignore` commit is a commit**, and commits into the same
///   repository serialize with the lifecycle operations that make them, which is
///   what keeps `commit_paths`'s `HEAD` compare-and-swap from having to refuse
///   this one.
///
/// The repository init and the directory canonicalization stay outside, where
/// they cost nothing to leave: neither reads nor writes anything a lifecycle
/// operation touches, and a repository has to exist before there is anything to
/// commit into.
///
/// The order holds. This is the topmost of `workspace::persist`'s four locks,
/// and the only lock taken *beneath* it here is the connection, the bottom one.
/// The row resolution above takes and releases the connection before this is
/// acquired, so nothing lower is ever held at the moment it is taken.
fn converge(index: &IndexHandle, dir: &Path) -> Result<WorkspaceInfo, AppError> {
    let ignore_written = crate::git::operations::init_repo(dir)?;

    let local_path = dir.to_string_lossy().to_string();
    let info = index.with(|conn| resolve_workspace_row(conn, dir, local_path))?;

    crate::workspace::persist::with_lifecycle_lock_id(&info.id, || {
        // The one write bootstrap makes into the user's bundle, so it is also
        // the one bootstrap has to record. `init_repo` creates or extends
        // `.gitignore` and commits nothing, which left the file untracked (on a
        // fresh bundle) or modified (on an adopted one) in every `git status`
        // the user ever ran against their own bundle — a worktree burlmd
        // dirtied on their behalf and never cleaned up. Worse, it was resolved
        // at a time nobody chose: the next tier 3 close would not sweep it
        // (that pathspec is one Note), but the next `commit_all` from a sync
        // would, filing burlmd's housekeeping inside an unrelated commit.
        //
        // Committed **only when the file actually changed**, which is what
        // keeps a repeat open from writing a second, empty-tree-identical
        // commit — and what makes `open_workspace`'s "existing history is
        // adopted unchanged" promise survive this: an adopted bundle that
        // already carries the patterns is touched neither on disk nor in
        // history. A foreign bundle that does not carry them gains exactly one
        // commit, which is the trade this makes knowingly — one recorded
        // housekeeping commit at a moment the user chose (they just opened the
        // bundle) against a worktree burlmd dirtied and left.
        //
        // **The commit is not narrowed to a clean `.gitignore`.** `commit_paths`
        // commits what is on disk at the named path, so if the user had their
        // own uncommitted `.gitignore` edits when the bundle was opened, this
        // records those edits alongside burlmd's appended patterns, in a commit
        // whose message describes only the latter. Declining when the file
        // differs from `HEAD` was considered and not taken: it would leave the
        // scratch patterns permanently uncommitted for exactly the users who
        // keep a working `.gitignore` in flight, so the file stays dirty in
        // every `git status` — the condition this commit exists to end — and is
        // then swept into whatever commits next anyway, which is the worse of
        // the two outcomes and the one the user did not see coming. What
        // actually happens here is bounded and visible: one commit, one path,
        // the user's own line-for-line content, made at a moment they chose,
        // and `git reset HEAD^` puts it back.
        //
        // Propagated rather than bound and dropped like the scratch sweep
        // below, and the asymmetry is deliberate: the sweep is best-effort
        // tidying with `.gitignore` itself as its backstop, whereas a
        // `commit_paths` that fails here means the repository cannot be
        // committed into at all — which every tier 3 close in the session is
        // about to discover the hard way, one Note's worth of work later.
        // Reporting it at open is the earlier and cheaper of the two moments.
        if ignore_written {
            crate::git::operations::commit_paths(
                dir,
                "Ignore burlmd scratch files\n\n\
                 .burlmd-trash.* and .*.tmp are this application's own scratch files: a deleted \
                 Note's full content and a Note mid-write, both plaintext, both left behind only \
                 by a kill. Ignoring them keeps a whole-worktree commit from publishing either.\n",
                &[".gitignore".to_string()],
            )?;
        }
        // Bound and dropped rather than propagated: a scratch entry that could
        // not be removed is untidy, is already `.gitignore`d, and will be swept
        // again at the next open — none of which is a reason to refuse the user
        // their Notes. `ScratchSweep` exists so that "how much was left behind"
        // is a value this call can be tested on rather than an error nobody
        // sees.
        let _swept = sweep_scratch_files(dir);

        // The read half of the fourth post-condition, taken with **no
        // connection held** and after the sweep, so the rows derived below
        // describe the bundle as it now is.
        let scanned = crate::index::scan::scan_bundle(dir)?;

        // The write half of the fourth post-condition: "bundle indexed". Runs
        // whether or not the row above was reused — a reused row says nothing
        // about whether the files under it still match the index, since another
        // tool (or another checkout) may have moved underneath it while the
        // application was not running.
        //
        // Not merely a missing post-condition, either. `WSPC-D006`'s rename
        // seeds its affected set from the `links` table, so in a bundle that was
        // never indexed a rename finds no inbound edges and rewrites nothing,
        // leaving every Link in the Workspace pointing at the concept the rename
        // removed — `architecture/risks.md` risk 8, reached by simply never
        // having scanned.
        //
        // Synchronous, deliberately. `flow-workspace-bootstrap.md` describes
        // indexing a large Workspace in the background with the tree filling in
        // as it goes; that is a recorded latent gap and building it here would
        // be a scope this bootstrap does not own. On an empty new bundle — the
        // ordinary first-run path — the scan above walked nothing and this costs
        // one transaction.
        index.with(|conn| crate::index::scan::write_scanned_bundle(conn, &info.id, &scanned))
    })?;

    Ok(info)
}

/// Reads the `workspaces` row for `local_path`, or writes one when there is
/// none. SQL only — the phase [`converge`] runs with the connection held, and
/// the reason it runs *before* the lifecycle lock rather than under it: the id
/// it resolves is what keys that lock.
fn resolve_workspace_row(
    conn: &Connection,
    dir: &Path,
    local_path: String,
) -> Result<WorkspaceInfo, AppError> {
    let existing = conn
        .query_row(
            "SELECT id, name, provider, remote_url FROM workspaces WHERE local_path = ?1",
            [&local_path],
            |row| {
                Ok(WorkspaceInfo {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    provider: row.get(2)?,
                    remote_url: row.get(3)?,
                    local_path: local_path.clone(),
                })
            },
        )
        .optional()?;

    match existing {
        // Reused, not recreated: no second row and — since root key generation
        // happens once per process, in `db::connection`'s own singleton init,
        // entirely upstream of this function — no second key either.
        Some(info) => Ok(info),
        None => {
            let id = mint_workspace_id()?;
            let name = workspace_name(dir);
            conn.execute(
                "INSERT INTO workspaces (id, name, provider, remote_url, local_path) \
                 VALUES (?1, ?2, 'local', NULL, ?3)",
                rusqlite::params![id, name, local_path],
            )?;
            Ok(WorkspaceInfo {
                id,
                name,
                provider: "local".to_string(),
                remote_url: None,
                local_path,
            })
        }
    }
}

/// Removes every `.burlmd-trash.*` entry and every `.{stem}.{pid}.{n}.tmp` file
/// left anywhere under `dir`.
///
/// **Only burlmd's own two shapes**, judged by
/// [`super::is_burlmd_scratch_name`] rather than by the broader
/// [`super::SCRATCH_IGNORE_PATTERNS`]. The distinction is not cosmetic: this
/// runs on every open, including the open of a directory another tool populated
/// (CAP-WS-05), and it removes what it matches — recursively, for a directory.
/// A predicate reading "any dot-prefixed `.tmp`" therefore deleted another
/// tool's `.foo.tmp`, and every file under its `.bar.tmp/`, as a side effect of
/// adopting the bundle. [`converge`] states that what this sweep removes is
/// "burlmd's, not the bundle's"; the narrow predicate is what makes that
/// sentence true. The `.gitignore` patterns stay broad, because ignoring a file
/// burlmd did not write costs nothing.
///
/// **Unconditionally, with no age threshold**, and that is the safe reading
/// rather than the lazy one: both families are created and removed inside a
/// single operation that holds a lock for its whole length, so neither is ever
/// legitimate at the moment a Workspace is being opened. One that is still
/// here got here because a `SIGKILL`, a crash or a power loss stopped the
/// cleanup — `Drop` does not run for any of them — and what it holds is
/// plaintext: a trash entry is the entire content of a Note that was deleted,
/// a temporary file is a Note as it was mid-write. `.gitignore` (written by
/// `git::operations::init_repo`) stops the next whole-worktree commit from
/// publishing them; this is what stops them sitting in the bundle at all.
///
/// The one case an age threshold would narrow is a re-open of the Workspace
/// that is *already* active, racing an idle write inside its own
/// `atomic_write`. It is stated rather than defended against because the
/// outcome is benign in the direction that matters: the sweep removes the
/// temporary file, the write's `rename` then fails, and tier 2 records the
/// error on the session and **keeps the draft row**, which is where the
/// unwritten work lives. Nothing is lost, and the next idle firing writes it.
///
/// # Why this runs under the lifecycle lock
///
/// The other race is not benign, and it is why [`converge`] holds the lifecycle
/// lock across this call. A `.burlmd-trash.*` entry is not only debris a kill
/// left behind: it is the **live rollback record** of an in-flight
/// `delete_note`. `workspace::lifecycle`'s `FileJournal::trash` renames the Note
/// aside rather than removing it, precisely so that a failure later in the
/// operation can rename it back, and `FileJournal::commit` is what finally
/// unlinks it once the deletion has succeeded. A sweep landing in that window
/// removes the only copy of the Note's content, and the rollback that would have
/// restored it finds nothing — turning a recoverable failure into permanent data
/// loss, on a path whose whole guarantee is that a lifecycle operation either
/// completes or changes nothing. Under the lock the two cannot overlap: a
/// deletion in flight has already excluded this open, and this sweep only ever
/// sees entries no operation still owns.
///
/// Failures do not abort the open, and that stays deliberate. This is
/// housekeeping on a path whose real job is opening a Workspace, and a scratch
/// file that cannot be removed — a read-only directory, a file another process
/// holds — is not a reason to refuse the user their Notes. `.gitignore` is the
/// backstop that makes it merely untidy rather than a disclosure.
///
/// They are no longer discarded outright, though. The outcome is returned as a
/// [`ScratchSweep`], so "the sweep ran and left five files behind" is a fact
/// this function's caller and its tests can see rather than one that existed
/// only inside the loop. The crate has no logging framework, so this is the
/// whole of the channel: [`converge`] does not fail on it — nothing about a
/// leftover scratch file makes the Workspace unusable — and records in one
/// place, in prose, that the decision is deliberate.
///
/// `.git/` is skipped for the same reason `index::scan::walk_bundle` skips it:
/// it is the application's own version history, holds thousands of files, and
/// contains no bundle content.
fn sweep_scratch_files(dir: &Path) -> ScratchSweep {
    // Recurses the whole bundle, so it belongs outside the connection for the
    // same reason the scan does (`SPK-WSPC-D001` §6.2.7).
    crate::db::connection::assert_no_io_under_the_connection("the scratch sweep");

    let mut outcome = ScratchSweep::default();
    let entries = match std::fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(e) => {
            outcome.record(format!("read directory {}: {e}", dir.display()));
            return outcome;
        }
    };
    for entry in entries {
        let entry = match entry {
            Ok(entry) => entry,
            Err(e) => {
                outcome.record(format!("read an entry under {}: {e}", dir.display()));
                continue;
            }
        };
        let name = entry.file_name().to_string_lossy().into_owned();
        if name == ".git" {
            continue;
        }
        let path = entry.path();
        // `workspace::classify_entry` rather than a local `is_dir()`, so that
        // this sweep and the two other walks over a bundle share one definition
        // of what a link is. The behavior here is unchanged: a link is not a
        // directory, so it is unlinked (never `remove_dir_all`'d through) when
        // its own name is one of ours, and never recursed into otherwise.
        let is_dir = entry
            .file_type()
            .is_ok_and(|t| super::classify_entry(&t) == super::BundleEntry::Directory);
        if super::is_burlmd_scratch_name(&name) {
            let removed = if is_dir {
                std::fs::remove_dir_all(&path)
            } else {
                std::fs::remove_file(&path)
            };
            match removed {
                Ok(()) => outcome.removed += 1,
                Err(e) => outcome.record(format!("remove {}: {e}", path.display())),
            }
        } else if is_dir {
            outcome.absorb(sweep_scratch_files(&path));
        }
    }
    outcome
}

/// What one [`sweep_scratch_files`] pass managed: how many scratch entries it
/// removed, how many it could not, and the first reason it could not.
///
/// Deliberately not an error type. Every field here describes a best-effort
/// step whose failure is survivable by construction, and the reason it is a
/// value rather than a discarded `Result` is stated on `sweep_scratch_files`.
#[derive(Debug, Default, PartialEq, Eq)]
struct ScratchSweep {
    removed: usize,
    failed: usize,
    first_failure: Option<String>,
}

impl ScratchSweep {
    fn record(&mut self, failure: String) {
        self.failed += 1;
        if self.first_failure.is_none() {
            self.first_failure = Some(failure);
        }
    }

    fn absorb(&mut self, other: Self) {
        self.removed += other.removed;
        self.failed += other.failed;
        if self.first_failure.is_none() {
            self.first_failure = other.first_failure;
        }
    }
}

fn workspace_name(dir: &Path) -> String {
    dir.file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("Workspace")
        .to_string()
}

/// Mints an opaque, locally-generated Workspace id — `schema.sql`: "Opaque,
/// locally minted. Not a concept id." A 128-bit CSPRNG value, hex-encoded.
fn mint_workspace_id() -> Result<String, AppError> {
    let mut bytes = [0u8; 16];
    getrandom::fill(&mut bytes)
        .map_err(|e| AppError::CryptoError(format!("OS CSPRNG failure: {e}")))?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::connection::{init_schema, open_encrypted_db_with_key, EnvVarGuard, ENV_LOCK};
    use tempfile::tempdir;

    /// A real, on-disk SQLCipher connection with the schema applied — never
    /// the process-wide `db::connection` singleton and never the OS
    /// Keychain, so these tests are hermetic and can run in any order.
    fn test_index(dir: &Path) -> Connection {
        let key = [0x77u8; 32]; // throwaway key, not the real Keychain entry
        let conn = open_encrypted_db_with_key(&dir.join("index.sqlite3"), &key).unwrap();
        init_schema(&conn).unwrap();
        conn
    }

    /// Gherkin: Given no Workspace directory exists and no network is
    /// reachable, When the local Workspace is opened, Then the directory is
    /// created, a repository is initialized in it, and a Workspace row is
    /// written with a local provider and no remote URL.
    ///
    /// "No network is reachable" needs no simulation: nothing in this
    /// module, `git::operations::init_repo`, or the query below makes a
    /// network call at all.
    #[test]
    fn open_or_create_creates_dir_repo_and_local_workspace_row() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let workspace_parent = tempdir().unwrap();
        let workspace_dir = workspace_parent.path().join("does-not-exist-yet");
        assert!(!workspace_dir.exists());

        let info = open_or_create_local_workspace_impl(
            &conn,
            Some(workspace_dir.to_string_lossy().to_string()),
        )
        .expect("bootstrap should succeed against an absent directory");

        assert!(workspace_dir.is_dir());
        assert!(workspace_dir.join(".git").is_dir());
        assert_eq!(info.provider, "local");
        assert_eq!(info.remote_url, None);
        // Canonicalized (WSPC-D004 review finding #2), so compared against a
        // canonicalized expectation rather than the raw tempdir path — the
        // two coincide unless a path component is a symlink, which this
        // assertion should not assume either way.
        assert_eq!(
            PathBuf::from(&info.local_path),
            std::fs::canonicalize(&workspace_dir).unwrap()
        );
        assert!(!info.id.is_empty());

        let row: (String, Option<String>) = conn
            .query_row(
                "SELECT provider, remote_url FROM workspaces WHERE id = ?1",
                [&info.id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(row, ("local".to_string(), None));
    }

    /// Gherkin: Given a Workspace that already exists, When the local
    /// Workspace is opened again, Then the existing repository and Workspace
    /// row are reused — same id, same row count.
    #[test]
    fn second_open_reuses_the_existing_repository_and_workspace_row() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let workspace_dir = tempdir().unwrap();
        let path = workspace_dir.path().to_string_lossy().to_string();

        let first = open_or_create_local_workspace_impl(&conn, Some(path.clone())).unwrap();
        let second = open_or_create_local_workspace_impl(&conn, Some(path)).unwrap();

        assert_eq!(first.id, second.id, "the same Workspace row must be reused");

        let count: i64 = conn
            .query_row("SELECT count(*) FROM workspaces", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 1, "no second row may be written on a repeat open");
    }

    /// Gherkin: Given an existing directory of Markdown files that this
    /// application did not create, When it is opened as a Workspace, Then it
    /// becomes the active Workspace, a Workspace row is written for it, and
    /// no Note in it is modified.
    #[test]
    fn open_workspace_adopts_a_foreign_directory_without_modifying_its_notes() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let foreign_dir = tempdir().unwrap();
        let welcome = foreign_dir.path().join("Welcome.md");
        let original_bytes = b"---\ntitle: Welcome\n---\n\nHello.\n";
        std::fs::write(&welcome, original_bytes).unwrap();

        let info = open_workspace_impl(&conn, foreign_dir.path().to_string_lossy().to_string())
            .expect("adopting a foreign directory should succeed");

        assert_eq!(info.provider, "local");
        let stored_bytes = std::fs::read(&welcome).unwrap();
        assert_eq!(
            stored_bytes, original_bytes,
            "no Note in an adopted directory may be modified"
        );

        let canonical_path = std::fs::canonicalize(foreign_dir.path()).unwrap();
        let row_count: i64 = conn
            .query_row(
                "SELECT count(*) FROM workspaces WHERE local_path = ?1",
                [canonical_path.to_string_lossy()],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(row_count, 1);
    }

    /// A `SIGKILL` leaves a `.burlmd-trash.*` entry (the full content of a
    /// deleted Note) or an `.{name}.tmp` (a Note mid-write) sitting untracked
    /// inside the bundle, because no `Drop` runs. `commit_all` snapshots the
    /// whole worktree, so the next commit would publish either as plaintext.
    /// Opening the Workspace sweeps both.
    #[test]
    fn opening_a_workspace_sweeps_scratch_files_a_kill_left_behind() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let dir = tempdir().unwrap();
        std::fs::create_dir_all(dir.path().join("projects")).unwrap();
        std::fs::write(dir.path().join("Kept.md"), "---\ntitle: Kept\n---\n").unwrap();
        std::fs::write(
            dir.path().join(".burlmd-trash.Deleted.md.4242.0"),
            "the whole content of a deleted Note\n",
        )
        .unwrap();
        std::fs::write(
            dir.path().join("projects/.burlmd-trash.Nested.md.4242.1"),
            "and another, one level down\n",
        )
        .unwrap();
        std::fs::create_dir_all(dir.path().join(".burlmd-trash.a directory.4242.2")).unwrap();
        std::fs::write(
            dir.path()
                .join(".burlmd-trash.a directory.4242.2/inside.md"),
            "a whole deleted Directory\n",
        )
        .unwrap();
        std::fs::write(
            dir.path().join("projects/.burlmd.md.4242.0.tmp"),
            "a Note as it was mid-write\n",
        )
        .unwrap();
        // A dot-file that is not ours must survive.
        std::fs::write(dir.path().join(".editorconfig"), "root = true\n").unwrap();

        open_workspace_impl(&conn, dir.path().to_string_lossy().to_string()).unwrap();

        assert!(!dir.path().join(".burlmd-trash.Deleted.md.4242.0").exists());
        assert!(!dir
            .path()
            .join("projects/.burlmd-trash.Nested.md.4242.1")
            .exists());
        assert!(!dir.path().join(".burlmd-trash.a directory.4242.2").exists());
        assert!(!dir.path().join("projects/.burlmd.md.4242.0.tmp").exists());
        assert!(dir.path().join("Kept.md").is_file(), "a Note must survive");
        assert!(
            dir.path().join(".editorconfig").is_file(),
            "a dot-file that is not burlmd's must survive"
        );
    }

    /// The sweep removes burlmd's scratch files and **only** burlmd's.
    ///
    /// The regression this pins: the predicate matched any dot-prefixed name
    /// ending in `.tmp`, so adopting a foreign bundle (CAP-WS-05) deleted
    /// another tool's `.foo.tmp` — and, because a matching *directory* is
    /// removed with `remove_dir_all`, everything inside its `.bar.tmp/` as well.
    /// `converge` says in as many words that what this removes is "burlmd's, not
    /// the bundle's", and that was false for every shape but its own.
    #[test]
    fn the_sweep_leaves_a_foreign_tools_dot_tmp_files_and_directories_alone() {
        let dir = tempdir().unwrap();
        // Not burlmd's: no `{pid}.{n}` before the suffix.
        std::fs::write(dir.path().join(".foo.tmp"), "another tool's scratch\n").unwrap();
        std::fs::create_dir_all(dir.path().join(".bar.tmp")).unwrap();
        std::fs::write(dir.path().join(".bar.tmp/held.txt"), "and its contents\n").unwrap();
        // Nor is a name that has only one numeric component, or a non-numeric
        // one where the pid belongs.
        std::fs::write(dir.path().join(".Note.md.7.tmp"), "one component\n").unwrap();
        std::fs::write(dir.path().join(".Note.md.pid.0.tmp"), "not a pid\n").unwrap();
        // burlmd's own, in both families.
        std::fs::write(dir.path().join(".Note.md.4242.0.tmp"), "mid-write\n").unwrap();
        std::fs::write(dir.path().join(".burlmd-trash.Gone.md.4242.0"), "gone\n").unwrap();

        let swept = sweep_scratch_files(dir.path());

        assert_eq!(swept.removed, 2, "only burlmd's two entries may be removed");
        assert_eq!(swept.failed, 0);
        assert!(!dir.path().join(".Note.md.4242.0.tmp").exists());
        assert!(!dir.path().join(".burlmd-trash.Gone.md.4242.0").exists());
        assert!(
            dir.path().join(".foo.tmp").is_file(),
            "a foreign .tmp file must survive"
        );
        assert!(
            dir.path().join(".bar.tmp/held.txt").is_file(),
            "a foreign .tmp directory and its contents must survive"
        );
        assert!(dir.path().join(".Note.md.7.tmp").is_file());
        assert!(dir.path().join(".Note.md.pid.0.tmp").is_file());
    }

    /// Bootstrap's three filesystem phases run with **no connection held**, and
    /// the guard says so rather than the prose alone.
    ///
    /// The regression this pins: [`converge`] took a `&Connection`, so its
    /// caller was obliged to hold one — and a repository init, a recursive
    /// scratch sweep and a read-and-parse of every Note in the bundle all ran
    /// inside `with_connection`, holding the process-wide mutex a keystroke's
    /// own tier 1 draft write waits on for the length of a whole bundle walk
    /// (`SPK-WSPC-D001` §6.2.7). A whole successful bootstrap here is the
    /// assertion: each of the three phases now asserts it is unguarded, so any
    /// of them slipping back under the connection is a panic, not a review
    /// finding.
    ///
    /// The second half proves the guard is live rather than vacuous, by doing
    /// the forbidden thing on purpose.
    #[cfg(debug_assertions)]
    #[test]
    fn bootstrap_never_walks_the_bundle_with_the_connection_held() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let dir = tempdir().unwrap();
        std::fs::write(dir.path().join("Walked.md"), "---\ntitle: Walked\n---\n").unwrap();
        std::fs::write(dir.path().join(".burlmd.md.4242.0.tmp"), "swept\n").unwrap();

        // Each phase asserts internally; reaching the end means none fired.
        let info = open_workspace_impl(&conn, dir.path().to_string_lossy().to_string()).unwrap();
        assert_eq!(
            conn.query_row(
                "SELECT count(*) FROM notes WHERE workspace_id = ?1",
                [&info.id],
                |r| r.get::<_, i64>(0)
            )
            .unwrap(),
            1,
            "the bundle must still be indexed by the split rebuild"
        );

        let previous_hook = std::panic::take_hook();
        std::panic::set_hook(Box::new(|_| {}));
        let forbidden = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            IndexHandle::Injected(&conn)
                .with(|_conn| crate::index::scan::scan_bundle(dir.path()).map(|_| ()))
        }));
        std::panic::set_hook(previous_hook);

        let payload = forbidden.expect_err("scanning under the connection must be a hard error");
        let message = payload
            .downcast_ref::<String>()
            .cloned()
            .or_else(|| payload.downcast_ref::<&str>().map(|s| (*s).to_string()))
            .unwrap_or_default();
        assert!(
            message.contains("ran inside a connection closure"),
            "expected the connection-scope guard, got {message:?}"
        );
    }

    /// The sweep reports what it did and what it could not do, instead of
    /// discarding both.
    ///
    /// Every failure here is survivable — that is why the open does not fail on
    /// one — but "survivable" and "invisible" are different things, and with no
    /// logging in this crate the returned [`ScratchSweep`] is the only place the
    /// distinction can live. The unremovable entry is a *non-empty directory
    /// made read-only*, which is what really stops `remove_dir_all`: the
    /// directory's own write bit is what permits unlinking the child inside it.
    #[test]
    fn the_scratch_sweep_reports_its_count_and_its_first_failure() {
        let dir = tempdir().unwrap();
        std::fs::write(dir.path().join(".burlmd-trash.One.md.4242.0"), "one\n").unwrap();
        std::fs::create_dir_all(dir.path().join("nested")).unwrap();
        std::fs::write(dir.path().join("nested/.burlmd.md.4242.0.tmp"), "two\n").unwrap();

        let clean = sweep_scratch_files(dir.path());

        assert_eq!(
            clean,
            ScratchSweep {
                removed: 2,
                failed: 0,
                first_failure: None
            }
        );

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;

            let stuck = dir.path().join(".burlmd-trash.Stuck.4242.1");
            std::fs::create_dir_all(&stuck).unwrap();
            std::fs::write(stuck.join("inside.md"), "held\n").unwrap();
            std::fs::set_permissions(&stuck, std::fs::Permissions::from_mode(0o500)).unwrap();
            std::fs::write(dir.path().join(".burlmd-trash.Free.md.4242.2"), "free\n").unwrap();

            let partial = sweep_scratch_files(dir.path());

            // Restored before any assertion, so a failing assert cannot leave
            // the `TempDir`'s own cleanup unable to run.
            std::fs::set_permissions(&stuck, std::fs::Permissions::from_mode(0o700)).unwrap();

            assert_eq!(partial.removed, 1, "the removable entry must still go");
            assert_eq!(partial.failed, 1);
            let failure = partial
                .first_failure
                .expect("the first failure must be reported, not discarded");
            assert!(
                failure.contains(".burlmd-trash.Stuck.4242.1"),
                "the report must name the entry that was left behind, got {failure}"
            );
            assert!(!dir.path().join(".burlmd-trash.Free.md.4242.2").exists());
        }
    }

    /// The other half: `.gitignore` is the backstop for a scratch file created
    /// *after* the sweep and killed before its own cleanup. It must be written
    /// when the repository is initialized and extended — not clobbered — when
    /// an existing bundle is adopted.
    #[test]
    fn bootstrap_writes_the_scratch_gitignore_and_appends_to_an_existing_one() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());

        let fresh = tempdir().unwrap();
        open_or_create_local_workspace_impl(
            &conn,
            Some(fresh.path().to_string_lossy().to_string()),
        )
        .unwrap();
        let written = std::fs::read_to_string(fresh.path().join(".gitignore")).unwrap();
        for pattern in crate::workspace::SCRATCH_IGNORE_PATTERNS {
            assert!(
                written.lines().any(|line| line.trim() == pattern),
                "{pattern} missing from a freshly initialized bundle's .gitignore: {written:?}"
            );
        }

        let adopted = tempdir().unwrap();
        std::fs::write(adopted.path().join(".gitignore"), "*.pdf\ndrafts/\n").unwrap();
        open_workspace_impl(&conn, adopted.path().to_string_lossy().to_string()).unwrap();
        let extended = std::fs::read_to_string(adopted.path().join(".gitignore")).unwrap();
        assert!(
            extended.starts_with("*.pdf\ndrafts/\n"),
            "the user's own patterns must survive verbatim, got {extended:?}"
        );
        for pattern in crate::workspace::SCRATCH_IGNORE_PATTERNS {
            assert!(
                extended.lines().any(|line| line.trim() == pattern),
                "{pattern} missing after adoption: {extended:?}"
            );
        }

        // Idempotent: a second open must not append the patterns again.
        open_workspace_impl(&conn, adopted.path().to_string_lossy().to_string()).unwrap();
        let twice = std::fs::read_to_string(adopted.path().join(".gitignore")).unwrap();
        assert_eq!(twice, extended, "a repeat open must change nothing");
    }

    /// A `.gitignore` this application cannot *read* must not stop the user
    /// reaching their Notes.
    ///
    /// The extension is a backstop and the function that writes it says so:
    /// the scratch files it covers are swept on every bootstrap, and every
    /// commit burlmd makes is pathspec-scoped, so the patterns only matter for
    /// a file the sweep missed *and* a broad `commit_all` then picked up. The
    /// symlink case already declines rather than failing, for exactly that
    /// reason.
    ///
    /// Reading the file as a `String` did not: a foreign bundle whose
    /// `.gitignore` holds arbitrary bytes (a latin-1 file, say) returned
    /// `IoError("stream did not contain valid UTF-8")`, and that propagated
    /// through `init_repo` -> `converge` -> `open_workspace`, so the bundle
    /// could never be opened at all. The same held for a `.gitignore` that is
    /// a directory, which reads as `IsADirectory`. Neither is a reason to
    /// refuse someone their own notes.
    #[test]
    fn a_gitignore_this_application_cannot_read_does_not_stop_the_bundle_opening() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());

        let latin1 = tempdir().unwrap();
        std::fs::write(latin1.path().join("Note.md"), "# Note\n").unwrap();
        // `0xFF` is not valid UTF-8 in any position.
        std::fs::write(latin1.path().join(".gitignore"), b"caf\xe9/\n*.pdf\n").unwrap();
        open_workspace_impl(&conn, latin1.path().to_string_lossy().to_string())
            .expect("a bundle whose .gitignore is not UTF-8 must still open");
        assert_eq!(
            std::fs::read(latin1.path().join(".gitignore")).unwrap(),
            b"caf\xe9/\n*.pdf\n",
            "the user's own bytes must be left exactly as they were"
        );

        let as_dir = tempdir().unwrap();
        std::fs::write(as_dir.path().join("Note.md"), "# Note\n").unwrap();
        std::fs::create_dir(as_dir.path().join(".gitignore")).unwrap();
        open_workspace_impl(&conn, as_dir.path().to_string_lossy().to_string())
            .expect("a bundle whose .gitignore is a directory must still open");
        assert!(
            as_dir.path().join(".gitignore").is_dir(),
            "the directory the user put there must be left alone"
        );
    }

    /// The `.gitignore` write is also **committed**, in a pathspec'd commit of
    /// its own, and only on the open that actually wrote it.
    ///
    /// It is a file burlmd puts inside the user's bundle. Left uncommitted it is
    /// untracked (fresh bundle) or modified (adopted one) in every `git status`
    /// the user ever runs against their own notes, forever — a worktree this
    /// application dirtied on their behalf and never cleaned up — and it is
    /// resolved at a time nobody chose, by the next `commit_all` a sync makes,
    /// filing burlmd's housekeeping inside an unrelated commit.
    #[test]
    fn bootstrap_commits_the_gitignore_it_writes_and_only_when_it_writes_one() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let bundle = tempdir().unwrap();

        open_or_create_local_workspace_impl(
            &conn,
            Some(bundle.path().to_string_lossy().to_string()),
        )
        .unwrap();

        assert_eq!(
            git_out(bundle.path(), &["status", "--porcelain"]),
            "",
            "bootstrap left the bundle's worktree dirty with its own .gitignore"
        );
        assert!(
            git_out(bundle.path(), &["ls-tree", "-r", "--name-only", "HEAD"])
                .lines()
                .any(|line| line == ".gitignore"),
            "the .gitignore is not in HEAD"
        );
        let subjects = git_out(bundle.path(), &["log", "--format=%s"]);
        assert_eq!(subjects, "Ignore burlmd scratch files", "{subjects:?}");

        // A repeat open writes nothing, so it must commit nothing.
        open_workspace_impl(&conn, bundle.path().to_string_lossy().to_string()).unwrap();
        assert_eq!(
            git_out(bundle.path(), &["log", "--format=%s"]),
            subjects,
            "a repeat open added a second commit for a file it did not touch"
        );
    }

    /// A bootstrap cannot run inside a lifecycle operation: everything after
    /// the `workspaces` row is resolved waits for the lifecycle lock.
    ///
    /// The two defects this closes, both invisible to any per-Note lock:
    ///
    /// - **`scan_bundle` → `write_scanned_bundle` straddled an O(bundle)
    ///   window.** A `rename_note` completing inside it has already moved the
    ///   file and rewritten its rows; the write phase then replays a snapshot
    ///   taken before the move, reinstating the old concept id and leaving the
    ///   index naming a file that no longer exists. Exactly the defect the
    ///   `reindex_workspace` fix closed, one function over.
    /// - **The scratch sweep removed a live rollback record.** A
    ///   `.burlmd-trash.*` entry is what `FileJournal::rollback` renames back
    ///   when a `delete_note` fails part-way; sweeping it mid-deletion turns a
    ///   recoverable failure into a lost Note.
    ///
    /// Driven through the lock itself rather than through a rename, for the
    /// reason `persist`'s own serialization tests give: holding it is precisely
    /// the condition a lifecycle operation establishes, and "makes no progress
    /// until it is released" is what serialization *means* here. The sleep can
    /// only weaken the observation, never fail it spuriously — a slower machine
    /// makes the "not yet" more certain — and the join is what proves the
    /// bootstrap is blocked rather than broken.
    ///
    /// The waiting thread opens its **own** connection to the same on-disk
    /// index, since a `rusqlite::Connection` is not `Sync`. That is also closer
    /// to what production does, where both callers reach the one process-wide
    /// connection rather than sharing a borrow.
    #[test]
    fn a_bootstrap_cannot_run_inside_a_lifecycle_operation() {
        use std::sync::atomic::{AtomicBool, Ordering};
        use std::sync::Arc;

        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let bundle = tempdir().unwrap();
        let path = bundle.path().to_string_lossy().to_string();

        // The first open establishes the row whose id keys the lock.
        let info = open_workspace_impl(&conn, path.clone()).unwrap();

        let entered = Arc::new(AtomicBool::new(false));
        let converged = Arc::new(AtomicBool::new(false));
        let index_path = index_dir.path().join("index.sqlite3");

        let waiter = crate::workspace::persist::with_lifecycle_lock_id(&info.id, || {
            let entered_by_waiter = Arc::clone(&entered);
            let converged_by_waiter = Arc::clone(&converged);
            let waiter = std::thread::spawn(move || {
                let own_conn = open_encrypted_db_with_key(&index_path, &[0x77u8; 32]).unwrap();
                entered_by_waiter.store(true, Ordering::SeqCst);
                open_workspace_impl(&own_conn, path).expect("the bundle is on disk");
                converged_by_waiter.store(true, Ordering::SeqCst);
            });

            while !entered.load(Ordering::SeqCst) {
                std::thread::yield_now();
            }
            std::thread::sleep(std::time::Duration::from_millis(100));
            assert!(
                !converged.load(Ordering::SeqCst),
                "a bootstrap completed while a lifecycle operation held the lock, so its \
                 scan-then-write can still replay a stale snapshot over a rename's rows, and \
                 its sweep can still remove a deletion's rollback record"
            );
            Ok(waiter)
        })
        .unwrap();

        waiter.join().unwrap();
        assert!(
            converged.load(Ordering::SeqCst),
            "the bootstrap never completed once the lock was released"
        );
        let count: i64 = conn
            .query_row("SELECT count(*) FROM workspaces", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 1, "the second open must reuse the same row");
    }

    fn git_out(dir: &Path, args: &[&str]) -> String {
        let output = std::process::Command::new("git")
            .args(args)
            .current_dir(dir)
            .env("GIT_CONFIG_GLOBAL", "/dev/null")
            .env("GIT_CONFIG_SYSTEM", "/dev/null")
            .output()
            .expect("git CLI available in devenv shell");
        String::from_utf8_lossy(&output.stdout).trim().to_string()
    }

    /// `flow-workspace-bootstrap.md`'s fourth post-condition: the bundle is
    /// indexed. Adopting a foreign bundle must populate `notes`, `directories`
    /// and `links` — the tree, search and the graph all read from those, and a
    /// `WSPC-D006` rename seeds its affected set from `links`, so an unindexed
    /// bundle renames a Note and leaves every inbound Link pointing at the
    /// concept the rename removed (`architecture/risks.md` risk 8).
    #[test]
    fn open_workspace_indexes_the_bundle_it_adopts() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let foreign_dir = tempdir().unwrap();
        std::fs::create_dir_all(foreign_dir.path().join("projects")).unwrap();
        std::fs::write(
            foreign_dir.path().join("Welcome.md"),
            "---\ntype: Note\ntitle: Welcome\n---\n\nSee [Burlmd](</projects/burlmd.md>).\n",
        )
        .unwrap();
        std::fs::write(
            foreign_dir.path().join("projects/burlmd.md"),
            "---\ntype: Note\ntitle: Burlmd\n---\n\nA distinctive antidisestablishmentarian body.\n",
        )
        .unwrap();

        let info = open_workspace_impl(&conn, foreign_dir.path().to_string_lossy().to_string())
            .expect("adopting a foreign directory should succeed");

        let note_ids: Vec<String> = {
            let mut stmt = conn
                .prepare("SELECT id FROM notes WHERE workspace_id = ?1 ORDER BY id")
                .unwrap();
            let rows = stmt
                .query_map([&info.id], |row| row.get::<_, String>(0))
                .unwrap()
                .collect::<Result<Vec<_>, _>>()
                .unwrap();
            rows
        };
        assert_eq!(
            note_ids,
            vec!["Welcome".to_string(), "projects/burlmd".to_string()],
            "every Note in an adopted bundle must be indexed"
        );

        let directories: i64 = conn
            .query_row(
                "SELECT count(*) FROM directories WHERE workspace_id = ?1 AND id = 'projects'",
                [&info.id],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(directories, 1, "the tree renders from `directories`");

        let (source, target): (String, String) = conn
            .query_row(
                "SELECT source_id, target_id FROM links WHERE workspace_id = ?1",
                [&info.id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(
            (source.as_str(), target.as_str()),
            ("Welcome", "projects/burlmd")
        );

        let searchable: i64 = conn
            .query_row(
                "SELECT count(*) FROM notes_fts WHERE notes_fts MATCH ?1",
                ["antidisestablishmentarian"],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(searchable, 1, "an adopted bundle must be searchable");
    }

    /// The other entry point converges on the same post-condition, including
    /// on a **reopen**: a reused `workspaces` row says nothing about whether
    /// the files under it still match the index, since another tool may have
    /// changed them while the application was not running.
    #[test]
    fn a_reopen_reindexes_changes_another_tool_made_while_the_app_was_closed() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let workspace_dir = tempdir().unwrap();
        let path = workspace_dir.path().to_string_lossy().to_string();
        std::fs::write(
            workspace_dir.path().join("First.md"),
            "---\ntype: Note\ntitle: First\n---\n\nBody.\n",
        )
        .unwrap();

        let first = open_or_create_local_workspace_impl(&conn, Some(path.clone())).unwrap();

        // Something else edits the bundle between the two opens.
        std::fs::remove_file(workspace_dir.path().join("First.md")).unwrap();
        std::fs::write(
            workspace_dir.path().join("Second.md"),
            "---\ntype: Note\ntitle: Second\n---\n\nBody.\n",
        )
        .unwrap();

        let second = open_or_create_local_workspace_impl(&conn, Some(path)).unwrap();

        assert_eq!(first.id, second.id);
        let note_ids: Vec<String> = {
            let mut stmt = conn
                .prepare("SELECT id FROM notes WHERE workspace_id = ?1 ORDER BY id")
                .unwrap();
            let rows = stmt
                .query_map([&second.id], |row| row.get::<_, String>(0))
                .unwrap()
                .collect::<Result<Vec<_>, _>>()
                .unwrap();
            rows
        };
        assert_eq!(note_ids, vec!["Second".to_string()]);
    }

    /// Gherkin: Given that directory contains no version history, When it is
    /// opened as a Workspace, Then a repository is initialized in it —
    /// otherwise `close_note`'s tier 3 commit has nothing to commit into
    /// (ADR-005 decision 8).
    #[test]
    fn open_workspace_initializes_a_repository_when_the_directory_has_no_history() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let foreign_dir = tempdir().unwrap();
        std::fs::write(foreign_dir.path().join("note.md"), b"content\n").unwrap();
        assert!(!foreign_dir.path().join(".git").exists());

        open_workspace_impl(&conn, foreign_dir.path().to_string_lossy().to_string()).unwrap();

        assert!(foreign_dir.path().join(".git").is_dir());
    }

    /// Gherkin: Given that directory already contains version history, When
    /// it is opened as a Workspace, Then the existing history is adopted
    /// unchanged.
    #[test]
    fn open_workspace_adopts_existing_history_unchanged() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let dir = tempdir().unwrap();
        crate::git::operations::init_repo(dir.path()).unwrap();
        std::fs::write(dir.path().join("note.md"), b"content\n").unwrap();
        let commit = crate::git::operations::commit_all(
            dir.path(),
            "pre-existing history",
            "Someone Else",
            "someone@example.com",
        )
        .unwrap();

        open_workspace_impl(&conn, dir.path().to_string_lossy().to_string()).unwrap();

        let head = std::process::Command::new("git")
            .args(["rev-parse", "HEAD"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        assert_eq!(
            String::from_utf8_lossy(&head.stdout).trim(),
            commit,
            "pre-existing history must not be disturbed by adoption"
        );
    }

    /// WSPC-D004 review finding #1: `open_workspace` must not create the
    /// directory it's pointed at — a typo, an unmounted volume, or a stale
    /// recent-Workspace entry must be reported rather than silently
    /// producing a fresh empty Workspace that shadows the real bundle.
    #[test]
    fn open_workspace_errors_and_creates_nothing_when_the_directory_is_absent() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let parent = tempdir().unwrap();
        let missing = parent.path().join("does-not-exist");
        assert!(!missing.exists());

        let result = open_workspace_impl(&conn, missing.to_string_lossy().to_string());

        assert!(
            matches!(result, Err(AppError::NotFound(_))),
            "expected NotFound, got {result:?}"
        );
        assert!(
            !missing.exists(),
            "open_workspace must not create the directory it failed to find"
        );
        let count: i64 = conn
            .query_row("SELECT count(*) FROM workspaces", [], |r| r.get(0))
            .unwrap();
        assert_eq!(
            count, 0,
            "no Workspace row may be written for a missing directory"
        );
    }

    /// WSPC-D004 review finding #2: `local_path` has no `UNIQUE` constraint,
    /// so the reuse-on-repeat-open behavior depends entirely on every caller
    /// agreeing on one spelling of the same directory. A trailing slash must
    /// not be enough to mint a second row for the same bundle.
    #[test]
    fn a_trailing_slash_spelling_of_the_same_directory_reuses_the_same_row() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let workspace_dir = tempdir().unwrap();
        let bare = workspace_dir.path().to_string_lossy().to_string();
        let with_trailing_slash = format!("{bare}/");

        let first = open_or_create_local_workspace_impl(&conn, Some(bare)).unwrap();
        let second = open_or_create_local_workspace_impl(&conn, Some(with_trailing_slash)).unwrap();

        assert_eq!(
            first.id, second.id,
            "a trailing-slash spelling of the same directory must reuse the row"
        );
        let count: i64 = conn
            .query_row("SELECT count(*) FROM workspaces", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 1);
    }

    /// WSPC-D004 review finding #2, the other spelling: a relative path to
    /// the same directory must also reuse the row rather than minting a
    /// second one that splits the bundle's index across two Workspace ids
    /// (ADR-005 decision 7). Mutates the process's current directory, so
    /// this holds `ENV_LOCK` for its whole duration — the same process-wide
    /// mutable state `EnvVarGuard`'s callers serialize on, per
    /// `db::connection::ENV_LOCK`'s doc comment.
    #[test]
    fn a_relative_spelling_of_the_same_directory_reuses_the_same_row() {
        let _guard = ENV_LOCK.lock().unwrap();
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let workspace_parent = tempdir().unwrap();
        let workspace_dir = workspace_parent.path().join("ws");
        std::fs::create_dir_all(&workspace_dir).unwrap();

        let original_cwd = std::env::current_dir().unwrap();
        std::env::set_current_dir(workspace_parent.path()).unwrap();
        let first = open_or_create_local_workspace_impl(
            &conn,
            Some(workspace_dir.to_string_lossy().to_string()),
        )
        .unwrap();
        let second = open_or_create_local_workspace_impl(&conn, Some("ws".to_string())).unwrap();
        std::env::set_current_dir(original_cwd).unwrap();

        assert_eq!(
            first.id, second.id,
            "a relative spelling of the same directory must reuse the row"
        );
        let count: i64 = conn
            .query_row("SELECT count(*) FROM workspaces", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 1);
    }

    /// Gherkin: Given any connection opened against the encrypted index,
    /// When `PRAGMA foreign_keys` is queried on it, Then it reports enabled.
    /// Re-asserted here (beyond `db::connection`'s own coverage) against the
    /// exact connection shape this module's tests use, since bootstrap is
    /// the caller `guidelines.md` names as depending on the cascades it
    /// gates.
    #[test]
    fn the_connection_bootstrap_writes_through_has_foreign_keys_enabled() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let enabled: i64 = conn
            .query_row("PRAGMA foreign_keys", [], |r| r.get(0))
            .unwrap();
        assert_eq!(enabled, 1);
    }

    /// WSPC-D004: `open_or_create_local_workspace`'s default path and
    /// `db::connection`'s default index path resolve to siblings under the
    /// same shared `burlmd/` parent — the index lives outside the bundle,
    /// not within it, and not at the legacy `$HOME/.burlmd` location.
    #[test]
    fn default_workspace_dir_and_default_index_path_are_siblings_outside_each_other() {
        let _guard = ENV_LOCK.lock().unwrap();
        let fake_home = tempdir().unwrap();
        let _home = EnvVarGuard::set("HOME", fake_home.path().as_os_str());
        let _no_xdg = EnvVarGuard::unset("XDG_DATA_HOME");
        let _no_override = EnvVarGuard::unset("BURLMD_DB_PATH");

        let workspace_dir = default_workspace_dir().unwrap();
        let index_path = crate::db::connection::default_db_path().unwrap();

        assert_eq!(
            workspace_dir,
            fake_home
                .path()
                .join(".local")
                .join("share")
                .join("burlmd")
                .join("workspace")
        );
        assert_eq!(
            index_path,
            fake_home
                .path()
                .join(".local")
                .join("share")
                .join("burlmd")
                .join("index.sqlite3")
        );
        assert_eq!(
            workspace_dir.parent(),
            index_path.parent(),
            "the Workspace directory and the index must share the same burlmd/ parent"
        );
        assert!(
            !index_path.starts_with(&workspace_dir),
            "the index must not live inside the bundle it indexes"
        );

        let legacy_path = fake_home.path().join(".burlmd").join("index.sqlite3");
        assert_ne!(index_path, legacy_path);
    }

    /// A bundle root that resolves to a path which is not valid UTF-8 is
    /// refused, for the reason `index::scan::walk_bundle` skips an *entry* so
    /// named: `to_string_lossy` does not fail, it substitutes `U+FFFD`, and
    /// what would go into `workspaces.local_path` is then a string naming no
    /// directory on this filesystem.
    ///
    /// That column is the root every later path resolution is joined onto, so
    /// the damage is not local to the row — and unlike a mangled *entry* name,
    /// it can never self-repair: the next open canonicalizes to the same bytes,
    /// mangles them the same way, and matches the same broken row by
    /// `local_path`, so reuse is what keeps it alive. Refusing at the boundary
    /// is the only exit.
    ///
    /// The path arrives here as a `String`, so it is valid UTF-8 by
    /// construction — which is exactly why this is reached through a symlink:
    /// `canonicalize` resolves it, and what it resolves *to* is bytes nobody at
    /// the FFI boundary chose.
    #[cfg(unix)]
    #[test]
    fn a_workspace_root_that_resolves_to_non_utf8_bytes_is_refused_and_writes_no_row() {
        use std::os::unix::ffi::OsStrExt;

        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let parent = tempdir().unwrap();
        // `0x80` is a continuation byte with no lead, so this is a valid Unix
        // path and not valid UTF-8 — the case `to_string_lossy` absorbs.
        let real = parent.path().join(std::ffi::OsStr::from_bytes(b"ws-\x80"));
        std::fs::create_dir(&real).unwrap();
        assert!(real.to_str().is_none(), "the fixture must be non-UTF-8");
        let link = parent.path().join("bundle");
        std::os::unix::fs::symlink(&real, &link).unwrap();

        let result = open_workspace_impl(&conn, link.to_string_lossy().to_string());

        match result {
            Err(AppError::IoError(message)) => assert!(
                message.contains("UTF-8"),
                "the refusal must say why, got {message:?}"
            ),
            other => panic!("a non-UTF-8 workspace root must be refused, got {other:?}"),
        }
        let count: i64 = conn
            .query_row("SELECT count(*) FROM workspaces", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 0, "no workspaces row may be written for it");
        assert!(
            !real.join(".git").exists(),
            "a refused root must not be initialized as a repository"
        );
    }
}
