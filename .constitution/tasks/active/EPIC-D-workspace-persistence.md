# Epic D: Workspace & Persistence

Makes Notes real. Today no production code path writes a single row to the index or a single byte to a Note — every `INSERT` in the repository lives inside `#[cfg(test)]`. This epic closes that: a bundle on disk, an index derived from it, and the four persistence tiers that keep the two in step.

Entirely Core-side. No ticket here touches Dart, and nothing in this epic is visible in the running application — Epic E is what mounts it.

#### WSPC-D001 Spike: Span Invalidation Under Source Splicing
- **Type:** Spike
- **Effort:** 3
- **Dependencies:** None
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `.constitution/spikes/SPK-WSPC-D001.md`
- **Scope (Out-of-Scope Files):**
  - `rust/src/**` (no production code in a Spike)
- **Verification Command:** `! grep -q 'Status: placeholder' .constitution/spikes/SPK-WSPC-D001.md && ! grep -q 'To be filled' .constitution/spikes/SPK-WSPC-D001.md && git diff --quiet $(git merge-base HEAD master) HEAD -- rust/src`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if the investigation concludes that whole-file reparse cannot meet the 16ms budget in `prd/constraints.md` at realistic Note sizes; that invalidates ADR-007's mitigation and requires a Stage 3 pass, not an improvised offset-arithmetic implementation."
  - "STOP if no production code change is required by the findings; a Spike that recommends implementation changes must name the ticket, not perform them."
- **Description:** Establish empirically how the Core Engine should maintain source spans across a splice, and at what Note size the chosen approach stops being viable. `architecture/risks.md` risk 7 names whole-file reparse as the mitigation because it makes an incorrect span map unrepresentable, but the cost has never been measured. Determine the reparse cost curve against Note size using the pinned parser, identify the size at which it approaches the frame budget, and confirm whether reparse-after-commit keeps that cost off the per-keystroke path given the tiering in ADR-008. Record whether offset arithmetic is ever warranted, and if so under exactly what conditions.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given the spike report at .constitution/spikes/SPK-WSPC-D001.md
When it is reviewed
Then it records measured reparse timings across at least three Note sizes spanning small, typical and pathological
And it states the Note size at which reparse approaches the 16ms frame budget
And it names the chosen span-maintenance strategy and the tickets it unlocks
And no file under rust/src has been modified
```

#### WSPC-D002 OKF Bundle Domain Module
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** None
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/okf/mod.rs`
  - `rust/src/okf/frontmatter.rs`
  - `rust/src/okf/concept_id.rs`
  - `rust/src/okf/links.rs`
  - `rust/src/frb_generated.rs`, `lib/src/rust/**` (regenerated bindings only. Required even though this ticket adds no `#[frb]` *function*: `AppError` is an `#[frb]` type mirrored into `lib/src/rust/error.dart`, and the generated codecs fall through to `unimplemented!()` on an unknown discriminant — so a Rust-only variant addition compiles, passes this gate, and panics the first time the new variant crosses the boundary.)
  - `rust/src/error.rs` (adds **every** variant the contract introduces — `PathUnavailable`, `NotFound`, `RevisionMismatch` and `OAuthStateMismatch` — not only the two this module itself reports. `AppError` lives here, not in `api`, and the later tickets that raise the other two do not scope this file. Adding all four at once costs nothing and is what keeps `WSPC-D007` able to pass its own revision-mismatch criterion.)
  - `rust/Cargo.toml`
  - `rust/src/lib.rs`
- **Scope (Out-of-Scope Files):**
  - `rust/src/api/**` (no FFI surface in this ticket)
  - `rust/src/db/**`
- **Verification Command:** `cd rust && cargo test okf:: -- --list | grep -q ': test' && cargo test okf:: && cargo test && cargo clippy --all-targets -- -D warnings`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if the YAML reader dependency named in `tech-spec/stack.md` cannot parse a fixture block; do not hand-roll a YAML parser, and do not substitute a different crate without a Stage 3 pass."
  - "STOP if any code path in this module writes or re-serializes a frontmatter block; ADR-007 makes the block a read-only span."
- **Description:** Implement the on-disk format domain specified in `tech-spec/data-models/okf-bundle.md`. Covers reading and validating a frontmatter block against `okf-frontmatter.schema.json`'s required/recommended split, converting between a bundle-relative path and an OKF concept id in both directions, classifying a Markdown link target as an internal Link or an external link, deriving a Link's target concept id, and enforcing the reserved-filename rule. A file must be reported as non-conformant — rather than rejected — when its frontmatter is absent, unparseable, **or parses without a non-empty `type`**. All three, because OKF section 11 states exactly two conformance conditions and the second is the `type` field; `okf-frontmatter.schema.json` already treats it as the sole conformance-bearing property.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given a Note file containing a frontmatter block with type and title
When the frontmatter is read
Then type and title are returned and the file is reported conformant

Given a Note file whose frontmatter contains keys the application does not manage
When the frontmatter is read
Then those keys are reported present and their original bytes are left untouched

Given a Note file with no frontmatter block at all
When the frontmatter is read
Then the file is reported non-conformant and is not rejected

Given a Note file whose frontmatter block parses cleanly but carries no `type`
When the frontmatter is read
Then the file is reported non-conformant and is not rejected — OKF section 11's second condition is a non-empty `type`, so this is the only case where the check is more than a parse attempt, and it is the case a naive implementation gets wrong

Given the bundle-relative path "projects/burlmd.md"
When the concept id is derived
Then it equals "projects/burlmd"

Given a link target "/projects/architecture.md"
When the link is classified
Then it is an internal Link with target concept id "projects/architecture"

Given a link target "https://example.com/page"
When the link is classified
Then it is an external link

Given a proposed Note filename of "index" or "log"
When the name is validated
Then it is rejected as reserved
```

#### WSPC-D003 Span-Preserving Parse and Splice Engine
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** WSPC-D001, WSPC-D002
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/markdown/parser.rs`
  - `rust/src/markdown/spans.rs`
  - `rust/src/markdown/splice.rs`
  - `rust/src/markdown/ast.rs` (reshapes `InlineElement::Link` from `{target_title, resolved_note_id}` to `{target_id, exists}` per the contract; the enum lives here)
  - `rust/src/markdown/mod.rs`
- **Scope (Out-of-Scope Files):**
  - `rust/src/api/**`
  - `rust/src/workspace/**`
- **Verification Command:** `cd rust && cargo test markdown:: -- --list | grep -q ': test' && cargo test markdown:: && cargo clippy --all-targets -- -D warnings`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if satisfying Edit Fidelity appears to require adding a byte range to any `AstNode` variant; `tech-spec/guidelines.md` forbids spans crossing the FFI boundary and ADR-007 decision 3 states why."
  - "STOP if any splice path needs to reconstruct Markdown from an AST; no serializer exists on the save path by design."
- **Description:** The heart of ADR-007. Parse a Note into an AST while building a Core-side span map keyed by `block_path` **and, within each Block, by inline run** (ADR-007 decision 8), then replace the bytes of one Block's span with new source text and reparse. The inline granularity is what lets a `BlockRange` — whose offsets are into *rendered* text, because it spans unfocused Blocks — resolve to the source offsets a splice needs. It costs no extra pass: `Parser::into_offset_iter()` already yields a range for every event, inline included. Frontmatter is located as a span like any other Block and is never re-serialized. Adopt the span-maintenance strategy chosen by WSPC-D001. The round-trip property required by `tech-spec/guidelines.md` is the primary gate: splicing a Block's own unmodified source back over its span must reproduce the file byte-for-byte, including whitespace, delimiter style, and unmanaged frontmatter keys.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given any Note in the fixture corpus and any Block within it
When that Block's own unmodified source is spliced back over its span
Then the resulting file is byte-identical to the original

Given a Note whose paragraphs use underscore emphasis and asterisk bullets
When a different Block is edited and the Note is written
Then the untouched paragraphs retain underscore emphasis and asterisk bullets exactly

Given a Note with frontmatter keys the application does not manage
When any Block is edited and the Note is written
Then the frontmatter block is byte-identical to the original

Given a paragraph Block whose new source begins with a list marker
When the splice is committed and the file reparsed
Then the resulting node at that position is a list rather than a paragraph

Given a paragraph whose source is `hello **bold** world`
When rendered offset 6 is resolved against the span map
Then it yields source offset 8, which is where `bold` begins

Given a selection expressed as rendered offsets across two Blocks
When it is resolved and the selected source extracted
Then the extracted text is exactly the source spanned by the selection, delimiters included
```

#### WSPC-D004 Local Workspace Bootstrap
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** WSPC-D002
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/workspace/mod.rs`
  - `rust/src/workspace/bootstrap.rs`
  - `rust/src/api/ffi_api.rs`
  - `rust/src/db/connection.rs`
  - `rust/src/db/schema.sql` (**the DDL the application actually executes**, via `include_str!` in `connection.rs`. It is currently byte-identical to the pre-v1.1.0 constitution schema and must be brought in line with `tech-spec/data-models/schema.sql` — composite `(workspace_id, id)` keys, `ON UPDATE CASCADE`, `content_hash`, `okf_conformant`, `links.target_id`, `idx_links_target`. Without this, every later ticket writes columns that do not exist.

    Two things it must **not** copy verbatim. `PRAGMA user_version = 1` does not belong in this file at all: `init_schema` replays the batch on every open, so a literal assignment resets a migrated database to the baseline. The Core reads the pragma and writes it only when it reads 0. And bringing the DDL in line breaks the existing tests in `rust/src/api/ffi_api.rs`, which insert into `notes` without `content_hash` and into `fts_mapping` without `workspace_id`, both now `NOT NULL` — which is why this ticket's gate runs an unfiltered `cargo test`, since every filtered gate between here and `WSPC-D008` would sail past a red suite.)
  - `rust/src/frb_generated.rs`, `lib/src/rust/**` (regenerated bindings only — this ticket adds `#[frb]` functions, and adding one without regenerating leaves the Dart side unable to call it)
- **Scope (Out-of-Scope Files):**
  - `rust/src/api/auth.rs` (no credential path participates in bootstrap)
  - `lib/main.dart`, `lib/src/components/**`, `lib/src/screens/**`, `lib/src/providers/**` (hand-written Dart is Epic E)
- **Verification Command:** `cd rust && cargo test workspace::bootstrap -- --list | grep -q ': test' && cargo test workspace::bootstrap && cargo test && cargo clippy --all-targets -- -D warnings`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if bootstrap requires reading a credential, contacting a network host, or consulting authentication state; `flow-workspace-bootstrap.md` contains no such step and CAP-WS-01 forbids one."
  - "STOP if the encrypted index is placed inside the bundle directory; `tech-spec/guidelines.md` requires it live alongside, not within, and names the exact path."
  - "STOP if an index file found at the old `$HOME/.burlmd/index.sqlite3` path is opened, migrated, or copied. It is stale derived state under a path the specification no longer names; the new path starts empty and `WSPC-D005` rebuilds it from the bundle."
- **Description:** Implement `open_or_create_local_workspace` and `open_workspace` per `flow-workspace-bootstrap.md`. The second takes a caller-supplied directory and is what `CAP-WS-05` and ADR-005 decision 7 both already assume exists; it shares every post-condition with the first except that it neither creates the directory nor initializes a repository in one that has no history. Resolves the default Workspace location and the index location specified in `guidelines.md` — the latter replacing the `$HOME/.burlmd/index.sqlite3` placeholder `connection.rs` carries from Epic B — creates the directory when absent, initializes a version-controlled repository in place, generates and stores the root encryption key on first boot, opens the encrypted index, and writes a Workspace row with a local provider and no remote. The root key path moves here from the authentication flow, where it never belonged. Both this path and a future clone path must converge on identical post-conditions.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given no Workspace directory exists and no network is reachable
When the local Workspace is opened
Then the directory is created, a repository is initialized in it, and a Workspace row is written with a local provider and no remote URL

Given no root encryption key exists in secure storage
When the local Workspace is opened
Then a key is generated, stored, and used to open the encrypted index (`CAP-WS-04` — the key generation moves here from the authentication flow, where it never belonged)

Given a Workspace that already exists
When the local Workspace is opened again
Then the existing repository and Workspace row are reused and no second key is generated

Given a Workspace has been opened
When the index file location is inspected
Then it is outside the bundle directory, at the path `guidelines.md` names, and not at `$HOME/.burlmd/index.sqlite3`

Given an index file exists at the old `$HOME/.burlmd/index.sqlite3` path
When the local Workspace is opened
Then that file is neither opened nor migrated, and the Workspace opens against an index at the new path

Given an existing directory of Markdown files that this application did not create
When it is opened as a Workspace
Then it becomes the active Workspace, a Workspace row is written for it, and no file in it is modified

Given any connection opened against the encrypted index
When `PRAGMA foreign_keys` is queried on it
Then it reports enabled — the setting is per-connection and not stored in the file, and every cascade in the schema is inert without it

Given an index file whose `user_version` reads something other than 0
When the schema batch is re-applied on open
Then `user_version` is left as it was rather than reset to the baseline
```

#### WSPC-D005 Bundle Indexer
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** WSPC-D003, WSPC-D004
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/index/mod.rs`
  - `rust/src/index/scan.rs`
  - `rust/src/index/incremental.rs`
  - `rust/src/api/ffi_api.rs`
  - `rust/src/frb_generated.rs`, `lib/src/rust/**` (regenerated bindings only — this ticket adds `#[frb]` functions)
- **Scope (Out-of-Scope Files):**
  - `rust/src/sync/scheduler.rs` (wiring the scheduler's hook is deferred scope)
- **Verification Command:** `cd rust && cargo test index:: -- --list | grep -q ': test' && cargo test index:: && cargo clippy --all-targets -- -D warnings`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if a full rescan is required to keep the index current during ordinary editing; `architecture/risks.md` risk 3 requires incremental updates as the routine path."
  - "STOP if a file with unparseable frontmatter causes indexing to fail rather than being recorded as non-conformant; CAP-WS-05 and CAP-PORT-03 both depend on tolerating it."
- **Description:** Populate and maintain every index table from the bundle on disk — the work no production code has ever done. Covers a full scan producing Note rows with content hashes and conformance flags, full-text rows with their mapping rows, Link edges with derived target ids including ghost Links, and Directory rows including empty ones. Also provides the incremental path used on every write, and `reindex_workspace`, which closes Epic C's deferred item 3 where the sync scheduler's re-index hook currently calls a documented no-op. Full-text search must satisfy the sub-100ms constraint at a realistic corpus size.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given a bundle containing Notes in nested Directories
When the Workspace is indexed
Then every Note has a row keyed by its concept id, with a content hash and a conformance flag

Given a Note containing a link to another Note that exists
When the Workspace is indexed
Then a Link edge is recorded with the target's concept id and it resolves

Given a Note containing a link to a Note that does not exist
When the Workspace is indexed
Then a Link edge is still recorded and is reported as unresolved rather than dropped

Given an empty Directory in the bundle
When the Workspace is indexed
Then a Directory row exists for it

Given a single Note has changed on disk
When the incremental index path runs
Then only that Note's rows are rewritten and no full rescan occurs

Given an indexed Workspace of at least one thousand Notes
When a full-text query is executed
Then results return in under 100 milliseconds
```

#### WSPC-D006 Note and Directory Lifecycle
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** WSPC-D005
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/workspace/lifecycle.rs`
  - `rust/src/workspace/links_rewrite.rs`
  - `rust/src/api/ffi_api.rs`
  - `rust/src/frb_generated.rs`, `lib/src/rust/**` (regenerated bindings only — this ticket adds `#[frb]` functions)
- **Scope (Out-of-Scope Files):**
  - `rust/src/markdown/**`
  - `lib/**`
- **Verification Command:** `cd rust && cargo test workspace::lifecycle -- --list | grep -q ': test' && cargo test workspace::lifecycle && cargo clippy --all-targets -- -D warnings`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if a rename or move can complete having rewritten only some inbound Links; `architecture/risks.md` risk 8 identifies partial rewriting as a silent graph-corruption mode, so the operation must be atomic or must fail."
  - "STOP if a title collision is resolved by silently disambiguating the filename; the contract specifies an error."
  - "STOP if a rename is refused because rewriting inbound Links violated the `links` primary key. That is a collision to merge, not a conflict to report — see the note on the key in `data-models/schema.sql`. The STOP above requires the operation be atomic or fail; it does not make this a legitimate failure."
- **Description:** Implement creation, deletion, rename and move for Notes, and creation, rename and deletion for Directories, per `contracts/ffi_api.rs`. Because OKF identity is positional, rename and move change a Note's concept id, so each must rewrite the file, its index rows, and every inbound Link in one atomic operation committed together. Creation writes a conformant frontmatter block. Deletion is committed so it stays recoverable.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given a Workspace with a Directory
When a Note is created in it with a title
Then a file exists with a frontmatter block containing a non-empty type and that title, and it is indexed

Given three Notes link to a fourth
When the fourth Note is renamed
Then all three links resolve to the new concept id and no link is left pointing at the old one

Given a Note is moved to a different Directory
When the move completes
Then its concept id reflects the new path and every inbound link resolves

Given a rename fails partway through rewriting inbound links
When the operation returns
Then no file, index row, or link has been changed

Given a Note already exists with a name derived from a requested title
When a second Note is created with that title
Then the operation reports the path as unavailable and creates nothing

Given a Note is deleted
When local version history is inspected
Then the deletion is committed and the prior content is recoverable

Given a Note carrying an unflushed draft row is deleted
When the draft table is inspected
Then no row remains for it — the table has no foreign key, so nothing cascades and the deletion must clear it explicitly

Given a Note whose content is indexed for full-text search is deleted
When the search index is queried for text unique to it
Then nothing matches — the `notes` cascade removes `fts_mapping`, which is the only pointer to the FTS row, so the FTS row must be deleted first or it becomes permanently unreachable and undeletable

Given a Note carrying an unflushed draft row is renamed
When the draft table is inspected
Then the row is re-keyed to the new concept id and the drafted content is intact — this is the one case the missing foreign key exists to permit, so it is the one case that must be tested

Given a Note links to both `Old` and a not-yet-created `New`
When `Old` is renamed to `New`
Then the rename succeeds and the two inbound edges collapse to one, rather than failing on the `links` primary key
```

#### WSPC-D007 Persistence Tiers
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** WSPC-D003, WSPC-D005
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/workspace/persist.rs`
  - `rust/src/draft.rs` (**where `NoteMetadata` and `NoteState` are actually defined** — `api/ffi_api.rs` only re-exports them. The contract reshapes both: `NoteMetadata` loses `workspace_id` and gains `okf_conformant`, `NoteState` gains `restored_from_draft`.)
  - `rust/src/api/ffi_api.rs`
  - `rust/src/frb_generated.rs`, `lib/src/rust/**` (regenerated bindings only — this ticket adds `#[frb]` functions)
- **Scope (Out-of-Scope Files):**
  - `rust/src/sync/scheduler.rs` (called, not modified)
- **Verification Command:** `cd rust && cargo test workspace::persist -- --list | grep -q ': test' && cargo test workspace::persist && cargo clippy --all-targets -- -D warnings`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if a commit is triggered on a timer rather than on Note close; ADR-008 rejected timer-based commits explicitly."
  - "STOP if a file write is not atomic; `architecture/resilience.md` guarantees the previous state survives an abrupt termination mid-write."
- **Description:** Implement the four tiers of ADR-008. Every Block edit writes a draft row; roughly a second of inactivity splices and writes the file atomically; closing a Note or quitting flushes any pending write, makes one commit for the session, clears the draft row, and notifies the sync scheduler — giving `notify_activity()` its first caller since Epic C. The write tier compares the file on disk against the Core's current revision for that Note — initialised to the on-disk hash at open and **re-recorded after every successful write** — immediately before writing, and refuses the write on mismatch. The re-recording is the load-bearing half: the timer fires repeatedly in one session, so a baseline pinned to open time would make the second write fail against the first — the Optimistic Concurrency Control in `architecture/risks.md` risk 6, now guarding file content rather than a database column. That comparison belongs entirely to the Core: `flush_note` takes no revision token, because the UI never learns when the idle tier fires and any token it held would be stale by construction. Switching away from a Note counts as closing it.

  Tier 1 puts a synchronous encrypted write of the Note's full source on the keystroke path. That is the one place in this design where a per-keystroke cost scales with document length, so it is measured rather than assumed against the 16ms frame budget in `prd/constraints.md`.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given a Note is being edited
When a Block edit is committed
Then a draft row exists for that Note and the file on disk is unchanged

Given a draft row exists and the process is terminated without cleanup
When the Note is next opened
Then the in-progress content is restored and the state reports it came from a draft

Given a Note with pending edits
When the idle write tier fires
Then the file is written atomically and a new content hash is returned

Given a Note has been written but not closed
When local version history is inspected
Then no commit exists for this session yet

Given a Block is still focused and the idle interval elapses
When the write tier fires
Then the buffered source is spliced and written, later spans shift by the byte delta, and no reparse occurs

Given a Note with edits from this session
When the Note is closed
Then exactly one commit is made, the draft row is cleared, and the sync scheduler is notified — this commit is the whole of `CAP-WS-02`, the durability guarantee that makes a local-only Workspace trustworthy before any Remote exists

Given a Note with edits and no external modification
When the idle write tier fires twice in one session
Then both writes succeed and neither is refused — the baseline advances with each write, so the second is not compared against the state the first replaced

Given the on-disk file was changed by something other than this application
When the idle write tier fires
Then the write is refused with a revision mismatch carrying the current revision, and the file on disk is left untouched

Given a Note whose source is 100 kilobytes
When a single Block edit is committed to the draft tier
Then the measured write completes within the frame budget, and the measurement is recorded in the test rather than asserted by inspection
```

#### WSPC-D008 Editing FFI Surface
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** WSPC-D003, WSPC-D007
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/api/ffi_api.rs`
  - `rust/src/draft.rs` (`NoteState` and `NoteMetadata` are defined here and only re-exported by `api/ffi_api.rs`; this ticket changes both shapes)
  - `rust/src/frb_generated.rs`
  - `lib/src/rust/**` (regenerated bindings only)
  - `lib/src/providers/note_providers.dart` (calls `openNote(path)` and assigns `updateBlock`'s return value; both signatures change here, so `dart analyze` cannot pass without it)
- **Scope (Out-of-Scope Files):**
  - `lib/src/components/**` (Epic F consumes this surface)
  - `lib/src/screens/**`
- **Verification Command:** `cd rust && cargo test api::ffi_api -- --list | grep -q ': test' && cargo test api::ffi_api && cargo clippy --all-targets -- -D warnings && cd .. && dart analyze`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if `update_block` retains its AST-based signature; ADR-007 decision 4 replaces it with source text, and leaving both is a divergence the UI will pick the wrong one from."
  - "STOP if `update_block` parses, splices, or returns a `NoteState`. It is the per-keystroke call and must stay cheap; the reparse belongs in `commit_block`. Putting it back on the typing path contradicts ADR-007, ADR-008 and `architecture/risks.md` risk 7 simultaneously."
  - "STOP if generated bindings are hand-edited rather than regenerated and committed."
- **Description:** Expose the editing operations across the FFI boundary exactly as `contracts/ffi_api.rs` declares them: fetching a Block's raw source, the per-keystroke `update_block` that buffers text and writes the draft row without parsing, the `commit_block` that splices and reparses on blur, block insert, delete, split and merge, and the three range operations over a multi-Block selection. Remove `open_note_by_id` by merging it into `open_note`, which now takes a concept id. Regenerate and commit the bindings. Note that a splice can change a Block's node shape, so the returned state is authoritative and callers must not retain a block path across a reparsing call.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given an open Note
When a Block's source is requested
Then the raw Markdown for that Block is returned, including its delimiters

Given an open Note
When a Block is updated with new source text
Then a draft row is written, no parse occurs, and no AST is returned

Given a Block whose buffered source differs from the file
When the Block is committed
Then the source is spliced over its span, the Note is reparsed, and the new state is returned

Given a Block and a character offset
When the Block is split at that offset
Then the returned state contains two Blocks whose combined source equals the original

Given the first Block of a Note
When a merge with the previous Block is requested
Then the operation is a no-op and returns the unchanged state

Given a selection spanning three Blocks
When it is copied as Markdown
Then the returned text reproduces the selected content across all three

Given the exposed surface
When it is compared against contracts/ffi_api.rs
Then open_note accepts a concept id and there is exactly one open-a-Note entry point
And no exposed function takes a workspace_id parameter
```

#### WSPC-D009 Discovery and Graph FFI Surface
- **Type:** Feature
- **Effort:** 3
- **Dependencies:** WSPC-D005
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/api/ffi_api.rs`
  - `rust/src/index/query.rs`
  - `rust/src/draft.rs` (four functions here return `Vec<NoteMetadata>`, which is defined in this file and loses `workspace_id` under the contract. This ticket depends only on `WSPC-D005`, so it can be scheduled before `WSPC-D007` — the other ticket that scopes this file — and its own gate would then be unpassable without it.)
  - `rust/src/frb_generated.rs`
  - `lib/src/rust/**` (regenerated bindings only)
- **Scope (Out-of-Scope Files):**
  - `lib/src/components/**`
- **Verification Command:** `cd rust && cargo test index::query -- --list | grep -q ': test' && cargo test index::query && cargo clippy --all-targets -- -D warnings && cd .. && dart analyze`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if search results are capped by a hardcoded constant rather than the caller's limit; silent truncation is the defect this ticket removes."
  - "STOP if the link completion's insert text is assembled anywhere but the Core; the UI must not be able to construct a non-conformant link target."
- **Description:** Expose search and knowledge-graph queries: full-text search scoped to a Workspace with a caller-supplied limit, title-prefix lookup, the Link completion that returns ready-to-insert bundle-absolute link text, backlinks served by the target index, and the Workspace tree for the sidebar. The Workspace filter closes an open Investigate item from the PR #4 review, where search had no Workspace scope despite the capability being defined per Workspace. Search input must remain safe for arbitrary user text, preserving the existing escaping behavior.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given an indexed Workspace
When a full-text search is run with a limit
Then at most that many results are returned, ranked best match first

Given two Workspaces exist in the index
When a search is run scoped to one of them
Then no result from the other Workspace is returned

Given a search query containing hyphens, colons, parentheses and an unmatched quote
When the search is run
Then it returns results or an empty list, and never a query syntax error

Given Notes exist whose titles match a completion query
When link completions are requested
Then each result carries insert text that is a bundle-absolute Markdown link

Given three Notes link to a target Note
When backlinks for that Note are requested
Then all three source Notes are returned

Given a Workspace with nested Directories and Notes
When the tree is requested
Then it returns nested entries with Directories before Notes at each level
```
