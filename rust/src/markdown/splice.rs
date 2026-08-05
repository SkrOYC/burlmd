//! Span-preserving source splicing (ADR-007 decision 1).
//!
//! An edit is a textual substitution into the Note's source over one Block's
//! span. Bytes outside that span are never rewritten, which is what makes the
//! Edit Fidelity constraint in `prd/constraints.md` a property of the design
//! rather than something to test for afterwards: no code path here is capable
//! of rewriting an unedited region, because nothing here can produce Markdown
//! from an AST at all. There is no serializer on the save path by design
//! (ADR-007 decision 2) and adding one would reintroduce exactly the failure
//! the constraint forbids.
//!
//! Every committed splice is followed by a whole-file reparse that rebuilds the
//! span map from scratch. `SPK-WSPC-D001` §5 rejected offset arithmetic here on
//! two independent grounds: a reparse already fits the frame budget with margin
//! at realistic Note sizes, and a *committed* splice is precisely the operation
//! that may change a Block's node shape — a paragraph gaining a leading `- `
//! becomes a list — so arithmetic would produce correctly shifted offsets into
//! a tree that no longer describes the file. Those errors are silent, which is
//! the whole of `architecture/risks.md` risk 7.

use std::fmt;
use std::ops::Range;

use super::parser::{parse_note, ParsedNote};
use super::spans::{BlockPath, RenderedRange, SpanMap};

/// Why a splice could not be performed.
///
/// These are all caller errors — a stale `block_path`, an out-of-range
/// selection — rather than parse failures, because `pulldown-cmark` has no
/// parse failure: every byte sequence is some Markdown document.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SpliceError {
    /// No Block is addressed by this path. Most likely a path retained across
    /// a reparsing call, which `tech-spec/guidelines.md` says is never valid.
    UnknownBlock(BlockPath),
    /// A rendered offset past the end of the Block's rendered text, or one
    /// that resolves to nothing.
    OffsetOutOfRange { path: BlockPath, offset: usize },
    /// The selection's end resolved before its start.
    InvertedRange,
    /// A source range that is not addressable in this text. Checked rather
    /// than trusted because `String::replace_range` *panics* on a non-boundary
    /// index, and a panic crossing the FFI boundary is not a recoverable
    /// error.
    InvalidSourceRange(Range<usize>),
}

impl fmt::Display for SpliceError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SpliceError::UnknownBlock(path) => {
                write!(f, "no Block is addressed by block_path {path:?}")
            }
            SpliceError::OffsetOutOfRange { path, offset } => write!(
                f,
                "rendered offset {offset} is out of range for block_path {path:?}"
            ),
            SpliceError::InvertedRange => write!(f, "selection ends before it starts"),
            SpliceError::InvalidSourceRange(range) => write!(
                f,
                "source range {}..{} is not a valid character range in this Note",
                range.start, range.end
            ),
        }
    }
}

impl std::error::Error for SpliceError {}

/// The result of a committed splice: the new source, and the AST and span map
/// reparsed from it.
///
/// The three are consistent with each other by construction, because the
/// second two were derived from the first. Keeping a span map alongside a
/// source it was not built from is the corruption mode this type exists to
/// make awkward.
#[derive(Debug, Clone)]
pub struct SplicedNote {
    pub source: String,
    pub ast: Vec<super::ast::AstNode>,
    pub spans: SpanMap,
}

/// Substitutes `replacement` for the bytes in `span`, leaving every other byte
/// of `source` untouched.
///
/// The lowest level of the splice path and the only place bytes are moved.
pub fn splice_source(
    source: &str,
    span: Range<usize>,
    replacement: &str,
) -> Result<String, SpliceError> {
    if span.start > span.end
        || span.end > source.len()
        || !source.is_char_boundary(span.start)
        || !source.is_char_boundary(span.end)
    {
        return Err(SpliceError::InvalidSourceRange(span));
    }
    let mut spliced =
        String::with_capacity(source.len() - (span.end - span.start) + replacement.len());
    spliced.push_str(&source[..span.start]);
    spliced.push_str(replacement);
    spliced.push_str(&source[span.end..]);
    Ok(spliced)
}

/// Replaces the Block at `path` with `replacement` and reparses the whole Note.
///
/// This is the committed-edit path — what `commit_block` and the structural
/// mutators run. The reparse is unconditional and has no size threshold, no
/// fallback and no background-thread escape hatch, deliberately: a second
/// strategy chosen by input size would be the one that gets the least testing,
/// on the rarest inputs, while producing silent corruption rather than a
/// visible fault (`SPK-WSPC-D001` §5, option C).
///
/// **Measured cost, so the next person to look at a slow blur finds the number
/// instead of re-deriving it** (`SPK-WSPC-D001` §4.1-4.2, `pulldown-cmark`
/// 0.12.2, release profile, Ryzen 7 PRO 4750U): 0.1ms at 2.5 KiB, 3.4ms at
/// 102 KiB, 9.6ms at 257 KiB. Against a 16ms frame budget the p95 crossing is
/// around **360 KiB of ordinary Markdown** and around **150 KiB of the densest
/// inline Markdown a person could plausibly write**. Above that a blur drops a
/// frame, on a discrete and infrequent action, which is a far better thing to
/// have than a second code path.
pub fn splice_block(
    source: &str,
    spans: &SpanMap,
    path: &[usize],
    replacement: &str,
    containing_dir: &str,
) -> Result<SplicedNote, SpliceError> {
    let block = spans
        .block(path)
        .ok_or_else(|| SpliceError::UnknownBlock(path.to_vec()))?;
    let spliced = splice_source(source, block.source.clone(), replacement)?;
    Ok(reparse(spliced, containing_dir))
}

/// Resolves a `BlockRange` (ADR-006 decision 3) to the source byte range it
/// selects.
///
/// Endpoints bias outward through an atomic run, so a selection that clips
/// into a code span or a link comes back holding the whole construct,
/// delimiters included.
pub fn resolve_range(
    source: &str,
    spans: &SpanMap,
    range: &RenderedRange,
) -> Result<Range<usize>, SpliceError> {
    let start = spans
        .resolve_offset(source, &range.start_path, range.start_offset)
        .ok_or_else(|| offset_error(spans, &range.start_path, range.start_offset))?
        .start();
    let end = spans
        .resolve_offset(source, &range.end_path, range.end_offset)
        .ok_or_else(|| offset_error(spans, &range.end_path, range.end_offset))?
        .end();
    if start > end {
        return Err(SpliceError::InvertedRange);
    }
    Ok(start..end)
}

/// The source text a `BlockRange` selects — what `copy_range_as_markdown`
/// returns. A slice of the Note, never a reconstruction of one.
pub fn extract_range<'s>(
    source: &'s str,
    spans: &SpanMap,
    range: &RenderedRange,
) -> Result<&'s str, SpliceError> {
    let resolved = resolve_range(source, spans, range)?;
    source
        .get(resolved.clone())
        .ok_or(SpliceError::InvalidSourceRange(resolved))
}

/// Replaces the source a `BlockRange` selects and reparses — the shape
/// `delete_range` and `replace_range` need. See [`splice_block`] for why the
/// reparse is unconditional.
pub fn splice_range(
    source: &str,
    spans: &SpanMap,
    range: &RenderedRange,
    replacement: &str,
    containing_dir: &str,
) -> Result<SplicedNote, SpliceError> {
    let resolved = resolve_range(source, spans, range)?;
    let spliced = splice_source(source, resolved, replacement)?;
    Ok(reparse(spliced, containing_dir))
}

fn reparse(source: String, containing_dir: &str) -> SplicedNote {
    let ParsedNote { ast, spans } = parse_note(&source, containing_dir);
    SplicedNote { source, ast, spans }
}

fn offset_error(spans: &SpanMap, path: &[usize], offset: usize) -> SpliceError {
    if spans.block(path).is_none() {
        SpliceError::UnknownBlock(path.to_vec())
    } else {
        SpliceError::OffsetOutOfRange {
            path: path.to_vec(),
            offset,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::markdown::ast::AstNode;
    use crate::markdown::spans::fixtures::*;
    use proptest::prelude::*;

    /// Every Block's path, in the order the parser completed them.
    fn block_paths(spans: &SpanMap) -> Vec<BlockPath> {
        spans.blocks().map(|block| block.path.clone()).collect()
    }

    /// The round-trip property `tech-spec/guidelines.md` makes mandatory for
    /// the splice path, and `WSPC-D003`'s first criterion: for any Note in the
    /// corpus and any Block within it, splicing that Block's own unmodified
    /// source back over its span reproduces the file byte for byte —
    /// whitespace, delimiter style and unmanaged frontmatter keys included.
    ///
    /// It is the executable form of the Edit Fidelity constraint, and it is
    /// checked through the real splice entry point rather than by re-deriving
    /// the arithmetic here, so a span that cannot be sliced fails it.
    #[test]
    fn splicing_a_block_over_its_own_span_is_byte_identical() {
        for (name, source) in corpus() {
            let parsed = crate::markdown::parse_note(source, "");
            assert!(
                !parsed.spans.is_empty(),
                "{name}: corpus entry has no Block"
            );

            for path in block_paths(&parsed.spans) {
                let block_source = parsed
                    .spans
                    .block_source(source, &path)
                    .unwrap_or_else(|| panic!("{name}: no source for block {path:?}"))
                    .to_string();
                let spliced = splice_block(source, &parsed.spans, &path, &block_source, "")
                    .unwrap_or_else(|error| panic!("{name}: block {path:?}: {error}"));
                assert_eq!(
                    spliced.source, source,
                    "{name}: block {path:?} did not round trip"
                );
            }
        }
    }

    /// The same property over generated Notes rather than fixed ones, so the
    /// gate is not only as good as the six documents somebody thought to
    /// write. Blocks are drawn from the shapes whose rendered and source
    /// lengths disagree, since those are where a naive implementation fails.
    fn block_token() -> impl Strategy<Value = String> {
        prop_oneof![
            Just("# A heading".to_string()),
            Just("Plain paragraph text.".to_string()),
            Just("Emphasis _underscored_ and **starred**.".to_string()),
            Just("An inline `code span` here.".to_string()),
            Just("Entities x &amp; y, caf&eacute;, and &#65;.".to_string()),
            Just(r"Escaped \*stars\* and \_underscores\_.".to_string()),
            Just("A [Link](</dir/target.md>) and [ext](https://example.com).".to_string()),
            Just("An image ![alt](/attachments/x.png) inline.".to_string()),
            Just("* bullet one\n* bullet two\n  * nested".to_string()),
            Just("1. ordered\n2. ordered two".to_string()),
            Just("- [x] done\n- [ ] pending".to_string()),
            Just("> quoted **text**\n>\n> - quoted bullet".to_string()),
            Just("```rust\nfn main() {}\n```".to_string()),
            Just("---".to_string()),
            Just("Multibyte café — with an em dash.".to_string()),
            Just("A hard break\\\nand its continuation.".to_string()),
        ]
    }

    proptest! {
        #[test]
        fn splicing_any_block_over_its_own_span_is_byte_identical_for_generated_notes(
            blocks in proptest::collection::vec(block_token(), 1..8),
            with_frontmatter in any::<bool>(),
        ) {
            let mut source = String::new();
            if with_frontmatter {
                source.push_str("---\ntype: note\ntitle: Generated\nunmanaged: keep me\n---\n\n");
            }
            source.push_str(&blocks.join("\n\n"));
            source.push('\n');

            let parsed = crate::markdown::parse_note(&source, "");
            for path in block_paths(&parsed.spans) {
                let block_source = parsed
                    .spans
                    .block_source(&source, &path)
                    .expect("every Block has source")
                    .to_string();
                let spliced = splice_block(&source, &parsed.spans, &path, &block_source, "")
                    .expect("splicing a Block's own source must succeed");
                prop_assert_eq!(&spliced.source, &source);
            }
        }
    }

    /// The other half of Edit Fidelity: an edit that *does* change a Block
    /// must leave every byte outside its span alone. Nothing here can rewrite
    /// an unedited region, and this is what says so.
    #[test]
    fn editing_one_block_leaves_every_other_byte_untouched() {
        for (name, source) in corpus() {
            let parsed = crate::markdown::parse_note(source, "");
            for path in block_paths(&parsed.spans) {
                let span = parsed.spans.block(&path).expect("span").source.clone();
                let spliced = splice_block(source, &parsed.spans, &path, "REPLACED", "")
                    .unwrap_or_else(|error| panic!("{name}: block {path:?}: {error}"));

                assert_eq!(
                    &spliced.source[..span.start],
                    &source[..span.start],
                    "{name}: block {path:?} rewrote bytes before its span"
                );
                assert_eq!(
                    &spliced.source[span.start + "REPLACED".len()..],
                    &source[span.end..],
                    "{name}: block {path:?} rewrote bytes after its span"
                );
            }
        }
    }

    /// `WSPC-D003`'s third criterion. The frontmatter block is never
    /// re-serialized, so keys the application does not manage survive an edit
    /// to any other Block without anything having to preserve them.
    #[test]
    fn frontmatter_is_byte_identical_after_another_block_is_edited() {
        let source = FRONTMATTER_AND_DELIMITER_STYLE;
        let parsed = crate::markdown::parse_note(source, "");
        let frontmatter = parsed.spans.frontmatter().expect("frontmatter span");
        let original = &source[frontmatter.clone()];

        for path in block_paths(&parsed.spans) {
            let spliced = splice_block(source, &parsed.spans, &path, "Rewritten body.", "")
                .unwrap_or_else(|error| panic!("block {path:?}: {error}"));
            let after = crate::markdown::parse_note(&spliced.source, "");
            let moved = after.spans.frontmatter().expect("frontmatter survived");
            assert_eq!(
                &spliced.source[moved], original,
                "editing block {path:?} disturbed the frontmatter"
            );
        }
    }

    /// `WSPC-D003`'s second criterion. No canonical form is ever imposed,
    /// because there is no serializer to impose one.
    #[test]
    fn untouched_blocks_keep_their_delimiter_style() {
        let source = FRONTMATTER_AND_DELIMITER_STYLE;
        let parsed = crate::markdown::parse_note(source, "");

        // The closing paragraph, chosen because it is neither the frontmatter
        // nor any of the styled Blocks the assertions below cover.
        let path = parsed
            .spans
            .blocks()
            .find(|block| source[block.source.clone()].starts_with("Closing paragraph"))
            .map(|block| block.path.clone())
            .expect("closing paragraph");

        let spliced = splice_block(source, &parsed.spans, &path, "Replaced closing text.\n", "")
            .expect("splice");

        assert!(spliced.source.contains("_underscore emphasis_"));
        assert!(spliced.source.contains("__underscore strong__"));
        assert!(spliced.source.contains("* asterisk bullet one"));
        assert!(spliced.source.contains("  * nested asterisk bullet"));
        assert!(spliced
            .source
            .contains("author: someone-the-app-does-not-manage"));
        assert!(spliced.source.contains("Replaced closing text."));
    }

    /// `WSPC-D003`'s fourth criterion, and ADR-007's second Negative
    /// consequence made concrete: a committed splice may change a Block's node
    /// shape, which is exactly why the whole file is reparsed rather than
    /// having its offsets arithmetically shifted.
    #[test]
    fn a_paragraph_spliced_with_a_list_marker_reparses_as_a_list() {
        let source = "# Heading\n\njust a paragraph\n\n# Trailing\n";
        let parsed = crate::markdown::parse_note(source, "");
        assert!(matches!(parsed.ast[1], AstNode::Paragraph { .. }));

        let spliced =
            splice_block(source, &parsed.spans, &[1], "- now an item\n", "").expect("splice");

        assert!(
            matches!(spliced.ast[1], AstNode::List { .. }),
            "expected a List at [1], got {:?}",
            spliced.ast[1]
        );
        assert_eq!(spliced.source, "# Heading\n\n- now an item\n\n# Trailing\n");
    }

    /// `WSPC-D003`'s last criterion: a selection expressed as rendered offsets
    /// across two Blocks extracts exactly the source it spans, delimiters
    /// included.
    ///
    /// The emphasis delimiters, the blank line between the Blocks and the
    /// trailing newline of the first are all picked up because extraction
    /// slices *between* two resolved offsets rather than concatenating run
    /// sources — which `SPK-WSPC-D001` §2 warns is wrong precisely because
    /// runs do not tile a Block's source.
    #[test]
    fn a_selection_across_two_blocks_extracts_exactly_the_spanned_source() {
        let source = "first **para** here\n\nsecond _para_ here\n";
        let parsed = crate::markdown::parse_note(source, "");

        // The whole of both Blocks' rendered text: "first para here" is 15
        // characters, "second para here" is 16.
        let range = RenderedRange::new(vec![0], 0, vec![1], 16);
        let extracted = extract_range(source, &parsed.spans, &range).expect("extract");
        assert_eq!(extracted, "first **para** here\n\nsecond _para_ here");
        assert_eq!(
            source.find(extracted),
            Some(0),
            "the extracted text must be a slice of the Note, not a reconstruction"
        );
    }

    /// The endpoint rule for a delimiter that is *not* inside a run.
    ///
    /// Emphasis delimiters fall in the gaps between runs, and ADR-007
    /// decision 8 fixes what an endpoint landing on the run after such a gap
    /// means: rendered offset 6 of `hello **bold** world` is source offset 8,
    /// where `bold` begins, not source offset 6 where `**` does. A code span's
    /// backticks are the opposite case — they are *inside* the atomic run's
    /// source range, so the same outward bias picks them up. Both rules follow
    /// from resolving against the run that actually produced the character.
    #[test]
    fn a_selection_starting_after_an_emphasis_delimiter_starts_at_the_text() {
        let source = "hello **bold** world\n";
        let parsed = crate::markdown::parse_note(source, "");

        let range = RenderedRange::new(vec![0], 6, vec![0], 10);
        let extracted = extract_range(source, &parsed.spans, &range).expect("extract");
        assert_eq!(extracted, "bold");
    }

    /// The same, clipping into a code span at each end. Only a run-atomic
    /// resolution returns the backticks, and they are what makes the extracted
    /// text parse back as a code span.
    #[test]
    fn a_selection_clipping_a_code_span_extracts_its_delimiters() {
        let source = "a `code span` b\n\nc `more code` d\n";
        let parsed = crate::markdown::parse_note(source, "");

        // Rendered offset 5 is inside `code span`; offset 8 is inside
        // `more code`. Both resolve outward.
        let range = RenderedRange::new(vec![0], 5, vec![1], 8);
        let extracted = extract_range(source, &parsed.spans, &range).expect("extract");
        assert!(extracted.starts_with("`code span`"), "got {extracted:?}");
        assert!(extracted.ends_with("`more code`"), "got {extracted:?}");
    }

    #[test]
    fn splicing_a_range_replaces_exactly_the_selected_source() {
        let source = "first **para** here\n\nsecond _para_ here\n";
        let parsed = crate::markdown::parse_note(source, "");

        let range = RenderedRange::new(vec![0], 0, vec![1], 16);
        let spliced = splice_range(source, &parsed.spans, &range, "MERGED", "").expect("splice");
        assert_eq!(spliced.source, "MERGED\n");
        assert!(matches!(spliced.ast[0], AstNode::Paragraph { .. }));
    }

    #[test]
    fn a_stale_block_path_is_an_error_rather_than_a_panic() {
        let source = "one paragraph\n";
        let parsed = crate::markdown::parse_note(source, "");

        assert_eq!(
            splice_block(source, &parsed.spans, &[4], "x", "").unwrap_err(),
            SpliceError::UnknownBlock(vec![4])
        );
        assert_eq!(
            resolve_range(
                source,
                &parsed.spans,
                &RenderedRange::new(vec![0], 0, vec![0], 99)
            )
            .unwrap_err(),
            SpliceError::OffsetOutOfRange {
                path: vec![0],
                offset: 99
            }
        );
    }

    #[test]
    fn an_inverted_selection_is_rejected() {
        let source = "alpha\n\nbeta\n";
        let parsed = crate::markdown::parse_note(source, "");
        assert_eq!(
            resolve_range(
                source,
                &parsed.spans,
                &RenderedRange::new(vec![1], 4, vec![0], 0)
            )
            .unwrap_err(),
            SpliceError::InvertedRange
        );
    }

    /// `String::replace_range` panics on a non-boundary index, and a panic
    /// crossing the FFI boundary is not a recoverable `AppError`, so the
    /// lowest level of the splice path checks rather than trusts.
    #[test]
    fn splicing_a_non_character_boundary_is_an_error_rather_than_a_panic() {
        let source = "café";
        assert_eq!(
            splice_source(source, 3..4, "x").unwrap_err(),
            SpliceError::InvalidSourceRange(3..4)
        );
        assert_eq!(
            splice_source(source, 0..99, "x").unwrap_err(),
            SpliceError::InvalidSourceRange(0..99)
        );
        assert_eq!(splice_source(source, 0..3, "tea").unwrap(), "teaé");
    }

    /// A reparse after a splice is a whole-file reparse, so the returned map
    /// describes the returned source and nothing else. Splicing a Block's own
    /// text back must therefore reproduce the map it came from.
    #[test]
    fn a_committed_splice_rebuilds_a_map_describing_the_new_source() {
        for (name, source) in corpus() {
            let parsed = crate::markdown::parse_note(source, "");
            for path in block_paths(&parsed.spans) {
                let text = parsed
                    .spans
                    .block_source(source, &path)
                    .expect("block source")
                    .to_string();
                let spliced =
                    splice_block(source, &parsed.spans, &path, &text, "").expect("splice");
                assert_eq!(
                    spliced.spans, parsed.spans,
                    "{name}: reparsing after a no-op splice of {path:?} changed the map"
                );
            }
        }
    }
}
