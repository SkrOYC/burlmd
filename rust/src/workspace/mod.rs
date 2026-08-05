//! Workspace lifecycle: bootstrap (init/open), Note & Directory CRUD, atomic
//! write, and the ADR-008 persistence tiers (`guidelines.md`'s module map).
//! `WSPC-D004` establishes this module and owns [`bootstrap`]; later tickets
//! in this epic add `lifecycle` and `persist` alongside it.

pub mod bootstrap;

pub use bootstrap::{default_workspace_dir, WorkspaceInfo};
