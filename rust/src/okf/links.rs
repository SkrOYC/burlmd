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
//!   or something external. It also takes the containing Note's directory,
//!   because OKF §6.1 permits relative destinations and
//!   `data-models/okf-bundle.md` requires burlmd to resolve them correctly
//!   when reading a foreign bundle, even though it never writes one itself.
//! - [`serialize_link`] takes a concept id and produces the Markdown text
//!   burlmd writes for a link to it, escaping the characters that would
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
/// this string.
///
/// `containing_dir` is the bundle-relative directory of the Note the link
/// was parsed out of (empty string for the bundle root, no leading or
/// trailing `/`) -- e.g. `"projects"` for a link found in
/// `projects/x.md`. It is only consulted when `dest` is relative (no
/// leading `/`); burlmd itself only ever writes the bundle-absolute form,
/// so every call site serializing a burlmd-authored link may pass an empty
/// string, but a foreign bundle read by burlmd may legitimately contain a
/// relative destination and OKF §6.1 requires it to resolve correctly
/// rather than being tolerated as merely "not a link".
///
/// An internal target's concept id is the resolved path with the leading
/// `/` (for an absolute destination) and trailing `.md` removed, and with
/// `.` and `..` segments normalized -- against `containing_dir` for a
/// relative destination, and against the bundle root for an absolute one. A
/// destination that climbs above the bundle root -- more `..` segments than
/// there are components to pop -- classifies as external: `notes.id` is
/// bundle-relative by construction (`data-models/okf-bundle.md`,
/// "Identity"), so there is no concept id to report, and clamping the climb
/// at the root would silently point the link at whatever unrelated Note
/// happens to live there instead of reporting that the destination does not
/// resolve.
///
/// The two spellings of the same destination therefore agree. They did not
/// before: the absolute branch stripped the leading `/` and the `.md` and
/// reported what was left verbatim, so `/a/../b.md` classified as
/// `Internal("a/../b")` -- an id no `notes.id` can ever equal, and so a
/// permanent ghost Link -- while `a/../b.md` read from the bundle root
/// normalized to `Internal("b")` and resolved. Nothing forbids a foreign
/// bundle from writing the absolute form with a `..` in it, and OKF §6.1
/// requires it to resolve.
pub fn classify(dest: &str, containing_dir: &str) -> LinkTarget {
    if has_url_scheme(dest) || !dest.ends_with(".md") {
        return LinkTarget::External(dest.to_string());
    }
    // An absolute destination resolves from the bundle root, which is the
    // same normalization with an empty base rather than a second one.
    let (base, relative) = match dest.strip_prefix('/') {
        Some(absolute) => ("", absolute),
        None => (containing_dir, dest),
    };
    match resolve_relative(base, relative) {
        Some(concept_id) => LinkTarget::Internal(concept_id),
        None => LinkTarget::External(dest.to_string()),
    }
}

/// Resolves a destination (already confirmed to end in `.md`, and with any
/// leading `/` already stripped) against `containing_dir`, normalizing `.`
/// and `..` segments the way a filesystem or URL resolver would. Returns
/// `None` when a `..` has nothing left to pop -- see [`classify`] for why
/// that case is reported as external rather than clamped.
fn resolve_relative(containing_dir: &str, dest: &str) -> Option<String> {
    let dest_without_ext = dest.strip_suffix(".md").unwrap_or(dest);
    let mut stack: Vec<&str> = containing_dir
        .split('/')
        .filter(|segment| !segment.is_empty())
        .collect();
    for segment in dest_without_ext.split('/') {
        match segment {
            "" | "." => {}
            ".." => {
                stack.pop()?;
            }
            other => stack.push(other),
        }
    }
    Some(stack.join("/"))
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
/// in `concept_id` backslash-escaped inside the brackets, and every one of
/// `\`, `[`, `]`, `<`, `>` and `&` in `text` backslash-escaped in the link
/// text position.
///
/// The text-position escapes matter because `text` is a Note title, not a
/// fixed label: CAP-GRAPH-02's completion inserts the target's own title
/// there, and a title is free-form user text under
/// `data-models/okf-bundle.md`'s verbatim derivation.
///
/// `[`/`]` are structural: an unescaped `]` in `text` closes the link's text
/// span early, and an unescaped `[` opens a second one -- either way
/// CommonMark stops parsing a link at all and emits plain text instead.
/// Verified against `pulldown-cmark` 0.12.2: `[a]b](</a]b.md>)` produces no
/// `Link` event.
///
/// `\` is structural for a different reason: CommonMark's own backslash
/// escape applies inside link text exactly as everywhere else, so a title
/// ending in an unescaped `\` consumes the link's closing `]` as `\]` --
/// an escaped literal bracket, not the delimiter -- and again produces no
/// `Link` event. A lone trailing `\` in a title is what surfaced this
/// (`[\](</\\.md>)` fails to parse), but any `\` immediately before `[` or
/// `]` has the same effect, so it is escaped unconditionally rather than
/// only at the end.
///
/// `<`/`>` are structural too, in a way the destination's own escaping of
/// them does not cover: a substring that looks like an HTML tag -- e.g. a
/// title of `<Meeting>` -- parses as inline HTML (`Event::InlineHtml`), not
/// as text, silently swallowing that whole span from the rendered label. A
/// lone `<` with no matching close is unaffected (CommonMark only recognizes
/// a complete tag shape), but determining exactly which spans are
/// "tag-shaped enough" to trigger this would mean reimplementing
/// CommonMark's own HTML-tag grammar; escaping both characters
/// unconditionally avoids needing to.
///
/// `&` is not structural -- it never breaks the parse -- but link text is
/// ordinary inline content, and CommonMark decodes HTML entity references
/// there exactly as it does everywhere else: a title containing the literal
/// substring `&eacute;` renders as `é`, and one containing `&amp;` renders
/// as `&`, silently changing what the reader sees from what the title
/// actually is. This is the text-position twin of the destination's `&`
/// rule below, for the identical reason.
///
/// All six are escaped unconditionally, matching the reasoning the
/// destination wrap uses: one rule with no predicate to get wrong, rather
/// than only escaping when a title happens to need it.
pub fn serialize_link(text: &str, concept_id: &str) -> String {
    format!(
        "[{}](</{}.md>)",
        escape_link_text(text),
        escape_destination(concept_id)
    )
}

/// Backslash-escapes every literal `\`, `[`, `]`, `<`, `>` and `&` in
/// `text`. `\`, `[` and `]` guard against prematurely closing or reopening
/// the link's text span (or escaping away the delimiter that does); `<` and
/// `>` guard against a tag-shaped substring being swallowed as inline HTML;
/// `&` guards against CommonMark decoding an entity-shaped substring of the
/// title into a different character. See [`serialize_link`].
fn escape_link_text(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        if matches!(c, '\\' | '[' | ']' | '<' | '>' | '&') {
            out.push('\\');
        }
        out.push(c);
    }
    out
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
        parsed_link(markdown).map(|(_text, dest)| dest)
    }

    /// Parses a single Markdown link's visible text and destination out of
    /// `markdown`. `None` when `markdown` does not parse as a link at all --
    /// which is exactly what an unescaped `[`/`]` in the text position, or
    /// an unwrapped destination containing a space, produces: CommonMark
    /// falls back to plain text with no `Link` event whatsoever.
    fn parsed_link(markdown: &str) -> Option<(String, String)> {
        let parser = Parser::new_ext(markdown, Options::empty());
        let mut dest = None;
        let mut text = String::new();
        let mut in_link = false;
        for event in parser {
            match event {
                Event::Start(Tag::Link { dest_url, .. }) => {
                    in_link = true;
                    dest = Some(dest_url.to_string());
                }
                Event::Text(t) if in_link => text.push_str(&t),
                Event::End(pulldown_cmark::TagEnd::Link) => in_link = false,
                _ => {}
            }
        }
        dest.map(|d| (text, d))
    }

    #[test]
    fn absolute_internal_target_classifies_with_stripped_concept_id() {
        let target = classify("/projects/architecture.md", "");
        assert_eq!(
            target,
            LinkTarget::Internal("projects/architecture".to_string())
        );
    }

    #[test]
    fn absolute_target_ignores_containing_dir() {
        // The bundle-absolute form is resolved from the bundle root
        // regardless of where the link was found.
        let target = classify("/projects/architecture.md", "unrelated/deep");
        assert_eq!(
            target,
            LinkTarget::Internal("projects/architecture".to_string())
        );
    }

    #[test]
    fn external_url_classifies_as_external() {
        let target = classify("https://example.com/page", "");
        assert_eq!(
            target,
            LinkTarget::External("https://example.com/page".to_string())
        );
    }

    #[test]
    fn non_md_target_classifies_as_external() {
        let target = classify("/attachments/diagram.png", "");
        assert_eq!(
            target,
            LinkTarget::External("/attachments/diagram.png".to_string())
        );
    }

    #[test]
    fn sibling_relative_target_resolves_against_containing_dir() {
        // A link found in `projects/x.md` pointing at `sibling.md` names
        // `projects/sibling`, not `sibling` -- OKF §6.1 permits this form in
        // a foreign bundle and `data-models/okf-bundle.md` requires burlmd
        // to resolve it correctly rather than merely tolerate it as broken.
        let target = classify("sibling.md", "projects");
        assert_eq!(target, LinkTarget::Internal("projects/sibling".to_string()));
    }

    #[test]
    fn dot_slash_relative_target_resolves_against_containing_dir() {
        let target = classify("./sibling.md", "projects");
        assert_eq!(target, LinkTarget::Internal("projects/sibling".to_string()));
    }

    #[test]
    fn dot_dot_relative_target_climbs_one_directory() {
        // A link in `projects/sub/x.md` pointing at `../sibling.md` names
        // `projects/sibling`: one `..` cancels one path component of the
        // containing directory.
        let target = classify("../sibling.md", "projects/sub");
        assert_eq!(target, LinkTarget::Internal("projects/sibling".to_string()));
    }

    #[test]
    fn dot_dot_relative_target_can_reach_the_bundle_root() {
        let target = classify("../root.md", "projects");
        assert_eq!(target, LinkTarget::Internal("root".to_string()));
    }

    #[test]
    fn dot_dot_relative_target_escaping_the_bundle_root_is_external() {
        // Decision: a relative destination with more `..` segments than the
        // containing directory has components is classified as external
        // rather than clamped to the bundle root. `notes.id` is
        // bundle-relative by construction, so there is no concept id this
        // could name -- and clamping would silently resolve the link to
        // whatever unrelated Note happens to live at the root instead of
        // reporting that the destination does not resolve within this
        // bundle.
        let target = classify("../escaped.md", "");
        assert_eq!(target, LinkTarget::External("../escaped.md".to_string()));

        let target = classify("../../too_far.md", "projects");
        assert_eq!(target, LinkTarget::External("../../too_far.md".to_string()));
    }

    /// The absolute and relative spellings of one destination must classify
    /// the same way, since they name the same file.
    ///
    /// The regression this pins: the absolute branch stripped the leading
    /// `/` and the `.md` and reported the rest verbatim, so `/a/../b.md`
    /// became `Internal("a/../b")` — an id no `notes.id` can ever equal, and
    /// therefore a Link that is permanently a ghost — while the identical
    /// `a/../b.md` read from the bundle root normalized to `Internal("b")`
    /// and resolved.
    #[test]
    fn an_absolute_destination_normalizes_exactly_as_the_relative_spelling_does() {
        for (absolute, relative) in [
            ("/a/../b.md", "a/../b.md"),
            ("/./b.md", "./b.md"),
            (
                "/projects/sub/../architecture.md",
                "projects/sub/../architecture.md",
            ),
            ("/a//b.md", "a//b.md"),
        ] {
            assert_eq!(
                classify(absolute, "unrelated/deep"),
                classify(relative, ""),
                "{absolute} and {relative} name the same file"
            );
        }
        assert_eq!(
            classify("/a/../b.md", ""),
            LinkTarget::Internal("b".to_string())
        );
    }

    /// The climbs-above-root rule applies to the absolute spelling too: there
    /// is nothing above the bundle root to pop, so the destination names no
    /// concept in this bundle and is reported as external rather than clamped.
    #[test]
    fn an_absolute_destination_climbing_above_the_bundle_root_is_external() {
        assert_eq!(
            classify("/../escaped.md", ""),
            LinkTarget::External("/../escaped.md".to_string())
        );
        assert_eq!(
            classify("/a/../../too_far.md", "projects"),
            LinkTarget::External("/a/../../too_far.md".to_string())
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
            let target = classify(&dest, "");
            assert_eq!(target, LinkTarget::Internal(concept_id.to_string()));
        }
    }

    #[test]
    fn unescaped_brackets_in_text_break_the_link_entirely() {
        // Demonstrates the defect a naive `serialize_link` produces: an
        // unescaped `]` in the text position closes the link's text span
        // early, and CommonMark falls back to plain text with no `Link`
        // event at all. Verified directly against pulldown-cmark 0.12.2
        // rather than assumed.
        assert_eq!(parsed_link("[a]b](</a]b.md>)"), None);
    }

    #[test]
    fn brackets_in_link_text_are_escaped_so_the_link_still_parses() {
        // A title containing `]` or `[` reaches the text position via
        // CAP-GRAPH-02's completion, which inserts the target Note's own
        // title. `serialize_link` must escape both there, not only in the
        // destination.
        for title in ["a]b", "a[b", "[a][b]", "]["] {
            let markdown = serialize_link(title, "target");
            let (text, dest) = parsed_link(&markdown)
                .unwrap_or_else(|| panic!("serialized link failed to parse: {markdown:?}"));
            assert_eq!(text, title);
            assert_eq!(
                classify(&dest, ""),
                LinkTarget::Internal("target".to_string())
            );
        }
    }

    #[test]
    fn trailing_backslash_in_text_breaks_the_link_entirely() {
        // A second structural defect the property test's `text = title`
        // change surfaced: a bare backslash immediately before the link's
        // closing `]` escapes that bracket instead of closing the link, so
        // CommonMark again falls back to plain text.
        assert_eq!(parsed_link("[\\](</a.md>)"), None);
    }

    #[test]
    fn backslash_and_ampersand_in_link_text_are_escaped_so_the_link_still_parses() {
        for title in [
            "\\",
            "a\\b",
            "&",
            "&amp;",
            "&eacute;",
            "&#65;",
            "Tom &amp; Jerry",
        ] {
            let markdown = serialize_link(title, "target");
            let (text, dest) = parsed_link(&markdown)
                .unwrap_or_else(|| panic!("serialized link failed to parse: {markdown:?}"));
            assert_eq!(text, title);
            assert_eq!(
                classify(&dest, ""),
                LinkTarget::Internal("target".to_string())
            );
        }
    }

    #[test]
    fn tag_shaped_text_is_swallowed_as_inline_html_when_unescaped() {
        // A further defect the property test's `text = title` change
        // surfaced: a title that happens to look like a complete HTML tag
        // parses as `Event::InlineHtml`, not `Event::Text`, so it vanishes
        // from the recovered label entirely rather than merely breaking the
        // link.
        assert_eq!(
            parsed_link("[<Meeting>](</a.md>)"),
            Some((String::new(), "/a.md".to_string()))
        );
    }

    #[test]
    fn angle_brackets_in_link_text_are_escaped_so_the_link_still_parses() {
        for title in ["<Meeting>", "a<b", "a>b", "<>"] {
            let markdown = serialize_link(title, "target");
            let (text, dest) = parsed_link(&markdown)
                .unwrap_or_else(|| panic!("serialized link failed to parse: {markdown:?}"));
            assert_eq!(text, title);
            assert_eq!(
                classify(&dest, ""),
                LinkTarget::Internal("target".to_string())
            );
        }
    }

    /// A generator of "risky" title substrings: whitespace, parentheses, a
    /// bare `#` and `%`, a bare `&`, a named HTML entity, a numeric HTML
    /// entity, each character `serialize_link` must escape in the
    /// destination (`\`, `<`, `>`, `&`), and each it must escape in the text
    /// (`[`, `]`). Titles are built by concatenating a short random sequence
    /// of these tokens, which is what makes this a property test over a
    /// generator rather than a fixture of single-word names.
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
            Just("[".to_string()),
            Just("]".to_string()),
        ]
    }

    proptest! {
        /// Round-trip property required by this ticket's Gherkin: for any
        /// title the derivation accepts, serializing a link to it -- using
        /// that same generated title as *both* the link text and the
        /// concept id, since CAP-GRAPH-02's completion does exactly that --
        /// and parsing the result back through `pulldown-cmark` recovers
        /// the original title in both positions.
        #[test]
        fn link_round_trips_through_serialize_and_a_real_parse(
            tokens in proptest::collection::vec(title_token(), 1..6)
        ) {
            let title = tokens.concat();
            prop_assume!(!title.is_empty());

            let markdown = serialize_link(&title, &title);
            let parsed = parsed_link(&markdown);
            prop_assert!(parsed.is_some(), "serialized link failed to parse: {markdown:?}");

            let (text, dest) = parsed.unwrap();
            prop_assert_eq!(&text, &title);
            prop_assert_eq!(classify(&dest, ""), LinkTarget::Internal(title));
        }
    }
}
