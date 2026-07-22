use pulldown_cmark::{Event, Options, Parser, Tag, TagEnd};

pub use crate::api::ffi_api::{AstNode, InlineElement, TextRun};

#[derive(Default)]
struct FormatState {
    bold: bool,
    italic: bool,
    strikethrough: bool,
}

pub fn parse_markdown(input: &str) -> Vec<AstNode> {
    let mut options = Options::empty();
    options.insert(Options::ENABLE_TABLES);
    options.insert(Options::ENABLE_FOOTNOTES);
    options.insert(Options::ENABLE_STRIKETHROUGH);
    options.insert(Options::ENABLE_TASKLISTS);

    let parser = Parser::new_ext(input, options);
    let mut root_nodes: Vec<AstNode> = Vec::new();
    let mut node_stack: Vec<ContainerNode> = Vec::new();

    let mut current_inlines: Vec<InlineElement> = Vec::new();
    let mut format_state = FormatState::default();
    let mut current_code_block: Option<(Option<String>, String)> = None;
    let mut link_stack: Vec<(String, Vec<InlineElement>)> = Vec::new();

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
                    current_code_block = Some((lang, String::new()));
                }
                Tag::Link { dest_url, .. } => {
                    link_stack.push((dest_url.to_string(), Vec::new()));
                }
                Tag::Image { dest_url, .. } => {
                    link_stack.push((dest_url.to_string(), Vec::new()));
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
                    if let Some(ContainerNode::ListItem { content, checked }) = node_stack.pop() {
                        let node = AstNode::ListItem { content, checked };
                        push_node(&mut root_nodes, &mut node_stack, node);
                    }
                }
                TagEnd::CodeBlock => {
                    if let Some((language, code)) = current_code_block.take() {
                        let node = AstNode::CodeBlock { language, code };
                        push_node(&mut root_nodes, &mut node_stack, node);
                    }
                }
                TagEnd::Link => {
                    if let Some((url, content)) = link_stack.pop() {
                        let processed_content = process_inlines(content);
                        let ext_link = InlineElement::ExternalLink {
                            url,
                            content: processed_content,
                        };
                        if let Some((_, ref mut parent_content)) = link_stack.last_mut() {
                            parent_content.push(ext_link);
                        } else {
                            current_inlines.push(ext_link);
                        }
                    }
                }
                TagEnd::Image => {
                    if let Some((url, content)) = link_stack.pop() {
                        let alt_text = content
                            .iter()
                            .map(|elem| match elem {
                                InlineElement::Text(tr) => tr.content.as_str(),
                                _ => "",
                            })
                            .collect::<Vec<_>>()
                            .join("");
                        let node = AstNode::Image {
                            alt_text,
                            url_or_path: url,
                        };

                        if matches!(node_stack.last(), Some(ContainerNode::Paragraph))
                            && !current_inlines.is_empty()
                        {
                            let p_content = process_inlines(std::mem::take(&mut current_inlines));
                            let p_node = AstNode::Paragraph { content: p_content };
                            push_node(&mut root_nodes, &mut node_stack, p_node);
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
                if let Some((_, ref mut code)) = current_code_block {
                    code.push_str(&text);
                } else {
                    push_raw_text(&text, &format_state, &mut current_inlines, &mut link_stack);
                }
            }
            Event::Code(text) => {
                let text_run = TextRun {
                    content: text.to_string(),
                    bold: format_state.bold,
                    italic: format_state.italic,
                    strikethrough: format_state.strikethrough,
                    code: true,
                };
                let elem = InlineElement::Text(text_run);
                if let Some((_, ref mut link_content)) = link_stack.last_mut() {
                    link_content.push(elem);
                } else {
                    current_inlines.push(elem);
                }
            }
            Event::Rule => {
                let node = AstNode::ThematicBreak;
                push_node(&mut root_nodes, &mut node_stack, node);
            }
            Event::SoftBreak | Event::HardBreak => {
                let text_run = TextRun {
                    content: "\n".to_string(),
                    bold: format_state.bold,
                    italic: format_state.italic,
                    strikethrough: format_state.strikethrough,
                    code: false,
                };
                let elem = InlineElement::Text(text_run);
                if let Some((_, ref mut link_content)) = link_stack.last_mut() {
                    link_content.push(elem);
                } else {
                    current_inlines.push(elem);
                }
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

fn push_node(root_nodes: &mut Vec<AstNode>, node_stack: &mut [ContainerNode], node: AstNode) {
    if let Some(parent) = node_stack.last_mut() {
        match parent {
            ContainerNode::Blockquote(nodes) => nodes.push(node),
            ContainerNode::List { items, .. } => items.push(node),
            ContainerNode::ListItem { content, .. } => content.push(node),
            _ => root_nodes.push(node),
        }
    } else {
        root_nodes.push(node);
    }
}

fn push_raw_text(
    text: &str,
    format_state: &FormatState,
    current_inlines: &mut Vec<InlineElement>,
    link_stack: &mut [(String, Vec<InlineElement>)],
) {
    let tr = TextRun {
        content: text.to_string(),
        bold: format_state.bold,
        italic: format_state.italic,
        strikethrough: format_state.strikethrough,
        code: false,
    };
    let elem = InlineElement::Text(tr);
    if let Some((_, ref mut link_content)) = link_stack.last_mut() {
        link_content.push(elem);
    } else {
        current_inlines.push(elem);
    }
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
            out.push(InlineElement::Text(TextRun {
                content: before.to_string(),
                bold: tr.bold,
                italic: tr.italic,
                strikethrough: tr.strikethrough,
                code: false,
            }));
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
                content: vec![InlineElement::Text(TextRun {
                    content: display_text.to_string(),
                    bold: tr.bold,
                    italic: tr.italic,
                    strikethrough: tr.strikethrough,
                    code: false,
                })],
            });

            rest = &after_start[end_idx + 2..];
        } else {
            out.push(InlineElement::Text(TextRun {
                content: rest.to_string(),
                bold: tr.bold,
                italic: tr.italic,
                strikethrough: tr.strikethrough,
                code: false,
            }));
            return;
        }
    }

    if !rest.is_empty() {
        out.push(InlineElement::Text(TextRun {
            content: rest.to_string(),
            bold: tr.bold,
            italic: tr.italic,
            strikethrough: tr.strikethrough,
            code: false,
        }));
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
    fn test_nested_list_and_code_block() {
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
