use pulldown_cmark::{Event, Options, Parser, Tag, TagEnd};

pub use crate::api::ffi_api::{AstNode, InlineElement, TextRun};

#[derive(Default)]
struct FormatState {
    bold: bool,
    italic: bool,
    strikethrough: bool,
}

struct LinkFrame {
    url: String,
    content: Vec<InlineElement>,
}

struct CodeBlockAccum {
    language: Option<String>,
    code: String,
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

    fn with_content(&self, content: String) -> Self {
        TextRun {
            content,
            ..self.clone()
        }
    }
}

pub fn parse_markdown(input: &str) -> Vec<AstNode> {
    let mut options = Options::empty();
    options.insert(Options::ENABLE_STRIKETHROUGH);
    options.insert(Options::ENABLE_TASKLISTS);

    let parser = Parser::new_ext(input, options);
    let mut root_nodes: Vec<AstNode> = Vec::new();
    let mut node_stack: Vec<ContainerNode> = Vec::new();

    let mut current_inlines: Vec<InlineElement> = Vec::new();
    let mut format_state = FormatState::default();
    let mut current_code_block: Option<CodeBlockAccum> = None;
    let mut link_stack: Vec<LinkFrame> = Vec::new();

    for event in parser {
        match event {
            Event::Start(tag) => match tag {
                Tag::Heading { level, .. } => {
                    current_inlines.clear();
                    node_stack.push(ContainerNode::Heading(level as u8));
                }
                Tag::Paragraph => {
                    current_inlines.clear();
                    node_stack.push(ContainerNode::Paragraph);
                }
                Tag::BlockQuote(_) => {
                    node_stack.push(ContainerNode::Blockquote(Vec::new()));
                }
                Tag::List(start_number) => {
                    // A tight list nested directly under another item's text (no
                    // blank line) leaves that text un-flushed in `current_inlines`;
                    // attribute it to the enclosing item before it gets shadowed.
                    flush_pending_inlines(&mut root_nodes, &mut node_stack, &mut current_inlines);
                    node_stack.push(ContainerNode::List {
                        ordered: start_number.is_some(),
                        items: Vec::new(),
                    });
                }
                Tag::Item => {
                    node_stack.push(ContainerNode::ListItem {
                        content: Vec::new(),
                        checked: None,
                    });
                }
                Tag::CodeBlock(kind) => {
                    let lang = match kind {
                        pulldown_cmark::CodeBlockKind::Fenced(lang) => {
                            let s = lang.trim();
                            if s.is_empty() {
                                None
                            } else {
                                Some(s.to_string())
                            }
                        }
                        pulldown_cmark::CodeBlockKind::Indented => None,
                    };
                    current_code_block = Some(CodeBlockAccum {
                        language: lang,
                        code: String::new(),
                    });
                }
                Tag::Link { dest_url, .. } | Tag::Image { dest_url, .. } => {
                    link_stack.push(LinkFrame {
                        url: dest_url.to_string(),
                        content: Vec::new(),
                    });
                }
                Tag::Strong => format_state.bold = true,
                Tag::Emphasis => format_state.italic = true,
                Tag::Strikethrough => format_state.strikethrough = true,
                _ => {}
            },
            Event::End(tag_end) => match tag_end {
                TagEnd::Heading(_) => {
                    if let Some(ContainerNode::Heading(level)) = node_stack.pop() {
                        let content = process_inlines(std::mem::take(&mut current_inlines));
                        let node = AstNode::Heading { level, content };
                        push_node(&mut root_nodes, &mut node_stack, node);
                    }
                }
                TagEnd::Paragraph => {
                    if let Some(ContainerNode::Paragraph) = node_stack.pop() {
                        if !current_inlines.is_empty() {
                            let content = process_inlines(std::mem::take(&mut current_inlines));
                            let node = AstNode::Paragraph { content };
                            push_node(&mut root_nodes, &mut node_stack, node);
                        }
                    }
                }
                TagEnd::BlockQuote(_) => {
                    if let Some(ContainerNode::Blockquote(nodes)) = node_stack.pop() {
                        let node = AstNode::Blockquote { nodes };
                        push_node(&mut root_nodes, &mut node_stack, node);
                    }
                }
                TagEnd::List(_) => {
                    if let Some(ContainerNode::List { ordered, items }) = node_stack.pop() {
                        let node = AstNode::List { ordered, items };
                        push_node(&mut root_nodes, &mut node_stack, node);
                    }
                }
                TagEnd::Item => {
                    if let Some(ContainerNode::ListItem {
                        mut content,
                        checked,
                    }) = node_stack.pop()
                    {
                        // Tight list items (the common `- a\n- b` form, and all task
                        // list items) get their text as bare `Event::Text`, with no
                        // `Paragraph` wrapper to trigger a flush. Flush here so that
                        // text isn't silently dropped.
                        if !current_inlines.is_empty() {
                            let inline_content =
                                process_inlines(std::mem::take(&mut current_inlines));
                            content.push(AstNode::Paragraph {
                                content: inline_content,
                            });
                        }
                        let node = AstNode::ListItem { content, checked };
                        push_node(&mut root_nodes, &mut node_stack, node);
                    }
                }
                TagEnd::CodeBlock => {
                    if let Some(accum) = current_code_block.take() {
                        let node = AstNode::CodeBlock {
                            language: accum.language,
                            code: accum.code,
                        };
                        push_node(&mut root_nodes, &mut node_stack, node);
                    }
                }
                TagEnd::Link => {
                    if let Some(frame) = link_stack.pop() {
                        let processed_content = process_inlines(frame.content);
                        let ext_link = InlineElement::ExternalLink {
                            url: frame.url,
                            content: processed_content,
                        };
                        push_inline(ext_link, &mut current_inlines, &mut link_stack);
                    }
                }
                TagEnd::Image => {
                    if let Some(frame) = link_stack.pop() {
                        let alt_text = frame
                            .content
                            .iter()
                            .map(|elem| match elem {
                                InlineElement::Text(tr) => tr.content.as_str(),
                                _ => "",
                            })
                            .collect::<Vec<_>>()
                            .join("");
                        let node = AstNode::Image {
                            alt_text,
                            url_or_path: frame.url,
                        };

                        // Images are block nodes in this AST, so any inline text
                        // accumulated ahead of them (in a paragraph, or a tight
                        // list item, which never opens its own Paragraph tag)
                        // must be flushed as its own node first to preserve order.
                        // Deliberately excludes Heading: a heading's content is
                        // inline-only (Vec<InlineElement>), so flushing here would
                        // strand it as an empty node instead of keeping its text
                        // attached - an image trailing heading text is a known,
                        // unhandled edge case rather than one this flush can fix.
                        if matches!(
                            node_stack.last(),
                            Some(ContainerNode::Paragraph) | Some(ContainerNode::ListItem { .. })
                        ) {
                            flush_pending_inlines(
                                &mut root_nodes,
                                &mut node_stack,
                                &mut current_inlines,
                            );
                        }
                        push_node(&mut root_nodes, &mut node_stack, node);
                    }
                }
                TagEnd::Strong => format_state.bold = false,
                TagEnd::Emphasis => format_state.italic = false,
                TagEnd::Strikethrough => format_state.strikethrough = false,
                _ => {}
            },
            Event::Text(text) => {
                if let Some(ref mut accum) = current_code_block {
                    accum.code.push_str(&text);
                } else {
                    push_raw_text(&text, &format_state, &mut current_inlines, &mut link_stack);
                }
            }
            Event::Code(text) => {
                let text_run = TextRun::from_state(text.to_string(), &format_state, true);
                push_inline(
                    InlineElement::Text(text_run),
                    &mut current_inlines,
                    &mut link_stack,
                );
            }
            Event::Rule => {
                let node = AstNode::ThematicBreak;
                push_node(&mut root_nodes, &mut node_stack, node);
            }
            Event::SoftBreak | Event::HardBreak => {
                let text_run = TextRun::from_state("\n".to_string(), &format_state, false);
                push_inline(
                    InlineElement::Text(text_run),
                    &mut current_inlines,
                    &mut link_stack,
                );
            }
            Event::TaskListMarker(checked) => {
                if let Some(ContainerNode::ListItem {
                    checked: ref mut c, ..
                }) = node_stack.last_mut()
                {
                    *c = Some(checked);
                }
            }
            _ => {}
        }
    }

    root_nodes
}

enum ContainerNode {
    Heading(u8),
    Paragraph,
    Blockquote(Vec<AstNode>),
    List {
        ordered: bool,
        items: Vec<AstNode>,
    },
    ListItem {
        content: Vec<AstNode>,
        checked: Option<bool>,
    },
}

/// Attaches `node` to the nearest ancestor that actually holds child nodes,
/// skipping past `Heading`/`Paragraph` frames on the stack. Those two exist
/// only to accumulate inline content and never hold block-level children, so
/// treating the topmost frame as "the parent" (regardless of its kind) would
/// wrongly hoist nodes to the document root whenever a block node (e.g. an
/// image) is pushed while a paragraph inside a blockquote or list item is
/// still open.
fn push_node(root_nodes: &mut Vec<AstNode>, node_stack: &mut [ContainerNode], node: AstNode) {
    for parent in node_stack.iter_mut().rev() {
        match parent {
            ContainerNode::Blockquote(nodes) => {
                nodes.push(node);
                return;
            }
            ContainerNode::List { items, .. } => {
                items.push(node);
                return;
            }
            ContainerNode::ListItem { content, .. } => {
                content.push(node);
                return;
            }
            ContainerNode::Heading(_) | ContainerNode::Paragraph => {}
        }
    }
    root_nodes.push(node);
}

/// Flushes any inline content accumulated outside of a `Paragraph` tag (e.g.
/// bare text directly under a tight list item) into a synthetic `Paragraph`
/// node attached to the current container. No-op when nothing is pending.
fn flush_pending_inlines(
    root_nodes: &mut Vec<AstNode>,
    node_stack: &mut [ContainerNode],
    current_inlines: &mut Vec<InlineElement>,
) {
    if current_inlines.is_empty() {
        return;
    }
    let content = process_inlines(std::mem::take(current_inlines));
    push_node(root_nodes, node_stack, AstNode::Paragraph { content });
}

fn push_inline(
    elem: InlineElement,
    current_inlines: &mut Vec<InlineElement>,
    link_stack: &mut [LinkFrame],
) {
    if let Some(frame) = link_stack.last_mut() {
        frame.content.push(elem);
    } else {
        current_inlines.push(elem);
    }
}

fn push_raw_text(
    text: &str,
    format_state: &FormatState,
    current_inlines: &mut Vec<InlineElement>,
    link_stack: &mut [LinkFrame],
) {
    let tr = TextRun::from_state(text.to_string(), format_state, false);
    push_inline(InlineElement::Text(tr), current_inlines, link_stack);
}

fn process_inlines(raw_inlines: Vec<InlineElement>) -> Vec<InlineElement> {
    let merged = merge_adjacent_text_runs(raw_inlines);
    let mut expanded = Vec::new();

    for elem in merged {
        match elem {
            InlineElement::Text(tr) => {
                if !tr.code {
                    parse_wikilinks_in_text_run(tr, &mut expanded);
                } else {
                    expanded.push(InlineElement::Text(tr));
                }
            }
            InlineElement::ExternalLink { url, content } => {
                expanded.push(InlineElement::ExternalLink {
                    url,
                    content: process_inlines(content),
                });
            }
            InlineElement::Link {
                target_title,
                resolved_note_id,
                content,
            } => {
                expanded.push(InlineElement::Link {
                    target_title,
                    resolved_note_id,
                    content: process_inlines(content),
                });
            }
        }
    }

    expanded
}

fn merge_adjacent_text_runs(inlines: Vec<InlineElement>) -> Vec<InlineElement> {
    let mut merged: Vec<InlineElement> = Vec::new();

    for elem in inlines {
        if let InlineElement::Text(ref tr) = elem {
            if let Some(InlineElement::Text(ref mut last_tr)) = merged.last_mut() {
                if last_tr.bold == tr.bold
                    && last_tr.italic == tr.italic
                    && last_tr.strikethrough == tr.strikethrough
                    && last_tr.code == tr.code
                {
                    last_tr.content.push_str(&tr.content);
                    continue;
                }
            }
        }
        merged.push(elem);
    }

    merged
}

fn parse_wikilinks_in_text_run(tr: TextRun, out: &mut Vec<InlineElement>) {
    let text = &tr.content;
    let mut rest = text.as_str();

    while let Some(start_idx) = rest.find("[[") {
        if start_idx > 0 {
            let before = &rest[..start_idx];
            out.push(InlineElement::Text(tr.with_content(before.to_string())));
        }
        let after_start = &rest[start_idx + 2..];
        if let Some(end_idx) = after_start.find("]]") {
            let inner = &after_start[..end_idx];
            let (target_title, display_text) = if let Some(pipe_idx) = inner.find('|') {
                (&inner[..pipe_idx], &inner[pipe_idx + 1..])
            } else {
                (inner, inner)
            };

            out.push(InlineElement::Link {
                target_title: target_title.to_string(),
                resolved_note_id: None,
                content: vec![InlineElement::Text(
                    tr.with_content(display_text.to_string()),
                )],
            });

            rest = &after_start[end_idx + 2..];
        } else {
            // No closing `]]`: emit the unmatched `[[...` tail as literal text.
            // `before` (the prefix up to `start_idx`) was already pushed above.
            out.push(InlineElement::Text(
                tr.with_content(rest[start_idx..].to_string()),
            ));
            return;
        }
    }

    if !rest.is_empty() {
        out.push(InlineElement::Text(tr.with_content(rest.to_string())));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
                }
                if let InlineElement::Text(tr) = &content[1] {
                    assert_eq!(tr.content, "bold");
                    assert!(tr.bold);
                }
                if let InlineElement::Text(tr) = &content[2] {
                    assert_eq!(tr.content, " text.");
                    assert!(!tr.bold);
                }
            }
            _ => panic!("Expected Paragraph node"),
        }
    }

    #[test]
    fn test_wikilink_parsing() {
        let md = "Check out [[My Note]] for details.";
        let ast = parse_markdown(md);

        assert_eq!(ast.len(), 1);
        if let AstNode::Paragraph { content } = &ast[0] {
            assert_eq!(content.len(), 3);
            if let InlineElement::Link {
                target_title,
                content: inner_content,
                ..
            } = &content[1]
            {
                assert_eq!(target_title, "My Note");
                assert_eq!(inner_content.len(), 1);
            } else {
                panic!("Expected Link inline element");
            }
        } else {
            panic!("Expected Paragraph node");
        }
    }

    #[test]
    fn test_wikilink_with_display_text() {
        let md = "Check out [[My Note|the note]] for details.";
        let ast = parse_markdown(md);

        assert_eq!(ast.len(), 1);
        if let AstNode::Paragraph { content } = &ast[0] {
            assert_eq!(content.len(), 3);
            if let InlineElement::Link {
                target_title,
                content: inner_content,
                ..
            } = &content[1]
            {
                assert_eq!(target_title, "My Note");
                assert_eq!(inner_content.len(), 1);
                match &inner_content[0] {
                    InlineElement::Text(tr) => assert_eq!(tr.content, "the note"),
                    _ => panic!("Expected Text inline element"),
                }
            } else {
                panic!("Expected Link inline element");
            }
        } else {
            panic!("Expected Paragraph node");
        }
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
    fn test_unterminated_wikilink_does_not_duplicate_prefix() {
        let md = "abc [[unclosed";
        let ast = parse_markdown(md);

        assert_eq!(ast.len(), 1);
        if let AstNode::Paragraph { content } = &ast[0] {
            let joined: String = content
                .iter()
                .map(|elem| match elem {
                    InlineElement::Text(tr) => tr.content.as_str(),
                    _ => "",
                })
                .collect();
            assert_eq!(joined, "abc [[unclosed");
        } else {
            panic!("Expected Paragraph node");
        }
    }

    #[test]
    fn test_multiple_unterminated_wikilinks_do_not_duplicate_prefix() {
        let md = "see [[A]] and [[B";
        let ast = parse_markdown(md);

        assert_eq!(ast.len(), 1);
        if let AstNode::Paragraph { content } = &ast[0] {
            let joined: String = content
                .iter()
                .map(|elem| match elem {
                    InlineElement::Text(tr) => tr.content.to_string(),
                    InlineElement::Link {
                        target_title,
                        content,
                        ..
                    } => {
                        let _ = target_title;
                        content
                            .iter()
                            .map(|inner| match inner {
                                InlineElement::Text(tr) => tr.content.as_str(),
                                _ => "",
                            })
                            .collect()
                    }
                    _ => String::new(),
                })
                .collect();
            assert_eq!(joined, "see A and [[B");
        } else {
            panic!("Expected Paragraph node");
        }
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
}
