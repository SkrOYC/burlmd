# Epic F: Editor Depth

Makes the application pleasant to write in. After Epic E a Note can be opened and read, but only plain single-run paragraphs are editable — no heading, list, quote or code Block can be edited, no Block can be created, and selection stops at every Block boundary. This epic delivers Live Preview, cross-Block selection, Block manipulation through ordinary typing, and Link insertion.

This epic became substantially cheaper and less risky when the editing model changed to raw-on-focus. Mapping formatted output to editable spans — previously the largest engineering risk in the project, and the source of a shipped regression — is no longer a requirement *for the focused Block*: its editable surface holds plain source text, so there is nothing to map.

It is not gone entirely, and `EDIT-F003`/`EDIT-F007` are where it survives. A `BlockRange` spans *unfocused* Blocks, which the user sees rendered, so its offsets are rendered offsets and the Core must resolve them to source offsets to splice. ADR-007 decision 8 specifies that mapping and establishes that the parser already yields it. The residual risk is far smaller than what it replaced: the dangerous version mapped back from laid-out geometry, which depends on fonts and wrapping, while this one is a pure function of source text and parser output computed where the parser already runs.

#### EDIT-F001 Spike: Rendered-to-Raw Promotion Fidelity
- **Type:** Spike
- **Effort:** 2
- **Dependencies:** SHEL-E004
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `.constitution/spikes/SPK-EDIT-F001.md`
- **Scope (Out-of-Scope Files):**
  - `lib/**` (no production code in a Spike)
  - `rust/src/**`
- **Verification Command:** `spike_commit=a960e34afb59e46ead601375bbfd6424eb4193ec; correction_commit=HEAD; test -s .constitution/spikes/SPK-EDIT-F001.md && ! grep -q 'Status: placeholder' .constitution/spikes/SPK-EDIT-F001.md && ! grep -q 'To be filled' .constitution/spikes/SPK-EDIT-F001.md && git diff --quiet "$spike_commit^" "$spike_commit" -- lib rust/src && git diff --check "$correction_commit^" "$correction_commit" && flutter test test/components/editor_test.dart test/components/selection_test.dart && dart analyze && ! rg -n '\[DEBUG-' lib rust test scripts`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if this Spike is landed across more than one commit; its gate asserts that the Spike's own commit touched no production code, for the reason recorded on `WSPC-D001`. This restriction applies to the original Spike delivery only: a separately committed, independent-review correction may add narrowly scoped evidence, contract reconciliation, regression coverage, and the minimum proven stabilization without rewriting history; record the deviation and every out-of-scope touch below."
  - "STOP if the promotion cannot be made typographically stable; that outcome selects the custom-selectable escalation path recorded in ADR-006 decision 6, which is a Stage 3 decision rather than an improvised widget change."
  - "STOP if resolving a rendered offset to a source offset turns out to need anything beyond the parser's own inline ranges; ADR-007 decision 8 asserts it does not, and an escalation there is a Stage 3 decision."
  - "STOP without also settling the case where a selection's INTERIOR contains the focused Block. It fails the rendered-offset rule for the same reason as the anchor, and its inline span map is stale between `update_block` and `commit_block` while `delete_range`/`replace_range` splice using it. Blurring before dispatching a range operation likely dissolves both; confirm it here."
  - "STOP if the drag-outward case turns out to be reachable and unspecified. ADR-006 accepts that a selection may start inside the focused Block and extend past it, but `BlockRange` defines every offset as a rendered offset on the grounds that a range spans unfocused Blocks — which is false for that one anchor, since a focused Block displays raw source. Settle it here, because this Spike already has both presentations in front of it: either the drag cannot escape an `EditableText` inside a `SelectableRegion`, in which case ADR-006's sentence is what needs correcting, or it can, in which case `BlockRange` needs a stated rule for a focused endpoint. Do not let `EDIT-F003` discover it."
  - "STOP if the finding is asserted from widget-property assertions rather than inspected rendered output; property assertions are precisely what missed the equivalent defect before."
- **Description:** Determine, from actual rendered output, whether promoting a Block from its formatted presentation to its raw editable presentation can be made free of visible layout movement. The text necessarily differs; the geometry must not. Compare screenshots of the same Block in both states across the Block types in scope, identify which properties must be held identical, and record whether the promote-on-focus approach in ADR-006 is viable or whether the escalation path must be taken. `tech-spec/guidelines.md` already requires typographic identity as a standard; this Spike establishes whether it is achievable and what it costs.
- **Acceptance:**
  - **Mode:** hitl_sil
  - **Evidence:**
```gherkin
Given the spike report at .constitution/spikes/SPK-EDIT-F001.md
When it is reviewed
Then it contains rendered screenshot comparisons of at least paragraph, heading and list-item Blocks in both states
And it names every property that must be held identical between the two states
And it records a viable or not-viable verdict on promote-on-focus with reasoning
And no file under lib or rust/src is modified by the Spike's own commit — throwaway prototyping is expected and necessary here, since the screenshot comparisons require a running widget and the raw-source presentation for headings and list items is EDIT-F002's deliverable, which depends on this Spike; prototype in a scratch Flutter project outside this repository — not in lib/, and not in a location cargo clippy --all-targets or flutter test would pick up — and do not let production code arrive under cover of a Spike
```

#### EDIT-F002 Live Preview Block Promotion
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** EDIT-F001, WSPC-D008
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/components/editor.dart`
  - `lib/src/components/block_view.dart`
  - `lib/src/components/block_editor.dart`
  - `lib/src/providers/rust_api_provider.dart`
  - `lib/src/rust/**` (generated by `flutter_rust_bridge_codegen generate`)
  - `rust/src/api/ffi_api.rs`
  - `rust/src/markdown/spans.rs`
  - `rust/src/workspace/persist.rs`
  - `rust/src/frb_generated.rs` (generated by `flutter_rust_bridge_codegen generate`)
  - `test/components/editor_test.dart`
- **Scope (Out-of-Scope Files):**
  - `lib/src/components/workspace_tree.dart`
- **Verification Command:** `cargo test --lib --manifest-path rust/Cargo.toml && flutter_rust_bridge_codegen generate && flutter test test/components/editor_test.dart test/components/selection_test.dart test/components/lifecycle_actions_test.dart test/components/block_editing_test.dart && BURLMD_SMOKE_F002=1 ./scripts/smoke-shot.sh f002-live-preview && dart analyze && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if the editable field renders formatted text rather than raw source; the whole point of this model is that the user sees and types real Markdown."
  - "STOP if the promotion introduces visible layout movement that the Spike identified as avoidable."
  - "STOP if edits are held in Dart state rather than sent to the Core; the Presentation Container must not become an owner of Note content."
  - "STOP if the editor calls a reparsing Core function on every keystroke; typing uses the buffering call, and the commit happens on blur. Reparsing per keystroke is what the 16ms budget cannot absorb."
- **Description:** Implement CAP-EDIT-01. Every Block renders formatted except the one holding the caret, which displays its raw Markdown source in an editable field with the caret placed where the user clicked. Every keystroke goes to the Core's per-keystroke call, which buffers the text and writes the draft row without parsing and without returning an AST — while a Block is focused the UI already holds the text being displayed, so there is nothing for a per-keystroke round trip to tell it. Blurring commits the Block, at which point the Core splices, reparses, and returns the authoritative state; because a splice can change a Block's node shape, focus is re-derived from that state rather than from a retained path. All Block types in scope are editable this way, not only paragraphs.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**
```gherkin
Given a Note with a paragraph containing bold text
When that paragraph is not focused
Then it renders with the bold run styled and no delimiters visible

Given the same paragraph
When it receives focus
Then it displays its raw Markdown source including the emphasis delimiters

Given a heading, a list item, a blockquote and a code Block
When each receives focus in turn
Then each displays its own raw source and accepts edits

Given a thematic break
When it is not focused
Then it renders as a rule, and when focused it displays its own source like any other Block — completing the `CAP-EDIT-02` Block-type list, whose last member no criterion previously mentioned

Given a Block is clicked partway through its text
When it is promoted
Then the caret is placed at the clicked position rather than at the start

Given a list or blockquote container with an editable descendant leaf
When it is promoted, split, inserted after, or merged with its predecessor
Then every Core edit address is that real leaf path (for example `[0, 1, 0]`), never the top-level container path `[0]`, which `update_block` rejects

Given a Block is focused and then blurred
When it returns to formatted output
Then its position and size are unchanged from before it was focused

Given a paragraph's raw source is edited to begin with a list marker
When focus leaves the Block
Then it renders as a list item and focus is re-derived from the returned state

Given an IME composition is live — a marked, not-yet-committed string such as CJK input
When the Block commits (blur) or the user navigates away and back
Then no composed or committed characters are lost, duplicated, or reordered, and the composition either completes into the Block's source or is visibly cancelled — never silently discarded
```

The last scenario exists because ADR-006 inherits the platform IME inside the focused field and nothing anywhere tested that a mid-composition string survives a commit; losing it is a correctness defect, not an edge case. It rides this ticket because this is where promotion first meets composition.

##### [EDIT-F001] Independent-review correction deviations & justifications
- `.constitution/tech-spec/adrs/ADR-006-raw-on-focus-editing.md`, `.constitution/tech-spec/contracts/ffi_api.rs`, and `rust/src/api/ffi_api.rs` — reconcile the settled focus/range invariant across ADR, contract, and exposed FFI documentation; no signature changed.
- `lib/src/components/editor.dart` and `lib/src/components/block_view.dart` — retain the formatted slot while longer raw source scrolls in the focused field, and reject an outward pointer sequence that began while a field was focused until a new rendered selection begins after blur.
- `test/components/editor_test.dart` and `test/components/selection_test.dart` — interaction and rendered-geometry regression tests, necessary to make the review correction durable.
- `lib/main.dart`, `scripts/smoke-shot.sh`, `.constitution/evidence/edit-f001/*.png`, and the evidence README — opt-in production-font fixture/capture support and generated `hitl_sil` artifacts. The harness accepts an explicit evidence output directory so normal `.qa/` captures remain ignored; these four PNGs are the documented exception to the normal no-binary-QA rule.
- `.constitution/tech-spec/changelog.md`, `.constitution/tech-spec/guidelines.md`, and `.constitution/tasks/changelog.md` — record this separately committed correction and its narrowly allowed durable evidence exception.

##### [EDIT-F002] Deviations & Justifications
- `test/components/lifecycle_actions_test.dart` — its `RustApi` fake needed `getBlockSource`/`commitBlock` overrides and promote-on-focus staging (tap before typing) because EDIT-F002 changed how the editor presents a focused Block, breaking this suite's existing IME-resync scenario; updated to match the new model, no criterion loosened.
- `lib/main.dart` — adds an env-gated (`BURLMD_SMOKE_F002`) staging hook that builds a demo Note through the Core and selects it, so the smoke-shot scenario can mount the editor pane; inert in normal use.
- `scripts/smoke-shot.sh` — forwards any caller-exported `BURLMD_SMOKE_*` variables to the launched app so the staging hook above is reachable from the verification harness; no behavior change without them.
- `rust/src/api/ffi_api.rs`, `rust/src/markdown/spans.rs`, `rust/src/workspace/persist.rs`, `lib/src/providers/rust_api_provider.dart`, and FRB-generated bindings — independent-review P1 correction: the old Dart mapping guessed raw offsets and promoted container paths that Core correctly refuses. `resolve_block_caret` is the Stage-3-sanctioned synchronous contract; it returns the actual editable leaf and its raw UTF-16 caret through the Core span map.
- `.constitution/tech-spec/{contracts/ffi_api.rs,changelog.md,stack.md}` — records the additive Core contract and Stage 3 minor-version bump. `test/components/editor_test.dart` and Rust span/session tests cover Unicode UTF-16 conversion, entities, escapes, noncanonical links, setext headings, fences, and nested list/quote leaves.
- `scripts/smoke-shot.sh` and `lib/src/components/editor.dart` — F002 now stages and asserts a readiness marker only after the selected demo Note reaches focused raw-source state. The exact verification command exports `BURLMD_SMOKE_F002=1`; a generic Workspace screenshot cannot pass this gate.
- `test/components/selection_test.dart` — F002's container-promotion correction touched this otherwise F003-owned suite only to update its `RustApi` fake for the additive `resolve_block_caret` contract and to retain real rendered-selection coverage; no F003 acceptance criterion changed.
- `test/components/block_editing_test.dart` — F002's structural-focus correction updates its Core fake and regressions because Enter, split, and Backspace now retain or re-derive real leaf paths after Core reparses; it does not change EDIT-F004 behavior or acceptance.
- `.constitution/tech-spec/contracts/ffi_api.rs`, `rust/src/api/ffi_api.rs`, `rust/src/workspace/persist.rs`, `lib/src/providers/rust_api_provider.dart`, generated bindings, and `test/components/block_editing_test.dart` — P1 continuation correction: `continue_block_after` replaces the list-only surface. Core now inspects the AST, continues Lists as sibling items, exits Blockquotes into adjacent top-level Blocks, and returns the real leaf/caret in both cases; Flutter no longer dispatches from path length.
- `.constitution/tech-spec/{contracts/ffi_api.rs,changelog.md}`, `rust/src/api/ffi_api.rs`, `rust/src/workspace/persist.rs`, `lib/src/providers/rust_api_provider.dart`, generated bindings, and `test/components/block_editing_test.dart` — P1 structural split/quoted-list correction: `split_block` now returns `StructuralEdit` and accepts the source string that owns Flutter's UTF-16 caret, so Core maps it through a live reparse and Flutter does not predict a successor path. Quoted-list continuation and merge repeat the complete source prefix (`> - `), with regressions at both Core and widget seams. The F002 gate now runs the full Rust library suite and `block_editing_test.dart` because these cross-layer structural contracts are no longer covered by the old UTF-16-only filter.

#### EDIT-F003 Cross-Block Selection and Copy
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** EDIT-F002
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/components/editor.dart`
  - `lib/src/components/block_view.dart`
  - `test/components/selection_test.dart`
- **Scope (Out-of-Scope Files):**
  - `lib/src/components/block_editor.dart`
- **Verification Command:** `cargo test --lib --manifest-path rust/Cargo.toml && flutter_rust_bridge_codegen generate && flutter test test/components/selection_test.dart test/components/editor_test.dart && BURLMD_SMOKE_F003=1 ./scripts/smoke-shot.sh f003-selection && dart analyze && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if producing Markdown for a selection requires serializing in Dart; the Core owns both the AST and the source text and already exposes this."
  - "STOP if cross-Block selection is achieved by making the whole Note one editable field; that abandons the Block model the entire contract is addressed by."
- **Description:** Implement CAP-EDIT-04. Rendered Blocks participate in one selection region so a selection can span them, supporting drag selection and select-all. Copying a multi-Block selection yields Markdown that reproduces the selected content, produced by the Core rather than reconstructed in the UI. Selection coordinates are ephemeral UI state and are the only Note-adjacent state the Presentation Container holds.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**
```gherkin
Given a Note with several Blocks and none focused
When a selection is dragged from within the first Block to within the third
Then the selection spans all three Blocks and is visibly highlighted across them

Given a selection spanning three Blocks
When it is copied
Then the clipboard contains Markdown reproducing the selected content across all three

Given a Note whose Blocks include a code block, a list and a paragraph
When a selection spanning all three is copied
Then the clipboard reproduces each — the fixture is specified to be heterogeneous because the rendered-text offsets a range is expressed in are defined per `AstNode` variant, and a three-paragraph fixture exercises exactly one of those definitions while passing the criterion above

Given a selection spanning Blocks
When select-all is invoked
Then the whole Note is selected

Given a Block is focused for editing
When text within it is selected
Then the selection behaves normally within that Block
```

##### [EDIT-F003] Deviations & Justifications
- `lib/main.dart` — adds an env-gated (`BURLMD_SMOKE_F003`) staging half that builds the heterogeneous demo Note through the Core (create_note + insert_block) and selects it so the editor pane mounts. Strictly forced: the Editor only mounts once a Note is selected, so it cannot stage its own Note — the same structural reason EDIT-F002's staging half lives there. The select-all half of the hook stays in `editor.dart` (in scope). Inert without the QA-harness variable.
- `scripts/smoke-shot.sh` — when `BURLMD_SMOKE_F003=1`, requires the staged code-block/list/paragraph Note to report that the editor-level Select All reached the full Core range before capturing. A generic rendered window cannot satisfy this gate; the readiness file remains inert for ordinary launches.
- `.constitution/tech-spec/{contracts/ffi_api.rs,guidelines.md,changelog.md}`, `rust/src/api/ffi_api.rs`, and generated bindings — the `BlockRange` boundary now accepts Flutter UTF-16 rendered-text offsets, converts them to Core scalar offsets, and rejects a surrogate interior. The contract, guidance, changelog, FFI wrapper, and generated Dart documentation must change together because they define or expose the same boundary.

#### EDIT-F004 Block Creation, Splitting and Merging
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** EDIT-F002
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/components/block_editor.dart`
  - `lib/src/components/editor.dart`
  - `test/components/block_editing_test.dart`
- **Scope (Out-of-Scope Files):**
  - `rust/src/**` (the Core surface already exists)
- **Verification Command:** `flutter test test/components/block_editing_test.dart && BURLMD_SMOKE_F004=1 ./scripts/smoke-shot.sh f004-block-editing`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if a Block is created or removed by mutating a local list in Dart rather than through the Core; the returned state is authoritative."
- **Description:** Implement CAP-EDIT-03. Pressing Enter at the end of a Block starts a new one; pressing it mid-Block splits at the caret; pressing Backspace at the start of a Block merges it into the predecessor. Each is committed through the Core and the caret is placed from the returned state. Without this the Note's structure is fixed at creation and the editor cannot compose anything.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**
```gherkin
Given the caret is at the end of a Block
When Enter is pressed
Then a new empty Block receives focus, held as UI-side caret position rather than committed to the Core — CommonMark has no representation of an empty paragraph, so no empty `continue_block_after` call is made and there is no `block_path` for the first keystroke to address

Given that new empty Block
When the first character is typed
Then `continue_block_after` is called with that character as its source, and every subsequent keystroke goes through `update_block` against the returned path

Given that new empty Block
When focus leaves it without anything being typed
Then no continuation is called and the Note is unchanged

Given a real Block was edited before Enter opens its empty successor
When that empty successor is abandoned
Then `commit_block` adopts the preceding edit exactly once before it renders formatted again

Given the caret is in the middle of a Block's text
When Enter is pressed
Then the Block splits at the caret and the combined source of the two Blocks equals the original

Given the caret is at the start of a Block that is not the first
When Backspace is pressed
Then the Block merges into its predecessor and the caret sits at the join

Given the caret is at the start of the first Block
When Backspace is pressed
Then nothing changes

Given a new empty Note
When text is typed and Enter is pressed twice
Then the Note contains the expected Blocks in order
```

##### [EDIT-F004] Deviations & Justifications
- `lib/main.dart` — adds an env-gated (`BURLMD_SMOKE_F004`) staging half that builds the three-paragraph demo Note through the Core (create_note + insert_block) and selects it. Strictly forced by the same structural reason as EDIT-F002's and EDIT-F003's staging halves: the Editor only mounts once a Note is selected, so it cannot stage its own Note; the promote-and-Enter half in `editor.dart` writes a `f004-promoted-phantom` readiness marker only after the staged Note has a focused phantom. `scripts/smoke-shot.sh` passes the F004 environment variable and rejects missing or invalid F004 readiness, so a generic window cannot pass. Inert without the QA-harness variable.

#### EDIT-F005 Inline Emphasis Shortcuts
- **Type:** Feature
- **Effort:** 2
- **Dependencies:** EDIT-F002
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/components/block_editor.dart`
  - `test/components/emphasis_shortcuts_test.dart`
- **Scope (Out-of-Scope Files):**
  - `lib/src/components/block_view.dart`
- **Verification Command:** `flutter test test/components/emphasis_shortcuts_test.dart && ./scripts/smoke-shot.sh f005-emphasis`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if a shortcut manipulates the AST rather than the focused Block's source text; under this editing model emphasis is delimiter insertion."
- **Description:** Implement CAP-EDIT-05. Standard shortcuts wrap the current selection in the corresponding Markdown delimiters within the focused Block, and unwrap when the selection is already wrapped. Because editing is raw, this is text manipulation rather than tree manipulation, which is why it is inexpensive here.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**
```gherkin
Given text is selected in the focused Block
When the bold shortcut is pressed
Then the selection is wrapped in bold delimiters and remains selected

Given a selection already wrapped in bold delimiters
When the bold shortcut is pressed
Then the delimiters are removed

Given no text is selected
When an emphasis shortcut is pressed
Then delimiters are inserted at the caret with the caret placed between them

Given the italic, strikethrough and inline-code shortcuts
When each is pressed with a selection
Then the selection is wrapped in the corresponding delimiters
```

#### EDIT-F006 Link Insertion Completion
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** EDIT-F002, WSPC-D009, WSPC-D006 (**`WSPC-D006` is here for `createNote`, not for `linkCompletions`.** The create-on-follow criterion below calls it, and this ticket scopes no provider file and no Rust, so it cannot land the wrapper itself — the test's `RustApi` override would not compile against a class lacking the method. Recorded because the dependency is invisible from the wrapper table, which lists only `linkCompletions` for this ticket.)
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/components/link_completion.dart`
  - `lib/src/components/block_editor.dart`
  - `test/components/link_completion_test.dart`
- **Scope (Out-of-Scope Files):**
  - `rust/src/**`
- **Verification Command:** `flutter test test/components/link_completion_test.dart && ./scripts/smoke-shot.sh f006-link-completion`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if the UI constructs the inserted link target itself; the Core returns ready-to-insert text so that a non-conformant target cannot be produced."
  - "STOP if the double-bracket trigger is left in the stored text; it is an affordance, not a storage format."
- **Description:** Implement CAP-GRAPH-02. Typing the double-bracket trigger in a focused Block opens a completion listing Notes by title; accepting a candidate replaces the trigger with the Core-supplied Markdown link. The user never types a link target. Rendered Blocks make Links followable, and a Link whose target does not exist renders distinctly, which is what makes writing forward into an uncreated concept a usable workflow.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**
```gherkin
Given a focused Block and existing Notes
When the double-bracket trigger is typed
Then a completion appears listing Notes matching what follows it

Given the completion is open
When a candidate is accepted
Then the trigger is replaced by a Markdown link supplied by the Core and no double brackets remain in the text

Given a Block containing a Link to an existing Note
When the Block is rendered
Then the Link is followable and opens the target Note (`CAP-GRAPH-03`, whose only home in this wave is this ticket even though its subject is insertion)

Given a Block containing a Link whose target does not exist
When the Block is rendered
Then the Link renders distinctly from a resolving Link

Given a Link whose target does not exist
When it is followed
Then the target Note is created and opened — the second half of `CAP-GRAPH-04`, which the contract asserts the UI performs and which no criterion previously covered

Given a Note is open holding a ghost Link, and its target is created elsewhere in the meantime
When that Link is followed
Then the existing Note opens rather than the create path running — `InlineElement::Link.exists` is advisory and goes stale the moment any other Note is created or deleted, so the follow path re-resolves against the index rather than trusting the flag; trusting it here calls `create_note` and gets `PathUnavailable` for a Link that resolves perfectly well, which `SHEL-E005`'s STOP then forbids working around

Given a Note is open holding a resolving Link, and its target is deleted elsewhere in the meantime
When that Link is followed
Then the create-on-follow offer appears rather than a not-found error — the mirror of the case above, from the same stale flag

Given the completion is open
When it is dismissed without accepting
Then the typed text is left exactly as entered
```

#### EDIT-F007 Editing Across a Multi-Block Selection
- **Type:** Feature
- **Effort:** 3
- **Dependencies:** EDIT-F003, EDIT-F004
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/components/editor.dart`
  - `lib/src/components/block_editor.dart`
  - `test/components/selection_editing_test.dart`
- **Scope (Out-of-Scope Files):**
  - `rust/src/**`
- **Verification Command:** `flutter test test/components/selection_editing_test.dart && ./scripts/smoke-shot.sh f007-range-editing`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if a range operation is implemented as a sequence of per-Block edits; that is not atomic and leaves the Note in intermediate states the Core never sanctioned."
- **Description:** Close the last gap in ADR-006 — the interaction it identifies as the fiddliest in the design. Typing over, deleting, or pasting into a selection that spans Blocks is dispatched to the Core as one range operation, and the caret is re-derived from the returned state. Doing this per-Block instead would produce intermediate states and lose atomicity.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**
```gherkin
Given a selection spanning three Blocks
When a character is typed
Then the selection is replaced in a single operation and the caret sits after the inserted character

Given a selection spanning three Blocks
When Delete or Backspace is pressed
Then the selected content is removed in a single operation

Given a selection spanning parts of two Blocks
When it is replaced
Then the unselected remainders of both Blocks are preserved and joined correctly

Given a range operation completes
When the caret position is checked
Then it was derived from the returned state rather than from a path retained across the call
```
