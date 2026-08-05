//! Workspace lifecycle: bootstrap (init/open), Note & Directory CRUD, atomic
//! write, and the ADR-008 persistence tiers (`guidelines.md`'s module map).
//! `WSPC-D004` establishes this module and owns [`bootstrap`]; later tickets
//! in this epic add `lifecycle` and `persist` alongside it.

pub mod bootstrap;
pub mod lifecycle;
/// The prose half of `WSPC-D006`'s inbound-Link rewrite. Private to this
/// module: [`lifecycle`] is the only legitimate caller, because rewriting a
/// Note's bytes outside the operation that also moves its index rows and its
/// open session is exactly the partial update `architecture/risks.md` risk 8
/// forbids.
mod links_rewrite;
pub mod persist;

pub use bootstrap::{default_workspace_dir, WorkspaceInfo};
pub use lifecycle::{IdRemap, LifecycleEffects};
pub use persist::{NoteSession, NoteWriteStatus, Workspace};

/// The prefix [`lifecycle`]'s `FileJournal` parks a deletion under.
pub(crate) const TRASH_PREFIX: &str = ".burlmd-trash.";

/// The `.gitignore` patterns covering every file burlmd puts *inside* a bundle
/// that is not bundle content: `FileJournal`'s trash entries
/// (`.burlmd-trash.{name}.{pid}.{n}`) and [`persist::atomic_write`]'s temporary
/// files (`.{name}.{pid}.{n}.tmp`).
///
/// Both are removed on the ordinary path — by `commit`/`rollback` and by the
/// rename respectively — and both survive a `SIGKILL` or a power loss, because
/// neither `Drop` nor any other cleanup runs then. What survives is plaintext:
/// a trash entry holds the entire content of a Note that was just deleted, and
/// a temporary file holds a Note as it was mid-write. `git::operations`'
/// commits are whole-worktree snapshots, so an untracked file left inside the
/// bundle is a file the next commit publishes — and, once a Remote is
/// connected, pushes. Ignoring them is what stops that.
///
/// `.*.tmp` rather than a pattern spelling out the pid and counter: it is
/// readable in a file the user may open, and a dot-prefixed `.tmp` inside a
/// bundle is not content either way — `index::scan::walk_bundle` already skips
/// every dot-prefixed entry, so nothing this matches was ever a Note.
pub(crate) const SCRATCH_IGNORE_PATTERNS: [&str; 2] = [".burlmd-trash.*", ".*.tmp"];

/// True when `name` is one of burlmd's own scratch files rather than bundle
/// content — see [`SCRATCH_IGNORE_PATTERNS`] for what makes these two families
/// special and why they are swept at open.
pub(crate) fn is_scratch_name(name: &str) -> bool {
    name.starts_with(TRASH_PREFIX) || (name.starts_with('.') && name.ends_with(".tmp"))
}
