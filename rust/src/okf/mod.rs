//! Open Knowledge Format v0.2 bundle domain (ADR-004, `data-models/okf-bundle.md`).
//!
//! Three independent pieces of the on-disk contract live here:
//!
//! - [`frontmatter`]: reads and validates a Note's YAML frontmatter block
//!   against OKF §11's conformance rule, without ever writing or
//!   re-serializing it (ADR-007 decision 5).
//! - [`concept_id`]: the bidirectional mapping between a bundle-relative path
//!   and a Note's OKF concept id (§2), and the reserved-filename rule (§3.1).
//! - [`links`]: classifies a parsed Markdown link destination as internal or
//!   external, and serializes a concept id into the angle-bracket-wrapped,
//!   escaped destination form burlmd writes.
//!
//! Nothing in this module touches the filesystem, the index, or the parser's
//! block-level AST -- it is pure domain logic over strings, consumed by
//! `workspace` and `index` in later tickets.

pub mod concept_id;
pub mod frontmatter;
pub mod links;

pub use concept_id::{concept_id_to_path, is_reserved_title, path_to_concept_id};
pub use frontmatter::{read_frontmatter, Frontmatter};
pub use links::{classify, resolve_bundle_path, serialize_destination, serialize_link, LinkTarget};
