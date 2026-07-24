# ADR-007: Span-Preserving Source Splicing Instead of AST Serialization

**Status:** Accepted

## Context
`architecture/flows/flow-edit-note.md` specifies a save phase that serializes the final AST back to Markdown and commits it. That phase has never been implemented: no serializer exists anywhere in `rust/src/`, and `save_note` performs only an Optimistic Concurrency Control check against `notes.last_modified`.

The absent piece was never only code. Nothing specified *what Markdown* an AST should serialize to — bullet character, emphasis delimiter, ATX versus setext headings, fence style, hard-wrap policy. Without a canonical form, an AST-to-Markdown serializer must invent one, and every save then rewrites the entire file into it.

PRD v1.1.0 made that unacceptable by adding the **Edit Fidelity** constraint: writing a Note "must not alter any region of that Note the user did not edit... leaving all other bytes — including whitespace, delimiter style, and any metadata keys the application does not itself manage — byte-identical." The primary actor writes Markdown in other tools too, and a Workspace whose every save produces a whole-file diff makes version history useless and merges gratuitously conflict-prone.

Two facts make a stronger guarantee cheap rather than expensive:

1. `pulldown-cmark` 0.12.2 provides `Parser::into_offset_iter()` (verified in the vendored source at `src/parse.rs:1310`), which yields a byte range for every event. Source spans are available without modifying or replacing the parser.
2. ADR-006 made editing *raw*. The user edits the source text of a Block directly, so the editor already possesses exactly the bytes that belong in that Block's span. Nothing needs to be reconstructed from an AST.

Together these convert serialization from a generation problem into a splice problem.

## Decision
1. **The file is the source of truth; edits are textual splices.** Parsing produces an AST *and* a span map. Committing an edit to Block *N* replaces the bytes in that Block's span with the user's edited text and reparses. Bytes outside the replaced span are never rewritten.
2. **No AST-to-Markdown serializer exists for the save path.** There is consequently no canonical form to specify, and no normalization behavior to document, because normalization never occurs.
3. **Spans live Core-side, keyed by `block_path`.** They are not fields on `AstNode` and never cross the FFI boundary. Putting byte ranges on every node would inflate every `update_block` payload, directly aggravating `architecture/risks.md` risk 1 (FFI serialization overhead against the 16ms budget), for data the UI cannot use.
4. **`update_block` becomes source-text-based.** Its signature changes from accepting an `AstNode` to accepting the Block's raw source `String`. A companion `get_block_source` returns the current raw text for a `block_path` so the UI can populate the editable field on focus.
5. **Frontmatter preservation is a special case of the same rule.** The metadata block is a span like any other, located via `Options::ENABLE_YAML_STYLE_METADATA_BLOCKS` (verified present at `src/lib.rs:559`) and `Tag::MetadataBlock`. It is parsed read-only to extract `type` and `title`, and its bytes are rewritten only when `title` actually changes. ADR-004's "preserve unknown keys verbatim" obligation therefore requires no work at all — unknown keys are preserved because the block is never re-serialized.
6. **A YAML writer is not required.** Only a reader, for validating parseability (OKF §11.1) and extracting two scalars.
7. **`base_revision` is a content hash of the on-disk file.** This replaces the `notes.last_modified` timestamp the current `save_note` compares. It reconciles the open-to-save path, which is presently broken by construction: `open_note` returns the literal placeholder `"head"` while `save_note` expects a stringified `last_modified`, so any real save returns `GitConflict`. A content hash is well-defined at both ends, immune to timestamp granularity and clock skew, and is exactly the token OCC needs. `sha2` is already a direct dependency.
8. **Writes are atomic.** A Note is written to a temporary file in the same directory and renamed over the target, satisfying `architecture/resilience.md`'s Atomic Commits guarantee.

## Consequences
- **Positive:** Edit Fidelity is guaranteed by construction rather than engineered and tested for. The class of "the app reformatted my file" defect cannot occur, because no code path is capable of rewriting an unedited region.
- **Positive:** Git diffs correspond to what the user actually changed, which makes local version history (CAP-WS-02) readable and keeps merge conflicts confined to genuinely concurrent edits.
- **Positive:** ADR-004's frontmatter-preservation obligation and CAP-PORT-03's tolerance of externally-authored files both fall out of this decision at no additional cost.
- **Positive:** The open-to-save path becomes coherent for the first time.
- **Negative:** Span invalidation is the hard part and the likely home of defects. Splicing Block *N* shifts every subsequent byte offset, so the span map must be rebuilt or adjusted on every commit. Reparsing the whole file after each splice is the simple correct answer and is the specified behavior; it is O(file) per committed edit rather than per keystroke, which the tiering in ADR-008 keeps off the typing path.
- **Negative:** Block-level granularity means an edit that changes a Block's *structure* (a paragraph becoming a list) reparses into a different node shape, so `block_path` stability across a commit cannot be assumed by the caller. The UI must re-derive focus from the returned state rather than retain a path across a commit.
- **Negative:** The AST becomes a read/render projection rather than the editable representation. Any future feature wanting to mutate structure programmatically (a formatting command, an automated refactor) must express itself as a source edit. Acceptable, and arguably more honest for a Markdown-native product.
- **Neutral:** An AST-to-Markdown serializer may still be needed for *generation* — creating a new Note from a template, or materializing a resolved `Suggestion`. Those produce new text rather than rewriting existing text, so they do not reintroduce the canonical-form problem for existing files.
