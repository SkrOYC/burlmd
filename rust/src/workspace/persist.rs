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
//! # The locks, and why there are three of them
//!
//! `SPK-WSPC-D001` §4.4 measured four shapes. Under one process-wide mutex a
//! keystroke waits a p95 of 10.4ms (WAL) or 55.9ms (SQLite defaults) in front
//! of buffer work that performs no I/O at all — the ADR-008 hazard reproduced
//! as a number. The shape below measured 0.031ms.
//!
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
//! The only permitted acquisition order is **tier 2 write lock → state lock →
//! connection**, and no two are held at once except the write lock over a
//! snapshot. The keystroke path takes a suffix of that order (state, then
//! connection), so no cycle exists and deadlock is unrepresentable rather than
//! merely unobserved. The session registry lock is above all three and is
//! never held while any of them is acquired.
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
use std::sync::{Arc, Condvar, Mutex, MutexGuard, OnceLock, Weak};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use rusqlite::{Connection, OptionalExtension};

use crate::draft::{NoteMetadata, NoteState};
use crate::error::AppError;
use crate::index::{self, content_hash};
use crate::markdown::{
    parse_markdown, parse_note, splice, AstNode, ParsedNote, RenderedRange, SpanMap,
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
    pub fn active() -> Result<Arc<Workspace>, AppError> {
        let id = crate::db::connection::active_workspace_id()?;
        let root = crate::db::connection::with_connection(|conn| index::workspace_root(conn, &id))?;
        Ok(Arc::new(Workspace {
            id,
            root,
            db: DbHandle::Process,
            idle_interval: DEFAULT_IDLE_INTERVAL,
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
    /// the acquisition order in the module documentation.
    fn with_db<T>(
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
                f(&conn)
            }
        }
    }

    fn note_path(&self, note_id: &str) -> PathBuf {
        self.root.join(concept_id_to_path(note_id))
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
        })
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
    /// Whether this session has changed the Note at all. Tier 3's gate: a Note
    /// opened and closed unread makes no commit.
    session_edited: bool,
    /// Whether edits are buffered that no successful tier 2 write has covered.
    unwritten: bool,
    last_written_at: Option<i64>,
    last_error: Option<AppError>,
    closed: bool,
    metadata: NoteMetadata,
}

struct SessionInner {
    workspace: Arc<Workspace>,
    note_id: String,
    /// Bundle-relative path with `.md`, the pathspec tier 3 commits.
    relative_path: String,
    absolute_path: PathBuf,
    state: Mutex<SessionState>,
    /// Held across the whole OCC sequence — revision check, atomic write,
    /// re-record — and taken by tier 2 writers only.
    write_lock: Mutex<()>,
    timer: IdleTimer,
}

/// One open Note. Cheap to clone; every clone addresses the same state.
#[derive(Clone)]
pub struct NoteSession(Arc<SessionInner>);

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
pub fn open_note(
    workspace: &Arc<Workspace>,
    note_id: &str,
) -> Result<(NoteSession, NoteState), AppError> {
    if let Some(session) = lookup(workspace.id(), note_id)? {
        let state = session.note_state()?;
        return Ok((session, state));
    }

    let absolute_path = workspace.note_path(note_id);
    let bytes = std::fs::read(&absolute_path).map_err(|e| {
        if e.kind() == std::io::ErrorKind::NotFound {
            AppError::NotFound(format!("no file on disk for concept id {note_id}"))
        } else {
            AppError::IoError(format!("read {}: {e}", absolute_path.display()))
        }
    })?;
    let revision = content_hash(&bytes);
    let disk_source = String::from_utf8_lossy(&bytes).into_owned();
    let last_modified = file_mtime(&absolute_path);

    let draft = workspace.with_db(|conn| read_draft(conn, workspace.id(), note_id))?;
    let restored_from_draft = draft.is_some();
    let (source, edit_seq) = match draft {
        Some(row) => (row.raw_markdown, row.edit_seq),
        None => (disk_source, 0),
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
        // A restored draft is by definition work that never reached disk, so
        // this session inherits both the obligation to write it and the one to
        // commit it.
        session_edited: restored_from_draft,
        unwritten: restored_from_draft,
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
        write_lock: Mutex::new(()),
        timer: IdleTimer::new(workspace.idle_interval),
    }));

    registry()?.insert(
        (workspace.id().to_string(), note_id.to_string()),
        session.clone(),
    );
    if restored_from_draft {
        // Recovered work reaches disk on the same idle interval as work typed
        // in this session, rather than waiting for the user to touch a Note
        // they may have opened only to check that it survived.
        session.arm_idle_timer();
    }
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

    /// The current state, as it crosses the FFI boundary.
    pub fn note_state(&self) -> Result<NoteState, AppError> {
        let state = self.lock_state()?;
        Ok(NoteState {
            ast: state.ast.as_ref().clone(),
            metadata: state.metadata.clone(),
            base_revision: state.revision.clone(),
            restored_from_draft: state.restored_from_draft,
        })
    }

    /// The working source, for tests and for callers that need the buffer
    /// itself rather than a projection of it.
    pub fn working_source(&self) -> Result<Arc<String>, AppError> {
        Ok(Arc::clone(&self.lock_state()?.source))
    }

    /// The raw Markdown source of one Block (ADR-006 decision 2).
    pub fn block_source(&self, block_path: &[usize]) -> Result<String, AppError> {
        let state = self.lock_state()?;
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
    /// The ordering is `SPK-WSPC-D001` §6.2.2 exactly — acquire, mutate, bump
    /// the sequence, snapshot, **release**, then write the row. The row write
    /// is not cheap: 7.96ms at 102 KiB and 22.79ms at 1 MiB against the
    /// encrypted index on real storage, measured with content that actually
    /// changes (a benchmark rewriting a constant string reports 0.22ms and is
    /// wrong by a factor of 36). It is roughly a thousand times the cost of the
    /// buffer and span work it accompanies, which is exactly why no lock is
    /// held across it.
    pub fn update_block(&self, block_path: &[usize], new_source: &str) -> Result<(), AppError> {
        let (snapshot, seq) = {
            let mut guard = self.lock_state()?;
            let state = &mut *guard;
            let span = state
                .spans
                .block(block_path)
                .ok_or_else(|| {
                    AppError::ParseError(format!("no Block at block_path {block_path:?}"))
                })?
                .source
                .clone();
            check_span(&state.source, &span)?;

            // One writer of the working source for this text, and it is here.
            Arc::make_mut(&mut state.source).replace_range(span.clone(), new_source);
            Arc::make_mut(&mut state.spans).apply_buffered_edit(block_path, new_source.len());

            state.edit_seq += 1;
            state.session_edited = true;
            state.unwritten = true;
            (Arc::clone(&state.source), state.edit_seq)
        };

        self.write_draft(&snapshot, seq)?;
        self.arm_idle_timer();
        Ok(())
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
    pub fn commit_block(&self, _block_path: &[usize]) -> Result<NoteState, AppError> {
        loop {
            let (source, seq) = {
                let state = self.lock_state()?;
                (Arc::clone(&state.source), state.edit_seq)
            };
            let ParsedNote { mut ast, spans } =
                parse_note(&source, containing_dir(&self.0.note_id));
            self.resolve_links(&mut ast)?;

            let mut state = self.lock_state()?;
            if state.edit_seq != seq {
                continue;
            }
            state.ast = Arc::new(ast);
            state.spans = Arc::new(spans);
            // Deliberately no `edit_seq` increment here.
            drop(state);
            return self.note_state();
        }
    }

    /// Inserts a new Block before the one at `block_path`, or at the end of the
    /// Note when the path addresses nothing.
    pub fn insert_block(
        &self,
        block_path: &[usize],
        source: String,
    ) -> Result<NoteState, AppError> {
        self.structural_edit(|working, spans| {
            let at = spans
                .block(block_path)
                .map_or(working.len(), |b| b.source.start);
            let mut text = source.clone();
            text.push_str("\n\n");
            splice::splice_source(working, at..at, &text).map_err(splice_error)
        })
    }

    /// Deletes a Block, taking the separator that followed it with it so the
    /// remaining Blocks stay separated by exactly one blank line.
    pub fn delete_block(&self, block_path: &[usize]) -> Result<NoteState, AppError> {
        self.structural_edit(|working, spans| {
            let span = block_span(spans, block_path)?;
            let end = next_block_start(spans, &span).unwrap_or(span.end);
            splice::splice_source(working, span.start..end, "").map_err(splice_error)
        })
    }

    /// Splits a Block at a **source** offset — pressing Enter mid-Block. The
    /// focused Block displays raw source under ADR-006, so the caret position
    /// the UI reports is already a source offset.
    pub fn split_block(&self, block_path: &[usize], offset: usize) -> Result<NoteState, AppError> {
        self.structural_edit(|working, spans| {
            let span = block_span(spans, block_path)?;
            if offset > span.end - span.start {
                return Err(AppError::ParseError(format!(
                    "split offset {offset} is past the end of block_path {block_path:?}"
                )));
            }
            let at = span.start + offset;
            splice::splice_source(working, at..at, "\n\n").map_err(splice_error)
        })
    }

    /// Merges a Block into its predecessor — Backspace at offset 0. A no-op on
    /// the first Block.
    pub fn merge_block_with_previous(&self, block_path: &[usize]) -> Result<NoteState, AppError> {
        self.structural_edit(|working, spans| {
            let span = block_span(spans, block_path)?;
            let Some(previous_end) = previous_block_end(spans, &span) else {
                return Ok(working.to_string());
            };
            splice::splice_source(working, previous_end..span.start, "").map_err(splice_error)
        })
    }

    /// Deletes a multi-Block selection (ADR-006 decision 3).
    pub fn delete_range(&self, range: &RenderedRange) -> Result<NoteState, AppError> {
        self.replace_range(range, "")
    }

    /// Replaces a multi-Block selection with text.
    pub fn replace_range(
        &self,
        range: &RenderedRange,
        replacement: &str,
    ) -> Result<NoteState, AppError> {
        self.structural_edit(|working, spans| {
            let resolved = splice::resolve_range(working, spans, range).map_err(splice_error)?;
            splice::splice_source(working, resolved, replacement).map_err(splice_error)
        })
    }

    /// The Markdown a multi-Block selection covers — a slice of the Note, never
    /// a reconstruction of one.
    pub fn copy_range_as_markdown(&self, range: &RenderedRange) -> Result<String, AppError> {
        let state = self.lock_state()?;
        Ok(splice::extract_range(&state.source, &state.spans, range)
            .map_err(splice_error)?
            .to_string())
    }

    /// The shared shape of every structural mutator: snapshot under the state
    /// lock, compute the new source and reparse **off** it, install under an
    /// edit-sequence check, then write the draft row with no lock held.
    ///
    /// Each of these is a discrete user action rather than a keystroke, which
    /// is what keeps the reparse off the typing path — and each writes its
    /// draft row here, before the write tier fires, which is ADR-008
    /// decision 1's whole point.
    fn structural_edit(
        &self,
        edit: impl Fn(&str, &SpanMap) -> Result<String, AppError>,
    ) -> Result<NoteState, AppError> {
        loop {
            let (source, spans, seq) = {
                let state = self.lock_state()?;
                (
                    Arc::clone(&state.source),
                    Arc::clone(&state.spans),
                    state.edit_seq,
                )
            };
            let new_source = edit(&source, &spans)?;
            let ParsedNote { mut ast, spans } =
                parse_note(&new_source, containing_dir(&self.0.note_id));
            self.resolve_links(&mut ast)?;

            let (snapshot, new_seq) = {
                let mut guard = self.lock_state()?;
                let state = &mut *guard;
                if state.edit_seq != seq {
                    continue;
                }
                state.source = Arc::new(new_source);
                state.spans = Arc::new(spans);
                state.ast = Arc::new(ast);
                state.edit_seq += 1;
                state.session_edited = true;
                state.unwritten = true;
                (Arc::clone(&state.source), state.edit_seq)
            };

            self.write_draft(&snapshot, new_seq)?;
            self.arm_idle_timer();
            return self.note_state();
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

    fn write_draft(&self, source: &str, edit_seq: i64) -> Result<(), AppError> {
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
                     edit_seq = excluded.edit_seq",
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
        let _write_guard = self
            .0
            .write_lock
            .lock()
            .map_err(|_| AppError::DatabaseError("tier 2 write lock poisoned".to_string()))?;

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
            return Ok(revision);
        }

        match self.write_locked(&source, seq, &revision) {
            Ok(new_revision) => Ok(new_revision),
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

    /// The OCC sequence, run entirely under the tier 2 write lock: compare the
    /// bytes on disk against the recorded revision, write atomically, clear the
    /// draft row conditionally, re-record the revision.
    ///
    /// Without one lock spanning all of it, two tier 2 writers — the idle timer
    /// and a `close_note` — both read the same revision, both pass, and the
    /// second silently discards the first.
    fn write_locked(&self, source: &str, seq: i64, revision: &str) -> Result<String, AppError> {
        let on_disk = std::fs::read(&self.0.absolute_path).map_err(|e| {
            if e.kind() == std::io::ErrorKind::NotFound {
                AppError::NotFound(format!(
                    "the file for {} is no longer on disk",
                    self.0.note_id
                ))
            } else {
                AppError::IoError(format!("read {}: {e}", self.0.absolute_path.display()))
            }
        })?;
        let disk_revision = content_hash(&on_disk);
        if disk_revision != revision {
            // The file changed underneath the draft. The file is left exactly
            // as it is, and the current revision travels with the error so the
            // caller can offer a reload rather than guess.
            return Err(AppError::RevisionMismatch(disk_revision));
        }

        let new_revision = content_hash(source.as_bytes());
        if new_revision != disk_revision {
            atomic_write(&self.0.absolute_path, source.as_bytes())?;
        }

        self.clear_draft_through(seq)?;
        let workspace_id = self.0.workspace.id().to_string();
        let note_id = self.0.note_id.clone();
        self.0.workspace.with_db(|conn| {
            // The index tracks disk, so it is brought level with what was just
            // written. It short-circuits on the content hash, so a write that
            // changed nothing costs a hash rather than a parse.
            index::incremental::index_note(conn, &workspace_id, &note_id)?;
            Ok(())
        })?;

        let mut state = self.lock_state()?;
        state.revision = new_revision.clone();
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
    /// rather than a loss. The next timer firing clears it, and tier 3 clears
    /// it unconditionally on close. The asymmetry is the point — failing to
    /// clear costs one spurious recovery notice, clearing wrongly costs the
    /// user's work.
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

    /// Discards the buffered edits and re-reads the Note from disk: deletes the
    /// draft row, reparses the file's current bytes, and rebuilds the working
    /// source, the span map and the revision baseline from them.
    ///
    /// This is the other half of `RevisionMismatch`, and without it that error
    /// has no exit — `open_note` restores the draft in preference to disk, so a
    /// reopen would hand back the buffer that just lost the comparison and fail
    /// again on every tick, forever.
    ///
    /// It is also the only call that reads bytes this application did not write
    /// into a Note that is already open, which is why it is where conflict
    /// markers become `Suggestion` nodes.
    pub fn reload(&self) -> Result<NoteState, AppError> {
        let workspace_id = self.0.workspace.id().to_string();
        let note_id = self.0.note_id.clone();
        self.0.workspace.with_db(|conn| {
            conn.execute(
                "DELETE FROM drafts WHERE workspace_id = ?1 AND note_id = ?2",
                rusqlite::params![workspace_id, note_id],
            )?;
            Ok(())
        })?;

        let bytes = std::fs::read(&self.0.absolute_path).map_err(|e| {
            AppError::IoError(format!("read {}: {e}", self.0.absolute_path.display()))
        })?;
        let revision = content_hash(&bytes);
        let source = String::from_utf8_lossy(&bytes).into_owned();
        let dir = containing_dir(&self.0.note_id);
        let ParsedNote { ast, spans } = parse_note(&source, dir);
        let mut ast = match conflict_suggestions(&source, dir) {
            Some(resolved) => resolved,
            None => ast,
        };
        self.resolve_links(&mut ast)?;
        let metadata = derive_metadata(
            &self.0.note_id,
            &source,
            &spans,
            file_mtime(&self.0.absolute_path),
        );

        let mut state = self.lock_state()?;
        state.source = Arc::new(source);
        state.spans = Arc::new(spans);
        state.ast = Arc::new(ast);
        state.revision = revision;
        state.metadata = metadata;
        state.restored_from_draft = false;
        state.unwritten = false;
        state.session_edited = false;
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
    /// A failed flush aborts the close with the error and leaves the session,
    /// the draft row and the file exactly as they were. Committing bytes this
    /// application did not write, or clearing a row holding work that never
    /// reached disk, are both worse than a close the UI has to follow with a
    /// reload — which is the exit the contract routes every mismatch through.
    pub fn close(&self) -> Result<(), AppError> {
        let (edited, unwritten) = {
            let state = self.lock_state()?;
            (state.session_edited, state.unwritten)
        };
        if edited || unwritten {
            self.flush()?;
        }

        let mut committed = false;
        if edited {
            let message = self.commit_message()?;
            let commit = crate::git::operations::commit_paths(
                self.0.workspace.root(),
                &message,
                std::slice::from_ref(&self.0.relative_path),
            )?;
            committed = commit.is_some();
        }

        let workspace_id = self.0.workspace.id().to_string();
        let note_id = self.0.note_id.clone();
        self.0.workspace.with_db(|conn| {
            conn.execute(
                "DELETE FROM drafts WHERE workspace_id = ?1 AND note_id = ?2",
                rusqlite::params![workspace_id, note_id],
            )?;
            Ok(())
        })?;

        {
            let mut state = self.lock_state()?;
            state.closed = true;
            state.session_edited = false;
            state.unwritten = false;
        }
        registry()?.remove(&(self.0.workspace.id().to_string(), self.0.note_id.clone()));

        // Tier 4: the commit is what signals the scheduler, so a close that
        // committed nothing notifies nothing.
        if committed {
            notify_sync_activity();
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
pub fn pending_drafts(workspace: &Workspace) -> Result<Vec<NoteMetadata>, AppError> {
    workspace.with_db(|conn| {
        let mut stmt = conn.prepare(
            "SELECT n.id, n.path, n.title, n.last_modified, n.okf_conformant \
             FROM drafts d \
             JOIN notes n ON n.workspace_id = d.workspace_id AND n.id = d.note_id \
             WHERE d.workspace_id = ?1 \
             ORDER BY d.updated_at DESC",
        )?;
        let rows = stmt.query_map([workspace.id()], |row| {
            Ok(NoteMetadata {
                id: row.get(0)?,
                path: row.get(1)?,
                title: row.get(2)?,
                last_modified: row.get(3)?,
                snippet: None,
                okf_conformant: row.get(4)?,
            })
        })?;
        rows.collect::<Result<Vec<_>, _>>().map_err(AppError::from)
    })
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

struct DraftRow {
    raw_markdown: String,
    edit_seq: i64,
}

fn read_draft(
    conn: &Connection,
    workspace_id: &str,
    note_id: &str,
) -> Result<Option<DraftRow>, AppError> {
    conn.query_row(
        "SELECT raw_markdown, edit_seq FROM drafts WHERE workspace_id = ?1 AND note_id = ?2",
        rusqlite::params![workspace_id, note_id],
        |row| {
            Ok(DraftRow {
                raw_markdown: row.get(0)?,
                edit_seq: row.get(1)?,
            })
        },
    )
    .optional()
    .map_err(AppError::from)
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
fn atomic_write(path: &Path, bytes: &[u8]) -> Result<(), AppError> {
    static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);

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
        let mut file = std::fs::File::create(&temp)?;
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
    if let Err(e) = std::fs::rename(&temp, path) {
        let _ = std::fs::remove_file(&temp);
        return Err(io_error(path, &e));
    }
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

fn block_span(spans: &SpanMap, path: &[usize]) -> Result<std::ops::Range<usize>, AppError> {
    spans
        .block(path)
        .map(|block| block.source.clone())
        .ok_or_else(|| AppError::ParseError(format!("no Block at block_path {path:?}")))
}

/// The start of the first Block beginning at or after `span.end`, which is
/// where the separator following a Block ends.
fn next_block_start(spans: &SpanMap, span: &std::ops::Range<usize>) -> Option<usize> {
    spans
        .blocks()
        .filter(|block| block.source.start >= span.end)
        .map(|block| block.source.start)
        .min()
}

/// The end of the last Block ending at or before `span.start`.
fn previous_block_end(spans: &SpanMap, span: &std::ops::Range<usize>) -> Option<usize> {
    spans
        .blocks()
        .filter(|block| block.source.end <= span.start)
        .map(|block| block.source.end)
        .max()
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

fn derive_metadata(
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
/// source, so it does not address the Suggestion nodes. That is accepted rather
/// than overlooked: a conflicted Note is not editable until the Suggestion is
/// resolved, and Epic H owns that surface.
fn conflict_suggestions(source: &str, containing_dir: &str) -> Option<Vec<AstNode>> {
    if !source.contains("<<<<<<< ") {
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
                nodes.extend(parse_markdown_segment(&plain, containing_dir));
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
                    base_content: base
                        .take()
                        .map(|text| parse_markdown_segment(&text, containing_dir)),
                    local_content: parse_markdown_segment(&local, containing_dir),
                    incoming_content: parse_markdown_segment(&incoming, containing_dir),
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
    if !saw_conflict {
        return None;
    }
    nodes.extend(parse_markdown_segment(&plain, containing_dir));
    Some(nodes)
}

enum Section {
    Plain,
    Local,
    Base,
    Incoming,
}

fn parse_markdown_segment(source: &str, containing_dir: &str) -> Vec<AstNode> {
    if source.trim().is_empty() {
        return Vec::new();
    }
    if source.starts_with("---") {
        return parse_note(source, containing_dir).ast;
    }
    parse_markdown(source)
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

    fn edit_seq(&self) -> i64 {
        self.lock_state().unwrap().edit_seq
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

        fn draft(&self, note_id: &str) -> Option<DraftRow> {
            self.workspace
                .with_db(|conn| read_draft(conn, self.workspace.id(), note_id))
                .unwrap()
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
        f.workspace
            .with_db(|conn| {
                crate::index::scan::reindex_workspace_impl(conn, f.workspace.id())?;
                Ok(())
            })
            .unwrap();
        let session = f.open("a");
        session.update_block(&[0], "Unflushed.\n").unwrap();

        let pending = pending_drafts(&f.workspace).unwrap();

        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].id, "a");
        assert_eq!(pending[0].title, "Alpha");
        assert!(pending[0].okf_conformant);
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
}
