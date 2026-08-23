//! ADR-008's four persistence tiers, and the lock discipline
//! `SPK-WSPC-D001` §6.2 settled for them.
//!
//! # The four tiers
//!
//! 1. **Every mutation writes the `drafts` row.** Not only the per-keystroke
//!    [`NoteSession::update_block`] but every structural mutator too, because
//!    each is a discrete user action with no preceding keystroke call — press
//!    Enter and the split would otherwise live only in memory until the idle
//!    timer fired a second later, and a kill in that window is exactly what
//!    this tier exists to survive (CAP-WS-03,
//!    `architecture/resilience.md`). [`NoteSession::commit_block`] is the sole
//!    mutator that writes nothing here, because what it reparses is already in
//!    the row.
//! 2. **~1s idle writes the file, atomically.** The working source, verbatim,
//!    through a uniquely named temporary file and a rename in the same
//!    directory. This tier splices nothing: `update_block` already substituted
//!    the text, and having a second writer of the working source is the
//!    duplication ADR-008 decision 2 works through.
//! 3. **Closing the Note makes one Git commit** — scoped to that Note's path
//!    alone, authored as the fixed application identity, and made only when
//!    the session actually changed something. Deliberately never on a timer.
//! 4. **That commit notifies the sync scheduler**, giving Epic C's
//!    `notify_activity()` its first caller.
//!
//! # The locks, and why there are five of them
//!
//! `SPK-WSPC-D001` §4.4 measured four shapes. Under one process-wide mutex a
//! keystroke waits a p95 of 10.4ms (WAL) or 55.9ms (SQLite defaults) in front
//! of buffer work that performs no I/O at all — the ADR-008 hazard reproduced
//! as a number. The shape below measured 0.031ms.
//!
//! - A per-Workspace **lifecycle lock** ([`with_lifecycle_lock`]) serializes
//!   whole `workspace::lifecycle` operations against each other, and [`open_note`]
//!   against all of them — an open decides whether a concept id exists and then
//!   installs a session for it, which is the same check-then-act a deletion can
//!   land inside. It is the one lock no *editing* path ever takes, and it is
//!   coarse on purpose — see its own documentation for the races it closes and
//!   why the other three could not close them.
//! - A per-Note **tier 1 lock** serializes source mutations through their draft
//!   writes. It is held across SQLite but never filesystem I/O, so a failed
//!   structural mutation can either roll back before another edit observes it
//!   or return the installed state as authoritative.
//! - A per-Note **state lock** guards the working source, the span map, the
//!   AST, the edit sequence and the recorded revision. **No thread ever holds
//!   it across I/O.** Both sides snapshot under it — an `Arc::clone`, which is
//!   a refcount bump — release it, and only then touch the database or the
//!   filesystem. The buffer is mutated through `Arc::make_mut`, so the copy is
//!   paid by whichever single keystroke first writes while a snapshot is still
//!   alive, rather than by the timer holding the lock for the length of the
//!   Note.
//! - A per-Note **tier 2 write lock** serializes tier 2 writers against each
//!   other, and is the only lock held across I/O. It is deliberate and safe:
//!   `update_block` and `commit_block` never take it, so no keystroke can wait
//!   on it. It exists because tier 2 has two writers — the idle timer and
//!   `close_note` — and the OCC check is a time-of-check-to-time-of-use bug
//!   unless one lock spans check, write and re-record as a unit.
//! - The process-wide **connection mutex** is unchanged: one statement at a
//!   time, as `db::connection` has always been.
//!
//! The only permitted acquisition order is **lifecycle lock → tier 2 write
//! lock → tier 1 lock → state lock → connection**. The state lock and the
//! connection are never held together; the tier 1 lock deliberately surrounds
//! either short phase, and the tier 2 write lock spans its snapshot. The
//! keystroke path takes a suffix of that order (tier 1, state, then
//! connection), so no cycle exists and
//! deadlock is unrepresentable rather than merely unobserved. The session
//! registry lock is above all five and is never held while any of them is
//! acquired.
//!
//! Nothing below the lifecycle lock ever reaches back up for it, which is what
//! makes the order total rather than merely conventional: this module's timer,
//! flush and close paths call into `workspace::lifecycle` for exactly two
//! things, `commit_stage_failure` and `restate`, and both are pure functions
//! over an `AppError` that take no lock at all.
//!
//! # Three standing review rules (`SPK-WSPC-D001` §6.2.7)
//!
//! No closure passed to `with_connection` may perform file I/O; no lock a
//! keystroke can contend for may be held across an `fsync`; and no tier 2
//! write may be issued outside the tier 2 write lock.

use std::collections::HashMap;
use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard, OnceLock, PoisonError, Weak};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use rusqlite::{Connection, OptionalExtension};

use crate::db::connection::assert_no_io_under_the_connection;
use crate::draft::{NoteMetadata, NoteState};
use crate::error::AppError;
use crate::index::{self, content_hash};
use crate::markdown::{
    parse_markdown_fragment, parse_note, splice, AstNode, ParsedNote, RenderedRange, SpanMap,
};
use crate::okf::{concept_id_to_path, read_frontmatter};
use crate::sync::scheduler::SyncScheduler;

/// How long a Note must sit idle before tier 2 writes it (ADR-008 decision 2).
///
/// The timer measures time since the last mutation and **may fire while the
/// Block is still focused** — otherwise a Note left focused indefinitely would
/// never reach disk, which is the opposite of what this tier is for.
pub const DEFAULT_IDLE_INTERVAL: Duration = Duration::from_secs(1);

// ---------------------------------------------------------------------------
// The Workspace a session persists into
// ---------------------------------------------------------------------------

/// Everything the persistence tiers need to reach one Workspace: its id, its
/// bundle root, and the way to the encrypted index.
///
/// Production always resolves to the process-wide connection; tests inject
/// their own so that no test in this module depends on the singleton, the
/// keyring, or on which test opened the shared database first.
pub struct Workspace {
    id: String,
    root: PathBuf,
    db: DbHandle,
    idle_interval: Duration,
    #[cfg(test)]
    before_draft_write: Mutex<Option<Arc<dyn Fn() + Send + Sync>>>,
}

enum DbHandle {
    /// `db::connection`'s process-wide `Mutex<Connection>`.
    Process,
    #[cfg(test)]
    Owned(Mutex<Connection>),
}

impl Workspace {
    /// The Workspace every FFI call is implicitly scoped to (ADR-005
    /// decision 7).
    ///
    /// The bundle root is cached beside the active-Workspace cell rather than
    /// re-read here, because this runs on every Note-level FFI call and the
    /// query it replaced took the process-wide connection mutex — the one a
    /// keystroke's own tier 1 draft write waits on — to read a `local_path`
    /// that cannot change while a Workspace is open. See
    /// `db::connection::active_workspace`.
    pub fn active() -> Result<Arc<Workspace>, AppError> {
        let (id, root) = crate::db::connection::active_workspace()?;
        Ok(Arc::new(Workspace {
            id,
            root,
            db: DbHandle::Process,
            idle_interval: DEFAULT_IDLE_INTERVAL,
            #[cfg(test)]
            before_draft_write: Mutex::new(None),
        }))
    }

    pub fn id(&self) -> &str {
        &self.id
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Acquires the connection and runs `f` against it.
    ///
    /// Every caller in this module holds no state lock when it calls this, per
    /// the acquisition order in the module documentation, and **no `f` may
    /// perform file I/O** (`SPK-WSPC-D001` §6.2.7): the connection is
    /// process-wide, so anything slow inside a closure is time a keystroke's
    /// own tier 1 write spends waiting. The rule is enforced rather than merely
    /// written down — see
    /// [`crate::db::connection::assert_no_io_under_the_connection`].
    ///
    /// The scope is entered by [`crate::db::connection::with_connection`]
    /// itself, so the production arm below needs nothing here. The test arm
    /// enters it explicitly: an injected connection is not process-wide and so
    /// costs a keystroke nothing, but every hermetic test in this crate runs
    /// against one, and a rule only the untested arm enforces is not enforced.
    pub(super) fn with_db<T>(
        &self,
        f: impl FnOnce(&Connection) -> Result<T, AppError>,
    ) -> Result<T, AppError> {
        match &self.db {
            DbHandle::Process => crate::db::connection::with_connection(f),
            #[cfg(test)]
            DbHandle::Owned(mutex) => {
                let conn = mutex
                    .lock()
                    .map_err(|_| AppError::DatabaseError("test db mutex poisoned".to_string()))?;
                let _scope = crate::db::connection::ConnectionScope::enter();
                f(&conn)
            }
        }
    }

    /// The absolute path of one Note's file, **rejecting any concept id that
    /// does not name a file inside this Workspace**.
    ///
    /// A concept id is the bundle-relative path with `.md` removed (ADR-004),
    /// so it is joined onto the root — and `Path::join` is happy to walk out of
    /// it. `../../.ssh/authorized_keys` is a concept id as far as the type
    /// system is concerned, and `WSPC-D008` wires this parameter straight to
    /// ids the UI supplies. Every component must therefore be an ordinary name:
    /// no `..`, no `.`, no absolute path, no Windows prefix or root.
    ///
    /// The check is lexical because it has to run *before* the file is read,
    /// and a path that does not exist yet cannot be canonicalized. A symlink
    /// planted inside the bundle would still resolve outside it, so a Note that
    /// does exist is additionally checked against the canonicalized root, which
    /// is the same containment test `index::path_is_in_workspace` applies.
    ///
    /// That last check alone was not enough, because on the **creation** path
    /// the file does not exist yet and so nothing looked at the directory it
    /// was about to be written into. [`Workspace::ensure_directory_contained`]
    /// closes that: the containing directory is resolved, and a Note is refused
    /// unless every component of it is really the directory it names.
    ///
    /// A backslash **anywhere** in the concept id is refused before any of
    /// that, so that all three path-handling functions in this Workspace agree
    /// on what a segment may carry: `lifecycle::validate_segment` rejects it in
    /// a name and `lifecycle::normalize_directory` rejects it in a Directory
    /// path, the latter after it turned out to be a traversal hole rather than
    /// a nicety. On Unix `..\..\etc` is one `Component::Normal` and so passes
    /// the check below; nothing here translates it afterwards, which is why the
    /// disagreement is currently harmless — but it is the same shape as the
    /// defect that made translating-then-checking unsafe, and one rule shared by
    /// three functions is cheaper than three that have to be re-verified apart.
    ///
    /// An interior **NUL** is refused on the same terms and by the same three
    /// functions. `validate_segment` already rejected it in a *name*, so a
    /// `create_note` was refused cleanly while a `create_directory("a\0b")`
    /// reached the filesystem and came back as a raw `IoError` about an invalid
    /// argument — the same input, two unrelated-looking answers, and the leaked
    /// one names an implementation detail rather than the rule it broke. It is
    /// also the one character no `CString` can carry, so nothing downstream
    /// could act on it even if it got through.
    pub(super) fn note_path(&self, note_id: &str) -> Result<PathBuf, AppError> {
        use std::path::Component;

        if note_id.contains('\\') {
            return Err(AppError::PathUnavailable(format!(
                "concept id {note_id} does not name a file inside the Workspace: a concept id \
                 is `/`-separated and a backslash is a character no segment may carry"
            )));
        }
        if note_id.contains('\0') {
            return Err(AppError::PathUnavailable(format!(
                "concept id {note_id:?} contains a NUL, which no path on this system can carry"
            )));
        }

        let relative = concept_id_to_path(note_id);
        let relative_path = Path::new(&relative);
        let escapes = relative_path
            .components()
            .any(|component| !matches!(component, Component::Normal(_)));
        if escapes || relative.is_empty() {
            return Err(AppError::PathUnavailable(format!(
                "concept id {note_id} does not name a file inside the Workspace"
            )));
        }

        self.ensure_directory_contained(relative_path.parent().unwrap_or(Path::new("")))
            .map_err(|reason| {
                AppError::PathUnavailable(format!(
                    "concept id {note_id} does not name a file inside the Workspace: {reason}"
                ))
            })?;

        let absolute = self.root.join(relative_path);

        // The **leaf** gets the rule its ancestors already had, and it is the
        // half that was missing rather than a belt-and-braces addition.
        // [`Workspace::ensure_directory_contained`] walks the *directory*
        // components above, so `Foo.md -> Real.md` planted inside the bundle
        // passed every check here: the link resolves inside the Workspace, so
        // the containment test below is satisfied, and the Note opens, reads
        // and writes through it perfectly well. `index::scan::walk_bundle`
        // skips symbolic links, so at the next reindex — which runs on every
        // Workspace open — the row disappears while the file stays on disk and
        // `lifecycle::ensure_path_available` consults the filesystem, leaving
        // `Foo` permanently taken by a Note nothing in the application can see.
        // That is precisely the ending the directory rule and the
        // dot-prefixed-name rule both exist to prevent, reached through the one
        // component neither of them looked at.
        //
        // `symlink_metadata` rather than `exists`, for that function's reason:
        // a *broken* link is seen as present and refused here rather than
        // mistaken for a name a create is free to take.
        if let Ok(metadata) = std::fs::symlink_metadata(&absolute) {
            if metadata.file_type().is_symlink() {
                return Err(AppError::PathUnavailable(format!(
                    "concept id {note_id} is a symbolic link, and the indexer skips those — a \
                     Note read or written through one either lands outside the Workspace or \
                     disappears from it at the next reindex while its file, and its name, stay \
                     taken"
                )));
            }
        }

        if absolute.exists() {
            let contained = match (
                std::fs::canonicalize(&self.root),
                std::fs::canonicalize(&absolute),
            ) {
                (Ok(root), Ok(resolved)) => resolved.starts_with(&root),
                _ => false,
            };
            if !contained {
                return Err(AppError::PathUnavailable(format!(
                    "concept id {note_id} resolves outside the Workspace"
                )));
            }
        }
        Ok(absolute)
    }

    /// Refuses a bundle-relative directory path unless every component of it
    /// that exists on disk **is** the directory it names — no component being a
    /// symbolic link, and nothing resolving outside the Workspace.
    ///
    /// Returns the reason as a `String` rather than an `AppError`, so each
    /// caller can name the thing it was asked for (a concept id, a Directory
    /// path) in front of it.
    ///
    /// Both halves of the rule matter, and the second is the less obvious one:
    ///
    /// - A link pointing **outside** the bundle turns a concept id the UI
    ///   supplies into an arbitrary write. Nothing before this looked, because
    ///   the lexical check above sees only `Component::Normal` names and the
    ///   `exists()` check below cannot run on a file being created.
    /// - A link pointing back **inside** the bundle is refused too, even though
    ///   the bytes would land in the Workspace. `index::scan::walk_bundle`
    ///   skips symbolic links, so the file is reachable at the concept id it was
    ///   created under only until the next reindex — which now runs on every
    ///   Workspace open. After that the row is gone, the file is still on disk,
    ///   and `lifecycle::ensure_path_available` consults the filesystem as well
    ///   as the index, so the name stays permanently taken by a Note nothing can
    ///   see. That is the same ending the dot-prefixed-name rule exists to
    ///   prevent, reached by a different route.
    ///
    /// The walk stops at the first component that does not exist: a path cannot
    /// have an existing descendant under a missing ancestor, and the levels a
    /// create is about to materialize are ordinary directories by construction.
    pub(super) fn ensure_directory_contained(&self, relative: &Path) -> Result<(), String> {
        let canonical_root = std::fs::canonicalize(&self.root)
            .map_err(|e| format!("resolve the Workspace root {}: {e}", self.root.display()))?;

        let mut expected = canonical_root;
        for component in relative.components() {
            expected.push(component);
            // `symlink_metadata` rather than `exists`, so a *broken* link is
            // seen as present and refused below rather than mistaken for a
            // level a create is free to materialize.
            if std::fs::symlink_metadata(&expected).is_err() {
                return Ok(());
            }
            let resolved = std::fs::canonicalize(&expected)
                .map_err(|e| format!("resolve {}: {e}", expected.display()))?;
            if resolved != expected {
                return Err(format!(
                    "{} is a symbolic link to {}, and the indexer skips those — a Note written \
                     through one either lands outside the Workspace or disappears from it at the \
                     next reindex while its file, and its name, stay taken",
                    expected.display(),
                    resolved.display()
                ));
            }
        }
        Ok(())
    }

    /// A Workspace over an injected connection, with the idle interval under
    /// the test's control. Tests fire the tiers explicitly wherever they can,
    /// so only the tests actually about the timer shorten it.
    #[cfg(test)]
    pub(crate) fn for_test(
        conn: Connection,
        id: impl Into<String>,
        root: PathBuf,
        idle_interval: Duration,
    ) -> Arc<Workspace> {
        Arc::new(Workspace {
            id: id.into(),
            root,
            db: DbHandle::Owned(Mutex::new(conn)),
            idle_interval,
            before_draft_write: Mutex::new(None),
        })
    }

    #[cfg(test)]
    fn set_before_draft_write(&self, hook: Option<Arc<dyn Fn() + Send + Sync>>) {
        *self.before_draft_write.lock().unwrap() = hook;
    }
}

// ---------------------------------------------------------------------------
// Session state
// ---------------------------------------------------------------------------

/// The mutable half of an open Note, guarded by the state lock.
struct SessionState {
    /// The working source: one buffer per open Note holding its full current
    /// text, identical to what `drafts.raw_markdown` persists. `Arc` so both
    /// sides snapshot it with a refcount bump rather than a copy.
    source: Arc<String>,
    spans: Arc<SpanMap>,
    ast: Arc<Vec<AstNode>>,
    /// Incremented by every tier 1 mutator, under this lock, in the same
    /// critical section as the buffer mutation — and by nothing else.
    /// `commit_block` must not advance it: it writes no draft row, so an
    /// increment here would push the counter past the value stored in the row
    /// and suppress every legitimate tier 2 clear for the rest of the session.
    edit_seq: i64,
    /// The OCC baseline: the hash of what this application believes is on
    /// disk. Initialised at open and **replaced after every successful write**,
    /// which is the load-bearing half — a baseline pinned to open time would
    /// make the second write of a session fail against the first.
    revision: String,
    /// Whether the working source came from a `drafts` row rather than disk.
    restored_from_draft: bool,
    /// Whether this session opened over a Note with **no file behind it**, and
    /// so owes the next tier 2 write a file rather than an overwrite.
    ///
    /// Set only by [`open_note`]'s recovery branch, and cleared by the first
    /// successful write. It is what lets [`NoteSession::write_locked`] tell
    /// two identical-looking `NotFound`s apart: a file deleted underneath a
    /// live session, which must surface so `close` can retire it and keep the
    /// draft row; and a file this session already knows is absent, whose
    /// absence is the state it recorded its OCC baseline against.
    awaiting_recreate: bool,
    /// Whether this session has changed the Note at all. Tier 3's gate: a Note
    /// opened and closed unread makes no commit.
    session_edited: bool,
    /// Whether edits are buffered that no successful tier 2 write has covered.
    unwritten: bool,
    /// Whether the bytes currently in `source` hold an **unresolved merge
    /// conflict** that [`conflict_suggestions`] collapsed into `Suggestion`
    /// nodes.
    ///
    /// Set and cleared by [`NoteSession::reload`] alone, because that is the
    /// only call that installs a collapsed AST, and re-evaluated on every
    /// reload rather than latched — the exit from a conflict is repairing the
    /// file and reloading it.
    ///
    /// While it stands, `ast` and `spans` describe **different documents**: the
    /// collapse replaces each conflict region's several raw Blocks with one
    /// `Suggestion` node and renumbers everything after it, while the span map
    /// is built from the raw source and still indexes the marker lines. Every
    /// `block_path` the UI reads off that AST therefore addresses some other
    /// Block of the file, so every call that takes one is refused until the
    /// conflict is gone. See [`SessionState::refuse_while_conflicted`].
    conflicted: bool,
    last_written_at: Option<i64>,
    last_error: Option<AppError>,
    closed: bool,
    metadata: NoteMetadata,
}

impl SessionState {
    /// Refuses `what` while [`SessionState::conflicted`] stands.
    ///
    /// Called from inside the same critical section as the work it guards, so
    /// that no mutator can pass the check against one state and then mutate
    /// another.
    ///
    /// The refusal is a `ParseError` because that is what every other
    /// unaddressable-`block_path` refusal on this surface already is
    /// (`update_block`'s container-path rule, `block_source`'s missing Block),
    /// and the caller's exit is the same in all three cases: this path names
    /// nothing it can act on. What is different is the *remedy*, so the message
    /// states it — the conflict is resolved in the file, and `reload` picks the
    /// repaired bytes up.
    fn refuse_while_conflicted(&self, note_id: &str, what: &str) -> Result<(), AppError> {
        if !self.conflicted {
            return Ok(());
        }
        Err(AppError::ParseError(format!(
            "{note_id} holds an unresolved merge conflict, so {what} is refused: the \
             Suggestion nodes the reload installed renumbered this Note's Blocks and the \
             span map still indexes the raw markers, so no block_path addresses the same \
             Block in both. Resolve the conflict in the file, then reload the Note."
        )))
    }
}

struct SessionInner {
    workspace: Arc<Workspace>,
    note_id: String,
    /// Bundle-relative path with `.md`, the pathspec tier 3 commits.
    relative_path: String,
    absolute_path: PathBuf,
    state: Mutex<SessionState>,
    /// Serializes source mutations across their tier-1 draft writes. Unlike
    /// `write_lock`, it never covers filesystem I/O.
    tier_one_lock: Mutex<()>,
    /// Held across the whole OCC sequence — revision check, atomic write,
    /// re-record — and taken by tier 2 writers only.
    write_lock: Mutex<()>,
    timer: IdleTimer,
}

/// One open Note. Cheap to clone; every clone addresses the same state.
#[derive(Clone)]
pub struct NoteSession(Arc<SessionInner>);

/// What a successful tier 2 write put on disk: the new revision, and the edit
/// sequence the written bytes covered.
struct WrittenThrough {
    revision: String,
    seq: i64,
}

/// The state a structural tier-1 mutation replaces. It is retained only while
/// its draft row is being written, so a database refusal can restore the exact
/// pre-mutation session without holding the state lock across I/O.
struct StructuralEditRollback {
    source: Arc<String>,
    spans: Arc<SpanMap>,
    ast: Arc<Vec<AstNode>>,
    metadata: NoteMetadata,
    edit_seq: i64,
    revision: String,
    session_edited: bool,
    unwritten: bool,
}

/// The open Notes of this process, keyed by Workspace and concept id.
///
/// This lock is above every lock in the module documentation's order and is
/// never held while any of them is acquired: callers clone the `NoteSession`
/// out and release it immediately.
/// `(workspace_id, concept id)`. A concept id is unique within a bundle, never
/// globally (`data-models/schema.sql` rule 1), so the Workspace qualifier is
/// what keeps two Workspaces' `Welcome` apart.
type SessionKey = (String, String);
type SessionMap = HashMap<SessionKey, NoteSession>;

fn sessions() -> &'static Mutex<SessionMap> {
    static SESSIONS: OnceLock<Mutex<SessionMap>> = OnceLock::new();
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn registry() -> Result<MutexGuard<'static, SessionMap>, AppError> {
    sessions()
        .lock()
        .map_err(|_| AppError::DatabaseError("open-note registry poisoned".to_string()))
}

/// The open session for `note_id` in the active Workspace, if any.
pub fn lookup(workspace_id: &str, note_id: &str) -> Result<Option<NoteSession>, AppError> {
    Ok(registry()?
        .get(&(workspace_id.to_string(), note_id.to_string()))
        .cloned())
}

// ---------------------------------------------------------------------------
// Opening
// ---------------------------------------------------------------------------

/// Opens a Note by concept id, restoring an unflushed draft if one exists.
///
/// The branch is load-bearing rather than presentational
/// (`flow-edit-note.md`): a draft row exists precisely when its content
/// differs from disk, so parsing the disk bytes and *then* reporting a
/// restored draft would return an AST of the wrong document and build the span
/// map against bytes that are not the working source. The working source is
/// whichever of the two is authoritative, while the recorded revision stays the
/// hash of what is **on disk**, because that is what tier 2 compares against
/// before overwriting it.
///
/// Which is also why the disk bytes are decoded **on the no-draft branch
/// only**. The strict decode is an obligation of the bytes that become the
/// working source (see [`decode_source`]), and a draft row's text is already a
/// `String`; running the decode first would make a file that went invalid
/// underneath a session — a foreign tool writing Latin-1 over it, a truncated
/// sync — refuse the one call that can hand the user their unflushed work back.
/// The revision is a hash of the raw bytes and needs no decode at all.
///
/// # A Note with no file
///
/// A missing file is `NotFound` **only when there is no draft row either**,
/// and the draft is consulted before that verdict is reached rather than
/// after. [`NoteSession::close`] promises that a Note deleted out from under
/// an open session keeps its row, and [`pending_drafts`] goes out of its way
/// to keep reporting it once the `notes` row is gone — but this function read
/// the file first, so the one call that could act on that report answered
/// `NotFound` for every Note it listed. The work was preserved and
/// unreachable, which is the promise's letter without its point.
///
/// So the row is opened as the working source with **no bytes behind it**,
/// and the recorded revision is the hash of that absent state — which is what
/// [`NoteSession::write_locked`]'s disk check reads for a file that is not
/// there, so the first tier 2 write passes the OCC comparison and creates the
/// file instead of raising `RevisionMismatch` against nothing. `session_edited`
/// and `unwritten` follow from `restored_from_draft` exactly as they do for
/// the ordinary recovery, so the recreated file also reaches tier 3.
///
/// # Why an open takes the lifecycle lock
///
/// This is the one entry point outside `workspace::lifecycle` that decides
/// whether a concept id exists and then acts on the answer, and it raced
/// `delete_note` between the two. The deletion removes the file, clears the
/// `notes` and `drafts` rows and *then* retires the session
/// ([`discard_session`]); an open that read the file and the row before any of
/// that, and reached its registry insert after all of it, installed a session
/// for a Note that no longer exists in any store. What is left is an orphaned
/// buffer holding the deleted content, reserving the name against
/// `ensure_path_available`, and — because a restored draft arms the idle timer —
/// able to write the file back out and index it. Neither the tier 2 write locks
/// nor the registry lock can close that: the write locks cover sessions that
/// already exist, and the registry lock is released before the read the decision
/// rests on.
///
/// So the whole open runs under [`with_lifecycle_lock`], which is what makes the
/// file and draft reads below the re-verification they have to be: they cannot
/// have been invalidated by a concurrent lifecycle operation, because no such
/// operation can be running. The order is unviolated — the lifecycle lock is the
/// topmost of the five and this function takes only the state lock and the
/// connection beneath it — and nothing here calls a `workspace::lifecycle` entry
/// point, so there is no path back up. The cost is that opening a Note waits
/// behind a rename or a delete in the same Workspace, which is a user-scale
/// operation and not a keystroke: tiers 1 and 2 still take no lifecycle lock at
/// all.
pub fn open_note(
    workspace: &Arc<Workspace>,
    note_id: &str,
) -> Result<(NoteSession, NoteState), AppError> {
    with_lifecycle_lock(workspace, || open_note_serialized(workspace, note_id))
}

/// [`open_note`] for the one caller that already holds the lifecycle lock —
/// `lifecycle::create_note`, which opens the Note it has just created. The lock
/// is not reentrant, so taking it twice on one thread deadlocks rather than
/// nesting.
pub(super) fn open_note_serialized(
    workspace: &Arc<Workspace>,
    note_id: &str,
) -> Result<(NoteSession, NoteState), AppError> {
    if let Some(session) = lookup(workspace.id(), note_id)? {
        let state = session.note_state()?;
        return Ok((session, state));
    }

    let absolute_path = workspace.note_path(note_id)?;
    let on_disk = match std::fs::read(&absolute_path) {
        Ok(bytes) => Some(bytes),
        // Not an error yet: whether this is a Note that does not exist or one
        // whose file was deleted out from under unflushed work is a question
        // only the `drafts` row below can answer.
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
        Err(e) => {
            return Err(AppError::IoError(format!(
                "read {}: {e}",
                absolute_path.display()
            )))
        }
    };

    let draft = workspace.with_db(|conn| read_draft(conn, workspace.id(), note_id))?;
    let restored_from_draft = draft.is_some();
    let awaiting_recreate = on_disk.is_none();
    let revision = content_hash(on_disk.as_deref().unwrap_or(ABSENT_FILE));
    let last_modified = match (&on_disk, &draft) {
        (Some(_), _) => file_mtime(&absolute_path),
        // Nothing to `stat`, so the draft's own `updated_at` — when the work
        // actually happened — is the honest answer, and the same one
        // `pending_drafts` synthesizes for this row.
        (None, Some(row)) => row.updated_at,
        (None, None) => 0,
    };
    let (source, edit_seq) = match (draft, on_disk) {
        (Some(row), _) => (row.raw_markdown, row.edit_seq),
        (None, Some(bytes)) => (decode_source(&absolute_path, bytes)?, 0),
        (None, None) => {
            return Err(AppError::NotFound(format!(
                "no file on disk for concept id {note_id}"
            )))
        }
    };

    let ParsedNote { mut ast, spans } = parse_note(&source, containing_dir(note_id));
    workspace.with_db(|conn| index::resolve_link_existence(conn, workspace.id(), &mut ast))?;
    let metadata = derive_metadata(note_id, &source, &spans, last_modified);

    let state = SessionState {
        source: Arc::new(source),
        spans: Arc::new(spans),
        ast: Arc::new(ast),
        edit_seq,
        revision,
        restored_from_draft,
        awaiting_recreate,
        // A restored draft is by definition work that never reached disk, so
        // this session inherits both the obligation to write it and the one to
        // commit it.
        session_edited: restored_from_draft,
        unwritten: restored_from_draft,
        // An open parses the source as it is, markers and all: the AST and the
        // span map are built from the same bytes by the same call, so every
        // `block_path` addresses the Block it names. Only `reload` collapses a
        // conflict, so only `reload` can set this.
        conflicted: false,
        last_written_at: None,
        last_error: None,
        closed: false,
        metadata,
    };

    let session = NoteSession(Arc::new(SessionInner {
        workspace: Arc::clone(workspace),
        note_id: note_id.to_string(),
        relative_path: concept_id_to_path(note_id),
        absolute_path,
        state: Mutex::new(state),
        tier_one_lock: Mutex::new(()),
        write_lock: Mutex::new(()),
        timer: IdleTimer::new(workspace.idle_interval),
    }));

    // Re-checked under the registry lock rather than trusting the check at the
    // top of this function: two threads opening the same Note race between the
    // two, and the loser would otherwise replace the winner's session in the
    // map — stranding a live buffer, and with it any timer thread already armed
    // against it, while the FFI surface addressed the replacement. Whoever
    // inserts first wins and the other's freshly built session is dropped
    // having done nothing but read.
    let session = match registry()?.entry((workspace.id().to_string(), note_id.to_string())) {
        std::collections::hash_map::Entry::Occupied(existing) => existing.get().clone(),
        std::collections::hash_map::Entry::Vacant(slot) => {
            slot.insert(session.clone());
            if restored_from_draft {
                // Recovered work reaches disk on the same idle interval as work
                // typed in this session, rather than waiting for the user to
                // touch a Note they may have opened only to check that it
                // survived.
                session.arm_idle_timer();
            }
            session
        }
    };
    let note_state = session.note_state()?;
    Ok((session, note_state))
}

// ---------------------------------------------------------------------------
// The session
// ---------------------------------------------------------------------------

impl NoteSession {
    pub fn note_id(&self) -> &str {
        &self.0.note_id
    }

    fn lock_state(&self) -> Result<MutexGuard<'_, SessionState>, AppError> {
        self.0
            .state
            .lock()
            .map_err(|_| AppError::DatabaseError("note state lock poisoned".to_string()))
    }

    /// Serializes tier-1 source mutations through their SQLite draft writes.
    /// It deliberately does not cover tier-2 filesystem I/O.
    fn lock_tier_one(&self) -> Result<MutexGuard<'_, ()>, AppError> {
        self.0
            .tier_one_lock
            .lock()
            .map_err(|_| AppError::DatabaseError("tier 1 lock poisoned".to_string()))
    }

    fn note_state_from(state: &SessionState) -> NoteState {
        NoteState {
            ast: state.ast.as_ref().clone(),
            metadata: state.metadata.clone(),
            base_revision: state.revision.clone(),
            restored_from_draft: state.restored_from_draft,
        }
    }

    /// The current state, as it crosses the FFI boundary.
    pub fn note_state(&self) -> Result<NoteState, AppError> {
        let state = self.lock_state()?;
        Ok(Self::note_state_from(&state))
    }

    /// The working source, for tests and for callers that need the buffer
    /// itself rather than a projection of it.
    pub fn working_source(&self) -> Result<Arc<String>, AppError> {
        Ok(Arc::clone(&self.lock_state()?.source))
    }

    /// The raw Markdown source of one Block (ADR-006 decision 2).
    ///
    /// Refused while the Note holds an unresolved conflict. This reads rather
    /// than writes, but it is addressed the same wrong way as the mutators are
    /// — `[2]` names `Para B.` in the collapsed AST and the conflict's
    /// `incoming` section in the span map — and handing back a Block the caller
    /// did not ask for is how the wrong text reaches the editor in the first
    /// place. [`SessionState::conflicted`] has the whole of it.
    pub fn block_source(&self, block_path: &[usize]) -> Result<String, AppError> {
        let state = self.lock_state()?;
        state.refuse_while_conflicted(&self.0.note_id, "reading a Block's source")?;
        state
            .spans
            .block_source(&state.source, block_path)
            .map(str::to_string)
            .ok_or_else(|| AppError::ParseError(format!("no Block at block_path {block_path:?}")))
    }

    // -- Tier 1 --------------------------------------------------------------

    /// The per-keystroke call: substitute the Block's new source into the
    /// working buffer, adjust the spans arithmetically, and write the draft
    /// row. No parse, no file, no AST returned.
    ///
    /// The ordering is `SPK-WSPC-D001` §6.2.2 with one per-Note extension:
    /// acquire tier 1, mutate, bump the sequence, snapshot, release the state
    /// lock, then write the row while retaining tier 1. The row write is not
    /// cheap: 7.96ms at 102 KiB and 22.79ms at 1 MiB against the
    /// encrypted index on real storage, measured with content that actually
    /// changes (a benchmark rewriting a constant string reports 0.22ms and is
    /// wrong by a factor of 36). It is roughly a thousand times the cost of the
    /// buffer and span work it accompanies. The tier-1 lock is per Note, so it
    /// only serializes concurrent calls targeting that same buffer; the normal
    /// synchronous input path remains one unchanged draft statement, measured
    /// by `a_block_edit_on_a_hundred_kilobyte_note_writes_its_draft_row_within_the_frame_budget`.
    ///
    /// Addresses a **leaf** Block only. A path naming a `List`, `ListItem` or
    /// `Blockquote` is refused with `ParseError` rather than served, because
    /// buffered arithmetic cannot say where that container's child Blocks went
    /// — see [`SpanMap::apply_buffered_edit`]. The caller edits the leaf the
    /// user focused, or routes a genuinely structural change through a
    /// reparsing mutator.
    pub fn update_block(&self, block_path: &[usize], new_source: &str) -> Result<(), AppError> {
        let _tier_one_guard = self.lock_tier_one()?;
        let (snapshot, seq) = {
            let mut guard = self.lock_state()?;
            let state = &mut *guard;
            state.refuse_while_conflicted(&self.0.note_id, "editing a Block")?;
            let span = state
                .spans
                .block(block_path)
                .ok_or_else(|| {
                    AppError::ParseError(format!("no Block at block_path {block_path:?}"))
                })?
                .source
                .clone();
            check_span(&state.source, &span)?;

            // The arithmetic is applied *first*, so that a refused edit leaves
            // the buffer and the map both untouched rather than the buffer
            // spliced against a map that never moved.
            if Arc::make_mut(&mut state.spans)
                .apply_buffered_edit(block_path, new_source.len())
                .is_none()
            {
                return Err(AppError::ParseError(format!(
                    "block_path {block_path:?} addresses a container Block, whose \
                     child spans a buffered edit cannot maintain; edit the Block \
                     that holds the text, or use a reparsing call"
                )));
            }
            // One writer of the working source for this text, and it is here.
            Arc::make_mut(&mut state.source).replace_range(span.clone(), new_source);

            state.edit_seq += 1;
            state.session_edited = true;
            state.unwritten = true;
            (Arc::clone(&state.source), state.edit_seq)
        };

        self.write_draft(&snapshot, seq)?;
        self.arm_idle_timer();
        Ok(())
    }

    /// Resolves a pointer caret in a top-level rendered Block to the actual
    /// editable leaf path and a raw-source UTF-16 caret offset. This reads the
    /// AST and span map installed by the same parse while holding the session
    /// state lock; it never mutates the working source or draft row.
    pub fn resolve_block_caret(
        &self,
        top_level_path: &[usize],
        rendered_utf16_offset: usize,
    ) -> Result<(Vec<usize>, usize), AppError> {
        if top_level_path.len() != 1 {
            return Err(AppError::ParseError(format!(
                "block_path {top_level_path:?} must name exactly one top-level Block"
            )));
        }
        let state = self.lock_state()?;
        let top_level = state.ast.get(top_level_path[0]).ok_or_else(|| {
            AppError::ParseError(format!("no Block at block_path {top_level_path:?}"))
        })?;
        let rendered = crate::markdown::rendered_text(top_level);
        state
            .spans
            .resolve_utf16_caret(
                &state.source,
                top_level_path,
                &rendered,
                rendered_utf16_offset,
            )
            .ok_or_else(|| {
                AppError::ParseError(format!(
                    "rendered UTF-16 offset {rendered_utf16_offset} is invalid for \
                     block_path {top_level_path:?}"
                ))
            })
    }

    // -- Reparsing mutators --------------------------------------------------

    /// Reparses the working source and rebuilds the span map (ADR-007
    /// decision 1). Writes no draft row: `update_block` already wrote whatever
    /// this reparses, and tier 2 clears the row on a successful write, so
    /// writing one here would re-create a row byte-identical to the file
    /// whenever a Block is blurred with no intervening keystrokes.
    ///
    /// The reparse runs holding **no lock at all** — it is the 3.4ms-at-102 KiB
    /// operation of `SPK-WSPC-D001` §4.1, far too long to hold a lock the timer
    /// needs. The install is guarded by an edit-sequence check rather than an
    /// assumption: under FRB the synchronous calls for one Note are serialized
    /// on the Dart thread and the timer never mutates the buffer, so the retry
    /// should never fire, but the failure it would otherwise hide is a span map
    /// describing a buffer that no longer exists.
    ///
    /// This is also where the Note's metadata is re-derived, because it is the
    /// call that reparses what the user typed. `metadata`, `source` and `spans`
    /// are one triple installed together: the title and `okf_conformant` are
    /// read off the frontmatter *span*, so carrying a value forward across a
    /// reparse it was not computed from is stale by construction.
    ///
    /// That is not merely hygienic. The frontmatter block carries no
    /// `block_path` at all (ADR-007 decision 5 — it is a span, not an
    /// `AstNode`), so no FFI call can name it and no session can edit an
    /// existing one in place. What a session *can* do is edit the head of the
    /// file: a Note with no frontmatter has its first Block starting at byte 0,
    /// so `insert_block(&[0], "---\ntype: Note\n…\n---")` makes a frontmatter
    /// span exist where the stored metadata was derived when none did. That is
    /// CAP-PORT-03's bring-a-foreign-file-into-conformance move, it is only
    /// expressible this way precisely because there is no frontmatter path, and
    /// `reparsing_refreshes_the_title_and_the_conformance_flag` pins it.
    /// Without the re-derivation the session would keep reporting
    /// `okf_conformant = false` and commit under the filename-derived title for
    /// the rest of its life.
    pub fn commit_block(&self, _block_path: &[usize]) -> Result<NoteState, AppError> {
        loop {
            let (source, seq) = {
                let state = self.lock_state()?;
                // A reparse of a conflicted buffer would replace the collapsed
                // AST with the raw one — silently un-resolving the Suggestion
                // the user is looking at, and doing it on a blur.
                state.refuse_while_conflicted(&self.0.note_id, "committing a Block")?;
                (Arc::clone(&state.source), state.edit_seq)
            };
            let ParsedNote { mut ast, spans } =
                parse_note(&source, containing_dir(&self.0.note_id));
            self.resolve_links(&mut ast)?;

            let mut state = self.lock_state()?;
            if state.edit_seq != seq {
                continue;
            }
            state.metadata = derive_metadata(
                &self.0.note_id,
                &source,
                &spans,
                state.metadata.last_modified,
            );
            state.ast = Arc::new(ast);
            state.spans = Arc::new(spans);
            // Deliberately no `edit_seq` increment here.
            drop(state);
            return self.note_state();
        }
    }

    /// Inserts a new Block before the one at `block_path`, or at the end of the
    /// Note when the path addresses nothing.
    ///
    /// **Both** seams are normalized, not just the trailing one. Appending a
    /// separator to the inserted text is only sufficient where the insertion
    /// point already sits on a blank-line boundary, and the end-of-Note case —
    /// which is what a path addressing nothing means — is precisely where it
    /// does not: an ordinary Note ends in a single `\n`, so `…Para two.\n` plus
    /// `New block` is one paragraph with a lazy continuation line, and a Note
    /// saved without a trailing newline glues the two together outright. Only a
    /// source that already ended in a blank line behaved.
    ///
    /// A path that addresses a Block inside a container (a list item, a
    /// blockquote's paragraph) is the same case one level down, and is resolved
    /// the same way: the new Block is separated by a blank line, which ends the
    /// container and starts a paragraph after it. That is the promise the name
    /// makes — a *Block*, genuinely separate — rather than a new sibling item,
    /// which would need a call that knows what marker to repeat.
    ///
    /// The **trailing** side is asymmetric on purpose. Mid-Note there is a
    /// following Block to stay separated from, so the full blank line is
    /// emitted; at the end of the Note there is nothing after the insertion, so
    /// the append is terminated with a single `\n` and the file does not gain a
    /// trailing blank line it never had.
    pub fn insert_block(
        &self,
        block_path: &[usize],
        source: String,
    ) -> Result<NoteState, AppError> {
        self.structural_edit(|working, spans, _, _| {
            let target = spans.block(block_path);
            // A path addressing nothing is the end-of-Note append, and it is the
            // one case with no *following* Block to stay separated from. The
            // separator that matters there is the one already emitted before the
            // text; padding the full blank line after it as well left the file
            // ending in one, which is a change to bytes the user did not edit on
            // every append.
            let required_after = if target.is_some() {
                BLOCK_SEPARATOR_NEWLINES
            } else {
                1
            };
            let at = target.map_or(working.len(), |b| b.source.start);
            let before = working
                .get(..at)
                .ok_or_else(|| AppError::ParseError(format!("offset {at} is not addressable")))?;
            // Both seams get the Note's own line ending, not an unconditional
            // `\n`. `before` is the authority when it holds a line ending at
            // all; the whole working source is the fallback for the one case
            // where it does not — an insertion at the very first Block, where
            // `before` is the frontmatter-less head of the file or empty.
            let newline = if before.contains('\n') {
                newline_style(before)
            } else {
                newline_style(working)
            };
            let mut text = separator_before(before, BLOCK_SEPARATOR_NEWLINES);
            text.push_str(&source);
            text.push_str(
                &newline.repeat(required_after.saturating_sub(trailing_newlines(&source))),
            );
            Ok((
                splice::splice_source(working, at..at, &text).map_err(splice_error)?,
                (),
            ))
        })
        .map(|(state, ())| state)
    }

    /// Continues after an editable leaf and returns the new state's actual
    /// first editable leaf path.
    ///
    /// A nearest containing List is continued with a sibling ListItem. Every
    /// other container intentionally exits: the new source is an independent
    /// top-level Block after the leaf's top-level ancestor. In particular,
    /// Enter at the end of a Blockquote paragraph creates a paragraph after
    /// the quote rather than asking the Presentation layer to pretend that a
    /// quote is a List.
    pub fn continue_block_after(
        &self,
        block_path: &[usize],
        source: &str,
    ) -> Result<(NoteState, Vec<usize>), AppError> {
        enum Continuation {
            List {
                marker: String,
                leaf_path: Vec<usize>,
                list_path: Vec<usize>,
                item_index: usize,
            },
            Independent {
                top_level_path: Vec<usize>,
            },
            EmptyNote,
        }

        let (state, focus_parent) =
            self.structural_edit(|working, spans, ast, retained_spans| {
                let continuation = if spans.is_empty() && block_path == [0] {
                    Continuation::EmptyNote
                } else {
                    let live_path = editable_live_path(spans, retained_spans, block_path)?;
                    let leaf = spans.block(&live_path).ok_or_else(|| {
                        AppError::ParseError(format!("no Block at block_path {live_path:?}"))
                    })?;
                    if !leaf.is_leaf() {
                        return Err(AppError::ParseError(format!(
                            "block_path {live_path:?} does not name an editable leaf"
                        )));
                    }
                    match nearest_list_item(ast, &live_path) {
                        Some((list_path, item_index)) => {
                            let prefix = line_prefix_before(working, leaf.source.start)?;
                            Continuation::List {
                                marker: prefix.to_string(),
                                leaf_path: live_path,
                                list_path,
                                item_index,
                            }
                        }
                        None => Continuation::Independent {
                            top_level_path: vec![live_path[0]],
                        },
                    }
                };

                match continuation {
                    Continuation::List {
                        marker,
                        leaf_path,
                        list_path,
                        item_index,
                    } => {
                        // The ListItem container span includes its following
                        // siblings in pulldown-cmark's event ranges; the editable
                        // leaf's end is the exact insertion boundary for this
                        // item's visible content.
                        let at = block_span(spans, &leaf_path)?.end;
                        let new_source =
                            splice::splice_source(working, at..at, &format!("\n{marker}{source}"))
                                .map_err(splice_error)?;
                        let mut item_path = list_path;
                        item_path.push(item_index.saturating_add(1));
                        Ok((new_source, item_path))
                    }
                    Continuation::Independent { top_level_path } => {
                        let next_top_level = top_level_path[0].saturating_add(1);
                        let at = block_span(spans, &top_level_path)?.end;
                        let before = working.get(..at).ok_or_else(|| {
                            AppError::ParseError(format!("offset {at} is not addressable"))
                        })?;
                        let after = working.get(at..).ok_or_else(|| {
                            AppError::ParseError(format!("offset {at} is not addressable"))
                        })?;
                        let newline = if before.contains('\n') {
                            newline_style(before)
                        } else {
                            newline_style(working)
                        };
                        let mut text = separator_before(before, BLOCK_SEPARATOR_NEWLINES);
                        text.push_str(source);
                        let required_after = if after.is_empty() {
                            1
                        } else {
                            BLOCK_SEPARATOR_NEWLINES
                        };
                        let existing_after = leading_newlines(after);
                        text.push_str(&newline.repeat(required_after.saturating_sub(
                            trailing_newlines(source).saturating_add(existing_after),
                        )));
                        Ok((
                            splice::splice_source(working, at..at, &text).map_err(splice_error)?,
                            vec![next_top_level],
                        ))
                    }
                    Continuation::EmptyNote => {
                        let newline = newline_style(working);
                        Ok((format!("{source}{newline}"), vec![0]))
                    }
                }
            })?;
        let focus = self.first_editable_leaf_at(&focus_parent)?;
        Ok((state, focus))
    }

    fn first_editable_leaf_at(&self, parent_path: &[usize]) -> Result<Vec<usize>, AppError> {
        let state = self.lock_state()?;
        state
            .spans
            .blocks()
            .filter(|block| block.is_leaf() && block.path.starts_with(parent_path))
            .map(|block| block.path.clone())
            .min()
            .ok_or_else(|| {
                AppError::ParseError(format!(
                    "continued Block at {parent_path:?} has no editable leaf"
                ))
            })
    }

    /// Deletes a Block, taking the newline run that immediately followed it
    /// with it so the remaining Blocks stay separated by exactly one blank
    /// line.
    ///
    /// # The delete stops at the newline run, not at the next Block
    ///
    /// The removed region is `span.start..span.end` plus the newline run
    /// starting at `span.end` ([`newline_run_len`]) — deliberately **not**
    /// `span.start..next_block_start`, which is what this used to remove.
    /// `markdown::parser` documents a class of bytes that are preserved but
    /// carry no span at all — a raw HTML block, inline HTML, a link reference
    /// definition — and the gap between two registered Blocks is precisely
    /// where those live. Deleting up to the next registered Block therefore
    /// deleted them: `Alpha\n\n<div>…</div>\n\nBeta\n` lost the whole `<div>`
    /// when the user deleted `Alpha`, and a `[ref]: /target.md` definition went
    /// the same way, silently breaking every reference Link that used it. That
    /// is the exact opposite of the guarantee `parser` states — "no edit can
    /// corrupt them and they survive every save byte-identically" — and it
    /// happened on the most routine edit there is.
    ///
    /// # The seam is still normalized
    ///
    /// Whatever newline run separated the deleted region from what follows it
    /// is what must still separate them afterwards, and any of it the preceding
    /// text does not already supply is put back ([`separator_across`]). This is
    /// what keeps the container case honest: `SpanMap::blocks` is flat, so the
    /// "next" Block after the last item of a list is the paragraph *after the
    /// whole list*, and the blank line between them closes the container and
    /// lives inside the last item's own span. Deleting that item removes its
    /// closing blank line with it, and the normalization puts one back, so
    /// `- a\n- b\n\nPara\n` becomes `- a\n\nPara\n` rather than the run-on
    /// `- a\nPara\n`. An ordinary paragraph delete is unaffected — its
    /// predecessor already ends in the blank line the run carried — and a
    /// delete at either end of the Note pads nothing, because there is no seam
    /// to keep apart.
    ///
    /// # The last Block takes the separator *before* it
    ///
    /// There is no newline run after the final Block to consume, so deleting it
    /// left the one that preceded it standing and the Note ended in a blank
    /// line: `A\n\nB\n\nC\n` became `A\n\nB\n\n`. That disagrees with the rule
    /// [`insert_block`](Self::insert_block)'s end-of-Note append keeps — a Note
    /// ends in exactly one line ending — so the two mutators disagreed about the
    /// shape of the same seam, and a delete-then-append round trip wrote a blank
    /// line the user never typed into the file and into version history.
    ///
    /// So when nothing at all remains after the run, the newline run
    /// *preceding* the Block is cut back to a single line ending instead
    /// ([`cut_to_one_trailing_newline`]), which is the same normalization read
    /// from the other side. "Nothing remains" is read off the source rather
    /// than off the span map, since an unaddressable region following the last
    /// registered Block is still text that has to stay separated from it.
    pub fn delete_block(&self, block_path: &[usize]) -> Result<NoteState, AppError> {
        self.structural_edit(|working, spans, _, retained_spans| {
            let live_path = live_path(spans, retained_spans, block_path)?;
            let span = block_span(spans, &live_path)?;
            let after = working.get(span.end..).unwrap_or_default();
            let run_end = span.end + newline_run_len(after);
            let (start, end) = if working.get(run_end..).unwrap_or_default().is_empty() {
                (
                    cut_to_one_trailing_newline(working.get(..span.start).unwrap_or_default()),
                    span.end,
                )
            } else {
                (span.start, run_end)
            };
            check_span(working, &(start..end))?;
            let separator = separator_across(working, start, end);
            Ok((
                splice::splice_source(working, start..end, &separator).map_err(splice_error)?,
                (),
            ))
        })
        .map(|(state, ())| state)
    }

    /// Splits a Block at a Flutter **UTF-16** offset into its source — pressing
    /// Enter mid-Block. The focused Block displays raw source under ADR-006,
    /// and `TextEditingValue` reports its caret in UTF-16 code units.
    ///
    /// The offset is converted against the Block's own source before anything
    /// indexes with it. Everything below this line — spans, splice ranges, the
    /// whole of `markdown::spans` — stays in bytes, which is what `SpanMap`
    /// records and what `String::replace_range` needs. A surrogate interior is
    /// refused rather than rounded to a neighbouring Unicode scalar.
    ///
    /// An offset past the Block's last UTF-16 code unit is refused rather than
    /// clamped — a caret the Block cannot hold names no split point.
    pub fn split_block(&self, block_path: &[usize], offset: usize) -> Result<NoteState, AppError> {
        self.structural_edit(|working, spans, _, retained_spans| {
            let live_path = editable_live_path(spans, retained_spans, block_path)?;
            let span = block_span(spans, &live_path)?;
            let block_source = working.get(span.clone()).ok_or_else(|| {
                AppError::ParseError(format!(
                    "source range {}..{} is not addressable in this Note",
                    span.start, span.end
                ))
            })?;
            let Some(byte_offset) = crate::markdown::spans::utf16_to_byte_offset(block_source, offset) else {
                return Err(AppError::ParseError(format!(
                    "split UTF-16 offset {offset} is not a character boundary in block_path {live_path:?}"
                )));
            };
            let at = span.start + byte_offset;
            let before = working
                .get(..at)
                .ok_or_else(|| AppError::ParseError(format!("offset {at} is not addressable")))?;
            let newline = if before.contains('\n') {
                newline_style(before)
            } else {
                newline_style(working)
            };
            Ok((
                splice::splice_source(working, at..at, &newline.repeat(2)).map_err(splice_error)?,
                (),
            ))
        })
        .map(|(state, ())| state)
    }

    /// Splits using the raw source and UTF-16 caret coordinate held by the
    /// editor field. Unlike [`split_block`](Self::split_block), this retains
    /// the caller's coordinate space when a buffered edit changed the AST
    /// shape (for example a paragraph became a List). The returned focus path
    /// and caret name the second half after Core reparses the splice.
    pub fn split_block_from_editor_source(
        &self,
        block_path: &[usize],
        editor_source: &str,
        offset: usize,
    ) -> Result<(NoteState, Vec<usize>, usize), AppError> {
        let (state, (block_path, caret_offset)) = self.structural_edit(|working, spans, _, retained_spans| {
            let retained = retained_spans.block(block_path).ok_or_else(|| {
                AppError::ParseError(format!("no Block at block_path {block_path:?}"))
            })?;
            if !retained.is_leaf() {
                return Err(AppError::ParseError(format!(
                    "block_path {block_path:?} does not name an editable leaf"
                )));
            }
            let retained_source = working.get(retained.source.clone()).ok_or_else(|| {
                AppError::ParseError(format!(
                    "source range {}..{} is not addressable in this Note",
                    retained.source.start, retained.source.end
                ))
            })?;
            if retained_source != editor_source {
                return Err(AppError::ParseError(format!(
                    "editor source no longer matches block_path {block_path:?}; refusing stale split"
                )));
            }
            let Some(editor_byte_offset) = crate::markdown::spans::utf16_to_byte_offset(editor_source, offset) else {
                return Err(AppError::ParseError(format!(
                    "split UTF-16 offset {offset} is not a character boundary in block_path {block_path:?}"
                )));
            };
            let live_path = editable_live_path(spans, retained_spans, block_path)?;
            let span = block_span(spans, &live_path)?;
            let field_relative_start = span.start.checked_sub(retained.source.start).ok_or_else(|| {
                AppError::ParseError(format!(
                    "live leaf {live_path:?} lies outside the editor source for block_path {block_path:?}"
                ))
            })?;
            let field_relative_end = span.end.checked_sub(retained.source.start).ok_or_else(|| {
                AppError::ParseError(format!(
                    "live leaf {live_path:?} lies outside the editor source for block_path {block_path:?}"
                ))
            })?;
            if editor_byte_offset < field_relative_start || editor_byte_offset > field_relative_end {
                return Err(AppError::ParseError(format!(
                    "split UTF-16 offset {offset} is outside the current editable leaf for block_path {block_path:?}"
                )));
            }
            let at = span.start + (editor_byte_offset - field_relative_start);
            // The same seam consistency `insert_block` keeps, for the same
            // reason: a blank line spelled `\n\n` inside a CRLF-authored Note is
            // whitespace noise in a diff the user did not ask for.
            let before = working
                .get(..at)
                .ok_or_else(|| AppError::ParseError(format!("offset {at} is not addressable")))?;
            let newline = if before.contains('\n') {
                newline_style(before)
            } else {
                newline_style(working)
            };
            let separator = newline.repeat(2);
            let new_source =
                splice::splice_source(working, at..at, &separator).map_err(splice_error)?;
            // Resolve against the post-splice parse before structural_edit
            // installs anything, preserving its all-or-nothing error boundary.
            let reparsed = parse_note(&new_source, containing_dir(&self.0.note_id));
            let focus = editable_leaf_at_or_after_source_offset(
                &new_source,
                &reparsed.spans,
                at + separator.len(),
            )?;
            Ok((new_source, focus))
        })?;
        Ok((state, block_path, caret_offset))
    }

    /// Merges a Block into its predecessor — Backspace at offset 0.
    ///
    /// The returned path and caret are authoritative after the reparse. A
    /// first Block is unchanged and returns that same leaf at offset zero.
    ///
    /// The merge deletes `previous_block_end..span.start`, which for two
    /// adjacent Blocks is nothing but the blank line between them. It is not
    /// always only that: the same gap [`delete_block`](Self::delete_block)
    /// stopped reaching into is where `markdown::parser`'s preserved-but-
    /// unaddressable regions live, so a Block whose predecessor is separated
    /// from it by a raw HTML block or a link reference definition has that
    /// region *inside* the gap, and merging absorbed it without a trace.
    ///
    /// Refused rather than fixed, because there is no correct answer to fix it
    /// to: the user pressed Backspace at the start of a Block believing it is
    /// adjacent to the one above, and the editor cannot show them what sits in
    /// between (rendering raw HTML in place is `EPIC-F`'s raw-mode work). Both
    /// silent alternatives are wrong — dropping the region destroys bytes
    /// nothing asked to touch, and hopping over it joins two Blocks that are
    /// not neighbours. The error names the content so the message is actionable
    /// rather than a bare refusal.
    pub fn merge_block_with_previous(
        &self,
        block_path: &[usize],
    ) -> Result<(NoteState, Vec<usize>, usize), AppError> {
        let (state, (focus_path, caret_offset)) =
            self.structural_edit(|working, spans, ast, retained_spans| {
                let live_path = editable_live_path(spans, retained_spans, block_path)?;
                let span = block_span(spans, &live_path)?;

                if let Some((list_path, item_index)) = nearest_list_item(ast, &live_path) {
                    let mut item_path = list_path.clone();
                    item_path.push(item_index);
                    let first_item_leaf =
                        first_editable_leaf(spans, &item_path).ok_or_else(|| {
                            AppError::ParseError(format!(
                                "ListItem at block_path {item_path:?} has no editable leaf"
                            ))
                        })?;

                    if item_index > 0 && first_item_leaf.path == live_path {
                        let mut previous_item_path = list_path;
                        previous_item_path.push(item_index - 1);
                        let previous_leaf = last_editable_leaf(spans, &previous_item_path)
                            .ok_or_else(|| {
                                AppError::ParseError(format!(
                            "ListItem at block_path {previous_item_path:?} has no editable leaf"
                        ))
                            })?;
                        let prefix = line_prefix_before(working, span.start)?;
                        let gap = working
                            .get(previous_leaf.source.end..span.start)
                            .ok_or_else(|| {
                                AppError::ParseError(format!(
                                    "source range {}..{} is not addressable in this Note",
                                    previous_leaf.source.end, span.start
                                ))
                            })?;
                        let expected_gap = format!("{}{prefix}", newline_style(working));
                        if gap == expected_gap {
                            let caret_offset = source_caret_before_trailing_newline(
                                working.get(previous_leaf.source.clone()).ok_or_else(|| {
                                    AppError::ParseError(format!(
                                        "source range {}..{} is not addressable in this Note",
                                        previous_leaf.source.start, previous_leaf.source.end
                                    ))
                                })?,
                            );
                            return Ok((
                                splice::splice_source(
                                    working,
                                    previous_leaf.source.end..span.start,
                                    "",
                                )
                                .map_err(splice_error)?,
                                (previous_leaf.path.clone(), caret_offset),
                            ));
                        }
                    }
                }

                // The first editable leaf of a top-level List or Blockquote
                // follows its predecessor through visible container syntax
                // (`- ` or `> `). That syntax is a seam the merge consumes,
                // not hidden content. Treat it like the sibling-list seam
                // above, while requiring an exact source match so raw HTML and
                // reference definitions in the gap remain refusals.
                if let Some(top_level_index) = live_path.first().copied() {
                    if top_level_index > 0
                        && matches!(
                            ast.get(top_level_index),
                            Some(AstNode::List { .. } | AstNode::Blockquote { .. })
                        )
                        && first_editable_leaf(spans, &[top_level_index])
                            .is_some_and(|first| first.path == live_path)
                    {
                        let previous_leaf = last_editable_leaf(spans, &[top_level_index - 1])
                            .ok_or_else(|| {
                                AppError::ParseError(format!(
                                    "top-level Block {} has no editable predecessor",
                                    top_level_index - 1
                                ))
                            })?;
                        let prefix = line_prefix_before(working, span.start)?;
                        let gap = working
                            .get(previous_leaf.source.end..span.start)
                            .ok_or_else(|| {
                                AppError::ParseError(format!(
                                    "source range {}..{} is not addressable in this Note",
                                    previous_leaf.source.end, span.start
                                ))
                            })?;
                        let expected_gap = format!("{}{prefix}", newline_style(working));
                        if gap == expected_gap {
                            let caret_offset = source_caret_before_trailing_newline(
                                working.get(previous_leaf.source.clone()).ok_or_else(|| {
                                    AppError::ParseError(format!(
                                        "source range {}..{} is not addressable in this Note",
                                        previous_leaf.source.start, previous_leaf.source.end
                                    ))
                                })?,
                            );
                            return Ok((
                                splice::splice_source(
                                    working,
                                    previous_leaf.source.end..span.start,
                                    "",
                                )
                                .map_err(splice_error)?,
                                (previous_leaf.path.clone(), caret_offset),
                            ));
                        }
                    }
                }

                let Some(previous_end) = previous_block_end(spans, &span) else {
                    return Ok((working.to_string(), (live_path, 0)));
                };
                let previous_leaf = previous_editable_leaf(spans, &span).ok_or_else(|| {
                    AppError::ParseError(format!(
                        "block_path {live_path:?} has no editable predecessor"
                    ))
                })?;
                let gap = working.get(previous_end..span.start).ok_or_else(|| {
                    AppError::ParseError(format!(
                        "source range {}..{} is not addressable in this Note",
                        previous_end, span.start
                    ))
                })?;
                if !gap.trim().is_empty() {
                    return Err(AppError::ParseError(format!(
                        "block_path {live_path:?} cannot be merged with the Block before it: \
                     the two are separated by content this editor does not render and \
                     cannot address, and the merge would delete it — {}",
                        elided(gap, 60)
                    )));
                }
                let caret_offset = source_caret_before_trailing_newline(
                    working.get(previous_leaf.source.clone()).ok_or_else(|| {
                        AppError::ParseError(format!(
                            "source range {}..{} is not addressable in this Note",
                            previous_leaf.source.start, previous_leaf.source.end
                        ))
                    })?,
                );
                Ok((
                    splice::splice_source(working, previous_end..span.start, "")
                        .map_err(splice_error)?,
                    (previous_leaf.path.clone(), caret_offset),
                ))
            })?;
        Ok((state, focus_path, caret_offset))
    }

    /// Deletes a multi-Block selection (ADR-006 decision 3).
    pub fn delete_range(
        &self,
        range: &RenderedRange,
    ) -> Result<(NoteState, RangeEditLocation), AppError> {
        self.replace_range(range, "")
    }

    /// Replaces a multi-Block selection with text and derives the caret from
    /// the resulting parse, never from the source tree the replacement
    /// invalidates.
    pub fn replace_range(
        &self,
        range: &RenderedRange,
        replacement: &str,
    ) -> Result<(NoteState, RangeEditLocation), AppError> {
        self.structural_edit_with_result(
            |working, spans, _, _| {
                let resolved =
                    splice::resolve_range(working, spans, range).map_err(splice_error)?;
                let join = resolved
                    .start
                    .checked_add(replacement.len())
                    .ok_or_else(|| {
                        AppError::ParseError(
                            "range replacement join overflowed source offset".to_string(),
                        )
                    })?;
                Ok((
                    splice::splice_source(working, resolved, replacement).map_err(splice_error)?,
                    join,
                ))
            },
            |source, spans, _, join| range_edit_caret(source, spans, join),
        )
    }

    /// The Markdown a multi-Block selection covers — a slice of the Note, never
    /// a reconstruction of one.
    ///
    /// Refused while the Note is conflicted for [`block_source`](Self::block_source)'s
    /// reason: a `RenderedRange` is two `block_path`s, and neither addresses
    /// the Block the caller selected.
    pub fn copy_range_as_markdown(&self, range: &RenderedRange) -> Result<String, AppError> {
        let state = self.lock_state()?;
        state.refuse_while_conflicted(&self.0.note_id, "copying a range")?;
        Ok(splice::extract_range(&state.source, &state.spans, range)
            .map_err(splice_error)?
            .to_string())
    }

    /// The shared shape of every structural mutator: snapshot under the state
    /// lock, reparse that live source for the operation's address map, compute
    /// the new source and reparse **off** it, install under an edit-sequence
    /// check, then write the draft row while retaining the per-Note tier-1
    /// lock. The state lock is still released before SQLite.
    ///
    /// Each of these is a discrete user action rather than a keystroke, which
    /// is what keeps the reparse off the typing path — and each writes its
    /// draft row here, before the write tier fires, which is ADR-008
    /// decision 1's whole point.
    fn structural_edit<T>(
        &self,
        edit: impl Fn(&str, &SpanMap, &[AstNode], &SpanMap) -> Result<(String, T), AppError>,
    ) -> Result<(NoteState, T), AppError> {
        self.structural_edit_with_result(edit, |_, _, _, result| Ok(result))
    }

    /// The structural transaction with a result derived from the one
    /// post-splice parse. This is used when a result is meaningful only in the
    /// new tree (for example the range-edit caret), while preserving the
    /// snapshot/retry/install/draft sequence shared by every structural edit.
    fn structural_edit_with_result<T, U>(
        &self,
        edit: impl Fn(&str, &SpanMap, &[AstNode], &SpanMap) -> Result<(String, T), AppError>,
        derive_result: impl Fn(&str, &SpanMap, &[AstNode], T) -> Result<U, AppError>,
    ) -> Result<(NoteState, U), AppError> {
        // This stays held until the draft write either succeeds or rolls the
        // mutation back. No later tier-1 edit can make our caller's result
        // stale between installation and this method's return.
        let _tier_one_guard = self.lock_tier_one()?;
        loop {
            let (source, retained_spans, seq) = {
                let state = self.lock_state()?;
                state.refuse_while_conflicted(&self.0.note_id, "a structural edit")?;
                (
                    Arc::clone(&state.source),
                    Arc::clone(&state.spans),
                    state.edit_seq,
                )
            };
            // `update_block` deliberately leaves its AST and inline map stale
            // until a reparse-producing action. Structural actions must never
            // classify or splice through that retained view: source is the
            // transaction's authority, so derive the operation map from it.
            let ParsedNote {
                ast: live_ast,
                spans: live_spans,
            } = parse_note(&source, containing_dir(&self.0.note_id));
            let (new_source, result) = edit(&source, &live_spans, &live_ast, &retained_spans)?;
            let ParsedNote { mut ast, spans } =
                parse_note(&new_source, containing_dir(&self.0.note_id));
            self.resolve_links(&mut ast)?;
            let result = derive_result(&new_source, &spans, &ast, result)?;

            let (snapshot, new_seq, previous) = {
                let mut guard = self.lock_state()?;
                let state = &mut *guard;
                if state.edit_seq != seq {
                    continue;
                }
                // Tier 1 writes after releasing the state lock. Keep the
                // complete part of state this mutation replaces so a failed
                // draft write can put the session back exactly where it was
                // rather than leaving a change installed with no crash-safe
                // copy and no timer.
                let previous = StructuralEditRollback {
                    source: Arc::clone(&state.source),
                    spans: Arc::clone(&state.spans),
                    ast: Arc::clone(&state.ast),
                    metadata: state.metadata.clone(),
                    edit_seq: state.edit_seq,
                    revision: state.revision.clone(),
                    session_edited: state.session_edited,
                    unwritten: state.unwritten,
                };
                // Re-derived for the same reason `commit_block` re-derives it:
                // metadata is read off the frontmatter span, and these
                // mutators install a new span map — including for an edit at
                // the head of a frontmatter-less Note, where `insert_block`
                // and the range operations both splice at byte 0.
                state.metadata = derive_metadata(
                    &self.0.note_id,
                    &new_source,
                    &spans,
                    state.metadata.last_modified,
                );
                state.source = Arc::new(new_source);
                state.spans = Arc::new(spans);
                state.ast = Arc::new(ast);
                state.edit_seq += 1;
                state.session_edited = true;
                state.unwritten = true;
                (Arc::clone(&state.source), state.edit_seq, previous)
            };

            if let Err(error) = self.write_draft(&snapshot, new_seq) {
                let (reverted, state) = {
                    let mut guard = self.lock_state()?;
                    let state = &mut *guard;
                    // The tier-1 lock prevents another source mutation here,
                    // but retain the sequence check as a defensive boundary.
                    // A tier-2 writer may have published this source while a
                    // previously armed timer was firing; its advanced revision
                    // makes the same rollback unsafe.
                    if state.edit_seq != new_seq || state.revision != previous.revision {
                        (false, Self::note_state_from(state))
                    } else {
                        state.source = previous.source;
                        state.spans = previous.spans;
                        state.ast = previous.ast;
                        state.metadata = previous.metadata;
                        state.edit_seq = previous.edit_seq;
                        state.session_edited = previous.session_edited;
                        state.unwritten = previous.unwritten;
                        (true, Self::note_state_from(state))
                    }
                };
                if !reverted {
                    // We cannot safely undo a source that another mutation or
                    // tier-2 writer has observed. Keep that authoritative
                    // state recoverable instead of stranding it in memory.
                    self.arm_idle_timer();
                    // The source remains the one this call installed; the
                    // tier-1 lock prevents a later edit sequence from making
                    // `result` stale. A tier-2 revision advance merely means
                    // these same bytes have already reached disk.
                    return Ok((state, result));
                }
                return Err(error);
            }
            self.arm_idle_timer();
            return Ok((self.note_state()?, result));
        }
    }

    /// Fills in `InlineElement::Link.exists`, the one field the parser cannot:
    /// it is whether the target concept id matches a `notes` row, which only
    /// the index knows (`WSPC-D005`). Every reparsing path runs it, since a
    /// reparse produces fresh Link nodes carrying the parser's `false`.
    ///
    /// Called with no state lock held, like every other database access here.
    fn resolve_links(&self, ast: &mut [AstNode]) -> Result<(), AppError> {
        let workspace_id = self.0.workspace.id().to_string();
        self.0
            .workspace
            .with_db(|conn| index::resolve_link_existence(conn, &workspace_id, ast))
    }

    /// Writes the tier 1 row, never letting it go backwards.
    ///
    /// The `WHERE excluded.edit_seq > drafts.edit_seq` guard makes "the row
    /// holds the newest edit" a property of this statement rather than an
    /// assumption about FRB serializing the calls that produce it. Without it,
    /// two tier 1 writes completing out of order would leave the older bytes in
    /// the row *under the newer sequence's protection from the conditional
    /// clear* — the one combination that both loses an edit and hides that it
    /// did.
    fn write_draft(&self, source: &str, edit_seq: i64) -> Result<(), AppError> {
        #[cfg(test)]
        if let Some(hook) = self.0.workspace.before_draft_write.lock().unwrap().clone() {
            hook();
        }
        let workspace_id = self.0.workspace.id().to_string();
        let note_id = self.0.note_id.clone();
        let now = unix_now();
        self.0.workspace.with_db(|conn| {
            conn.execute(
                "INSERT INTO drafts (workspace_id, note_id, raw_markdown, updated_at, edit_seq) \
                 VALUES (?1, ?2, ?3, ?4, ?5) \
                 ON CONFLICT(workspace_id, note_id) DO UPDATE SET \
                     raw_markdown = excluded.raw_markdown, \
                     updated_at = excluded.updated_at, \
                     edit_seq = excluded.edit_seq \
                 WHERE excluded.edit_seq > drafts.edit_seq",
                rusqlite::params![workspace_id, note_id, source, now, edit_seq],
            )?;
            Ok(())
        })
    }

    // -- Tier 2 --------------------------------------------------------------

    /// Forces tier 2: writes the working source to the file atomically and
    /// returns the new revision.
    ///
    /// Takes no revision token from the caller, deliberately. The Core holds
    /// the baseline and re-records it after every success, so a token the UI
    /// held from `open_note` would be stale by construction — a Core-owned idle
    /// timer advances the revision without the UI ever observing it.
    pub fn flush(&self) -> Result<String, AppError> {
        self.flush_covering().map(|written| written.revision)
    }

    /// [`flush`](Self::flush), reporting **which edit sequence the write
    /// covered** as well as the new revision.
    ///
    /// `close_note` needs the sequence, not just the revision: clearing the
    /// draft row unconditionally afterwards would destroy a keystroke that
    /// landed between the write and the clear, and `SPK-WSPC-D001` §6.2.6's
    /// asymmetry says that direction of error costs the user's work while the
    /// other costs one spurious recovery notice.
    fn flush_covering(&self) -> Result<WrittenThrough, AppError> {
        let _write_guard = self.lock_writes()?;

        let (source, seq, revision, closed) = {
            let state = self.lock_state()?;
            (
                Arc::clone(&state.source),
                state.edit_seq,
                state.revision.clone(),
                state.closed,
            )
        };
        if closed {
            return Ok(WrittenThrough { revision, seq });
        }

        match self.write_locked(&source, seq, &revision) {
            Ok(revision) => Ok(WrittenThrough { revision, seq }),
            Err(error) => {
                // Failing toward keeping the draft row: the row is what holds
                // the user's unwritten work, and every ambiguous case resolves
                // toward keeping it.
                let mut state = self.lock_state()?;
                state.last_error = Some(error.clone());
                Err(error)
            }
        }
    }

    /// The tier 2 write lock. Taken by tier 2 writers only — the idle timer,
    /// `flush`, `close` and `reload` — and never by a call that merely mutates
    /// state, so no keystroke can wait on it even though it is held across the
    /// file I/O it exists to serialize.
    fn lock_writes(&self) -> Result<MutexGuard<'_, ()>, AppError> {
        self.0
            .write_lock
            .lock()
            .map_err(|_| AppError::DatabaseError("tier 2 write lock poisoned".to_string()))
    }

    /// The OCC sequence, run entirely under the tier 2 write lock: compare the
    /// bytes on disk against the recorded revision, write atomically, clear the
    /// draft row conditionally, re-record the revision.
    ///
    /// Without one lock spanning all of it, two tier 2 writers — the idle timer
    /// and a `close_note` — both read the same revision, both pass, and the
    /// second silently discards the first.
    ///
    /// **A session that opened over no file at all creates one here**, which
    /// is the only case where a missing file is not this function's error to
    /// raise. [`SessionState::awaiting_recreate`] is what distinguishes it
    /// from a file deleted underneath a live session: the latter still reports
    /// `NotFound`, because `close` reads that as the deletion it is and keeps
    /// the draft row. For the former the absent file *is* the state the
    /// baseline was recorded against, so it compares as the empty one and the
    /// write goes ahead — unconditionally, since a recovered draft that
    /// happens to be empty hashes equal to the absent file and would otherwise
    /// leave nothing on disk at all.
    fn write_locked(&self, source: &str, seq: i64, revision: &str) -> Result<String, AppError> {
        let awaiting_recreate = self.lock_state()?.awaiting_recreate;
        let on_disk = match self.read_file() {
            Ok(bytes) => bytes,
            Err(AppError::NotFound(_)) if awaiting_recreate => ABSENT_FILE.to_vec(),
            Err(error) => return Err(error),
        };
        let disk_revision = content_hash(&on_disk);
        if disk_revision != revision {
            // The file changed underneath the draft. The file is left exactly
            // as it is, and the current revision travels with the error so the
            // caller can offer a reload rather than guess. A recreating
            // session reaches this when the file *came back* between the open
            // and this write — a sync, a restore from the trash — and the
            // exit is the same one: the user is offered the reload rather than
            // having the returned bytes overwritten by a draft.
            return Err(AppError::RevisionMismatch(disk_revision));
        }

        let new_revision = content_hash(source.as_bytes());
        if new_revision != disk_revision || awaiting_recreate {
            if awaiting_recreate {
                self.ensure_containing_directory()?;
            }
            atomic_write(&self.0.absolute_path, source.as_bytes())?;
        }

        // The baseline is re-recorded **here**, the instant the bytes are on
        // disk, and not after the two steps below.
        //
        // Both of those steps are independently recoverable — a draft row that
        // outlives its write costs one spurious "restored from draft" notice,
        // and a stale `notes` row is repaired by the next write or a reindex —
        // but a database error in either used to abort before the baseline
        // moved, leaving the recorded revision describing bytes the file no
        // longer has. The next tick then compared a fresh disk hash against
        // that stale baseline and raised `RevisionMismatch`, whose only exit is
        // `reload` — and reload discards the buffer. A recoverable index error
        // was being converted into a prompt that destroys the user's unwritten
        // work, which is exactly the direction `SPK-WSPC-D001` §6.2.6 forbids.
        //
        // Taken and released on its own, rather than by hoisting the whole
        // state update up here: the two calls below acquire the connection, and
        // the module's acquisition order forbids holding the state lock across
        // that.
        {
            let mut state = self.lock_state()?;
            state.revision = new_revision.clone();
            // The file exists again, so any *later* disappearance is an
            // external deletion like any other and must surface as one rather
            // than being silently undone by the next write.
            state.awaiting_recreate = false;
        }

        self.clear_draft_through(seq)?;
        self.index_written_source(source, &new_revision)?;

        let mut state = self.lock_state()?;
        state.metadata.last_modified = unix_now();
        state.last_written_at = Some(unix_now());
        state.last_error = None;
        state.unwritten = state.edit_seq > seq;
        // `restored_from_draft` is deliberately left alone. It is a fact about
        // how this session *started* — the previous one ended without tier 2
        // flushing — not about whether the buffer is currently on disk, and
        // `SHEL-E007`'s recovery notice would otherwise disappear a second
        // after it appeared, on the first idle write. `reload` clears it,
        // because that call replaces the recovered buffer outright.
        Ok(new_revision)
    }

    /// Recreates the directory that was removed along with the Note's file.
    ///
    /// Only reached on [`write_locked`](Self::write_locked)'s recreate path,
    /// and only for a level that is genuinely gone: deleting a Note in a file
    /// manager often means deleting the folder it was in, and without this the
    /// recovered session's every write fails with an `IoError` that `close`
    /// does not treat as a vanished file — leaving the session unclosable,
    /// which is the exact trap the recovery path exists to open. It creates
    /// nothing that was not already the Note's own containing directory, so
    /// `create_note`'s rule that a Directory must exist before a Note goes
    /// into it is not weakened here.
    fn ensure_containing_directory(&self) -> Result<(), AppError> {
        assert_no_io_under_the_connection("recreating a Note's directory");
        let Some(parent) = self.0.absolute_path.parent() else {
            return Ok(());
        };
        if parent.is_dir() {
            return Ok(());
        }
        std::fs::create_dir_all(parent)
            .map_err(|e| AppError::IoError(format!("create {}: {e}", parent.display())))
    }

    /// The Note's bytes as they are on disk right now.
    ///
    /// A file that is gone reports `NotFound` rather than a generic I/O error,
    /// because the two have different exits: `NotFound` here means the file was
    /// deleted by something outside this application — another tool, or the
    /// user in a file manager — and `close` treats it as such rather than
    /// leaving the session unclosable. The one caller that means something
    /// else by an absent file — [`NoteSession::write_locked`] recreating one —
    /// says so at its own call site rather than by weakening this one.
    fn read_file(&self) -> Result<Vec<u8>, AppError> {
        assert_no_io_under_the_connection("reading a Note's file");
        std::fs::read(&self.0.absolute_path).map_err(|e| {
            if e.kind() == std::io::ErrorKind::NotFound {
                AppError::NotFound(format!(
                    "the file for {} is no longer on disk",
                    self.0.note_id
                ))
            } else {
                AppError::IoError(format!("read {}: {e}", self.0.absolute_path.display()))
            }
        })
    }

    /// Brings the index level with the bytes tier 2 just wrote, **without
    /// putting file I/O or a parse inside the connection closure**.
    ///
    /// `index::incremental::index_note` would be the obvious call and is the
    /// wrong one here: it re-reads the file, stats it, and on a changed hash
    /// parses it — all O(file) work, and all of it would run under the
    /// process-wide connection mutex that a keystroke's own tier 1 write has to
    /// acquire. That is the composition `SPK-WSPC-D001` §6.2.7 forbids in as
    /// many words ("no closure passed to `with_connection` may perform file
    /// I/O"), and it is exactly what this tier would have broken first. The
    /// bytes are already in hand, so the hash comparison, the `stat` and the
    /// derivation all happen out here and the two closures below run SQL only.
    ///
    /// The short-circuit is kept because it is what makes this cheap on the
    /// common path: a write that changed nothing costs one indexed lookup
    /// rather than a parse and a link walk.
    fn index_written_source(&self, source: &str, revision: &str) -> Result<(), AppError> {
        let workspace_id = self.0.workspace.id().to_string();
        let note_id = self.0.note_id.clone();
        let stored = self.0.workspace.with_db(|conn| {
            index::incremental::stored_content_hash(conn, &workspace_id, &note_id)
        })?;
        if stored.as_deref() == Some(revision) {
            return Ok(());
        }

        let note = index::derive_note(
            &note_id,
            source,
            revision.to_string(),
            file_mtime(&self.0.absolute_path),
        );
        self.0.workspace.with_db(|conn| {
            index::incremental::write_note_rows(conn, &workspace_id, &note)?;
            Ok(())
        })
    }

    /// Clears the draft row **only if it holds nothing newer than what is now
    /// on disk**, evaluated atomically against the row rather than against a
    /// counter that leads it.
    ///
    /// `SPK-WSPC-D001` §6.2.6 is what forbids the obvious alternative: a tier 1
    /// write releases the state lock before its own 8-23ms row write, so a
    /// timer that snapshotted at sequence N, wrote the file, re-acquired and
    /// observed an in-memory counter still reading N would clear a row the
    /// keystroke is about to write — and the keystroke would then write row(N)
    /// into a table the timer believed it had emptied. The counter compared is
    /// therefore the row's.
    ///
    /// `<=` rather than `=` because a row *lagging* the snapshot is also
    /// redundant once the newer bytes are on disk, and refusing to clear it
    /// would leave `open_note` preferring an older draft over a newer file.
    ///
    /// The residual case is benign and stated so it is not mistaken for a
    /// defect: a keystroke's row landing *after* this statement survives
    /// holding bytes identical to disk, which is a false "restored from draft"
    /// rather than a loss, cleared by the next firing. The asymmetry is the
    /// point — failing to clear costs one spurious recovery notice, clearing
    /// wrongly costs the user's work — and it is why `close` clears through the
    /// sequence its own flush covered rather than clearing outright.
    fn clear_draft_through(&self, seq: i64) -> Result<(), AppError> {
        let workspace_id = self.0.workspace.id().to_string();
        let note_id = self.0.note_id.clone();
        self.0.workspace.with_db(|conn| {
            conn.execute(
                "DELETE FROM drafts WHERE workspace_id = ?1 AND note_id = ?2 AND edit_seq <= ?3",
                rusqlite::params![workspace_id, note_id, seq],
            )?;
            Ok(())
        })
    }

    /// Arms (or re-arms) the idle timer. Called by every tier 1 mutator, so the
    /// interval always measures time since the last edit.
    fn arm_idle_timer(&self) {
        self.0.timer.arm(&self.0);
    }

    // -- Status --------------------------------------------------------------

    pub fn write_status(&self) -> Result<NoteWriteStatus, AppError> {
        let state = self.lock_state()?;
        Ok(NoteWriteStatus {
            last_written_at: state.last_written_at,
            last_error: state.last_error.clone(),
            has_unwritten_edits: state.unwritten,
        })
    }

    // -- Reload --------------------------------------------------------------

    /// Discards the buffered edits and re-reads the Note from disk: reparses
    /// the file's current bytes, deletes the draft row once those bytes are in
    /// hand, and rebuilds the working source, the span map and the revision
    /// baseline from them.
    ///
    /// This is the other half of `RevisionMismatch`, and without it that error
    /// has no exit — `open_note` restores the draft in preference to disk, so a
    /// reopen would hand back the buffer that just lost the comparison and fail
    /// again on every tick, forever.
    ///
    /// It is also the only call that reads bytes this application did not write
    /// into a Note that is already open, which is why it is where conflict
    /// markers become `Suggestion` nodes.
    ///
    /// It runs under the **tier 2 write lock** for its whole length, because it
    /// re-records the OCC baseline and is therefore a tier 2 writer in the only
    /// sense that matters: without the lock, a concurrent idle write can land
    /// between this read and the baseline it derives from it, leaving the Core
    /// recording a revision the file no longer has — the time-of-check to
    /// time-of-use hole `SPK-WSPC-D001` §6.2.5 gave the lock to close. The
    /// acquisition order is unchanged: write lock, then state, then connection.
    ///
    /// **It does not clear `session_edited`**, and that is a decision rather
    /// than an omission. Work this session already wrote to disk before the
    /// reload is on disk still, and clearing the flag would drop it out of
    /// history at close for no gain: the pathspec commit no-ops when the path
    /// already matches `HEAD`, so keeping the flag costs an unchanged-tree
    /// check and buys the user's own pre-reload writes their commit. What is
    /// discarded here is the *buffer*, which is unwritten by definition.
    pub fn reload(&self) -> Result<NoteState, AppError> {
        let _write_guard = self.lock_writes()?;

        // **The row is deleted only once the bytes that are to replace it are
        // in hand**, and the order below is the whole of that guarantee: read,
        // hash, decode, and only then clear. Clearing first destroyed the
        // draft on exactly the two failures a reload is most likely to hit —
        // a file something outside this application deleted, and one that has
        // gone invalid underneath the session — and both of those are the
        // cases where the row *is* the user's work. `close` keeps the row for
        // a vanished file so `pending_drafts` can report it and `open_note`
        // can recover it; a reload attempted on the way to that recovery must
        // not be the call that throws it away.
        let bytes = self.read_file()?;
        let revision = content_hash(&bytes);
        let source = decode_source(&self.0.absolute_path, bytes)?;

        let dir = containing_dir(&self.0.note_id);
        let ParsedNote { ast, spans } = parse_note(&source, dir);
        let collapsed = conflict_suggestions(&source, dir);
        let conflicted = collapsed.is_some();
        let mut ast = collapsed.unwrap_or(ast);
        self.resolve_links(&mut ast)?;
        let metadata = derive_metadata(
            &self.0.note_id,
            &source,
            &spans,
            file_mtime(&self.0.absolute_path),
        );

        // Reload linearizes with tier-1 source mutations at its draft clear
        // and state install, not over the file read and parse above. Holding
        // this lock across filesystem work would put reload on the typing
        // path, while taking it here ensures no structural caller can return a
        // result for source this reload then replaces.
        let _tier_one_guard = self.lock_tier_one()?;
        let workspace_id = self.0.workspace.id().to_string();
        let note_id = self.0.note_id.clone();
        self.0.workspace.with_db(|conn| {
            conn.execute(
                "DELETE FROM drafts WHERE workspace_id = ?1 AND note_id = ?2",
                rusqlite::params![workspace_id, note_id],
            )?;
            Ok(())
        })?;

        let mut state = self.lock_state()?;
        state.source = Arc::new(source);
        state.spans = Arc::new(spans);
        state.ast = Arc::new(ast);
        state.revision = revision;
        // Cleared alongside the revision, because the two are one fact: the
        // baseline above is the hash of **bytes that were read from a file**,
        // so by the time it is recorded the file exists and this session is no
        // longer owed one. A reload cannot succeed any other way — `read_file`
        // is the first thing it does and `NotFound` is where it stops.
        //
        // Leaving it set had two consequences, one wasteful and one a trap.
        // `write_locked` writes unconditionally while it stands, so every idle
        // tick after a reload rewrote bytes identical to the ones on disk. And
        // it makes a *second* external deletion unrepresentable as one: the
        // absent file compares as `ABSENT_FILE` against a baseline taken from
        // real content, so the write raises `RevisionMismatch` instead of
        // `NotFound` — and `close` reads only `NotFound` as a vanished file, so
        // the session became unclosable again, which is the exact state the
        // recovery path exists to get the user *out* of.
        state.awaiting_recreate = false;
        state.metadata = metadata;
        state.restored_from_draft = false;
        state.unwritten = false;
        // Re-evaluated rather than latched, in both directions: a reload of a
        // file the user (or the Sync Manager) has since repaired is the only
        // exit from the refusals below, and a reload that reads *newly*
        // conflicted bytes into a Note that was fine has to enter them.
        state.conflicted = conflicted;
        state.last_error = None;
        drop(state);
        self.note_state()
    }

    // -- Tier 3 and 4 --------------------------------------------------------

    /// Flushes tier 2, makes one Git commit for this editing session, clears
    /// the draft row and notifies the sync scheduler.
    ///
    /// A close with nothing to commit makes no commit and notifies nothing:
    /// opening a Note to read it and navigating away is the *most common* path
    /// through this tier, and one empty commit per Note visited would destroy
    /// the readable history the whole design exists to produce.
    ///
    /// A refused flush aborts the close with the error, before the commit and
    /// before the draft-row clear: committing bytes this application did not
    /// write, or clearing a row holding work that never reached disk, are both
    /// worse than a close the UI has to follow with a reload — which is the
    /// exit the contract routes every mismatch through.
    ///
    /// **The session is left closable, not untouched**, and the distinction
    /// matters to whoever retries. A flush fails at one of three points, and
    /// only the first leaves nothing behind: the OCC comparison
    /// ([`write_locked`](Self::write_locked)) refuses before any byte moves,
    /// but a failure in either SQL stage *after* it — the conditional draft
    /// clear, the index update — happens with the bytes already published by
    /// the atomic rename and the OCC baseline already advanced to match them.
    /// So a refused close may well have written the file. What it never does is
    /// commit, clear the row, or retire the session, which is what makes the
    /// retry clean rather than merely possible: the second close re-enters with
    /// a buffer the file already matches, so its flush writes nothing, passes,
    /// and completes the SQL stages the first one did not reach.
    ///
    /// **Neither a refused commit nor a refused draft-row clear does**, and the
    /// asymmetry is the point: by the time either runs the flush has succeeded,
    /// so the Note's bytes are on disk and its rows are in the index. The close
    /// therefore runs to completion — session deregistered, `closed` set, timer
    /// with nothing left to fire against — and the stage error is returned
    /// afterwards, saying which stage it was. Both used to propagate with `?`
    /// and strand the session in the registry with its timer armed, leaving a
    /// Note that could not be closed and could not be navigated away from over a
    /// failure that had nothing to do with the user's work. Every one of tier
    /// 3's four siblings in `workspace::lifecycle` already reconciled first and
    /// reported second.
    ///
    /// The draft-row clear is the *cheaper* of the two to fail, which is why it
    /// is folded into the commit-stage report rather than given precedence over
    /// it: a `drafts` row that outlives the write covering it costs one spurious
    /// "restored from draft" notice on the next open, and is cleared by that
    /// open's own recovery path or by the next tier 2 write's conditional clear.
    /// Nothing is lost by it — the row holds bytes identical to the file — so
    /// when both stages fail the commit's error is the one returned, with the
    /// draft failure attached to it.
    ///
    /// **A file that has vanished is the one exception**, because it is the one
    /// case where refusing traps the user. Something outside this application
    /// deleted the Note; every subsequent flush and every reload will fail on
    /// the same missing file, so a close that propagated the error would leave
    /// a session that can never be closed and a Note that can never be
    /// navigated away from. So the session is retired without a commit — there
    /// is nothing on disk to commit — and **the draft row is left in place**,
    /// which is what turns the deletion into recoverable work: the row survives
    /// in the encrypted index and `pending_drafts` reports it. That is
    /// `SPK-WSPC-D001` §6.2.6's asymmetry applied to the harshest case, and it
    /// keeps `architecture/resilience.md`'s promise that unwritten work
    /// survives events the application never got to handle.
    pub fn close(&self) -> Result<(), AppError> {
        let (edited, unwritten) = {
            let state = self.lock_state()?;
            (state.session_edited, state.unwritten)
        };

        let mut written: Option<WrittenThrough> = None;
        let mut file_vanished = false;
        if edited || unwritten {
            match self.flush_covering() {
                Ok(flushed) => written = Some(flushed),
                Err(AppError::NotFound(_)) => file_vanished = true,
                Err(error) => return Err(error),
            }
        }

        // The commit stage's failure is **held**, not propagated, for the
        // reason the four lifecycle operations already hold theirs
        // ([`super::lifecycle::commit_stage_failure`]) — and here the cost of
        // propagating was worse than an unrecorded commit. The flush above has
        // already put the Note's bytes on disk and its rows in the index; a `?`
        // here returned before the session was deregistered, its timer left
        // armed and its `closed` flag unset, so the Note could not be closed,
        // could not be navigated away from, and every retry took the same exit
        // — over a Git failure (an unreadable object store, a `.git` a sync
        // moved) that had nothing to do with the user's work, which was already
        // safe.
        //
        // `commit_message` is inside this too: it reads `HEAD` through
        // `path_in_head`, so whatever breaks the commit generally breaks the
        // message first, and it is the same stage either way.
        let mut committed = false;
        let mut commit_failure: Option<AppError> = None;
        if edited && !file_vanished {
            let staged = self.commit_message().and_then(|message| {
                crate::git::operations::commit_paths(
                    self.0.workspace.root(),
                    &message,
                    std::slice::from_ref(&self.0.relative_path),
                )
            });
            match staged {
                Ok(commit) => committed = commit.is_some(),
                Err(error) => commit_failure = Some(error),
            }
        }

        // Bound to the sequence the write actually covered, for the same reason
        // the timer's clear is: a keystroke landing between the flush returning
        // and this statement is work no write has covered, and clearing it
        // would destroy it. Nothing was written when the file vanished, so
        // nothing is cleared.
        //
        // **Held rather than propagated**, exactly as the commit stage above is
        // and for a reason that is one stage stronger: by here the bytes are on
        // disk *and* the commit may already have been made, so a `?` returned
        // before `closed` was set, before the session left the registry and
        // before the scheduler was notified — over a `drafts`-table failure that
        // costs the user nothing at all. This is the same trap round 6 closed
        // for the commit stage, one stage earlier, and it was reachable by the
        // ordinary route: `with_db` fails for a full disk, a locked database, or
        // a poisoned connection mutex just as readily here as anywhere else.
        let mut draft_clear_failure: Option<AppError> = None;
        if let Some(flushed) = &written {
            if let Err(error) = self.clear_draft_through(flushed.seq) {
                draft_clear_failure = Some(error);
            }
        }

        {
            let mut state = self.lock_state()?;
            state.closed = true;
            state.session_edited = false;
            state.unwritten = file_vanished;
        }
        registry()?.remove(&(self.0.workspace.id().to_string(), self.0.note_id.clone()));

        // Tier 4: the commit is what signals the scheduler, so a close that
        // committed nothing notifies nothing.
        if committed {
            notify_sync_activity();
        }

        // Reported only now that the close itself is complete: the session is
        // out of the registry, the idle timer has nothing left to fire against,
        // and the Note is closable again. What the caller gets is the truth —
        // the Note is written, only one record of it is missing.
        //
        // The commit failure wins when both fired, with the draft failure
        // attached to it as the lesser of the two: an unrecorded commit is work
        // the user must act on, while an uncleared `drafts` row repairs itself.
        let subject = format!("closing {}", self.0.note_id);
        if let Some(error) = commit_failure {
            let also: Vec<String> = draft_clear_failure
                .iter()
                .map(|e| format!("clearing the draft row for {}: {e:?}", self.0.note_id))
                .collect();
            return Err(super::lifecycle::commit_stage_failure(
                &subject, error, &also,
            ));
        }
        if let Some(error) = draft_clear_failure {
            return Err(draft_stage_failure(&subject, error));
        }
        Ok(())
    }

    /// The generated message tier 3 commits with. It carries no correctness
    /// weight, but it is what the user reads when recovering an earlier
    /// version, so it names the Note and the nature of the change.
    fn commit_message(&self) -> Result<String, AppError> {
        let title = self.lock_state()?.metadata.title.clone();
        let existed =
            crate::git::operations::path_in_head(self.0.workspace.root(), &self.0.relative_path)?;
        let verb = if existed { "Update" } else { "Create" };
        Ok(format!("{verb} {title}\n\n{}\n", self.0.relative_path))
    }
}

/// The error [`NoteSession::close`] returns when the **draft-row cleanup**
/// failed after everything else had settled.
///
/// The sibling of [`super::lifecycle::commit_stage_failure`], and deliberately
/// shaped like it: the close happened, so this reports which record of it is
/// missing rather than pretending the operation failed. What distinguishes the
/// two is the recovery advice, and it is the whole reason this has its own
/// sentence — an unrecorded commit is something the user has to act on, while a
/// surviving `drafts` row is self-repairing. It holds bytes identical to the
/// file by construction (the clear only ever runs for the sequence a successful
/// write covered), so the worst it produces is one spurious "restored from
/// draft" notice, and the next open's recovery path or the next tier 2 write's
/// conditional clear removes it.
fn draft_stage_failure(subject: &str, error: AppError) -> AppError {
    super::lifecycle::restate(error, |detail| {
        format!(
            "{subject}: the Note is closed and its work is safe — the bytes are on disk and \
             the index has them — but clearing the draft row that recorded the unflushed \
             edits failed, so the row stays behind: {detail}. Nothing is lost by it: the row \
             holds what the file holds, and the next open (or the next successful write) \
             clears it."
        )
    })
}

// ---------------------------------------------------------------------------
// The idle timer (tier 2's routine trigger)
// ---------------------------------------------------------------------------

struct IdleTimer {
    interval: Duration,
    state: Mutex<TimerState>,
    wakeup: Condvar,
}

#[derive(Default)]
struct TimerState {
    deadline: Option<Instant>,
    running: bool,
}

impl IdleTimer {
    fn new(interval: Duration) -> Self {
        IdleTimer {
            interval,
            state: Mutex::new(TimerState::default()),
            wakeup: Condvar::new(),
        }
    }

    /// Records that an edit just happened and makes sure a thread is waiting
    /// for the Note to go idle. Debounce rather than throttle: each call moves
    /// the deadline out, so a burst of keystrokes produces one write.
    fn arm(&self, inner: &Arc<SessionInner>) {
        let Ok(mut state) = self.state.lock() else {
            return;
        };
        state.deadline = Some(Instant::now() + self.interval);
        if state.running {
            self.wakeup.notify_all();
            return;
        }
        state.running = true;
        drop(state);

        // The thread holds a `Weak`, so a session that is dropped without ever
        // going idle does not keep itself alive through its own timer.
        let weak = Arc::downgrade(inner);
        let spawned = std::thread::Builder::new()
            .name("burlmd-idle-write".to_string())
            .spawn(move || idle_loop(&weak));
        if spawned.is_err() {
            if let Ok(mut state) = self.state.lock() {
                state.running = false;
            }
        }
    }
}

fn idle_loop(weak: &Weak<SessionInner>) {
    loop {
        let Some(inner) = weak.upgrade() else {
            return;
        };
        let timer = &inner.timer;
        let Ok(mut state) = timer.state.lock() else {
            return;
        };
        loop {
            let Some(deadline) = state.deadline else {
                state.running = false;
                return;
            };
            let now = Instant::now();
            if now >= deadline {
                state.deadline = None;
                break;
            }
            let Ok((next, _)) = timer.wakeup.wait_timeout(state, deadline - now) else {
                return;
            };
            state = next;
        }
        drop(state);

        // Errors have no caller to return to here; they are recorded on the
        // session and surface through `note_write_status`, which is why that
        // poll exists at all.
        let session = NoteSession(Arc::clone(&inner));
        drop(inner);
        let _ = session.flush();
    }
}

// ---------------------------------------------------------------------------
// Tier 4: the sync scheduler
// ---------------------------------------------------------------------------

fn scheduler_slot() -> &'static Mutex<Option<Arc<SyncScheduler>>> {
    static SCHEDULER: OnceLock<Mutex<Option<Arc<SyncScheduler>>>> = OnceLock::new();
    SCHEDULER.get_or_init(|| Mutex::new(None))
}

/// Registers the scheduler tier 3 notifies. Wired by whoever starts one — no
/// production path does yet, and this module deliberately does not start one
/// on its own: a scheduler needs a remote, a branch and credentials, none of
/// which a local-only Workspace has (ADR-005).
pub fn set_sync_scheduler(scheduler: Option<Arc<SyncScheduler>>) {
    if let Ok(mut slot) = scheduler_slot().lock() {
        *slot = scheduler;
    }
}

fn notify_sync_activity() {
    if let Ok(slot) = scheduler_slot().lock() {
        if let Some(scheduler) = slot.as_ref() {
            scheduler.notify_activity();
        }
    }
}

// ---------------------------------------------------------------------------
// Status and recovery surfaces
// ---------------------------------------------------------------------------

/// The state of the write tier for one open Note, polled by the UI.
///
/// A poll rather than a stream because tier 2's routine trigger is a Core-owned
/// idle timer: when its write fails there is no caller to return the error to,
/// and `RevisionMismatch` — the entirety of risk 6's mitigation — would
/// otherwise be raised into nothing.
///
/// `Default` is what a Note that is **not open** reports — no error and no
/// unwritten edits — because `note_write_status` never fails and so needs a
/// value for that case rather than an error.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct NoteWriteStatus {
    pub last_written_at: Option<i64>,
    pub last_error: Option<AppError>,
    pub has_unwritten_edits: bool,
}

/// Notes with an unflushed draft, for surfacing recovered work on startup
/// (CAP-WS-03).
///
/// **`LEFT JOIN`, not `JOIN`**, and the difference is the whole point of the
/// surface. `close`'s documentation promises that a Note deleted out from under
/// an open session keeps its draft row "in the encrypted index, and
/// `pending_drafts` reports it" — but the row's `notes` partner is gone by then,
/// and a full rebuild (`index::scan`'s `DELETE FROM notes`) removes it for good
/// on the very next open. An inner join makes that draft invisible to the one
/// call that reports it: the user's unwritten work is still on disk in the
/// index, and nothing can ever tell them so. The `drafts` table carries no
/// foreign key precisely so the row can outlive its Note; the reporting query
/// has to be written the same way.
///
/// The synthesized metadata for that case is deliberately modest — the id and
/// its derived path are facts, the title falls back to the id's filename stem
/// because no indexed title survives, `last_modified` is the draft's own
/// `updated_at` (which is when the work happened), and `okf_conformant` is
/// `false` rather than a guess about bytes nothing has parsed.
///
/// **`, d.note_id` as a tie-break**, the same one every other list-returning
/// query in this crate carries and for the same reason. `updated_at` is
/// second-granularity, and the case this call exists for — an application
/// killed with several sessions open — produces ties by construction, leaving
/// the remainder to SQLite's unspecified row order. Today the plan happens to
/// walk the `(workspace_id, note_id)` primary key and so happens to come out
/// sorted, but that is a property of a query plan, not of the query: a recovery
/// list that reshuffles between two calls that saw no writes is not something to
/// leave resting on one.
pub fn pending_drafts(workspace: &Workspace) -> Result<Vec<NoteMetadata>, AppError> {
    workspace.with_db(|conn| {
        let mut stmt = conn.prepare(
            "SELECT d.note_id, d.updated_at, n.path, n.title, n.last_modified, n.okf_conformant \
             FROM drafts d \
             LEFT JOIN notes n ON n.workspace_id = d.workspace_id AND n.id = d.note_id \
             WHERE d.workspace_id = ?1 \
             ORDER BY d.updated_at DESC, d.note_id",
        )?;
        let rows = stmt.query_map([workspace.id()], |row| {
            let note_id: String = row.get(0)?;
            let draft_updated_at: i64 = row.get(1)?;
            let path: Option<String> = row.get(2)?;
            Ok(NoteMetadata {
                path: path.unwrap_or_else(|| concept_id_to_path(&note_id)),
                title: row
                    .get::<_, Option<String>>(3)?
                    .unwrap_or_else(|| file_stem(&note_id).to_string()),
                last_modified: row.get::<_, Option<i64>>(4)?.unwrap_or(draft_updated_at),
                okf_conformant: row.get::<_, Option<bool>>(5)?.unwrap_or(false),
                id: note_id,
                snippet: None,
            })
        })?;
        rows.collect::<Result<Vec<_>, _>>().map_err(AppError::from)
    })
}

/// The filename stem of a concept id — its last `/`-separated segment.
fn file_stem(concept_id: &str) -> &str {
    concept_id.rsplit_once('/').map_or(concept_id, |(_, s)| s)
}

// ---------------------------------------------------------------------------
// Carrying an open session across a lifecycle operation (`WSPC-D006`)
// ---------------------------------------------------------------------------

/// The concept ids of every Note currently open in `workspace_id`.
///
/// `WSPC-D006`'s inbound-Link sweep needs these because the `links` table only
/// knows about Links that have reached disk and been indexed. A Link typed into
/// an open Note and not yet written exists **only** in that session's working
/// source, so a sweep driven by the index alone would leave it pointing at a
/// concept the rename removed — and the Note's own next write would then index
/// the dead edge, which is the graph corruption `architecture/risks.md` risk 8
/// describes, arriving from the one direction the index cannot see.
pub(super) fn open_note_ids(workspace_id: &str) -> Result<Vec<String>, AppError> {
    Ok(registry()?
        .keys()
        .filter(|(id, _)| id == workspace_id)
        .map(|(_, note_id)| note_id.clone())
        .collect())
}

/// The per-Workspace lifecycle locks, keyed by Workspace id.
///
/// Keyed rather than a single process-wide `Mutex<()>` because two Workspaces
/// share no bundle, no index rows and no concept-id namespace
/// (`data-models/schema.sql` rule 1), so serializing across them would buy
/// nothing and would make one Workspace's slow `git` commit block another's
/// rename. The map only grows — one small entry per Workspace id this process
/// has ever run a lifecycle operation for, which in production is one
/// (ADR-005 decision 7 allows exactly one active Workspace) and in the test
/// harness is one per fixture.
///
/// This lock is a peer of the session registry lock: taken, cloned out of and
/// released before any lower lock is acquired.
type LifecycleLocks = HashMap<String, Arc<Mutex<()>>>;

fn lifecycle_locks() -> &'static Mutex<LifecycleLocks> {
    static LOCKS: OnceLock<Mutex<LifecycleLocks>> = OnceLock::new();
    LOCKS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Runs `f` as the **only lifecycle operation in this Workspace**, which is
/// what makes `workspace::lifecycle`'s headline property — one operation that
/// either completes or changes nothing — a statement about concurrent callers
/// and not only about failure.
///
/// # Why the tier 2 write locks were not enough
///
/// [`with_write_locks`] locks the tier 2 write lock of every Note that is
/// *open*, and a Workspace with no Note open has none. Two lifecycle operations
/// therefore ran fully interleaved on the common path. FRB 2.12's default
/// handler is `SimpleHandler`/`SimpleExecutor`, whose own documentation reads
/// "it creates an internal thread pool, and each call to a Rust function is
/// handled by a different thread", and every lifecycle function in
/// `api::ffi_api` is an `#[frb] async fn` dispatched through it — so two of them
/// genuinely run at once, and a user double-clicking a rename or a shell
/// dispatching a batch produces exactly that.
///
/// The two failures this closes, both of them checked-then-acted races that no
/// per-Note lock can see:
///
/// - **Two renames onto one destination.** `ensure_path_available` asks the
///   filesystem and the index whether the destination is free. Two operations
///   asking before either has written both get "yes", and the second one's
///   journal rename lands on top of the first's result — one Note silently
///   replacing another, with the index rewritten to match whichever transaction
///   committed last.
/// - **A create landing inside a rename.** `apply_reidentify` moves the
///   filesystem under its journal and *then* rewrites the index rows; a
///   `create_note` that runs between those two steps writes a file and an index
///   row at a path the rename is still mid-way through vacating, so the row the
///   rename's transaction writes and the row the create wrote are two rows for
///   one path, and the loser's file is orphaned.
///
/// # Coarse on purpose
///
/// One lock for every lifecycle entry point — and for [`open_note`], which is
/// not one but performs the same check-then-act against the same three stores —
/// held for the whole operation including its `git` commit. This is
/// serialization, not fairness: there is no queue, no ordering guarantee
/// between waiters, and no attempt to let operations on disjoint subtrees
/// proceed together. That is the right trade
/// because these operations are *user-scale* — a rename per click, not per
/// keystroke — and because a finer scheme keyed on paths has to decide what
/// "disjoint" means for an operation whose affected set (`plan_affected`) is
/// computed from the index *after* the lock would have to be held. The cost is
/// paid only by a second concurrent lifecycle call, and **no editing path takes
/// this lock at all**: tier 1, tier 2 and tier 3 never reach it, so no keystroke
/// and no idle write can ever wait on a rename's commit.
///
/// # Ordering
///
/// This is the **topmost** of the five locks in this module's order (lifecycle
/// → tier 2 write → tier 1 → state → connection): it is acquired before
/// [`with_write_locks`] and released after it, and nothing that runs beneath it
/// reaches back for it. The debug assert below pins the one direction that
/// would be easy to violate silently — taking it from inside a connection
/// closure, which would invert the bottom of the order and put a whole `git`
/// commit under the process-wide connection mutex a keystroke waits on.
///
/// A poisoned lifecycle lock is **recovered from rather than propagated**,
/// which is the opposite of what this module does with every other poisoned
/// mutex, and deliberately so: the others guard state that a panic may have left
/// half-written, while this one guards `()`. There is no invariant to protect,
/// so refusing every subsequent lifecycle operation in the process because one
/// of them panicked would turn a single failure into a permanently unusable
/// Workspace. The registry lock above it is still propagated, since a panic
/// there really can leave the session map inconsistent.
pub(crate) fn with_lifecycle_lock<T>(
    workspace: &Workspace,
    f: impl FnOnce() -> Result<T, AppError>,
) -> Result<T, AppError> {
    with_lifecycle_lock_id(workspace.id(), f)
}

/// [`with_lifecycle_lock`] keyed on a Workspace **id** rather than on a
/// [`Workspace`].
///
/// The lock is registered per Workspace id and guards `()`, so the id is all it
/// ever needed. The distinction exists for `workspace::bootstrap::converge`,
/// which has to take this lock at a point where no `Workspace` value exists yet:
/// it is the code that establishes the `workspaces` row a `Workspace` is built
/// from, and `Workspace::active` reads the active-Workspace cell that bootstrap
/// has not set at that point either. Every other caller has a `Workspace` in
/// hand and goes through [`with_lifecycle_lock`].
pub(crate) fn with_lifecycle_lock_id<T>(
    workspace_id: &str,
    f: impl FnOnce() -> Result<T, AppError>,
) -> Result<T, AppError> {
    debug_assert!(
        !crate::db::connection::in_connection_closure(),
        "a lifecycle operation was started inside a connection closure: the lifecycle lock \
         is the topmost of this module's five locks and the connection is the bottom one, \
         so this inverts the acquisition order and holds the process-wide connection mutex \
         across a whole lifecycle operation, `git` commit included"
    );

    let lock = {
        let mut locks = lifecycle_locks()
            .lock()
            .map_err(|_| AppError::DatabaseError("lifecycle lock registry poisoned".to_string()))?;
        Arc::clone(locks.entry(workspace_id.to_string()).or_default())
    };
    let _guard = lock.lock().unwrap_or_else(PoisonError::into_inner);
    f()
}

/// Runs `f` holding the **tier 2 write lock of every Note open in this
/// Workspace**, so that no idle write can land inside a lifecycle operation.
///
/// Without this, a timer firing between the moment `WSPC-D006` reads a Note's
/// bytes and the moment it writes the rewritten ones silently loses whatever
/// the timer wrote: the lifecycle operation overwrites the file from a snapshot
/// taken before it. The tier 2 write lock is exactly the lock that exists to
/// make check-write-record one unit, and a lifecycle rewrite is a tier 2 writer
/// in every sense that matters, so it takes the same lock.
///
/// **Every open session, not only the affected ones**, because the affected set
/// is what the operation is still computing when the locks must already be
/// held. The set is bounded by how many Notes the user has open — a handful of
/// tabs, not the size of the bundle — which is also why locking them by
/// recursion is fine here.
///
/// Acquired in **sorted concept-id order**, which is what stops two concurrent
/// lifecycle operations over overlapping sets from deadlocking against each
/// other — a property [`with_lifecycle_lock`] now makes moot for two lifecycle
/// operations, and which still holds for a lifecycle operation racing anything
/// else that takes these locks. The order against the other locks is unchanged
/// and is the one the module documentation states: lifecycle lock, then tier
/// 2 write lock, tier 1 lock, state, then connection.
/// Acquiring the registry lock *while* holding a write lock (which
/// [`carry_session_forward`] does, inside `f`) is permitted by that same rule —
/// what it forbids is holding the registry lock while acquiring any of the
/// three, and nothing in this module does that.
///
/// # The snapshot is re-checked once the locks are held
///
/// The registry is read to *pick* the sessions and released again before the
/// first `Mutex` is taken, because the lock order forbids holding it while
/// acquiring a write lock (see above) — and that leaves a window. FRB 2.12's
/// default handler is `SimpleHandler`/`SimpleExecutor`, whose own documentation
/// reads "it creates an internal thread pool, and each call to a Rust function
/// is handled by a different thread"; every `#[frb] async fn` in
/// `api::ffi_api` — `open_note` included — is dispatched through it, so two of
/// them genuinely run at once. An `open_note` landing inside that window
/// installed a session this call never locked, and `plan_affected`'s own
/// `open_note_ids` snapshot (taken after the locks, from the same registry)
/// could then either miss it or, worse, include it while its buffer was
/// unprotected — a session left keyed to the concept id the rename vacated,
/// which is `architecture/risks.md` risk 8 from the direction file-level
/// atomicity cannot see.
///
/// [`open_note`] now takes the lifecycle lock itself, and every caller of this
/// function already holds it, so that particular racer can no longer occupy the
/// window. The re-check below stays: it is what makes this function correct on
/// its own terms rather than by an invariant established two frames up the
/// stack, and the window is still open to anything else that installs a session.
///
/// So after every session in the snapshot is locked, the registry is consulted
/// again: any session that appeared since is folded into the set and the whole
/// acquisition is **retried from the start** rather than tacked onto the end.
/// Retrying is what preserves the sorted order — appending a newcomer whose id
/// sorts before something already held would break exactly the invariant that
/// keeps two concurrent lifecycle operations from deadlocking. The set only ever
/// grows, so each retry makes progress and the loop terminates; the bound below
/// exists so that a pathological open storm fails loudly instead of spinning.
///
/// The invariant this establishes is therefore: **when `f` begins, every session
/// open in this Workspace is write-locked by this call.** It does not extend
/// *through* `f` — a Note opened while the operation is running is not locked,
/// and cannot be, since holding the registry lock for that span is what the lock
/// order forbids. That newcomer is largely covered anyway, because
/// [`carry_session_forward`] resolves each affected id through the registry at
/// the moment it runs rather than through the earlier snapshot; what it cannot
/// reach is a session opened between the re-check and `write_files`, whose
/// buffer holds the pre-rewrite bytes of a Note the operation did not
/// re-identify. The next reload or reindex settles that one.
///
/// One window this deliberately does not close: `update_block` never takes this
/// lock, by design, so that no keystroke can wait on file I/O. A keystroke
/// landing inside a lifecycle operation therefore still races it. That is
/// inherent to tier 1 rather than a gap here — the same property the lock
/// discipline is chosen for.
pub(super) fn with_write_locks<T>(
    workspace: &Workspace,
    f: impl FnOnce() -> Result<T, AppError>,
) -> Result<T, AppError> {
    with_write_locks_hooked(workspace, || {}, f)
}

/// How many times [`with_write_locks`] will fold in newly-appeared sessions and
/// re-acquire before giving up. Each retry needs one more Note to have been
/// opened in the microseconds between a snapshot and the locks it names, so this
/// is far beyond what a user with a handful of tabs can produce.
const LOCK_SNAPSHOT_ATTEMPTS: usize = 64;

/// [`with_write_locks`] with a seam for the test that drives its re-check.
///
/// `after_snapshot` runs immediately after each registry snapshot is taken and
/// before any lock derived from it is acquired — which is precisely the window a
/// concurrent `open_note` occupies. It is `|| {}` everywhere but that one test,
/// and monomorphizes away.
fn with_write_locks_hooked<T>(
    workspace: &Workspace,
    after_snapshot: impl Fn(),
    f: impl FnOnce() -> Result<T, AppError>,
) -> Result<T, AppError> {
    let mut locked = sessions_not_among(&[], workspace)?;
    locked.sort_by(|a, b| a.note_id().cmp(b.note_id()));
    let mut f = Some(f);

    for _ in 0..LOCK_SNAPSHOT_ATTEMPTS {
        after_snapshot();
        let outcome = lock_each_write(&locked, || {
            let appeared = sessions_not_among(&locked, workspace)?;
            if !appeared.is_empty() {
                return Ok(Err(appeared));
            }
            let run = f
                .take()
                .expect("the body runs once: this branch returns out of the retry loop");
            run().map(Ok)
        })?;
        match outcome {
            Ok(value) => return Ok(value),
            Err(appeared) => {
                locked.extend(appeared);
                locked.sort_by(|a, b| a.note_id().cmp(b.note_id()));
            }
        }
    }

    Err(AppError::DatabaseError(format!(
        "gave up acquiring the tier 2 write locks after {LOCK_SNAPSHOT_ATTEMPTS} attempts: Notes \
         kept being opened in this Workspace faster than the locks covering them could be taken"
    )))
}

/// Every session open in `workspace` that is not already in `held`, compared by
/// **identity** rather than by concept id: `carry_session_forward` retires a
/// session and installs a rebuilt one under the same key, and holding the
/// retired object's lock protects nothing.
fn sessions_not_among(
    held: &[NoteSession],
    workspace: &Workspace,
) -> Result<Vec<NoteSession>, AppError> {
    let registry = registry()?;
    Ok(registry
        .iter()
        .filter(|((id, _), _)| id == workspace.id())
        .map(|(_, session)| session.clone())
        .filter(|candidate| {
            !held
                .iter()
                .any(|session| Arc::ptr_eq(&session.0, &candidate.0))
        })
        .collect())
}

fn lock_each_write<T>(
    sessions: &[NoteSession],
    f: impl FnOnce() -> Result<T, AppError>,
) -> Result<T, AppError> {
    match sessions.split_first() {
        None => f(),
        Some((head, rest)) => {
            let _guard = head.lock_writes()?;
            lock_each_write(rest, f)
        }
    }
}

/// Moves an open Note's session onto `new_id`, installing bytes a lifecycle
/// operation rewrote and re-recording the OCC baseline from them.
///
/// This is the half of `contracts/ffi_api.rs`'s three rename obligations that
/// only this module can discharge, because the working source, the span map and
/// the recorded revision are all private state of a live session:
///
/// - the **working source** gets the same substitution the file got, or the
///   next tier 2 write copies the buffer verbatim over the rewrite;
/// - the **span map** is rebuilt from it rather than adjusted, since a
///   frontmatter title and a Link destination can both change length;
/// - the **recorded revision** becomes the hash of the post-rewrite file, or
///   that Note's next tier 2 write raises `RevisionMismatch` against this
///   application's own rewrite.
///
/// `new_source` is `None` when the operation moved the Note without changing
/// its bytes. A session that is not open is not an error: most affected Notes
/// are not open, which is the whole reason the draft row is re-keyed separately.
///
/// When the id changes the session is **rebuilt rather than mutated**: the
/// identity of a `SessionInner` — its concept id and the two paths derived from
/// it — is immutable by construction, and every reader of it (the idle timer,
/// tier 2's OCC sequence, tier 3's pathspec) reads it without a lock precisely
/// because it cannot move. The retired session is marked closed first, so an
/// idle write already in flight against it returns without touching the file it
/// no longer names.
pub(super) fn carry_session_forward(
    workspace: &Arc<Workspace>,
    old_id: &str,
    new_id: &str,
    new_source: Option<String>,
    new_revision: String,
) -> Result<(), AppError> {
    let Some(session) = lookup(workspace.id(), old_id)? else {
        return Ok(());
    };

    if old_id == new_id {
        return session.install_rewrite(new_source, new_revision);
    }

    // The registry lock is above every other lock in this module's order, so it
    // is taken and released around nothing but the map operation itself.
    let retired = registry()?.remove(&(workspace.id().to_string(), old_id.to_string()));
    let Some(session) = retired else {
        return Ok(());
    };

    let snapshot = {
        let mut state = session.lock_state()?;
        state.closed = true;
        SessionState {
            source: Arc::clone(&state.source),
            spans: Arc::clone(&state.spans),
            ast: Arc::clone(&state.ast),
            edit_seq: state.edit_seq,
            revision: state.revision.clone(),
            restored_from_draft: state.restored_from_draft,
            awaiting_recreate: state.awaiting_recreate,
            session_edited: state.session_edited,
            unwritten: state.unwritten,
            // Not carried across, because the AST installed below is a fresh
            // `parse_note` of the moved bytes: it and its span map come from
            // the same call over the same source, so nothing is renumbered and
            // every `block_path` addresses the Block it names again. The
            // markers survive as literal text until the next reload collapses
            // them, which is exactly what an `open_note` over the same file
            // would produce.
            conflicted: false,
            last_written_at: state.last_written_at,
            last_error: state.last_error.clone(),
            closed: false,
            metadata: state.metadata.clone(),
        }
    };

    let absolute_path = workspace.note_path(new_id)?;
    let source = match new_source {
        Some(rewritten) => Arc::new(rewritten),
        None => snapshot.source,
    };
    let ParsedNote { mut ast, spans } = parse_note(&source, containing_dir(new_id));
    workspace.with_db(|conn| index::resolve_link_existence(conn, workspace.id(), &mut ast))?;
    let metadata = derive_metadata(new_id, &source, &spans, file_mtime(&absolute_path));

    let state = SessionState {
        source,
        spans: Arc::new(spans),
        ast: Arc::new(ast),
        revision: new_revision,
        metadata,
        ..snapshot
    };
    let unwritten = state.unwritten;

    let moved = NoteSession(Arc::new(SessionInner {
        workspace: Arc::clone(workspace),
        note_id: new_id.to_string(),
        relative_path: concept_id_to_path(new_id),
        absolute_path,
        state: Mutex::new(state),
        tier_one_lock: Mutex::new(()),
        write_lock: Mutex::new(()),
        timer: IdleTimer::new(workspace.idle_interval),
    }));
    registry()?.insert(
        (workspace.id().to_string(), new_id.to_string()),
        moved.clone(),
    );

    // The retired session's timer died with it, so buffered work that has not
    // reached disk needs a live one or it would sit in the buffer until close.
    if unwritten {
        moved.arm_idle_timer();
    }
    Ok(())
}

/// Retires an open session for a Note that no longer exists, without writing,
/// committing, or clearing anything.
///
/// [`NoteSession::close`] is the wrong call for a deletion: it flushes tier 2
/// first, which would recreate the file this operation just removed. Marking
/// the session closed is what stops an idle write already in flight from doing
/// the same.
pub(super) fn discard_session(workspace: &Workspace, note_id: &str) -> Result<(), AppError> {
    let retired = registry()?.remove(&(workspace.id().to_string(), note_id.to_string()));
    if let Some(session) = retired {
        let mut state = session.lock_state()?;
        state.closed = true;
        state.unwritten = false;
    }
    Ok(())
}

impl NoteSession {
    /// Installs rewritten bytes and a fresh OCC baseline into a session whose
    /// concept id did not change — the source-Note half of
    /// [`carry_session_forward`].
    fn install_rewrite(
        &self,
        new_source: Option<String>,
        new_revision: String,
    ) -> Result<(), AppError> {
        let Some(rewritten) = new_source else {
            let _tier_one_guard = self.lock_tier_one()?;
            let mut state = self.lock_state()?;
            state.revision = new_revision;
            return Ok(());
        };

        // Parsed with no lock held, like every other parse in this module.
        let ParsedNote { mut ast, spans } = parse_note(&rewritten, containing_dir(&self.0.note_id));
        let metadata = derive_metadata(
            &self.0.note_id,
            &rewritten,
            &spans,
            file_mtime(&self.0.absolute_path),
        );

        // Lifecycle callers already hold the lifecycle and tier-2 write
        // locks. Taking tier 1 here completes that order before either the
        // link lookup or state install, so a structural result can never be
        // paired with a lifecycle-replaced session state.
        let _tier_one_guard = self.lock_tier_one()?;
        self.resolve_links(&mut ast)?;

        let mut state = self.lock_state()?;
        state.source = Arc::new(rewritten);
        state.spans = Arc::new(spans);
        state.ast = Arc::new(ast);
        state.metadata = metadata;
        state.revision = new_revision;
        // Cleared for the reason the moved session's snapshot clears it: the
        // AST and the span map above came from one `parse_note` over one
        // source, so they address the same document again.
        state.conflicted = false;
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// The bytes a Note that is **not on disk** is compared against.
///
/// Named rather than written as `&[]` at its two use sites, because the two
/// have to agree: [`open_note`]'s recovery branch records the hash of this as
/// the OCC baseline, and [`NoteSession::write_locked`] substitutes it for the
/// read that would have produced one. The comparison passing is what lets the
/// first write create the file rather than raise `RevisionMismatch` against a
/// file that is not there.
const ABSENT_FILE: &[u8] = &[];

struct DraftRow {
    raw_markdown: String,
    edit_seq: i64,
    updated_at: i64,
}

fn read_draft(
    conn: &Connection,
    workspace_id: &str,
    note_id: &str,
) -> Result<Option<DraftRow>, AppError> {
    conn.query_row(
        "SELECT raw_markdown, edit_seq, updated_at FROM drafts \
         WHERE workspace_id = ?1 AND note_id = ?2",
        rusqlite::params![workspace_id, note_id],
        |row| {
            Ok(DraftRow {
                raw_markdown: row.get(0)?,
                edit_seq: row.get(1)?,
                updated_at: row.get(2)?,
            })
        },
    )
    .optional()
    .map_err(AppError::from)
}

/// The bytes of a Note that is about to become an **editable** working source,
/// decoded strictly.
///
/// Lossy decoding is the wrong tool on this path, and the reason is that a
/// session's working source is written back. `from_utf8_lossy` replaces every
/// invalid byte with U+FFFD, so the first idle write after any edit would
/// rewrite the whole file with the replacement characters *and* re-record that
/// mangled text as the OCC baseline — destroying bytes the user never touched,
/// silently, in a file this application was only asked to edit one Block of.
/// That is precisely what `prd/constraints.md`'s Edit Fidelity and CAP-PORT-03
/// forbid, and refusing is the same call `lifecycle::read_source` already makes
/// for the same reason on the Link-rewrite path.
///
/// `index::scan::RawNote::derive` stays lossy on purpose and is not an
/// inconsistency: indexing is read-only, so a Note that cannot be edited is
/// still discovered, searchable and visible in the tree rather than absent
/// from the Workspace altogether.
fn decode_source(path: &Path, bytes: Vec<u8>) -> Result<String, AppError> {
    String::from_utf8(bytes).map_err(|_| {
        AppError::ParseError(format!(
            "{} is not valid UTF-8, so it cannot be edited without corrupting it",
            path.display()
        ))
    })
}

/// Writes `bytes` to `path` so that an abrupt termination mid-write leaves the
/// previous state intact (`architecture/resilience.md`).
///
/// The temporary file is **uniquely named per write** and lives in the target's
/// own directory. Both halves matter: a name derived from the target (the
/// obvious `target.with_extension("tmp")`) is shared by two concurrent writers,
/// and the loser renames a partially written file over the Note; and a
/// temporary file in another directory cannot be renamed atomically onto this
/// one, because `rename` is only atomic within a filesystem.
///
/// The containing **directory** is deliberately not `fsync`ed after the
/// rename. What that costs is bounded and is not the guarantee this function
/// makes: on a power loss the rename itself may not have reached the platter,
/// so the file may still hold its previous contents — never a partial or
/// interleaved one, because the bytes were `fsync`ed into the temporary file
/// before the rename published them. Losing the last write to a power cut is
/// already the accepted cost of `synchronous = NORMAL` on the index the draft
/// row lives in (`SPK-WSPC-D001` §6.3), and tier 1's purpose is to survive an
/// application crash, which this handles unconditionally.
///
/// **The temporary file is private from the instant it exists** and only then
/// takes the target's mode. It holds the Note's full plaintext for the whole of
/// the write and the `fsync`, so creating it at the process umask left every
/// Note in the Workspace world-readable for that window — see
/// [`create_private_temp`].
///
/// **The target's permissions survive the rename.** Publishing by rename means
/// the file the user ends up with is the *temporary* one. Without
/// [`carry_permissions_forward`] below, the first idle write over a Note the
/// user had restricted to 0600 relaxed it to world-readable, silently and with
/// nothing in the UI to say so; the same held for `lifecycle`'s journal, whose
/// overwrite and rollback both route here. The mode is copied from the existing
/// target when there is one, and left at the private creation mode when this
/// write is creating the file.
///
/// `pub(crate)` rather than `pub(super)` for one caller outside this module:
/// `git::operations::ensure_scratch_ignored`, which extends the *user's* own
/// `.gitignore` and was the last write into a bundle still going through a
/// truncating `std::fs::write`. See that function for why it belongs here.
pub(crate) fn atomic_write(path: &Path, bytes: &[u8]) -> Result<(), AppError> {
    static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);

    assert_no_io_under_the_connection("an atomic write");

    let directory = path
        .parent()
        .ok_or_else(|| AppError::IoError(format!("{} has no parent directory", path.display())))?;
    let stem = path
        .file_name()
        .map_or_else(|| "note".to_string(), |n| n.to_string_lossy().into_owned());
    // Dot-prefixed and `.tmp`-suffixed, which is what `super::is_scratch_name`
    // and the `.gitignore` `git::operations::init_repo` installs both key on: a
    // kill between the create and the rename leaves this file behind holding a
    // Note mid-write, and it must be neither committed nor mistaken for content.
    let temp = directory.join(format!(
        ".{stem}.{}.{}.tmp",
        std::process::id(),
        NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
    ));

    let write = || -> std::io::Result<()> {
        let mut file = create_private_temp(&temp)?;
        file.write_all(bytes)?;
        // Before the rename, so the rename publishes bytes that are already
        // durable rather than a name pointing at an empty file.
        file.sync_all()?;
        Ok(())
    };
    if let Err(e) = write() {
        let _ = std::fs::remove_file(&temp);
        return Err(io_error(&temp, &e));
    }
    if let Err(e) = carry_permissions_forward(path, &temp) {
        let _ = std::fs::remove_file(&temp);
        return Err(io_error(path, &e));
    }
    if let Err(e) = std::fs::rename(&temp, path) {
        let _ = std::fs::remove_file(&temp);
        return Err(io_error(path, &e));
    }
    Ok(())
}

/// Publishes a new file without ever replacing an existing destination.
///
/// Lifecycle creation has an unavoidable boundary with external tools: even
/// while burlmd's lifecycle lock serializes its own operations, another
/// process can create the requested path after the availability check. A
/// rename would replace that file on Unix, so new Notes publish the durable
/// private temporary through a hard link instead. `link` creates the final
/// name iff it does not already exist; its `AlreadyExists` answer is therefore
/// an honest collision rather than a lossy overwrite.
///
/// `Ok(false)` means the destination appeared before publication. All other
/// I/O failures retain the normal typed application error.
pub(crate) fn atomic_create(path: &Path, bytes: &[u8]) -> Result<bool, AppError> {
    atomic_create_with_cleanup(path, bytes, |temp| std::fs::remove_file(temp))
}

/// The `hard_link` is the publication point. Scratch cleanup happens only
/// afterwards, so it is best-effort: reporting an error here would tell a
/// lifecycle caller creation failed after the Note already exists at its final
/// path.
fn atomic_create_with_cleanup(
    path: &Path,
    bytes: &[u8],
    cleanup_temp: impl FnOnce(&Path) -> std::io::Result<()>,
) -> Result<bool, AppError> {
    static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);

    assert_no_io_under_the_connection("an atomic create");

    let directory = path
        .parent()
        .ok_or_else(|| AppError::IoError(format!("{} has no parent directory", path.display())))?;
    let stem = path
        .file_name()
        .map_or_else(|| "note".to_string(), |n| n.to_string_lossy().into_owned());
    let temp = directory.join(format!(
        ".{stem}.{}.{}.tmp",
        std::process::id(),
        NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
    ));

    let write = || -> std::io::Result<()> {
        let mut file = create_private_temp(&temp)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        Ok(())
    };
    if let Err(error) = write() {
        let _ = std::fs::remove_file(&temp);
        return Err(io_error(&temp, &error));
    }

    match std::fs::hard_link(&temp, path) {
        Ok(()) => {
            let _ = cleanup_temp(&temp);
            Ok(true)
        }
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
            let _ = std::fs::remove_file(&temp);
            Ok(false)
        }
        Err(error) => {
            let _ = std::fs::remove_file(&temp);
            Err(io_error(path, &error))
        }
    }
}

/// Creates the temporary file **already private**, rather than at the process
/// umask and narrowed afterwards.
///
/// The mode is not merely the file's end state: between the create and
/// [`carry_permissions_forward`] the file holds the Note's full plaintext, and
/// at the ordinary umask that is 0644 — world-readable, on a multi-user machine,
/// for the whole of a write plus an `fsync`. Every Note goes through this
/// window, including one the user had deliberately restricted to 0600, whose
/// mode was correct before the write and correct after it and open in between.
/// `O_CREAT | O_EXCL` with mode 0600 closes it at the syscall: there is no
/// instant at which the file exists at a wider mode.
///
/// [`carry_permissions_forward`] still runs afterwards and may *widen* this,
/// which is the intended order — an ordinary Note's own 0644 is the mode the
/// user is entitled to keep, and it is applied to a file whose bytes are
/// already written and durable.
///
/// `create_new` rather than `create`: the name carries this process's pid and a
/// per-write counter, so an existing one is a collision that should surface
/// rather than a file to truncate and inherit the mode of.
#[cfg(unix)]
fn create_private_temp(temp: &Path) -> std::io::Result<std::fs::File> {
    use std::os::unix::fs::OpenOptionsExt;

    std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(temp)
}

/// See the `unix` twin above. Windows has no mode bits to set at creation, and
/// `tech-spec/stack.md` ships desktop Linux and macOS, so this is the whole of
/// the second implementation rather than a placeholder for one.
#[cfg(not(unix))]
fn create_private_temp(temp: &Path) -> std::io::Result<std::fs::File> {
    std::fs::File::create(temp)
}

/// Copies `target`'s permission bits onto `temp`, so that the rename that
/// publishes `temp` does not also replace the mode the user chose.
///
/// A missing target is not an error: this write is creating the file, and the
/// umask is then exactly the right answer for what its mode should be.
///
/// Unix only, and unconditionally so rather than behind a runtime check —
/// burlmd ships to desktop Linux and macOS (`tech-spec/stack.md`), and Windows
/// has no equivalent bits to carry, so the `cfg` is the whole story rather than
/// a placeholder for a second implementation.
#[cfg(unix)]
fn carry_permissions_forward(target: &Path, temp: &Path) -> std::io::Result<()> {
    let existing = match std::fs::metadata(target) {
        Ok(metadata) => metadata,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(e) => return Err(e),
    };
    std::fs::set_permissions(temp, existing.permissions())
}

#[cfg(not(unix))]
fn carry_permissions_forward(_target: &Path, _temp: &Path) -> std::io::Result<()> {
    Ok(())
}

fn io_error(path: &Path, e: &std::io::Error) -> AppError {
    // ENOSPC. `std::io::ErrorKind::StorageFull` is still unstable, so the raw
    // code is the only stable way to reach the dedicated `AppError` variant the
    // contract defines for a full disk.
    if e.raw_os_error() == Some(28) {
        return AppError::DiskFull;
    }
    AppError::IoError(format!("write {}: {e}", path.display()))
}

/// A `SpliceError` is a caller error — a stale `block_path`, an out-of-range
/// selection — rather than a parse failure, and `ParseError` is the variant the
/// contract gives that class. Converted here rather than through a `From` impl,
/// since neither `error.rs` nor `splice.rs` is this ticket's file to touch.
fn splice_error(e: splice::SpliceError) -> AppError {
    AppError::ParseError(e.to_string())
}

fn check_span(source: &str, span: &std::ops::Range<usize>) -> Result<(), AppError> {
    if span.start > span.end
        || span.end > source.len()
        || !source.is_char_boundary(span.start)
        || !source.is_char_boundary(span.end)
    {
        // `String::replace_range` panics rather than erring on a non-boundary
        // index, and a panic crossing the FFI boundary is not a recoverable
        // `AppError`.
        return Err(AppError::ParseError(format!(
            "source range {}..{} is not addressable in this Note",
            span.start, span.end
        )));
    }
    Ok(())
}

/// The Core-owned postcondition of a range replacement. It deliberately lives
/// in the persistence domain rather than the FFI module, which is only a
/// wrapper over this transaction.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RangeEditLocation {
    Block {
        block_path: Vec<usize>,
        source_offset_utf16: usize,
    },
    Phantom {
        insertion_index: usize,
    },
}

/// Resolves the exact source join after a range replacement against the span
/// map built from the replacement's resulting source. A join can fall in
/// Markdown syntax which is not part of an editable leaf (a list marker or a
/// block separator); in that case the nearest actual leaf is chosen without
/// inventing a path or source offset. If no editable leaf remains, the caller
/// must focus the existing phantom insertion slot instead.
fn range_edit_caret(
    source: &str,
    spans: &SpanMap,
    join: usize,
) -> Result<RangeEditLocation, AppError> {
    if join > source.len() || !source.is_char_boundary(join) {
        return Err(AppError::ParseError(format!(
            "range replacement join {join} is not a source character boundary"
        )));
    }

    let leaves: Vec<_> = spans.blocks().filter(|block| block.is_leaf()).collect();
    let leaf = leaves
        .iter()
        .copied()
        .filter(|block| block.source.start <= join && join <= block.source.end)
        .max_by_key(|block| block.source.start)
        .or_else(|| {
            leaves
                .iter()
                .copied()
                .filter(|block| block.source.start >= join)
                .min_by_key(|block| block.source.start)
        })
        .or_else(|| {
            leaves
                .iter()
                .copied()
                .filter(|block| block.source.end <= join)
                .max_by_key(|block| block.source.end)
        });

    let Some(leaf) = leaf else {
        let insertion_index = spans
            .blocks()
            .filter(|block| block.path.len() == 1 && block.source.end <= join)
            .count();
        return Ok(RangeEditLocation::Phantom { insertion_index });
    };

    let caret_source_offset = join.clamp(leaf.source.start, leaf.source.end);
    let prefix = source
        .get(leaf.source.start..caret_source_offset)
        .ok_or_else(|| {
            AppError::ParseError(format!(
                "range replacement join {caret_source_offset} is not addressable in resulting leaf {:?}",
                leaf.path
            ))
        })?;
    Ok(RangeEditLocation::Block {
        block_path: leaf.path.clone(),
        source_offset_utf16: prefix.encode_utf16().count(),
    })
}

/// Resolves a post-splice source position to the editable leaf that contains
/// it, or to the next leaf when Markdown syntax occupies the immediate bytes
/// before that leaf (for example the indentation after a new blank line).
fn editable_leaf_at_or_after_source_offset(
    source: &str,
    spans: &SpanMap,
    source_offset: usize,
) -> Result<(Vec<usize>, usize), AppError> {
    let leaf = spans
        .blocks()
        .filter(|block| block.is_leaf())
        .filter(|block| {
            (block.source.start <= source_offset && source_offset < block.source.end)
                || block.source.start >= source_offset
        })
        .min_by_key(|block| block.source.start)
        .ok_or_else(|| {
            AppError::ParseError(format!(
                "no editable leaf follows source offset {source_offset} after structural edit"
            ))
        })?;
    let caret_source_offset = source_offset.max(leaf.source.start);
    let prefix = source
        .get(leaf.source.start..caret_source_offset)
        .ok_or_else(|| {
            AppError::ParseError(format!(
                "source offset {caret_source_offset} is not addressable in the resulting leaf"
            ))
        })?;
    Ok((leaf.path.clone(), prefix.encode_utf16().count()))
}

fn block_span(spans: &SpanMap, path: &[usize]) -> Result<std::ops::Range<usize>, AppError> {
    spans
        .block(path)
        .map(|block| block.source.clone())
        .ok_or_else(|| AppError::ParseError(format!("no Block at block_path {path:?}")))
}

/// Resolves an edit address against the freshly parsed working source.
///
/// `update_block` keeps the focused leaf's old path and resizes its retained
/// span without parsing. When its text becomes a container (for example, a
/// paragraph becoming a List), that path now names a container in the live
/// tree. The old span still identifies exactly the source region the user was
/// editing, so select the unique live leaf contained by it instead of treating
/// the retained AST as current structure.
fn editable_live_path(
    live_spans: &SpanMap,
    retained_spans: &SpanMap,
    requested_path: &[usize],
) -> Result<Vec<usize>, AppError> {
    if let Some(block) = live_spans.block(requested_path) {
        if block.is_leaf() {
            return Ok(block.path.clone());
        }
    }

    let retained = retained_spans.block(requested_path).ok_or_else(|| {
        AppError::ParseError(format!("no Block at block_path {requested_path:?}"))
    })?;
    if !retained.is_leaf() {
        return Err(AppError::ParseError(format!(
            "no live Block at block_path {requested_path:?}"
        )));
    }
    let candidates: Vec<_> = live_spans
        .blocks()
        .filter(|block| {
            block.is_leaf()
                && retained.source.start <= block.source.start
                && block.source.end <= retained.source.end
        })
        .collect();
    match candidates.as_slice() {
        [block] => Ok(block.path.clone()),
        [] => Err(AppError::ParseError(format!(
            "block_path {requested_path:?} no longer names an editable leaf after its buffered edit"
        ))),
        _ => Err(AppError::ParseError(format!(
            "block_path {requested_path:?} became multiple editable leaves after its buffered edit; commit it before a structural edit"
        ))),
    }
}

/// Resolves any structural address through the live source, retaining a
/// buffered leaf's source region only when its pre-reparse path disappeared.
fn live_path(
    live_spans: &SpanMap,
    retained_spans: &SpanMap,
    requested_path: &[usize],
) -> Result<Vec<usize>, AppError> {
    if let Some(block) = live_spans.block(requested_path) {
        return Ok(block.path.clone());
    }
    editable_live_path(live_spans, retained_spans, requested_path)
}

#[cfg(test)]
fn node_at_path<'a>(nodes: &'a [AstNode], path: &[usize]) -> Option<&'a AstNode> {
    let (head, rest) = path.split_first()?;
    let node = nodes.get(*head)?;
    if rest.is_empty() {
        return Some(node);
    }
    match node {
        AstNode::List { items, .. } => node_at_path(items, rest),
        AstNode::ListItem { content, .. } => node_at_path(content, rest),
        AstNode::Blockquote { nodes } => node_at_path(nodes, rest),
        AstNode::Suggestion { local_content, .. } => node_at_path(local_content, rest),
        _ => None,
    }
}

/// The closest ListItem containing `path`, expressed as the List's path and
/// its item index. A quote or nested list between the outer list and leaf is
/// traversed, so continuation stays in the innermost list the user is editing.
fn nearest_list_item(nodes: &[AstNode], path: &[usize]) -> Option<(Vec<usize>, usize)> {
    fn walk(
        nodes: &[AstNode],
        path: &[usize],
        prefix: &mut Vec<usize>,
        closest: &mut Option<(Vec<usize>, usize)>,
    ) -> Option<()> {
        let (head, rest) = path.split_first()?;
        let node = nodes.get(*head)?;
        if let AstNode::List { .. } = node {
            let item = *rest.first()?;
            let mut list_path = prefix.clone();
            list_path.push(*head);
            *closest = Some((list_path, item));
        }
        prefix.push(*head);
        let result = if rest.is_empty() {
            Some(())
        } else {
            match node {
                AstNode::List { items, .. } => walk(items, rest, prefix, closest),
                AstNode::ListItem { content, .. } => walk(content, rest, prefix, closest),
                AstNode::Blockquote { nodes } => walk(nodes, rest, prefix, closest),
                AstNode::Suggestion { local_content, .. } => {
                    walk(local_content, rest, prefix, closest)
                }
                _ => None,
            }
        };
        prefix.pop();
        result
    }
    let mut closest = None;
    walk(nodes, path, &mut Vec::new(), &mut closest)?;
    closest
}

/// The complete Markdown prefix on the line that introduces an editable list
/// leaf. This deliberately includes enclosing blockquote markers and nested
/// indentation, not merely the ListItem's own `- ` or `1. ` marker.
fn line_prefix_before(source: &str, content_start: usize) -> Result<&str, AppError> {
    let before = source.get(..content_start).ok_or_else(|| {
        AppError::ParseError(format!("source offset {content_start} is not addressable"))
    })?;
    let line_start = before.rfind('\n').map_or(0, |newline| newline + 1);
    source.get(line_start..content_start).ok_or_else(|| {
        AppError::ParseError(format!(
            "source line prefix {line_start}..{content_start} is not addressable"
        ))
    })
}

/// How many newlines a Block must be followed by for the next one to be a
/// separate Block: a blank line, which is two.
const BLOCK_SEPARATOR_NEWLINES: usize = 2;

/// How many newlines terminate `text`, counting a `\r\n` pair as one.
///
/// This is the unit both seam helpers measure in, because "is there a blank
/// line here" is a question about the newline run at a boundary and nothing
/// else — a leaf Block's span runs to the newline that terminates it, and a
/// container's last child absorbs the blank line that closes the container.
fn trailing_newlines(text: &str) -> usize {
    text.bytes()
        .rev()
        .filter(|byte| *byte != b'\r')
        .take_while(|byte| *byte == b'\n')
        .count()
}

/// How many newlines `text` begins with, counting a `\r\n` pair as one.
///
/// This complements [`trailing_newlines`] at an insertion seam: existing
/// separator bytes after an insertion point already separate the new source
/// from the following Block and must not be duplicated.
fn leading_newlines(text: &str) -> usize {
    text.bytes()
        .take_while(|byte| matches!(byte, b'\n' | b'\r'))
        .filter(|byte| *byte != b'\r')
        .count()
}

/// How the text ending at this boundary spells a line ending: `"\r\n"` when the
/// last one in `text` is a CRLF pair, `"\n"` otherwise (including when there is
/// none at all).
///
/// Every seam this module emits is measured CRLF-aware by [`trailing_newlines`]
/// and used to be *written* LF-only, which put a bare `\n` into a
/// CRLF-authored Note on every insert and every delete. The Note still parses —
/// CommonMark accepts either — but `prd/constraints.md`'s Edit Fidelity is about
/// the bytes: a mixed-ending file shows the user a diff line for a seam they
/// never touched, and a Windows-authored bundle grows one of those per edit.
/// Deriving the spelling from the text the seam is being welded onto is what
/// keeps the file internally consistent whichever convention it was written in.
///
/// Visible to [`super::lifecycle`] because a rename inserts a line too — the
/// frontmatter `title` a Note did not carry — and that insert has exactly this
/// obligation. One definition rather than two, for `classify_entry`'s reason:
/// a policy that has to hold everywhere and is spelled twice is one that will
/// eventually hold in only one of the two places.
pub(super) fn newline_style(text: &str) -> &'static str {
    match text.rfind('\n') {
        Some(at) if text[..at].ends_with('\r') => "\r\n",
        _ => "\n",
    }
}

/// The newlines that must be emitted at the end of `before` for text appended
/// to it to start `required` newlines' worth of separation later.
///
/// Spelled the way `before` spells its own line endings ([`newline_style`]).
///
/// Empty when `before` is empty — the start of the Note is already a Block
/// boundary and padding it would open the file with a blank line.
fn separator_before(before: &str, required: usize) -> String {
    if before.is_empty() {
        return String::new();
    }
    newline_style(before).repeat(required.saturating_sub(trailing_newlines(before)))
}

/// Where `text` ends once its trailing newline run is cut back to the single
/// line ending a Note ends in, counted and spelled CRLF-aware like every other
/// seam here ([`trailing_newlines`], [`newline_style`]).
///
/// `text.len()` when there is nothing to cut — one line ending or none at all,
/// which is also the empty case: deleting the only Block of a Note leaves an
/// empty file rather than a lone newline.
fn cut_to_one_trailing_newline(text: &str) -> usize {
    let bytes = text.as_bytes();
    let mut end = text.len();
    for _ in 1..trailing_newlines(text) {
        // Each iteration removes one line ending, which is a `\n` and the `\r`
        // in front of it when the Note is CRLF-authored.
        end -= 1;
        if end > 0 && bytes[end - 1] == b'\r' {
            end -= 1;
        }
    }
    end
}

/// The text that must replace `source[start..end]` for what precedes `start` to
/// stay as separated from what follows `end` as the removed region kept them.
///
/// Empty on either edge of the Note: with nothing on one side there is no seam,
/// and padding one would leave a leading or trailing blank line that the delete
/// was not asked for.
fn separator_across(source: &str, start: usize, end: usize) -> String {
    let (Some(before), Some(removed), Some(after)) = (
        source.get(..start),
        source.get(start..end),
        source.get(end..),
    ) else {
        return String::new();
    };
    if before.is_empty() || after.is_empty() {
        return String::new();
    }
    separator_before(before, trailing_newlines(removed))
}

/// The **byte length** of the newline run `text` opens with, counting `\r` and
/// `\n` alike so a CRLF pair contributes two.
///
/// The counterpart of [`trailing_newlines`], read from the other end and in the
/// other unit: that one answers "is there a blank line here", which is a count
/// of line endings, while this one answers "where does the run stop", which is
/// an index a splice range needs. Both bytes are ASCII, so the result is always
/// a character boundary.
fn newline_run_len(text: &str) -> usize {
    text.bytes()
        .take_while(|byte| matches!(byte, b'\n' | b'\r'))
        .count()
}

/// `text` collapsed onto one line and cut to `limit` characters, for quoting
/// invisible content back to a caller in an error message.
///
/// Bounded because the content being quoted is a region the editor cannot show
/// — a raw HTML block can be the size of an embedded SVG, and an error is a
/// sentence rather than a dump of it.
fn elided(text: &str, limit: usize) -> String {
    let one_line = text.split_whitespace().collect::<Vec<_>>().join(" ");
    match one_line.char_indices().nth(limit) {
        Some((at, _)) => format!("{}…", &one_line[..at]),
        None => one_line,
    }
}

/// The end of the last Block ending at or before `span.start`.
fn previous_block_end(spans: &SpanMap, span: &std::ops::Range<usize>) -> Option<usize> {
    spans
        .blocks()
        .filter(|block| block.source.end <= span.start)
        .map(|block| block.source.end)
        .max()
}

/// The first editable descendant of `parent_path`, in document order.
fn first_editable_leaf<'a>(
    spans: &'a SpanMap,
    parent_path: &[usize],
) -> Option<&'a crate::markdown::BlockSpan> {
    spans
        .blocks()
        .filter(|block| block.is_leaf() && block.path.starts_with(parent_path))
        .min_by_key(|block| block.source.start)
}

/// The last editable descendant of `parent_path`, in document order.
fn last_editable_leaf<'a>(
    spans: &'a SpanMap,
    parent_path: &[usize],
) -> Option<&'a crate::markdown::BlockSpan> {
    spans
        .blocks()
        .filter(|block| block.is_leaf() && block.path.starts_with(parent_path))
        .max_by_key(|block| block.source.end)
}

/// The editable leaf immediately before `span`, ignoring container spans.
fn previous_editable_leaf<'a>(
    spans: &'a SpanMap,
    span: &std::ops::Range<usize>,
) -> Option<&'a crate::markdown::BlockSpan> {
    spans
        .blocks()
        .filter(|block| block.is_leaf() && block.source.end <= span.start)
        .max_by_key(|block| block.source.end)
}

/// Flutter caret offset immediately before the source's line terminator.
fn source_caret_before_trailing_newline(source: &str) -> usize {
    source.trim_end_matches(['\r', '\n']).encode_utf16().count()
}

fn containing_dir(concept_id: &str) -> &str {
    concept_id.rsplit_once('/').map_or("", |(dir, _)| dir)
}

fn file_mtime(path: &Path) -> i64 {
    std::fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map_or(0, |d| i64::try_from(d.as_secs()).unwrap_or(0))
}

fn unix_now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .ok()
        .map_or(0, |d| i64::try_from(d.as_secs()).unwrap_or(0))
}

/// The one derivation of a Note's display metadata from its source, shared with
/// [`super::lifecycle`] rather than duplicated there.
///
/// Title derivation is load-bearing — it is what the tree, the palette and
/// every completion label read — and it has a fallback (`title` absent, blank
/// or whitespace-only ⇒ the filename) that two copies are free to disagree
/// about silently. `pub(super)` so the sibling module calls this one instead of
/// keeping its own; this is the copy with six call sites and the one every
/// editing path already goes through.
pub(super) fn derive_metadata(
    note_id: &str,
    source: &str,
    spans: &SpanMap,
    last_modified: i64,
) -> NoteMetadata {
    let frontmatter = spans
        .frontmatter()
        .and_then(|span| source.get(span))
        .map_or_else(Default::default, read_frontmatter);
    let title = frontmatter
        .title
        .as_deref()
        .map(str::trim)
        .filter(|t| !t.is_empty())
        .map_or_else(
            || {
                note_id
                    .rsplit_once('/')
                    .map_or(note_id, |(_, name)| name)
                    .to_string()
            },
            str::to_string,
        );
    NoteMetadata {
        id: note_id.to_string(),
        path: concept_id_to_path(note_id),
        title,
        last_modified,
        snippet: None,
        okf_conformant: frontmatter.is_conformant(),
    }
}

/// Turns the conflict regions of a merged file into `AstNode::Suggestion`
/// nodes, or `None` when the source holds no conflict markers.
///
/// `git merge`'s default `merge` style emits no base section, so
/// `base_content` is populated only for a `diff3`-style conflict. Nothing else
/// in the crate produces a `Suggestion`: it is materialized from markers, never
/// parsed, which is why this lives on the reload path rather than in the
/// parser.
///
/// The span map handed back alongside this AST is the one built from the whole
/// source, so it does not address the Suggestion nodes — and it is worse than
/// that: collapsing a conflict region's several raw Blocks into one node
/// **renumbers** every Block after it, so the two structures describe different
/// documents rather than merely disagreeing about one region. That is why
/// [`SessionState::conflicted`] exists. Returning a collapsed AST is what sets
/// it, and while it stands every call that takes a `block_path` is refused, so
/// the mismatch is unreachable rather than merely documented. Epic H owns the
/// resolution surface.
///
/// # An unterminated region is not a conflict
///
/// The scan is line-based and has no idea what a fenced code block is, so a
/// Note that *documents* a merge conflict — `<<<<<<< HEAD` inside a fence,
/// which is an ordinary thing to write — opens a region nothing closes. Every
/// line after it accumulated into a section that was never emitted, and the
/// tail of the Note disappeared from the AST outright.
///
/// So a scan that ends anywhere but [`Section::Plain`] reports `None`: the
/// document is treated as **not conflicted**, parsed as the ordinary Markdown
/// it is, and the fenced sample stays visible as text. That is the right answer
/// for both populations this reaches. A prose Note about merge conflicts is not
/// conflicted, and neither is a genuinely truncated merge file — Git's own
/// output always closes what it opens, so a region with no `>>>>>>>` is not
/// something this application should be materializing Suggestions from.
fn conflict_suggestions(source: &str, containing_dir: &str) -> Option<Vec<AstNode>> {
    // Spelled exactly as the scan below spells it: `<<<<<<<` at the start of a
    // line, with no trailing space required. The early exit used to demand one
    // while the scan did not, so an unlabeled marker — which `git` itself
    // writes when the conflicting side has no name to put there — short-
    // circuited as unconflicted and rendered as literal text in an editable
    // Note. The direction was safe, but one predicate spelled two ways is an
    // invitation to reconcile them the other way round, which un-sets
    // `conflicted` on a real conflict.
    if !source.starts_with("<<<<<<<") && !source.contains("\n<<<<<<<") {
        return None;
    }

    let mut nodes: Vec<AstNode> = Vec::new();
    let mut plain = String::new();
    let mut local = String::new();
    let mut base: Option<String> = None;
    let mut incoming = String::new();
    let mut section = Section::Plain;
    let mut saw_conflict = false;

    for line in source.split_inclusive('\n') {
        let trimmed = line.trim_end_matches(['\n', '\r']);
        match (&section, trimmed) {
            (Section::Plain, marker) if marker.starts_with("<<<<<<<") => {
                // The head of the document is the text before the **first**
                // marker, and only there can a leading `---` be frontmatter.
                let segment = if saw_conflict {
                    Segment::Interior
                } else {
                    Segment::Head
                };
                nodes.extend(parse_markdown_segment(&plain, containing_dir, segment));
                plain.clear();
                local.clear();
                base = None;
                incoming.clear();
                section = Section::Local;
                saw_conflict = true;
            }
            (Section::Local, marker) if marker.starts_with("|||||||") => {
                base = Some(String::new());
                section = Section::Base;
            }
            (Section::Local | Section::Base, marker) if marker.starts_with("=======") => {
                section = Section::Incoming;
            }
            (Section::Incoming, marker) if marker.starts_with(">>>>>>>") => {
                nodes.push(AstNode::Suggestion {
                    base_content: base.take().map(|text| {
                        parse_markdown_segment(&text, containing_dir, Segment::Interior)
                    }),
                    local_content: parse_markdown_segment(
                        &local,
                        containing_dir,
                        Segment::Interior,
                    ),
                    incoming_content: parse_markdown_segment(
                        &incoming,
                        containing_dir,
                        Segment::Interior,
                    ),
                });
                section = Section::Plain;
            }
            (Section::Plain, _) => plain.push_str(line),
            (Section::Local, _) => local.push_str(line),
            (Section::Base, _) => {
                if let Some(text) = base.as_mut() {
                    text.push_str(line);
                }
            }
            (Section::Incoming, _) => incoming.push_str(line),
        }
    }
    // Nothing is salvaged from a half-open region, and nothing is fabricated
    // from one either: whatever `local`, `base` and `incoming` accumulated is
    // dropped along with `nodes`, and the caller parses the source as ordinary
    // Markdown instead. See this function's own documentation.
    if !saw_conflict || !matches!(section, Section::Plain) {
        return None;
    }
    // Never the head: this runs only after at least one region closed, so
    // whatever `plain` holds started after a `>>>>>>>` line.
    nodes.extend(parse_markdown_segment(
        &plain,
        containing_dir,
        Segment::Interior,
    ));
    Some(nodes)
}

enum Section {
    Plain,
    Local,
    Base,
    Incoming,
}

/// Parses one segment of a conflicted Note — a conflict side, or the plain text
/// between regions — into the Blocks the collapse splices together.
///
/// Two things are positional here, and getting either wrong loses content.
///
/// `containing_dir` is passed to **every** segment. It is what
/// `okf::links::classify` resolves a relative destination against (OKF §6.1),
/// and a conflicted Note's segments live in the same Directory as the Note
/// itself. Only the `---` branch used to receive it, so every conflict side and
/// every post-head segment resolved its Links against the bundle root instead:
/// `[u](Other.md)` inside `sub/a.md` became `Internal("Other")`, an id no
/// `notes.id` equals, so the Link rendered as a ghost pointing at a Note
/// sitting right beside it.
///
/// [`Segment::Head`] is the segment that starts at byte zero, and it is the
/// only one parsed with the YAML metadata option. Frontmatter is positional
/// under OKF §4 — byte zero of the file and nowhere else — so applying the
/// option to a later segment reads a `---` that is an ordinary thematic break
/// as the opening fence of a metadata block. A local side of `---\nMine\n---`
/// then produced no nodes at all, silently dropping one of the two versions of
/// the user's work out of the Suggestion asking them to choose between the two.
fn parse_markdown_segment(source: &str, containing_dir: &str, segment: Segment) -> Vec<AstNode> {
    if source.trim().is_empty() {
        return Vec::new();
    }
    match segment {
        Segment::Head => parse_note(source, containing_dir).ast,
        Segment::Interior => parse_markdown_fragment(source, containing_dir),
    }
}

/// Where a segment sits in the document, which is what decides whether a
/// leading `---` can be frontmatter. See [`parse_markdown_segment`].
#[derive(Clone, Copy)]
enum Segment {
    Head,
    Interior,
}

#[cfg(test)]
impl NoteSession {
    /// The source span currently recorded for one Block. Test-only: spans are
    /// Core-side state and cross no boundary (ADR-007 decision 3).
    fn span_of(&self, block_path: &[usize]) -> std::ops::Range<usize> {
        self.lock_state()
            .unwrap()
            .spans
            .block(block_path)
            .unwrap_or_else(|| panic!("no Block at {block_path:?}"))
            .source
            .clone()
    }

    pub(crate) fn edit_seq(&self) -> i64 {
        self.lock_state().unwrap().edit_seq
    }

    /// Poisons this session's state lock, which is what a panic inside a
    /// mutator that held it leaves behind. `pub(crate)` for `api::ffi_api`'s
    /// test of `note_write_status`, which is the surface that has to tell a
    /// broken session apart from a clean one; the lock is private state and
    /// there is no other way to reach that branch.
    pub(crate) fn poison_state_for_test(&self) {
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _guard = self.0.state.lock();
            panic!("poisoning this session's state lock on purpose (test)");
        }));
    }

    /// Drops this session from the registry without closing it — what an
    /// abrupt process termination leaves behind, minus the process.
    fn forget(&self) {
        registry()
            .unwrap()
            .remove(&(self.0.workspace.id().to_string(), self.0.note_id.clone()));
    }
}

#[cfg(test)]
mod tests {
    use std::process::Command;
    use std::sync::atomic::{AtomicU32, AtomicUsize};

    use tempfile::TempDir;

    use super::*;

    // -- fixture -------------------------------------------------------------

    struct Fixture {
        dir: TempDir,
        workspace: Arc<Workspace>,
    }

    impl Fixture {
        fn root(&self) -> PathBuf {
            self.dir.path().join("bundle")
        }

        fn write(&self, relative: &str, contents: &str) {
            let path = self.root().join(relative);
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent).unwrap();
            }
            std::fs::write(path, contents).unwrap();
        }

        fn read(&self, relative: &str) -> String {
            std::fs::read_to_string(self.root().join(relative)).unwrap()
        }

        fn open(&self, note_id: &str) -> NoteSession {
            open_note(&self.workspace, note_id).unwrap().0
        }

        /// A full rebuild, in the two phases production uses: the walk runs
        /// with no connection held, and only the row write goes under it.
        /// Calling `reindex_workspace_impl` inside a `with_db` closure instead
        /// trips the debug guard, which is the point of the split.
        fn reindex(&self) {
            let scanned = crate::index::scan::scan_bundle(&self.root()).unwrap();
            self.workspace
                .with_db(|conn| {
                    crate::index::scan::write_scanned_bundle(conn, self.workspace.id(), &scanned)
                })
                .unwrap();
        }

        fn draft(&self, note_id: &str) -> Option<DraftRow> {
            self.workspace
                .with_db(|conn| read_draft(conn, self.workspace.id(), note_id))
                .unwrap()
        }

        /// Makes every `DELETE` on `drafts` after the first `allowed` of them
        /// fail, for the whole life of this fixture's connection.
        ///
        /// A `RAISE(ABORT)` trigger — the injection every other failure test
        /// here uses — cannot express this. `close` issues the identical
        /// statement twice in a row (the flush's conditional clear, then its
        /// own), the first deletes the row and the second therefore matches
        /// nothing, so a row trigger fires on the stage that must succeed and
        /// not on the stage under test. An authorizer runs while the statement
        /// is being *prepared*, before any row is looked at, which is the only
        /// hook that can tell the two apart.
        fn deny_drafts_delete_after(&self, allowed: usize) {
            let seen = Arc::new(AtomicUsize::new(0));
            self.workspace
                .with_db(|conn| {
                    conn.authorizer(Some(move |context: rusqlite::hooks::AuthContext<'_>| {
                        match context.action {
                            rusqlite::hooks::AuthAction::Delete {
                                table_name: "drafts",
                            } => {
                                if seen.fetch_add(1, Ordering::SeqCst) >= allowed {
                                    rusqlite::hooks::Authorization::Deny
                                } else {
                                    rusqlite::hooks::Authorization::Allow
                                }
                            }
                            _ => rusqlite::hooks::Authorization::Allow,
                        }
                    }))?;
                    Ok(())
                })
                .unwrap();
        }

        /// Undoes [`Fixture::deny_drafts_delete_after`], so a test can go on to
        /// show the Note is usable again rather than trapped.
        fn allow_drafts_delete(&self) {
            self.workspace
                .with_db(|conn| {
                    conn.authorizer(None::<fn(rusqlite::hooks::AuthContext<'_>) -> _>)?;
                    Ok(())
                })
                .unwrap();
        }

        /// Runs `sql` against the index, so that a failure arising *after* the
        /// filesystem phase can be driven deterministically rather than waited
        /// for. Used to install and drop `RAISE(ABORT)` triggers, the same
        /// injection `workspace::lifecycle`'s tests use.
        fn inject_failure(&self, sql: &str) {
            self.workspace
                .with_db(|conn| {
                    conn.execute_batch(sql)?;
                    Ok(())
                })
                .unwrap();
        }

        /// A baseline commit, so a test that inspects history is comparing
        /// against something rather than against an unborn `HEAD`.
        fn commit_baseline(&self) {
            crate::git::operations::commit_all(
                &self.root(),
                "baseline",
                "Test",
                "test@example.com",
            )
            .unwrap();
        }

        fn git(&self, args: &[&str]) -> String {
            let output = Command::new("git")
                .args(args)
                .current_dir(self.root())
                .env("GIT_CONFIG_GLOBAL", "/dev/null")
                .env("GIT_CONFIG_SYSTEM", "/dev/null")
                .output()
                .expect("git CLI available in devenv shell");
            String::from_utf8_lossy(&output.stdout).trim().to_string()
        }

        fn commit_subjects(&self) -> Vec<String> {
            let log = self.git(&["log", "--format=%s"]);
            if log.is_empty() {
                return Vec::new();
            }
            log.lines().map(str::to_string).collect()
        }
    }

    fn fixture() -> Fixture {
        // An interval no test waits out: every test but the timer's own fires
        // the tiers explicitly, which is both faster and deterministic.
        fixture_with_idle(Duration::from_secs(3600))
    }

    fn fixture_with_idle(idle: Duration) -> Fixture {
        fixture_in(tempfile::tempdir().unwrap(), idle)
    }

    /// A fixture on storage that really fsyncs.
    ///
    /// `SPK-WSPC-D001` §3 records this as one of the two methodological points
    /// that changed its own answers: `/tmp` is `tmpfs` on this project's target
    /// machine, where every write runs at memory speed and `fsync` is a no-op,
    /// and its first pass understated tier 2's atomic write by roughly 20x.
    /// `tempfile::tempdir()` follows `TMPDIR`, so a timing test that used it
    /// would measure memory rather than the encrypted index on a disk. Falls
    /// back to the ordinary temporary directory where `/var/tmp` does not
    /// exist, and the test prints which one it used so a number is never
    /// quoted without its filesystem.
    fn fixture_on_durable_storage(idle: Duration) -> (Fixture, PathBuf) {
        let durable = PathBuf::from("/var/tmp");
        let dir = if durable.is_dir() {
            tempfile::Builder::new()
                .prefix("burlmd-persist-")
                .tempdir_in(&durable)
                .unwrap()
        } else {
            tempfile::tempdir().unwrap()
        };
        let path = dir.path().to_path_buf();
        (fixture_in(dir, idle), path)
    }

    fn fixture_in(dir: TempDir, idle: Duration) -> Fixture {
        static NEXT_WORKSPACE: AtomicU32 = AtomicU32::new(0);

        let root = dir.path().join("bundle");
        std::fs::create_dir_all(&root).unwrap();
        crate::git::operations::init_repo(&root).unwrap();

        let key = [0x5au8; 32]; // throwaway, never the real Keychain entry
        let conn = crate::db::connection::open_encrypted_db_with_key(
            &dir.path().join("index.sqlite3"),
            &key,
        )
        .unwrap();
        crate::db::connection::init_schema(&conn).unwrap();

        // Unique per fixture: the open-note registry and the scheduler slot are
        // process-wide, and the test harness runs these in parallel.
        let workspace_id = format!("ws-{}", NEXT_WORKSPACE.fetch_add(1, Ordering::SeqCst));
        conn.execute(
            "INSERT INTO workspaces (id, name, provider, remote_url, local_path) \
             VALUES (?1, 'Test Workspace', 'local', NULL, ?2)",
            rusqlite::params![workspace_id, root.to_string_lossy()],
        )
        .unwrap();

        let workspace = Workspace::for_test(conn, workspace_id, root, idle);
        Fixture { dir, workspace }
    }

    fn note(title: &str, body: &str) -> String {
        format!("---\ntype: Note\ntitle: {title}\n---\n\n{body}\n")
    }

    fn wait_until(limit: Duration, mut condition: impl FnMut() -> bool) -> bool {
        let deadline = Instant::now() + limit;
        while Instant::now() < deadline {
            if condition() {
                return true;
            }
            std::thread::sleep(Duration::from_millis(5));
        }
        condition()
    }

    // -- tier 1: the buffered edit ------------------------------------------

    /// ADR-008 decision 2, worked through on its own example. A Block whose
    /// source grows by two bytes moves its **own** span end by two as well as
    /// shifting every later span by two. A rule that only shifted the later
    /// ones would leave the next splice replacing too little.
    #[test]
    fn a_buffered_edit_resizes_the_edited_span_and_shifts_every_later_one() {
        let f = fixture();
        f.write("a.md", "AAA\n\nBBB\n");
        let session = f.open("a");
        // ADR-008 decision 2 writes the example's spans as `[0,3)` and
        // `[5,8)`; a real Block span runs to the newline that terminates it,
        // so they are `[0,4)` and `[5,9)` here. The arithmetic the decision
        // states is unaffected — it is about the delta, not the endpoints.
        assert_eq!(session.span_of(&[0]), 0..4);
        assert_eq!(session.span_of(&[1]), 5..9);

        // Two bytes typed at the end of the first Block.
        session.update_block(&[0], "AAAXX\n").unwrap();

        assert_eq!(*session.working_source().unwrap(), "AAAXX\n\nBBB\n");
        assert_eq!(
            session.span_of(&[0]),
            0..6,
            "the edited Block's own span end must move by the delta, not stay put"
        );
        assert_eq!(
            session.span_of(&[1]),
            7..11,
            "every later span must shift by the same delta"
        );
    }

    /// The regression ADR-008 decision 2 exists to make unrepresentable: a
    /// second writer re-splicing the buffered source over an unresized span
    /// duplicates the typed bytes inside the Block the user is still typing in.
    #[test]
    fn an_idle_write_mid_focus_then_a_blur_leaves_the_typed_text_exactly_once() {
        let f = fixture();
        f.write("a.md", "AAA\n\nBBB\n");
        let session = f.open("a");

        session.update_block(&[0], "AAAXX\n").unwrap();
        // The timer may fire while the Block is still focused; that is what
        // this tier is for.
        session.flush().unwrap();
        assert_eq!(f.read("a.md"), "AAAXX\n\nBBB\n");

        // Typing continues in the same focused Block, then it blurs.
        session.update_block(&[0], "AAAXXY\n").unwrap();
        session.commit_block(&[0]).unwrap();
        session.flush().unwrap();

        let written = f.read("a.md");
        assert_eq!(written, "AAAXXY\n\nBBB\n");
        assert_eq!(written.matches("XX").count(), 1, "typed text duplicated");
    }

    /// A tier 2 write must not relax the permissions the user chose.
    ///
    /// `atomic_write` publishes by renaming a fresh temporary file over the
    /// target, and a fresh file is created at the process umask — 0644 in the
    /// ordinary case. Renaming that over a Note the user had deliberately
    /// restricted to 0600 replaced its mode along with its bytes, so the first
    /// idle write after opening a private Note quietly made it world-readable
    /// with nothing in the UI to say so.
    #[cfg(unix)]
    #[test]
    fn a_tier_two_write_preserves_a_restrictive_file_mode() {
        use std::os::unix::fs::PermissionsExt;

        let f = fixture();
        f.write(
            "private.md",
            "---\ntype: Note\ntitle: Private\n---\n\nsecret\n",
        );
        let path = f.root().join("private.md");
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).unwrap();

        let session = f.open("private");
        session
            .update_block(&[0], "secret and then some\n")
            .unwrap();
        session.flush().unwrap();

        let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(
            mode, 0o600,
            "a tier 2 write widened the Note's mode to {mode:o}"
        );
        assert!(f.read("private.md").contains("secret and then some"));
    }

    /// The same rule one step earlier, on the window the end-state test above
    /// cannot see: the temporary file must never exist at a wider mode, not even
    /// for the duration of the write.
    ///
    /// The regression this pins: the temporary was created with
    /// `File::create` — the process umask, 0644 in the ordinary case — and
    /// narrowed only after the content was written and `fsync`ed. Every Note in
    /// the Workspace, including one deliberately restricted to 0600, was
    /// therefore readable by any user on the machine for the whole of each idle
    /// write, in a file whose eventual mode was correct. Probing that window
    /// from outside is a race; asserting the creation mode is not.
    #[cfg(unix)]
    #[test]
    fn the_temporary_file_a_write_publishes_from_is_private_from_creation() {
        use std::os::unix::fs::PermissionsExt;

        let dir = tempfile::tempdir().unwrap();
        let temp = dir.path().join(".Private.md.4242.0.tmp");

        let file = create_private_temp(&temp).expect("the temporary must be creatable");

        let mode = file.metadata().unwrap().permissions().mode() & 0o777;
        assert_eq!(
            mode, 0o600,
            "the temporary was created at {mode:o}, exposing the Note's plaintext"
        );
        assert!(
            create_private_temp(&temp).is_err(),
            "the name carries a pid and a counter, so an existing one is a \
             collision to surface rather than a file to truncate"
        );
    }

    /// A 100 KiB Note, one Block edit, measured rather than assumed:
    /// `SPK-WSPC-D001` §4.3 corrected ADR-008's claim that this tier is cheap
    /// (7.96ms at 102 KiB with SQLite's defaults, 2.41ms under the WAL settings
    /// `WSPC-D004` now applies), and the measurement mutates the buffer on
    /// every call because rewriting a constant string reports 0.22ms and is
    /// wrong by a factor of 36.
    #[test]
    fn a_block_edit_on_a_hundred_kilobyte_note_writes_its_draft_row_within_the_frame_budget() {
        let (f, where_it_ran) = fixture_on_durable_storage(Duration::from_secs(3600));
        let filler = "Sed ut perspiciatis unde omnis iste natus error sit voluptatem.\n\n";
        let mut body = String::with_capacity(110_000);
        while body.len() < 100 * 1024 {
            body.push_str(filler);
        }
        f.write("big.md", &note("Big", &body));
        let session = f.open("big");
        let size = session.working_source().unwrap().len();

        let mut samples = Vec::new();
        for iteration in 0..25u32 {
            // Content that actually changes on every call, as a keystroke does.
            // A benchmark looping over a constant string measures a SQLCipher
            // no-op — 0.22ms against 7.96ms, wrong by a factor of 36
            // (`SPK-WSPC-D001` §3).
            let typed = format!("Sed ut perspiciatis unde omnis iste natus error{iteration}.\n");
            // Paced rather than tight: after an idle gap the core is at a lower
            // clock and the working set is out of cache, which is the state a
            // real keystroke arrives in. The tight-loop figure is optimistic by
            // 3-40x and is not the number to plan against.
            std::thread::sleep(Duration::from_millis(8));
            let started = Instant::now();
            session.update_block(&[1], &typed).unwrap();
            samples.push(started.elapsed());
        }
        samples.sort();
        let median = samples[samples.len() / 2];
        let p95 = samples[(samples.len() * 95) / 100];
        let worst = *samples.last().unwrap();

        // Recorded in the test output rather than asserted by inspection, per
        // this ticket's last Gherkin.
        println!(
            "tier 1 draft write, {size} bytes, {} samples, 8ms-paced, under {}: \
             median {:.3}ms, p95 {:.3}ms, max {:.3}ms",
            samples.len(),
            where_it_ran.display(),
            median.as_secs_f64() * 1000.0,
            p95.as_secs_f64() * 1000.0,
            worst.as_secs_f64() * 1000.0
        );
        assert!(
            p95 < Duration::from_millis(16),
            "tier 1 p95 {:.3}ms exceeds the 16ms frame budget at {size} bytes \
             (median {:.3}ms)",
            p95.as_secs_f64() * 1000.0,
            median.as_secs_f64() * 1000.0
        );
    }

    // -- tier 1: the structural mutators ------------------------------------

    /// Each of these is a discrete user action with no preceding keystroke
    /// call, so scoping tier 1 to `update_block` would leave the edit only in
    /// memory until the timer fired roughly a second later. A kill in that
    /// window loses it, which is exactly what this tier exists to prevent.
    #[test]
    fn every_structural_edit_writes_its_draft_row_before_the_write_tier_fires() {
        type StructuralEdit = Box<dyn Fn(&NoteSession)>;

        let cases: Vec<(&str, StructuralEdit)> = vec![
            (
                "split",
                Box::new(|s: &NoteSession| {
                    s.split_block(&[0], 3).unwrap();
                }),
            ),
            (
                "merge",
                Box::new(|s: &NoteSession| {
                    s.merge_block_with_previous(&[1]).unwrap();
                }),
            ),
            (
                "insert",
                Box::new(|s: &NoteSession| {
                    s.insert_block(&[0], "Inserted.".to_string()).unwrap();
                }),
            ),
            (
                "delete",
                Box::new(|s: &NoteSession| {
                    s.delete_block(&[0]).unwrap();
                }),
            ),
            (
                "replace_range",
                Box::new(|s: &NoteSession| {
                    let range = RenderedRange::new(vec![0], 0, vec![1], 3);
                    s.replace_range(&range, "Replaced.").unwrap();
                }),
            ),
        ];

        for (name, edit) in cases {
            let f = fixture();
            let on_disk = note("A", "First paragraph.\n\nSecond paragraph.");
            f.write("a.md", &on_disk);
            let session = f.open("a");
            assert!(
                f.draft("a").is_none(),
                "{name}: a draft row existed already"
            );

            edit(&session);

            let row = f
                .draft("a")
                .unwrap_or_else(|| panic!("{name} wrote no draft row"));
            assert_eq!(
                row.raw_markdown,
                *session.working_source().unwrap(),
                "{name}: the row does not hold the working source"
            );
            assert_ne!(row.raw_markdown, on_disk, "{name} changed nothing");
            assert_eq!(
                f.read("a.md"),
                on_disk,
                "{name} touched the file, which is tier 2's job"
            );
        }
    }

    /// A failed tier-1 write is a refusal, not a half-installed structural
    /// edit. In particular it must not arm a timer that later writes the
    /// refused buffer, and retrying after the database is healthy must apply
    /// the edit exactly once.
    #[test]
    fn a_structural_draft_failure_rolls_back_source_state_and_timer_before_retry() {
        let f = fixture_with_idle(Duration::from_millis(40));
        let original = note("A", "First paragraph.\n\nSecond paragraph.");
        f.write("a.md", &original);
        let session = f.open("a");
        let state_before = session.note_state().unwrap();
        let sequence_before = session.edit_seq();

        f.inject_failure(
            "CREATE TRIGGER injected_structural_draft_write BEFORE INSERT ON drafts \
             BEGIN SELECT RAISE(ABORT, 'injected structural draft failure'); END;",
        );
        let refused = session.insert_block(&[1], "Inserted.".to_string());

        assert!(refused.is_err(), "the injected tier-1 failure must refuse");
        assert_eq!(
            *session.working_source().unwrap(),
            original,
            "a refused structural edit left its source installed"
        );
        assert_eq!(
            session.note_state().unwrap(),
            state_before,
            "a refused structural edit left its reparsed state installed"
        );
        assert_eq!(
            session.edit_seq(),
            sequence_before,
            "a refused structural edit advanced the draft sequence"
        );
        assert!(
            f.draft("a").is_none(),
            "the failed statement wrote a draft row"
        );
        assert!(
            !wait_until(Duration::from_millis(180), || f.read("a.md") != original),
            "the failed structural edit armed a timer that wrote its refused source"
        );

        f.inject_failure("DROP TRIGGER injected_structural_draft_write;");
        session.insert_block(&[1], "Inserted.".to_string()).unwrap();
        let expected = note("A", "First paragraph.\n\nInserted.\n\nSecond paragraph.");
        assert_eq!(*session.working_source().unwrap(), expected);
        assert_eq!(
            f.draft("a").as_ref().map(|row| row.raw_markdown.as_str()),
            Some(expected.as_str()),
            "the successful retry did not write its complete draft"
        );
        assert!(
            wait_until(Duration::from_secs(3), || f.read("a.md") == expected),
            "the successful retry did not arm tier 2"
        );
        assert!(
            wait_until(Duration::from_millis(300), || f.draft("a").is_none()),
            "tier 2 did not clear the retry's draft row"
        );
    }

    /// If a pre-existing idle write publishes a structural mutation while its
    /// tier-1 draft statement is blocked, rollback would make the session
    /// disagree with disk. That branch must return the installed state as a
    /// success, not tell the caller to retry an edit that already happened.
    #[test]
    fn a_structural_draft_failure_after_tier_two_publication_returns_authoritative_success() {
        let f = fixture_with_idle(Duration::from_millis(100));
        let original = note("A", "First paragraph.\n\nSecond paragraph.");
        f.write("a.md", &original);
        let session = f.open("a");
        session.update_block(&[0], "First edited.\n").unwrap();
        let revision_before = session.note_state().unwrap().base_revision;
        let expected = note("A", "First edited.\n\nInserted.\n\nSecond paragraph.");

        f.inject_failure(
            "CREATE TRIGGER injected_structural_draft_update BEFORE UPDATE ON drafts \
             WHEN NEW.edit_seq = 2 \
             BEGIN SELECT RAISE(ABORT, 'injected structural draft failure'); END;",
        );

        let (entered_tx, entered_rx) = std::sync::mpsc::sync_channel(1);
        let (release_tx, release_rx) = std::sync::mpsc::sync_channel(0);
        let seen = Arc::new(AtomicUsize::new(0));
        let seen_update = Arc::clone(&seen);
        f.workspace
            .with_db(|conn| {
                conn.authorizer(Some(
                    move |context: rusqlite::hooks::AuthContext<'_>| match context.action {
                        rusqlite::hooks::AuthAction::Update {
                            table_name: "drafts",
                            ..
                        } if seen_update.fetch_add(1, Ordering::SeqCst) == 0 => {
                            entered_tx
                                .send(())
                                .expect("the test must still await the blocked draft write");
                            release_rx
                                .recv()
                                .expect("the test must release the blocked draft write");
                            rusqlite::hooks::Authorization::Allow
                        }
                        _ => rusqlite::hooks::Authorization::Allow,
                    },
                ))?;
                Ok(())
            })
            .unwrap();

        let structural = {
            let session = session.clone();
            std::thread::spawn(move || session.insert_block(&[1], "Inserted.".to_string()))
        };
        entered_rx
            .recv_timeout(Duration::from_secs(3))
            .expect("the structural write never reached the deterministic pause");
        assert!(
            wait_until(Duration::from_secs(3), || {
                session.note_state().unwrap().base_revision != revision_before
                    && f.read("a.md") == expected
            }),
            "tier 2 did not publish the structural source while tier 1 was paused"
        );

        release_tx
            .send(())
            .expect("the paused structural write stopped unexpectedly");
        let returned = structural
            .join()
            .expect("the structural thread must not panic")
            .expect("a published structural mutation must return success");
        f.allow_drafts_delete();
        f.inject_failure("DROP TRIGGER injected_structural_draft_update;");

        assert_eq!(returned, session.note_state().unwrap());
        assert_eq!(*session.working_source().unwrap(), expected);
        assert_eq!(f.read("a.md"), expected);
        assert_ne!(
            returned.base_revision, revision_before,
            "the successful result retained the pre-publication revision"
        );
        assert!(
            wait_until(Duration::from_secs(3), || {
                let timer = session.0.timer.state.lock().unwrap();
                !timer.running && timer.deadline.is_none()
            }),
            "the recovery timer did not finish before the fixture was dropped"
        );
    }

    /// Lifecycle rewrites install a new source, AST and revision. They must
    /// wait behind a structural mutation's tier-1 draft boundary: otherwise a
    /// failed structural write could return lifecycle state paired with its own
    /// stale focus/caret result.
    #[test]
    fn a_lifecycle_rewrite_waits_for_a_paused_failing_structural_draft_write() {
        let f = fixture();
        f.write("a.md", &note("A", "First paragraph.\n\nSecond paragraph."));
        let session = f.open("a");
        session.update_block(&[0], "First edited.\n").unwrap();

        f.inject_failure(
            "CREATE TRIGGER injected_structural_draft_update BEFORE UPDATE ON drafts \
             WHEN NEW.edit_seq = 2 \
             BEGIN SELECT RAISE(ABORT, 'injected structural draft failure'); END;",
        );
        let (entered_tx, entered_rx) = std::sync::mpsc::sync_channel(1);
        let (release_tx, release_rx) = std::sync::mpsc::sync_channel(0);
        let release_rx = Arc::new(Mutex::new(release_rx));
        let release_for_hook = Arc::clone(&release_rx);
        f.workspace.set_before_draft_write(Some(Arc::new(move || {
            entered_tx
                .send(())
                .expect("the test must still await the paused draft write");
            release_for_hook
                .lock()
                .unwrap()
                .recv()
                .expect("the test must release the paused draft write");
        })));

        let structural = {
            let session = session.clone();
            std::thread::spawn(move || session.insert_block(&[1], "Inserted.".to_string()))
        };
        entered_rx
            .recv_timeout(Duration::from_secs(3))
            .expect("the structural write never reached its deterministic pause");

        let lifecycle_source = note("A", "Rewritten by lifecycle.");
        let lifecycle_revision = content_hash(lifecycle_source.as_bytes());
        let (lifecycle_started_tx, lifecycle_started_rx) = std::sync::mpsc::sync_channel(1);
        let rewrite = {
            let session = session.clone();
            let source = lifecycle_source.clone();
            std::thread::spawn(move || {
                lifecycle_started_tx
                    .send(())
                    .expect("the test must observe the lifecycle attempt");
                session.install_rewrite(Some(source), lifecycle_revision)
            })
        };
        lifecycle_started_rx
            .recv_timeout(Duration::from_secs(3))
            .expect("the lifecycle rewrite thread never started");
        assert!(
            !wait_until(Duration::from_millis(200), || {
                *session.working_source().unwrap() == lifecycle_source
            }),
            "lifecycle rewrote the session while structural tier 1 was paused"
        );

        release_tx
            .send(())
            .expect("the paused structural write stopped unexpectedly");
        assert!(
            structural
                .join()
                .expect("the structural thread must not panic")
                .is_err(),
            "the unpersisted structural edit must roll back rather than return success"
        );
        rewrite
            .join()
            .expect("the lifecycle thread must not panic")
            .expect("the lifecycle rewrite must install once tier 1 releases");
        f.workspace.set_before_draft_write(None);
        f.inject_failure("DROP TRIGGER injected_structural_draft_update;");

        assert_eq!(*session.working_source().unwrap(), lifecycle_source);
        assert_eq!(
            session.note_state().unwrap().base_revision,
            content_hash(lifecycle_source.as_bytes()),
            "the session state does not match the lifecycle rewrite"
        );
    }

    #[test]
    fn range_edit_result_reports_phantom() {
        let f = fixture();
        let frontmatter = "---\ntype: Note\ntitle: A\nunmanaged: keep-this-byte-for-byte\n---";
        let original = format!("{frontmatter}\n\nOnly editable text.\n");
        f.write("a.md", &original);
        let session = f.open("a");

        let (state, caret) = session
            .delete_range(&RenderedRange::new(vec![0], 0, vec![0], 19))
            .unwrap();

        assert_eq!(caret, RangeEditLocation::Phantom { insertion_index: 0 });
        assert!(state.ast.is_empty(), "the deleted body left an AST node");
        let edited = session.working_source().unwrap();
        assert!(
            edited.starts_with(frontmatter),
            "deleting the entire body rewrote frontmatter bytes"
        );
        assert!(
            !edited.contains("Only editable text."),
            "the selected body survived deletion"
        );
        assert_eq!(
            f.draft("a").as_ref().map(|row| row.raw_markdown.as_str()),
            Some(edited.as_str()),
            "the one range operation did not persist its complete source as one draft"
        );
        assert_eq!(f.read("a.md"), original, "range edit wrote tier 2 eagerly");
    }

    #[test]
    fn range_replace_over_three_blocks_returns_the_reparsed_join_caret() {
        let f = fixture();
        f.write("a.md", &note("A", "One\n\nTwo\n\nThree"));
        let session = f.open("a");

        let (state, caret) = session
            .replace_range(&RenderedRange::new(vec![0], 0, vec![2], 5), "replacement")
            .unwrap();

        assert_eq!(state.ast.len(), 1, "three Blocks did not become one");
        assert_eq!(
            caret,
            RangeEditLocation::Block {
                block_path: vec![0],
                source_offset_utf16: "replacement".encode_utf16().count(),
            },
            "the caret was predicted from a former Block rather than returned from the new parse"
        );
        assert!(session.working_source().unwrap().ends_with("replacement\n"));
        assert_eq!(
            f.draft("a").unwrap().raw_markdown,
            *session.working_source().unwrap(),
            "the atomic edit and its draft disagree"
        );
    }

    #[test]
    fn range_replace_preserves_partial_remainders_and_pasted_multiline_text() {
        let f = fixture();
        f.write("a.md", &note("A", "Alpha\n\nBravo"));
        let session = f.open("a");

        let (_, caret) = session
            .replace_range(&RenderedRange::new(vec![0], 2, vec![1], 3), "X\nY")
            .unwrap();

        assert!(
            session.working_source().unwrap().ends_with("AlX\nYvo\n"),
            "the start/end remainders or pasted newline were reconstructed instead of spliced"
        );
        assert_eq!(
            caret,
            RangeEditLocation::Block {
                block_path: vec![0],
                source_offset_utf16: "AlX\nY".encode_utf16().count(),
            }
        );
    }

    #[test]
    fn range_replace_reparses_structural_markdown_before_returning_a_caret() {
        let f = fixture();
        f.write("a.md", &note("A", "Alpha\n\nBeta"));
        let session = f.open("a");

        let (state, caret) = session
            .replace_range(
                &RenderedRange::new(vec![0], 0, vec![0], 5),
                "- first\n- second",
            )
            .unwrap();

        assert!(matches!(state.ast[0], AstNode::List { .. }));
        match caret {
            RangeEditLocation::Block {
                block_path,
                source_offset_utf16,
            } => {
                assert_ne!(
                    block_path,
                    vec![0],
                    "a List container was returned as editable"
                );
                let source = session.block_source(&block_path).unwrap();
                assert_eq!(
                    source_offset_utf16,
                    source_caret_before_trailing_newline(&source)
                );
            }
            RangeEditLocation::Phantom { .. } => panic!("list replacement has editable leaves"),
        }
    }

    #[test]
    fn range_delete_is_the_same_operation_as_empty_replacement_and_rejects_reverse_ranges_atomically(
    ) {
        let deleted = fixture();
        let source = note("A", "Alpha\n\nBeta");
        deleted.write("a.md", &source);
        let delete_session = deleted.open("a");
        let range = RenderedRange::new(vec![0], 1, vec![1], 2);
        let delete_result = delete_session.delete_range(&range).unwrap();

        let replaced = fixture();
        replaced.write("a.md", &source);
        let replace_session = replaced.open("a");
        let replace_result = replace_session.replace_range(&range, "").unwrap();

        assert_eq!(delete_result.1, replace_result.1);
        assert_eq!(
            *delete_session.working_source().unwrap(),
            *replace_session.working_source().unwrap(),
            "delete_range diverged from its shared empty-replacement primitive"
        );

        let before = Arc::clone(&replace_session.working_source().unwrap());
        let bad = RenderedRange::new(vec![1], 1, vec![0], 1);
        assert!(replace_session.replace_range(&bad, "x").is_err());
        assert_eq!(
            *replace_session.working_source().unwrap(),
            *before,
            "a rejected reverse range changed the working source"
        );
    }

    /// A range is a coordinate into the AST that was current when the
    /// selection was made. A structural edit reparses that AST, so retaining
    /// the old endpoint paths must fail rather than splice whichever Blocks
    /// later happen to occupy those indices. The refusal is transactional:
    /// it cannot add a draft row, advance its sequence, or partly alter the
    /// frontmatter/source installed by the preceding structural edit.
    #[test]
    fn range_replace_rejects_a_stale_path_transactionally() {
        let f = fixture();
        let frontmatter = "---\ntype: Note\ntitle: A\nunmanaged: preserve-me\n---";
        let original = format!("{frontmatter}\n\nfirst\n\nsecond\n\nthird\n");
        f.write("a.md", &original);
        let session = f.open("a");

        // Captured while `second` and `third` occupied [1] and [2].
        let stale = RenderedRange::new(vec![1], 0, vec![2], 5);
        session.delete_block(&[1]).unwrap();

        let after_reparse = format!("{frontmatter}\n\nfirst\n\nthird\n");
        assert_eq!(
            *session.working_source().unwrap(),
            after_reparse,
            "the setup structural edit did not install its exact reparsed source"
        );
        let state_before_refusal = session.note_state().unwrap();
        let draft_before_refusal = f.draft("a").expect("the structural edit wrote no draft");
        let sequence_before_refusal = session.edit_seq();

        let refused = session.replace_range(&stale, "must not splice");
        assert!(
            matches!(refused, Err(AppError::ParseError(ref message)) if message.contains("no Block is addressed by block_path [2]")),
            "a stale endpoint must be a typed refusal, got {refused:?}"
        );

        assert_eq!(
            *session.working_source().unwrap(),
            after_reparse,
            "the refused stale range partly spliced the current source"
        );
        assert_eq!(
            session.note_state().unwrap(),
            state_before_refusal,
            "the refused stale range changed the reparsed Note state"
        );
        assert_eq!(
            session.edit_seq(),
            sequence_before_refusal,
            "the refused stale range advanced the edit sequence"
        );
        let draft_after_refusal = f.draft("a").expect("the existing draft disappeared");
        assert_eq!(
            draft_after_refusal.raw_markdown, draft_before_refusal.raw_markdown,
            "the refused stale range rewrote the draft source"
        );
        assert_eq!(
            draft_after_refusal.edit_seq, draft_before_refusal.edit_seq,
            "the refused stale range rewrote the draft sequence"
        );
        assert_eq!(
            f.read("a.md"),
            original,
            "a rejected range wrote the on-disk Note instead of only refusing"
        );
    }

    #[test]
    fn range_replace_returns_a_utf16_safe_emoji_caret() {
        let f = fixture();
        f.write("a.md", &note("A", "Alpha\n\nBeta"));
        let session = f.open("a");

        let (_, caret) = session
            .replace_range(&RenderedRange::new(vec![0], 1, vec![1], 2), "😀")
            .unwrap();

        assert_eq!(
            caret,
            RangeEditLocation::Block {
                block_path: vec![0],
                source_offset_utf16: "A😀".encode_utf16().count(),
            }
        );
    }

    /// The one mutator that writes no row, and the one that must not advance
    /// the sequence: an increment here would push the counter past the value
    /// stored in the row and suppress every legitimate tier 2 clear for the
    /// rest of the session.
    #[test]
    fn commit_block_writes_no_draft_row_and_does_not_advance_the_edit_sequence() {
        let f = fixture();
        f.write("a.md", &note("A", "First paragraph."));
        let session = f.open("a");
        session
            .update_block(&[0], "First paragraph, edited.\n")
            .unwrap();
        let sequence = session.edit_seq();
        session.flush().unwrap();
        assert!(f.draft("a").is_none(), "the successful write left the row");

        session.commit_block(&[0]).unwrap();

        assert_eq!(session.edit_seq(), sequence);
        assert!(f.draft("a").is_none(), "commit_block wrote a draft row");
    }

    // -- tier 2 --------------------------------------------------------------

    /// The baseline advances with each write, so the second is not compared
    /// against the state the first replaced. A baseline pinned to open time
    /// would turn `RevisionMismatch` from an external-change signal into a
    /// guaranteed second-write failure.
    #[test]
    fn two_idle_writes_in_one_session_both_succeed() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));
        let session = f.open("a");

        session.update_block(&[0], "First edit.\n").unwrap();
        let first = session.flush().unwrap();
        assert_eq!(f.read("a.md"), *session.working_source().unwrap());

        session.update_block(&[0], "Second edit.\n").unwrap();
        let second = session.flush().unwrap();

        assert_ne!(first, second, "the revision did not advance");
        assert_eq!(f.read("a.md"), *session.working_source().unwrap());
        assert_eq!(
            second,
            crate::index::content_hash(f.read("a.md").as_bytes())
        );
    }

    /// Only a change the Core did not make raises this, and when it does the
    /// file is left exactly as the other writer left it.
    #[test]
    fn an_external_modification_refuses_the_write_and_leaves_the_file_untouched() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));
        let session = f.open("a");
        session.update_block(&[0], "Mine.\n").unwrap();

        let external = note("A", "Written by something else.");
        f.write("a.md", &external);

        let result = session.flush();

        assert_eq!(
            result,
            Err(AppError::RevisionMismatch(crate::index::content_hash(
                external.as_bytes()
            ))),
            "the mismatch must carry the current revision"
        );
        assert_eq!(f.read("a.md"), external, "the file was overwritten");
        assert!(
            f.draft("a").is_some(),
            "a refused write must keep the draft row: it holds the only copy"
        );
        let status = session.write_status().unwrap();
        assert!(matches!(
            status.last_error,
            Some(AppError::RevisionMismatch(_))
        ));
        assert!(status.has_unwritten_edits);
    }

    /// The other half of `RevisionMismatch`, and the only exit from it.
    #[test]
    fn reloading_rebuilds_from_disk_and_the_next_write_succeeds() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));
        let session = f.open("a");
        session.update_block(&[0], "Mine.\n").unwrap();
        let external = note("A", "Written by something else.");
        f.write("a.md", &external);
        assert!(session.flush().is_err());

        let state = session.reload().unwrap();

        assert!(f.draft("a").is_none(), "the draft row survived a reload");
        assert!(!state.restored_from_draft);
        assert_eq!(*session.working_source().unwrap(), external);
        assert_eq!(
            state.base_revision,
            crate::index::content_hash(external.as_bytes())
        );
        // Without the reload this comparison fails on every tick, forever.
        session.update_block(&[0], "Mine, again.\n").unwrap();
        session.flush().unwrap();
        assert_eq!(f.read("a.md"), *session.working_source().unwrap());
    }

    /// A database failure *after* the bytes are on disk must not strand the OCC
    /// baseline behind the file.
    ///
    /// The regression this pins: `state.revision` was assigned after
    /// `clear_draft_through` and `index_written_source`, so an error in either
    /// aborted with the file already rewritten and the baseline still
    /// describing the previous bytes. The next tick compared a fresh disk hash
    /// against that stale baseline and raised `RevisionMismatch` — whose only
    /// exit is `reload`, which discards the buffer. A recoverable index error
    /// became a prompt that destroys the user's unwritten work.
    #[test]
    fn a_database_failure_after_the_write_still_records_the_new_baseline() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));
        let session = f.open("a");
        session.update_block(&[0], "Second.\n").unwrap();

        // Fails the draft clear that follows the atomic write. `write_draft`
        // upserts rather than deleting, so this fires for the clear alone.
        f.inject_failure(
            "CREATE TRIGGER injected_draft_clear BEFORE DELETE ON drafts \
             BEGIN SELECT RAISE(ABORT, 'injected index failure'); END;",
        );

        let refused = session.flush();

        assert!(
            refused.is_err(),
            "the injected failure must surface, got {refused:?}"
        );
        assert_eq!(
            f.read("a.md"),
            *session.working_source().unwrap(),
            "the bytes reached disk before the failure"
        );

        f.inject_failure("DROP TRIGGER injected_draft_clear;");
        session.update_block(&[0], "Third.\n").unwrap();

        let next = session.flush();

        assert!(
            !matches!(next, Err(AppError::RevisionMismatch(_))),
            "the next write must not raise RevisionMismatch against bytes this \
             session itself wrote, got {next:?}"
        );
        next.expect("the next write must succeed");
        assert_eq!(f.read("a.md"), *session.working_source().unwrap());
    }

    /// A Note whose bytes are not valid UTF-8 is refused rather than decoded
    /// lossily, on both paths that build a working source — and its bytes are
    /// left exactly as they were.
    ///
    /// The regression this pins: both paths used `from_utf8_lossy`, while the
    /// OCC revision hashes the raw bytes. Every invalid byte became U+FFFD in
    /// the buffer, so the first idle write after any edit rewrote the whole
    /// file with the replacement characters and re-recorded that mangled text
    /// as the baseline — destroying bytes the user never touched, in a file
    /// this application was asked to edit one Block of (`prd/constraints.md`
    /// Edit Fidelity, CAP-PORT-03).
    #[test]
    fn a_note_that_is_not_valid_utf8_is_refused_rather_than_decoded_lossily() {
        let f = fixture();
        // A conformant Note carrying one byte no UTF-8 sequence can contain.
        let mut bytes = note("A", "First.").into_bytes();
        bytes.extend_from_slice(b"latin-1 caf\xe9\n");
        std::fs::create_dir_all(f.root()).unwrap();
        std::fs::write(f.root().join("a.md"), &bytes).unwrap();

        let opened = open_note(&f.workspace, "a").map(|(_, state)| state);

        assert!(
            matches!(opened, Err(AppError::ParseError(_))),
            "opening a non-UTF-8 Note must error cleanly, got {opened:?}"
        );
        assert_eq!(
            std::fs::read(f.root().join("a.md")).unwrap(),
            bytes,
            "a refused open must leave the file's bytes untouched"
        );

        // The same on `reload`, which is the other path that turns disk bytes
        // into an editable working source. The session is opened while the file
        // is valid, then the invalid bytes arrive from outside.
        f.write("b.md", &note("B", "First."));
        let session = f.open("b");
        std::fs::write(f.root().join("b.md"), &bytes).unwrap();

        let reloaded = session.reload();

        assert!(
            matches!(reloaded, Err(AppError::ParseError(_))),
            "reloading non-UTF-8 bytes must error cleanly, got {reloaded:?}"
        );
        assert_eq!(
            std::fs::read(f.root().join("b.md")).unwrap(),
            bytes,
            "a refused reload must leave the file's bytes untouched"
        );
    }

    /// A file that goes invalid underneath a session must not make that
    /// session's unflushed work unreachable.
    ///
    /// The regression this pins: `open_note` decoded the disk bytes strictly
    /// *before* it looked for a draft row, so a foreign tool writing Latin-1
    /// over a Note — or a truncated sync — refused the one call that restores
    /// tier 1's work. The decode is an obligation of bytes that become the
    /// working source, and on this branch they do not: the draft's text is the
    /// working source and the raw bytes are only hashed for the OCC baseline.
    #[test]
    fn a_draft_is_restored_even_when_the_file_on_disk_went_invalid() {
        let f = fixture();
        let valid = note("A", "First.");
        f.write("a.md", &valid);

        let session = f.open("a");
        session.update_block(&[0], "Unflushed work.\n").unwrap();
        let unflushed = session.working_source().unwrap().to_string();
        // The registry entry, and nothing else, goes away: what a kill leaves
        // behind is the draft row on its own.
        session.forget();

        let mut bytes = valid.into_bytes();
        bytes.extend_from_slice(b"latin-1 caf\xe9\n");
        std::fs::write(f.root().join("a.md"), &bytes).unwrap();

        let (restored, state) = open_note(&f.workspace, "a")
            .expect("an unflushed draft must be reachable through a file gone invalid");

        assert!(
            state.restored_from_draft,
            "the open must report that it restored the draft"
        );
        assert_eq!(
            *restored.working_source().unwrap(),
            unflushed,
            "the restored buffer must be the draft, not the disk bytes"
        );
        // And with no draft to restore, the same file is still refused rather
        // than decoded lossily — see the test above, whose Note has no row.
    }

    /// Appending a Block at the end of a Note must produce a Block, whatever
    /// the source happened to end with.
    ///
    /// The regression this pins: the insert separator was appended to the new
    /// text only, which assumes the insertion point already sits on a
    /// blank-line boundary. At the end of an ordinary Note it does not — a Note
    /// ends in one `\n` — so `Para two.` and `New block` parsed as a single
    /// paragraph, the new text arriving as a lazy continuation line of the Block
    /// above it. Only a source that already ended in a blank line behaved, which
    /// is the least common of the three.
    #[test]
    fn appending_a_block_separates_it_whatever_the_source_ended_with() {
        for ending in [
            "Para one.\n\nPara two.\n",
            "Para one.\n\nPara two.",
            "Para one.\n\nPara two.\n\n",
        ] {
            let f = fixture();
            f.write("a.md", ending);
            let session = f.open("a");
            assert_eq!(session.note_state().unwrap().ast.len(), 2);

            // A path addressing nothing is the end-of-Note append.
            let state = session
                .insert_block(&[9], "New block.".to_string())
                .unwrap();

            assert_eq!(
                state.ast.len(),
                3,
                "{ending:?} did not gain a Block: {:?}",
                session.working_source().unwrap()
            );
            assert_eq!(
                session.block_source(&[1]).unwrap().trim_end(),
                "Para two.",
                "{ending:?} let the append run into the Block above it"
            );
            assert_eq!(
                session.block_source(&[2]).unwrap().trim_end(),
                "New block.",
                "{ending:?} did not produce the inserted Block"
            );
            // The Block structure above is the contract; this is the byte-level
            // half of it. An end-of-Note append has nothing after it to stay
            // separated from, so the full separator was padding the file with a
            // trailing blank line it never had — a change to bytes the user did
            // not edit, on every append, in a project whose Edit Fidelity
            // constraint is exactly that.
            assert!(
                session.working_source().unwrap().ends_with("New block.\n"),
                "{ending:?} left a trailing blank line: {:?}",
                session.working_source().unwrap()
            );
        }
    }

    /// A mid-Note insert lands before the Block it names and is separated from
    /// the one above it, including where that one is a list item whose own span
    /// ends in a single newline.
    #[test]
    fn a_mid_note_insert_is_separated_from_the_block_above_it() {
        let f = fixture();
        f.write("a.md", "Alpha\n\nBeta\n");
        let session = f.open("a");

        session.insert_block(&[1], "Middle.".to_string()).unwrap();

        assert_eq!(
            *session.working_source().unwrap(),
            "Alpha\n\nMiddle.\n\nBeta\n"
        );

        let g = fixture();
        g.write("b.md", "- a\n- b\n\nPara\n");
        let list = g.open("b");

        list.insert_block(&[0, 1], "Middle.".to_string()).unwrap();

        assert_eq!(
            *list.working_source().unwrap(),
            "- a\n\nMiddle.\n\n- b\n\nPara\n",
            "an insert inside a list ran into the item above it"
        );
    }

    /// Every seam a structural edit welds into a CRLF-authored Note is spelled
    /// `\r\n`, so the file stays byte-consistent with itself.
    ///
    /// The regression this pins: `separator_before` and `insert_block` measured
    /// the newline run CRLF-aware (`trailing_newlines` counts a pair as one) and
    /// then emitted `"\n"` unconditionally. A Windows-authored Note therefore
    /// gained a bare `\n` at every insert, split and delete — Blocks the user
    /// never touched showing up as whitespace changes in their diff, one more
    /// per edit, in a project whose Edit Fidelity constraint
    /// (`prd/constraints.md`) is exactly that.
    #[test]
    fn a_structural_edit_on_a_crlf_note_emits_crlf_seams() {
        let f = fixture();
        f.write("a.md", "Alpha\r\n\r\nBeta\r\n");
        let session = f.open("a");

        session.insert_block(&[1], "Middle.".to_string()).unwrap();

        let source = session.working_source().unwrap();
        assert_eq!(*source, "Alpha\r\n\r\nMiddle.\r\n\r\nBeta\r\n");
        assert!(
            !source.replace("\r\n", "").contains('\n'),
            "a bare LF was welded into a CRLF Note: {source:?}"
        );

        // The end-of-Note append is the other seam `insert_block` emits.
        session.insert_block(&[9], "Tail.".to_string()).unwrap();
        let source = session.working_source().unwrap();
        assert_eq!(*source, "Alpha\r\n\r\nMiddle.\r\n\r\nBeta\r\n\r\nTail.\r\n");

        // And the seam a split opens mid-Block.
        let g = fixture();
        g.write("b.md", "Alpha beta\r\n");
        let split = g.open("b");
        split.split_block(&[0], 5).unwrap();
        assert_eq!(*split.working_source().unwrap(), "Alpha\r\n\r\n beta\r\n");
    }

    /// The LF half of the same rule: a Note written with Unix line endings is
    /// unaffected, which is what makes the CRLF change a fidelity fix rather
    /// than a new convention.
    #[test]
    fn a_structural_edit_on_an_lf_note_still_emits_lf_seams() {
        let f = fixture();
        f.write("a.md", "Alpha\n\nBeta\n");
        let session = f.open("a");

        session.insert_block(&[1], "Middle.".to_string()).unwrap();
        session.insert_block(&[9], "Tail.".to_string()).unwrap();

        let source = session.working_source().unwrap();
        assert_eq!(*source, "Alpha\n\nMiddle.\n\nBeta\n\nTail.\n");
        assert!(!source.contains('\r'), "a CR appeared in an LF Note");
    }

    /// `split_block` accepts the Flutter raw field's **UTF-16** offset. The
    /// Core converts it at this boundary; spans and splice ranges remain bytes.
    #[test]
    fn splitting_a_multibyte_block_measures_the_offset_in_utf16_code_units() {
        let f = fixture();
        f.write("a.md", "Café x\n");
        let session = f.open("a");

        // `é` occupies one UTF-16 code unit, so offset 5 is immediately before
        // the `x`.
        session.split_block(&[0], 5).unwrap();

        let source = session.working_source().unwrap();
        assert_eq!(
            *source, "Café \n\nx\n",
            "the split landed at a byte offset rather than a character one"
        );
    }

    /// The end boundary is measured in UTF-16 code units, not Rust bytes.
    #[test]
    fn a_split_offset_past_the_last_utf16_code_unit_is_refused() {
        let f = fixture();
        f.write("a.md", "Café x\n");
        let session = f.open("a");

        session
            .split_block(&[0], 7)
            .expect("the end-of-Block caret is a valid split point");

        let g = fixture();
        g.write("b.md", "Café x\n");
        let refused = g.open("b").split_block(&[0], 8);
        assert!(
            matches!(refused, Err(AppError::ParseError(ref message))
                if message.contains("not a character boundary")),
            "an offset past the Block's last UTF-16 code unit must be refused, got {refused:?}"
        );
    }

    #[test]
    fn splitting_a_non_bmp_block_uses_utf16_and_rejects_a_surrogate_interior() {
        let f = fixture();
        f.write("a.md", "😀x\n");
        let session = f.open("a");

        // The emoji occupies two UTF-16 code units; 2 is the caret between the
        // emoji and x, while 1 is inside the emoji's surrogate pair.
        session.split_block(&[0], 2).unwrap();
        assert_eq!(*session.working_source().unwrap(), "😀\n\nx\n");

        let g = fixture();
        g.write("b.md", "😀x\n");
        let refused = g.open("b").split_block(&[0], 1);
        assert!(
            matches!(refused, Err(AppError::ParseError(ref message))
                if message.contains("not a character boundary")),
            "a split may not land inside a UTF-16 surrogate pair, got {refused:?}"
        );
    }

    /// ASCII behaviour is unchanged, since for a Block with no multibyte
    /// character the two units are the same number.
    #[test]
    fn splitting_an_ascii_block_is_unchanged_by_the_character_offset_rule() {
        let f = fixture();
        f.write("a.md", "Alpha beta\n");
        let session = f.open("a");

        session.split_block(&[0], 5).unwrap();

        assert_eq!(*session.working_source().unwrap(), "Alpha\n\n beta\n");
    }

    #[test]
    fn splitting_a_buffered_paragraph_promoted_to_a_list_uses_the_raw_field_coordinate() {
        let f = fixture();
        f.write("a.md", "plain\n");
        let session = f.open("a");

        let editor_source = "- alpha beta\n";
        session.update_block(&[0], editor_source).unwrap();
        let (state, focus, caret) = session
            .split_block_from_editor_source(&[0], editor_source, "- alpha".encode_utf16().count())
            .unwrap();

        assert_eq!(*session.working_source().unwrap(), "- alpha\n\n beta\n");
        assert_eq!(focus, vec![1]);
        assert_eq!(caret, 0);
        assert_eq!(session.block_source(&focus).unwrap(), "beta\n");
        assert!(matches!(
            state.ast.as_slice(),
            [AstNode::List { .. }, AstNode::Paragraph { .. }]
        ));
    }

    #[test]
    fn splitting_a_buffered_list_source_rejects_a_non_bmp_surrogate_without_mutating() {
        let f = fixture();
        f.write("a.md", "plain\n");
        let session = f.open("a");

        let editor_source = "- 😀beta\n";
        session.update_block(&[0], editor_source).unwrap();
        let before = session.working_source().unwrap();
        let refused = session.split_block_from_editor_source(&[0], editor_source, 3);

        assert!(
            matches!(refused, Err(AppError::ParseError(ref message)) if message.contains("not a character boundary"))
        );
        assert_eq!(*session.working_source().unwrap(), *before);
    }

    #[test]
    fn splitting_a_buffered_list_source_at_its_non_bmp_boundary_returns_the_second_leaf() {
        let f = fixture();
        f.write("a.md", "plain\n");
        let session = f.open("a");

        let editor_source = "- 😀beta\n";
        session.update_block(&[0], editor_source).unwrap();
        let (state, focus, caret) = session
            .split_block_from_editor_source(&[0], editor_source, 4)
            .unwrap();

        assert_eq!(*session.working_source().unwrap(), "- 😀\n\nbeta\n");
        assert_eq!(focus, vec![1]);
        assert_eq!(caret, 0);
        assert_eq!(session.block_source(&focus).unwrap(), "beta\n");
        assert!(matches!(
            state.ast.as_slice(),
            [AstNode::List { .. }, AstNode::Paragraph { .. }]
        ));
    }

    #[test]
    fn continuing_after_a_nested_list_leaf_preserves_the_list_and_returns_its_new_leaf() {
        let f = fixture();
        f.write("a.md", "- alpha\n- beta\n");
        let session = f.open("a");

        let (state, focus) = session.continue_block_after(&[0, 0, 0], "middle").unwrap();

        assert_eq!(
            *session.working_source().unwrap(),
            "- alpha\n- middle\n- beta\n"
        );
        assert_eq!(focus, vec![0, 1, 0]);
        assert_eq!(session.block_source(&focus).unwrap(), "middle");
        assert!(matches!(
            node_at_path(&state.ast, &focus),
            Some(AstNode::Paragraph { .. })
        ));
    }

    /// `update_block` deliberately does not reparse while a raw field is
    /// focused. Its retained paragraph path must therefore be resolved through
    /// the live source before Enter decides whether to continue a List.
    #[test]
    fn continuing_after_a_buffered_paragraph_to_list_change_uses_the_live_structure() {
        let f = fixture();
        f.write("a.md", "plain\n");
        let session = f.open("a");

        session.update_block(&[0], "- item\n").unwrap();
        let (state, focus) = session.continue_block_after(&[0], "next").unwrap();

        assert_eq!(*session.working_source().unwrap(), "- item\n- next\n");
        assert_eq!(focus, vec![0, 1, 0]);
        assert_eq!(session.block_source(&focus).unwrap(), "next");
        assert!(matches!(
            node_at_path(&state.ast, &focus),
            Some(AstNode::Paragraph { .. })
        ));
    }

    /// Backspace at the start of a ListItem removes its marker seam rather
    /// than treating that marker as invisible content that forbids a merge.
    #[test]
    fn merging_a_nested_list_item_preserves_its_container_and_returns_the_join() {
        let f = fixture();
        f.write("a.md", "- alpha\n- beta\n");
        let session = f.open("a");

        let (state, focus, caret_offset) = session.merge_block_with_previous(&[0, 1, 0]).unwrap();

        assert_eq!(*session.working_source().unwrap(), "- alphabeta\n");
        assert_eq!(focus, vec![0, 0, 0]);
        assert_eq!(caret_offset, "alpha".encode_utf16().count());
        assert_eq!(session.block_source(&focus).unwrap(), "alphabeta");
        assert!(matches!(state.ast.as_slice(), [AstNode::List { .. }]));
    }

    /// The marker of the first item is visible container syntax, not an
    /// unaddressable region. Backspace therefore crosses from a preceding
    /// top-level paragraph into a top-level List exactly as it crosses between
    /// ordinary adjacent Blocks.
    #[test]
    fn merging_the_first_top_level_list_item_crosses_the_container_boundary() {
        let f = fixture();
        f.write("a.md", "Alpha\n\n- beta\n");
        let session = f.open("a");

        let (state, focus, caret) = session.merge_block_with_previous(&[1, 0, 0]).unwrap();

        assert_eq!(*session.working_source().unwrap(), "Alpha\nbeta\n");
        assert_eq!(focus, vec![0]);
        assert_eq!(caret, "Alpha".encode_utf16().count());
        assert_eq!(session.block_source(&focus).unwrap(), "Alpha\nbeta\n");
        assert!(matches!(state.ast.as_slice(), [AstNode::Paragraph { .. }]));
    }

    /// Quotes carry the same visible prefix rule as Lists at a top-level
    /// boundary. Nested quote/list behavior remains on the list-sibling path
    /// above, so this covers only the cross-container seam.
    #[test]
    fn merging_the_first_top_level_blockquote_leaf_crosses_the_container_boundary() {
        let f = fixture();
        f.write("a.md", "Alpha\n\n> beta\n");
        let session = f.open("a");

        let (state, focus, caret) = session.merge_block_with_previous(&[1, 0]).unwrap();

        assert_eq!(*session.working_source().unwrap(), "Alpha\nbeta\n");
        assert_eq!(focus, vec![0]);
        assert_eq!(caret, "Alpha".encode_utf16().count());
        assert_eq!(session.block_source(&focus).unwrap(), "Alpha\nbeta\n");
        assert!(matches!(state.ast.as_slice(), [AstNode::Paragraph { .. }]));
    }

    #[test]
    fn continuing_a_list_inside_a_blockquote_repeats_the_full_container_prefix() {
        let f = fixture();
        f.write("a.md", "> - alpha\n> - beta\n");
        let session = f.open("a");

        let (state, focus) = session
            .continue_block_after(&[0, 0, 0, 0], "middle")
            .unwrap();

        assert_eq!(
            *session.working_source().unwrap(),
            "> - alpha\n> - middle\n> - beta\n"
        );
        assert_eq!(focus, vec![0, 0, 1, 0]);
        assert_eq!(session.block_source(&focus).unwrap(), "middle");
        assert!(matches!(state.ast.as_slice(), [AstNode::Blockquote { .. }]));
    }

    #[test]
    fn merging_a_list_inside_a_blockquote_preserves_the_quote_prefix_and_focus() {
        let f = fixture();
        f.write("a.md", "> - alpha\n> - beta\n");
        let session = f.open("a");

        let (state, focus, caret) = session.merge_block_with_previous(&[0, 0, 1, 0]).unwrap();

        assert_eq!(*session.working_source().unwrap(), "> - alphabeta\n");
        assert_eq!(focus, vec![0, 0, 0, 0]);
        assert_eq!(caret, "alpha".encode_utf16().count());
        assert_eq!(session.block_source(&focus).unwrap(), "alphabeta");
        assert!(matches!(state.ast.as_slice(), [AstNode::Blockquote { .. }]));
    }

    #[test]
    fn continuing_after_a_blockquote_leaf_exits_to_a_top_level_block_and_returns_its_leaf() {
        let f = fixture();
        f.write("a.md", "> alpha\n\nBeta\n");
        let session = f.open("a");

        let (state, focus) = session.continue_block_after(&[0, 0], "middle").unwrap();

        assert_eq!(
            *session.working_source().unwrap(),
            "> alpha\n\nmiddle\n\nBeta\n"
        );
        assert_eq!(focus, vec![1]);
        assert_eq!(session.block_source(&focus).unwrap(), "middle\n");
        assert!(matches!(
            node_at_path(&state.ast, &focus),
            Some(AstNode::Paragraph { .. })
        ));
    }

    #[test]
    fn continuing_after_a_top_level_leaf_inserts_after_that_leaf() {
        let f = fixture();
        f.write("a.md", "Alpha\n\nBeta\n");
        let session = f.open("a");

        let (state, focus) = session.continue_block_after(&[0], "middle").unwrap();

        assert_eq!(
            *session.working_source().unwrap(),
            "Alpha\n\nmiddle\n\nBeta\n"
        );
        assert_eq!(focus, vec![1]);
        assert_eq!(session.block_source(&focus).unwrap(), "middle\n");
        assert!(matches!(
            node_at_path(&state.ast, &focus),
            Some(AstNode::Paragraph { .. })
        ));
    }

    #[test]
    fn continuing_in_an_empty_note_uses_the_first_block_sentinel() {
        let f = fixture();
        f.write("a.md", "");
        let session = f.open("a");

        let (state, focus) = session.continue_block_after(&[0], "first").unwrap();

        assert_eq!(*session.working_source().unwrap(), "first\n");
        assert_eq!(focus, vec![0]);
        assert_eq!(session.block_source(&focus).unwrap(), "first\n");
        assert!(matches!(
            node_at_path(&state.ast, &focus),
            Some(AstNode::Paragraph { .. })
        ));
    }

    /// Deleting the last item of a list must not absorb the paragraph that
    /// follows the list into the item that survives.
    ///
    /// The regression this pins: `delete_block` removed
    /// `span.start..next_block_start`, and [`SpanMap::blocks`] is flat, so the
    /// "next" Block after the last list item is the paragraph *after the whole
    /// list*. The blank line in between closes the container and lives inside
    /// the last item's own span, so taking it turned `- a\n- b\n\nPara\n` into
    /// `- a\nPara\n` — one list item reading "a Para".
    #[test]
    fn deleting_the_last_item_of_a_list_leaves_the_next_paragraph_its_own_block() {
        let f = fixture();
        f.write("a.md", "- a\n- b\n\nPara\n");
        let session = f.open("a");

        session.delete_block(&[0, 1]).unwrap();

        assert_eq!(*session.working_source().unwrap(), "- a\n\nPara\n");
        let state = session.note_state().unwrap();
        assert_eq!(
            state.ast.len(),
            2,
            "the list and the paragraph are no longer two Blocks"
        );
        assert_eq!(session.block_source(&[1]).unwrap(), "Para\n");
    }

    /// The other half of the same rule: an ordinary paragraph delete still
    /// takes its separator with it, and a delete in the middle of a list still
    /// leaves the list contiguous.
    #[test]
    fn an_ordinary_delete_still_collapses_the_separator_that_followed_it() {
        let f = fixture();
        f.write("a.md", "Alpha\n\nBeta\n\nGamma\n");
        let session = f.open("a");

        session.delete_block(&[1]).unwrap();

        assert_eq!(*session.working_source().unwrap(), "Alpha\n\nGamma\n");
        assert_eq!(session.note_state().unwrap().ast.len(), 2);

        let g = fixture();
        g.write("b.md", "- a\n- b\n- c\n\nPara\n");
        let list = g.open("b");

        list.delete_block(&[0, 1]).unwrap();

        assert_eq!(*list.working_source().unwrap(), "- a\n- c\n\nPara\n");
        assert_eq!(list.note_state().unwrap().ast.len(), 2);

        // The first Block of a Note has no seam above it to keep open.
        let h = fixture();
        h.write("c.md", "Alpha\n\nBeta\n");
        let first = h.open("c");

        first.delete_block(&[0]).unwrap();

        assert_eq!(*first.working_source().unwrap(), "Beta\n");
    }

    /// Deleting the **last** Block takes the separator that preceded it, so the
    /// Note still ends in exactly one line ending.
    ///
    /// The disagreement this pins: `insert_block`'s end-of-Note append emits a
    /// single trailing newline, while a delete of the final Block consumed the
    /// separator *after* it — of which there is none — and left
    /// `A\n\nB\n\nC\n` as `A\n\nB\n\n`. Round-tripping the two therefore grew a
    /// blank line at the end of the file that no edit put there.
    #[test]
    fn deleting_the_final_block_leaves_the_note_ending_in_one_newline() {
        let f = fixture();
        f.write("a.md", "A\n\nB\n\nC\n");
        let session = f.open("a");

        session.delete_block(&[2]).unwrap();

        assert_eq!(*session.working_source().unwrap(), "A\n\nB\n");
        assert_eq!(session.note_state().unwrap().ast.len(), 2);

        // A CRLF Note keeps its own line endings through the same cut.
        let g = fixture();
        g.write("b.md", "A\r\n\r\nB\r\n");
        let crlf = g.open("b");

        crlf.delete_block(&[1]).unwrap();

        assert_eq!(*crlf.working_source().unwrap(), "A\r\n");

        // And the container case from the other side: the blank line that closes
        // the list is the deleted paragraph's preceding separator.
        let h = fixture();
        h.write("c.md", "- a\n- b\n\nPara\n");
        let list = h.open("c");

        list.delete_block(&[1]).unwrap();

        assert_eq!(*list.working_source().unwrap(), "- a\n- b\n");

        // Deleting the only Block of a Note empties it rather than leaving a
        // stray newline behind.
        let i = fixture();
        i.write("d.md", "Only.\n");
        let only = i.open("d");

        only.delete_block(&[0]).unwrap();

        assert_eq!(*only.working_source().unwrap(), "");
    }

    /// A delete must not take the bytes between it and the next registered
    /// Block, because that gap is exactly where `markdown::parser`'s
    /// preserved-but-unaddressable regions live.
    ///
    /// The regression this pins: `delete_block` removed
    /// `span.start..next_block_start`, and a raw HTML block, a link reference
    /// definition and inline HTML produce no `AstNode` and therefore no span —
    /// so deleting the paragraph *before* one of them deleted the region too.
    /// `parser`'s module documentation states the opposite as a guarantee ("no
    /// edit can corrupt them and they survive every save byte-identically"),
    /// and `prd/constraints.md`'s Edit Fidelity is what that guarantee serves.
    #[test]
    fn deleting_a_block_leaves_the_unaddressable_region_after_it_byte_identical() {
        // A raw HTML block between two paragraphs: deleting the first must
        // leave the HTML exactly as authored.
        let f = fixture();
        f.write("a.md", "Alpha\n\n<div>\n  raw\n</div>\n\nBeta\n");
        let session = f.open("a");

        session.delete_block(&[0]).unwrap();

        assert_eq!(
            *session.working_source().unwrap(),
            "<div>\n  raw\n</div>\n\nBeta\n"
        );

        // A link reference definition, which `pulldown-cmark` consumes without
        // emitting any event at all — the region with no span of any kind.
        let g = fixture();
        g.write("b.md", "Alpha\n\n[ref]: /target.md\n\nBeta\n");
        let refs = g.open("b");

        refs.delete_block(&[0]).unwrap();

        assert_eq!(
            *refs.working_source().unwrap(),
            "[ref]: /target.md\n\nBeta\n"
        );

        // And the same in the middle of a Note, where the delete does have a
        // seam on both sides to normalize.
        let h = fixture();
        h.write("c.md", "Alpha\n\nBeta\n\n<div>raw</div>\n\nGamma\n");
        let middle = h.open("c");

        middle.delete_block(&[1]).unwrap();

        assert_eq!(
            *middle.working_source().unwrap(),
            "Alpha\n\n<div>raw</div>\n\nGamma\n"
        );
    }

    /// The same rule read from the other side: a merge whose gap holds
    /// unaddressable content is refused rather than silently absorbing it.
    #[test]
    fn merging_across_an_unaddressable_region_is_refused_and_names_it() {
        let f = fixture();
        f.write("a.md", "Alpha\n\n<div>raw</div>\n\nBeta\n");
        let session = f.open("a");

        let refused = session.merge_block_with_previous(&[1]);

        assert!(
            matches!(refused, Err(AppError::ParseError(ref message))
                if message.contains("<div>raw</div>")),
            "a merge that would delete an invisible region must be refused and \
             name what it would have deleted, got {refused:?}"
        );
        assert_eq!(
            *session.working_source().unwrap(),
            "Alpha\n\n<div>raw</div>\n\nBeta\n",
            "the refused merge must have changed nothing"
        );

        // A link reference definition is the same case.
        let g = fixture();
        g.write("b.md", "Alpha\n\n[ref]: /target.md\n\nBeta\n");
        let refs = g.open("b");

        assert!(matches!(
            refs.merge_block_with_previous(&[1]),
            Err(AppError::ParseError(_))
        ));
    }

    /// The ordinary merge — a gap that is nothing but the blank line between
    /// two adjacent Blocks — is unchanged by the refusal above.
    #[test]
    fn an_ordinary_merge_still_joins_two_adjacent_blocks() {
        let f = fixture();
        f.write("a.md", "Alpha\n\nBeta\n");
        let session = f.open("a");

        session.merge_block_with_previous(&[1]).unwrap();

        assert_eq!(*session.working_source().unwrap(), "Alpha\nBeta\n");

        // Merging the first Block is still a no-op with no predecessor to
        // refuse against.
        let g = fixture();
        g.write("b.md", "Alpha\n\nBeta\n");
        let first = g.open("b");

        first.merge_block_with_previous(&[0]).unwrap();

        assert_eq!(*first.working_source().unwrap(), "Alpha\n\nBeta\n");
    }

    /// `architecture/resilience.md`: an abrupt termination mid-write leaves the
    /// previous state intact. The write goes to a uniquely named temporary file
    /// in the target's own directory and arrives by rename.
    #[test]
    fn a_write_leaves_no_temporary_file_behind_and_the_file_is_never_partial() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));
        let session = f.open("a");
        session.update_block(&[0], "Edited.\n").unwrap();
        session.flush().unwrap();

        let leftovers: Vec<String> = std::fs::read_dir(f.root())
            .unwrap()
            .filter_map(Result::ok)
            .map(|entry| entry.file_name().to_string_lossy().into_owned())
            .filter(|name| name.ends_with(".tmp"))
            .collect();
        assert!(
            leftovers.is_empty(),
            "temporary files left behind: {leftovers:?}"
        );
        assert_eq!(f.read("a.md"), *session.working_source().unwrap());
    }

    /// `hard_link` has already published the final path when scratch cleanup
    /// runs. A cleanup failure is therefore a recoverable leftover, never a
    /// failed create result that would make lifecycle code compensate for a
    /// Note that is already visible.
    #[test]
    fn atomic_create_reports_publication_success_when_post_publish_cleanup_fails() {
        let directory = tempfile::tempdir().unwrap();
        let destination = directory.path().join("published.md");
        let leftover = Arc::new(Mutex::new(None));
        let recorded_leftover = Arc::clone(&leftover);

        let published = atomic_create_with_cleanup(&destination, b"published bytes", move |temp| {
            *recorded_leftover.lock().unwrap() = Some(temp.to_path_buf());
            Err(std::io::Error::new(
                std::io::ErrorKind::PermissionDenied,
                "injected cleanup failure",
            ))
        });

        assert_eq!(published, Ok(true));
        assert_eq!(std::fs::read(&destination).unwrap(), b"published bytes");
        let temp = leftover
            .lock()
            .unwrap()
            .clone()
            .expect("the injected cleanup must receive the scratch path");
        assert!(
            temp.exists(),
            "the failed cleanup unexpectedly removed the scratch file"
        );
        std::fs::remove_file(temp).unwrap();
    }

    /// A successful write clears the row, so a row present means work not yet
    /// on disk rather than merely work that happened — and brings the index
    /// level with the bytes just written.
    #[test]
    fn a_successful_write_clears_the_draft_row_and_indexes_the_note() {
        let f = fixture();
        f.write("a.md", &note("A", "Antidisestablishmentarianism."));
        let session = f.open("a");
        session
            .update_block(&[0], "Supercalifragilistic.\n")
            .unwrap();
        assert!(f.draft("a").is_some());

        session.flush().unwrap();

        assert!(f.draft("a").is_none());
        let indexed: i64 = f
            .workspace
            .with_db(|conn| {
                conn.query_row(
                    "SELECT count(*) FROM notes_fts WHERE notes_fts MATCH 'Supercalifragilistic'",
                    [],
                    |row| row.get(0),
                )
                .map_err(AppError::from)
            })
            .unwrap();
        assert_eq!(indexed, 1, "the index does not track what was written");
    }

    /// `SPK-WSPC-D001` §6.2.6's interleaving, without the thread: the timer's
    /// clear runs with the sequence it snapshotted, and a keystroke's later row
    /// has landed in the meantime. That row must survive.
    #[test]
    fn the_timers_draft_clear_only_removes_rows_the_write_covered() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));
        let session = f.open("a");

        session.update_block(&[0], "Keystroke one.\n").unwrap();
        let snapshot_seq = session.edit_seq();
        // The keystroke the timer raced writes its row while the timer is
        // between its file write and its clear.
        session.update_block(&[0], "Keystroke two.\n").unwrap();
        assert!(session.edit_seq() > snapshot_seq);

        session.clear_draft_through(snapshot_seq).unwrap();

        let row = f
            .draft("a")
            .expect("the later keystroke's row was cleared by a stale snapshot");
        assert_eq!(row.edit_seq, session.edit_seq());
        assert_eq!(row.raw_markdown, *session.working_source().unwrap());

        // And the `<=` half: a row lagging the snapshot is redundant once the
        // newer bytes are on disk, so it goes.
        session.clear_draft_through(session.edit_seq() + 5).unwrap();
        assert!(f.draft("a").is_none());
    }

    // -- tier 1 recovery -----------------------------------------------------

    /// A kill before the write tier fires leaves the row, and the next open
    /// parses **the draft** rather than disk — a draft row exists precisely
    /// when its content differs from disk, so parsing disk would return an AST
    /// of the wrong document.
    #[test]
    fn a_surviving_draft_row_is_restored_on_open_and_reported_as_such() {
        let f = fixture();
        let on_disk = note("A", "First.");
        f.write("a.md", &on_disk);
        let session = f.open("a");
        session.split_block(&[0], 3).unwrap();
        let drafted = session.working_source().unwrap().to_string();
        // The process dies here: no close, no flush.
        session.forget();

        let (session, state) = open_note(&f.workspace, "a").unwrap();

        assert!(state.restored_from_draft);
        assert_eq!(*session.working_source().unwrap(), drafted);
        assert_ne!(drafted, on_disk);
        assert_eq!(f.read("a.md"), on_disk, "disk must be untouched");
        // The recovered work is written and committed by the close that
        // follows, exactly as if the edits had been made in this session.
        session.close().unwrap();
        assert_eq!(f.read("a.md"), drafted);
    }

    #[test]
    fn pending_drafts_reports_notes_with_unflushed_work() {
        let f = fixture();
        f.write("a.md", &note("Alpha", "First."));
        f.write("b.md", &note("Beta", "First."));
        f.reindex();
        let session = f.open("a");
        session.update_block(&[0], "Unflushed.\n").unwrap();

        let pending = pending_drafts(&f.workspace).unwrap();

        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].id, "a");
        assert_eq!(pending[0].title, "Alpha");
        assert!(pending[0].okf_conformant);
    }

    /// A draft row whose Note has been deleted from disk and cleared from
    /// `notes` by the next full rebuild is still reported.
    ///
    /// This is `close`'s own promise for the one case it calls the harshest:
    /// something outside this application deleted the file, so the session is
    /// retired without a commit and **the draft row is left in place**, because
    /// the row is now the only copy of the user's unwritten work. The inner
    /// join this query used made that row invisible to the only call that
    /// reports it — silently, and permanently from the next open onward, since
    /// `index::scan`'s rebuild is what removes the `notes` partner.
    #[test]
    fn a_draft_orphaned_by_a_rebuild_is_still_reported() {
        let f = fixture();
        f.write("a.md", &note("Alpha", "First."));
        f.write("b.md", &note("Beta", "First."));
        f.reindex();
        let session = f.open("a");
        session.update_block(&[0], "Unflushed.\n").unwrap();

        // Something outside the application deletes the file. `close` retires
        // the session without a commit and keeps the draft row.
        std::fs::remove_file(f.root().join("a.md")).unwrap();
        session.close().unwrap();
        assert!(
            f.draft("a").is_some(),
            "the draft row is the only copy left"
        );

        // The next open rebuilds the index, which drops the orphaned `notes`
        // row the draft used to join against.
        f.reindex();

        let pending = pending_drafts(&f.workspace).unwrap();

        assert_eq!(
            pending.iter().map(|m| m.id.as_str()).collect::<Vec<_>>(),
            vec!["a"],
            "a draft that outlived its Note must still be reported"
        );
        assert_eq!(pending[0].path, "a.md");
        assert_eq!(
            pending[0].title, "a",
            "the id's stem, no indexed title left"
        );
        assert!(
            !pending[0].okf_conformant,
            "nothing parsed these bytes, so conformance is not asserted"
        );
        assert!(pending[0].last_modified > 0, "the draft's own updated_at");
    }

    /// Drafts that share an `updated_at` come back in a stable order.
    ///
    /// `updated_at` is second-granularity, so a user who left several Notes
    /// unflushed in the same second — or an application killed while several
    /// sessions were open, which is the case this call exists for — has ties,
    /// and `ORDER BY d.updated_at DESC` alone leaves the remainder to SQLite's
    /// unspecified row order. That is a recovery list that reshuffles itself
    /// between two consecutive calls that saw no writes. `, d.note_id` is the
    /// same tie-break every other list-returning query in this crate carries,
    /// for the same reason.
    ///
    /// A guard rather than a reproduction: without the tie-break this passes
    /// anyway, because the current plan walks the `(workspace_id, note_id)`
    /// primary key and hands the sorter rows already in id order. That is
    /// exactly the accident being pinned — what this fails on is a future plan
    /// change (an added index, different statistics) that quietly reorders a
    /// list of the user's unflushed work.
    #[test]
    fn drafts_sharing_an_updated_at_are_ordered_deterministically() {
        let f = fixture();
        // Written and drafted in reverse order, so insertion order is the
        // opposite of the order asserted below and cannot pass by accident.
        for id in ["c", "b", "a"] {
            f.write(&format!("{id}.md"), &note(id, "First."));
        }
        f.reindex();
        let _sessions: Vec<NoteSession> = ["c", "b", "a"]
            .iter()
            .map(|id| {
                let session = f.open(id);
                session.update_block(&[0], "Unflushed.\n").unwrap();
                session
            })
            .collect();

        // Force the tie the clock only sometimes produces.
        f.workspace
            .with_db(|conn| {
                conn.execute("UPDATE drafts SET updated_at = 1700000000", [])
                    .map_err(AppError::from)
            })
            .unwrap();

        let ids: Vec<String> = pending_drafts(&f.workspace)
            .unwrap()
            .into_iter()
            .map(|m| m.id)
            .collect();

        assert_eq!(
            ids,
            vec!["a".to_string(), "b".to_string(), "c".to_string()],
            "tied drafts must fall back to the note id, not to row order"
        );
    }

    // -- tier 3 --------------------------------------------------------------

    /// Reading a Note and navigating away is the most common path through this
    /// tier. An empty commit per Note visited would destroy the readable
    /// history this design exists to produce.
    #[test]
    fn a_note_opened_and_closed_with_no_edits_makes_no_commit() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));
        f.commit_baseline();
        let before = f.commit_subjects();

        let session = f.open("a");
        session.commit_block(&[0]).unwrap();
        session.close().unwrap();

        assert_eq!(f.commit_subjects(), before, "a commit was made for a read");
    }

    /// One commit per Note per session, covering that Note only — a
    /// whole-worktree commit would sweep both and break the guarantee that is
    /// this design's entire justification.
    #[test]
    fn closing_one_of_two_dirty_notes_commits_that_note_only() {
        let f = fixture();
        f.write("a.md", &note("Alpha", "First."));
        f.write("b.md", &note("Beta", "First."));
        f.commit_baseline();

        let alpha = f.open("a");
        let beta = f.open("b");
        alpha.update_block(&[0], "Alpha edited.\n").unwrap();
        beta.update_block(&[0], "Beta edited.\n").unwrap();
        alpha.flush().unwrap();
        beta.flush().unwrap();

        alpha.close().unwrap();

        let changed = f.git(&["show", "--name-only", "--format=", "HEAD"]);
        assert_eq!(
            changed, "a.md",
            "the commit swept more than the closed Note"
        );
        let committed_beta = f.git(&["show", "HEAD:b.md"]);
        assert!(
            committed_beta.contains("First."),
            "b.md's edit was swept into a's commit: {committed_beta}"
        );
        assert_eq!(f.commit_subjects().len(), 2);
        assert!(f.commit_subjects()[0].contains("Alpha"));
    }

    /// This commit is the whole of CAP-WS-02, and its identity is fixed by
    /// ADR-008 rather than read from the user or from Git configuration.
    #[test]
    fn the_commit_author_is_the_fixed_application_identity() {
        let f = fixture();
        f.write("a.md", &note("Alpha", "First."));
        f.commit_baseline();
        // A repository-local identity, which `git commit` would have used and
        // which this path must ignore.
        f.git(&["config", "user.name", "Someone Else"]);
        f.git(&["config", "user.email", "else@example.com"]);

        let session = f.open("a");
        session.update_block(&[0], "Alpha edited.\n").unwrap();
        session.close().unwrap();

        assert_eq!(
            f.git(&["log", "-1", "--format=%an <%ae>"]),
            "burlmd <noreply@burlmd.invalid>"
        );
        assert_eq!(
            f.git(&["log", "-1", "--format=%cn <%ce>"]),
            "burlmd <noreply@burlmd.invalid>"
        );
    }

    /// Tier 3 end to end: the pending write is flushed, exactly one commit
    /// covers the session, the draft row is cleared, and the sync scheduler is
    /// notified — `notify_activity()`'s first caller since Epic C.
    #[test]
    fn closing_a_note_flushes_commits_once_clears_the_draft_and_notifies_sync() {
        use crate::sync::scheduler::{SyncConfig, SyncDeps, SyncScheduler};

        let f = fixture();
        f.write("a.md", &note("Alpha", "First."));
        f.commit_baseline();

        let pushes = Arc::new(AtomicUsize::new(0));
        let pushes_in_thread = Arc::clone(&pushes);
        let mut config = SyncConfig::new(f.root(), "origin", "main");
        config.debounce = Duration::from_millis(20);
        config.poll_interval = Duration::from_secs(3600);
        let scheduler = Arc::new(SyncScheduler::start(
            config,
            SyncDeps {
                push: Box::new(move |_, _, _, _| {
                    pushes_in_thread.fetch_add(1, Ordering::SeqCst);
                    Ok(())
                }),
                ..SyncDeps::default()
            },
        ));
        set_sync_scheduler(Some(Arc::clone(&scheduler)));

        let session = f.open("a");
        session.update_block(&[0], "Alpha edited.\n").unwrap();
        session.close().unwrap();

        assert_eq!(
            f.read("a.md"),
            "---\ntype: Note\ntitle: Alpha\n---\n\nAlpha edited.\n"
        );
        assert!(f.draft("a").is_none(), "the draft row survived the close");
        assert_eq!(
            f.commit_subjects().len(),
            2,
            "expected exactly one new commit"
        );
        let notified = wait_until(Duration::from_secs(3), || pushes.load(Ordering::SeqCst) > 0);
        set_sync_scheduler(None);
        scheduler.stop();
        assert!(notified, "the sync scheduler was never notified");
    }

    /// A Note whose file this session created rather than changed says so.
    #[test]
    fn the_generated_commit_message_names_the_note_and_the_nature_of_the_change() {
        let f = fixture();
        f.write("a.md", &note("Alpha", "First."));
        let session = f.open("a");
        session.update_block(&[0], "Alpha edited.\n").unwrap();
        session.close().unwrap();
        assert_eq!(f.commit_subjects(), vec!["Create Alpha".to_string()]);

        f.write("b.md", &note("Beta", "First."));
        f.commit_baseline();
        let beta = f.open("b");
        beta.update_block(&[0], "Beta edited.\n").unwrap();
        beta.close().unwrap();
        assert_eq!(f.commit_subjects()[0], "Update Beta");
    }

    /// A close whose flush fails changes nothing: no commit of bytes this
    /// application did not write, and above all no cleared draft row.
    #[test]
    fn a_close_whose_flush_is_refused_commits_nothing_and_keeps_the_draft() {
        let f = fixture();
        f.write("a.md", &note("Alpha", "First."));
        f.commit_baseline();
        let session = f.open("a");
        session.update_block(&[0], "Mine.\n").unwrap();
        f.write("a.md", &note("Alpha", "Written by something else."));

        let result = session.close();

        assert!(
            matches!(result, Err(AppError::RevisionMismatch(_))),
            "{result:?}"
        );
        assert_eq!(f.commit_subjects().len(), 1);
        assert!(f.draft("a").is_some(), "the draft row was cleared anyway");
    }

    /// A close whose **commit** fails is the opposite case, and used to be
    /// treated identically.
    ///
    /// By then the flush has succeeded: the bytes are on disk and the rows are
    /// in the index. Propagating with `?` returned before the session was
    /// deregistered and before `closed` was set, so the Note stayed in the
    /// registry with its idle timer armed — unclosable, un-navigable-away-from,
    /// and every retry taking the same exit, over a Git-level failure that had
    /// nothing to do with the user's work. All four of tier 3's siblings in
    /// `workspace::lifecycle` already reconciled first and reported second
    /// through `commit_stage_failure`; this is the same treatment.
    #[test]
    fn a_close_whose_commit_fails_still_closes_the_note_and_says_so() {
        let f = fixture();
        f.write("a.md", &note("Alpha", "First."));
        f.commit_baseline();
        let session = f.open("a");
        session.update_block(&[0], "Alpha edited.\n").unwrap();
        // The commit stage, and only the commit stage: tier 2's atomic write
        // and the index both work perfectly well without a repository.
        std::fs::remove_dir_all(f.root().join(".git")).unwrap();

        let result = session.close();

        let message = match &result {
            Err(error) => format!("{error:?}"),
            Ok(()) => panic!("the commit failure must still be reported"),
        };
        assert!(
            message.contains("the commit recording it in version history failed"),
            "the error must name the stage that failed, and say the Note itself is \
             written: {message}"
        );
        assert!(
            message.contains("closing a"),
            "the error must name what was being closed: {message}"
        );

        assert_eq!(
            f.read("a.md"),
            "---\ntype: Note\ntitle: Alpha\n---\n\nAlpha edited.\n",
            "the flush had already succeeded; the Note's bytes must be on disk"
        );
        assert!(
            lookup(f.workspace.id(), "a").unwrap().is_none(),
            "the session is still registered, so the Note can never be closed"
        );
        assert!(f.draft("a").is_none(), "the draft row survived the close");

        // And the Note is usable again rather than trapped.
        let (reopened, state) = open_note(&f.workspace, "a").unwrap();
        assert!(!state.restored_from_draft);
        reopened.close().unwrap();
    }

    /// The same trap, one stage earlier: a close whose **draft-row clear**
    /// fails.
    ///
    /// It used to propagate with `?` from between the commit and the
    /// deregistration, so the bytes were on disk, the commit had already been
    /// made, and the session was *still* stranded in the registry with `closed`
    /// unset and its timer armed — over a `drafts`-table failure that costs the
    /// user nothing at all. The clear is bound to the sequence the flush
    /// covered, so the row it fails to remove holds bytes identical to the file.
    #[test]
    fn a_close_whose_draft_clear_fails_still_closes_the_note_and_says_so() {
        let f = fixture();
        f.write("a.md", &note("Alpha", "First."));
        f.commit_baseline();
        let session = f.open("a");
        session.update_block(&[0], "Alpha edited.\n").unwrap();

        // Only the close's own clear, and not the flush's. The two issue the
        // identical statement one after the other inside `close`, so no trigger
        // can tell them apart — the first deletes the row and the second finds
        // nothing left to fire on. An authorizer runs at *prepare* time, before
        // any row is consulted, which is what makes "the second DELETE on
        // `drafts` fails" expressible at all. It is a faithful stand-in for what
        // production hits here: a full disk, a locked database, a page that will
        // not read.
        f.deny_drafts_delete_after(1);

        let result = session.close();

        let message = match &result {
            Err(error) => format!("{error:?}"),
            Ok(()) => panic!("the draft-clear failure must still be reported"),
        };
        assert!(
            message.contains("clearing the draft row"),
            "the error must name the stage that failed: {message}"
        );
        assert!(
            message.contains("the Note is closed and its work is safe"),
            "the error must say the user's work survived: {message}"
        );
        assert!(
            message.contains("closing a"),
            "the error must name what was being closed: {message}"
        );

        // Everything the close is for happened anyway.
        assert_eq!(
            f.read("a.md"),
            "---\ntype: Note\ntitle: Alpha\n---\n\nAlpha edited.\n",
            "the flush had already succeeded; the Note's bytes must be on disk"
        );
        assert_eq!(
            f.commit_subjects(),
            vec!["Update Alpha".to_string(), "baseline".to_string()],
            "the commit stage ran before this one and must not be undone by it"
        );
        assert!(
            lookup(f.workspace.id(), "a").unwrap().is_none(),
            "the session is still registered, so the Note can never be closed"
        );

        // And the Note is usable again rather than trapped. (The flush's own
        // clear had already emptied the row, so there is nothing to recover
        // from — which is the point: the failing stage was redundant work.)
        f.allow_drafts_delete();
        let (reopened, _) = open_note(&f.workspace, "a").unwrap();
        reopened.close().unwrap();
    }

    // -- the idle timer ------------------------------------------------------

    /// Tier 2's routine trigger is a Core-owned timer, and tier 3 is not on a
    /// timer at all — ADR-008 rejected timer-based commits explicitly, and this
    /// ticket carries a STOP for it.
    #[test]
    fn the_idle_timer_writes_the_file_and_never_commits() {
        let f = fixture_with_idle(Duration::from_millis(40));
        f.write("a.md", &note("Alpha", "First."));
        f.commit_baseline();
        let session = f.open("a");

        session
            .update_block(&[0], "Written by the timer.\n")
            .unwrap();

        let written = wait_until(Duration::from_secs(3), || {
            f.read("a.md").contains("Written by the timer.")
        });
        assert!(written, "the idle timer never wrote the file");
        assert!(
            wait_until(Duration::from_millis(300), || f.draft("a").is_none()),
            "the timer's write did not clear the draft row"
        );
        assert_eq!(
            f.commit_subjects().len(),
            1,
            "a commit was made on a timer rather than on close"
        );
    }

    /// The lock discipline, exercised rather than argued: keystrokes on this
    /// thread while the timer fires repeatedly on its own must not deadlock,
    /// and the file must end up holding exactly the buffer.
    #[test]
    fn keystrokes_and_the_idle_timer_agree_on_the_final_bytes() {
        let f = fixture_with_idle(Duration::from_millis(5));
        f.write("a.md", &note("Alpha", "First."));
        let session = f.open("a");

        for iteration in 0..60u32 {
            session
                .update_block(&[0], &format!("Keystroke {iteration}.\n"))
                .unwrap();
            std::thread::sleep(Duration::from_millis(1));
        }
        session.flush().unwrap();

        assert_eq!(f.read("a.md"), *session.working_source().unwrap());
        assert!(f.read("a.md").contains("Keystroke 59."));
    }

    // -- reload and conflict markers ----------------------------------------

    /// Reload is the only call that reads bytes this application did not write
    /// into a Note that is already open, so it is where the Sync Manager's
    /// conflict markers become `Suggestion` nodes rather than literal text.
    #[test]
    fn a_reload_of_a_conflicted_file_yields_suggestion_nodes() {
        let f = fixture();
        f.write("a.md", &note("Alpha", "First."));
        let session = f.open("a");
        f.write(
            "a.md",
            "---\ntype: Note\ntitle: Alpha\n---\n\nBefore.\n\n\
             <<<<<<< HEAD\nMine.\n=======\nTheirs.\n>>>>>>> origin/main\n\nAfter.\n",
        );

        let state = session.reload().unwrap();

        let suggestions: Vec<&AstNode> = state
            .ast
            .iter()
            .filter(|node| matches!(node, AstNode::Suggestion { .. }))
            .collect();
        assert_eq!(suggestions.len(), 1, "ast: {:?}", state.ast);
        let AstNode::Suggestion {
            base_content,
            local_content,
            incoming_content,
        } = suggestions[0]
        else {
            unreachable!("filtered above")
        };
        // `git merge`'s default style emits no base section; only a `diff3`
        // merge populates this.
        assert!(base_content.is_none());
        assert_eq!(crate::markdown::rendered_text(&local_content[0]), "Mine.");
        assert_eq!(
            crate::markdown::rendered_text(&incoming_content[0]),
            "Theirs."
        );
        assert!(
            !format!("{:?}", state.ast).contains("<<<<<<<"),
            "the markers survived as literal text"
        );
    }

    // -- review findings -----------------------------------------------------

    /// `SPK-WSPC-D001` §6.2.7's first standing rule: no closure passed to the
    /// connection may perform file I/O. The process-wide connection is what a
    /// keystroke's own tier 1 write waits on, so anything slow inside a closure
    /// is latency charged to typing — and the obvious `index_note` call on the
    /// tier 2 path did exactly that, reading, stat-ing and parsing the file it
    /// had just been handed the bytes of.
    ///
    /// The rule is now enforced at runtime in debug builds, which is what this
    /// asserts: the guard fires rather than merely being documented.
    #[test]
    #[should_panic(expected = "ran inside a connection closure")]
    fn file_io_inside_a_connection_closure_is_a_hard_error() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));

        let _ = f.workspace.with_db(|_conn| {
            atomic_write(&f.root().join("a.md"), b"written under the connection\n")
        });
    }

    /// The same rule, from the other side: the tier 2 write path itself must
    /// never reach the filesystem while holding the connection. This is the
    /// regression the guard above exists to catch, exercised through the real
    /// call rather than a synthetic one.
    #[test]
    fn a_tier_2_write_never_touches_the_filesystem_under_the_connection() {
        let f = fixture();
        f.write("a.md", &note("A", "Antidisestablishmentarianism."));
        let session = f.open("a");
        session
            .update_block(&[0], "Supercalifragilistic.\n")
            .unwrap();

        // Panics through the debug guard if any of the write, the draft clear
        // or the reindex reaches a file with the connection held.
        session.flush().unwrap();

        // And the index really was brought level, so the cheap path is not
        // cheap by having skipped the work.
        let indexed: i64 = f
            .workspace
            .with_db(|conn| {
                conn.query_row(
                    "SELECT count(*) FROM notes_fts WHERE notes_fts MATCH 'Supercalifragilistic'",
                    [],
                    |row| row.get(0),
                )
                .map_err(AppError::from)
            })
            .unwrap();
        assert_eq!(indexed, 1);
    }

    /// A buffered edit cannot maintain a container's child spans, so
    /// `update_block` refuses the path instead of leaving a map whose
    /// descendants address bytes that no longer exist.
    #[test]
    fn update_block_refuses_a_container_path_and_changes_nothing() {
        let f = fixture();
        f.write("a.md", "- alpha\n- beta\n\ntail\n");
        let session = f.open("a");
        let before = session.working_source().unwrap();

        let result = session.update_block(&[0], "- rewritten entirely\n");

        assert!(matches!(result, Err(AppError::ParseError(_))), "{result:?}");
        assert_eq!(
            session.working_source().unwrap(),
            before,
            "the buffer moved"
        );
        assert!(f.draft("a").is_none(), "a refused edit wrote a draft row");

        // The leaf inside the item is what the user actually focuses, and it
        // is served.
        assert_eq!(
            session.resolve_block_caret(&[0], 1).unwrap(),
            (vec![0, 0, 0], 1),
            "pointer promotion resolves the List container to its editable leaf"
        );
        session.update_block(&[0, 0, 0], "alpha edited").unwrap();
        assert!(session.working_source().unwrap().contains("alpha edited"));
    }

    /// A keystroke landing between the close-time flush and the draft clear is
    /// work no write has covered. Clearing it would destroy it, which is the
    /// direction `SPK-WSPC-D001` §6.2.6 says must never be taken.
    #[test]
    fn a_close_clears_only_the_draft_the_flush_covered() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));
        f.commit_baseline();
        let session = f.open("a");
        session.update_block(&[0], "Flushed.\n").unwrap();
        let flushed = session.flush_covering().unwrap();

        // The racing keystroke: its row is newer than anything on disk.
        session
            .update_block(&[0], "Typed after the flush.\n")
            .unwrap();
        let racing_seq = session.edit_seq();
        assert!(racing_seq > flushed.seq);

        // Close re-flushes, so the racing row is covered this time; the case
        // that matters is a clear bound to the *earlier* sequence, which is
        // what the close would have used had it cleared unconditionally.
        session.clear_draft_through(flushed.seq).unwrap();

        let row = f
            .draft("a")
            .expect("the racing keystroke's row was destroyed");
        assert_eq!(row.edit_seq, racing_seq);
    }

    /// A Note deleted by something outside this application must not trap the
    /// session: every flush and every reload would fail on the same missing
    /// file. Closing retires it without a commit and **keeps the draft row**,
    /// which is what makes the deleted work recoverable.
    #[test]
    fn a_note_whose_file_vanished_can_still_be_closed_and_its_draft_survives() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));
        f.commit_baseline();
        let session = f.open("a");
        session
            .update_block(&[0], "Work that only exists in the draft.\n")
            .unwrap();

        std::fs::remove_file(f.root().join("a.md")).unwrap();

        // The write tier reports the deletion as such rather than as a generic
        // I/O failure, so the close below can tell the two apart.
        assert!(
            matches!(session.flush(), Err(AppError::NotFound(_))),
            "a vanished file must surface as NotFound"
        );

        session
            .close()
            .expect("a vanished file must not trap the session");

        assert_eq!(
            f.commit_subjects().len(),
            1,
            "nothing was on disk to commit"
        );
        let row = f
            .draft("a")
            .expect("the draft row is the only copy of the work left");
        assert!(row
            .raw_markdown
            .contains("Work that only exists in the draft."));
        // The session is gone, so a later open recovers from the row rather
        // than addressing a session whose file is not there. What that open
        // then does is the test below.
        assert!(lookup(f.workspace.id(), "a").unwrap().is_none());
    }

    /// The other half of the promise above, and the half that was missing:
    /// keeping the row is only recovery if something can open it again.
    ///
    /// `open_note` read the file before it consulted `drafts`, so every click
    /// on the Note `pending_drafts` was still listing returned `NotFound` and
    /// the kept work had no route back into the editor at all — the row simply
    /// sat there until a reindex removed the `notes` row that named it.
    #[test]
    fn a_vanished_notes_draft_is_recovered_by_reopening_it() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));
        f.commit_baseline();
        let session = f.open("a");
        session
            .update_block(&[0], "Work that only exists in the draft.\n")
            .unwrap();

        std::fs::remove_file(f.root().join("a.md")).unwrap();
        session
            .close()
            .expect("a vanished file must not trap the session");

        // The surface that tells the user the work survived still names it...
        let pending = pending_drafts(&f.workspace).unwrap();
        assert_eq!(
            pending.iter().map(|m| m.id.as_str()).collect::<Vec<_>>(),
            vec!["a"]
        );

        // ...and opening what it names now hands the work back rather than
        // reporting the file it no longer has.
        let (recovered, state) =
            open_note(&f.workspace, "a").expect("the Note pending_drafts reports must be openable");
        assert!(
            state.restored_from_draft,
            "the recovered buffer must be flagged as restored, for SHEL-E007's notice"
        );
        assert!(recovered
            .working_source()
            .unwrap()
            .contains("Work that only exists in the draft."));
        assert!(
            !f.root().join("a.md").exists(),
            "opening must not write; tier 2 is what puts bytes on disk"
        );

        // The first tier 2 write recreates the file, rather than failing the
        // OCC check against a file that is not there.
        recovered.flush().unwrap();
        assert!(f
            .read("a.md")
            .contains("Work that only exists in the draft."));
        assert!(
            f.draft("a").is_none(),
            "the row must be cleared by the write that covered it"
        );

        // And from there the session is ordinary: another edit writes, and the
        // close commits the recreated file.
        recovered
            .update_block(&[0], "Typed after the recovery.\n")
            .unwrap();
        recovered.flush().unwrap();
        assert!(f.read("a.md").contains("Typed after the recovery."));
        recovered.close().unwrap();
        assert!(f.draft("a").is_none());
        assert_eq!(
            f.commit_subjects(),
            vec!["Update A".to_string(), "baseline".to_string()],
            "the recreated file must reach history on close"
        );
        assert!(f
            .git(&["show", "HEAD:a.md"])
            .contains("Typed after the recovery."));
    }

    /// Deleting a Note in a file manager often means deleting the folder it
    /// was in. The recreate path has to put that level back, or every write
    /// the recovered session makes fails with an `IoError` — which `close`
    /// does not read as a vanished file, so the session becomes unclosable and
    /// the trap simply moves one level up.
    #[test]
    fn a_recovered_draft_recreates_the_directory_that_went_with_its_file() {
        let f = fixture();
        f.write("projects/a.md", &note("A", "First."));
        f.commit_baseline();
        let session = f.open("projects/a");
        session.update_block(&[0], "Only in the draft.\n").unwrap();

        std::fs::remove_dir_all(f.root().join("projects")).unwrap();
        session.close().unwrap();

        let (recovered, _) = open_note(&f.workspace, "projects/a").unwrap();
        recovered.flush().unwrap();

        assert!(f.root().join("projects").is_dir());
        assert!(f.read("projects/a.md").contains("Only in the draft."));
        recovered.close().unwrap();
    }

    /// The state a recovered session is in **after a reload**: it is owed
    /// nothing, because the reload read a file.
    ///
    /// `awaiting_recreate` says "this session opened over no file and so owes
    /// the next tier 2 write a file rather than an overwrite". A reload cannot
    /// succeed without a file, so by the time it re-records the baseline the
    /// flag describes a state that has stopped being true — and it used not to
    /// be cleared. The cheap consequence is here: while it stands,
    /// `write_locked` writes unconditionally, so every idle tick rewrites bytes
    /// byte-identical to the ones already on disk. The inode is what shows it,
    /// since `atomic_write` renames a fresh temporary over the path.
    #[cfg(unix)]
    #[test]
    fn an_idle_write_after_a_recovered_note_reloads_does_not_rewrite_unchanged_bytes() {
        use std::os::unix::fs::MetadataExt as _;

        let f = fixture();
        let session = recovered_session_whose_file_came_back(&f);
        session.reload().unwrap();

        let before = std::fs::metadata(f.root().join("a.md")).unwrap().ino();
        session.flush().unwrap();
        let after = std::fs::metadata(f.root().join("a.md")).unwrap().ino();

        assert_eq!(
            before, after,
            "a write of unchanged bytes replaced the file: the reloaded session is \
             still marked as owing a recreate"
        );
    }

    /// The costly consequence of the same flag: a **second** external deletion.
    ///
    /// With `awaiting_recreate` still set, the absent file compares as the empty
    /// one against a baseline taken from real content, so tier 2 raises
    /// `RevisionMismatch` rather than `NotFound` — and `close` reads only
    /// `NotFound` as a vanished file. The session was therefore stranded in the
    /// registry with its timer armed, which is precisely the unclosable state
    /// the recovery path exists to get the user out of, reached a second time.
    #[test]
    fn a_second_external_deletion_after_a_reload_surfaces_not_found_and_closes() {
        let f = fixture();
        let session = recovered_session_whose_file_came_back(&f);
        session.reload().unwrap();

        std::fs::remove_file(f.root().join("a.md")).unwrap();

        assert!(
            matches!(session.flush(), Err(AppError::NotFound(_))),
            "a file deleted after a reload is an external deletion like any other"
        );
        session
            .close()
            .expect("a vanished file must not trap the session a second time");
        assert!(
            lookup(f.workspace.id(), "a").unwrap().is_none(),
            "the session is still registered, so the Note can never be closed"
        );
    }

    /// The shared setup for the two tests above: a Note deleted underneath an
    /// unflushed session, recovered from its `drafts` row, and then met by a
    /// file that has **come back** — a sync landing, a restore from the trash.
    /// The returned session is the recovered one, still flagged
    /// `awaiting_recreate` and not yet reloaded.
    fn recovered_session_whose_file_came_back(f: &Fixture) -> NoteSession {
        f.write("a.md", &note("A", "First."));
        f.commit_baseline();
        let session = f.open("a");
        session
            .update_block(&[0], "Work that only exists in the draft.\n")
            .unwrap();
        std::fs::remove_file(f.root().join("a.md")).unwrap();
        session.close().unwrap();

        let (recovered, _) = open_note(&f.workspace, "a").unwrap();
        f.write("a.md", &note("A", "Returned from somewhere else."));
        recovered
    }

    /// A Note whose file is gone and whose draft row is gone with it is simply
    /// not there, and still says so.
    #[test]
    fn a_vanished_file_with_no_draft_still_reports_not_found() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));
        let session = f.open("a");
        session.close().unwrap();
        std::fs::remove_file(f.root().join("a.md")).unwrap();

        assert!(f.draft("a").is_none());
        assert!(matches!(
            open_note(&f.workspace, "a"),
            Err(AppError::NotFound(_))
        ));
    }

    /// Reload surfaces the same distinction, so the UI is told the file is gone
    /// rather than that something unspecified went wrong with it.
    #[test]
    fn reloading_a_vanished_file_reports_not_found() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));
        let session = f.open("a");
        std::fs::remove_file(f.root().join("a.md")).unwrap();

        assert!(matches!(session.reload(), Err(AppError::NotFound(_))));
    }

    /// A reload that fails must leave the `drafts` row exactly where it found
    /// it, because a failing reload is precisely when that row is the only copy
    /// of the user's work.
    ///
    /// The regression this pins: `reload` deleted the row *first* and only then
    /// read the file, so a Note something outside this application had deleted
    /// answered `NotFound` having already destroyed the unflushed buffer on its
    /// way there. That is the exact row `close` goes out of its way to keep for
    /// a vanished file, that `pending_drafts` reports, and that `open_note`'s
    /// recovery branch reopens — a reload attempted anywhere along that path
    /// emptied it.
    #[test]
    fn a_reload_of_a_vanished_file_leaves_the_draft_row_recoverable() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));
        let session = f.open("a");
        session.update_block(&[0], "Unwritten work.\n").unwrap();
        assert!(f.draft("a").is_some(), "tier 1 wrote the row");
        std::fs::remove_file(f.root().join("a.md")).unwrap();

        assert!(matches!(session.reload(), Err(AppError::NotFound(_))));

        let row = f
            .draft("a")
            .expect("a failed reload must not delete the draft row");
        assert!(
            row.raw_markdown.contains("Unwritten work."),
            "the row must still hold the buffer, got {:?}",
            row.raw_markdown
        );

        // And the round-4 recovery path really can act on it: the session is
        // dropped from the registry the way a crash would leave it, and the
        // reopen restores the row rather than answering `NotFound`.
        session.forget();
        let (_, state) = open_note(&f.workspace, "a").expect("the row must be reopenable");
        assert!(state.restored_from_draft);
        assert!(session
            .working_source()
            .unwrap()
            .contains("Unwritten work."));
    }

    /// The same obligation on the other refusing branch: a file that has gone
    /// invalid underneath the session. The decode is what refuses, and it must
    /// refuse before the row is cleared rather than after.
    #[test]
    fn a_reload_of_a_file_that_went_invalid_leaves_the_draft_row_intact() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));
        let session = f.open("a");
        session.update_block(&[0], "Unwritten work.\n").unwrap();

        let mut bytes = note("A", "First.").into_bytes();
        bytes.extend_from_slice(b"latin-1 caf\xe9\n");
        std::fs::write(f.root().join("a.md"), &bytes).unwrap();

        assert!(matches!(session.reload(), Err(AppError::ParseError(_))));

        let row = f
            .draft("a")
            .expect("a refused decode must not delete the draft row");
        assert!(row.raw_markdown.contains("Unwritten work."));
    }

    /// A session that brings a foreign file into conformance, or corrects its
    /// title, must not keep reporting the old metadata — or commit under the
    /// old title, which is what the user reads when recovering a version.
    #[test]
    fn reparsing_refreshes_the_title_and_the_conformance_flag() {
        let f = fixture();
        // No frontmatter at all: a file another tool wrote (CAP-WS-05).
        f.write("a.md", "Just a body.\n");
        f.commit_baseline();
        let session = f.open("a");
        let (_, opened) = open_note(&f.workspace, "a").unwrap();
        assert!(!opened.metadata.okf_conformant);
        assert_eq!(opened.metadata.title, "a");

        // The user repairs it — an explicit action, never automatic.
        session
            .insert_block(&[0], "---\ntype: Note\ntitle: Repaired\n---".to_string())
            .unwrap();
        let state = session.commit_block(&[0]).unwrap();

        assert!(
            state.metadata.okf_conformant,
            "conformance was not re-derived"
        );
        assert_eq!(state.metadata.title, "Repaired");
        session.close().unwrap();
        assert_eq!(f.commit_subjects()[0], "Update Repaired");
    }

    /// A concept id is joined onto the bundle root, and `WSPC-D008` wires that
    /// parameter to ids the UI supplies. One that walks out of the Workspace is
    /// refused before anything is read.
    #[test]
    fn a_concept_id_that_escapes_the_workspace_is_refused() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));
        // A real file outside the bundle, so the refusal cannot be mistaken for
        // "no such file".
        std::fs::write(f.dir.path().join("outside.md"), "secrets\n").unwrap();

        // `..` itself is deliberately absent: `.md` is appended before the path
        // is resolved, so it names a file called `...md` *inside* the bundle
        // and is refused, correctly, as a Note that does not exist.
        assert!(matches!(
            open_note(&f.workspace, "..").map(|(_, state)| state),
            Err(AppError::NotFound(_))
        ));

        for escaping in [
            "../outside",
            "../../etc/passwd",
            "/etc/passwd",
            "a/../../outside",
            // A backslash is refused here for the same reason
            // `lifecycle::normalize_directory` refuses it in a Directory path
            // and `lifecycle::validate_segment` in a name: on Unix `..\..\x` is
            // one `Component::Normal`, so the containment check below cannot see
            // it, and three path-handling functions that disagree about what a
            // segment may carry is the shape the round-1 traversal defect had.
            "..\\..\\outside",
            "a\\b",
        ] {
            let refused = open_note(&f.workspace, escaping).map(|(_, state)| state);
            assert!(
                matches!(refused, Err(AppError::PathUnavailable(_))),
                "{escaping} was not refused: {:?}",
                refused.map(|state| state.metadata.path)
            );
        }
        // The ordinary id still opens, and so does one in a subdirectory.
        f.write("deep/nested/b.md", &note("B", "Nested."));
        open_note(&f.workspace, "a").unwrap();
        open_note(&f.workspace, "deep/nested/b").unwrap();
    }

    /// The draft row must never go backwards, as a property of the statement
    /// rather than an assumption that the calls producing it arrive in order.
    #[test]
    fn a_draft_row_never_regresses_to_an_older_edit_sequence() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));
        let session = f.open("a");
        session.update_block(&[0], "Newest.\n").unwrap();
        let newest = f.draft("a").unwrap();

        // An out-of-order tier 1 write, carrying older bytes and an older
        // sequence than the row already holds.
        session
            .write_draft("stale bytes that must not win\n", newest.edit_seq - 1)
            .unwrap();

        let row = f.draft("a").unwrap();
        assert_eq!(row.edit_seq, newest.edit_seq);
        assert_eq!(row.raw_markdown, newest.raw_markdown);
    }

    /// Reload deliberately leaves `session_edited` alone: work this session
    /// already wrote to disk is on disk still, and dropping it out of history
    /// would buy nothing, since the pathspec commit no-ops when the path
    /// already matches HEAD.
    #[test]
    fn work_written_before_a_reload_still_reaches_history_on_close() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));
        f.commit_baseline();
        let session = f.open("a");
        session
            .update_block(&[0], "Written before the reload.\n")
            .unwrap();
        session.flush().unwrap();

        session.reload().unwrap();
        session.close().unwrap();

        assert_eq!(
            f.commit_subjects().len(),
            2,
            "the flushed work never reached history"
        );
        assert!(f
            .git(&["show", "HEAD:a.md"])
            .contains("Written before the reload."));
    }

    /// Two threads opening the same Note must converge on one session, or the
    /// loser's buffer — and any timer already armed against it — is stranded
    /// while the FFI surface addresses the winner's.
    #[test]
    fn opening_the_same_note_twice_converges_on_one_session() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));

        let first = f.open("a");
        let second = f.open("a");

        first
            .update_block(&[0], "Typed into the first handle.\n")
            .unwrap();
        assert_eq!(
            second.working_source().unwrap(),
            first.working_source().unwrap(),
            "the second open returned a different buffer"
        );
        assert!(Arc::ptr_eq(&first.0, &second.0));
    }

    /// An open cannot run inside a lifecycle operation, which is what stops it
    /// installing a session for a Note a concurrent `delete_note` has already
    /// retired.
    ///
    /// The race this closes: `delete_note` removes the file, clears both rows
    /// and *then* calls `discard_session`, so an open that read the file and the
    /// draft before the deletion started and reached its registry insert after
    /// the discard left a live session — with the deleted content in its buffer
    /// and its name reserved against `ensure_path_available` — for a Note that
    /// exists in no store. Both halves now take the same Workspace-wide lock, so
    /// the interleaving is unrepresentable rather than merely unlikely.
    ///
    /// Driven through the lock itself rather than through the deletion: holding
    /// it is exactly the condition a lifecycle operation establishes, and the
    /// assertion — the open makes no progress until it is released — is what
    /// serialization *means* here. The sleep can only weaken the observation,
    /// never fail it spuriously: a slower machine makes the "not yet" more
    /// certain, and the join below is what proves the open is blocked rather
    /// than broken.
    #[test]
    fn an_open_cannot_run_inside_a_lifecycle_operation() {
        let f = fixture();
        f.write("a.md", &note("A", "First."));

        let opened = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let entered = Arc::new(std::sync::atomic::AtomicBool::new(false));

        let waiter = with_lifecycle_lock(&f.workspace, || {
            let workspace = Arc::clone(&f.workspace);
            let opened_by_waiter = Arc::clone(&opened);
            let entered_by_waiter = Arc::clone(&entered);
            let waiter = std::thread::spawn(move || {
                entered_by_waiter.store(true, Ordering::SeqCst);
                open_note(&workspace, "a").expect("the Note is on disk");
                opened_by_waiter.store(true, Ordering::SeqCst);
            });

            while !entered.load(Ordering::SeqCst) {
                std::thread::yield_now();
            }
            std::thread::sleep(Duration::from_millis(100));
            assert!(
                !opened.load(Ordering::SeqCst),
                "open_note completed while a lifecycle operation held the lock, so \
                 a delete can still retire a session an open is about to install"
            );
            Ok(waiter)
        })
        .unwrap();

        waiter.join().unwrap();
        assert!(
            opened.load(Ordering::SeqCst),
            "the open never completed once the lock was released"
        );
        assert!(lookup(f.workspace.id(), "a").unwrap().is_some());
    }

    /// A Note opened *after* `with_write_locks` read the registry is still
    /// covered by the locks the lifecycle operation runs under.
    ///
    /// The window is real rather than theoretical: FRB 2.12's default handler
    /// documents itself as "an internal thread pool, and each call to a Rust
    /// function is handled by a different thread", and every `#[frb] async fn`
    /// in `api::ffi_api` — `open_note` among them — is dispatched through it. The
    /// registry lock cannot be held across the acquisition (the lock order
    /// forbids it, and `carry_session_forward` takes the registry lock *inside*
    /// the write locks), so the snapshot has to be re-checked afterwards
    /// instead. The hook below opens the second Note in exactly that window; the
    /// assertion is that the body still runs with its write lock held.
    ///
    /// `try_lock` is the observation because it is taken from the thread that
    /// holds the lock: `Mutex::try_lock` reports `WouldBlock` for an
    /// already-locked mutex whoever locked it, whereas `lock` from the same
    /// thread would deadlock.
    #[test]
    fn a_session_opened_after_the_lock_snapshot_is_still_locked_by_the_operation() {
        let f = fixture();
        f.write("first.md", &note("First", "one"));
        f.write("second.md", &note("Second", "two"));
        let _first = f.open("first");

        let opened_late = std::cell::Cell::new(false);
        let held_inside = std::cell::Cell::new(None);

        with_write_locks_hooked(
            &f.workspace,
            || {
                if !opened_late.replace(true) {
                    f.open("second");
                }
            },
            || {
                let late = lookup(f.workspace.id(), "second")?
                    .expect("the late open registered a session");
                held_inside.set(Some(late.0.write_lock.try_lock().is_err()));
                Ok(())
            },
        )
        .unwrap();

        assert!(opened_late.get(), "the hook never ran");
        assert_eq!(
            held_inside.get(),
            Some(true),
            "a session that appeared after the snapshot ran unlocked inside the \
             lifecycle operation, so an idle write could land in the middle of it"
        );
    }

    // -- a conflicted Note is not editable until it is resolved --------------

    /// A merged file whose conflict is genuinely terminated, so
    /// [`conflict_suggestions`] collapses it. Three Blocks in the AST it
    /// produces — `Para A.`, the `Suggestion`, `Para B.` — against four in the
    /// span map built from these same bytes, which is the whole of the hazard
    /// below.
    const CONFLICTED: &str = "---\ntype: Note\ntitle: Alpha\n---\n\nPara A.\n\n\
                              <<<<<<< HEAD\nMine.\n=======\nTheirs.\n\
                              >>>>>>> origin/main\n\nPara B.\n";

    fn refuses_as_conflicted<T: std::fmt::Debug>(what: &str, result: Result<T, AppError>) {
        match result {
            // Named, not merely refused: the caller has to be able to tell this
            // apart from an unaddressable `block_path`, because the remedy is
            // completely different.
            Err(AppError::ParseError(message)) => assert!(
                message.starts_with("a holds an unresolved merge conflict"),
                "{what}: the refusal must name the Note and the unresolved \
                 conflict, got {message:?}"
            ),
            other => panic!("{what} must refuse while the conflict stands, got {other:?}"),
        }
    }

    /// `reload` installs an AST the conflict collapse **renumbered** alongside
    /// a span map built from the raw source, so every `block_path` the UI reads
    /// off that AST addresses a different Block of the file: `[2]` is `Para B.`
    /// in the AST and the conflict's `incoming` section in the map. Served,
    /// `block_source` hands back the wrong text; taken, `update_block` splices
    /// the user's typing over conflict machinery and tier 2 writes it to disk.
    ///
    /// The invariant the collapse always claimed — "a conflicted Note is not
    /// editable until the Suggestion is resolved" — is therefore enforced
    /// rather than merely documented.
    #[test]
    fn a_conflicted_note_refuses_every_call_that_addresses_a_block() {
        let f = fixture();
        f.write("a.md", &note("Alpha", "Para A."));
        let session = f.open("a");
        f.write("a.md", CONFLICTED);

        let state = session.reload().unwrap();
        assert!(
            state
                .ast
                .iter()
                .any(|node| matches!(node, AstNode::Suggestion { .. })),
            "the fixture must actually conflict: {:?}",
            state.ast
        );

        let range = RenderedRange::new(vec![0], 0, vec![2], 1);
        refuses_as_conflicted("block_source", session.block_source(&[2]));
        refuses_as_conflicted(
            "update_block",
            session.update_block(&[2], "typed over it\n"),
        );
        refuses_as_conflicted("commit_block", session.commit_block(&[2]));
        refuses_as_conflicted(
            "insert_block",
            session.insert_block(&[2], "inserted".to_string()),
        );
        refuses_as_conflicted("delete_block", session.delete_block(&[2]));
        refuses_as_conflicted("split_block", session.split_block(&[2], 1));
        refuses_as_conflicted(
            "merge_block_with_previous",
            session.merge_block_with_previous(&[2]),
        );
        refuses_as_conflicted("delete_range", session.delete_range(&range));
        refuses_as_conflicted("replace_range", session.replace_range(&range, "x"));
        refuses_as_conflicted(
            "copy_range_as_markdown",
            session.copy_range_as_markdown(&range),
        );

        // Nothing was buffered and nothing reached disk.
        assert_eq!(*session.working_source().unwrap(), CONFLICTED);
        assert_eq!(f.read("a.md"), CONFLICTED);
        // The read-only surface is untouched: this is a Note the user must be
        // able to look at in order to resolve it.
        assert!(!session.note_state().unwrap().ast.is_empty());
        assert!(!session.write_status().unwrap().has_unwritten_edits);
    }

    /// The exit. The conflict is resolved outside this application — by the
    /// user in another editor, or by the Sync Manager — and the reload that
    /// picks those bytes up re-evaluates the flag rather than latching it, so
    /// the Note becomes editable again with no reopen.
    #[test]
    fn a_reload_of_a_repaired_file_makes_the_note_editable_again() {
        let f = fixture();
        f.write("a.md", &note("Alpha", "Para A."));
        let session = f.open("a");
        f.write("a.md", CONFLICTED);
        session.reload().unwrap();
        assert!(session.update_block(&[2], "x\n").is_err());

        f.write("a.md", &note("Alpha", "Para A.\n\nResolved.\n\nPara B."));
        let state = session.reload().unwrap();

        assert!(
            !state
                .ast
                .iter()
                .any(|node| matches!(node, AstNode::Suggestion { .. })),
            "the repaired file still parsed as conflicted: {:?}",
            state.ast
        );
        assert_eq!(session.block_source(&[2]).unwrap().trim(), "Para B.");
        session.update_block(&[2], "Para B, edited.\n").unwrap();
        session.flush().unwrap();
        assert!(f.read("a.md").contains("Para B, edited."));
    }

    /// A conflicted session still **closes**, and closes clean: the buffer is
    /// byte-identical to the file the reload read, so tier 2 writes nothing and
    /// the conflicted bytes are the user's own merge state rather than anything
    /// this application put there. Refusing the close instead would strand a
    /// Note the user cannot navigate away from, which is the trap every other
    /// path in this tier is shaped to avoid.
    #[test]
    fn closing_a_conflicted_session_writes_nothing_of_its_own() {
        let f = fixture();
        f.write("a.md", &note("Alpha", "Para A."));
        let session = f.open("a");
        session
            .update_block(&[0], "Edited before the merge.\n")
            .unwrap();
        f.write("a.md", CONFLICTED);
        session.reload().unwrap();

        session.close().unwrap();

        assert_eq!(
            f.read("a.md"),
            CONFLICTED,
            "close rewrote a file it had no edits for"
        );
    }

    /// A `<<<<<<<` line **inside a fenced code block** — a Note documenting how
    /// to resolve a merge, which is an ordinary thing to write — opens a region
    /// the line-based scan never sees closed. Everything after it used to be
    /// swallowed into the unterminated section and dropped from the AST
    /// outright, so the tail of the Note vanished on reload.
    ///
    /// A scan that ends outside `Plain` therefore reports **no conflict at
    /// all**: an unterminated region is not one, and treating it as one would
    /// also fabricate `Suggestion` nodes out of a code sample.
    #[test]
    fn an_unterminated_marker_is_not_a_conflict_and_keeps_the_notes_tail() {
        let f = fixture();
        f.write("a.md", &note("Alpha", "Intro."));
        let session = f.open("a");
        f.write(
            "a.md",
            "---\ntype: Note\ntitle: Alpha\n---\n\nIntro.\n\n\
             ```\n<<<<<<< HEAD\n```\n\nTail paragraph.\n",
        );

        let state = session.reload().unwrap();

        let rendered = format!("{:?}", state.ast);
        assert!(
            !state
                .ast
                .iter()
                .any(|node| matches!(node, AstNode::Suggestion { .. })),
            "a fenced marker is not a conflict: {rendered}"
        );
        assert!(
            rendered.contains("Tail paragraph"),
            "the tail after the unterminated marker was dropped: {rendered}"
        );
        // And the Note stays editable, because nothing renumbered its Blocks.
        assert_eq!(session.block_source(&[0]).unwrap().trim(), "Intro.");
    }

    /// The early exit and the scan agree on how a marker is spelled, so an
    /// **unlabeled** `<<<<<<<` is a conflict to both of them.
    ///
    /// The disagreement this pins: the early exit tested `contains("<<<<<<< ")`
    /// — with a trailing space — while the scan matched `starts_with("<<<<<<<")`
    /// without one, so a region opened by a bare `<<<<<<<` short-circuited as
    /// unconflicted and its markers rendered as literal text in an editable
    /// Note. The direction is safe, but two spellings of one predicate is an
    /// invitation to "fix" whichever one is read second, and the wrong choice
    /// there un-sets `conflicted` on a real conflict.
    #[test]
    fn an_unlabeled_conflict_marker_is_still_a_conflict() {
        let f = fixture();
        f.write("a.md", &note("Alpha", "First."));
        let session = f.open("a");
        f.write(
            "a.md",
            "---\ntype: Note\ntitle: Alpha\n---\n\nBefore.\n\n\
             <<<<<<<\nMine.\n=======\nTheirs.\n>>>>>>>\n\nAfter.\n",
        );

        let state = session.reload().unwrap();

        assert!(
            state
                .ast
                .iter()
                .any(|node| matches!(node, AstNode::Suggestion { .. })),
            "an unlabeled marker opens a genuine conflict region: {:?}",
            state.ast
        );
        assert!(
            !format!("{:?}", state.ast).contains("<<<<<<<"),
            "the markers survived as literal text"
        );
        // A Note with no marker at all still takes the early exit unchanged.
        let g = fixture();
        g.write("b.md", &note("Beta", "Ordinary prose about nothing."));
        let clean = g.open("b");
        assert!(!format!("{:?}", clean.reload().unwrap().ast).contains("Suggestion"));
    }

    /// Every internal Link `target_id` in `ast`, in tree order.
    fn internal_targets(ast: &[AstNode]) -> Vec<String> {
        fn walk(nodes: &[AstNode], out: &mut Vec<String>) {
            for node in nodes {
                match node {
                    AstNode::Paragraph { content } | AstNode::Heading { content, .. } => {
                        for element in content {
                            if let crate::markdown::InlineElement::Link { target_id, .. } = element
                            {
                                out.push(target_id.clone());
                            }
                        }
                    }
                    AstNode::Blockquote { nodes } => walk(nodes, out),
                    AstNode::List { items, .. } => walk(items, out),
                    AstNode::ListItem { content, .. } => walk(content, out),
                    AstNode::Suggestion {
                        base_content,
                        local_content,
                        incoming_content,
                    } => {
                        if let Some(base) = base_content {
                            walk(base, out);
                        }
                        walk(local_content, out);
                        walk(incoming_content, out);
                    }
                    _ => {}
                }
            }
        }
        let mut out = Vec::new();
        walk(ast, &mut out);
        out
    }

    /// Every segment of a conflicted Note resolves its relative Links against
    /// the **Note's own Directory**, not the bundle root.
    ///
    /// The regression this pins: only the `---`-prefixed branch of
    /// `parse_markdown_segment` was handed `containing_dir`; every other
    /// segment — which is every conflict side and every plain segment after the
    /// head — went through `parse_markdown`, i.e. `parse_note(source, "")`. A
    /// relative `[u](Other.md)` inside `sub/a.md` therefore classified as
    /// `Internal("Other")` rather than `Internal("sub/Other")`, so the rendered
    /// Link carried a `target_id` no `notes.id` equals and `exists` came back
    /// false for a Note that is right there beside it.
    #[test]
    fn a_conflicted_notes_relative_links_resolve_against_its_own_directory() {
        let source = "Head [h](Other.md)\n\n\
                      <<<<<<< HEAD\nMine [l](Other.md)\n\
                      =======\nTheirs [i](Other.md)\n\
                      >>>>>>> origin/main\n\n\
                      Tail [t](Other.md)\n";

        let collapsed = conflict_suggestions(source, "sub").expect("the fixture must conflict");

        assert_eq!(
            internal_targets(&collapsed),
            vec![
                "sub/Other".to_string(),
                "sub/Other".to_string(),
                "sub/Other".to_string(),
                "sub/Other".to_string(),
            ],
            "a segment parsed against the bundle root instead of the Note's own \
             Directory: {collapsed:?}"
        );
    }

    /// A conflict side (or a tail) that **opens with `---`** keeps its content.
    ///
    /// The regression this pins: both arms of `parse_markdown_segment` parsed
    /// with `ENABLE_YAML_STYLE_METADATA_BLOCKS`, which is only correct for the
    /// positional head of the document. A local side of `---\nMine\n---` is a
    /// thematic break, a paragraph and another thematic break; parsed as a
    /// metadata block it produced **no AST nodes at all**, so the side vanished
    /// from the Suggestion the user is being asked to choose between — the one
    /// place in this crate where silently dropping content decides which of two
    /// versions of the user's work survives.
    #[test]
    fn a_conflict_segment_opening_with_a_thematic_break_keeps_its_content() {
        let source = "---\ntype: Note\ntitle: Alpha\n---\n\nHead.\n\n\
                      <<<<<<< HEAD\n---\nMine\n---\n\
                      =======\nTheirs\n\
                      >>>>>>> origin/main\n\
                      ---\nTail after a break\n---\n";

        let collapsed = conflict_suggestions(source, "").expect("the fixture must conflict");
        let rendered = format!("{collapsed:?}");

        assert!(
            rendered.contains("Mine"),
            "the local side opening with `---` was swallowed as frontmatter: {rendered}"
        );
        assert!(
            rendered.contains("Theirs"),
            "the incoming side is missing: {rendered}"
        );
        assert!(
            rendered.contains("Tail after a break"),
            "the tail segment opening with `---` was swallowed as frontmatter: {rendered}"
        );
        // And the head's real frontmatter is still frontmatter: it contributes
        // no Block of its own, rather than a thematic break plus a heading
        // built out of the YAML.
        assert!(
            !rendered.contains("title: Alpha"),
            "the head's frontmatter stopped being parsed as frontmatter: {rendered}"
        );
        assert!(
            rendered.contains("Head."),
            "the head segment lost its prose: {rendered}"
        );
    }
}
