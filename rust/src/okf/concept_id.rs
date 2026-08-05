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

/// Converts a bundle-relative path (with the `.md` suffix) to its OKF
/// concept id: the same path with `.md` removed (OKF §2).
///
/// No-op when `path` does not end in `.md` -- callers are expected to always
/// pass a Note path, and returning the path unchanged rather than panicking
/// keeps this a total function over any `&str`.
pub fn path_to_concept_id(path: &str) -> String {
    path.strip_suffix(".md").unwrap_or(path).to_string()
}

/// The inverse of [`path_to_concept_id`]: appends `.md` back onto a concept
/// id to recover its bundle-relative path.
pub fn concept_id_to_path(concept_id: &str) -> String {
    format!("{concept_id}.md")
}

/// True when `title` is a reserved OKF filename stem (`data-models/okf-bundle.md`,
/// "Reserved filenames"). Checked against the verbatim title -- the filename
/// derivation this guards is itself verbatim, plus `.md`, with no case
/// folding, so the reservation is exact-match rather than case-insensitive.
pub fn is_reserved_title(title: &str) -> bool {
    RESERVED_TITLES.contains(&title)
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
    fn similar_but_distinct_titles_are_not_reserved() {
        assert!(!is_reserved_title("Index"));
        assert!(!is_reserved_title("logs"));
        assert!(!is_reserved_title("indexes"));
        assert!(!is_reserved_title("my log"));
    }
}
