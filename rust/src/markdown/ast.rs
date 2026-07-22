use flutter_rust_bridge::frb;

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
