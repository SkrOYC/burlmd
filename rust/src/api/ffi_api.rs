use flutter_rust_bridge::frb;

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
pub struct TextRun {
    pub content: String,
    pub bold: bool,
    pub italic: bool,
    pub strikethrough: bool,
    pub code: bool,
}

#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InlineElement {
    Text(TextRun),
    /// A lateral link to another note `[[title]]`
    Link {
        target_title: String,
        resolved_note_id: Option<String>,
        content: Vec<InlineElement>,
    },
    /// A standard markdown link `[text](url)`
    ExternalLink {
        url: String,
        content: Vec<InlineElement>,
    },
}

#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AstNode {
    Heading {
        level: u8,
        content: Vec<InlineElement>,
    },
    Paragraph {
        content: Vec<InlineElement>,
    },
    List {
        ordered: bool,
        items: Vec<AstNode>,
    },
    ListItem {
        content: Vec<AstNode>,
        checked: Option<bool>,
    },
    Blockquote {
        nodes: Vec<AstNode>,
    },
    CodeBlock {
        language: Option<String>,
        code: String,
    },
    ThematicBreak,
    Image {
        alt_text: String,
        url_or_path: String,
    },
    /// Represents a pending Git conflict that the user must resolve.
    Suggestion {
        base_content: Option<Vec<AstNode>>,
        local_content: Vec<AstNode>,
        incoming_content: Vec<AstNode>,
    },
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

    let metadata = NoteMetadata {
        id: path.clone(),
        workspace_id: "default".to_string(),
        path: path.clone(),
        title,
        last_modified: 0,
        snippet: None,
    };

    Ok(NoteState {
        ast,
        metadata,
        base_revision: "head".to_string(),
    })
}
