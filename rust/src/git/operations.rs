//! Programmatic Git `clone`, `commit`, `push`, and `pull` operations against a local
//! Workspace directory (ticket SYNC-C001).
//!
//! ## Verified capability split (checked 2026-07-24 against gix 0.86.0 on crates.io,
//! published 2026-07-23, and its upstream `crate-status.md`)
//!
//! `gix` (gitoxide) is used for the operations it implements robustly, and the `git` CLI
//! (available in the devenv shell; the ticket explicitly permits this) is used for the rest:
//!
//! - **clone -> gix.** `crate-status.md` lists remote `clone` (including shallow) as
//!   implemented ("usable"), and `gix::prepare_clone(..).fetch_then_checkout(..)` plus
//!   `PrepareCheckout::main_worktree(..)` is the documented, exercised path
//!   (docs.rs `gix::clone`).
//! - **commit -> gix.** `crate-status.md` lists `commit` and "low-level ref/object/index
//!   mutation" as implemented. We build the new tree with `Repository::edit_tree`
//!   (`tree-editor` feature) from blobs written via `Repository::write_blob`, then write the
//!   commit object and move the branch ref with `Repository::commit_as` (docs.rs
//!   `gix::Repository`), matching the ticket's Gherkin literally: a commit lands in the local
//!   `.git` object database and its branch ref.
//! - **push -> `git` CLI.** Upstream is unambiguous: `crate-status.md` lists `push` as
//!   entirely unimplemented for the `gix` crate ("- [ ] push") and the plumbing crates
//!   (`gix-transport`/`gix-protocol`) explicitly do not implement "send-pack / receive-pack
//!   client plumbing" or "report-status, sideband, delete-refs, push-options and atomic
//!   pushes". There is no gix API to fall back to here at all, so this ticket shells out.
//! - **pull -> `git` CLI.** `gix` implements `fetch`, but `crate-status.md`'s merge row is
//!   only partial ("merge: [x] blobs, [x] trees, [ ] commits") — there is no commit-level
//!   merge/three-way-merge-with-conflict-markers machinery in the `gix` crate today. Since
//!   `flow-conflict-resolution.md` depends on real `<<<<<<<`/`=======`/`>>>>>>>` conflict
//!   markers being left in the working tree by a failed merge, and `git merge`'s behavior
//!   here is exactly that contract, pull is implemented as `git fetch` + `git merge`
//!   (equivalent to `git pull --no-rebase`) via the CLI rather than reimplemented against
//!   partial plumbing.
//!
//! Authentication is accepted as an optional [`GitCredentials`] parameter on every operation
//! that talks to a remote, so SYNC-C002's keyring-backed OAuth token can be threaded through
//! later. No keyring integration happens in this ticket.

use crate::error::AppError;
use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use base64::Engine as _;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::AtomicBool;
use zeroize::Zeroizing;

/// Credentials for authenticating against a remote (e.g. a GitHub OAuth access token).
/// SYNC-C002 is responsible for retrieving this from `keyring`; this ticket only defines the
/// shape so that wiring point exists.
///
/// The token is wrapped in `Zeroizing` (same pattern as `security::keyring`) so it is wiped
/// from memory on drop, and `Debug` is implemented by hand to redact it: the derived `Debug`
/// would otherwise print the cleartext token in panic messages, logs, or `{:?}` output.
#[derive(Clone, Default, PartialEq, Eq)]
pub struct GitCredentials {
    /// The username to authenticate with. For GitHub token auth this is conventionally
    /// ignored by the server but must be non-empty; `"x-access-token"` is a safe default.
    pub username: String,
    /// The bearer token / personal access token / OAuth access token.
    pub token: Zeroizing<String>,
}

impl std::fmt::Debug for GitCredentials {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("GitCredentials")
            .field("username", &self.username)
            .field("token", &"***")
            .finish()
    }
}

/// Clone `url` into `dest`, checking out the default branch's worktree.
///
/// Uses `gix::prepare_clone` (see module docs). `dest` must not already exist.
pub fn clone_repo(
    url: &str,
    dest: &Path,
    credentials: Option<&GitCredentials>,
) -> Result<(), AppError> {
    let interrupt = AtomicBool::new(false);

    let mut prepare = gix::prepare_clone(url, dest).map_err(|e| classify_gix_clone_err(&e))?;

    if let Some(creds) = credentials {
        let creds = creds.clone();
        prepare = prepare.configure_connection(move |connection| {
            let creds = creds.clone();
            // The `Err` variant of `gix_credentials::protocol::Error` is dictated by the
            // `set_credentials` trait signature upstream, not by anything under our control
            // here; boxing it would change the callback's required type.
            #[allow(clippy::result_large_err)]
            connection.set_credentials(move |action| match action {
                gix::credentials::helper::Action::Get(ctx) => {
                    Ok(Some(gix::credentials::protocol::Outcome {
                        identity: gix::sec::identity::Account {
                            username: creds.username.clone(),
                            password: creds.token.to_string(),
                            oauth_refresh_token: None,
                        },
                        next: gix::credentials::helper::NextAction::from(ctx),
                    }))
                }
                gix::credentials::helper::Action::Store(_)
                | gix::credentials::helper::Action::Erase(_) => Ok(None),
            });
            Ok(())
        });
    }

    let (mut checkout, _outcome) = prepare
        .fetch_then_checkout(gix::progress::Discard, &interrupt)
        .map_err(|e| classify_gix_fetch_err(&e))?;
    checkout
        .main_worktree(gix::progress::Discard, &interrupt)
        .map_err(|e| AppError::IoError(format!("checkout after clone failed: {e}")))?;
    Ok(())
}

/// Initializes a Git repository in `dest` (ADR-005 decision 2: `init`, not `clone`), creating
/// `dest` itself if it does not yet exist. A no-op when `dest` already contains a repository —
/// reached when `open_workspace` adopts a directory the user pointed at that already has
/// history, or when `open_or_create_local_workspace`/`open_workspace` runs a second time
/// against the same Workspace directory (ADR-005 decision 8, `flow-workspace-bootstrap.md`):
/// existing history is adopted unchanged rather than re-initialized, which is what makes this
/// safe to call unconditionally on every bootstrap path.
///
/// Checked via `gix::open` first rather than a bare `.git`-directory existence check, since
/// that is the same definition of "already a repository" every other function in this module
/// uses. `gix::init` itself would otherwise fail outright the moment `.git` exists
/// (`gix_discover::repository::Path`'s `DirectoryExists` error) — there is no idempotent
/// "init or open" call on `gix`'s own surface to delegate this to.
///
/// Either way — initialized here or adopted — the bundle is left with a
/// `.gitignore` carrying `workspace::SCRATCH_IGNORE_PATTERNS`. See
/// [`ensure_scratch_ignored`] for why that has to happen on the adoption path
/// too, and for how a user's existing file is extended rather than replaced.
///
/// Returns **whether that `.gitignore` was created or extended**, because the
/// file is a write into the user's bundle that nothing here commits. Left
/// uncommitted it is an untracked (or modified) path in every `git status` the
/// user ever runs against their own bundle, forever, and it is resolved at a
/// time nobody chose by whatever commits next — a tier 3 close sweeping it into
/// a Note's commit, or a `commit_all` from a sync. The caller that owns the
/// bundle-opening flow ([`crate::workspace::bootstrap`]) records it in one
/// pathspec'd commit of its own, and only when this reports `true`: a repeat
/// open writes nothing and must therefore commit nothing.
pub fn init_repo(dest: &Path) -> Result<bool, AppError> {
    // Bootstrap's first phase, and one of the three that used to run inside a
    // `with_connection` closure — `SPK-WSPC-D001` §6.2.7's first standing rule.
    crate::db::connection::assert_no_io_under_the_connection("initializing a repository");

    if gix::open(dest).is_ok() {
        return ensure_scratch_ignored(dest);
    }

    gix::init(dest).map_err(|e| AppError::IoError(format!("init repo: {e}")))?;
    ensure_scratch_ignored(dest)
}

/// Makes sure `dest/.gitignore` excludes burlmd's own scratch files, creating
/// the file when there is none and **appending only the missing patterns** when
/// there is one.
///
/// Applied on adoption as well as on init, because the hazard is a property of
/// the bundle rather than of who created it: `commit_all` snapshots the whole
/// worktree, so a `.burlmd-trash.*` entry or an `.{name}.tmp` left behind by a
/// `SIGKILL` — the two cases where no `Drop` and no rename get to run — is
/// plaintext that the next broad commit records and a connected Remote then
/// publishes. A bundle adopted from another tool is exactly as exposed to that
/// as one this application created.
///
/// The existing file is never rewritten or reordered. It is the user's, may
/// carry patterns that matter to tools burlmd knows nothing about, and the only
/// edit made here is appending the lines that are genuinely absent.
///
/// # Why this publishes by rename
///
/// The append is composed in memory and then written through
/// [`crate::workspace::persist::atomic_write`], not `std::fs::write`. This is
/// the one write this application makes into a file the *user* owns — every
/// other write into a bundle is a Note, and every one of those already goes
/// through that call — and a truncating write is the one shape that can destroy
/// the file it is extending: `std::fs::write` opens with `O_TRUNC`, so a kill
/// (or a full disk) between the truncate and the write leaves the user's own
/// `.gitignore` empty, having lost patterns burlmd never had any business
/// touching. Publishing by rename means the previous contents stay addressable
/// until the new ones are complete and `fsync`ed. `atomic_write` also carries
/// the target's mode forward, which matters for the same reason it matters for
/// a Note: the file the user ends up with is the temporary one, so without that
/// step a restricted `.gitignore` would come back world-readable.
///
/// A `.gitignore` this call *creates* therefore lands at `atomic_write`'s
/// private creation mode rather than at the umask, which is consistent with
/// every Note this application creates rather than a special case.
///
/// Returns `true` when the file was actually created or appended to, so that
/// [`init_repo`]'s caller can commit it exactly once. See [`init_repo`].
///
/// # A symlinked `.gitignore` is left alone
///
/// Publishing by rename is what makes the append safe, and it is also what makes
/// it wrong here: a rename replaces the *link* with a regular file, so a
/// `.gitignore` the user symlinked into a dotfiles repository — the ordinary way
/// a shared ignore file is kept — would be silently detached from its source,
/// with the patterns still present but every future edit at the other end no
/// longer arriving. Resolving the link and appending through it instead means
/// writing into a file outside the bundle that the user never pointed this
/// application at, which is worse.
///
/// So the extension is declined and `false` returned, leaving the user's
/// arrangement exactly as they built it. What that gives up is only the
/// *backstop*: the scratch files this pattern list covers are swept on every
/// bootstrap ([`crate::workspace::bootstrap`]), and every commit this
/// application makes is pathspec-scoped to the Notes it touched, so a scratch
/// file reaching a commit needs the sweep to have missed it *and* a broad
/// `commit_all` to run. The creation path is unaffected — there is no link to
/// detach when there is no file.
fn ensure_scratch_ignored(dest: &Path) -> Result<bool, AppError> {
    let path = dest.join(".gitignore");
    if std::fs::symlink_metadata(&path).is_ok_and(|metadata| metadata.is_symlink()) {
        return Ok(false);
    }
    let existing = match std::fs::read_to_string(&path) {
        Ok(contents) => Some(contents),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
        Err(e) => return Err(AppError::IoError(format!("read {}: {e}", path.display()))),
    };

    let present: Vec<&str> = existing
        .as_deref()
        .unwrap_or_default()
        .lines()
        .map(str::trim)
        .collect();
    let missing: Vec<&str> = crate::workspace::SCRATCH_IGNORE_PATTERNS
        .iter()
        .copied()
        .filter(|pattern| !present.contains(pattern))
        .collect();
    if missing.is_empty() {
        return Ok(false);
    }

    let mut out = String::new();
    if let Some(contents) = &existing {
        out.push_str(contents);
        if !contents.is_empty() && !contents.ends_with('\n') {
            out.push('\n');
        }
        if !contents.is_empty() {
            out.push('\n');
        }
    }
    out.push_str("# burlmd scratch files: never bundle content, and plaintext.\n");
    for pattern in missing {
        out.push_str(pattern);
        out.push('\n');
    }
    crate::workspace::persist::atomic_write(&path, out.as_bytes())?;
    Ok(true)
}

/// Snapshot every file currently in the working tree (excluding `.git` and anything matched
/// by `.gitignore`) into a new tree object and create a commit on top of the current `HEAD`,
/// moving the branch ref forward.
///
/// Returns the new commit's hex object id.
///
/// This is a full-worktree snapshot rather than an index-diff commit: it is equivalent to
/// `git add -A && git commit`, which is the semantics the Gherkin ("a local directory with
/// changes" -> "a Git commit is created") calls for — including `git add -A`'s own real
/// behavior of skipping gitignored paths unless `-f` is given, honored here via
/// `Repository::excludes` (see `collect_files`). In particular, the new tree is built
/// starting from the *empty* tree (not the parent commit's tree) and populated only with
/// files `collect_files` currently finds in the worktree: a path that existed in the parent
/// commit but is no longer present on disk (deleted, or the source half of a rename) is
/// therefore correctly absent from the new tree, rather than surviving into it.
pub fn commit_all(
    repo_path: &Path,
    message: &str,
    author_name: &str,
    author_email: &str,
) -> Result<String, AppError> {
    let repo = gix::open(repo_path).map_err(|e| AppError::IoError(format!("open repo: {e}")))?;

    // `Repository::excludes` needs *some* `gix_index::State` to resolve id-mapped ignore
    // sources against (irrelevant here, since the default `Source` below reads `.gitignore`
    // straight off the worktree instead), so an empty index when none is present on disk yet
    // is exactly right rather than an error.
    let index = repo
        .index_or_empty()
        .map_err(|e| AppError::IoError(format!("open index: {e}")))?;
    let mut excludes = repo
        .excludes(
            &index,
            None,
            gix::worktree::stack::state::ignore::Source::default(),
        )
        .map_err(|e| AppError::IoError(format!("configure .gitignore excludes: {e}")))?;

    let mut files = Vec::new();
    collect_files(repo_path, repo_path, &mut excludes, &mut files)?;

    // Always start from the empty tree, rather than the parent commit's tree: the tree
    // editor only ever `upsert`s paths found in the worktree below, so seeding it with the
    // parent's tree would let deleted/renamed-away paths silently survive into the new
    // commit (they'd never be visited, let alone removed). Building from empty and
    // re-adding exactly what's on disk makes the result an accurate full-worktree snapshot
    // regardless of what was deleted or renamed since the parent commit.
    let empty_tree_id = gix::ObjectId::empty_tree(repo.object_hash());
    let mut editor = repo
        .edit_tree(empty_tree_id)
        .map_err(|e| AppError::IoError(format!("start tree edit: {e}")))?;

    for file in &files {
        let relative = file
            .strip_prefix(repo_path)
            .expect("file was discovered under repo_path");
        let rela_path: String = relative
            .components()
            .map(|c| c.as_os_str().to_string_lossy().into_owned())
            .collect::<Vec<_>>()
            .join("/");
        let bytes = std::fs::read(file).map_err(|e| AppError::IoError(e.to_string()))?;
        let blob_id = repo
            .write_blob(bytes)
            .map_err(|e| AppError::IoError(format!("write blob: {e}")))?;
        editor
            .upsert(rela_path.as_str(), blob_kind(file), blob_id.detach())
            .map_err(|e| AppError::IoError(format!("stage {}: {e}", relative.display())))?;
    }

    let tree_id = editor
        .write()
        .map_err(|e| AppError::IoError(format!("write tree: {e}")))?;

    let parents: Vec<gix::ObjectId> = match repo.head_id() {
        Ok(id) => vec![id.detach()],
        Err(_) => Vec::new(),
    };

    let time = gix::date::Time::now_local_or_utc();
    let signature = gix::actor::Signature {
        name: author_name.into(),
        email: author_email.into(),
        time,
    };

    let mut time_buf = gix::date::parse::TimeBuf::default();
    let signature_ref = signature.to_ref(&mut time_buf);
    let commit_id = repo
        .commit_as(
            signature_ref,
            signature_ref,
            "HEAD",
            message,
            tree_id,
            parents,
        )
        .map_err(|e| AppError::IoError(format!("write commit: {e}")))?;

    // `Repository::commit_as` only writes the commit object and moves the branch ref; it does
    // not touch `.git/index`. Without this, the on-disk index still reflects the pre-commit
    // state, so a subsequent `git merge`/`git status` (used by push/pull's `git` CLI shell-out)
    // would see phantom uncommitted changes and refuse to proceed. Rebuild the index from the
    // tree we just committed and write it back so the index and worktree agree, matching what
    // `git commit` itself does.
    let mut index_file = repo
        .index_from_tree(&tree_id)
        .map_err(|e| AppError::IoError(format!("build index from tree: {e}")))?;
    index_file
        .write(gix::index::write::Options::default())
        .map_err(|e| AppError::IoError(format!("write index: {e}")))?;

    Ok(commit_id.detach().to_string())
}

/// The identity every commit this application makes is authored and committed
/// as (ADR-008's consequences).
///
/// Deliberately **not** the user's identity and deliberately not read from
/// `user.name`/`user.email`: the local Workspace has no account, and asking
/// for one would reintroduce the onboarding step ADR-005 removed. `.invalid`
/// is reserved by RFC 2606 precisely so it can never resolve. Once a Remote is
/// attached, Epic G may set a provider identity for *subsequent* commits; it
/// must not rewrite earlier ones, since the whole point of tier 3 is that
/// history exists before any Remote does.
pub const COMMIT_AUTHOR_NAME: &str = "burlmd";
/// See [`COMMIT_AUTHOR_NAME`].
pub const COMMIT_AUTHOR_EMAIL: &str = "noreply@burlmd.invalid";

/// Commits **only** `relative_paths`, leaving every other change in the
/// working tree uncommitted. Returns the new commit's hex object id, or `None`
/// when the paths already match `HEAD` and there was therefore nothing to
/// commit.
///
/// This is ADR-008 tier 3's operation, and the reason [`commit_all`] cannot
/// serve it: a tier 3 commit covers one Note's editing session, so with two
/// Notes dirty on disk a whole-worktree snapshot would sweep both and break
/// the "approximately one commit per Note per writing session" guarantee that
/// is this design's entire justification.
///
/// Authored and committed as [`COMMIT_AUTHOR_NAME`]/[`COMMIT_AUTHOR_EMAIL`],
/// never as a value read from the user or from Git configuration — the
/// signature is passed explicitly to `Repository::commit_as`, so no
/// `~/.gitconfig` on the host can influence it.
///
/// The new tree starts from `HEAD`'s tree rather than from the empty tree,
/// which is exactly the difference from [`commit_all`]: every path not named
/// here keeps whatever `HEAD` recorded for it. A named path that is absent
/// from disk is removed from the tree, so a deletion commits as a deletion.
///
/// Returning `None` rather than writing an empty commit is load-bearing, not
/// tidiness. Opening a Note to read it and navigating away calls `close_note`,
/// which is the *most common* path through tier 3; committing unconditionally
/// would put one empty commit in history per Note visited.
///
/// # One `HEAD` snapshot, read once
///
/// The parent tree and the parent commit id come from the **same** read of
/// `HEAD`, and that is a correctness requirement rather than tidiness. They used
/// to be two reads — the tree at the top, the id just before `commit_as` — and a
/// commit landing between them produced a commit that `gix` **accepts**: the
/// reference update's compare-and-swap is `MustExistAndMatch(first parent)`
/// (`gix::Repository::commit_as`), so a *fresh* parent satisfies it while the
/// tree beneath it is still the stale one this call started from. Every path the
/// intervening commit changed and this one did not name is then silently
/// reverted to its pre-commit content, in a commit that reports success.
///
/// Reading `HEAD` once closes it by making the CAS mean what it looks like it
/// means: the parent handed to `commit_as` is the commit whose tree this one was
/// derived from, so an intervening commit fails the CAS and the operation
/// **errors** instead. Tier 3's callers already treat a failed commit stage as a
/// reportable outcome (`workspace::lifecycle`'s commit-stage reporting, and
/// `bootstrap::converge` propagates it), which is the correct answer to "the
/// bundle moved underneath this operation": retryable, and visible.
pub fn commit_paths(
    repo_path: &Path,
    message: &str,
    relative_paths: &[String],
) -> Result<Option<String>, AppError> {
    commit_paths_hooked(repo_path, message, relative_paths, || {})
}

/// [`commit_paths`] with a seam for the test that drives the torn `HEAD` window.
///
/// `after_snapshot` runs after this call has read `HEAD` and built its tree, and
/// before the commit that names that snapshot as its parent is written — which
/// is precisely the window a concurrent commit occupies. It is `|| {}`
/// everywhere but that one test, and monomorphizes away.
fn commit_paths_hooked(
    repo_path: &Path,
    message: &str,
    relative_paths: &[String],
    after_snapshot: impl FnOnce(),
) -> Result<Option<String>, AppError> {
    let repo = gix::open(repo_path).map_err(|e| AppError::IoError(format!("open repo: {e}")))?;

    // The single `HEAD` snapshot everything below is derived from: the parent
    // tree, the emptiness check, and the parent this commit claims. `None` is an
    // unborn `HEAD`, which takes the empty tree and no parent — and therefore
    // `MustNotExist` as its CAS, so a first commit racing this one fails just as
    // loudly.
    let head_id: Option<gix::ObjectId> = repo.head_id().ok().map(gix::Id::detach);
    let parent_tree_id = match head_id {
        Some(head) => repo
            .find_commit(head)
            .map_err(|e| AppError::IoError(format!("read HEAD commit: {e}")))?
            .tree_id()
            .map_err(|e| AppError::IoError(format!("read HEAD tree: {e}")))?
            .detach(),
        None => gix::ObjectId::empty_tree(repo.object_hash()),
    };
    let mut editor = repo
        .edit_tree(parent_tree_id)
        .map_err(|e| AppError::IoError(format!("start tree edit: {e}")))?;

    let mut staged: Vec<StagedPath> = Vec::with_capacity(relative_paths.len());
    for relative in relative_paths {
        let absolute = repo_path.join(relative);
        if absolute.is_file() {
            let bytes = std::fs::read(&absolute)
                .map_err(|e| AppError::IoError(format!("read {}: {e}", absolute.display())))?;
            let blob_id = repo
                .write_blob(bytes)
                .map_err(|e| AppError::IoError(format!("write blob: {e}")))?;
            let kind = blob_kind(&absolute);
            editor
                .upsert(relative.as_str(), kind, blob_id.detach())
                .map_err(|e| AppError::IoError(format!("stage {relative}: {e}")))?;
            staged.push(StagedPath {
                relative: relative.clone(),
                blob: Some((blob_id.detach(), kind)),
            });
        } else {
            editor
                .remove(relative.as_str())
                .map_err(|e| AppError::IoError(format!("unstage {relative}: {e}")))?;
            staged.push(StagedPath {
                relative: relative.clone(),
                blob: None,
            });
        }
    }

    let tree_id = editor
        .write()
        .map_err(|e| AppError::IoError(format!("write tree: {e}")))?
        .detach();
    if tree_id == parent_tree_id {
        return Ok(None);
    }

    after_snapshot();

    // The snapshot above, not a second read: see `commit_paths`.
    let parents: Vec<gix::ObjectId> = head_id.into_iter().collect();

    let signature = gix::actor::Signature {
        name: COMMIT_AUTHOR_NAME.into(),
        email: COMMIT_AUTHOR_EMAIL.into(),
        time: gix::date::Time::now_local_or_utc(),
    };
    let mut time_buf = gix::date::parse::TimeBuf::default();
    let signature_ref = signature.to_ref(&mut time_buf);
    let commit_id = repo
        .commit_as(
            signature_ref,
            signature_ref,
            "HEAD",
            message,
            tree_id,
            parents,
        )
        .map_err(|e| AppError::IoError(format!("write commit: {e}")))?;

    // Same obligation as `commit_all`: `commit_as` moves the ref without
    // touching `.git/index`, so a later `git status`/`git merge` (the CLI
    // shell-outs push and pull use) would otherwise see phantom uncommitted
    // changes for the paths just committed. Unlike `commit_all`, only the named
    // paths' entries move — see [`refresh_index_entries`].
    refresh_index_entries(&repo, &tree_id, &staged)?;

    Ok(Some(commit_id.detach().to_string()))
}

/// What one named path became in the tree [`commit_paths`] just wrote: the blob
/// it staged, with the mode it staged it under, or `None` when the path was gone
/// from disk and the commit therefore recorded a deletion.
struct StagedPath {
    relative: String,
    blob: Option<(gix::ObjectId, gix::object::tree::EntryKind)>,
}

/// Brings `.git/index` into line with a [`commit_paths`] commit by moving
/// **only the entries for the paths that commit named**, leaving every other
/// entry — and therefore everything the user has staged — exactly as it was.
///
/// # Why this is not `index_from_tree(...).write()`
///
/// It used to be, and that call does not update an index: it *replaces* one.
/// The rebuilt index is the committed tree and nothing else, so every entry the
/// user had staged and not yet committed was silently discarded — `git add A.md`
/// followed by burlmd closing a session over `B.md` left `A.md`'s staged
/// version gone from the index with no message, and `git diff --cached` empty.
/// That runs on **every** `close_note` and again at `converge`, and it is worst
/// exactly where it is least expected: an adopted repository (ADR-005 decision
/// 8) whose owner uses Git normally alongside burlmd. A bundle is the user's
/// directory and their repository; this application commits into it, and it has
/// no business rearranging their staging area to do so.
///
/// `commit_all` keeps the wholesale rebuild, and the asymmetry is deliberate:
/// it is `git add -A && git commit`, which stages the entire worktree anyway, so
/// there is nothing of the user's left for it to preserve.
///
/// # What each named path does to the index
///
/// - A path the commit **removed** takes its index entry with it, at every
///   stage, along with every entry beneath it — `commit_paths` reads a directory
///   path as a subtree removal (that is how `delete_directory` and
///   `rename_directory`'s old half are committed), and the index is flat, so the
///   subtree has to be swept by prefix here.
/// - A path the commit **staged** gets its entry's object id and mode set to
///   what was committed, and its conflict stages (1/2/3) dropped: committing a
///   path resolves it, which is what `git add` does too.
/// - A staged path's **flags are narrowed, not cleared**. Only
///   `INTENT_TO_ADD` is removed, because that is the one flag committing the
///   path genuinely retires — `git add --intent-to-add` marks an entry whose
///   content is not in the object database yet, and after this it is. Every
///   other flag on that entry was set by the user with `git update-index`:
///   `ASSUME_VALID` (`--assume-unchanged`) and `SKIP_WORKTREE`
///   (`--skip-worktree`) are deliberate instructions to Git about how to treat
///   *their* file, and they survive `git commit` in Git itself. Resetting the
///   whole word to `Flags::empty()` silently revoked both, on every
///   `close_note`, in a repository the user also uses normally (ADR-005
///   decision 8) — the same class of overreach as the wholesale index rebuild
///   above, one field down.
/// - A staged path with no entry yet is appended and the entries re-sorted,
///   since `dangerously_push_entry` breaks the ordering every later lookup by
///   path relies on.
///
/// The stat data is left zeroed rather than `lstat`ed, which is precisely what
/// `index_from_tree` produced for every entry before this and therefore is not a
/// change in behavior. Git reads a zero `sd_size` as "never stat'ed" and falls
/// back to comparing content (`read-cache.c`'s `ie_modified`), so the path reads
/// as clean when it matches and dirty when it does not. Recording a stat taken
/// *after* the bytes were read would be the unsafe direction: a write landing in
/// between would leave the index asserting the worktree is clean when it is not.
///
/// The tree-cache extension is dropped, on `gix_index::File::write`'s own
/// instruction: it is serialized as-is and is not invalidated against the
/// entries, so leaving a stale one behind would let a later `git commit` capture
/// outdated subtree content.
fn refresh_index_entries(
    repo: &gix::Repository,
    tree_id: &gix::ObjectId,
    staged: &[StagedPath],
) -> Result<(), AppError> {
    use gix::index::entry::{Flags, Mode, Stage, Stat};

    // No index file at all — a repository initialized and never staged into.
    // There is nothing of the user's to preserve, so seeding it from the tree
    // just committed is both correct and the only thing available.
    if !repo.index_path().exists() {
        let mut built = repo
            .index_from_tree(tree_id)
            .map_err(|e| AppError::IoError(format!("build index from tree: {e}")))?;
        built
            .write(gix::index::write::Options::default())
            .map_err(|e| AppError::IoError(format!("write index: {e}")))?;
        return Ok(());
    }

    let mut index = repo
        .open_index()
        .map_err(|e| AppError::IoError(format!("open index: {e}")))?;

    let removed: Vec<&[u8]> = staged
        .iter()
        .filter(|s| s.blob.is_none())
        .map(|s| s.relative.as_bytes())
        .collect();
    let updated: Vec<&[u8]> = staged
        .iter()
        .filter(|s| s.blob.is_some())
        .map(|s| s.relative.as_bytes())
        .collect();
    index.remove_entries(|_, path, entry| {
        let path: &[u8] = path;
        removed.iter().any(|r| is_at_or_under(path, r))
            || (entry.stage() != Stage::Unconflicted && updated.contains(&path))
    });

    let mut appended = false;
    for entry in staged {
        let Some((blob_id, kind)) = entry.blob else {
            continue;
        };
        let mode = if kind == gix::object::tree::EntryKind::BlobExecutable {
            Mode::FILE_EXECUTABLE
        } else {
            Mode::FILE
        };
        let path = gix::bstr::BStr::new(entry.relative.as_bytes());
        match index.entry_mut_by_path_and_stage(path, Stage::Unconflicted) {
            Some(existing) => {
                existing.id = blob_id;
                existing.mode = mode;
                existing.stat = Stat::default();
                // Only intent-to-add is cleared — see this function's
                // documentation on why the rest are the user's.
                existing.flags -= Flags::INTENT_TO_ADD;
            }
            None => {
                index.dangerously_push_entry(Stat::default(), blob_id, Flags::empty(), mode, path);
                appended = true;
            }
        }
    }
    if appended {
        index.sort_entries();
    }
    index.remove_tree();

    index
        .write(gix::index::write::Options::default())
        .map_err(|e| AppError::IoError(format!("write index: {e}")))?;
    Ok(())
}

/// Whether the index entry at `path` is the removed path `removed` itself or
/// lives beneath it. `commit_paths` names a Directory as one path and reads it
/// as a subtree removal; index entries are flat file paths, so the subtree has
/// to be recognized by prefix — and by a prefix that ends at a `/` boundary, so
/// that removing `Notes` does not also unstage `Notes-archive/a.md`.
fn is_at_or_under(path: &[u8], removed: &[u8]) -> bool {
    if path == removed {
        return true;
    }
    path.len() > removed.len()
        && path.starts_with(removed)
        && !removed.is_empty()
        && path[removed.len()] == b'/'
}

/// The tree entry kind for a regular file on disk: `100755` when it carries
/// the executable bit, `100644` otherwise.
///
/// Staging everything as `Blob` flattened the mode of every file in the
/// bundle, which undoes on the very next commit what
/// `persist::atomic_write`'s permission carry-forward preserves on disk — and
/// unlike a working-tree mode, the flattened one travels: a clone or a
/// checkout of that history hands back a script that no longer runs. A bundle
/// is an ordinary directory a user can put anything in
/// (`data-models/okf-bundle.md`), so this is not hypothetical even though
/// burlmd itself writes only Notes.
///
/// Unix only, and unconditionally so for the reason
/// [`persist::atomic_write`](crate::workspace::persist)'s permission
/// carry-forward gives: burlmd ships to desktop Linux and macOS
/// (`tech-spec/stack.md`), and Windows has no bit to read. A metadata call
/// that fails is not an error here — the bytes were already read successfully
/// — so it falls back to the ordinary mode.
#[cfg(unix)]
fn blob_kind(absolute: &Path) -> gix::object::tree::EntryKind {
    use std::os::unix::fs::PermissionsExt as _;

    let executable = std::fs::metadata(absolute)
        .map(|metadata| metadata.permissions().mode() & 0o111 != 0)
        .unwrap_or(false);
    if executable {
        gix::object::tree::EntryKind::BlobExecutable
    } else {
        gix::object::tree::EntryKind::Blob
    }
}

#[cfg(not(unix))]
fn blob_kind(_absolute: &Path) -> gix::object::tree::EntryKind {
    gix::object::tree::EntryKind::Blob
}

/// Whether `relative_path` is present in the commit `HEAD` points at — what
/// tells tier 3's generated message whether this session created the Note or
/// changed one that was already in history. `false` for an unborn `HEAD`.
pub fn path_in_head(repo_path: &Path, relative_path: &str) -> Result<bool, AppError> {
    let repo = gix::open(repo_path).map_err(|e| AppError::IoError(format!("open repo: {e}")))?;
    let tree_id = repo
        .head_tree_id_or_empty()
        .map_err(|e| AppError::IoError(format!("read HEAD tree: {e}")))?
        .detach();
    let editor = repo
        .edit_tree(tree_id)
        .map_err(|e| AppError::IoError(format!("start tree edit: {e}")))?;
    Ok(editor.get(relative_path).is_some())
}

/// Push `branch` to `remote` (a configured remote name, e.g. `"origin"`).
///
/// Shells out to `git push` (see module docs: `gix` has no push support at all).
pub fn push(
    repo_path: &Path,
    remote: &str,
    branch: &str,
    credentials: Option<&GitCredentials>,
) -> Result<(), AppError> {
    let mut cmd = git_command(repo_path);
    cmd.arg("push").arg(remote).arg(branch);
    apply_credentials(&mut cmd, credentials);

    let output = cmd
        .output()
        .map_err(|e| AppError::IoError(format!("spawn git push: {e}")))?;
    if output.status.success() {
        return Ok(());
    }
    Err(classify_git_cli_failure(&output.stderr))
}

/// Fetch and merge `branch` from `remote` into the current branch (equivalent to
/// `git pull --no-rebase`).
///
/// On a merge conflict, the working tree is left with raw `<<<<<<<`/`=======`/`>>>>>>>`
/// conflict markers (as `flow-conflict-resolution.md` requires) and `AppError::GitConflict`
/// is returned; the merge is deliberately *not* aborted, so callers must not assume the
/// working tree is clean after an `Err(GitConflict)`.
///
/// Shells out to `git fetch` + `git merge` (see module docs: `gix`'s `merge` support does not
/// yet cover commits, only blobs and trees).
pub fn pull(
    repo_path: &Path,
    remote: &str,
    branch: &str,
    credentials: Option<&GitCredentials>,
) -> Result<(), AppError> {
    let mut fetch_cmd = git_command(repo_path);
    fetch_cmd.arg("fetch").arg(remote).arg(branch);
    apply_credentials(&mut fetch_cmd, credentials);

    let fetch_output = fetch_cmd
        .output()
        .map_err(|e| AppError::IoError(format!("spawn git fetch: {e}")))?;
    if !fetch_output.status.success() {
        return Err(classify_git_cli_failure(&fetch_output.stderr));
    }

    let merge_output = git_command(repo_path)
        .arg("merge")
        .arg("--no-edit")
        .arg(format!("{remote}/{branch}"))
        .output()
        .map_err(|e| AppError::IoError(format!("spawn git merge: {e}")))?;

    if merge_output.status.success() {
        return Ok(());
    }

    let combined = [
        merge_output.stdout.as_slice(),
        merge_output.stderr.as_slice(),
    ]
    .concat();
    let text = String::from_utf8_lossy(&combined);
    if text.contains("CONFLICT") || text.contains("Automatic merge failed") {
        return Err(AppError::GitConflict);
    }
    Err(classify_git_cli_failure(&merge_output.stderr))
}

/// Recursively collect every regular file under `dir`, skipping the top-level `.git`
/// directory and anything matched by `.gitignore` (checked via `excludes`, a `gix`
/// exclude-stack cache built once in `commit_all` and threaded through recursive calls so
/// per-directory `.gitignore` files are only parsed once each rather than per file).
///
/// A whole directory that matches `.gitignore` is pruned rather than recursed into, so a
/// pattern like `build/` correctly skips everything underneath it too, not just a literal
/// `build` entry.
fn collect_files(
    root: &Path,
    dir: &Path,
    excludes: &mut gix::AttributeStack<'_>,
    out: &mut Vec<PathBuf>,
) -> Result<(), AppError> {
    for entry in std::fs::read_dir(dir).map_err(|e| AppError::IoError(e.to_string()))? {
        let entry = entry.map_err(|e| AppError::IoError(e.to_string()))?;
        let path = entry.path();
        let file_type = entry
            .file_type()
            .map_err(|e| AppError::IoError(e.to_string()))?;
        if path.file_name().map(|n| n == ".git").unwrap_or(false) && path.parent() == Some(root) {
            continue;
        }

        let relative = path
            .strip_prefix(root)
            .expect("entry was discovered under root");
        let mode = if file_type.is_dir() {
            gix::index::entry::Mode::DIR
        } else {
            gix::index::entry::Mode::FILE
        };
        let is_excluded = excludes
            .at_path(relative, Some(mode))
            .map_err(|e| {
                AppError::IoError(format!(
                    "check .gitignore exclusion for {}: {e}",
                    relative.display()
                ))
            })?
            .is_excluded();
        if is_excluded {
            continue;
        }

        if file_type.is_dir() {
            collect_files(root, &path, excludes, out)?;
        } else if file_type.is_file() {
            out.push(path);
        }
    }
    Ok(())
}

/// Deterministic author/committer identity injected into every `git` CLI invocation's
/// environment by [`git_command`] (`GIT_AUTHOR_NAME`/`GIT_AUTHOR_EMAIL` +
/// `GIT_COMMITTER_NAME`/`GIT_COMMITTER_EMAIL`).
///
/// `pull`'s `git merge --no-edit` creates a real merge commit whenever the fetched history
/// and the local history have both diverged and merge cleanly (i.e. neither side is a
/// fast-forward of the other) — see `reindex_failure_on_a_clean_auto_merge_is_not_masked` in
/// `sync::scheduler` for exactly that shape. Unlike `commit_all`, `git merge` is `git`'s own
/// CLI machinery, not our tree-editor code, so it has no caller-supplied name/email to draw
/// on; it falls back to reading `user.name`/`user.email` out of git config, which is
/// unconfigured on a fresh production machine (nothing in this app's install/setup path ever
/// runs `git config --global user.name`). Without an identity, that `git merge` invocation
/// fails outright with "fatal: unable to auto-detect email address" /
/// "Committer identity unknown", which `flow-sync-push.md`'s pull-then-merge step depends on
/// succeeding. Setting these four env vars gives every CLI-driven `git` invocation in this
/// module a deterministic identity that never depends on host git config, matching in shape
/// (a plain name/email pair) how `commit_all` builds its own `gix::actor::Signature` from an
/// explicit name/email a few lines above — the difference is that `commit_all`'s identity is
/// always supplied by its caller (there is no fixed default to literally copy), while a
/// `git merge` auto-merge commit has no caller-facing "author" of its own at all, so it is
/// attributed to the app itself rather than to whichever user happened to trigger the sync.
/// Applying the same env vars to `fetch`/`push` too is harmless (they never read identity) and
/// keeps every call in this module going through one consistently-configured builder.
const CLI_IDENTITY_NAME: &str = "BurlMD";
const CLI_IDENTITY_EMAIL: &str = "sync@burlmd.app";

/// Builds a `git` CLI [`Command`] rooted at `workdir` with the settings every `git` CLI
/// invocation in this module needs, and MUST be the single entry point every such invocation
/// goes through: no stdin (so a `git` that would otherwise prompt interactively fails fast
/// instead of hanging), stdout/stderr piped for capture, `LC_ALL=C` pinned in the child's
/// environment, `GIT_TERMINAL_PROMPT=0` to kill any remaining interactive-prompt path (stdin
/// being `/dev/null` already stops most of these; some `git` builds' credential-helper prompts
/// go through a pty instead of stdin, which `GIT_TERMINAL_PROMPT=0` closes off too), a fixed
/// author/committer identity (see [`CLI_IDENTITY_NAME`]/[`CLI_IDENTITY_EMAIL`] above), and
/// `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` pointed at `/dev/null` so none of this — the
/// identity included — can be silently overridden by whatever `~/.gitconfig` or `/etc/gitconfig`
/// happens to exist on the machine this runs on. That last point is also what makes this
/// module's own test suite deterministic: without it, a developer or CI machine that *does*
/// have a global git identity configured (as most developer machines do) would mask the exact
/// "no identity configured" failure this module needs to handle, the way it did until this was
/// added — see `pull_auto_merges_with_no_git_identity_configured_anywhere` below.
///
/// `LC_ALL=C` is not optional politeness: `classify_git_cli_failure` below classifies outcomes
/// by substring-matching *English* fragments of `git`'s own stderr (`"non-fast-forward"`,
/// `"CONFLICT"`, `"Authentication failed"`, etc.). `git` localizes that stderr via gettext
/// according to `LC_ALL`/`LC_MESSAGES`/`LANG` (POSIX precedence, in that order), so a `git`
/// invoked while inheriting a non-English locale from this process's environment (e.g. a
/// contributor's machine running under `LANG=es_ES.UTF-8`) would otherwise silently misroute a
/// real non-fast-forward push into `AppError::IoError`, skipping the entire fetch+merge
/// conflict flow `flow-sync-push.md` and `flow-conflict-resolution.md` depend on. `LC_ALL`
/// overrides both `LANG` and `LC_MESSAGES` when set, so pinning only `LC_ALL` here is
/// sufficient to force `git`'s stderr back to the C-locale (English) text the classifier
/// depends on, regardless of what the host process's own locale is.
fn git_command(workdir: &Path) -> Command {
    let mut cmd = Command::new("git");
    cmd.current_dir(workdir)
        .env("LC_ALL", "C")
        .env("GIT_TERMINAL_PROMPT", "0")
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_CONFIG_SYSTEM", "/dev/null")
        .env("GIT_AUTHOR_NAME", CLI_IDENTITY_NAME)
        .env("GIT_AUTHOR_EMAIL", CLI_IDENTITY_EMAIL)
        .env("GIT_COMMITTER_NAME", CLI_IDENTITY_NAME)
        .env("GIT_COMMITTER_EMAIL", CLI_IDENTITY_EMAIL)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    cmd
}

/// Inject HTTP(S) auth (if any) into a `git` CLI invocation without putting the token on the
/// command line (where it would be visible via `/proc/<pid>/cmdline` / `ps`). Uses git's
/// environment-variable config-injection mechanism (`GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n`/
/// `GIT_CONFIG_VALUE_n`, supported since Git 2.31) to set a one-shot `http.extraHeader`.
///
/// The `user:token` pair and the base64-encoded header value are both wrapped in `Zeroizing`
/// so *this process's* copies are wiped on drop (same discipline as `GitCredentials::token`
/// itself). That said, the wipe is necessarily partial: `Command::env` copies the value into
/// the `Command`'s own internal env map immediately, and the OS copies it again into the
/// child process's env block at spawn time — neither of those copies is reachable to zero.
/// The token surviving un-wiped in the child process's environment for the lifetime of that
/// process is therefore a conscious, accepted bound of authenticating via `git`'s CLI env
/// mechanism at all, not something this function can close.
fn apply_credentials(cmd: &mut Command, credentials: Option<&GitCredentials>) {
    // The `Command` inherits this process's own environment, which may already carry an
    // injected `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n` sequence (e.g.
    // from a wrapper this binary itself was launched under). Unconditionally starting our
    // own entry at index 0 with `GIT_CONFIG_COUNT=1` would silently discard or mis-index
    // whatever was already there; append after it instead.
    apply_credentials_after(cmd, credentials, existing_git_config_count());
}

/// [`apply_credentials`] with the inherited entry count **passed in** rather than read from
/// the process environment.
///
/// The split exists for the two tests that cover the appending behavior, and it is a real
/// bug fix rather than a testing convenience. Those tests used to establish their fixture by
/// `std::env::set_var`ing `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0`/`GIT_CONFIG_VALUE_0` into the
/// *process* environment, holding `db::connection::ENV_LOCK` — a lock that, as the comment
/// above them said in as many words, deliberately does not cover the many other tests in this
/// crate that spawn a real `git` child. But `git` reads that sequence out of the environment
/// it inherits at `fork`/`exec`, and the three variables cannot be set atomically: any `git`
/// spawned in the window after `GIT_CONFIG_COUNT=1` and before `GIT_CONFIG_VALUE_0` exists
/// dies with `error: missing config value for GIT_CONFIG_VALUE_0`. That is a `git init` in
/// another test thread failing for reasons that have nothing to do with what it is testing,
/// which is exactly the intermittent failure this crate had been carrying as "a rare flake".
///
/// Reading the count once, at the one place that needs it, means the tests can pass the
/// fixture as an argument and mutate nothing process-wide.
fn apply_credentials_after(
    cmd: &mut Command,
    credentials: Option<&GitCredentials>,
    inherited_entries: usize,
) {
    if let Some(creds) = credentials {
        let user_pass = Zeroizing::new(format!("{}:{}", creds.username, creds.token.as_str()));
        let basic = Zeroizing::new(BASE64_STANDARD.encode(user_pass.as_bytes()));
        let header_value = Zeroizing::new(format!("Authorization: Basic {}", basic.as_str()));
        let index = inherited_entries;
        cmd.env("GIT_CONFIG_COUNT", (index + 1).to_string());
        cmd.env(format!("GIT_CONFIG_KEY_{index}"), "http.extraheader");
        cmd.env(format!("GIT_CONFIG_VALUE_{index}"), header_value.as_str());
    }
}

/// How many `GIT_CONFIG_COUNT`-style entries are already present in *this process's own*
/// environment (i.e. what the spawned `git` child would inherit before `apply_credentials`
/// adds its own), so that entry can be appended after them rather than clobbering index 0.
/// Absent or unparseable is treated as zero, matching `git`'s own behavior for a missing
/// `GIT_CONFIG_COUNT`.
fn existing_git_config_count() -> usize {
    std::env::var("GIT_CONFIG_COUNT")
        .ok()
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(0)
}

/// Classifies a failed `git` CLI invocation's stderr by substring-matching known English
/// fragments of `git`'s own diagnostic text. This depends entirely on that stderr actually
/// being in the C locale (English) — every call site in this module must build its `Command`
/// via [`git_command`], which pins `LC_ALL=C` for exactly this reason (see its doc comment);
/// calling this against stderr captured from a `git` invocation that inherited a different
/// `LANG`/`LC_MESSAGES` would silently misclassify real conflicts/auth failures as a generic
/// `IoError`.
fn classify_git_cli_failure(stderr: &[u8]) -> AppError {
    let text = String::from_utf8_lossy(stderr);
    let lower = text.to_lowercase();
    if lower.contains("non-fast-forward")
        || lower.contains("fetch first")
        || lower.contains("conflict")
    {
        AppError::GitConflict
    } else if lower.contains("authentication failed")
        || lower.contains("invalid credentials")
        || lower.contains("invalid username or password")
        || lower.contains("bad credentials")
        || lower.contains("permission denied")
        || lower.contains("access denied")
        || lower.contains("error: 401")
        || lower.contains("error: 403")
        || lower.contains("returned error: 401")
        || lower.contains("returned error: 403")
        || lower.contains("http basic: access denied")
        || lower.contains("support for password authentication was removed")
    {
        // Checked ahead of the generic network-error branch below: git's own auth-failure
        // stderr (`fatal: Authentication failed for '...'`, an HTTP 401/403 status line, an
        // SSH `Permission denied (publickey)`, etc.) also often contains phrases like
        // "unable to access" that would otherwise be caught by the network branch — this
        // ordering makes sure a stale/invalid credential is reported distinctly as
        // `AuthExpired`, matching `tech-spec/contracts/ffi_api.rs`'s dedicated variant for
        // exactly this case, rather than being misclassified as a transient `NetworkError`
        // the scheduler would otherwise retry forever with backoff.
        AppError::AuthExpired
    } else if lower.contains("could not resolve host")
        || lower.contains("could not read from remote repository")
        || lower.contains("connection refused")
        || lower.contains("connection timed out")
        || lower.contains("unable to access")
        || lower.contains("network")
    {
        AppError::NetworkError(text.trim().to_string())
    } else {
        AppError::IoError(text.trim().to_string())
    }
}

fn classify_gix_clone_err(err: &gix::clone::Error) -> AppError {
    AppError::IoError(format!("prepare clone: {err}"))
}

fn classify_gix_fetch_err(err: &gix::clone::fetch::Error) -> AppError {
    let text = err.to_string();
    let lower = text.to_lowercase();
    if lower.contains("could not resolve") || lower.contains("connect") || lower.contains("i/o") {
        AppError::NetworkError(text)
    } else {
        AppError::IoError(text)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{git, init_bare, init_repo};
    use std::process::Command as StdCommand;
    use tempfile::tempdir;

    /// WSPC-D004: `init_repo` creates a directory that does not exist yet and initializes a
    /// Git repository in it (ADR-005 decision 2/decision 1, "creates the directory when
    /// absent, initializes a version-controlled repository in place").
    #[test]
    fn init_repo_creates_the_directory_and_a_repository_when_neither_exists() {
        let parent = tempdir().unwrap();
        let dest = parent.path().join("workspace");
        assert!(!dest.exists());

        super::init_repo(&dest).expect("init_repo should succeed against a nonexistent directory");

        assert!(dest.is_dir());
        assert!(dest.join(".git").is_dir());
    }

    /// The point of the `.gitignore` `init_repo` writes: `commit_all` is a
    /// **whole-worktree** snapshot, so a scratch file left inside the bundle by
    /// a `SIGKILL` — a `.burlmd-trash.*` entry holding a deleted Note's entire
    /// content, or an `.{name}.tmp` holding a Note mid-write — would otherwise
    /// be committed as plaintext by the next commit, and pushed by the next
    /// sync. Asserted against a real commit rather than against the file's
    /// text, since what matters is `gix`'s reading of the patterns rather than
    /// their spelling.
    #[test]
    fn scratch_files_a_kill_left_behind_are_never_committed() {
        let dir = tempdir().unwrap();
        super::init_repo(dir.path()).unwrap();
        std::fs::create_dir_all(dir.path().join("projects")).unwrap();
        std::fs::write(dir.path().join("Kept.md"), b"a real Note\n").unwrap();
        std::fs::write(
            dir.path().join(".burlmd-trash.Deleted.md.4242.0"),
            b"the whole content of a deleted Note\n",
        )
        .unwrap();
        std::fs::write(
            dir.path().join("projects/.Nested.md.4242.0.tmp"),
            b"a Note as it was mid-write\n",
        )
        .unwrap();

        commit_all(dir.path(), "snapshot", "Test User", "test@example.com").unwrap();

        let tracked = StdCommand::new("git")
            .args(["ls-tree", "-r", "--name-only", "HEAD"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        let tracked = String::from_utf8_lossy(&tracked.stdout);
        let mut paths: Vec<&str> = tracked.lines().collect();
        paths.sort_unstable();
        assert_eq!(
            paths,
            vec![".gitignore", "Kept.md"],
            "no scratch file may reach a commit"
        );
    }

    /// The `.gitignore` append is the only write this application makes into a
    /// file the **user** owns, and it was the only one not going through
    /// `persist::atomic_write`: a `std::fs::write` truncates in place, so a kill
    /// between the truncate and the write left the user's own `.gitignore`
    /// empty — on the adoption path, where the file is theirs and may carry
    /// patterns burlmd knows nothing about (this function's own documentation
    /// promises it is "never rewritten or reordered").
    ///
    /// Asserted by **inode identity**, which is what tells the two shapes
    /// apart: a truncating write keeps the target's inode, while publishing by
    /// rename replaces it — so the previous contents are addressable until the
    /// instant the new ones are complete and durable. The mode assertion is the
    /// second half of routing through that call rather than a second concern:
    /// `carry_permissions_forward` is what keeps a rename from silently
    /// widening a file the user had restricted.
    #[cfg(unix)]
    #[test]
    fn extending_the_users_gitignore_publishes_by_rename_rather_than_truncating_it() {
        use std::os::unix::fs::{MetadataExt, PermissionsExt};

        let dir = tempdir().unwrap();
        let path = dir.path().join(".gitignore");
        std::fs::write(&path, "*.pdf\ndrafts/\n").unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).unwrap();
        let before = std::fs::metadata(&path).unwrap().ino();

        assert!(
            super::init_repo(dir.path()).unwrap(),
            "the patterns were absent, so this open must report having written them"
        );

        let after = std::fs::metadata(&path).unwrap();
        assert_ne!(
            before,
            after.ino(),
            "the .gitignore was written in place, so a kill mid-write would empty it"
        );
        assert_eq!(
            after.permissions().mode() & 0o777,
            0o600,
            "the rename replaced the mode the user chose"
        );
        let contents = std::fs::read_to_string(&path).unwrap();
        assert!(
            contents.starts_with("*.pdf\ndrafts/\n"),
            "the user's own patterns must survive verbatim, got {contents:?}"
        );

        let leftovers: Vec<String> = std::fs::read_dir(dir.path())
            .unwrap()
            .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
            .filter(|name| name.ends_with(".tmp"))
            .collect();
        assert!(
            leftovers.is_empty(),
            "the publishing rename left a temporary file behind: {leftovers:?}"
        );
    }

    /// A `.gitignore` the user symlinked — into a dotfiles repository, say —
    /// survives adoption as a symlink, and the file it points at is not written
    /// either.
    ///
    /// The defect this pins: the append publishes by rename, and a rename over a
    /// symlink replaces the *link* with a regular file. Adopting such a bundle
    /// would have detached the user's shared ignore file from its source
    /// silently, leaving the patterns in place but every later edit at the other
    /// end no longer arriving. Declining costs only the backstop; see
    /// `ensure_scratch_ignored`.
    #[cfg(unix)]
    #[test]
    fn a_symlinked_gitignore_is_left_as_a_symlink_and_its_target_untouched() {
        let dir = tempdir().unwrap();
        let elsewhere = tempdir().unwrap();
        let target = elsewhere.path().join("shared-gitignore");
        std::fs::write(&target, "*.pdf\n").unwrap();
        let link = dir.path().join(".gitignore");
        std::os::unix::fs::symlink(&target, &link).unwrap();

        assert!(
            !super::init_repo(dir.path()).unwrap(),
            "nothing was written, so this open must report nothing to commit"
        );

        assert!(
            std::fs::symlink_metadata(&link).unwrap().is_symlink(),
            "the publishing rename replaced the user's symlink with a regular file"
        );
        assert_eq!(
            std::fs::read_link(&link).unwrap(),
            target,
            "the link now points somewhere else"
        );
        assert_eq!(
            std::fs::read_to_string(&target).unwrap(),
            "*.pdf\n",
            "the file at the other end of the link was written through"
        );
    }

    /// WSPC-D004 / ADR-005 decision 8: a directory of files this application did not create,
    /// with no version history, gets a repository initialized in it rather than being left
    /// unable to accumulate any (`close_note`'s tier 3 commit would otherwise have nothing to
    /// commit into).
    #[test]
    fn init_repo_initializes_in_a_nonempty_directory_with_no_history() {
        let dir = tempdir().unwrap();
        std::fs::write(
            dir.path().join("existing.md"),
            b"a note this app did not write\n",
        )
        .unwrap();

        super::init_repo(dir.path()).expect("init_repo should succeed against a foreign directory");

        assert!(dir.path().join(".git").is_dir());
        // The file the user already had must be left completely untouched.
        let contents = std::fs::read_to_string(dir.path().join("existing.md")).unwrap();
        assert_eq!(contents, "a note this app did not write\n");
    }

    /// WSPC-D004 / ADR-005 decision 8: when the directory already has version history,
    /// `init_repo` must adopt it unchanged rather than re-initializing (which would either
    /// error against an existing `.git`, or — worse, if it silently succeeded — discard it).
    #[test]
    fn init_repo_is_a_noop_and_adopts_history_when_a_repository_already_exists() {
        let dir = tempdir().unwrap();
        super::init_repo(dir.path()).unwrap();
        std::fs::write(dir.path().join("a.md"), b"a\n").unwrap();
        let first_commit =
            commit_all(dir.path(), "first", "Test User", "test@example.com").unwrap();

        super::init_repo(dir.path()).expect("a second init_repo call must not fail");

        let head = StdCommand::new("git")
            .args(["rev-parse", "HEAD"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        assert_eq!(
            String::from_utf8_lossy(&head.stdout).trim(),
            first_commit,
            "existing history must be adopted unchanged, not reinitialized"
        );
    }

    /// ADR-008 tier 3: a commit covers one Note's editing session, so with two
    /// Notes dirty on disk, closing one must not sweep both.
    #[test]
    fn commit_paths_commits_only_the_named_path() {
        let dir = tempdir().unwrap();
        init_repo(dir.path());
        std::fs::write(dir.path().join("a.md"), b"a first\n").unwrap();
        std::fs::write(dir.path().join("b.md"), b"b first\n").unwrap();
        commit_all(dir.path(), "baseline", "Test User", "test@example.com").unwrap();

        std::fs::write(dir.path().join("a.md"), b"a second\n").unwrap();
        std::fs::write(dir.path().join("b.md"), b"b second\n").unwrap();
        let commit = commit_paths(dir.path(), "just a", &["a.md".to_string()])
            .unwrap()
            .expect("a changed path must produce a commit");

        assert_eq!(commit.len(), 40, "expected a sha1 hex object id");
        let changed = StdCommand::new("git")
            .args(["show", "--name-only", "--format=", "HEAD"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        assert_eq!(String::from_utf8_lossy(&changed.stdout).trim(), "a.md");
        let committed_b = StdCommand::new("git")
            .args(["show", "HEAD:b.md"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        assert_eq!(
            String::from_utf8_lossy(&committed_b.stdout),
            "b first\n",
            "the other Note's working-tree change was swept in"
        );
    }

    /// A tier 3 commit updates the index entries for the paths it committed and
    /// **nothing else** — the user's own staging area survives it untouched.
    ///
    /// The regression this pins: the index was brought up to date with
    /// `index_from_tree(&tree_id).write()`, which does not update an index but
    /// replaces one. Everything the user had staged and not yet committed was
    /// discarded, silently, on every `close_note` and again at `converge` — so
    /// `git add A.md` followed by burlmd closing a session over an unrelated
    /// `B.md` left `git diff --cached` empty and A.md's staged version gone. A
    /// bundle is the user's own repository (ADR-005 decision 8 adopts existing
    /// ones); this application has no business rearranging their staging area to
    /// commit into it.
    #[test]
    fn commit_paths_leaves_the_users_own_staged_changes_alone() {
        let dir = tempdir().unwrap();
        init_repo(dir.path());
        std::fs::write(dir.path().join("a.md"), b"a first\n").unwrap();
        std::fs::write(dir.path().join("b.md"), b"b first\n").unwrap();
        commit_all(dir.path(), "baseline", "Test User", "test@example.com").unwrap();

        // The user stages a change of their own and has not committed it yet.
        std::fs::write(dir.path().join("a.md"), b"a staged by the user\n").unwrap();
        git(dir.path(), &["add", "a.md"]);

        // burlmd closes a session over an entirely different Note.
        std::fs::write(dir.path().join("b.md"), b"b second\n").unwrap();
        commit_paths(dir.path(), "just b", &["b.md".to_string()])
            .unwrap()
            .expect("a changed path must produce a commit");

        let staged = StdCommand::new("git")
            .args(["diff", "--cached", "--name-only"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        assert_eq!(
            String::from_utf8_lossy(&staged.stdout).trim(),
            "a.md",
            "the user's staged change was wiped out of the index"
        );
        let staged_bytes = StdCommand::new("git")
            .args(["show", ":a.md"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        assert_eq!(
            String::from_utf8_lossy(&staged_bytes.stdout),
            "a staged by the user\n",
            "the staged version must be exactly what the user staged"
        );
        // The committed path itself still has to read as clean, which is the
        // whole reason the index is touched at all.
        let status = StdCommand::new("git")
            .args(["status", "--porcelain"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        assert_eq!(
            String::from_utf8_lossy(&status.stdout).trim(),
            "M  a.md",
            "the committed path must be clean and only the user's own change staged"
        );
    }

    /// The same obligation one field further in: the index **flags** the user
    /// set on a path with `git update-index` survive a burlmd commit over it.
    ///
    /// The regression this pins: the entry's whole flag word was reset to
    /// `Flags::empty()`, which silently revoked `--assume-unchanged`
    /// (`ASSUME_VALID`) and `--skip-worktree` (`SKIP_WORKTREE`) on any path a
    /// tier 3 commit named. Both are deliberate instructions the user gave Git
    /// about how to treat their own file — `--skip-worktree` in particular is
    /// how a tracked local config is kept out of every diff — and both survive
    /// `git commit` in Git itself. A bundle is the user's repository (ADR-005
    /// decision 8 adopts existing ones), so revoking them on every `close_note`
    /// is the same overreach as rebuilding their staging area, one field down.
    ///
    /// Only `INTENT_TO_ADD` is cleared, and that one really is retired by
    /// committing: it marks an entry whose content is not in the object database
    /// yet, and after the commit it is.
    #[test]
    fn commit_paths_preserves_the_index_flags_the_user_set_with_update_index() {
        use gix::index::entry::Flags;

        let dir = tempdir().unwrap();
        init_repo(dir.path());
        std::fs::write(dir.path().join("assumed.md"), b"assumed first\n").unwrap();
        std::fs::write(dir.path().join("skipped.md"), b"skipped first\n").unwrap();
        commit_all(dir.path(), "baseline", "Test User", "test@example.com").unwrap();

        git(
            dir.path(),
            &["update-index", "--assume-unchanged", "assumed.md"],
        );
        git(
            dir.path(),
            &["update-index", "--skip-worktree", "skipped.md"],
        );

        std::fs::write(dir.path().join("assumed.md"), b"assumed second\n").unwrap();
        std::fs::write(dir.path().join("skipped.md"), b"skipped second\n").unwrap();
        commit_paths(
            dir.path(),
            "close a session over both",
            &["assumed.md".to_string(), "skipped.md".to_string()],
        )
        .unwrap()
        .expect("both paths changed");

        // Asserted through `git` itself, which is the reader that has to agree:
        // `ls-files -v` prints `h` for assume-unchanged and `S` for
        // skip-worktree, and `H` for an ordinary entry.
        let listed = StdCommand::new("git")
            .args(["ls-files", "-v"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        let listed = String::from_utf8_lossy(&listed.stdout);
        let mut lines: Vec<&str> = listed.lines().collect();
        lines.sort_unstable();
        assert_eq!(
            lines,
            vec!["S skipped.md", "h assumed.md"],
            "the flags the user set with `git update-index` were revoked by a commit"
        );

        // And in the index this crate reads back, so the bits are really there
        // rather than merely printed.
        let repo = gix::open(dir.path()).unwrap();
        let index = repo.open_index().unwrap();
        let flags = |path: &str| {
            index
                .entry_by_path(gix::bstr::BStr::new(path.as_bytes()))
                .expect("the committed path must still have an entry")
                .flags
        };
        assert!(flags("assumed.md").contains(Flags::ASSUME_VALID));
        assert!(flags("skipped.md").contains(Flags::SKIP_WORKTREE));
        assert!(!flags("assumed.md").contains(Flags::INTENT_TO_ADD));
        assert!(!flags("skipped.md").contains(Flags::INTENT_TO_ADD));
    }

    /// The other half of the same obligation: a commit that *removes* a
    /// Directory has to take every index entry beneath it, not just an entry
    /// spelled exactly like the Directory (the index is flat, and holds none).
    #[test]
    fn commit_paths_unstages_the_whole_subtree_a_directory_removal_committed() {
        let dir = tempdir().unwrap();
        init_repo(dir.path());
        std::fs::create_dir_all(dir.path().join("doomed")).unwrap();
        std::fs::write(dir.path().join("doomed/a.md"), b"a\n").unwrap();
        std::fs::write(dir.path().join("doomed-kept.md"), b"kept\n").unwrap();
        commit_all(dir.path(), "baseline", "Test User", "test@example.com").unwrap();

        std::fs::remove_dir_all(dir.path().join("doomed")).unwrap();
        commit_paths(dir.path(), "delete the directory", &["doomed".to_string()])
            .unwrap()
            .expect("a removal is a change");

        let status = StdCommand::new("git")
            .args(["status", "--porcelain"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        assert_eq!(
            String::from_utf8_lossy(&status.stdout).trim(),
            "",
            "the removed subtree's index entries were left behind"
        );
        let tracked = StdCommand::new("git")
            .args(["ls-files"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        let listing = String::from_utf8_lossy(&tracked.stdout);
        let mut paths: Vec<&str> = listing.lines().collect();
        paths.sort_unstable();
        assert_eq!(
            paths,
            vec!["doomed-kept.md"],
            "a sibling sharing the removed Directory's name prefix was unstaged too"
        );
    }

    /// The most common path through tier 3 is a Note that was read and not
    /// changed. One empty commit per Note visited would destroy the readable
    /// history the design exists to produce.
    #[test]
    fn commit_paths_makes_no_commit_when_the_path_already_matches_head() {
        let dir = tempdir().unwrap();
        init_repo(dir.path());
        std::fs::write(dir.path().join("a.md"), b"a\n").unwrap();
        let baseline = commit_all(dir.path(), "baseline", "Test User", "test@example.com").unwrap();

        let commit = commit_paths(dir.path(), "nothing changed", &["a.md".to_string()]).unwrap();

        assert_eq!(commit, None);
        let head = StdCommand::new("git")
            .args(["rev-parse", "HEAD"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        assert_eq!(String::from_utf8_lossy(&head.stdout).trim(), baseline);
    }

    /// A commit landing between this call's `HEAD` snapshot and its own write
    /// must make the write **fail**, not silently revert it.
    ///
    /// The defect this pins: the parent tree was read at the top of
    /// `commit_paths` and the parent commit id near the bottom, so a commit
    /// landing between the two produced a commit `gix` **accepts** — the
    /// reference update's compare-and-swap is `MustExistAndMatch(first parent)`,
    /// and the parent was re-read fresh, so it matched — carrying a tree derived
    /// from the *stale* snapshot. Every path the intervening commit touched and
    /// this one did not name was reverted to its pre-commit content, in a commit
    /// that reported success and that nothing downstream had any reason to
    /// question. Two lifecycle operations racing, or a lifecycle commit racing a
    /// sync's `commit_all`, is enough to reach it.
    ///
    /// Deterministic rather than timing-dependent: the intervening commit is
    /// driven *through* the window by the seam
    /// [`commit_paths_hooked`] exists for, so the interleaving is the one the
    /// test names rather than one a scheduler might produce.
    ///
    /// The second half is the other obligation — the failure is a refusal, not a
    /// dead end. Once the window is closed the same commit retries and lands,
    /// with the intervening commit's work intact underneath it.
    #[test]
    fn a_commit_landing_inside_the_head_window_is_refused_rather_than_reverting_it() {
        let dir = tempdir().unwrap();
        init_repo(dir.path());
        std::fs::write(dir.path().join("a.md"), b"a first\n").unwrap();
        std::fs::write(dir.path().join("b.md"), b"b first\n").unwrap();
        commit_all(dir.path(), "baseline", "Test User", "test@example.com").unwrap();
        let baseline = head_of(dir.path());

        // burlmd's commit, closing a session over `a.md`.
        std::fs::write(dir.path().join("a.md"), b"a second\n").unwrap();

        let landed = std::cell::Cell::new(None);
        let result = super::commit_paths_hooked(
            dir.path(),
            "close the session over a",
            &["a.md".to_string()],
            || {
                // Somebody else's commit, entirely inside the window.
                std::fs::write(dir.path().join("b.md"), b"b second\n").unwrap();
                git(dir.path(), &["add", "b.md"]);
                git(dir.path(), &["commit", "-q", "-m", "someone else's commit"]);
                landed.set(Some(head_of(dir.path())));
            },
        );

        let landed = landed.into_inner().expect("the window hook must have run");
        assert_ne!(landed, baseline, "the fixture's own commit did not land");
        assert!(
            result.is_err(),
            "a commit derived from a stale HEAD was accepted: {result:?}"
        );
        assert_eq!(
            head_of(dir.path()),
            landed,
            "the branch moved despite the compare-and-swap"
        );
        assert_eq!(
            git_show(dir.path(), "HEAD:b.md"),
            "b second\n",
            "the intervening commit's work was reverted by a commit that reported success"
        );

        // Retryable: with the window closed, the same commit lands and keeps the
        // other one's work.
        commit_paths(
            dir.path(),
            "close the session over a",
            &["a.md".to_string()],
        )
        .unwrap()
        .expect("the retry must commit");
        assert_eq!(git_show(dir.path(), "HEAD:a.md"), "a second\n");
        assert_eq!(git_show(dir.path(), "HEAD:b.md"), "b second\n");
    }

    fn head_of(dir: &Path) -> String {
        let output = StdCommand::new("git")
            .args(["rev-parse", "HEAD"])
            .current_dir(dir)
            .output()
            .unwrap();
        String::from_utf8_lossy(&output.stdout).trim().to_string()
    }

    fn git_show(dir: &Path, spec: &str) -> String {
        let output = StdCommand::new("git")
            .args(["show", spec])
            .current_dir(dir)
            .output()
            .unwrap();
        String::from_utf8_lossy(&output.stdout).into_owned()
    }

    /// A named path that is gone from disk commits as a deletion, which is what
    /// makes deletion recoverable from local history (CAP-LIFE-04).
    #[test]
    fn commit_paths_records_a_deletion_for_a_path_no_longer_on_disk() {
        let dir = tempdir().unwrap();
        init_repo(dir.path());
        std::fs::write(dir.path().join("a.md"), b"a\n").unwrap();
        std::fs::write(dir.path().join("b.md"), b"b\n").unwrap();
        commit_all(dir.path(), "baseline", "Test User", "test@example.com").unwrap();

        std::fs::remove_file(dir.path().join("a.md")).unwrap();
        commit_paths(dir.path(), "delete a", &["a.md".to_string()])
            .unwrap()
            .expect("a deletion is a change");

        let tree = StdCommand::new("git")
            .args(["ls-tree", "--name-only", "HEAD"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        assert_eq!(String::from_utf8_lossy(&tree.stdout).trim(), "b.md");
    }

    /// A bundle may hold files this application did not write, and round 3
    /// made tier 2 carry the mode of the ones it does forward across its
    /// publishing rename. Committing every path as `100644` undid that at the
    /// next commit: the mode is part of what the tree records, so a checkout
    /// of that history — or a clone of it on another machine — hands back a
    /// script that no longer runs.
    #[cfg(unix)]
    #[test]
    fn commit_paths_records_the_executable_bit_rather_than_flattening_it() {
        use std::os::unix::fs::PermissionsExt as _;

        let dir = tempdir().unwrap();
        init_repo(dir.path());
        let script = dir.path().join("hook.sh");
        std::fs::write(&script, b"#!/bin/sh\necho hello\n").unwrap();
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
        std::fs::write(dir.path().join("a.md"), b"a\n").unwrap();

        commit_paths(
            dir.path(),
            "add a script and a Note",
            &["hook.sh".to_string(), "a.md".to_string()],
        )
        .unwrap()
        .expect("two new paths are a change");

        let tree = StdCommand::new("git")
            .args(["ls-tree", "HEAD"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        let listing = String::from_utf8_lossy(&tree.stdout);
        let modes: Vec<(&str, &str)> = listing
            .lines()
            .filter_map(|line| {
                let (mode, rest) = line.split_once(' ')?;
                let name = rest.rsplit_once('\t')?.1;
                Some((name, mode))
            })
            .collect();
        assert!(
            modes.contains(&("hook.sh", "100755")),
            "an executable file must commit as 100755: {listing:?}"
        );
        assert!(
            modes.contains(&("a.md", "100644")),
            "an ordinary Note must still commit as 100644: {listing:?}"
        );
    }

    /// ADR-008's consequences fix this identity, and it is deliberately not the
    /// user's: the local Workspace has no account, and asking for one would
    /// reintroduce the onboarding step ADR-005 removed. A repository-local
    /// `user.name`/`user.email` — which `git commit` itself would have used —
    /// must not reach it.
    #[test]
    fn commit_paths_authors_as_the_fixed_application_identity() {
        let dir = tempdir().unwrap();
        init_repo(dir.path());
        git(dir.path(), &["config", "user.name", "Someone Else"]);
        git(dir.path(), &["config", "user.email", "else@example.com"]);
        std::fs::write(dir.path().join("a.md"), b"a\n").unwrap();

        commit_paths(dir.path(), "add a", &["a.md".to_string()])
            .unwrap()
            .expect("a new path is a change");

        let author = StdCommand::new("git")
            .args(["log", "-1", "--format=%an <%ae>|%cn <%ce>"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        assert_eq!(
            String::from_utf8_lossy(&author.stdout).trim(),
            "burlmd <noreply@burlmd.invalid>|burlmd <noreply@burlmd.invalid>"
        );
    }

    /// What tells tier 3's generated message whether this session created the
    /// Note or changed one already in history.
    #[test]
    fn path_in_head_distinguishes_a_new_note_from_one_already_in_history() {
        let dir = tempdir().unwrap();
        init_repo(dir.path());
        std::fs::write(dir.path().join("a.md"), b"a\n").unwrap();

        // An unborn HEAD holds nothing.
        assert!(!path_in_head(dir.path(), "a.md").unwrap());

        commit_all(dir.path(), "baseline", "Test User", "test@example.com").unwrap();

        assert!(path_in_head(dir.path(), "a.md").unwrap());
        assert!(!path_in_head(dir.path(), "never-existed.md").unwrap());
    }
    /// Gherkin: Given a local directory with changes, When the commit function is called,
    /// Then a Git commit is created in the local `.git` index.
    #[test]
    fn commit_all_creates_commit_in_fresh_repo() {
        let dir = tempdir().unwrap();
        init_repo(dir.path());
        std::fs::write(dir.path().join("note.md"), b"# Hello\n").unwrap();

        let commit_id = commit_all(
            dir.path(),
            "initial commit",
            "Test User",
            "test@example.com",
        )
        .expect("commit_all should succeed");

        assert_eq!(commit_id.len(), 40, "expected a sha1 hex object id");

        let log = StdCommand::new("git")
            .args(["log", "--oneline", "-1"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        let log_text = String::from_utf8_lossy(&log.stdout);
        assert!(log_text.contains("initial commit"));

        let show = StdCommand::new("git")
            .args(["show", "HEAD:note.md"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        assert_eq!(String::from_utf8_lossy(&show.stdout), "# Hello\n");
    }

    #[test]
    fn commit_all_creates_second_commit_on_top_of_first() {
        let dir = tempdir().unwrap();
        init_repo(dir.path());
        std::fs::write(dir.path().join("a.md"), b"a\n").unwrap();
        commit_all(dir.path(), "first", "Test User", "test@example.com").unwrap();

        std::fs::write(dir.path().join("b.md"), b"b\n").unwrap();
        let second = commit_all(dir.path(), "second", "Test User", "test@example.com").unwrap();

        let parent = StdCommand::new("git")
            .args(["rev-parse", "HEAD^"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        assert!(!String::from_utf8_lossy(&parent.stdout).trim().is_empty());

        // Both files should be present in the resulting tree (full worktree snapshot).
        let ls = StdCommand::new("git")
            .args(["ls-tree", "-r", "--name-only", "HEAD"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        let names = String::from_utf8_lossy(&ls.stdout);
        assert!(names.contains("a.md"));
        assert!(names.contains("b.md"));

        let head = StdCommand::new("git")
            .args(["rev-parse", "HEAD"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        assert_eq!(String::from_utf8_lossy(&head.stdout).trim(), second);
    }

    #[test]
    fn clone_repo_checks_out_working_tree_from_local_path() {
        let src = tempdir().unwrap();
        init_repo(src.path());
        std::fs::write(src.path().join("readme.md"), b"hello\n").unwrap();
        commit_all(src.path(), "seed", "Test User", "test@example.com").unwrap();

        let dest_parent = tempdir().unwrap();
        let dest = dest_parent.path().join("clone");

        clone_repo(&src.path().to_string_lossy(), &dest, None).expect("clone should succeed");

        let contents = std::fs::read_to_string(dest.join("readme.md")).unwrap();
        assert_eq!(contents, "hello\n");
        assert!(dest.join(".git").is_dir());
    }

    #[test]
    fn push_then_pull_round_trip_via_local_bare_remote() {
        let bare_parent = tempdir().unwrap();
        let bare = bare_parent.path().join("remote.git");
        init_bare(&bare);

        // First clone: makes a commit and pushes it upstream.
        let work_a_parent = tempdir().unwrap();
        let work_a = work_a_parent.path().join("a");
        clone_repo(&bare.to_string_lossy(), &work_a, None).expect("clone A should succeed");
        std::fs::write(work_a.join("from_a.md"), b"from a\n").unwrap();
        commit_all(&work_a, "commit from a", "A", "a@example.com").unwrap();
        push(&work_a, "origin", "main", None).expect("push should succeed");

        // Second clone: pulls what A pushed.
        let work_b_parent = tempdir().unwrap();
        let work_b = work_b_parent.path().join("b");
        clone_repo(&bare.to_string_lossy(), &work_b, None).expect("clone B should succeed");
        pull(&work_b, "origin", "main", None).expect("pull should succeed");

        let contents = std::fs::read_to_string(work_b.join("from_a.md")).unwrap();
        assert_eq!(contents, "from a\n");
    }

    #[test]
    fn pull_surfaces_conflict_markers_without_destroying_them() {
        let bare_parent = tempdir().unwrap();
        let bare = bare_parent.path().join("remote.git");
        init_bare(&bare);

        // Seed the bare remote with an initial commit both clones will diverge from.
        let seed_parent = tempdir().unwrap();
        let seed = seed_parent.path().join("seed");
        clone_repo(&bare.to_string_lossy(), &seed, None).unwrap();
        std::fs::write(seed.join("shared.md"), b"base\n").unwrap();
        commit_all(&seed, "seed", "Seed", "seed@example.com").unwrap();
        push(&seed, "origin", "main", None).unwrap();

        // Clone B *before* A pushes, so both start from the same "seed" ancestor and
        // genuinely diverge rather than one being a fast-forward of the other.
        let work_b_parent = tempdir().unwrap();
        let work_b = work_b_parent.path().join("b");
        clone_repo(&bare.to_string_lossy(), &work_b, None).unwrap();

        // Clone A diverges and pushes upstream.
        let work_a_parent = tempdir().unwrap();
        let work_a = work_a_parent.path().join("a");
        clone_repo(&bare.to_string_lossy(), &work_a, None).unwrap();
        std::fs::write(work_a.join("shared.md"), b"from a\n").unwrap();
        commit_all(&work_a, "a changes shared.md", "A", "a@example.com").unwrap();
        push(&work_a, "origin", "main", None).unwrap();

        // B, unaware of A's push, diverges independently from the same seed commit.
        std::fs::write(work_b.join("shared.md"), b"from b\n").unwrap();
        commit_all(&work_b, "b changes shared.md", "B", "b@example.com").unwrap();

        let result = pull(&work_b, "origin", "main", None);
        assert_eq!(result, Err(AppError::GitConflict));

        let contents = std::fs::read_to_string(work_b.join("shared.md")).unwrap();
        assert!(
            contents.contains("<<<<<<<"),
            "expected raw conflict markers to survive in the working tree, got: {contents}"
        );
        assert!(contents.contains("======="));
        assert!(contents.contains(">>>>>>>"));
        assert!(contents.contains("from a\n") || contents.contains("from b\n"));
    }

    #[test]
    fn push_to_nonexistent_remote_is_a_network_error() {
        let dir = tempdir().unwrap();
        init_repo(dir.path());
        std::fs::write(dir.path().join("a.md"), b"a\n").unwrap();
        commit_all(dir.path(), "first", "Test User", "test@example.com").unwrap();
        git(
            dir.path(),
            &["remote", "add", "origin", "/nonexistent/path/repo.git"],
        );

        let result = push(dir.path(), "origin", "main", None);
        assert!(matches!(
            result,
            Err(AppError::NetworkError(_)) | Err(AppError::IoError(_))
        ));
    }

    fn ls_tree_paths(dir: &Path) -> Vec<String> {
        let ls = StdCommand::new("git")
            .args(["ls-tree", "-r", "--name-only", "HEAD"])
            .current_dir(dir)
            .output()
            .unwrap();
        String::from_utf8_lossy(&ls.stdout)
            .lines()
            .map(|s| s.to_string())
            .collect()
    }

    /// Regression test for the tree-editor deletion bug: `commit_all` used to seed the tree
    /// editor from the parent commit's tree and only `upsert` worktree files, so a file
    /// deleted from the worktree was never visited and survived into the new commit.
    #[test]
    fn commit_all_reflects_a_deleted_file() {
        let dir = tempdir().unwrap();
        init_repo(dir.path());
        std::fs::write(dir.path().join("keep.md"), b"keep\n").unwrap();
        std::fs::write(dir.path().join("gone.md"), b"gone\n").unwrap();
        commit_all(dir.path(), "add both", "Test User", "test@example.com").unwrap();

        std::fs::remove_file(dir.path().join("gone.md")).unwrap();
        commit_all(
            dir.path(),
            "delete gone.md",
            "Test User",
            "test@example.com",
        )
        .unwrap();

        let names = ls_tree_paths(dir.path());
        assert!(names.contains(&"keep.md".to_string()));
        assert!(
            !names.iter().any(|n| n == "gone.md"),
            "deleted file must not survive into the new commit's tree, got: {names:?}"
        );
    }

    /// Regression test for the tree-editor rename bug: renaming used to leave the old path
    /// present in the new commit's tree alongside the new one, since the old path was never
    /// removed from the parent tree the editor started from.
    #[test]
    fn commit_all_reflects_a_renamed_file() {
        let dir = tempdir().unwrap();
        init_repo(dir.path());
        std::fs::write(dir.path().join("old_name.md"), b"content\n").unwrap();
        commit_all(
            dir.path(),
            "add old_name.md",
            "Test User",
            "test@example.com",
        )
        .unwrap();

        std::fs::rename(
            dir.path().join("old_name.md"),
            dir.path().join("new_name.md"),
        )
        .unwrap();
        commit_all(
            dir.path(),
            "rename old_name.md to new_name.md",
            "Test User",
            "test@example.com",
        )
        .unwrap();

        let names = ls_tree_paths(dir.path());
        assert!(names.contains(&"new_name.md".to_string()));
        assert!(
            !names.iter().any(|n| n == "old_name.md"),
            "old path must not survive a rename, got: {names:?}"
        );
    }

    /// Same deletion bug, but for a file nested inside a subdirectory, to make sure the fix
    /// isn't just correct for top-level paths.
    #[test]
    fn commit_all_reflects_a_deleted_file_in_a_subdirectory() {
        let dir = tempdir().unwrap();
        init_repo(dir.path());
        std::fs::create_dir_all(dir.path().join("notes/sub")).unwrap();
        std::fs::write(dir.path().join("notes/sub/keep.md"), b"keep\n").unwrap();
        std::fs::write(dir.path().join("notes/sub/gone.md"), b"gone\n").unwrap();
        commit_all(
            dir.path(),
            "add nested files",
            "Test User",
            "test@example.com",
        )
        .unwrap();

        std::fs::remove_file(dir.path().join("notes/sub/gone.md")).unwrap();
        commit_all(
            dir.path(),
            "delete nested gone.md",
            "Test User",
            "test@example.com",
        )
        .unwrap();

        let names = ls_tree_paths(dir.path());
        assert!(names.contains(&"notes/sub/keep.md".to_string()));
        assert!(
            !names.iter().any(|n| n == "notes/sub/gone.md"),
            "deleted nested file must not survive into the new commit's tree, got: {names:?}"
        );
    }

    /// Regression test for the credential-leak bug: `GitCredentials`'s derived `Debug` used
    /// to print the raw token in cleartext (e.g. in a panic message or `{:?}` log line).
    #[test]
    fn git_credentials_debug_output_redacts_the_token() {
        let creds = GitCredentials {
            username: "x-access-token".to_string(),
            token: Zeroizing::new("super-secret-token-value".to_string()),
        };

        let debug_output = format!("{creds:?}");

        assert!(
            !debug_output.contains("super-secret-token-value"),
            "Debug output must not contain the raw token, got: {debug_output}"
        );
        assert!(debug_output.contains("username"));
        assert!(debug_output.contains("x-access-token"));
    }

    /// `commit_all` must honor `.gitignore`, matching real `git add -A`'s own behavior
    /// (skipping gitignored paths unless `-f` is given): a top-level ignored file must not
    /// be committed, a directory-level ignore pattern must prune everything underneath it
    /// (not just a literal name match), the same must hold for a file nested inside a
    /// tracked subdirectory, and — since `.gitignore` itself is an ordinary tracked file
    /// unless something ignores it too — it must still be committed.
    #[test]
    fn commit_all_honors_gitignore() {
        let dir = tempdir().unwrap();
        init_repo(dir.path());
        std::fs::write(dir.path().join(".gitignore"), b"ignored.md\nbuild/\n").unwrap();
        std::fs::write(dir.path().join("ignored.md"), b"should not be committed\n").unwrap();
        std::fs::write(dir.path().join("tracked.md"), b"should be committed\n").unwrap();
        std::fs::create_dir_all(dir.path().join("build")).unwrap();
        std::fs::write(
            dir.path().join("build/output.md"),
            b"excluded via a directory-level rule\n",
        )
        .unwrap();
        std::fs::create_dir_all(dir.path().join("notes/sub")).unwrap();
        std::fs::write(
            dir.path().join("notes/sub/ignored.md"),
            b"nested ignored file\n",
        )
        .unwrap();
        std::fs::write(
            dir.path().join("notes/sub/tracked.md"),
            b"nested tracked file\n",
        )
        .unwrap();

        commit_all(
            dir.path(),
            "respect gitignore",
            "Test User",
            "test@example.com",
        )
        .unwrap();

        let names = ls_tree_paths(dir.path());
        assert!(
            names.contains(&".gitignore".to_string()),
            "the .gitignore file itself must be committed, got: {names:?}"
        );
        assert!(names.contains(&"tracked.md".to_string()));
        assert!(names.contains(&"notes/sub/tracked.md".to_string()));
        assert!(
            !names.iter().any(|n| n == "ignored.md"),
            "a gitignored top-level file must not be committed, got: {names:?}"
        );
        assert!(
            !names.iter().any(|n| n.starts_with("build/")),
            "a gitignored directory's contents must not be committed, got: {names:?}"
        );
        assert!(
            !names.iter().any(|n| n == "notes/sub/ignored.md"),
            "a gitignored file nested in a subdirectory must not be committed, got: {names:?}"
        );
    }

    /// Regression test for the locale-sensitive stderr classification bug, plus every other
    /// fixed env var `git_command` MUST set on every invocation: `classify_git_cli_failure`
    /// substring-matches English `git` diagnostics, which only appear when the child inherits
    /// a C locale; `GIT_TERMINAL_PROMPT=0` closes off pty-based credential-helper prompts that
    /// nulled stdin alone doesn't stop; `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` pointed at
    /// `/dev/null` stop a host's `~/.gitconfig`/`/etc/gitconfig` from overriding anything
    /// (including the identity below); and the fixed author/committer identity is what lets
    /// `git merge` create an auto-merge commit on a machine with no git identity configured at
    /// all. `git_command` is the single builder every CLI invocation in this module goes
    /// through, so asserting all of this here covers every call site.
    #[test]
    fn git_command_pins_locale_prompt_config_isolation_and_identity() {
        let dir = tempdir().unwrap();
        let cmd = git_command(dir.path());
        let envs: std::collections::HashMap<_, _> = cmd.get_envs().collect();
        let os = std::ffi::OsStr::new;
        assert_eq!(
            envs.get(os("LC_ALL")),
            Some(&Some(os("C"))),
            "git_command must pin LC_ALL=C so classify_git_cli_failure's English substring \
             matching stays correct regardless of the host process's own locale"
        );
        assert_eq!(
            envs.get(os("GIT_TERMINAL_PROMPT")),
            Some(&Some(os("0"))),
            "git_command must set GIT_TERMINAL_PROMPT=0 as belt-and-suspenders prompt \
             suppression alongside the already-nulled stdin"
        );
        assert_eq!(
            envs.get(os("GIT_CONFIG_GLOBAL")),
            Some(&Some(os("/dev/null"))),
            "git_command must isolate the child from the host's global git config"
        );
        assert_eq!(
            envs.get(os("GIT_CONFIG_SYSTEM")),
            Some(&Some(os("/dev/null"))),
            "git_command must isolate the child from the host's system git config"
        );
        assert_eq!(
            envs.get(os("GIT_AUTHOR_NAME")),
            Some(&Some(os(CLI_IDENTITY_NAME)))
        );
        assert_eq!(
            envs.get(os("GIT_AUTHOR_EMAIL")),
            Some(&Some(os(CLI_IDENTITY_EMAIL)))
        );
        assert_eq!(
            envs.get(os("GIT_COMMITTER_NAME")),
            Some(&Some(os(CLI_IDENTITY_NAME)))
        );
        assert_eq!(
            envs.get(os("GIT_COMMITTER_EMAIL")),
            Some(&Some(os(CLI_IDENTITY_EMAIL)))
        );
    }

    /// Regression test for the "Committer identity unknown" bug: `pull`'s `git merge --no-edit`
    /// creates a real merge commit whenever both sides have diverged and merge cleanly (not a
    /// fast-forward), and `git merge` needs *some* author/committer identity to do that. Before
    /// `git_command` injected `GIT_AUTHOR_*`/`GIT_COMMITTER_*`, this only worked by accident on
    /// a machine with a global `user.name`/`user.email` already configured (as most developer
    /// machines — including the one this fix was written on — happen to have); a genuinely
    /// fresh machine (or CI) with no git identity configured anywhere would fail here.
    ///
    /// This repo's `.git` directory has no `user.name`/`user.email` set (neither `init_repo`
    /// nor `test_support::git` — used here only for `init_bare` — ever configures one), and
    /// `git_command` itself now points `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` at `/dev/null`
    /// for every invocation it builds, so this test is not relying on (or vulnerable to) the
    /// host machine's own global git config either way — it would pass or fail identically on
    /// a machine with no global identity at all.
    #[test]
    fn pull_auto_merges_with_no_git_identity_configured_anywhere() {
        let bare_parent = tempdir().unwrap();
        let bare = bare_parent.path().join("remote.git");
        init_bare(&bare);

        // Seed a common ancestor both clones diverge from.
        let seed_parent = tempdir().unwrap();
        let seed = seed_parent.path().join("seed");
        clone_repo(&bare.to_string_lossy(), &seed, None).unwrap();
        std::fs::write(seed.join("shared.md"), b"base\n").unwrap();
        commit_all(&seed, "seed", "Seed", "seed@example.com").unwrap();
        push(&seed, "origin", "main", None).unwrap();

        // Clone B *before* A pushes, so both diverge from the same ancestor rather than one
        // being a fast-forward of the other (a fast-forward merge creates no merge commit and
        // so would never exercise the identity bug this test guards against).
        let work_b_parent = tempdir().unwrap();
        let work_b = work_b_parent.path().join("b");
        clone_repo(&bare.to_string_lossy(), &work_b, None).unwrap();

        // Clone A diverges with a *different* file, so the eventual merge is non-conflicting.
        let work_a_parent = tempdir().unwrap();
        let work_a = work_a_parent.path().join("a");
        clone_repo(&bare.to_string_lossy(), &work_a, None).unwrap();
        std::fs::write(work_a.join("from_a.md"), b"from a\n").unwrap();
        commit_all(&work_a, "a adds a new file", "A", "a@example.com").unwrap();
        push(&work_a, "origin", "main", None).unwrap();

        // B, unaware of A's push, diverges independently with an unrelated new file.
        std::fs::write(work_b.join("from_b.md"), b"from b\n").unwrap();
        commit_all(&work_b, "b adds a different new file", "B", "b@example.com").unwrap();

        pull(&work_b, "origin", "main", None)
            .expect("pull's auto-merge must succeed even with no git identity configured anywhere");

        // Both files should be present in the merged tree.
        let names = ls_tree_paths(&work_b);
        assert!(names.contains(&"from_a.md".to_string()));
        assert!(names.contains(&"from_b.md".to_string()));
    }

    /// Regression test for the `GIT_CONFIG_COUNT` clobbering bug: `apply_credentials` used to
    /// unconditionally write `GIT_CONFIG_COUNT=1`/`GIT_CONFIG_KEY_0`/`GIT_CONFIG_VALUE_0`,
    /// discarding (or mis-indexing) any config-injection entries this process's own environment
    /// already carried. It must instead append after whatever is already there.
    ///
    /// # Why the inherited count is an argument and not `std::env::set_var`
    ///
    /// This test and the one below it used to build their fixture by writing those three
    /// variables into the *process* environment under `db::connection::ENV_LOCK`, and that is
    /// what made this crate's test suite intermittently fail somewhere else entirely.
    /// `ENV_LOCK` is not held by the many tests here that spawn a real `git` child, by design
    /// — but `git` reads `GIT_CONFIG_COUNT` and friends out of the environment it inherits at
    /// `fork`/`exec`, and three `set_var` calls are not one atomic step. A `git init` in
    /// another test thread landing after `GIT_CONFIG_COUNT=1` and before `GIT_CONFIG_VALUE_0`
    /// exists dies with `error: missing config value for GIT_CONFIG_VALUE_0`, taking an
    /// unrelated test with it. The comment that used to live here asserted the opposite —
    /// "none of those tests ... depend on inherited ambient ones" — which was true of
    /// `git_command`'s own variables and false of this one, since nothing clears
    /// `GIT_CONFIG_*` for a spawned child.
    ///
    /// So the fixture is passed in ([`apply_credentials_after`]) and nothing process-wide is
    /// touched. No `ENV_LOCK`, no `unsafe`, and no other test can observe this one running.
    #[test]
    fn apply_credentials_appends_after_an_existing_injected_config_entry() {
        let mut cmd = Command::new("git");
        let credentials = GitCredentials {
            username: "x-access-token".to_string(),
            token: Zeroizing::new("tok".to_string()),
        };
        // One entry already injected into the environment this `git` would inherit.
        apply_credentials_after(&mut cmd, Some(&credentials), 1);

        let envs: std::collections::HashMap<_, _> = cmd.get_envs().collect();
        assert_eq!(
            envs.get(std::ffi::OsStr::new("GIT_CONFIG_COUNT")),
            Some(&Some(std::ffi::OsStr::new("2"))),
            "count must grow to existing (1) + our own entry (1) = 2"
        );
        assert_eq!(
            envs.get(std::ffi::OsStr::new("GIT_CONFIG_KEY_1")),
            Some(&Some(std::ffi::OsStr::new("http.extraheader"))),
            "our entry must land at the next free index (1), not clobber index 0"
        );
        assert!(
            envs.contains_key(std::ffi::OsStr::new("GIT_CONFIG_VALUE_1")),
            "our entry's value must be set at the matching index"
        );
        // The pre-existing entry at index 0 must be left completely untouched by
        // `apply_credentials` (it never even sees it — it's inherited, not on the `Command`).
        assert!(
            !envs.contains_key(std::ffi::OsStr::new("GIT_CONFIG_KEY_0")),
            "apply_credentials must not overwrite the pre-existing index-0 entry"
        );
    }

    /// With no `GIT_CONFIG_COUNT` set in the process environment at all, `apply_credentials`
    /// must fall back to starting at index 0 (the pre-fix behavior), not error or skip. That
    /// absence is what [`existing_git_config_count`] reports as `0`, and it is passed in here
    /// for the reason the test above states.
    #[test]
    fn apply_credentials_starts_at_index_zero_with_no_preexisting_config() {
        let mut cmd = Command::new("git");
        let credentials = GitCredentials {
            username: "x-access-token".to_string(),
            token: Zeroizing::new("tok".to_string()),
        };
        apply_credentials_after(&mut cmd, Some(&credentials), 0);

        let envs: std::collections::HashMap<_, _> = cmd.get_envs().collect();
        assert_eq!(
            envs.get(std::ffi::OsStr::new("GIT_CONFIG_COUNT")),
            Some(&Some(std::ffi::OsStr::new("1")))
        );
        assert_eq!(
            envs.get(std::ffi::OsStr::new("GIT_CONFIG_KEY_0")),
            Some(&Some(std::ffi::OsStr::new("http.extraheader")))
        );
    }
}
