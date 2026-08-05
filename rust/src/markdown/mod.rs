//! Markdown parsing and span-preserving source splicing (ADR-007).
//!
//! [`parser`] produces an [`AstNode`] tree and, in the same pass, the
//! [`spans::SpanMap`] that records where each Block came from. [`splice`]
//! substitutes new source text over one Block's span and reparses. The span
//! map is Core-side state and never crosses the FFI boundary.

pub mod ast;
pub mod parser;
pub mod spans;
pub mod splice;

pub use ast::{AstNode, InlineElement, TextRun};
pub use parser::{parse_markdown, parse_note, ParsedNote};
pub use spans::{
    rendered_text, BlockPath, BlockSpan, InlineRun, RenderedRange, SourceResolution, SpanMap,
};
pub use splice::{
    extract_range, resolve_range, splice_block, splice_range, splice_source, SpliceError,
    SplicedNote,
};
