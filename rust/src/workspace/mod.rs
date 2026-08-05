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
