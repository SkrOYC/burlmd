pub mod ast;
pub mod parser;

pub use ast::{AstNode, InlineElement, TextRun};
pub use parser::parse_markdown;
