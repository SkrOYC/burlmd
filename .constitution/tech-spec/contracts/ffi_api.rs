// Raw Rust interface contract exposed to Flutter via flutter_rust_bridge.
// This defines the exact shapes passing over the FFI boundary.

use flutter_rust_bridge::frb;

#[frb]
pub struct NoteMetadata {
    pub id: String,
    pub path: String,
    pub title: String,
    pub last_modified: i64,
}

// ---------------------------------------------------------------------------
// Abstract Syntax Tree (AST) Definition
// ---------------------------------------------------------------------------

#[frb]
pub enum TextFormat {
    Normal,
    Bold,
    Italic,
    Strikethrough,
    InlineCode,
}

#[frb]
pub struct TextRun {
    pub text: String,
    pub format: TextFormat,
}

#[frb]
pub enum InlineElement {
    Text(TextRun),
    Link { text: String, target_note_id: String },
    ExternalLink { text: String, url: String },
}

#[frb]
pub enum AstNode {
    Heading { level: u8, content: Vec<InlineElement> },
    Paragraph { content: Vec<InlineElement> },
    List { ordered: bool, items: Vec<AstNode> },
    ListItem { content: Vec<InlineElement>, checked: Option<bool> },
    Blockquote { nodes: Vec<AstNode> },
    CodeBlock { language: Option<String>, code: String },
    Image { alt_text: String, absolute_path: String },
    
    /// Represents a pending Git conflict that the user must resolve.
    /// Rendered as a Google-Docs style margin suggestion.
    Suggestion { 
        base_content: Vec<AstNode>, 
        incoming_content: Vec<AstNode> 
    },
}

#[frb]
pub struct NoteState {
    pub id: String,
    pub is_dirty: bool,
    pub nodes: Vec<AstNode>,
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
    IoError(String),
    ParseError(String),
}

/// Authenticates via OAuth and returns a Workspace ID
#[frb]
pub async fn authenticate_workspace(provider: String, auth_code: String) -> Result<String, AppError> {
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
pub fn update_block(note_id: String, block_path: Vec<usize>, raw_markdown: String) -> Result<NoteState, AppError> {
    unimplemented!()
}

#[frb(sync)]
pub fn resolve_suggestion(note_id: String, block_path: Vec<usize>, keep_incoming: bool) -> Result<NoteState, AppError> {
    unimplemented!()
}

#[frb(sync)]
pub fn save_note(note_id: String) -> Result<(), AppError> {
    unimplemented!()
}

#[frb]
pub async fn search_notes(query: String) -> Result<Vec<NoteMetadata>, AppError> {
    unimplemented!()
}
