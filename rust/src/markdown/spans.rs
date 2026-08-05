//! The Core-side span map (ADR-007 decisions 3 and 8).
//!
//! Parsing a Note produces two things: the [`AstNode`] tree the Presentation
//! Container renders, and this map, which records **where in the source each
//! Block came from**. Editing is a textual substitution into the source over
//! one of these ranges; nothing is ever regenerated from the AST, because no
//! serializer exists on the save path by design (ADR-007 decision 2).
//!
//! Nothing here crosses the FFI boundary. A byte offset into a file the UI
//! does not own, cannot read and must not write is meaningless to it, so the
//! map is Core-side state keyed by `block_path` and never a field on
//! `AstNode` (ADR-007 decision 3, `tech-spec/guidelines.md`).
//!
//! # Two offset spaces, and they are not the same unit
//!
//! - **Source offsets are byte offsets** into the Note's source text. They are
//!   what a splice needs, and every [`BlockSpan::source`] and
//!   [`InlineRun::source`] is one.
//! - **Rendered offsets are character offsets** — counts of Unicode scalar
//!   values — into a Block's *rendered* text, the string
//!   [`rendered_text`] produces. `BlockRange` (ADR-006 decision 3) is
//!   expressed in these, because it spans *unfocused* Blocks, which the user
//!   sees rendered rather than as source.
//!
//! Whether the UI's own offsets are scalar values or UTF-16 code units is a
//! question about a Flutter widget rather than about this map; `EDIT-F003`
//! owns proving the two agree.
//!
//! # Why a rendered offset does not simply interpolate into a source offset
//!
//! ADR-007 decision 8's worked example — `hello **bold** world`, where
//! rendered offset 6 resolves to source offset 8 — is the case where a run's
//! rendered text and its source bytes are *the same bytes*, so
//! `source.start + (offset - rendered.start)` is right. `SPK-WSPC-D001` §2
//! measured the cases where they are not, against the same `pulldown-cmark`
//! 0.12.2 this crate pins:
//!
//! | Source | Run | Rendered | Source |
//! | :--- | :--- | ---: | ---: |
//! | ``a `code span` b`` | `` `code span` `` | 9 | 11 |
//! | `x &amp; y` | `&amp;` | 1 | 5 |
//! | `caf&eacute; au lait` | `&eacute;` | 1 | 8 |
//! | `num &#65; ref` | `&#65;` | 1 | 5 |
//! | `[link](url) tail` | `[link](url)` | 4 | 11 |
//!
//! Interpolating inside any of those lands on an interior byte of a delimiter
//! or an entity reference — in the general case not even a character boundary.
//! So each run records whether interpolation is sound, and a run for which it
//! is not is **atomic**: an offset strictly inside it resolves to the run's
//! whole source range, delimiters included, never to an interior byte. That is
//! what makes the cross-Block selection criterion — "the extracted text is
//! exactly the source spanned by the selection, delimiters included" —
//! actually hold for a code span, whose backticks live *inside* the run's
//! source range.
//!
//! # Runs do not tile a Block's source
//!
//! A backslash escape is the clearest case. `pulldown-cmark` reports
//! `esc \*not emphasis\* end` as `Text("*not emphasis")` at source `5..18` —
//! rendered and source lengths agree and the bytes are identical, so that run
//! *is* interpolable, but its range starts **after** the backslash at offset
//! 4. Emphasis delimiters (`**`), list bullets, heading markers and code
//! fences leave gaps of the same shape. Nothing here may reconstruct a
//! selection by concatenating run sources; resolution produces two source
//! offsets and the caller slices *between* them, which picks the gaps back up.

use std::collections::HashMap;
use std::ops::Range;

use super::ast::{AstNode, InlineElement};

/// An index path into a Note's AST addressing one Block.
///
/// **Not stable across any reparsing call** — a splice can change a Block's
/// node shape (ADR-007's second Negative consequence), so callers re-derive it
/// from the returned state rather than retaining it.
pub type BlockPath = Vec<usize>;

/// One inline run within a Block: a contiguous piece of rendered text, and the
/// source bytes it was produced from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InlineRun {
    /// Character offsets into the Block's rendered text. Runs tile
    /// `0..rendered_len` in order and without gaps.
    pub rendered: Range<usize>,
    /// Byte offsets into the Note's source. Runs are in source order but do
    /// **not** tile the Block's source span: delimiters, markers and escapes
    /// fall in the gaps between them.
    pub source: Range<usize>,
    /// True when this run's source bytes are byte-identical to its rendered
    /// text, which is exactly the condition under which a rendered offset may
    /// be interpolated into a source offset. False makes the run *atomic*:
    /// see [`SpanMap::resolve_offset`].
    pub interpolable: bool,
}

/// One Block's source span, plus the inline granularity ADR-007 decision 8
/// requires.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlockSpan {
    /// The path this Block is addressed by.
    pub path: BlockPath,
    /// Byte range in the Note's source. Splicing happens over exactly this.
    pub source: Range<usize>,
    /// The Block's inline runs, in source order. Empty for a container Block
    /// (a `List`, `ListItem` or `Blockquote`), whose rendered text is composed
    /// from its children instead.
    pub runs: Vec<InlineRun>,
    /// Length of this Block's rendered text, in characters.
    pub rendered_len: usize,
    /// Indices into [`SpanMap::blocks`] of this Block's child Blocks, in
    /// document order.
    children: Vec<usize>,
}

impl BlockSpan {
    /// True when this Block composes no child Blocks, so its rendered text
    /// comes from its own [`InlineRun`]s.
    #[must_use]
    pub fn is_leaf(&self) -> bool {
        self.children.is_empty()
    }
}

/// A selection expressed as rendered offsets across one or more Blocks — the
/// Core-side twin of the contract's `BlockRange` (ADR-006 decision 3).
///
/// The contract's type crosses the FFI boundary and this one does not; they
/// carry the same four fields because the conversion is meant to be nothing
/// more than a change of ownership.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RenderedRange {
    pub start_path: BlockPath,
    pub start_offset: usize,
    pub end_path: BlockPath,
    pub end_offset: usize,
}

impl RenderedRange {
    #[must_use]
    pub fn new(
        start_path: BlockPath,
        start_offset: usize,
        end_path: BlockPath,
        end_offset: usize,
    ) -> Self {
        RenderedRange {
            start_path,
            start_offset,
            end_path,
            end_offset,
        }
    }
}

/// Where a rendered offset lands in the source.
///
/// Two of the three variants are ranges rather than points, and that is the
/// substance of this type: a rendered offset does not in general name one
/// source byte. It names one *if and only if* it falls strictly inside a run
/// whose source bytes are its rendered text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SourceResolution {
    /// A single byte offset, strictly inside an interpolable run.
    Exact(usize),
    /// The offset sits between two runs — or at the very start or end of the
    /// Block's rendered text — and the markup in the gap belongs to neither.
    ///
    /// `before` is where the preceding run's source ended and `after` is where
    /// the following run's source begins. For `hello **bold** world` at
    /// rendered offset 6 they are 6 and 8: the `**` lies between them, which is
    /// why ADR-007 decision 8's answer for that offset is 8. They are equal
    /// wherever no markup separates the two runs.
    Boundary { before: usize, after: usize },
    /// The offset fell strictly inside a run whose source is not its rendered
    /// text — a code span, an entity reference, a link, a hard break. There is
    /// no meaningful interior byte, so the whole run resolves at once.
    Atomic(Range<usize>),
}

impl SourceResolution {
    /// The source offset to use when this resolution is the **start** of a
    /// selection.
    ///
    /// Biases forward: a boundary starts at the following run, so the markup
    /// in the gap is left out, and an atomic run is entered from its first
    /// byte, so its opening delimiter is taken in. Both readings come from the
    /// same rule — resolve to the run that actually produced the character
    /// being selected.
    #[must_use]
    pub fn start(&self) -> usize {
        match self {
            SourceResolution::Exact(offset) => *offset,
            SourceResolution::Boundary { after, .. } => *after,
            SourceResolution::Atomic(range) => range.start,
        }
    }

    /// The source offset to use when this resolution is the **end** of a
    /// selection: symmetrically, a boundary ends where the preceding run did
    /// and an atomic run is left from its last byte.
    #[must_use]
    pub fn end(&self) -> usize {
        match self {
            SourceResolution::Exact(offset) => *offset,
            SourceResolution::Boundary { before, .. } => *before,
            SourceResolution::Atomic(range) => range.end,
        }
    }
}

/// The map from `block_path` to a byte range in the working source, with
/// inline granularity inside each Block.
///
/// Built during the same parse that produces the AST (`SPK-WSPC-D001` §6.1:
/// the incremental cost is 1.11-1.35x rising with Note size, where a second
/// pass would be 2x) and discarded and rebuilt with it.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SpanMap {
    blocks: Vec<BlockSpan>,
    by_path: HashMap<BlockPath, usize>,
    frontmatter: Option<Range<usize>>,
}

impl SpanMap {
    /// The span of every Block, in the order the parser completed them
    /// (post-order: a child before its parent).
    pub fn blocks(&self) -> impl Iterator<Item = &BlockSpan> {
        self.blocks.iter()
    }

    /// How many Blocks the map holds.
    #[must_use]
    pub fn len(&self) -> usize {
        self.blocks.len()
    }

    /// True when the source produced no addressable Block at all.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.blocks.is_empty()
    }

    /// The span of the Block at `path`, or `None` when no Block is addressed
    /// by it.
    #[must_use]
    pub fn block(&self, path: &[usize]) -> Option<&BlockSpan> {
        self.by_path.get(path).map(|index| &self.blocks[*index])
    }

    /// The raw source text of the Block at `path` — what `get_block_source`
    /// hands the UI to populate the editable field on focus (ADR-007
    /// decision 4).
    ///
    /// `source` must be the text this map was built from.
    #[must_use]
    pub fn block_source<'s>(&self, source: &'s str, path: &[usize]) -> Option<&'s str> {
        let span = self.block(path)?;
        source.get(span.source.clone())
    }

    /// The frontmatter block's span, when the Note has one.
    ///
    /// It is a span like any other Block (ADR-007 decision 5), located via
    /// `Options::ENABLE_YAML_STYLE_METADATA_BLOCKS`, but it produces no
    /// `AstNode` and so has no `block_path` to be keyed by. It is read-only:
    /// ADR-004's "preserve unknown keys verbatim" obligation costs no work
    /// precisely because nothing ever re-serializes these bytes.
    ///
    /// The range excludes the newline that terminates the closing `---`.
    #[must_use]
    pub fn frontmatter(&self) -> Option<Range<usize>> {
        self.frontmatter.clone()
    }

    /// Resolves a rendered character offset within one Block to the source.
    ///
    /// `source` must be the text this map was built from; it is consulted only
    /// to walk characters inside an interpolable run, since the map stores
    /// ranges rather than a second copy of the Note.
    ///
    /// Returns `None` when `path` addresses no Block, or when `rendered_offset`
    /// is past the end of that Block's rendered text. An offset exactly at the
    /// end is in range and resolves to the end of the Block's last run.
    #[must_use]
    pub fn resolve_offset(
        &self,
        source: &str,
        path: &[usize],
        rendered_offset: usize,
    ) -> Option<SourceResolution> {
        let index = *self.by_path.get(path)?;
        self.resolve_at(source, index, rendered_offset)
    }

    fn resolve_at(
        &self,
        source: &str,
        index: usize,
        rendered_offset: usize,
    ) -> Option<SourceResolution> {
        let block = &self.blocks[index];
        if rendered_offset > block.rendered_len {
            return None;
        }

        if !block.children.is_empty() {
            // A container's rendered text is its children's, joined with a
            // single `\n` (the `BlockRange` definition in
            // `contracts/ffi_api.rs`). An offset landing on a joiner is the
            // end of the child before it.
            let mut consumed = 0;
            for child in &block.children {
                let child_len = self.blocks[*child].rendered_len;
                if rendered_offset <= consumed + child_len {
                    return self.resolve_at(source, *child, rendered_offset - consumed);
                }
                consumed += child_len + 1;
            }
            return None;
        }

        let mut previous_end: Option<usize> = None;
        for run in &block.runs {
            if rendered_offset == run.rendered.start {
                return Some(SourceResolution::Boundary {
                    before: previous_end.unwrap_or(run.source.start),
                    after: run.source.start,
                });
            }
            if rendered_offset < run.rendered.end {
                if !run.interpolable {
                    return Some(SourceResolution::Atomic(run.source.clone()));
                }
                // Sound only because `interpolable` means the run's source
                // bytes *are* its rendered text, so its Nth character sits at
                // the same byte offset in both.
                let within = rendered_offset - run.rendered.start;
                let text = source.get(run.source.clone())?;
                let byte = text.char_indices().nth(within).map(|(byte, _)| byte)?;
                return Some(SourceResolution::Exact(run.source.start + byte));
            }
            previous_end = Some(run.source.end);
        }

        // The end of the Block's rendered text. Anchored on the last run's
        // source end rather than the Block's, so a selection running to the end
        // of a paragraph does not swallow the newline that terminates it.
        let end = block
            .runs
            .last()
            .map_or(block.source.start, |run| run.source.end);
        Some(SourceResolution::Boundary {
            before: end,
            after: end,
        })
    }

    /// Resolves a `BlockRange` (ADR-006 decision 3) to the source byte range
    /// it selects.
    ///
    /// Each endpoint resolves to the run that produced the character it names:
    /// a start inside an atomic run enters at that run's first byte and an end
    /// inside one leaves at its last, so a selection touching a code span or a
    /// link extracts the whole construct, delimiters included. Markup lying in
    /// a *gap* between runs — an emphasis delimiter, a list bullet, a
    /// backslash escape — belongs to neither run and is therefore excluded at
    /// either endpoint, which is the same rule ADR-007 decision 8 states when
    /// it puts rendered offset 6 of `hello **bold** world` at source offset 8.
    ///
    /// Returns `None` when either endpoint is unresolvable, or when the
    /// resolved range is inverted.
    #[must_use]
    pub fn resolve_range(&self, source: &str, range: &RenderedRange) -> Option<Range<usize>> {
        let start = self
            .resolve_offset(source, &range.start_path, range.start_offset)?
            .start();
        let end = self
            .resolve_offset(source, &range.end_path, range.end_offset)?
            .end();
        if start > end {
            return None;
        }
        Some(start..end)
    }
}

/// Accumulates [`BlockSpan`]s during a parse and derives the tree
/// relationships once the whole document has been seen.
#[derive(Debug, Default)]
pub(super) struct SpanMapBuilder {
    blocks: Vec<BlockSpan>,
    frontmatter: Option<Range<usize>>,
}

impl SpanMapBuilder {
    pub(super) fn push_block(
        &mut self,
        path: BlockPath,
        source: Range<usize>,
        runs: Vec<InlineRun>,
    ) {
        let rendered_len = runs.last().map_or(0, |run| run.rendered.end);
        self.blocks.push(BlockSpan {
            path,
            source,
            runs,
            rendered_len,
            children: Vec::new(),
        });
    }

    pub(super) fn set_frontmatter(&mut self, source: Range<usize>) {
        self.frontmatter = Some(source);
    }

    pub(super) fn finish(mut self) -> SpanMap {
        let by_path: HashMap<BlockPath, usize> = self
            .blocks
            .iter()
            .enumerate()
            .map(|(index, block)| (block.path.clone(), index))
            .collect();

        for index in 0..self.blocks.len() {
            let path = &self.blocks[index].path;
            if path.len() < 2 {
                continue;
            }
            if let Some(parent) = by_path.get(&path[..path.len() - 1]).copied() {
                self.blocks[parent].children.push(index);
            }
        }
        // Children are collected in completion order, which for a container is
        // already document order; sort by the last path component anyway so
        // the invariant does not depend on that.
        let last_component: Vec<usize> = self
            .blocks
            .iter()
            .map(|block| block.path.last().copied().unwrap_or(0))
            .collect();
        for block in &mut self.blocks {
            block
                .children
                .sort_unstable_by_key(|child| last_component[*child]);
        }

        // A container's rendered length is its children's, joined with one
        // `\n` each. Deepest paths first, so a child is always resolved before
        // its parent.
        let mut by_depth: Vec<usize> = (0..self.blocks.len()).collect();
        by_depth.sort_by_key(|index| std::cmp::Reverse(self.blocks[*index].path.len()));
        for index in by_depth {
            if self.blocks[index].children.is_empty() {
                continue;
            }
            let children = self.blocks[index].children.clone();
            let total: usize = children
                .iter()
                .map(|child| self.blocks[*child].rendered_len)
                .sum();
            self.blocks[index].rendered_len = total + children.len() - 1;
        }

        SpanMap {
            blocks: self.blocks,
            by_path,
            frontmatter: self.frontmatter,
        }
    }
}

/// A Block's rendered text, per the `BlockRange` definition in
/// `tech-spec/contracts/ffi_api.rs`.
///
/// It is a pure function of the `AstNode` — of what the Core and the UI both
/// already hold — which is what makes a rendered offset well-defined without
/// the UI having to describe its geometry. It deliberately models no
/// decoration the widget draws but no field contains: no list bullet, no
/// ordered marker, no code fence.
#[must_use]
pub fn rendered_text(node: &AstNode) -> String {
    match node {
        AstNode::Heading { content, .. } | AstNode::Paragraph { content } => {
            rendered_inline_text(content)
        }
        AstNode::List { items, .. } => join_rendered(items),
        AstNode::ListItem { content, .. } => join_rendered(content),
        AstNode::Blockquote { nodes } => join_rendered(nodes),
        AstNode::CodeBlock { code, .. } => code.clone(),
        AstNode::ThematicBreak => String::new(),
        AstNode::Image { alt_text, .. } => alt_text.clone(),
        AstNode::Suggestion {
            base_content,
            local_content,
            incoming_content,
        } => {
            // No parse path produces this node — it is materialized from
            // conflict markers — so it has no span and this is only the
            // recursive rule applied in declaration order.
            let mut nodes: Vec<&AstNode> = Vec::new();
            if let Some(base) = base_content {
                nodes.extend(base.iter());
            }
            nodes.extend(local_content.iter());
            nodes.extend(incoming_content.iter());
            nodes
                .into_iter()
                .map(rendered_text)
                .collect::<Vec<_>>()
                .join("\n")
        }
    }
}

fn join_rendered(nodes: &[AstNode]) -> String {
    nodes
        .iter()
        .map(rendered_text)
        .collect::<Vec<_>>()
        .join("\n")
}

fn rendered_inline_text(content: &[InlineElement]) -> String {
    let mut out = String::new();
    push_inline_text(content, &mut out);
    out
}

fn push_inline_text(content: &[InlineElement], out: &mut String) {
    for element in content {
        match element {
            InlineElement::Text(run) => out.push_str(&run.content),
            InlineElement::Link { content, .. } | InlineElement::ExternalLink { content, .. } => {
                push_inline_text(content, out);
            }
        }
    }
}

/// The fixture corpus every span and splice test runs over.
///
/// `SPK-WSPC-D001` §6.1 is explicit that `hello **bold** world` alone passes
/// against a broken implementation, so the corpus carries every shape whose
/// rendered and source lengths disagree — inline code spans, named and numeric
/// entity references, backslash escapes and links — alongside the delimiter
/// styles and unmanaged frontmatter keys the Edit Fidelity criteria name.
#[cfg(test)]
pub(crate) mod fixtures {
    /// Underscore emphasis, asterisk bullets, nested lists, and frontmatter
    /// carrying keys this application does not manage.
    pub(crate) const FRONTMATTER_AND_DELIMITER_STYLE: &str = r"---
type: note
title: Styling
author: someone-the-app-does-not-manage
tags:
  - alpha
  - beta
nested:
  key: value
---

# Styling

A paragraph with _underscore emphasis_ and __underscore strong__ in it.

* asterisk bullet one
* asterisk bullet two
  * nested asterisk bullet
  * another nested one

Closing paragraph.
";

    /// Inline code spans, fenced code, and named and numeric entity
    /// references — every run here whose rendered length is not its source
    /// length.
    pub(crate) const CODE_AND_ENTITIES: &str = r"# Entities and code

An inline `code span` next to x &amp; y, caf&eacute; au lait and &#65; besides.

```text
literal &amp; stays literal
```

Another `span with **not bold**` inside, then a plain tail.
";

    /// Backslash escapes (whose run source excludes the backslash) and links
    /// of every classification, including a ghost.
    pub(crate) const ESCAPES_AND_LINKS: &str = r"# Escapes and links

esc \*not emphasis\* end, and a \_literal underscore\_ as well.

See [Architecture](</projects/architecture.md>) and [the docs](https://example.com/docs).

A [ghost](</not/created.md>) link, then an image ![alt text](/attachments/diagram.png) inline.
";

    /// Setext headings, blockquotes, ordered and nested lists, task lists, a
    /// hard break and a thematic break.
    pub(crate) const NESTED_STRUCTURE: &str = r"Setext Heading
==============

> A blockquote paragraph with `code` and **bold** in it.
>
> - quoted bullet
> - second quoted bullet

1. ordered one
2. ordered two
   1. nested ordered

- [x] done task
- [ ] pending task

A line with a hard break\
and its continuation.

---

Final paragraph.
";

    /// A Note that does not end in a newline, and one whose last Block runs to
    /// the final byte.
    pub(crate) const NO_TRAILING_NEWLINE: &str = r"# No trailing newline

The final paragraph ends without one";

    /// Multi-byte characters, so a character offset and a byte offset visibly
    /// disagree.
    pub(crate) const MULTIBYTE: &str = r"# Café notes

Nous étions à Paris — les cafés étaient **pleins** de monde.

An entity café spelled caf&eacute; renders identically.
";

    pub(crate) fn corpus() -> Vec<(&'static str, &'static str)> {
        vec![
            (
                "FRONTMATTER_AND_DELIMITER_STYLE",
                FRONTMATTER_AND_DELIMITER_STYLE,
            ),
            ("CODE_AND_ENTITIES", CODE_AND_ENTITIES),
            ("ESCAPES_AND_LINKS", ESCAPES_AND_LINKS),
            ("NESTED_STRUCTURE", NESTED_STRUCTURE),
            ("NO_TRAILING_NEWLINE", NO_TRAILING_NEWLINE),
            ("MULTIBYTE", MULTIBYTE),
        ]
    }
}

#[cfg(test)]
mod tests {
    use super::fixtures::*;
    use super::*;
    use crate::markdown::parser::parse_note;

    /// Walks an AST by `block_path`, the way the span map's keys address it.
    pub(crate) fn node_at<'a>(ast: &'a [AstNode], path: &[usize]) -> Option<&'a AstNode> {
        let (head, rest) = path.split_first()?;
        let node = ast.get(*head)?;
        if rest.is_empty() {
            return Some(node);
        }
        match node {
            AstNode::List { items, .. } => node_at(items, rest),
            AstNode::ListItem { content, .. } => node_at(content, rest),
            AstNode::Blockquote { nodes } => node_at(nodes, rest),
            _ => None,
        }
    }

    /// The span map is only usable if every range it holds can actually be
    /// sliced. `String::replace_range` panics rather than erring on a
    /// non-boundary index, and a panic crossing the FFI boundary is not a
    /// recoverable `AppError`.
    #[test]
    fn every_span_is_a_valid_character_range() {
        for (name, source) in corpus() {
            let parsed = parse_note(source, "");
            for block in parsed.spans.blocks() {
                let span = &block.source;
                assert!(
                    span.start <= span.end && span.end <= source.len(),
                    "{name}: block {:?} span {span:?} out of bounds",
                    block.path
                );
                assert!(
                    source.is_char_boundary(span.start) && source.is_char_boundary(span.end),
                    "{name}: block {:?} span {span:?} is not a character range",
                    block.path
                );
                for run in &block.runs {
                    assert!(
                        run.source.start <= run.source.end && run.source.end <= source.len(),
                        "{name}: block {:?} run {run:?} out of bounds",
                        block.path
                    );
                    assert!(
                        source.is_char_boundary(run.source.start)
                            && source.is_char_boundary(run.source.end),
                        "{name}: block {:?} run {run:?} is not a character range",
                        block.path
                    );
                }
            }
            if let Some(frontmatter) = parsed.spans.frontmatter() {
                assert!(
                    source.is_char_boundary(frontmatter.start)
                        && source.is_char_boundary(frontmatter.end),
                    "{name}: frontmatter span {frontmatter:?} is not a character range"
                );
            }
        }
    }

    /// A run marked interpolable claims its source bytes *are* its rendered
    /// text; anything else makes interpolation land on an interior byte of a
    /// delimiter. Runs must also tile `0..rendered_len` in rendered space,
    /// since resolution walks them in order.
    #[test]
    fn runs_tile_rendered_space_and_interpolable_runs_are_byte_identical() {
        for (name, source) in corpus() {
            let parsed = parse_note(source, "");
            for block in parsed.spans.blocks() {
                let mut expected_start = 0;
                for run in &block.runs {
                    assert_eq!(
                        run.rendered.start, expected_start,
                        "{name}: block {:?} runs leave a gap in rendered space",
                        block.path
                    );
                    assert!(run.rendered.end > run.rendered.start);
                    expected_start = run.rendered.end;
                }
                if !block.runs.is_empty() {
                    assert_eq!(expected_start, block.rendered_len, "{name}");
                }
            }
        }
    }

    /// The rendered offsets a `BlockRange` carries are offsets into the string
    /// `rendered_text` produces, so the map's own idea of a Block's rendered
    /// length has to agree with it — otherwise the two sides of the boundary
    /// are counting different things and every cross-Block selection is off.
    #[test]
    fn rendered_length_agrees_with_the_ast_rendered_text() {
        for (name, source) in corpus() {
            let parsed = parse_note(source, "");
            for block in parsed.spans.blocks() {
                let node = node_at(&parsed.ast, &block.path).unwrap_or_else(|| {
                    panic!("{name}: no AST node at block_path {:?}", block.path)
                });
                assert_eq!(
                    block.rendered_len,
                    rendered_text(node).chars().count(),
                    "{name}: block {:?} rendered length disagrees with {node:?}",
                    block.path
                );
            }
        }
    }

    /// ADR-007 decision 8's worked example, verbatim: rendered offset 6
    /// resolves to source offset 8, which is where `bold` begins.
    #[test]
    fn bold_paragraph_resolves_rendered_offset_six_to_source_offset_eight() {
        let source = "hello **bold** world";
        let parsed = parse_note(source, "");

        let resolved = parsed
            .spans
            .resolve_offset(source, &[0], 6)
            .expect("offset 6 is in range");
        assert_eq!(resolved.start(), 8);
        assert_eq!(&source[8..12], "bold");

        // The `**` between the two runs is addressable from neither, which is
        // what the offset being a boundary rather than a point records.
        assert_eq!(
            resolved,
            SourceResolution::Boundary {
                before: 6,
                after: 8
            }
        );
        assert_eq!(&source[6..8], "**");
    }

    /// `SPK-WSPC-D001` §2's first counterexample: interpolating inside a code
    /// span returns the backtick, so the run resolves whole instead.
    #[test]
    fn offset_inside_a_code_span_resolves_to_the_whole_run() {
        let source = "a `code span` b";
        let parsed = parse_note(source, "");

        // Entering the run lands on the opening delimiter, which is what
        // "delimiters included" requires — the backtick is *inside* the run's
        // source range rather than in a gap beside it.
        let entry = parsed
            .spans
            .resolve_offset(source, &[0], 2)
            .expect("offset 2 is in range");
        assert_eq!(entry.start(), 2);
        assert_eq!(&source[2..3], "`");

        // Anywhere strictly inside it resolves to the whole construct, never
        // to the interior byte interpolation would have produced.
        for offset in 3..11 {
            assert_eq!(
                parsed.spans.resolve_offset(source, &[0], offset),
                Some(SourceResolution::Atomic(2..13)),
                "rendered offset {offset}"
            );
        }
        assert_eq!(&source[2..13], "`code span`");
    }

    /// Entity references collapse several source bytes into one rendered
    /// character, so nothing inside them is addressable by interpolation at
    /// all. Named and numeric alike.
    #[test]
    fn offsets_inside_entity_references_resolve_to_the_whole_run() {
        let cases: &[(&str, usize, Range<usize>, &str)] = &[
            ("x &amp; y", 2, 2..7, "&amp;"),
            ("caf&eacute; au lait", 3, 3..11, "&eacute;"),
            ("num &#65; ref", 4, 4..9, "&#65;"),
        ];
        for (source, entry, expected, literal) in cases {
            let parsed = parse_note(source, "");
            assert_eq!(&source[expected.clone()], *literal);
            // The run is one rendered character wide, so its only interior
            // position is its start, which is exact by definition. What the
            // map must record is that it is *not* interpolable, so a run of
            // more than one character (`&eacute;` renders `é`, one character)
            // never yields an interior byte.
            let block = parsed.spans.block(&[0]).expect("paragraph span");
            let run = block
                .runs
                .iter()
                .find(|run| run.source == *expected)
                .unwrap_or_else(|| panic!("no run at {expected:?} for {source:?}"));
            assert!(
                !run.interpolable,
                "{source:?}: entity run {run:?} must not be interpolable"
            );
            assert_eq!(
                parsed
                    .spans
                    .resolve_offset(source, &[0], *entry)
                    .expect("entry offset is in range")
                    .start(),
                expected.start
            );
        }
    }

    /// A wider entity-bearing run: `&amp;` inside a longer paragraph, resolved
    /// from an offset that is genuinely interior.
    #[test]
    fn interior_offset_of_a_multi_character_atomic_run_resolves_whole() {
        // A hard break renders as one `\n` from a two-byte source, and an
        // inline link renders as its text from a source that is not.
        let source = "text [a link](https://example.com) tail";
        let parsed = parse_note(source, "");
        let link = 5..34;
        assert_eq!(&source[link.clone()], "[a link](https://example.com)");

        // Entering the link lands on `[`.
        assert_eq!(
            parsed
                .spans
                .resolve_offset(source, &[0], 5)
                .expect("offset 5 is in range")
                .start(),
            5
        );
        // Inside the link text there is no meaningful interior byte: the run's
        // source carries syntax its rendered text does not.
        for offset in 6..11 {
            assert_eq!(
                parsed.spans.resolve_offset(source, &[0], offset),
                Some(SourceResolution::Atomic(link.clone())),
                "rendered offset {offset}"
            );
        }
    }

    /// The escape case is the one `SPK-WSPC-D001` §2 records as *not* a length
    /// mismatch. Measured against `pulldown-cmark` 0.12.2, `esc \*not
    /// emphasis\* end` yields `Text("*not emphasis")` at source `5..18`: the
    /// bytes are identical, so the run interpolates soundly, and the hazard is
    /// instead that its range excludes the backslash at offset 4. Runs do not
    /// tile the Block's source.
    #[test]
    fn an_escaped_run_interpolates_but_leaves_its_backslash_in_a_gap() {
        let source = r"esc \*not emphasis\* end";
        let parsed = parse_note(source, "");
        let block = parsed.spans.block(&[0]).expect("paragraph span");

        let escaped = block
            .runs
            .iter()
            .find(|run| run.source.start == 5)
            .expect("escaped run at source offset 5");
        assert!(escaped.interpolable);
        assert_eq!(&source[escaped.source.clone()], "*not emphasis");

        // Interpolation inside it is byte-exact.
        assert_eq!(
            parsed.spans.resolve_offset(source, &[0], 5),
            Some(SourceResolution::Exact(6))
        );
        assert_eq!(&source[6..7], "n");

        // And the backslash belongs to no run at all: the gap between the run
        // ending at 4 and the run starting at 5.
        assert_eq!(&source[4..5], "\\");
        assert!(
            block
                .runs
                .iter()
                .all(|run| !(run.source.start <= 4 && 4 < run.source.end)),
            "source offset 4 (the backslash) must lie in a gap, runs: {:?}",
            block.runs
        );
    }

    /// A hard break renders as one character from a source that is not one
    /// character, so it is atomic like every other length-mismatched run.
    #[test]
    fn a_hard_break_is_not_interpolable() {
        let source = "one\\\ntwo";
        let parsed = parse_note(source, "");
        let block = parsed.spans.block(&[0]).expect("paragraph span");
        let brk = block
            .runs
            .iter()
            .find(|run| run.source == (3..5))
            .expect("hard break run");
        assert!(!brk.interpolable);
    }

    /// Rendered offsets are character counts and source offsets are byte
    /// counts. With multi-byte text in the Block the two visibly disagree, and
    /// interpolation has to walk characters rather than add integers.
    #[test]
    fn interpolation_walks_characters_not_bytes() {
        let source = "café **gras** fin";
        let parsed = parse_note(source, "");

        // `café ` is five characters but six bytes, so the bold run starts at
        // rendered offset 5 and source offset 8 (`é` plus the two asterisks).
        assert_eq!(source.find("gras"), Some(8));
        assert_eq!(
            parsed
                .spans
                .resolve_offset(source, &[0], 5)
                .expect("offset 5 is in range")
                .start(),
            8
        );
        // Two characters into the first run is two bytes in; three characters
        // in crosses `é` and is four bytes in.
        assert_eq!(
            parsed.spans.resolve_offset(source, &[0], 2),
            Some(SourceResolution::Exact(2))
        );
        assert_eq!(
            parsed.spans.resolve_offset(source, &[0], 4),
            Some(SourceResolution::Exact(5))
        );
    }

    /// A container Block's rendered text is its children's, joined with one
    /// `\n` each (the `BlockRange` definition in `contracts/ffi_api.rs`), so a
    /// path naming a list resolves through to the item the offset lands in.
    #[test]
    fn a_container_block_resolves_through_its_children() {
        let source = "- alpha\n- beta\n";
        let parsed = parse_note(source, "");

        let list = parsed.spans.block(&[0]).expect("list span");
        assert!(!list.is_leaf());
        assert_eq!(list.rendered_len, "alpha\nbeta".chars().count());

        // Offset 0 is the start of the first item's text; the `- ` bullet is
        // decoration the rendered text deliberately does not model.
        assert_eq!(
            parsed
                .spans
                .resolve_offset(source, &[0], 0)
                .expect("offset 0 is in range")
                .start(),
            2
        );
        // Offset 6 is the first character of the second item, past the joiner.
        assert_eq!(
            parsed
                .spans
                .resolve_offset(source, &[0], 6)
                .expect("offset 6 is in range")
                .start(),
            10
        );
        assert_eq!(&source[10..14], "beta");
    }

    #[test]
    fn an_offset_past_the_end_of_a_block_does_not_resolve() {
        let source = "short\n";
        let parsed = parse_note(source, "");
        // The offset at the very end is in range, and stops before the newline
        // that terminates the paragraph rather than swallowing it.
        assert_eq!(
            parsed
                .spans
                .resolve_offset(source, &[0], 5)
                .expect("offset 5 is in range")
                .end(),
            5
        );
        assert_eq!(parsed.spans.resolve_offset(source, &[0], 6), None);
        assert_eq!(parsed.spans.resolve_offset(source, &[9], 0), None);
    }

    /// ADR-007 decision 5: the frontmatter block is a span like any other and
    /// produces no `AstNode`, which is the whole of why ADR-004's
    /// "preserve unknown keys verbatim" obligation costs no work.
    #[test]
    fn frontmatter_is_a_span_with_no_block_path() {
        let source = FRONTMATTER_AND_DELIMITER_STYLE;
        let parsed = parse_note(source, "");
        let frontmatter = parsed.spans.frontmatter().expect("frontmatter span");

        assert!(source[frontmatter.clone()].starts_with("---\ntype: note"));
        assert!(source[frontmatter.clone()].ends_with("---"));
        assert!(source[frontmatter.clone()].contains("author: someone-the-app-does-not-manage"));
        assert!(
            parsed
                .spans
                .blocks()
                .all(|block| block.source.start >= frontmatter.end),
            "no Block may overlap the frontmatter span"
        );
    }

    #[test]
    fn block_source_returns_the_raw_text_of_one_block() {
        let source = "# Title\n\nA _paragraph_ here.\n";
        let parsed = parse_note(source, "");

        assert_eq!(parsed.spans.block_source(source, &[0]), Some("# Title\n"));
        assert_eq!(
            parsed.spans.block_source(source, &[1]),
            Some("A _paragraph_ here.\n")
        );
        assert_eq!(parsed.spans.block_source(source, &[7]), None);
    }
}
