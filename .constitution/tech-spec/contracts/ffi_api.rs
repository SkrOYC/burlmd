// Raw Rust interface contract exposed to Flutter via flutter_rust_bridge.
// This defines the exact shapes passing over the FFI boundary.

use flutter_rust_bridge::frb;

#[frb]
pub struct NoteMetadata {
    pub id: String,
    pub workspace_id: String,
    pub path: String,
    pub title: String,
    pub last_modified: i64,
    pub snippet: Option<String>,
}

// ---------------------------------------------------------------------------
// Abstract Syntax Tree (AST) Definition
// ---------------------------------------------------------------------------

#[frb]
pub struct TextRun {
    pub content: String,
    pub bold: bool,
    pub italic: bool,
    pub strikethrough: bool,
    pub code: bool,
}

#[frb]
pub enum InlineElement {
    Text(TextRun),
    /// A lateral link to another note `[[title]]`
    Link { target_title: String, resolved_note_id: Option<String>, content: Vec<InlineElement> },
    /// A standard markdown link `[text](url)`
    ExternalLink { url: String, content: Vec<InlineElement> },
}

#[frb]
pub enum AstNode {
    Heading { level: u8, content: Vec<InlineElement> },
    Paragraph { content: Vec<InlineElement> },
    List { ordered: bool, items: Vec<AstNode> },
    ListItem { content: Vec<AstNode>, checked: Option<bool> },
    Blockquote { nodes: Vec<AstNode> },
    CodeBlock { language: Option<String>, code: String },
    Image { alt_text: String, url_or_path: String },
    
    /// Represents a pending Git conflict that the user must resolve.
    /// Rendered as a Google-Docs style margin suggestion.
    Suggestion { 
        base_content: Option<Vec<AstNode>>, 
        local_content: Vec<AstNode>,
        incoming_content: Vec<AstNode> 
    },
}

#[frb]
pub struct NoteState {
    pub ast: Vec<AstNode>,
    pub metadata: NoteMetadata,
    pub base_revision: String,
}

// ---------------------------------------------------------------------------
// Synchronous & Asynchronous Interface Methods
// ---------------------------------------------------------------------------

#[frb]
pub enum AppError {
    DiskFull,
    AuthExpired,
    GitConflict,
    DatabaseError(String),
    CryptoError(String),
    NetworkError(String),
    OAuthError(String),
    IoError(String),
    ParseError(String),
}

/// Authenticates via OAuth and returns a Workspace ID
#[frb]
pub async fn authenticate_workspace(provider: String, auth_code: String, code_verifier: String) -> Result<String, AppError> {
    unimplemented!()
}

#[frb(sync)] 
pub fn open_note(path: String) -> Result<NoteState, AppError> {
    unimplemented!()
}

#[frb(sync)] 
pub fn open_note_by_id(note_id: String) -> Result<NoteState, AppError> {
    unimplemented!()
}

#[frb(sync)]
pub fn update_block(note_id: String, block_path: Vec<usize>, new_node: AstNode) -> Result<NoteState, AppError> {
    unimplemented!()
}

#[frb(sync)]
pub fn insert_block(note_id: String, block_path: Vec<usize>, new_node: AstNode) -> Result<NoteState, AppError> {
    unimplemented!()
}

#[frb(sync)]
pub fn delete_block(note_id: String, block_path: Vec<usize>) -> Result<NoteState, AppError> {
    unimplemented!()
}

#[frb(sync)]
pub fn resolve_suggestion(note_id: String, block_path: Vec<usize>, resolved_node: AstNode) -> Result<NoteState, AppError> {
    unimplemented!()
}

#[frb(sync)]
pub fn save_note(note_id: String, expected_base_revision: String) -> Result<(), AppError> {
    unimplemented!()
}

#[frb]
pub async fn search_notes(query: String) -> Result<Vec<NoteMetadata>, AppError> {
    unimplemented!()
}
