//! Classifying and serializing OKF links (`data-models/okf-bundle.md`,
//! "Links"; OKF §6.1).
//!
//! A link is a standard Markdown link. The **bundle-absolute** form --
//! leading `/`, resolved from the bundle root -- is the one burlmd writes,
//! and its destination is always angle-bracket wrapped:
//!
//! ```markdown
//! See [Architecture](</projects/architecture.md>) for the container split.
//! ```
//!
//! Two functions, and they are not inverses of the same operation on the
//! same representation:
//!
//! - [`classify`] takes a **parsed** link destination -- what `pulldown-cmark`
//!   hands back as `dest_url` once it has already stripped the angle
//!   brackets and resolved CommonMark's own backslash-escapes and HTML
//!   entity references -- and decides whether it names a Note in this bundle
//!   or something external.
//! - [`serialize_link`] takes a concept id and produces the Markdown text
//!   burlmd writes for a link to it, escaping the four characters that would
//!   otherwise corrupt a round trip through that same parser.
//!
//! The destination is wrapped **unconditionally**, not only when the path
//! would otherwise be invalid as a bare destination. Titles are derived into
//! filenames verbatim (`data-models/okf-bundle.md`, "Deriving a filename
//! from a title"), so an ordinary multi-word title produces a path
//! containing a space -- and CommonMark forbids a *bare* link destination
//! from containing one. `[a](/Meeting Notes.md)` therefore parses as
//! paragraph text, not as a link, so a conditional wrap would need a
//! predicate that exactly matches CommonMark's rule for what a bare
//! destination may contain; getting that predicate wrong reproduces the
//! defect for whichever character it missed. Wrapping always is one rule
//! with no branch.

/// The classification of a parsed link destination.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LinkTarget {
    /// A link to another Note in the bundle, carrying its OKF concept id.
    Internal(String),
    /// Any link that is not an internal Note reference: it has a URL scheme,
    /// or does not end in `.md`.
    External(String),
}

/// Classifies a parsed link destination as internal or external
/// (`data-models/okf-bundle.md`, "Links").
///
/// `dest` is the destination as a Markdown parser already resolved it --
/// angle brackets stripped, CommonMark backslash-escapes and HTML entity
/// references already applied. This function performs no unescaping of its
/// own; there is none left to do once a real CommonMark parser has produced
/// this string. An internal target's concept id is `dest` with the leading
/// `/` and trailing `.md` removed.
pub fn classify(dest: &str) -> LinkTarget {
    if has_url_scheme(dest) || !dest.ends_with(".md") {
        return LinkTarget::External(dest.to_string());
    }
    let concept_id = dest.strip_prefix('/').unwrap_or(dest);
    let concept_id = concept_id.strip_suffix(".md").unwrap_or(concept_id);
    LinkTarget::Internal(concept_id.to_string())
}

/// True when `dest` opens with a URI scheme (RFC 3986 §3.1: a letter,
/// followed by letters, digits, `+`, `-` or `.`, followed by `:`) -- e.g.
/// `https:`, `mailto:`. A bundle-relative path never matches this, since it
/// either has no `:` at all or, on Windows-style input this project does not
/// produce, would need a single-letter scheme that RFC 3986 still requires
/// to start with a letter.
fn has_url_scheme(dest: &str) -> bool {
    match dest.find(':') {
        Some(colon_idx) if colon_idx > 0 => {
            let scheme = &dest[..colon_idx];
            let mut chars = scheme.chars();
            chars.next().is_some_and(|c| c.is_ascii_alphabetic())
                && chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '-' | '.'))
        }
        _ => false,
    }
}

/// Serializes a Markdown link with visible text `text` pointing at
/// `concept_id`, in the bundle-absolute, angle-bracket-wrapped form burlmd
/// writes: `[text](</concept_id.md>)`, with any literal `\`, `<`, `>` or `&`
/// in `concept_id` backslash-escaped inside the brackets.
pub fn serialize_link(text: &str, concept_id: &str) -> String {
    format!("[{text}](</{}.md>)", escape_destination(concept_id))
}

/// Backslash-escapes every literal `\`, `<`, `>` and `&` in `concept_id`.
/// Unconditional, not merely sufficient: a `&` that begins no valid HTML
/// entity already round-trips through a CommonMark parser unescaped, and
/// escaping it round-trips to the same string, so there is no case where
/// applying the escape is wrong -- see the escaping table in
/// `data-models/okf-bundle.md`.
fn escape_destination(concept_id: &str) -> String {
    let mut out = String::with_capacity(concept_id.len());
    for c in concept_id.chars() {
        if matches!(c, '\\' | '<' | '>' | '&') {
            out.push('\\');
        }
        out.push(c);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use pulldown_cmark::{Event, Options, Parser, Tag};

    /// Parses a single Markdown link's destination out of `markdown`, the
    /// way a real caller downstream of `pulldown-cmark` would see it: angle
    /// brackets stripped, backslash-escapes and unescaped HTML entities
    /// already resolved. Used only to prove serialization round-trips
    /// through an actual parser rather than through our own inverse of the
    /// escaping rule.
    fn parsed_dest(markdown: &str) -> Option<String> {
        let parser = Parser::new_ext(markdown, Options::empty());
        for event in parser {
            if let Event::Start(Tag::Link { dest_url, .. }) = event {
                return Some(dest_url.to_string());
            }
        }
        None
    }

    #[test]
    fn absolute_internal_target_classifies_with_stripped_concept_id() {
        let target = classify("/projects/architecture.md");
        assert_eq!(
            target,
            LinkTarget::Internal("projects/architecture".to_string())
        );
    }

    #[test]
    fn external_url_classifies_as_external() {
        let target = classify("https://example.com/page");
        assert_eq!(
            target,
            LinkTarget::External("https://example.com/page".to_string())
        );
    }

    #[test]
    fn non_md_target_classifies_as_external() {
        let target = classify("/attachments/diagram.png");
        assert_eq!(
            target,
            LinkTarget::External("/attachments/diagram.png".to_string())
        );
    }

    #[test]
    fn destination_with_a_space_is_angle_bracket_wrapped() {
        let markdown = serialize_link("text", "projects/Meeting Notes");
        assert_eq!(markdown, "[text](</projects/Meeting Notes.md>)");
    }

    #[test]
    fn destination_is_wrapped_even_with_no_space() {
        // Unconditional wrapping: a single-word concept id still gets the
        // brackets, because the rule has no branch.
        let markdown = serialize_link("text", "Welcome");
        assert_eq!(markdown, "[text](</Welcome.md>)");
    }

    #[test]
    fn backslash_less_than_greater_than_and_ampersand_are_each_escaped() {
        let cases: &[(&str, &str)] = &[
            ("A<B", "[t](</A\\<B.md>)"),
            ("A>B", "[t](</A\\>B.md>)"),
            ("A&B", "[t](</A\\&B.md>)"),
            ("A\\B", "[t](</A\\\\B.md>)"),
        ];
        for (concept_id, expected) in cases {
            assert_eq!(serialize_link("t", concept_id), *expected);
        }
    }

    #[test]
    fn escaped_special_characters_parse_back_to_the_original_concept_id() {
        for concept_id in ["A<B", "A>B", "A&B", "A\\B", "<>&\\", "Tom &amp; Jerry"] {
            let markdown = serialize_link("t", concept_id);
            let dest = parsed_dest(&markdown).expect("serialized link should parse");
            let target = classify(&dest);
            assert_eq!(target, LinkTarget::Internal(concept_id.to_string()));
        }
    }

    /// A generator of "risky" title substrings: whitespace, parentheses, a
    /// bare `#` and `%`, a bare `&`, a named HTML entity, a numeric HTML
    /// entity, and each character `serialize_link` must escape. Titles are
    /// built by concatenating a short random sequence of these tokens, which
    /// is what makes this a property test over a generator rather than a
    /// fixture of single-word names.
    fn title_token() -> impl Strategy<Value = String> {
        prop_oneof![
            Just("Meeting".to_string()),
            Just("Notes".to_string()),
            Just(" ".to_string()),
            Just("(draft)".to_string()),
            Just("#tag".to_string()),
            Just("100%".to_string()),
            Just("&".to_string()),
            Just("&amp;".to_string()),
            Just("&eacute;".to_string()),
            Just("&#65;".to_string()),
            Just("<".to_string()),
            Just(">".to_string()),
            Just("\\".to_string()),
        ]
    }

    proptest! {
        /// Round-trip property required by this ticket's Gherkin: for any
        /// title the derivation accepts, serializing a link to it and
        /// parsing the result back through `pulldown-cmark` recovers the
        /// original concept id.
        #[test]
        fn link_round_trips_through_serialize_and_a_real_parse(
            tokens in proptest::collection::vec(title_token(), 1..6)
        ) {
            let title = tokens.concat();
            prop_assume!(!title.is_empty());

            let markdown = serialize_link("text", &title);
            let dest = parsed_dest(&markdown);
            prop_assert!(dest.is_some(), "serialized link failed to parse: {markdown:?}");

            let target = classify(&dest.unwrap());
            prop_assert_eq!(target, LinkTarget::Internal(title));
        }
    }
}
