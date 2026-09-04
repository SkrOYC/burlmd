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
//!   user's own prose — `.constitution/prd/constraints.yaml`'s Edit Fidelity constraint — and
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
//!
//! A move has a second half, and it runs through the same three properties:
//! the moved Note's **own outbound** destinations can be written relatively
//! (OKF §6.1), and a relative destination resolves against the Note's directory
//! — which is the one thing a move changes. [`absolutize_relative_links`] is
//! that half, and it covers attachments as well as Links: what breaks under a
//! move is how a destination *resolves*, which has nothing to do with whether
//! the file at the end of it is a Note.

use std::collections::BTreeMap;
use std::ops::Range;

use pulldown_cmark::{Event, Options, Parser, Tag, TagEnd};

use crate::error::AppError;
use crate::okf::{classify, resolve_bundle_path, serialize_destination, LinkTarget};

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
    rewrite_destinations(source, Scan::LinksOnly, |dest| {
        match classify(dest, containing_dir) {
            LinkTarget::Internal(id) => remap.get(&id).map(|new| Replacement::Note(new.clone())),
            LinkTarget::External(_) => None,
        }
    })
}

/// Rewrites every **relatively written** destination in `source` — Links to
/// other Notes and references to files beside them alike — into the
/// bundle-absolute form burlmd writes, leaving every already-absolute and every
/// truly external destination byte-for-byte as it was. Returns `None` when the
/// source holds no relatively-written destination.
///
/// `containing_dir` is the directory those destinations currently resolve
/// against, i.e. where the Note is *before* it moves.
///
/// # Why a move has to do this
///
/// OKF §6.1 permits a relative destination and [`classify`] resolves it against
/// the Note's own directory, so `[t](Target.md)` in a Note at the bundle root
/// names `Target` and the identical bytes in a Note under `sub/` name
/// `sub/Target`. Moving a Note between Directories therefore silently repoints
/// every relatively-written Link it holds at a *different concept* — the file
/// is genuinely wrong afterwards, not merely differently spelled, and
/// `index::derive_note` indexes the wrong edge because it classifies against
/// the new id's directory.
///
/// Rewriting them into the absolute form is what keeps the Links naming the
/// concepts the author wrote them for. It is deliberately the *only* thing a
/// move changes in those bytes: an absolute destination already resolves
/// identically from anywhere, and an external one is not ours to touch.
///
/// # Attachments are the same defect, and they are not Links
///
/// A relative destination breaks under a move because of how it *resolves*, not
/// because of what it points at, so `![diagram](img/diagram.png)` and
/// `[the plan](plan.pdf)` are wrong afterwards in exactly the way `[t](Target.md)`
/// is: the base directory moved out from under bytes that were never touched,
/// and the reference now names a file in the new Directory or names nothing at
/// all. [`classify`] answers `External` for both — it is asking whether a
/// destination names a *Note*, which they do not — so the first pass at this
/// rewrote Links and left every attachment behind, in a bundle burlmd did not
/// write and therefore in precisely the foreign-bundle case (CAP-PORT-03) this
/// function exists for. burlmd's own writes are already absolute and are
/// unaffected either way.
///
/// So a destination with no URI scheme that is not already absolute is resolved
/// as a bundle path ([`resolve_bundle_path`]) and rewritten to name the same
/// file from the bundle root. A destination carrying a scheme is a real external
/// URL and is not ours; one that climbs above the bundle root names nothing this
/// bundle can address and is left as written, on the same terms `classify` sets
/// for a Note destination. Images are scanned alongside Links here, and only
/// here: an `![…](…)` is a destination in the same sense, and it is the shape
/// most attachment references actually take.
pub(super) fn absolutize_relative_links(
    source: &str,
    containing_dir: &str,
) -> Result<Option<String>, AppError> {
    rewrite_destinations(source, Scan::LinksAndImages, |dest| {
        if dest.starts_with('/') {
            return None;
        }
        match classify(dest, containing_dir) {
            LinkTarget::Internal(id) => Some(Replacement::Note(id)),
            LinkTarget::External(_) => {
                resolve_bundle_path(dest, containing_dir).map(Replacement::BundlePath)
            }
        }
    })
}

/// What one destination is being rewritten *to*, which decides how it is
/// spelled: a concept id gains the leading `/` and the `.md` a Note reference
/// carries, a bundle path is written as it resolved. Both go through the
/// serializer's own escaping and bracketing.
enum Replacement {
    Note(String),
    BundlePath(String),
}

impl Replacement {
    /// The destination text to splice in, angle brackets included.
    fn destination_text(&self) -> String {
        match self {
            Self::Note(concept_id) => serialize_destination(&format!("/{concept_id}.md")),
            Self::BundlePath(path) => serialize_destination(&format!("/{path}")),
        }
    }
}

impl std::fmt::Display for Replacement {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Note(concept_id) => write!(f, "{concept_id}"),
            Self::BundlePath(path) => write!(f, "{path}"),
        }
    }
}

/// Which destinations a scan considers. Images are `![…](…)` and carry a
/// destination in the same sense a Link does, but only the absolutize pass has
/// any business rewriting one: a remap is keyed by concept id, and an image
/// destination that resolved to a Note's id would be an image of a Markdown
/// file.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Scan {
    LinksOnly,
    LinksAndImages,
}

/// The shared splice: find every destination `select` names a replacement for,
/// and replace its span with the serializer's own text.
///
/// `select` receives the destination exactly as `pulldown-cmark` resolved it —
/// angle brackets stripped, escapes and entity references applied — and returns
/// what the destination should name afterwards, or `None` to leave it alone.
fn rewrite_destinations(
    source: &str,
    scan: Scan,
    select: impl FnMut(&str) -> Option<Replacement>,
) -> Result<Option<String>, AppError> {
    let mut rewrites: Vec<(Range<usize>, String)> = Vec::new();
    for link in matching_links(source, scan, select) {
        let Some(destination) = destination_span(source, &link.span, link.text_end) else {
            return Err(AppError::ParseError(format!(
                "the Link at bytes {}..{} targets {} but its destination is not written inline, \
                 so this operation cannot rewrite it; rewriting the rest would leave the graph \
                 partially updated (architecture/risks.md risk 8)",
                link.span.start, link.span.end, link.new_target,
            )));
        };
        rewrites.push((destination, link.new_target.destination_text()));
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

/// One destination that is being rewritten.
struct MatchedLink {
    /// The whole `[text](dest)` span — or `![text](dest)`, `!` included, for an
    /// image.
    span: Range<usize>,
    /// The furthest byte any *inner* event reached, i.e. a lower bound on
    /// where the link text ends. Scanning for the closing `]` from here rather
    /// than from the start of the span is what keeps a `]` inside an inline
    /// code span in the link text from being mistaken for the delimiter.
    text_end: usize,
    new_target: Replacement,
}

/// A destination whose Start event has been seen and whose End has not.
struct OpenLink {
    link: MatchedLink,
    matches: bool,
}

fn matching_links(
    source: &str,
    scan: Scan,
    mut select: impl FnMut(&str) -> Option<Replacement>,
) -> Vec<MatchedLink> {
    let mut matched = Vec::new();
    // A stack rather than a single slot, because an image can appear *inside*
    // link text (`[![alt](img.png)](/Target.md)`) and, when images are scanned,
    // both are open at once. Popping the inner one folds its span into the outer
    // one's `text_end` exactly as any other inner event does.
    let mut open: Vec<OpenLink> = Vec::new();
    let images = scan == Scan::LinksAndImages;

    for (event, range) in Parser::new_ext(source, parser_options()).into_offset_iter() {
        let opened = match &event {
            Event::Start(Tag::Link { dest_url, .. }) => Some(dest_url),
            Event::Start(Tag::Image { dest_url, .. }) if images => Some(dest_url),
            _ => None,
        };
        if let Some(dest_url) = opened {
            let new_target = select(dest_url);
            open.push(OpenLink {
                matches: new_target.is_some(),
                link: MatchedLink {
                    text_end: range.start.saturating_add(1),
                    span: range,
                    new_target: new_target.unwrap_or_else(|| Replacement::Note(String::new())),
                },
            });
            continue;
        }

        let closes = matches!(event, Event::End(TagEnd::Link))
            || (images && matches!(event, Event::End(TagEnd::Image)));
        if closes {
            if let Some(closed) = open.pop() {
                let span = closed.link.span.clone();
                if closed.matches {
                    matched.push(closed.link);
                }
                fold_inner(&mut open, &span);
            }
            continue;
        }

        // Inner content of an open Link — including an image inside the link
        // text when images are not themselves scanned, whose own Start/End land
        // here.
        fold_inner(&mut open, &range);
    }
    matched
}

/// Extends the innermost open destination's `text_end` to cover `range`, when
/// `range` really lies inside it.
fn fold_inner(open: &mut [OpenLink], range: &Range<usize>) {
    if let Some(top) = open.last_mut() {
        if range.start >= top.link.span.start && range.end <= top.link.span.end {
            top.link.text_end = top.link.text_end.max(range.end);
        }
    }
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

    /// The move case: a relatively-written internal destination is rewritten
    /// into the absolute form, which is the only spelling that survives the
    /// Note changing directory.
    #[test]
    fn a_relative_destination_is_absolutized_against_the_containing_directory() {
        let out = absolutize_relative_links("[t](Target.md) and [u](../Up.md)\n", "a/b")
            .unwrap()
            .unwrap();

        assert_eq!(out, "[t](</a/b/Target.md>) and [u](</a/Up.md>)\n");
    }

    /// Everything that already resolves from anywhere, or that is not ours, is
    /// left byte-for-byte alone — including a destination this crate would spell
    /// differently if it were writing it fresh.
    #[test]
    fn absolutizing_leaves_absolute_and_external_destinations_untouched() {
        let source = "[a](</x/Already.md>) [b](/bare/Absolute.md) \
                      [c](https://example.com/Old.md) ![d](/x/image.png) \
                      [e](mailto:someone@example.com) [f](#section)\n";

        assert!(absolutize_relative_links(source, "sub").unwrap().is_none());
    }

    /// A relatively-written **attachment** moves with the Note for the same
    /// reason a relatively-written Link does: what changed is the directory its
    /// destination resolves against.
    ///
    /// The regression this pins: `classify` answers `External` for every
    /// non-`.md` destination — it is asking whether one names a *Note* — and the
    /// absolutizer dropped externals, so `![diagram](img/diagram.png)` kept its
    /// bytes while the base directory moved out from under it. The image then
    /// named `newdir/img/diagram.png`, which is a different file or no file at
    /// all, in exactly the foreign bundle this rewrite exists to keep intact.
    #[test]
    fn a_relative_attachment_is_absolutized_to_the_file_it_already_named() {
        let source = "![diagram](img/diagram.png) and [the plan](../shared/plan.pdf)\n";

        let out = absolutize_relative_links(source, "a/b").unwrap().unwrap();

        assert_eq!(
            out,
            "![diagram](</a/b/img/diagram.png>) and [the plan](</a/shared/plan.pdf>)\n"
        );
    }

    /// A destination carrying a URI scheme is a real external reference and is
    /// not ours to touch, image or Link — and one that climbs above the bundle
    /// root names nothing this bundle can address, so it is left as written on
    /// the same terms `classify` sets for a Note destination.
    #[test]
    fn absolutizing_leaves_external_urls_and_escaping_attachments_byte_for_byte() {
        let source = "![remote](https://example.com/d.png) [mail](mailto:a@example.com) \
                      ![up](../../outside.png)\n";

        assert!(absolutize_relative_links(source, "sub").unwrap().is_none());
    }

    /// An image nested inside link text: both destinations are open at once, and
    /// both are rewritten. The scan used one slot for the open destination, so
    /// the inner image's End closed the *outer* Link's record and the Link was
    /// dropped silently.
    #[test]
    fn an_image_inside_link_text_and_its_enclosing_link_both_move() {
        let source = "[![alt](img/a.png)](Target.md)\n";

        let out = absolutize_relative_links(source, "sub").unwrap().unwrap();

        assert_eq!(out, "[![alt](</sub/img/a.png>)](</sub/Target.md>)\n");
    }

    /// A remap is keyed by concept id, so the inbound-Link rewrite deliberately
    /// does not look at images: an image whose destination happened to resolve
    /// to a renamed Note's id would be an image of a Markdown file, and
    /// rewriting it is not what a rename was asked to do.
    #[test]
    fn the_inbound_rewrite_still_scans_links_only() {
        let source = "![a](</Old.md>) and [b](</Old.md>)\n";

        let out = rewrite(source, &[("Old", "New")]).unwrap();

        assert_eq!(out, "![a](</Old.md>) and [b](</New.md>)\n");
    }

    /// A relative destination that climbs above the bundle root names no
    /// concept in this bundle ([`classify`] reports it external), so there is
    /// nothing to absolutize it to and it is left as written.
    #[test]
    fn a_relative_destination_escaping_the_bundle_root_is_left_alone() {
        assert!(absolutize_relative_links("[a](../../far.md)", "sub")
            .unwrap()
            .is_none());
    }

    /// The STOP condition applies here too: a relative Link whose destination
    /// lives in a reference definition cannot be absolutized, and leaving it
    /// behind while absolutizing its neighbours is the partial rewrite this
    /// module refuses to perform.
    #[test]
    fn absolutizing_a_reference_style_link_fails_rather_than_being_skipped() {
        let result = absolutize_relative_links("[a][ref]\n\n[ref]: Target.md\n", "sub");

        assert!(
            matches!(result, Err(AppError::ParseError(_))),
            "expected a refusal rather than a partial rewrite, got {result:?}"
        );
    }

    /// The destination text must stay in lockstep with the serializer that owns
    /// the bracket rule and the escaping table, since everything else here
    /// depends on it.
    #[test]
    fn the_destination_text_is_the_serializers_own() {
        let note = Replacement::Note("Meeting Notes".to_string());
        assert_eq!(note.destination_text(), "</Meeting Notes.md>");
        assert_eq!(
            crate::okf::serialize_link("Meeting Notes", "Meeting Notes"),
            format!("[Meeting Notes]({})", note.destination_text())
        );
        // An attachment is wrapped and escaped by the same rules, minus the
        // `.md` a concept id carries.
        assert_eq!(
            Replacement::BundlePath("a/Diagram <1>.png".to_string()).destination_text(),
            "</a/Diagram \\<1\\>.png>"
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

    /// Text that merely *looks* like a Link — inside a fenced code block or an
    /// inline code span — is not a Link and must not be rewritten. A rename
    /// that edited a code sample would be silent corruption of the user's
    /// prose, and the property rests on parser behaviour rather than on
    /// anything this module does, which is exactly why it is pinned here.
    #[test]
    fn links_inside_fenced_and_inline_code_are_not_rewritten() {
        let source = "Prose [a](</Old.md>).\n\n\
                      Inline `[a](</Old.md>)` stays.\n\n\
                      ```markdown\n[a](</Old.md>)\n```\n\n\
                      Indented:\n\n    [a](</Old.md>)\n";

        let out = rewrite(source, &[("Old", "New")]).unwrap();

        assert_eq!(
            out.matches("</New.md>").count(),
            1,
            "only the one real Link may move: {out:?}"
        );
        assert_eq!(
            out.matches("</Old.md>").count(),
            3,
            "the inline code span, the fenced block and the indented block must \
             all be left exactly as written: {out:?}"
        );
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
