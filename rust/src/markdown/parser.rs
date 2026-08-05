//! Parses a Note into an AST **and** the Core-side span map, in one pass.
//!
//! One pass rather than two because `Parser::into_offset_iter()` already
//! yields a byte range for every event, inline events included (ADR-007
//! decision 8), and `SPK-WSPC-D001` §4.1 measured the incremental cost of
//! building the map alongside the AST at 1.11-1.35x — rising with Note size —
//! against the 2x a second parse would cost.
//!
//! # Regions that are preserved but not addressable
//!
//! Some of a Note's bytes produce no `AstNode` and therefore no entry in the
//! span map. This is a decision rather than an oversight, and it is recorded
//! here because the alternative reading — that these are gaps a future change
//! should close by fabricating a span — is the exact mistake that produced
//! this module's worst defect.
//!
//! The regions are: raw HTML blocks and inline HTML (`Event::Html` and
//! `Event::InlineHtml`, which this AST has no variant for), link reference
//! definitions (`[ref]: /target.md`, which `pulldown-cmark` consumes without
//! emitting any event at all), and inline constructs that render no characters
//! — an empty link text, or a link whose only content was an image already
//! hoisted into a Block of its own.
//!
//! What follows from being unaddressable is narrow and safe. Nothing writes
//! those bytes, because the only writer is a splice over a registered span and
//! no span covers them, so **no edit can corrupt them and they survive every
//! save byte-identically** — which is what the Edit Fidelity constraint asks
//! for and what `CAP-PORT-03`'s externally-authored bundles need. What is lost
//! is only that the UI does not render them and cannot focus them, and that
//! insert and delete step over them rather than into them. Making raw HTML
//! editable in place is `EPIC-F` territory (raw-mode editing), not something
//! to reach by giving these regions a span here.

use std::ops::Range;

use pulldown_cmark::{CodeBlockKind, CowStr, Event, Options, Parser, Tag, TagEnd};

use super::ast::{AstNode, InlineElement, TextRun};
use super::spans::{BlockPath, InlineRun, SpanMap, SpanMapBuilder};
use crate::okf::links::{self, LinkTarget};

/// A parsed Note: the tree the UI renders, and the span map that says where
/// each Block came from.
///
/// The two are produced together and are only meaningful together — a span map
/// is a description of the exact source text it was parsed from, so it is
/// discarded and rebuilt whenever that text changes (ADR-007 decision 1).
#[derive(Debug, Clone)]
pub struct ParsedNote {
    pub ast: Vec<AstNode>,
    pub spans: SpanMap,
}

/// Parses `source` into an AST, discarding the span map.
///
/// Kept for read-only callers that render a Note they will not edit. Anything
/// on an editing path wants [`parse_note`], because throwing the map away here
/// and rebuilding it later would be the second parse this design exists to
/// avoid.
///
/// It has **no production caller in this crate today** — its last one, the
/// conflict collapse in `workspace::persist`, moved to
/// [`parse_markdown_fragment`], which is the correct entry point for text that
/// does not begin a document. Left in place rather than removed: it is the
/// whole-document read-only entry point, and a `containing_dir` of `""` is the
/// right default only for a caller that genuinely parses from the bundle root.
#[must_use]
pub fn parse_markdown(input: &str) -> Vec<AstNode> {
    parse_note(input, "").ast
}

/// Parses a **fragment** of a Note — a region that is not the start of the
/// document — into an AST, discarding the span map.
///
/// The one difference from [`parse_markdown`] is that a leading `---` is a
/// thematic break here rather than the opening fence of a YAML metadata block,
/// and that is the whole reason this exists. Frontmatter is *positional*: OKF
/// §4 puts it at byte zero of the file and nowhere else, so
/// `ENABLE_YAML_STYLE_METADATA_BLOCKS` is only ever the right reading for the
/// segment that starts there.
///
/// The caller this was added for is `workspace::persist`'s conflict collapse,
/// which parses each side of a `<<<<<<<`/`>>>>>>>` region — and the tail after
/// it — as its own document. Parsed with the metadata option, a side that
/// happens to open with `---` was consumed as frontmatter and produced **no
/// nodes at all**, so one of the two versions of the user's work disappeared
/// from the Suggestion they are being asked to choose between.
#[must_use]
pub fn parse_markdown_fragment(source: &str, containing_dir: &str) -> Vec<AstNode> {
    Builder::new(source, containing_dir, Frontmatter::Absent)
        .run()
        .ast
}

/// Parses `source` into an AST and its span map.
///
/// `containing_dir` is the bundle-relative directory of the Note being parsed
/// (empty for the bundle root, no leading or trailing `/`). It is passed
/// through to [`links::classify`], which needs it to resolve the relative link
/// destinations OKF §6.1 permits in a bundle burlmd did not write.
#[must_use]
pub fn parse_note(source: &str, containing_dir: &str) -> ParsedNote {
    Builder::new(source, containing_dir, Frontmatter::Possible).run()
}

/// Whether the text being parsed **begins the document**, and may therefore
/// open with frontmatter. See [`parse_markdown_fragment`].
#[derive(Clone, Copy, PartialEq, Eq)]
enum Frontmatter {
    Possible,
    Absent,
}

fn parser_options(frontmatter: Frontmatter) -> Options {
    let mut options = Options::empty();
    options.insert(Options::ENABLE_STRIKETHROUGH);
    options.insert(Options::ENABLE_TASKLISTS);
    // ADR-007 decision 5: this is what makes the frontmatter block a span like
    // any other rather than a thematic break followed by garbage, and it is
    // the whole of what "preserve unknown keys verbatim" costs. Only for text
    // that begins the document, because that is the only place OKF §4 puts
    // frontmatter — elsewhere the option turns a thematic break into a
    // swallowed region.
    if frontmatter == Frontmatter::Possible {
        options.insert(Options::ENABLE_YAML_STYLE_METADATA_BLOCKS);
    }
    options
}

#[derive(Default)]
struct FormatState {
    bold: bool,
    italic: bool,
    strikethrough: bool,
}

impl TextRun {
    fn from_state(content: String, format_state: &FormatState, code: bool) -> Self {
        TextRun {
            content,
            bold: format_state.bold,
            italic: format_state.italic,
            strikethrough: format_state.strikethrough,
            code,
        }
    }
}

/// An open `[text](dest)` or `![alt](dest)`.
struct LinkFrame {
    kind: LinkKind,
    content: Vec<InlineElement>,
    source: Range<usize>,
    /// Rendered characters accumulated inside this link. Its children emit no
    /// runs of their own — the whole link is one atomic run, because its
    /// source (`[text](dest)`) is not its rendered text (`text`).
    rendered_chars: usize,
}

enum LinkKind {
    Link(LinkTarget),
    Image(String),
}

struct CodeBlockAccum {
    language: Option<String>,
    code: String,
    source: Range<usize>,
    runs: RunAccum,
}

/// Accumulates the inline runs of the Block currently being built, assigning
/// each its rendered character range as it arrives.
#[derive(Default)]
struct RunAccum {
    runs: Vec<InlineRun>,
    rendered_len: usize,
}

impl RunAccum {
    /// Zero-width runs are dropped: they would shadow the following run's
    /// start offset while addressing nothing.
    fn push(&mut self, rendered_chars: usize, source: Range<usize>, interpolable: bool) {
        if rendered_chars == 0 {
            return;
        }
        let start = self.rendered_len;
        self.rendered_len += rendered_chars;
        self.runs.push(InlineRun {
            rendered: start..self.rendered_len,
            source,
            interpolable,
        });
    }

    fn take(&mut self) -> Vec<InlineRun> {
        self.rendered_len = 0;
        std::mem::take(&mut self.runs)
    }

    fn clear(&mut self) {
        self.rendered_len = 0;
        self.runs.clear();
    }
}

/// An open block-level container.
struct Frame {
    kind: FrameKind,
    source: Range<usize>,
    /// Paragraph frames only. Set when a Block node was hoisted out of this
    /// paragraph — an inline image becomes an `AstNode::Image` sibling — so
    /// the paragraph's remaining text no longer begins where its tag does.
    split: bool,
}

enum FrameKind {
    Heading(u8),
    Paragraph,
    Blockquote {
        path: BlockPath,
        nodes: Vec<AstNode>,
    },
    List {
        path: BlockPath,
        ordered: bool,
        items: Vec<AstNode>,
    },
    ListItem {
        path: BlockPath,
        content: Vec<AstNode>,
        checked: Option<bool>,
    },
}

impl FrameKind {
    /// `Heading` and `Paragraph` exist only to accumulate inline content and
    /// never hold Block-level children, so a Block pushed while one is open
    /// belongs to whatever encloses *it*.
    fn holds_children(&self) -> bool {
        matches!(
            self,
            FrameKind::Blockquote { .. } | FrameKind::List { .. } | FrameKind::ListItem { .. }
        )
    }
}

struct Builder<'a> {
    source: &'a str,
    containing_dir: &'a str,
    root_nodes: Vec<AstNode>,
    frames: Vec<Frame>,
    inlines: Vec<InlineElement>,
    runs: RunAccum,
    format_state: FormatState,
    code_block: Option<CodeBlockAccum>,
    link_stack: Vec<LinkFrame>,
    spans: SpanMapBuilder,
    frontmatter: Frontmatter,
    in_metadata: bool,
    /// Blocks hoisted out of a frame that cannot hold Block children, held
    /// back so they land after it rather than before it. See `close_image`.
    deferred: Vec<DeferredBlock>,
}

/// A Block waiting for its enclosing inline-only frame to close.
struct DeferredBlock {
    node: AstNode,
    source: Range<usize>,
    runs: Vec<InlineRun>,
}

impl<'a> Builder<'a> {
    fn new(source: &'a str, containing_dir: &'a str, frontmatter: Frontmatter) -> Self {
        Builder {
            source,
            containing_dir,
            root_nodes: Vec::new(),
            frames: Vec::new(),
            inlines: Vec::new(),
            runs: RunAccum::default(),
            format_state: FormatState::default(),
            code_block: None,
            link_stack: Vec::new(),
            spans: SpanMapBuilder::default(),
            frontmatter,
            in_metadata: false,
            deferred: Vec::new(),
        }
    }

    fn run(mut self) -> ParsedNote {
        let parser = Parser::new_ext(self.source, parser_options(self.frontmatter));
        for (event, range) in parser.into_offset_iter() {
            self.handle(event, range);
        }
        ParsedNote {
            ast: self.root_nodes,
            spans: self.spans.finish(),
        }
    }

    fn handle(&mut self, event: Event<'_>, range: Range<usize>) {
        match event {
            Event::Start(tag) => self.start(tag, range),
            Event::End(tag_end) => self.end(tag_end, range),
            Event::Text(text) => self.text(&text, range),
            Event::Code(text) => self.code_span(&text, range),
            Event::Rule => self.push_block(AstNode::ThematicBreak, Some(range), Vec::new()),
            Event::SoftBreak | Event::HardBreak => self.line_break(range),
            Event::TaskListMarker(checked) => {
                if let Some(FrameKind::ListItem { checked: slot, .. }) =
                    self.frames.last_mut().map(|frame| &mut frame.kind)
                {
                    *slot = Some(checked);
                }
            }
            _ => {}
        }
    }

    fn start(&mut self, tag: Tag<'_>, range: Range<usize>) {
        match tag {
            Tag::MetadataBlock(_) => {
                self.spans.set_frontmatter(range);
                self.in_metadata = true;
            }
            Tag::Heading { level, .. } => {
                self.reset_inlines();
                self.open(FrameKind::Heading(level as u8), range);
            }
            Tag::Paragraph => {
                self.reset_inlines();
                self.open(FrameKind::Paragraph, range);
            }
            Tag::BlockQuote(_) => {
                let path = self.next_path();
                self.open(
                    FrameKind::Blockquote {
                        path,
                        nodes: Vec::new(),
                    },
                    range,
                );
            }
            Tag::List(start_number) => {
                // A tight list nested directly under another item's text (no
                // blank line) leaves that text un-flushed; attribute it to the
                // enclosing item before the list frame shadows it.
                self.flush_pending_inlines();
                let path = self.next_path();
                self.open(
                    FrameKind::List {
                        path,
                        ordered: start_number.is_some(),
                        items: Vec::new(),
                    },
                    range,
                );
            }
            Tag::Item => {
                let path = self.next_path();
                self.open(
                    FrameKind::ListItem {
                        path,
                        content: Vec::new(),
                        checked: None,
                    },
                    range,
                );
            }
            Tag::CodeBlock(kind) => {
                let language = match kind {
                    CodeBlockKind::Fenced(lang) => {
                        let trimmed = lang.trim();
                        if trimmed.is_empty() {
                            None
                        } else {
                            Some(trimmed.to_string())
                        }
                    }
                    CodeBlockKind::Indented => None,
                };
                self.code_block = Some(CodeBlockAccum {
                    language,
                    code: String::new(),
                    source: range,
                    runs: RunAccum::default(),
                });
            }
            Tag::Link { dest_url, .. } => {
                let target = links::classify(&dest_url, self.containing_dir);
                self.open_link(LinkKind::Link(target), range);
            }
            Tag::Image { dest_url, .. } => {
                self.open_link(LinkKind::Image(dest_url.to_string()), range);
            }
            Tag::Strong => self.format_state.bold = true,
            Tag::Emphasis => self.format_state.italic = true,
            Tag::Strikethrough => self.format_state.strikethrough = true,
            _ => {}
        }
    }

    fn end(&mut self, tag_end: TagEnd, _range: Range<usize>) {
        match tag_end {
            TagEnd::MetadataBlock(_) => self.in_metadata = false,
            TagEnd::Heading(_) => {
                let Some(frame) = self.frames.pop() else {
                    return;
                };
                let FrameKind::Heading(level) = frame.kind else {
                    return;
                };
                let runs = self.runs.take();
                let source = split_adjusted_source(&frame, &runs);
                let content = process_inlines(std::mem::take(&mut self.inlines));
                self.push_block(AstNode::Heading { level, content }, source, runs);
                // Anything hoisted out of the heading follows it, in the order
                // it appeared in the source.
                self.drain_deferred();
            }
            TagEnd::Paragraph => {
                let Some(frame) = self.frames.pop() else {
                    return;
                };
                if !matches!(frame.kind, FrameKind::Paragraph) {
                    return;
                }
                if self.inlines.is_empty() {
                    self.runs.clear();
                    return;
                }
                let runs = self.runs.take();
                let source = split_adjusted_source(&frame, &runs);
                let content = process_inlines(std::mem::take(&mut self.inlines));
                self.push_block(AstNode::Paragraph { content }, source, runs);
            }
            TagEnd::BlockQuote(_) => {
                let Some(frame) = self.frames.pop() else {
                    return;
                };
                let FrameKind::Blockquote { path, nodes } = frame.kind else {
                    return;
                };
                self.push_container(AstNode::Blockquote { nodes }, path, frame.source);
            }
            TagEnd::List(_) => {
                let Some(frame) = self.frames.pop() else {
                    return;
                };
                let FrameKind::List {
                    path,
                    ordered,
                    items,
                } = frame.kind
                else {
                    return;
                };
                self.push_container(AstNode::List { ordered, items }, path, frame.source);
            }
            TagEnd::Item => {
                // Tight list items (the common `- a\n- b` form, and every task
                // list item) get their text as bare `Event::Text`, with no
                // `Paragraph` wrapper to trigger a flush. Flush into the item
                // before it closes, so the text is neither dropped nor
                // attributed to the item's parent.
                self.flush_pending_inlines();
                let Some(frame) = self.frames.pop() else {
                    return;
                };
                let FrameKind::ListItem {
                    path,
                    content,
                    checked,
                } = frame.kind
                else {
                    return;
                };
                self.push_container(AstNode::ListItem { content, checked }, path, frame.source);
            }
            TagEnd::CodeBlock => {
                let Some(mut accum) = self.code_block.take() else {
                    return;
                };
                let runs = accum.runs.take();
                self.push_block(
                    AstNode::CodeBlock {
                        language: accum.language,
                        code: accum.code,
                    },
                    Some(accum.source),
                    runs,
                );
            }
            TagEnd::Link => self.close_link(),
            TagEnd::Image => self.close_image(),
            TagEnd::Strong => self.format_state.bold = false,
            TagEnd::Emphasis => self.format_state.italic = false,
            TagEnd::Strikethrough => self.format_state.strikethrough = false,
            _ => {}
        }
    }

    fn text(&mut self, text: &CowStr<'_>, range: Range<usize>) {
        if self.in_metadata {
            // ADR-007 decision 5 and ADR-004: the frontmatter block is read
            // only, and is not part of the rendered document.
            return;
        }
        if text.is_empty() {
            // Would push an inline element with no run behind it, which is the
            // state that makes an enclosing Block unable to derive its extent.
            return;
        }
        if let Some(accum) = self.code_block.as_mut() {
            accum.code.push_str(text);
            let interpolable = self.source.get(range.clone()) == Some(&**text);
            accum.runs.push(text.chars().count(), range, interpolable);
            return;
        }
        self.push_run(text, range);
        let run = TextRun::from_state(text.to_string(), &self.format_state, false);
        self.push_inline(InlineElement::Text(run));
    }

    fn code_span(&mut self, text: &CowStr<'_>, range: Range<usize>) {
        // Never interpolable: the run's source carries the backticks its
        // rendered text does not, so an interior offset has no counterpart.
        self.push_run(text, range);
        let run = TextRun::from_state(text.to_string(), &self.format_state, true);
        self.push_inline(InlineElement::Text(run));
    }

    fn line_break(&mut self, range: Range<usize>) {
        // A soft break is one `\n` in both spaces; a hard break renders as one
        // `\n` from a two-space-plus-newline source, and the length check
        // below is what makes the second atomic without a special case.
        self.push_run(&CowStr::Borrowed("\n"), range);
        let run = TextRun::from_state("\n".to_string(), &self.format_state, false);
        self.push_inline(InlineElement::Text(run));
    }

    fn open_link(&mut self, kind: LinkKind, range: Range<usize>) {
        self.link_stack.push(LinkFrame {
            kind,
            content: Vec::new(),
            source: range,
            rendered_chars: 0,
        });
    }

    fn close_link(&mut self) {
        let Some(frame) = self.link_stack.pop() else {
            return;
        };

        // A link that renders no characters contributes nothing to either the
        // tree or the map, and emitting it does active harm. Its run would be
        // zero-width and therefore dropped, leaving an inline element with no
        // run behind it — which is exactly the state that used to make the
        // enclosing Block fall back to a fabricated span. The two shapes that
        // reach here are an empty link text (`[](x)`) and a link whose only
        // content was an Image that has already been hoisted into a Block of
        // its own (`[![alt](i.png)](u)`, the badge link ordinary in
        // externally-authored bundles). Its bytes stay on disk untouched, like
        // any other region no Block addresses.
        if frame.rendered_chars == 0 {
            return;
        }

        let content = process_inlines(frame.content);
        let element = match frame.kind {
            // `exists` is declared but not resolved here: it is whether
            // `target_id` matches a `notes` row, which needs the index. This
            // module sits upstream of the indexer, so `WSPC-D005` populates it.
            LinkKind::Link(LinkTarget::Internal(target_id)) => InlineElement::Link {
                target_id,
                exists: false,
                content,
            },
            LinkKind::Link(LinkTarget::External(url)) => {
                InlineElement::ExternalLink { url, content }
            }
            LinkKind::Image(url) => InlineElement::ExternalLink { url, content },
        };
        // One atomic run for the whole construct. `[text](dest)` is not its
        // own rendered text, so no interior offset interpolates; resolving to
        // the whole range is what keeps a selection touching a link from
        // splicing into the middle of its destination.
        self.emit_run(frame.rendered_chars, frame.source, false);
        self.push_inline(element);
    }

    fn close_image(&mut self) {
        let Some(frame) = self.link_stack.pop() else {
            return;
        };
        let alt_text: String = frame
            .content
            .iter()
            .map(|element| match element {
                InlineElement::Text(run) => run.content.as_str(),
                _ => "",
            })
            .collect();

        // `AstNode` has no inline image variant, so an inline image has to
        // become a Block of its own. Whichever frame it came out of must then
        // give up the bytes it now owns, or the two Blocks overlap and editing
        // either destroys the other.
        //
        // Paragraph and ListItem can hold Block children, so the text ahead of
        // the image is flushed into its own Block right here and document
        // order comes out right. `split` additionally makes the fragment left
        // behind derive its span from its runs rather than from the paragraph
        // tag, which is what trims the tail the image occupies.
        let mut defer = false;
        if let Some(frame) = self.frames.last_mut() {
            match frame.kind {
                FrameKind::Paragraph => frame.split = true,
                FrameKind::ListItem { .. } => {}
                // A heading's content is inline-only, so it cannot hold the
                // image and cannot be flushed mid-way without stranding its
                // text. The image is held back and emitted as the heading's
                // next *sibling* once the heading closes — pushing it
                // immediately put it in the tree ahead of the heading that
                // contained it, in the wrong document order.
                FrameKind::Heading(_) => {
                    frame.split = true;
                    defer = true;
                }
                _ => {}
            }
        }
        if !defer {
            self.flush_pending_inlines();
        }

        let rendered_chars = alt_text.chars().count();
        let mut runs = RunAccum::default();
        runs.push(rendered_chars, frame.source.clone(), false);
        let LinkKind::Image(url_or_path) = frame.kind else {
            return;
        };
        let node = AstNode::Image {
            alt_text,
            url_or_path,
        };
        if defer {
            self.deferred.push(DeferredBlock {
                node,
                source: frame.source,
                runs: runs.take(),
            });
            return;
        }
        self.push_block(node, Some(frame.source), runs.take());
    }

    /// Emits the Blocks held back from an inline-only frame, as siblings
    /// following the Block that frame produced.
    fn drain_deferred(&mut self) {
        for deferred in std::mem::take(&mut self.deferred) {
            self.push_block(deferred.node, Some(deferred.source), deferred.runs);
        }
    }

    fn push_run(&mut self, rendered: &CowStr<'_>, source: Range<usize>) {
        let interpolable = self.source.get(source.clone()) == Some(&**rendered);
        self.emit_run(rendered.chars().count(), source, interpolable);
    }

    fn emit_run(&mut self, rendered_chars: usize, source: Range<usize>, interpolable: bool) {
        if let Some(frame) = self.link_stack.last_mut() {
            frame.rendered_chars += rendered_chars;
            return;
        }
        self.runs.push(rendered_chars, source, interpolable);
    }

    fn push_inline(&mut self, element: InlineElement) {
        if let Some(frame) = self.link_stack.last_mut() {
            frame.content.push(element);
        } else {
            self.inlines.push(element);
        }
    }

    fn reset_inlines(&mut self) {
        self.inlines.clear();
        self.runs.clear();
    }

    fn open(&mut self, kind: FrameKind, source: Range<usize>) {
        self.frames.push(Frame {
            kind,
            source,
            split: false,
        });
    }

    /// Flushes inline content accumulated outside any `Paragraph` tag — bare
    /// text directly under a tight list item — into a synthetic paragraph.
    ///
    /// Its span is the extent of its runs, since it has no tag of its own, and
    /// it gets no span at all when it has no runs. That case is reachable
    /// whenever inline content produces AST elements that render nothing, and
    /// the previous fallback of `0..0` was a silent corruption: splicing that
    /// path wrote at byte zero of the file and left the real Block alone.
    fn flush_pending_inlines(&mut self) {
        if self.inlines.is_empty() {
            self.runs.clear();
            return;
        }
        let runs = self.runs.take();
        let source = run_extent(&runs);
        let content = process_inlines(std::mem::take(&mut self.inlines));
        self.push_block(AstNode::Paragraph { content }, source, runs);
    }

    /// The index of the innermost frame that actually holds Block children.
    fn container_index(&self) -> Option<usize> {
        self.frames
            .iter()
            .rposition(|frame| frame.kind.holds_children())
    }

    /// The `block_path` the next Block attached here will have.
    fn next_path(&self) -> BlockPath {
        let Some(index) = self.container_index() else {
            return vec![self.root_nodes.len()];
        };
        let (path, filled) = match &self.frames[index].kind {
            FrameKind::Blockquote { path, nodes } => (path, nodes.len()),
            FrameKind::List { path, items, .. } => (path, items.len()),
            FrameKind::ListItem { path, content, .. } => (path, content.len()),
            // `container_index` only ever returns one of the three above.
            _ => unreachable!("container_index returned a non-container frame"),
        };
        let mut child = path.clone();
        child.push(filled);
        child
    }

    fn attach(&mut self, node: AstNode) {
        let Some(index) = self.container_index() else {
            self.root_nodes.push(node);
            return;
        };
        match &mut self.frames[index].kind {
            FrameKind::Blockquote { nodes, .. } => nodes.push(node),
            FrameKind::List { items, .. } => items.push(node),
            FrameKind::ListItem { content, .. } => content.push(node),
            _ => unreachable!("container_index returned a non-container frame"),
        }
    }

    /// Attaches a Block to the tree and, when a truthful source range for it
    /// exists, registers that range in the span map.
    ///
    /// `source` is an `Option` because refusing to register is the correct
    /// answer for a Block whose extent cannot be determined — inline content
    /// that renders nothing, or a fragment left behind after a Block was
    /// hoisted out of it. Registering a fabricated range is far worse than
    /// registering none: an unregistered path makes `splice_block` return
    /// `UnknownBlock`, while a wrong one makes it write over the wrong bytes.
    fn push_block(&mut self, node: AstNode, source: Option<Range<usize>>, runs: Vec<InlineRun>) {
        if let Some(source) = source {
            let path = self.next_path();
            self.spans.push_block(path, source, runs);
        }
        self.attach(node);
    }

    /// A container's path was fixed when it opened, because its children were
    /// addressed relative to it while it was still on the stack.
    fn push_container(&mut self, node: AstNode, path: BlockPath, source: Range<usize>) {
        self.spans.push_block(path, source, Vec::new());
        self.attach(node);
    }
}

/// The source range to register for a Block built from an inline frame.
///
/// Ordinarily this is the frame's own tag range, which is what makes a
/// heading's `# ` and a paragraph's terminating newline part of the Block a
/// caller edits. A frame an inline Image was hoisted out of is the exception:
/// the hoisted Image is registered as its own Block, so the fragment left
/// behind must not claim any of the bytes the Image now owns, or editing
/// either one destroys the other. For that case the range is the extent of the
/// fragment's own runs — trimmed at *both* ends, since an Image may sit on
/// either side of it — and `None` when the fragment has no runs to derive an
/// extent from.
fn split_adjusted_source(frame: &Frame, runs: &[InlineRun]) -> Option<Range<usize>> {
    if !frame.split {
        return Some(frame.source.clone());
    }
    run_extent(runs)
}

/// The source range spanned by a set of runs, or `None` when there are none.
///
/// Runs do not tile, so this is the outer extent rather than a union: the gaps
/// between runs are markup belonging to the same Block.
fn run_extent(runs: &[InlineRun]) -> Option<Range<usize>> {
    match (runs.first(), runs.last()) {
        (Some(first), Some(last)) => Some(first.source.start..last.source.end),
        _ => None,
    }
}

fn process_inlines(raw_inlines: Vec<InlineElement>) -> Vec<InlineElement> {
    merge_adjacent_text_runs(raw_inlines)
        .into_iter()
        .map(|element| match element {
            InlineElement::ExternalLink { url, content } => InlineElement::ExternalLink {
                url,
                content: process_inlines(content),
            },
            InlineElement::Link {
                target_id,
                exists,
                content,
            } => InlineElement::Link {
                target_id,
                exists,
                content: process_inlines(content),
            },
            text @ InlineElement::Text(_) => text,
        })
        .collect()
}

fn merge_adjacent_text_runs(inlines: Vec<InlineElement>) -> Vec<InlineElement> {
    let mut merged: Vec<InlineElement> = Vec::new();

    for element in inlines {
        if let InlineElement::Text(ref run) = element {
            if let Some(InlineElement::Text(ref mut last)) = merged.last_mut() {
                if last.bold == run.bold
                    && last.italic == run.italic
                    && last.strikethrough == run.strikethrough
                    && last.code == run.code
                {
                    last.content.push_str(&run.content);
                    continue;
                }
            }
        }
        merged.push(element);
    }

    merged
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::markdown::spans::rendered_text;

    #[test]
    fn test_heading_and_bold_parsing() {
        let md = "# Title\n\nThis is **bold** text.";
        let ast = parse_markdown(md);

        assert_eq!(ast.len(), 2);

        match &ast[0] {
            AstNode::Heading { level, content } => {
                assert_eq!(*level, 1);
                assert_eq!(content.len(), 1);
                if let InlineElement::Text(tr) = &content[0] {
                    assert_eq!(tr.content, "Title");
                    assert!(!tr.bold);
                } else {
                    panic!("Expected Text inline element");
                }
            }
            _ => panic!("Expected Heading node"),
        }

        match &ast[1] {
            AstNode::Paragraph { content } => {
                assert_eq!(content.len(), 3);
                if let InlineElement::Text(tr) = &content[0] {
                    assert_eq!(tr.content, "This is ");
                    assert!(!tr.bold);
                } else {
                    panic!("Expected Text inline element");
                }
                if let InlineElement::Text(tr) = &content[1] {
                    assert_eq!(tr.content, "bold");
                    assert!(tr.bold);
                } else {
                    panic!("Expected Text inline element");
                }
                if let InlineElement::Text(tr) = &content[2] {
                    assert_eq!(tr.content, " text.");
                    assert!(!tr.bold);
                } else {
                    panic!("Expected Text inline element");
                }
            }
            _ => panic!("Expected Paragraph node"),
        }
    }

    #[test]
    fn internal_link_carries_the_target_concept_id() {
        // The on-disk form of a Link is a bundle-absolute Markdown link with
        // an angle-bracket-wrapped destination (ADR-004 decision 5, OKF §6.1);
        // classification is `okf::links`' job, not a second copy here.
        let md = "See [Architecture](</projects/architecture.md>) for more.";
        let ast = parse_note(md, "").ast;

        assert_eq!(ast.len(), 1);
        let AstNode::Paragraph { content } = &ast[0] else {
            panic!("Expected Paragraph node");
        };
        assert_eq!(content.len(), 3);
        let InlineElement::Link {
            target_id,
            exists,
            content: inner,
        } = &content[1]
        else {
            panic!("Expected Link inline element, got {:?}", content[1]);
        };
        assert_eq!(target_id, "projects/architecture");
        // Declared here, resolved by `WSPC-D005` against the index.
        assert!(!exists);
        assert_eq!(inner.len(), 1);
        match &inner[0] {
            InlineElement::Text(tr) => assert_eq!(tr.content, "Architecture"),
            other => panic!("Expected Text inline element, got {other:?}"),
        }
    }

    #[test]
    fn relative_link_resolves_against_the_containing_directory() {
        let md = "See [Sibling](<sibling.md>) for more.";
        let ast = parse_note(md, "projects").ast;

        let AstNode::Paragraph { content } = &ast[0] else {
            panic!("Expected Paragraph node");
        };
        let InlineElement::Link { target_id, .. } = &content[1] else {
            panic!("Expected Link inline element");
        };
        assert_eq!(target_id, "projects/sibling");
    }

    #[test]
    fn test_external_link_parsing() {
        let md = "See [the docs](https://example.com/docs) for details.";
        let ast = parse_markdown(md);

        assert_eq!(ast.len(), 1);
        if let AstNode::Paragraph { content } = &ast[0] {
            assert_eq!(content.len(), 3);
            if let InlineElement::ExternalLink {
                url,
                content: inner_content,
            } = &content[1]
            {
                assert_eq!(url, "https://example.com/docs");
                assert_eq!(inner_content.len(), 1);
                match &inner_content[0] {
                    InlineElement::Text(tr) => assert_eq!(tr.content, "the docs"),
                    _ => panic!("Expected Text inline element"),
                }
            } else {
                panic!("Expected ExternalLink inline element");
            }
        } else {
            panic!("Expected Paragraph node");
        }
    }

    #[test]
    fn double_bracket_syntax_stays_literal_text() {
        // ADR-004 decision 5 and the `InlineElement::Link` contract: `[[` is a
        // UI trigger and is never stored on disk, so nothing in the parser may
        // invent a Link out of it.
        let md = "Check out [[My Note]] for details.";
        let ast = parse_markdown(md);

        assert_eq!(ast.len(), 1);
        let AstNode::Paragraph { content } = &ast[0] else {
            panic!("Expected Paragraph node");
        };
        assert_eq!(rendered_text(&ast[0]), "Check out [[My Note]] for details.");
        assert!(content
            .iter()
            .all(|element| matches!(element, InlineElement::Text(_))));
    }

    #[test]
    fn frontmatter_is_a_span_and_not_an_ast_node() {
        let md = "---\ntype: note\ntitle: T\ncustom: keep\n---\n\n# H\n";
        let parsed = parse_note(md, "");

        assert_eq!(parsed.ast.len(), 1);
        assert!(matches!(parsed.ast[0], AstNode::Heading { .. }));
        let frontmatter = parsed.spans.frontmatter().expect("frontmatter span");
        assert_eq!(
            &md[frontmatter],
            "---\ntype: note\ntitle: T\ncustom: keep\n---"
        );
    }

    /// Pulls the text of a tight list item's first (implicit) paragraph.
    fn item_text(node: &AstNode) -> &str {
        match node {
            AstNode::ListItem { content, .. } => match content.first() {
                Some(AstNode::Paragraph { content }) => match content.first() {
                    Some(InlineElement::Text(tr)) => tr.content.as_str(),
                    _ => panic!("Expected Text inline element in item paragraph"),
                },
                _ => panic!("Expected Paragraph as item content"),
            },
            _ => panic!("Expected ListItem"),
        }
    }

    #[test]
    fn test_tight_list_item_content() {
        let md = "```rust\nfn main() {}\n```\n\n- Item 1\n- Item 2";
        let ast = parse_markdown(md);

        assert_eq!(ast.len(), 2);
        match &ast[0] {
            AstNode::CodeBlock { language, code } => {
                assert_eq!(language.as_deref(), Some("rust"));
                assert_eq!(code, "fn main() {}\n");
            }
            _ => panic!("Expected CodeBlock"),
        }

        match &ast[1] {
            AstNode::List { ordered, items } => {
                assert!(!ordered);
                assert_eq!(items.len(), 2);
                assert_eq!(item_text(&items[0]), "Item 1");
                assert_eq!(item_text(&items[1]), "Item 2");
            }
            _ => panic!("Expected List"),
        }
    }

    #[test]
    fn test_task_list_item_content() {
        let md = "- [x] done\n- [ ] todo";
        let ast = parse_markdown(md);

        assert_eq!(ast.len(), 1);
        match &ast[0] {
            AstNode::List { ordered, items } => {
                assert!(!ordered);
                assert_eq!(items.len(), 2);

                match &items[0] {
                    AstNode::ListItem { checked, .. } => assert_eq!(*checked, Some(true)),
                    _ => panic!("Expected ListItem"),
                }
                assert_eq!(item_text(&items[0]), "done");

                match &items[1] {
                    AstNode::ListItem { checked, .. } => assert_eq!(*checked, Some(false)),
                    _ => panic!("Expected ListItem"),
                }
                assert_eq!(item_text(&items[1]), "todo");
            }
            _ => panic!("Expected List"),
        }
    }

    #[test]
    fn test_nested_tight_list_content() {
        let md = "- Outer\n  - Inner";
        let ast = parse_markdown(md);

        assert_eq!(ast.len(), 1);
        match &ast[0] {
            AstNode::List { items, .. } => {
                assert_eq!(items.len(), 1);
                match &items[0] {
                    AstNode::ListItem { content, .. } => {
                        assert_eq!(content.len(), 2);
                        match &content[0] {
                            AstNode::Paragraph { content } => match &content[0] {
                                InlineElement::Text(tr) => assert_eq!(tr.content, "Outer"),
                                _ => panic!("Expected Text inline element"),
                            },
                            _ => panic!("Expected Paragraph for outer item text"),
                        }
                        match &content[1] {
                            AstNode::List {
                                items: inner_items, ..
                            } => {
                                assert_eq!(inner_items.len(), 1);
                                assert_eq!(item_text(&inner_items[0]), "Inner");
                            }
                            _ => panic!("Expected nested List"),
                        }
                    }
                    _ => panic!("Expected ListItem"),
                }
            }
            _ => panic!("Expected List"),
        }
    }

    #[test]
    fn test_image_inside_list_item_preserves_order() {
        let md = "- text before ![a](x.png) after";
        let ast = parse_markdown(md);

        assert_eq!(ast.len(), 1);
        match &ast[0] {
            AstNode::List { items, .. } => {
                assert_eq!(items.len(), 1);
                match &items[0] {
                    AstNode::ListItem { content, .. } => {
                        assert_eq!(content.len(), 3);
                        match &content[0] {
                            AstNode::Paragraph { content } => match &content[0] {
                                InlineElement::Text(tr) => assert_eq!(tr.content, "text before "),
                                _ => panic!("Expected Text inline element"),
                            },
                            _ => panic!("Expected Paragraph before image"),
                        }
                        match &content[1] {
                            AstNode::Image {
                                alt_text,
                                url_or_path,
                            } => {
                                assert_eq!(alt_text, "a");
                                assert_eq!(url_or_path, "x.png");
                            }
                            _ => panic!("Expected Image node"),
                        }
                        match &content[2] {
                            AstNode::Paragraph { content } => match &content[0] {
                                InlineElement::Text(tr) => assert_eq!(tr.content, " after"),
                                _ => panic!("Expected Text inline element"),
                            },
                            _ => panic!("Expected Paragraph after image"),
                        }
                    }
                    _ => panic!("Expected ListItem"),
                }
            }
            _ => panic!("Expected List"),
        }
    }

    #[test]
    fn test_image_inside_blockquote_stays_nested() {
        let md = "> quoted text ![a](x.png)";
        let ast = parse_markdown(md);

        assert_eq!(ast.len(), 1);
        match &ast[0] {
            AstNode::Blockquote { nodes } => {
                assert_eq!(nodes.len(), 2);
                match &nodes[0] {
                    AstNode::Paragraph { content } => match &content[0] {
                        InlineElement::Text(tr) => assert_eq!(tr.content, "quoted text "),
                        _ => panic!("Expected Text inline element"),
                    },
                    _ => panic!("Expected Paragraph before image"),
                }
                match &nodes[1] {
                    AstNode::Image {
                        alt_text,
                        url_or_path,
                    } => {
                        assert_eq!(alt_text, "a");
                        assert_eq!(url_or_path, "x.png");
                    }
                    _ => panic!("Expected Image node"),
                }
            }
            _ => panic!("Expected Blockquote"),
        }
    }

    #[test]
    fn test_image_inside_loose_list_item_stays_nested() {
        let md = "- first ![a](x.png)\n\n- second";
        let ast = parse_markdown(md);

        assert_eq!(ast.len(), 1);
        match &ast[0] {
            AstNode::List { items, .. } => {
                assert_eq!(items.len(), 2);
                match &items[0] {
                    AstNode::ListItem { content, .. } => {
                        assert_eq!(content.len(), 2);
                        match &content[0] {
                            AstNode::Paragraph { content } => match &content[0] {
                                InlineElement::Text(tr) => assert_eq!(tr.content, "first "),
                                _ => panic!("Expected Text inline element"),
                            },
                            _ => panic!("Expected Paragraph before image"),
                        }
                        match &content[1] {
                            AstNode::Image {
                                alt_text,
                                url_or_path,
                            } => {
                                assert_eq!(alt_text, "a");
                                assert_eq!(url_or_path, "x.png");
                            }
                            _ => panic!("Expected Image node"),
                        }
                    }
                    _ => panic!("Expected ListItem"),
                }
                assert_eq!(item_text(&items[1]), "second");
            }
            _ => panic!("Expected List"),
        }
    }

    #[test]
    fn test_inline_image_in_paragraph() {
        let md = "Before image ![alt text](http://example.com/img.png) After image";
        let ast = parse_markdown(md);

        assert_eq!(ast.len(), 3);
        match &ast[0] {
            AstNode::Paragraph { content } => {
                assert_eq!(content.len(), 1);
                if let InlineElement::Text(tr) = &content[0] {
                    assert_eq!(tr.content, "Before image ");
                }
            }
            _ => panic!("Expected Paragraph before image"),
        }
        match &ast[1] {
            AstNode::Image {
                alt_text,
                url_or_path,
            } => {
                assert_eq!(alt_text, "alt text");
                assert_eq!(url_or_path, "http://example.com/img.png");
            }
            _ => panic!("Expected Image node"),
        }
        match &ast[2] {
            AstNode::Paragraph { content } => {
                assert_eq!(content.len(), 1);
                if let InlineElement::Text(tr) = &content[0] {
                    assert_eq!(tr.content, " After image");
                }
            }
            _ => panic!("Expected Paragraph after image"),
        }
    }

    /// The two entry points differ on exactly one thing, and this is it: a
    /// `---`-fenced block at byte zero is frontmatter to [`parse_note`] and
    /// ordinary Markdown to [`parse_markdown_fragment`].
    ///
    /// Frontmatter contributes no `AstNode` at all (its bytes are recorded in
    /// the span map instead), so a caller that parses a *fragment* with the
    /// metadata option loses that region outright rather than rendering it
    /// oddly — which is what made this a content-loss defect in the conflict
    /// collapse rather than a cosmetic one.
    #[test]
    fn a_fragment_reads_a_leading_fence_as_a_thematic_break_not_as_frontmatter() {
        let source = "---\nMine\n---\n";

        assert!(
            parse_note(source, "").ast.is_empty(),
            "the whole document was frontmatter, so it contributes no Block"
        );

        let fragment = parse_markdown_fragment(source, "");
        assert!(
            !fragment.is_empty(),
            "a fragment must keep the content a metadata block would swallow"
        );
        assert!(
            format!("{fragment:?}").contains("Mine"),
            "the fragment lost its text: {fragment:?}"
        );
    }

    /// A fragment resolves relative Link destinations against `containing_dir`
    /// exactly as [`parse_note`] does — the parameter is not decoration.
    #[test]
    fn a_fragment_resolves_relative_links_against_its_containing_directory() {
        let fragment = parse_markdown_fragment("See [u](Other.md).\n", "sub");

        assert!(
            format!("{fragment:?}").contains("sub/Other"),
            "a relative destination resolved against the bundle root: {fragment:?}"
        );
    }
}
