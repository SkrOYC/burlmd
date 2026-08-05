use std::sync::{Mutex, MutexGuard};

use flutter_rust_bridge::frb;

use crate::error::AppError;
use crate::markdown::AstNode;

/// The Core Engine's active-draft-state domain: the currently open note's
/// metadata/AST, and the in-memory cache + path-addressed mutation logic
/// `update_block` needs to apply keystroke-level edits without a disk or DB
/// round trip. Owned by this module rather than `api::ffi_api` per
/// `architecture/containers.md`'s Core Engine responsibility ("manages the
/// active draft state of open notes"), which is a distinct concern from the
/// FFI bridge — `api::ffi_api` re-exports these types and calls into this
/// module's functions, keeping its own `#[frb]` functions as thin wrappers.
#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteMetadata {
    /// OKF concept id: the bundle-relative path with `.md` removed.
    ///
    /// Carries no `workspace_id` alongside it, per the contract's rule 2:
    /// exactly one Workspace is active at a time and the Core owns which one
    /// (ADR-005 decision 7), so every row crossing this boundary belongs to
    /// it and a qualifier the UI could neither choose nor check was only ever
    /// a second source of truth for something the Core already knows.
    pub id: String,
    /// The same path with `.md` retained.
    pub path: String,
    pub title: String,
    pub last_modified: i64,
    /// Populated by search results only.
    pub snippet: Option<String>,
    /// False when the file has no frontmatter, when it does not parse, or when
    /// it parses without a non-empty `type` — OKF §11's first two conformance
    /// conditions, the second of which an implementation that only tries to
    /// parse will miss. Such a file is still fully usable; the flag exists so
    /// the UI can offer to bring it into conformance (CAP-PORT-03).
    pub okf_conformant: bool,
}

#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteState {
    pub ast: Vec<AstNode>,
    pub metadata: NoteMetadata,
    /// Content hash of the on-disk file (ADR-007 decision 7).
    ///
    /// **Not an input.** The Core holds this value and compares it itself
    /// before every tier 2 write, replacing it with the hash of what it just
    /// wrote after each success — see `workspace::persist`. It is exposed for
    /// display and diagnostics only, and no function on this boundary takes
    /// it back.
    pub base_revision: String,
    /// True when the working source was restored from the `drafts` table
    /// rather than read from disk — i.e. a previous session ended without
    /// tier 2 flushing (ADR-008 tier 1, CAP-WS-03).
    pub restored_from_draft: bool,
}

/// Holds the AST of the note currently open in the editor, kept in memory so
/// `update_block` can apply keystroke-level edits without a disk round trip.
/// Single-slot: this project's UI has exactly one active note at a time.
static ACTIVE_NOTE_CACHE: Mutex<Option<NoteState>> = Mutex::new(None);

pub fn active_note_cache() -> Result<MutexGuard<'static, Option<NoteState>>, AppError> {
    ACTIVE_NOTE_CACHE
        .lock()
        .map_err(|_| AppError::DatabaseError("active note cache poisoned".to_string()))
}

/// Descends `path` into `nodes`, replacing the addressed node with
/// `new_node`. Only `List`/`ListItem`/`Blockquote` hold nested `Vec<AstNode>`
/// and can be descended through; `Suggestion`'s three branches are
/// deliberately not addressable here (that's `resolve_suggestion`'s job).
pub fn set_node_at_path(
    nodes: &mut [AstNode],
    path: &[usize],
    new_node: AstNode,
) -> Result<(), AppError> {
    let (&idx, rest) = path
        .split_first()
        .ok_or_else(|| AppError::ParseError("empty block_path".to_string()))?;
    let node = nodes
        .get_mut(idx)
        .ok_or_else(|| AppError::ParseError(format!("block_path index {idx} out of range")))?;

    if rest.is_empty() {
        *node = new_node;
        return Ok(());
    }

    match node {
        AstNode::List { items, .. } => set_node_at_path(items, rest, new_node),
        AstNode::ListItem { content, .. } => set_node_at_path(content, rest, new_node),
        AstNode::Blockquote { nodes, .. } => set_node_at_path(nodes, rest, new_node),
        AstNode::Suggestion { .. } => Err(AppError::ParseError(
            "update_block cannot descend into Suggestion nodes; use resolve_suggestion".to_string(),
        )),
        _ => Err(AppError::ParseError(format!(
            "block_path continues past a leaf node at index {idx}"
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::markdown::{InlineElement, TextRun};

    // `set_node_at_path` is tested directly as a pure function rather than
    // through `update_block`, which reads/writes the process-wide
    // `ACTIVE_NOTE_CACHE` static: exercising that shared mutable state from
    // parallel test threads would make tests interfere with each other.
    fn text_paragraph(s: &str) -> AstNode {
        AstNode::Paragraph {
            content: vec![InlineElement::Text(TextRun {
                content: s.to_string(),
                bold: false,
                italic: false,
                strikethrough: false,
                code: false,
            })],
        }
    }

    #[test]
    fn set_node_at_path_replaces_a_top_level_node() {
        let mut nodes = vec![text_paragraph("a"), text_paragraph("b")];
        set_node_at_path(&mut nodes, &[1], text_paragraph("replaced")).unwrap();

        assert_eq!(nodes[0], text_paragraph("a"));
        assert_eq!(nodes[1], text_paragraph("replaced"));
    }

    #[test]
    fn set_node_at_path_descends_through_list_and_list_item() {
        let mut nodes = vec![AstNode::List {
            ordered: false,
            items: vec![AstNode::ListItem {
                content: vec![text_paragraph("original")],
                checked: None,
            }],
        }];

        set_node_at_path(&mut nodes, &[0, 0, 0], text_paragraph("edited")).unwrap();

        let AstNode::List { items, .. } = &nodes[0] else {
            panic!("expected a List node");
        };
        let AstNode::ListItem { content, .. } = &items[0] else {
            panic!("expected a ListItem node");
        };
        assert_eq!(content[0], text_paragraph("edited"));
    }

    #[test]
    fn set_node_at_path_descends_through_blockquote() {
        let mut nodes = vec![AstNode::Blockquote {
            nodes: vec![text_paragraph("original")],
        }];

        set_node_at_path(&mut nodes, &[0, 0], text_paragraph("edited")).unwrap();

        let AstNode::Blockquote { nodes: inner, .. } = &nodes[0] else {
            panic!("expected a Blockquote node");
        };
        assert_eq!(inner[0], text_paragraph("edited"));
    }

    #[test]
    fn set_node_at_path_rejects_an_empty_path() {
        let mut nodes = vec![text_paragraph("a")];
        let result = set_node_at_path(&mut nodes, &[], text_paragraph("x"));
        assert!(matches!(result, Err(AppError::ParseError(_))));
    }

    #[test]
    fn set_node_at_path_rejects_an_out_of_range_index() {
        let mut nodes = vec![text_paragraph("a")];
        let result = set_node_at_path(&mut nodes, &[5], text_paragraph("x"));
        assert!(matches!(result, Err(AppError::ParseError(_))));
    }

    #[test]
    fn set_node_at_path_rejects_descending_into_a_leaf_node() {
        let mut nodes = vec![text_paragraph("a")];
        // Paragraph has no nested Vec<AstNode> to descend into.
        let result = set_node_at_path(&mut nodes, &[0, 0], text_paragraph("x"));
        assert!(matches!(result, Err(AppError::ParseError(_))));
    }

    #[test]
    fn set_node_at_path_rejects_descending_into_a_suggestion() {
        let mut nodes = vec![AstNode::Suggestion {
            base_content: None,
            local_content: vec![text_paragraph("local")],
            incoming_content: vec![text_paragraph("incoming")],
        }];
        let result = set_node_at_path(&mut nodes, &[0, 0], text_paragraph("x"));
        assert!(matches!(result, Err(AppError::ParseError(_))));
    }
}
