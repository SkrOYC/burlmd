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

/// True when `name` is covered by [`SCRATCH_IGNORE_PATTERNS`], and therefore
/// **untracked by construction** — which is the only thing a caller staging
/// paths for a commit needs to know about it.
///
/// Deliberately as broad as the patterns themselves, including the foreign
/// `.anything.tmp` they also cover. Ignoring a file this application did not
/// write costs nothing; *staging* one that Git is configured to ignore is what
/// the patterns exist to prevent, so the predicate that decides what to stage
/// has to match the patterns rather than burlmd's narrower own shapes.
///
/// [`is_burlmd_scratch_name`] is the other half of this pair and is the one to
/// use before **removing** anything.
pub(crate) fn is_ignored_scratch_name(name: &str) -> bool {
    name.starts_with(TRASH_PREFIX) || (name.starts_with('.') && name.ends_with(".tmp"))
}

/// True when `name` is one of burlmd's own scratch files — a `FileJournal`
/// trash entry or an [`persist::atomic_write`] temporary — rather than bundle
/// content, judged strictly enough to *delete* what it matches.
///
/// This is narrower than [`is_ignored_scratch_name`] on purpose, and the
/// asymmetry is the point. `bootstrap::sweep_scratch_files` removes what this
/// matches, recursively for a directory, from a bundle that may well be another
/// tool's (CAP-WS-05) — so a predicate reading "any dot-prefixed `.tmp`" made
/// opening a foreign Workspace delete `.vim.tmp`, `.cache.tmp`, or a whole
/// `.build.tmp/` tree that burlmd never created. `converge`'s own documentation
/// says the sweep removes files that are "burlmd's, not the bundle's"; this is
/// what makes that true.
///
/// The temporary form is `.{stem}.{pid}.{n}.tmp` ([`persist::atomic_write`]),
/// so both trailing components must be numeric and a stem must precede them.
/// The trash form needs no such test: [`TRASH_PREFIX`] is distinctive on its
/// own.
pub(crate) fn is_burlmd_scratch_name(name: &str) -> bool {
    if name.starts_with(TRASH_PREFIX) {
        return true;
    }
    let Some(rest) = name.strip_prefix('.').and_then(|n| n.strip_suffix(".tmp")) else {
        return false;
    };
    let Some((rest, counter)) = rest.rsplit_once('.') else {
        return false;
    };
    let Some((stem, pid)) = rest.rsplit_once('.') else {
        return false;
    };
    !stem.is_empty() && is_decimal(pid) && is_decimal(counter)
}

fn is_decimal(text: &str) -> bool {
    !text.is_empty() && text.bytes().all(|b| b.is_ascii_digit())
}

/// What one directory entry is, as far as **every** walker over a bundle is
/// concerned. See [`classify_entry`] for why there is only one of these.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum BundleEntry {
    /// A real directory on this filesystem, and therefore the only thing a
    /// walker may descend into.
    Directory,
    /// A regular file — or anything else that is neither a directory nor a
    /// link, which for a walker's purposes is the same thing: a leaf.
    File,
    /// A symbolic link, of any target kind. Never followed, never descended
    /// into, and never resolved to the thing it points at.
    Symlink,
}

/// Classifies one directory entry for the three walkers this crate runs over a
/// bundle: [`lifecycle::collect_files`](lifecycle), which names a renamed
/// Directory's contents for a commit; `index::scan::walk_dir`, which finds the
/// Notes to index; and [`bootstrap::sweep_scratch_files`](bootstrap), which
/// removes this application's own leftovers.
///
/// # Why one definition rather than three predicates
///
/// All three used to decide "is this a directory?" for themselves, and they
/// arrived at three different answers. `collect_files` asked `Path::is_dir()`,
/// which **follows** the link: a symlink inside a renamed subtree therefore had
/// its *target's* contents named in the pathspec, so `commit_paths` read the
/// bytes on the far end of the link — anywhere on the filesystem, outside the
/// bundle entirely — and staged them into the bundle's history. A link pointing
/// at its own ancestor recursed until the kernel returned `ELOOP`, staging the
/// same files once per level on the way. Neither is a hypothetical: a bundle is
/// an ordinary directory a user can put anything in
/// (`data-models/okf-bundle.md`).
///
/// The other two happened to be right, and that is precisely the problem — three
/// separate spellings of a policy that has to hold everywhere is three chances
/// to get it wrong again. So the policy is stated once, here: **`file_type`
/// comes from [`std::fs::DirEntry::file_type`], which does not follow links, and
/// a link is a leaf.** Passing a `Metadata`-derived `FileType` would defeat it,
/// because `std::fs::metadata` resolves the link before reporting the kind.
///
/// What each caller *does* with a [`BundleEntry::Symlink`] is still its own
/// decision — the scratch sweep unlinks one whose name matches, the scan ignores
/// it, `collect_files` leaves it out of the pathspec — and only the "never
/// follow it" half is shared.
pub(crate) fn classify_entry(file_type: &std::fs::FileType) -> BundleEntry {
    if file_type.is_symlink() {
        BundleEntry::Symlink
    } else if file_type.is_dir() {
        BundleEntry::Directory
    } else {
        BundleEntry::File
    }
}
