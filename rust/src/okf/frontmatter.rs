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
//!
//! A block is also treated as non-conformant, rather than being handed to
//! `saphyr`'s loader at all, when it exceeds [`MAX_FRONTMATTER_BYTES`] or
//! contains a YAML alias reference (see [`contains_alias_reference`]). Both
//! are untrusted-input bounds: `read_frontmatter` runs on a foreign
//! bundle's files (CAP-WS-05, CAP-PORT-03) and, from `WSPC-D005` onward, on
//! every indexed Note, so "never fails" has to mean it in the presence of a
//! deliberately hostile or merely corrupted block, not only a well-formed
//! one.

use pulldown_cmark::{Event, MetadataBlockKind, Options, Parser, Tag, TagEnd};
use saphyr::{LoadableYamlNode, Yaml};
use saphyr_parser::{Event as YamlEvent, Parser as YamlParser};

/// The two frontmatter keys burlmd itself reads and writes (ADR-004
/// decision 3). Everything else found in the block is reported by name only,
/// in [`Frontmatter::other_keys`].
const MANAGED_KEYS: [&str; 2] = ["type", "title"];

/// A generous ceiling on the raw byte length of a frontmatter block, applied
/// before it is handed to `saphyr`. Every field `okf-frontmatter.schema.json`
/// documents is a handful of short scalars, small lists of scalars, or a
/// small nested trust/provenance object -- nothing in the advisory schema
/// approaches this size -- so a block this large is either corrupted or
/// hostile, and reporting it non-conformant costs nothing a legitimate Note
/// would ever pay. This bound is defense-in-depth, not the fix for the
/// attack below: it is sized to reject a block that is large because its
/// *source text* is large, which the alias check does not, by itself, rule
/// out.
const MAX_FRONTMATTER_BYTES: usize = 64 * 1024;

/// A generous ceiling on the number of raw parse events read while
/// pre-scanning a block for aliases (see [`contains_alias_reference`]).
/// Sized well above anything a legitimate frontmatter block -- a flat
/// mapping of a dozen or so scalars and short lists -- could ever produce,
/// so this only ever fires on a block that is already going to be rejected
/// by the byte cap, the alias check, or both; it exists so pre-scanning
/// itself can never be the unbounded operation.
const MAX_PRESCAN_EVENTS: usize = 4096;

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
/// Note's full Markdown text. Never fails: absence, a parse error, an
/// oversized or alias-bearing block (see [`contains_alias_reference`]), and
/// a present-but-empty `type` all produce a [`Frontmatter`] whose
/// [`Frontmatter::is_conformant`] returns `false`, per the module-level
/// contract above.
pub fn read_frontmatter(source: &str) -> Frontmatter {
    let Some(yaml_text) = extract_yaml_block(source) else {
        return Frontmatter::default();
    };
    if yaml_text.len() > MAX_FRONTMATTER_BYTES {
        return Frontmatter::default();
    }
    if contains_alias_reference(&yaml_text) {
        return Frontmatter::default();
    }

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

/// True when `yaml_text` contains a YAML alias reference (`*anchor`)
/// anywhere in the document.
///
/// This closes an allocation-exhaustion path in `saphyr`'s convenience
/// loader (`Yaml::load_from_str`, used by [`read_frontmatter`] once this
/// check passes): `YamlLoader` resolves each alias by *cloning* the
/// subtree its anchor names, so a small chain of anchors that each alias
/// the previous one several times -- the classic "billion laughs" shape --
/// clones exponentially rather than linearly in the source text's size. A
/// 432-byte, 9-level block of this shape was measured driving the process
/// to an allocation failure -- `handle_alloc_error`, which aborts rather
/// than unwinding, so it cannot be caught with `catch_unwind` and would
/// otherwise defeat this function's own "never fails" contract. Because the
/// malicious block is small, [`MAX_FRONTMATTER_BYTES`] alone does not catch
/// it; only this check does.
///
/// This does not hand-roll YAML parsing -- the STOP condition on this
/// ticket forbids that. It walks the exact token stream `saphyr`'s own
/// loader consumes, via `saphyr_parser::Parser` (the crate `saphyr` itself
/// is built on and re-exports transitively), and stops at the first
/// `Alias` token -- before any node is materialized or cloned, which is
/// what makes this safe to run unconditionally rather than a mitigation
/// that only reduces the blast radius.
///
/// A frontmatter block never legitimately needs an anchor or alias:
/// `okf-frontmatter.schema.json`'s properties are flat scalars, short lists
/// of scalars, or small nested objects with no repeated substructure, so
/// rejecting any block that uses one costs no real Note its conformance.
fn contains_alias_reference(yaml_text: &str) -> bool {
    let parser = YamlParser::new_from_str(yaml_text);
    for (event_count, event) in parser.enumerate() {
        if event_count >= MAX_PRESCAN_EVENTS {
            return true;
        }
        match event {
            Ok((YamlEvent::Alias(_), _)) => return true,
            Ok(_) => {}
            // A scan error here will be reported identically by the real
            // load in `read_frontmatter` (non-conformant either way), so
            // let that path own producing it rather than duplicating the
            // decision here.
            Err(_) => return false,
        }
    }
    false
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

    #[test]
    fn a_single_alias_reference_is_non_conformant_not_loaded() {
        // The minimal fixture that proves the guard fires: one anchor, one
        // alias to it. This is not a real "billion laughs" payload -- it
        // would take many more nested levels to actually exhaust memory --
        // deliberately, so this test stays small and fast rather than
        // spending its own time or memory reproducing an exponential
        // expansion. `contains_alias_reference` rejects the block on the
        // first `Alias` token it sees, before `saphyr`'s loader ever runs,
        // so a `type` present elsewhere in the same block is irrelevant:
        // the whole block is treated as unparseable.
        let source = "---\ntype: Note\na: &a [1, 2, 3]\nb: [*a, *a]\n---\n\nBody.\n";
        let fm = read_frontmatter(source);
        assert_eq!(fm.note_type, None);
        assert!(!fm.is_conformant());
    }

    #[test]
    fn alias_bomb_shaped_block_is_non_conformant_not_aborted() {
        // The actual shape measured aborting the process pre-fix: 9 levels,
        // each an anchor aliasing the previous level 9 times. Safe to
        // construct here at full scale -- ~430 bytes, well under
        // `MAX_FRONTMATTER_BYTES` -- because `contains_alias_reference`
        // stops at the *first* `Alias` token (in level 1) rather than
        // letting `saphyr`'s loader clone its way through all nine, so this
        // test runs in microseconds rather than exhausting memory.
        let mut yaml = String::from("type: Note\n");
        yaml.push_str("a0: &a0 [\"lol\", \"lol\", \"lol\", \"lol\", \"lol\", \"lol\", \"lol\", \"lol\", \"lol\"]\n");
        for level in 1..9 {
            let prev = level - 1;
            yaml.push_str(&format!(
                "a{level}: &a{level} [*a{prev}, *a{prev}, *a{prev}, *a{prev}, *a{prev}, *a{prev}, *a{prev}, *a{prev}, *a{prev}]\n"
            ));
        }
        let source = format!("---\n{yaml}---\n\nBody.\n");
        assert!(
            yaml.len() < MAX_FRONTMATTER_BYTES,
            "fixture must stay well under the byte cap to prove the alias check is what catches it"
        );

        let fm = read_frontmatter(&source);
        assert_eq!(fm.note_type, None);
        assert!(!fm.is_conformant());
    }

    #[test]
    fn a_block_over_the_byte_cap_is_non_conformant() {
        // Large but alias-free: no exponential blowup is possible here, but
        // an unbounded block is still an unbounded allocation, so the byte
        // cap is what has to catch this one.
        let mut yaml = String::from("type: Note\ntags:\n");
        while yaml.len() <= MAX_FRONTMATTER_BYTES {
            yaml.push_str("  - a very ordinary tag value padding out the block\n");
        }
        let source = format!("---\n{yaml}---\n\nBody.\n");

        let fm = read_frontmatter(&source);
        assert_eq!(fm.note_type, None);
        assert!(!fm.is_conformant());
    }

    #[test]
    fn a_block_at_a_realistic_size_under_the_cap_still_reads_normally() {
        // Guards against a cap set so tight it rejects legitimate content:
        // a block comfortably larger than any real frontmatter but still
        // far under the cap must still parse and be reported conformant.
        let mut yaml = String::from("type: Note\ntitle: burlmd\ntags:\n");
        for _ in 0..200 {
            yaml.push_str("  - some-realistic-tag\n");
        }
        assert!(yaml.len() < MAX_FRONTMATTER_BYTES);
        let source = format!("---\n{yaml}---\n\nBody.\n");

        let fm = read_frontmatter(&source);
        assert_eq!(fm.note_type.as_deref(), Some("Note"));
        assert!(fm.is_conformant());
        assert!(fm.other_keys.contains(&"tags".to_string()));
    }
}
