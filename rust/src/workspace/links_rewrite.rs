//! Rewriting inbound Links in the *source bytes* of the Notes that hold them.
//!
//! Renaming or moving a Note changes its concept id (OKF positional identity,
//! ADR-004), so every Link pointing at it names a concept that no longer
//! exists. `architecture/risks.md` risk 8 is that a partial rewrite leaves
//! dangling Links indistinguishable from deliberate ghost Links, so the graph
//! degrades silently rather than failing loudly. This module is the half of
//! the mitigation that touches prose; [`super::lifecycle`] owns the file, index
//! and session halves and is what makes the whole thing atomic.
//!
//! Three properties this module exists to guarantee:
//!
//! - **Only the destination bytes move.** The Link's display text is the
//!   user's own prose — `prd/constraints.md`'s Edit Fidelity constraint — and
//!   re-serializing it would double-escape a title an author already escaped
//!   by hand. Everything outside the destination span is copied verbatim.
//! - **The destination is written by the real serializer.** A multi-word title
//!   derives to a filename containing a space, and CommonMark forbids a *bare*
//!   destination from containing one, so a hand-rolled `format!` that forgot
//!   the angle brackets would emit paragraph text where a Link used to be —
//!   the failure `data-models/okf-bundle.md` spends a page on. The replacement
//!   text is therefore derived from [`crate::okf::serialize_link`] itself
//!   rather than reimplemented beside it.
//! - **A Link that matches but cannot be rewritten is an error, never a
//!   skip.** A reference-style Link (`[a][ref]`) keeps its destination in a
//!   definition this scanner does not address. Leaving it behind while
//!   rewriting its neighbours is exactly the partial rewrite the STOP
//!   condition forbids, so the operation fails instead and
//!   [`super::lifecycle`] rolls back.

use std::collections::BTreeMap;
use std::ops::Range;

use pulldown_cmark::{Event, Options, Parser, Tag, TagEnd};

use crate::error::AppError;
use crate::okf::{classify, serialize_link, LinkTarget};

/// Old concept id → new concept id, for every Note whose identity an operation
/// moved. A `BTreeMap` rather than a `HashMap` so that a `rename_directory`
/// over hundreds of Notes produces deterministic error messages and
/// deterministic test output.
pub(super) type Remap = BTreeMap<String, String>;

/// Rewrites every internal Link in `source` whose target appears in `remap`,
/// returning `None` when the source holds no such Link.
///
/// `containing_dir` is the bundle-relative directory of the Note `source` came
/// from, as it is *at the time the bytes were read* — [`classify`] needs it to
/// resolve the relative destinations OKF §6.1 permits in a foreign bundle.
///
/// Errors when a Link whose target is remapped has no addressable destination
/// span, which today means a reference-style Link. See the module
/// documentation.
pub(super) fn rewrite_link_targets(
    source: &str,
    containing_dir: &str,
    remap: &Remap,
) -> Result<Option<String>, AppError> {
    if remap.is_empty() {
        return Ok(None);
    }

    let mut rewrites: Vec<(Range<usize>, String)> = Vec::new();
    for link in matching_links(source, containing_dir, remap) {
        let Some(destination) = destination_span(source, &link.span, link.text_end) else {
            return Err(AppError::ParseError(format!(
                "the Link at bytes {}..{} targets {} but its destination is not written inline, \
                 so this rename cannot rewrite it; rewriting the rest would leave the graph \
                 partially updated (architecture/risks.md risk 8)",
                link.span.start, link.span.end, link.new_target,
            )));
        };
        rewrites.push((destination, destination_text(&link.new_target)));
    }

    if rewrites.is_empty() {
        return Ok(None);
    }

    // Descending, so an earlier replacement never invalidates a later span's
    // offsets.
    rewrites.sort_by_key(|(span, _)| std::cmp::Reverse(span.start));
    let mut out = source.to_string();
    for (span, replacement) in rewrites {
        if span.end > out.len()
            || !out.is_char_boundary(span.start)
            || !out.is_char_boundary(span.end)
        {
            return Err(AppError::ParseError(format!(
                "link destination span {}..{} is not addressable in this Note",
                span.start, span.end
            )));
        }
        out.replace_range(span, &replacement);
    }
    Ok(Some(out))
}

/// One Link whose target is being remapped.
struct MatchedLink {
    /// The whole `[text](dest)` span.
    span: Range<usize>,
    /// The furthest byte any *inner* event reached, i.e. a lower bound on
    /// where the link text ends. Scanning for the closing `]` from here rather
    /// than from the start of the span is what keeps a `]` inside an inline
    /// code span in the link text from being mistaken for the delimiter.
    text_end: usize,
    new_target: String,
}

fn matching_links(source: &str, containing_dir: &str, remap: &Remap) -> Vec<MatchedLink> {
    let mut matched = Vec::new();
    let mut open: Option<MatchedLink> = None;
    let mut open_matches = false;

    for (event, range) in Parser::new_ext(source, parser_options()).into_offset_iter() {
        match event {
            Event::Start(Tag::Link { ref dest_url, .. }) => {
                let new_target = match classify(dest_url, containing_dir) {
                    LinkTarget::Internal(id) => remap.get(&id).cloned(),
                    LinkTarget::External(_) => None,
                };
                open_matches = new_target.is_some();
                open = Some(MatchedLink {
                    text_end: range.start.saturating_add(1),
                    span: range,
                    new_target: new_target.unwrap_or_default(),
                });
            }
            Event::End(TagEnd::Link) => {
                if let Some(link) = open.take() {
                    if open_matches {
                        matched.push(link);
                    }
                }
                open_matches = false;
            }
            _ => {
                // Inner content of an open Link — including an image inside the
                // link text, whose own Start/End land here.
                if let Some(link) = open.as_mut() {
                    if range.start >= link.span.start && range.end <= link.span.end {
                        link.text_end = link.text_end.max(range.end);
                    }
                }
            }
        }
    }
    matched
}

/// The same options `markdown::parser` parses with. Re-stated rather than
/// borrowed because `rust/src/markdown/**` is outside this ticket's scope and
/// `parser_options` is private there; the metadata-block flag is the one that
/// carries weight here, since without it a Note's frontmatter parses as a
/// thematic break followed by content and a `title:` line could in principle
/// be scanned for Links.
fn parser_options() -> Options {
    let mut options = Options::empty();
    options.insert(Options::ENABLE_STRIKETHROUGH);
    options.insert(Options::ENABLE_TASKLISTS);
    options.insert(Options::ENABLE_YAML_STYLE_METADATA_BLOCKS);
    options
}

/// The byte span of one Link's destination — angle brackets included when it
/// has them — given the span of the whole Link and a lower bound on where its
/// text ends.
///
/// `None` when the Link is not an inline `[text](dest)`: a reference,
/// collapsed or shortcut Link keeps its destination in a definition elsewhere
/// in the document, which this scanner deliberately does not address rather
/// than rewriting by guesswork.
fn destination_span(source: &str, span: &Range<usize>, text_end: usize) -> Option<Range<usize>> {
    let bytes = source.as_bytes();
    let mut i = text_end.max(span.start.saturating_add(1));
    while i < span.end && i < bytes.len() {
        if bytes[i] == b']' && !is_escaped(bytes, i) {
            if bytes.get(i + 1) != Some(&b'(') {
                return None;
            }
            return parse_destination(bytes, i + 2, span.end);
        }
        i += 1;
    }
    None
}

/// Reads the destination that starts at or after `from`, stopping at `limit`
/// (the closing `)` of the Link).
fn parse_destination(bytes: &[u8], from: usize, limit: usize) -> Option<Range<usize>> {
    let mut start = from;
    while start < limit && bytes[start].is_ascii_whitespace() {
        start += 1;
    }
    if start >= limit {
        return None;
    }

    if bytes[start] == b'<' {
        let mut k = start + 1;
        while k < limit {
            match bytes[k] {
                b'\\' => k += 1,
                b'>' => return Some(start..k + 1),
                _ => {}
            }
            k += 1;
        }
        return None;
    }

    // A bare destination, which burlmd never writes but a foreign bundle may
    // hold: it ends at the first unescaped whitespace (a Link title follows) or
    // at the `)` that closes the Link, with nested parens balanced.
    let mut k = start;
    let mut depth = 0u32;
    while k < limit {
        match bytes[k] {
            b'\\' => k += 1,
            b'(' => depth += 1,
            b')' => {
                if depth == 0 {
                    break;
                }
                depth -= 1;
            }
            c if c.is_ascii_whitespace() => break,
            _ => {}
        }
        k += 1;
    }
    (k > start).then_some(start..k)
}

fn is_escaped(bytes: &[u8], index: usize) -> bool {
    let mut backslashes = 0usize;
    let mut i = index;
    while i > 0 && bytes[i - 1] == b'\\' {
        backslashes += 1;
        i -= 1;
    }
    backslashes % 2 == 1
}

/// The destination text burlmd writes for `concept_id`, angle brackets
/// included.
///
/// Derived from [`serialize_link`] rather than reimplemented beside it: that
/// function owns the bracket rule and the `\`/`<`/`>`/`&` escaping table in
/// `data-models/okf-bundle.md`, and a second copy here would be free to drift
/// from it silently. With an empty link text its output is exactly
/// `"[](" + destination + ")"`.
fn destination_text(concept_id: &str) -> String {
    let link = serialize_link("", concept_id);
    match link
        .strip_prefix("[](")
        .and_then(|rest| rest.strip_suffix(')'))
    {
        Some(destination) => destination.to_string(),
        None => link,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn remap(pairs: &[(&str, &str)]) -> Remap {
        pairs
            .iter()
            .map(|(old, new)| ((*old).to_string(), (*new).to_string()))
            .collect()
    }

    fn rewrite(source: &str, pairs: &[(&str, &str)]) -> Option<String> {
        rewrite_link_targets(source, "", &remap(pairs)).unwrap()
    }

    /// The destination helper must stay in lockstep with the serializer that
    /// owns the escaping table, since everything else here depends on it.
    #[test]
    fn the_destination_text_is_the_serializers_own() {
        assert_eq!(destination_text("Meeting Notes"), "</Meeting Notes.md>");
        assert_eq!(
            serialize_link("Meeting Notes", "Meeting Notes"),
            format!("[Meeting Notes]({})", destination_text("Meeting Notes"))
        );
    }

    /// The criterion's mandatory shape: a title containing a space. A
    /// single-word fixture passes vacuously, because a bare destination with no
    /// space parses as a Link either way.
    #[test]
    fn a_multi_word_target_is_rewritten_with_the_brackets_intact() {
        let source = "See [Meeting Notes](</Meeting Notes.md>) for context.\n";

        let out = rewrite(source, &[("Meeting Notes", "Standup Notes")]).unwrap();

        assert_eq!(
            out,
            "See [Meeting Notes](</Standup Notes.md>) for context.\n"
        );
    }

    /// Edit Fidelity: only the destination bytes move. The display text is the
    /// user's prose and is copied through byte for byte, escapes included.
    #[test]
    fn the_display_text_is_left_exactly_as_written() {
        let source = r"A [Tom \&amp; Jerry](</Old.md>) reference.";

        let out = rewrite(source, &[("Old", "New")]).unwrap();

        assert_eq!(out, r"A [Tom \&amp; Jerry](</New.md>) reference.");
    }

    #[test]
    fn a_source_with_no_matching_link_is_left_alone() {
        assert!(rewrite("Just [text](</Other.md>).", &[("Old", "New")]).is_none());
    }

    #[test]
    fn external_links_are_never_touched() {
        let source = "[site](https://example.com/Old.md) and [Old](</Old.md>)";

        let out = rewrite(source, &[("Old", "New")]).unwrap();

        assert_eq!(
            out,
            "[site](https://example.com/Old.md) and [Old](</New.md>)"
        );
    }

    /// Several Links in one Note all move, and the replacements do not
    /// invalidate each other's offsets.
    #[test]
    fn every_matching_link_in_one_note_moves() {
        let source = "[a](</A B.md>) then [b](</A B.md>) then [c](</C.md>)\n";

        let out = rewrite(source, &[("A B", "X Y"), ("C", "Z")]).unwrap();

        assert_eq!(
            out,
            "[a](</X Y.md>) then [b](</X Y.md>) then [c](</Z.md>)\n"
        );
    }

    /// A `]` inside inline code in the link text is not the delimiter. Scanning
    /// from the start of the span rather than from the end of the parsed inner
    /// content gets this wrong.
    #[test]
    fn a_bracket_inside_inline_code_in_the_link_text_is_not_the_delimiter() {
        let source = "[a `]` b](</Old.md>)";

        let out = rewrite(source, &[("Old", "New")]).unwrap();

        assert_eq!(out, "[a `]` b](</New.md>)");
    }

    /// A foreign bundle may hold a bare destination. It is read and rewritten
    /// into the bracketed form burlmd writes.
    #[test]
    fn a_bare_destination_is_read_and_rewritten_into_the_bracketed_form() {
        let source = "[a](/Old.md)";

        let out = rewrite(source, &[("Old", "New Name")]).unwrap();

        assert_eq!(out, "[a](</New Name.md>)");
    }

    /// A destination already carrying escapes round-trips through the
    /// serializer's own escaping rather than being spliced verbatim.
    #[test]
    fn an_entity_shaped_target_is_re_escaped_by_the_serializer() {
        let source = r"[a](</Caf\&eacute;.md>)";

        let out = rewrite(source, &[(r"Caf&eacute;", "Café")]).unwrap();

        assert_eq!(out, "[a](</Café.md>)");
    }

    /// Frontmatter is a metadata block, not content, so nothing in it is
    /// scanned for Links.
    #[test]
    fn frontmatter_is_not_scanned() {
        let source = "---\ntype: Note\ntitle: Old\n---\n\nBody [x](</Old.md>)\n";

        let out = rewrite(source, &[("Old", "New")]).unwrap();

        assert_eq!(
            out,
            "---\ntype: Note\ntitle: Old\n---\n\nBody [x](</New.md>)\n"
        );
    }

    /// The STOP condition, at this layer: a matching Link whose destination
    /// lives in a reference definition is an error, not a silent skip.
    #[test]
    fn a_reference_style_link_fails_rather_than_being_skipped() {
        let source = "[a][ref]\n\n[ref]: </Old.md>\n";

        let result = rewrite_link_targets(source, "", &remap(&[("Old", "New")]));

        assert!(
            matches!(result, Err(AppError::ParseError(_))),
            "expected a refusal rather than a partial rewrite, got {result:?}"
        );
    }

    /// Relative destinations are permitted by OKF §6.1 in a bundle burlmd did
    /// not write, and resolve against the Note's own directory.
    #[test]
    fn a_relative_destination_resolves_against_the_containing_directory() {
        let source = "[a](../Old.md)";

        let out = rewrite_link_targets(source, "dir/sub", &remap(&[("dir/Old", "dir/New")]))
            .unwrap()
            .unwrap();

        assert_eq!(out, "[a](</dir/New.md>)");
    }

    /// A self-Link is an inbound Link like any other and is found by the same
    /// scan — there is no separate code path for it, which is what makes the
    /// "rename a Note that links to itself" criterion fall out rather than need
    /// special handling.
    #[test]
    fn a_self_link_is_matched_by_the_same_scan() {
        let source = "---\ntype: Note\ntitle: Me Myself\n---\n\nback to [me](</Me Myself.md>)\n";

        let out = rewrite(source, &[("Me Myself", "You Yourself")]).unwrap();

        assert!(out.contains("[me](</You Yourself.md>)"), "{out:?}");
    }
}
