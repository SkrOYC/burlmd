//! The mapping between a bundle-relative path and an OKF concept id, and the
//! reserved-filename rule that constrains it.
//!
//! Per OKF §2, a concept's id is "the path of the concept's file within the
//! bundle, with the `.md` suffix removed" -- `data-models/okf-bundle.md`
//! restates this as the sole definition of `notes.id`. Identity is therefore
//! positional: no UUID is minted, stored, or written to disk.

/// OKF §3.1 reserves `index.md` (directory listing, §8) and `log.md` (update
/// history, §9). burlmd generates neither (ADR-004 decision 6) and reserves
/// both filenames outright: a title deriving to one is rejected with
/// `PathUnavailable` rather than silently disambiguated
/// (`data-models/okf-bundle.md`, "Reserved filenames").
const RESERVED_TITLES: [&str; 2] = ["index", "log"];

/// Converts a bundle-relative path (with the `.md` suffix, and optionally a
/// leading `/`) to its OKF concept id: the same path with any leading `/`
/// and the `.md` suffix removed (OKF §2).
///
/// `notes.id` never carries a leading slash (`data-models/okf-bundle.md`,
/// "Identity": "workspace-relative... no leading slash"), so a caller
/// passing a bundle-**absolute** form -- as a parsed link destination does,
/// per `links::classify` -- gets back the same id a bundle-relative path
/// would. Stripping neither is a no-op, so this stays a total function over
/// any `&str`: callers are expected to pass a Note path, but nothing here
/// panics if one doesn't end in `.md` or start with `/`.
pub fn path_to_concept_id(path: &str) -> String {
    let path = path.strip_prefix('/').unwrap_or(path);
    path.strip_suffix(".md").unwrap_or(path).to_string()
}

/// The inverse of [`path_to_concept_id`]: appends `.md` back onto a concept
/// id to recover its bundle-relative path. Never adds a leading `/` -- the
/// inverse of stripping one, when [`path_to_concept_id`] was given an
/// absolute path, is the caller's to re-add if it needs the absolute form
/// back; a bundle-relative path is what `notes.path` in `schema.sql` stores.
pub fn concept_id_to_path(concept_id: &str) -> String {
    format!("{concept_id}.md")
}

/// True when `title` is a reserved OKF filename stem
/// (`data-models/okf-bundle.md`, "Reserved filenames"), accepting either the
/// bare title (`"index"`) or a filename (`"index.md"`) -- both route through
/// [`path_to_concept_id`] first, so a caller validating a filename rather
/// than the title it was derived from still gets the rejection. Checked
/// against the verbatim stem -- the filename derivation this guards is
/// itself verbatim, plus `.md`, with no case folding, so the reservation is
/// exact-match rather than case-insensitive.
///
/// That `.md`-stripping routing **widens** the rule, and deliberately: a title
/// spelled literally `index.md` is rejected even though
/// [`concept_id_to_path`] would derive it to `index.md.md`, which collides with
/// nothing OKF reserves. The over-strictness is the cheaper mistake in both
/// directions -- a user who wanted a Note called `index.md` loses a spelling
/// they can trivially vary, while accepting it would leave `is_reserved_title`
/// unable to answer for a caller holding a *filename*, which is the form
/// `index::scan` and every path-shaped check work in. One predicate that reads
/// both forms and refuses both beats two that disagree about which one they
/// were given.
pub fn is_reserved_title(title: &str) -> bool {
    RESERVED_TITLES.contains(&path_to_concept_id(title).as_str())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn path_to_concept_id_strips_md_suffix() {
        assert_eq!(path_to_concept_id("projects/burlmd.md"), "projects/burlmd");
    }

    #[test]
    fn path_to_concept_id_handles_root_level_note() {
        assert_eq!(path_to_concept_id("Welcome.md"), "Welcome");
    }

    #[test]
    fn path_to_concept_id_strips_a_leading_slash() {
        // `notes.id` never carries a leading slash (`data-models/okf-bundle.md`,
        // "Identity"), so a bundle-absolute path -- the form a parsed link
        // destination arrives in -- must map to the same id a
        // bundle-relative one does.
        assert_eq!(
            path_to_concept_id("/projects/x.md"),
            path_to_concept_id("projects/x.md")
        );
        assert_eq!(path_to_concept_id("/projects/x.md"), "projects/x");
    }

    #[test]
    fn concept_id_to_path_is_the_inverse() {
        let concept_id = "projects/burlmd";
        let path = concept_id_to_path(concept_id);
        assert_eq!(path, "projects/burlmd.md");
        assert_eq!(path_to_concept_id(&path), concept_id);
    }

    #[test]
    fn round_trip_holds_for_nested_and_root_paths() {
        for concept_id in ["Welcome", "projects/burlmd", "a/b/c/deep"] {
            let path = concept_id_to_path(concept_id);
            assert_eq!(path_to_concept_id(&path), concept_id);
        }
    }

    #[test]
    fn index_and_log_are_reserved() {
        assert!(is_reserved_title("index"));
        assert!(is_reserved_title("log"));
    }

    #[test]
    fn index_and_log_are_reserved_as_filenames_too() {
        // A caller may be validating a filename it already derived (or one
        // read off disk) rather than the bare title, so both forms must be
        // rejected identically.
        assert!(is_reserved_title("index.md"));
        assert!(is_reserved_title("log.md"));
    }

    #[test]
    fn similar_but_distinct_titles_are_not_reserved() {
        assert!(!is_reserved_title("Index"));
        assert!(!is_reserved_title("logs"));
        assert!(!is_reserved_title("indexes"));
        assert!(!is_reserved_title("my log"));
    }

    #[test]
    fn similar_but_distinct_filenames_are_not_reserved() {
        assert!(!is_reserved_title("Index.md"));
        assert!(!is_reserved_title("logs.md"));
        assert!(!is_reserved_title("indexes.md"));
    }
}
