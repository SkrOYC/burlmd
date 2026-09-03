---
id: ADR-0006
status: accepted
date: 2026-09-03
certainty: assumed
assumption: "Migrated; the decision's ruling reference was not found in the status line."
---
# ADR-006: Raw-on-Focus Block Editing via SelectionArea and Focus Promotion

**Status:** Accepted
**Supersedes:** the hidden-Markdown editing model rejected in `prd/out-of-scope/hidden-markdown-wysiwyg.md`

## Context
PRD v1.1.0 replaced the previous "format without seeing raw Markdown asterisks/backticks" P0 with CAP-EDIT-01 (Live Preview): the focused Block shows raw Markdown source, every other Block renders formatted. CAP-EDIT-04 additionally requires selection spanning multiple Blocks.

Those two requirements are in tension under the obvious implementation. If each Block is its own editable text field, each field owns its own selection and selection cannot cross Block boundaries. That limitation is what `lib/src/components/editor.dart` has today, where `_buildBlock` dispatches between a read-only `renderBlock` path and an editable `_EditableParagraph`.

`architecture/containers.md` constrains the solution space further: the Presentation Container "is strictly stateless and maintains no persistent data of its own", and `guidelines.md` requires that "UI widgets must be completely stateless regarding note content." Adopting an existing Flutter block-editor package would violate both — `appflowy_editor` 6.2.0 (the strongest candidate, ~516 likes, last published ~7 months before this ADR) holds an `EditorState`/`Document` in Dart, which would make the UI the owner of note content and require a bidirectional mapping against the Rust AST as a permanent tax. `super_editor` was eliminated on maintenance and platform grounds: 0.2.7, last published roughly two years prior, with its own documentation listing Linux support as unverified — Linux being the primary development target.

Investigation of Flutter's own selection system resolved the tension. Per the `SelectableRegion` documentation, "to make a custom selectable widget, its render object needs to mix in `Selectable` and implement the required APIs to handle `SelectionEvent`s as well as paint appropriate selection highlights", registering via a `SelectionRegistrar`; and `Text` widgets automatically participate in an enclosing selection region. A `SelectionArea` therefore provides genuine cross-widget selection over read-only content. The documentation is silent on whether `EditableText`/`TextField` participate; only `Text` is documented as automatic. The design below deliberately does not depend on that silence resolving favourably.

Separately, PRD v1.1.0's shift to raw editing removed the hardest problem this layer previously had. Rendering formatted output *inside* an editable surface — mapping inline emphasis runs to editable spans and back — no longer exists as a requirement, because the editable surface displays plain source text.

## Decision
1. **Rendered Blocks are read-only widgets inside one `SelectionArea`.** They participate in a single selection region, satisfying CAP-EDIT-04 natively, including drag selection, select-all, and copy.
2. **Focus promotes exactly one Block to a raw editable field.** Clicking a Block replaces its rendered form with a plain text field containing that Block's raw Markdown source, with the caret placed at the clicked offset. Blurring returns it to rendered form.
3. **Range operations are dispatched to the Core Engine.** Copy, cut, delete, and replace across a multi-Block selection are expressed as a range — `(start_block_path, start_offset)` to `(end_block_path, end_offset)` — and executed in Rust, which owns both the AST and the source text. "Copy selection as Markdown" is correct by construction there and would require reimplementing serialization in Dart otherwise.
4. **Dart holds selection coordinates only.** Offsets and paths are ephemeral UI state, not note content, so `guidelines.md`'s statelessness rule is satisfied with no amendment to `architecture/containers.md`.
5. **No third-party editor package is adopted.** The evaluation and its reasons are recorded above so the decision is not silently revisited.
6. **Escalation path recorded, not taken.** If the rendered-to-raw promotion proves visually unacceptable, the documented fallback is to implement the `Selectable` mixin on each Block's render object so that both rendered and editable states participate in one continuous selection region. That is strictly more work — selection highlight painting and `SelectionEvent` handling become ours — and is not adopted pre-emptively.

## Consequences
- **Positive:** CAP-EDIT-01 and CAP-EDIT-04 are both satisfied without amending the architecture, and without the UI becoming a second owner of note content.
- **Positive:** This is an extension of the dispatch `editor.dart` already performs, not a rewrite. The existing read-only rendering path is retained as-is.
- **Positive:** The editable widget is a plain text field over plain text. The Epic B regression where a multi-run paragraph collapsed into one flat unstyled field — invisible to six passing widget tests until a screenshot was inspected — becomes structurally impossible, because no run-to-span mapping exists in the editable path any more.
- **Positive:** Flutter's own IME composition, caret, undo, and platform text actions are inherited rather than reimplemented.
- **Negative:** The rendered and raw presentations of a Block are different text (`**bold**` versus **bold**), so the promotion is visibly a change. It must not also be a *layout* change — differing font metrics between the two states would make the Block jump on focus. Identical text styling across both paths is a hard requirement, verified by rendered-output inspection rather than widget-property assertions.
- **Negative:** While a Block is focused for editing, its editable field does not participate in the surrounding `SelectionArea` (amended per `SPK-BURL-F001`, verified empirically on Flutter 3.44.3): gestures inside it belong to the field alone, and region drags crossing it select around it, omitting its content — a selection can never be dragged out of the focused Block nor have an endpoint inside it. A pointer sequence that began in the field remains ineligible even if blur occurs mid-drag; only a fresh rendered selection after blur/`commit_block` may dispatch a range operation. Consequently every `BlockRange` offset is a rendered offset over an unfocused, reparsed Block and no focused-endpoint rule is needed.
- **Negative:** Typing over a live cross-Block selection requires a replace-range round trip to Rust followed by re-render and caret placement in the resulting Block. This is the fiddliest interaction in the design and the most likely source of defects.
- **Neutral:** Keyboard emphasis shortcuts (CAP-EDIT-05) become text manipulation — wrapping a selection in delimiters — rather than AST mutation, which is substantially simpler than under the rejected model.
