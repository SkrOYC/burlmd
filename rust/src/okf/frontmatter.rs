//! Reading and validating a Note's YAML frontmatter block.
//!
//! `data-models/okf-bundle.md` and `okf-frontmatter.schema.json` are the
//! governing contracts. OKF §11 states three conformance conditions for a
//! bundle; this module implements the first two of them for a single Note: a
//! parseable frontmatter block containing a non-empty `type`. (The third
//! constrains the structure of `index.md`/`log.md` when present; burlmd
//! generates neither, per ADR-004 decision 6.)
//!
//! A file failing either condition -- no frontmatter, unparseable
//! frontmatter, or frontmatter that parses without a non-empty `type` -- is
//! reported non-conformant, **not** rejected: CAP-WS-05 (opening a foreign
//! Workspace) and CAP-PORT-03 (tolerating files external tools wrote) both
//! depend on that. This is also, per the schema's own framing, the case a
//! naive implementation gets wrong: a block containing only `title:` parses
//! perfectly and is still non-conformant, because `type` -- not parseability
//! alone -- is what §11 conditions on.
//!
//! This module never writes or re-serializes the block (ADR-007 decision 5).
//! It reports which unmanaged keys are present so the caller can decide what
//! to surface, but preservation of their bytes is achieved simply by never
//! touching the span they occupy -- not by round-tripping through this
//! struct.

use pulldown_cmark::{Event, MetadataBlockKind, Options, Parser, Tag, TagEnd};
use saphyr::{LoadableYamlNode, Yaml};

/// The two frontmatter keys burlmd itself reads and writes (ADR-004
/// decision 3). Everything else found in the block is reported by name only,
/// in [`Frontmatter::other_keys`].
const MANAGED_KEYS: [&str; 2] = ["type", "title"];

/// The result of reading a Note's frontmatter block.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Frontmatter {
    /// The `type` value, when the block parsed and the key was present with
    /// a string value -- regardless of whether that value is empty. Use
    /// [`Frontmatter::is_conformant`], not a bare presence check, to apply
    /// OKF §11's actual rule.
    pub note_type: Option<String>,
    /// The `title` value, when present. OKF §4.1 makes this recommended, not
    /// required, so its absence never affects conformance.
    pub title: Option<String>,
    /// Names of keys present in the block that burlmd does not itself
    /// manage (e.g. `tags`, `description`, `status`).
    pub other_keys: Vec<String>,
}

impl Frontmatter {
    /// OKF §11's second conformance condition, applied to this Note: a
    /// non-empty `type`. This is the one condition parsing alone cannot
    /// establish -- a block containing only `title:` parses cleanly and is
    /// still non-conformant, which is why this is a method rather than
    /// `note_type.is_some()`.
    pub fn is_conformant(&self) -> bool {
        matches!(&self.note_type, Some(t) if !t.is_empty())
    }
}

/// Reads and validates the frontmatter block at the start of `source`, a
/// Note's full Markdown text. Never fails: absence, a parse error, and a
/// present-but-empty `type` all produce a [`Frontmatter`] whose
/// [`Frontmatter::is_conformant`] returns `false`, per the module-level
/// contract above.
pub fn read_frontmatter(source: &str) -> Frontmatter {
    let Some(yaml_text) = extract_yaml_block(source) else {
        return Frontmatter::default();
    };

    // saphyr is a full YAML 1.2 parser, not hand-rolled extraction -- OKF
    // §11 makes parseability itself the conformance test, so a block that
    // fails to parse here is genuinely non-conformant, not a bug to work
    // around.
    let Ok(docs) = Yaml::load_from_str(&yaml_text) else {
        return Frontmatter::default();
    };
    let Some(doc) = docs.first() else {
        return Frontmatter::default();
    };
    // A block that parses as YAML but not as a mapping (e.g. a bare scalar)
    // has no keys to read -- `as_mapping_get` already returns `None` for a
    // non-mapping node, so `note_type`/`title` fall out `None` naturally.
    // `other_keys` needs the mapping explicitly to enumerate its keys.
    let other_keys = match doc.as_mapping() {
        Some(mapping) => mapping
            .keys()
            .filter_map(|k| k.as_str())
            .filter(|k| !MANAGED_KEYS.contains(k))
            .map(str::to_string)
            .collect(),
        None => Vec::new(),
    };

    Frontmatter {
        note_type: doc
            .as_mapping_get("type")
            .and_then(|v| v.as_str())
            .map(str::to_string),
        title: doc
            .as_mapping_get("title")
            .and_then(|v| v.as_str())
            .map(str::to_string),
        other_keys,
    }
}

/// Locates the frontmatter block via `pulldown-cmark`'s
/// `ENABLE_YAML_STYLE_METADATA_BLOCKS` option and returns its raw YAML text
/// (delimiters stripped), or `None` when the document opens with no such
/// block. Never hand-rolls YAML-block detection -- the STOP condition on
/// this ticket forbids substituting parser logic of our own for what
/// `pulldown-cmark` already recognizes.
fn extract_yaml_block(source: &str) -> Option<String> {
    let mut options = Options::empty();
    options.insert(Options::ENABLE_YAML_STYLE_METADATA_BLOCKS);
    let parser = Parser::new_ext(source, options);
    for event in parser {
        match event {
            Event::Start(Tag::MetadataBlock(MetadataBlockKind::YamlStyle)) => {}
            Event::Text(text) => return Some(text.to_string()),
            Event::End(TagEnd::MetadataBlock(_)) => return None,
            _ => return None,
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frontmatter_with_type_and_title_is_conformant() {
        let source = "---\ntype: Note\ntitle: burlmd\n---\n\n# burlmd\n";
        let fm = read_frontmatter(source);
        assert_eq!(fm.note_type.as_deref(), Some("Note"));
        assert_eq!(fm.title.as_deref(), Some("burlmd"));
        assert!(fm.is_conformant());
    }

    #[test]
    fn unmanaged_keys_are_reported_present() {
        let source =
            "---\ntype: Note\ntitle: burlmd\ntags:\n  - a\n  - b\nstatus: draft\n---\n\nBody.\n";
        let fm = read_frontmatter(source);
        assert!(fm.other_keys.contains(&"tags".to_string()));
        assert!(fm.other_keys.contains(&"status".to_string()));
        assert!(!fm.other_keys.contains(&"type".to_string()));
        assert!(!fm.other_keys.contains(&"title".to_string()));
    }

    #[test]
    fn missing_frontmatter_is_non_conformant_not_rejected() {
        let source = "# Just a heading\n\nNo frontmatter here.\n";
        let fm = read_frontmatter(source);
        assert_eq!(fm.note_type, None);
        assert!(!fm.is_conformant());
    }

    #[test]
    fn frontmatter_that_parses_cleanly_without_type_is_non_conformant() {
        // The case a naive "did it parse?" implementation gets wrong: this
        // block is perfectly valid YAML, so a parseability check alone
        // reports it conformant. OKF §11's second condition -- a non-empty
        // `type` -- is what actually applies here, and this block has none.
        let source = "---\ntitle: Untyped Note\n---\n\nBody.\n";
        let fm = read_frontmatter(source);
        assert_eq!(fm.note_type, None);
        assert_eq!(fm.title.as_deref(), Some("Untyped Note"));
        assert!(!fm.is_conformant());
    }

    #[test]
    fn frontmatter_with_empty_type_is_non_conformant() {
        let source = "---\ntype: \"\"\ntitle: x\n---\n\nBody.\n";
        let fm = read_frontmatter(source);
        assert_eq!(fm.note_type.as_deref(), Some(""));
        assert!(!fm.is_conformant());
    }

    #[test]
    fn unparseable_frontmatter_is_non_conformant_not_rejected() {
        // Unterminated flow sequence: invalid YAML, but must not panic or
        // propagate an error -- the file is still fully usable.
        let source = "---\ntype: [unterminated\n---\n\nBody.\n";
        let fm = read_frontmatter(source);
        assert_eq!(fm.note_type, None);
        assert!(!fm.is_conformant());
    }

    #[test]
    fn unterminated_block_with_no_closing_delimiter_is_non_conformant() {
        let source = "---\ntype: Note\n\n# heading with no closing delimiter\n";
        let fm = read_frontmatter(source);
        assert_eq!(fm.note_type, None);
        assert!(!fm.is_conformant());
    }
}
