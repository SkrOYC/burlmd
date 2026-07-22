use flutter_rust_bridge::frb;

// AST types are owned by the `markdown` domain module (parsing is what
// produces and shapes them); re-exported here so they cross the FFI
// boundary FRB scans (`rust_input: crate::api`) without `markdown`
// having to depend back on this module for its own output types.
pub use crate::markdown::{AstNode, InlineElement, TextRun};

#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteMetadata {
    pub id: String,
    pub workspace_id: String,
    pub path: String,
    pub title: String,
    pub last_modified: i64,
    pub snippet: Option<String>,
}

#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteState {
    pub ast: Vec<AstNode>,
    pub metadata: NoteMetadata,
    pub base_revision: String,
}

#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
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

#[frb(sync)]
pub fn open_note(path: String) -> Result<NoteState, AppError> {
    let content = std::fs::read_to_string(&path).map_err(|e| AppError::IoError(e.to_string()))?;

    let path_obj = std::path::Path::new(&path);
    let title = path_obj
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("Untitled")
        .to_string();

    let ast = crate::markdown::parse_markdown(&content);

    let last_modified = std::fs::metadata(&path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    let metadata = NoteMetadata {
        id: path.clone(),
        workspace_id: "default".to_string(),
        path: path.clone(),
        title,
        last_modified,
        snippet: None,
    };

    Ok(NoteState {
        ast,
        metadata,
        base_revision: "head".to_string(),
    })
}
