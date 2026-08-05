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
    /// A Link to another Note. On disk this is a standard bundle-absolute
    /// Markdown link with an angle-bracket-wrapped destination,
    /// `[text](</dir/note.md>)` (ADR-004 decision 5, OKF §6.1) — the `[[`
    /// sequence is a UI trigger only and is never stored.
    Link {
        /// The target's OKF concept id, as `okf::links::classify` derived it
        /// from the parsed destination. Always present, even when nothing
        /// matches it.
        target_id: String,
        /// False for a ghost Link — a Link to a Note not yet created, which
        /// OKF §6.1 requires consumers to tolerate and which CAP-GRAPH-04
        /// makes a feature.
        ///
        /// Resolving this requires the index, not the parser: it is whether
        /// `target_id` matches a `notes` row. `WSPC-D003` declares the field
        /// and sits upstream of the indexer, so it leaves the field `false`
        /// and `WSPC-D005` populates it.
        ///
        /// **Advisory, and only as fresh as the state it came from.** Creating
        /// or deleting a Note flips it for every inbound Link in every other
        /// Note, so the follow path must re-resolve against the index rather
        /// than trust the flag; what it is *for* is rendering.
        exists: bool,
        content: Vec<InlineElement>,
    },
    /// Any link that is not an internal Note reference: it has a URL scheme,
    /// or does not end in `.md`.
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
