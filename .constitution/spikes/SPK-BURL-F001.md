# Spike Report: BURL-F001 Rendered-to-Raw Promotion Fidelity

**Status:** Complete. Executed on branch `feat/epic-f-editor-depth`; prototype lives at `/tmp/spike-edit-f001` (Flutter widget tests) and `/tmp/spike-edit-f001-cargo` (Rust parser probe), outside this repository. No file under `lib/`, `rust/src/` or `test/` was touched.

## 1. Context & Objective
- **Triggering upstream file/section:** `.constitution/tech-spec/adrs/ADR-006-raw-on-focus-editing.md` decisions 2 and 6, and its first Negative consequence; the typographic-identity standard in `tech-spec/guidelines.md`.
- **Target:** Whether promoting a Block from its formatted presentation to its raw editable presentation can be made free of visible layout movement, and what must be held identical for that to hold.

Under CAP-EDIT-01 the text necessarily differs between the two states — `**bold**` versus bold. The geometry must not. If it does, every Block visibly jumps as the caret moves through the Note, which would make the editing model unpleasant in exactly the way it exists to avoid.

## 2. Codebase Baseline
- **Current State:** `lib/src/components/editor.dart` already dispatches between a read-only render path (`renderBlock` → `Text.rich` over `renderInline` spans) and an editable path (`_EditableParagraph` → `TextField`). Both presentations exist to compare, but they are *never shown for the same Block*: only single-run paragraphs are editable today, everything else renders read-only. The read-only path styles runs via nullable fields on `TextSpan` (so leaf runs inherit ancestor weight — e.g. a heading's bold), while `_paragraphStyle` builds an explicit `TextStyle` for the editable field. Those two styling conventions are exactly where divergence would originate.
- **Discovered Constraints:**
  - `Text.rich` merges its outer style with `MaterialApp`'s `DefaultTextStyle` (`bodyMedium`, which carries `height ≈ 1.43`). `EditableText` reads its `style` literally and consults no `DefaultTextStyle`. Any property left implicit therefore differs between the states by construction (measured below).
  - `RenderParagraph` defaults to `TextLeadingDistribution.even`; `RenderEditable` defaults to `proportional`. Left implicit, this shifts glyphs ~2px vertically between states at equal total height.
  - `EditableText`/`TextField` do **not** participate in an enclosing `SelectionArea` on Flutter 3.44.3 (measured, §3c) — which resolves the drag-outward question before `BURL-F003` reaches it.

## 3. Options & Trade-offs

### 3a. Promotion fidelity measurements (real RenderBox geometry)

Method: `flutter test` on a real rendered tree (scratch project). Each Block wrapped in a `RepaintBoundary`; size read off the actual `RenderBox`; line count and first painted glyph-line's vertical offset derived from `getBoxesForSelection` boxes on the deepest `RenderParagraph`/`RenderEditable` in each subtree. Formatted fixtures mirror `editor.dart`'s render path; raw fixtures hold Markdown source in an `EditableText` at the same width constraint (400 logical px). Test default font (Ahem) makes every glyph a fixed-size box — proportional-font caveats noted in §5.

Both presentations driven from **one shared style factory**, with every metric-pertinent property pinned explicitly:

| Block | State | width | height | lines | firstLineTop |
|---|---|---|---|---|---|
| paragraph (`Intro with **b** end`) | formatted | 228.0 | **20.0** | 1 | 2.8 |
| paragraph | raw | 400.0 | **20.0** | 1 | 2.8 |
| heading lvl 2 (`## Head two`, 24px bold) | formatted | 194.0 | **30.0** | 1 | 3.0 |
| heading lvl 2 | raw | 400.0 | **30.0** | 1 | 3.0 |
| list item (`- item one`, bullet row) | formatted | 400.0 | **20.0** | 1 | 2.8 |
| list item | raw | 400.0 | **20.0** | 1 | 2.8 |
| blockquote (`> quoted line`, left border) | formatted | 171.8 | **20.0** | 1 | 2.8 |
| blockquote | raw | 400.0 | **20.0** | 1 | 2.8 |
| code block (fenced, 2 content lines, pad 8) | formatted | 400.0 | **52.0** | **2** | 9.9 |
| code block (raw incl. fence lines) | raw | 400.0 | **88.0** | **4** | 9.9 |

With styles pinned, paragraph, heading, list item and blockquote are geometrically identical in every measured dimension. Width differs only where the formatted Row/inline layout shrink-wraps (228.0 vs 400.0) — the block's *occupied* width, not its layout slot; under the editor's full-width column both get the same constraints, so no sibling moves.

**The hazard, demonstrated rather than asserted.** With `height` left implicit (the natural way to write both paths):

| paragraph variant | height | firstLineTop |
|---|---|---|
| formatted (`Text.rich`, inherits `bodyMedium.height ≈ 1.43`) | 20.0 | 3.0 |
| raw (`EditableText`, no `DefaultTextStyle` lookup) | **14.0** | **0.0** |

That is a ~6 px vertical jump *per line* on every focus — invisible to any widget-property assertion that checks `style.fontSize` on both sides, because both would report 14. Only rendered geometry catches it. Similarly, leaving leading distribution implicit produced equal heights (20.0) but shifted firstLineTop 2.85 vs 4.74 — a sub-baseline wobble visible as glyph jump at promotion.

### 3b. Properties that must be held identical, and how

| Property | Must hold | How to hold it |
|---|---|---|
| Font size per Block type (heading levels ×) | yes | Shared style factory producing the single `TextStyle` per Block type, consumed by both `renderBlock` and the promoted field. |
| Font family / fallbacks (incl. monospace for inline code) | yes | Same factory; the raw field shows delimiters as plain text in the Block's *base* style, so only per-type families matter. |
| Font weight / slant / decoration of the Block's base style (headings bold) | yes | Factory emits explicit values (not null-inherit) so the field cannot miss an inherited weight. |
| Line height (`TextStyle.height`) | yes — the sharpest trap | Pin explicitly in the factory for BOTH paths. `Text` inherits `DefaultTextStyle`'s height; `EditableText` does not. Measured 20.0 vs 14.0 unpinned. |
| Leading distribution (`TextHeightBehavior.leadingDistribution`) | yes | Set `textHeightBehavior: TextHeightBehavior(leadingDistribution: even)` on the editable field (and/or merge into `DefaultTextStyle`); don't rely on either default. Measured 2.85 vs 4.74 unpinned. |
| Container padding & decoration (blockquote border+left pad, code background+pad, list marker column) | yes | Replicate the exact container widget around the promoted field; measured identical when replicated (firstLineTop 9.9 in both code-block states). |
| Wrap width, soft-wrap, `maxLines` (null) | yes | Promoted field sits in the same layout slot with the same constraints; `maxLines: null`. |
| Text scaling (`MediaQuery.textScaler`), text direction, alignment | yes | Never bypass `MediaQuery` for either path; verify at a non-1.0 scale factor in `BURL-F002`'s smoke shot. |

Not required to match: caret/cursor painting (paint-only, no layout effect), selection highlight, IME composing underline.

**Intrinsic content differences (CAP-EDIT-01):** a fenced code Block's raw state contains fence lines, and a thematic break renders as a `Divider` unfocused and `---` focused. Those source bytes remain visible and editable, but they do not grow the Block: `blockPromotionSlot` preserves the complete formatted footprint and the focused raw field scrolls inside it. No styling discipline removes the bytes; the stabilization prevents their extra lines from moving sibling Blocks.

### 3c. Selection experiments (drag-outward, Flutter 3.44.3)

Real gesture-driven drags against `SelectionArea(onSelectionChanged:)` containing `Text('BEFORE…')`, a focused `TextField`, `Text('AFTER…')`:

- **Outward:** mouse-drag starting *inside* the focused field's text, ending past AFTER ⇒ region selection stayed **null**. The gesture belongs to the field; `SelectableRegion` never engages.
- **Inward:** mouse-drag from BEFORE down past the field ⇒ selected text was `"rker textAFTER marker text"` — the surrounding widgets selected normally and the field's content was **skipped entirely**, as a hole in the region.
- The field retained primary focus throughout.

So `EditableText`/`TextField` does not merely resist extending selection outward; it does not participate in the region at all, in either direction. A selection anchored inside a focused Block **cannot** extend past it.

### 3d. Option A vs Option B
- **Option A — promote-on-focus** (ADR-006 decision 2). Cheapest, extends the existing dispatch, inherits platform text editing. Viable per §3a once the property table above is enforced; the enforcement cost is one shared style factory plus two pinned properties (`height`, `textHeightBehavior`) — properties whose omission produces silent, assertion-proof jumps.
- **Option B — custom selectable render objects per Block** (ADR-006 decision 6). No promotion at all, so no movement is possible; costs implementing selection highlight painting and selection-event handling directly. **Not selected:** the visual-stability precondition of ADR-006 decision 6 ("if the promotion proves visually unacceptable") did not trigger.

## 4. Execution Directives
- **Chosen Option:** Option A — promote-on-focus is **viable**.
- **Why it fits:** Every inline-delimiter Block type in scope (paragraph, heading, list item, blockquote) measured pixel-identical in height, line count and first-line position across both states once the shared style factory pins the property table in §3b. The two known movement sources are (1) implicit `height`/leading-distribution defaults that differ structurally between `Text` and `EditableText` — fixed by pinning, verified by measurement — and (2) extra raw source lines from code fences or thematic breaks, now contained by `blockPromotionSlot`'s preserved formatted footprint and focused-field scrolling. The STOP condition "cannot be made typographically stable" is not met; the ADR-006 decision 6 escalation stays untaken.
- **Answers the ticket requires settled:**
  - **(a) Interior case — reachable as a skipped hole, but ineligible.** A region drag may begin in an unfocused Block, cross a focused `EditableText`, and continue in a later unfocused Block; Flutter selects around the field and omits its content (§3c). Its pointer epoch is nevertheless ineligible for every Core range operation: it began while the focused Block's span map could be stale, and blur during that drag does not turn it into a fresh rendered selection. Blur fires `commit_block`, reparses and rebuilds the map; only a new pointer-down and rendered selection after that commit may dispatch `delete_range`/`replace_range`/copy. Thus no range ever splices against the focused interior or its stale map.
  - **(b) Drag-outward — NOT reachable; ADR-006's sentence should be corrected.** Its Negative consequence reads *"While a Block is focused for editing, selection is scoped to that Block until the user drags outward."* Measured reality: selection cannot be dragged out of the focused field at all, and region drags across it skip its content. `BlockRange` therefore needs **no** focused-endpoint rule — no range endpoint can ever be a raw-source offset. Proposed correction wording: *"While a Block is focused for editing, its editable field does not participate in the surrounding SelectionArea (verified empirically on Flutter 3.44.3): gestures inside it belong to the field alone, and region drags crossing it select around it, omitting its content. A selection consequently can never have an endpoint inside the focused Block, `BlockRange` needs no focused-endpoint case, and every range operation is dispatched only after blur."*
  - **(c) Rendered→source offsets — confirmed, nothing beyond the parser's own inline ranges.** Fresh independent probe against pulldown-cmark 0.12.2 (`Parser::into_offset_iter()`): every rendered offset of a fixture containing bold, code span, entity and link resolved into some run's source range; byte-identical runs interpolate (`source.start + (offset − rendered.start)`), non-interpolable interiors (code-span/entity/link-target bytes) clamp atomically to run endpoints — exactly ADR-007 decision 8 as amended by `SPK-BURL-D001`/implemented by `BURL-D003`. No STOP.
- **Downstream Backlog Impact:** Unblocks `BURL-F002` (Live Preview Block Promotion) and through it the rest of Epic F. `BURL-F002` inherits: the shared style factory with pinned `height` and `textHeightBehavior`; replicated container decorations around promoted fields; the blur-before-range-op protocol; the corrected ADR-006 sentence (a Stage 3 edit, not `BURL-F002`'s code); and the rule that code-fence and thematic-break source remains editable inside the preserved formatted footprint, scrolling rather than growing the Block.
- **Verification Command result:** the ticket's gate command (file non-empty, placeholder markers absent, no production code in the Spike's commit) ⇒ exit 0.

## 5. Durable visual and boundary evidence

The original scratch measurements remain useful for line-height and leading-distribution diagnosis, but they do not exercise proportional production fonts at a wrap boundary. The checked-in [production-font captures](../evidence/edit-f001/README.md) now provide side-by-side formatted/focused evidence for paragraph, heading, and list item. They are generated exclusively by `scripts/smoke-shot.sh`; no image is hand-authored.

The companion regression in `test/components/editor_test.dart` sets a 320 logical-pixel viewport and searches actual `RenderParagraph` and `RenderEditable` line boxes until raw source takes an additional painted line for each of paragraph, heading, and list item. Its assertion is against the live entry `Rect`, not a `TextStyle`: the formatted footprint stays unchanged. This found a real missing stabilization in the first F002 implementation — matching font metrics is insufficient because the raw delimiter/prefix bytes shift a soft-wrap boundary. `blockPromotionSlot` now retains the formatted layout footprint and lets the focused raw field scroll inside it. That is the minimum local stabilization; no Stage 3 redesign is required.

The selection result is also regression-tested through a real mouse drag: a region pointer sequence can cross a focused middle `EditableText` and skip it, but it cannot issue a Core range operation even if it blurs before pointer-up. A fresh pointer-down and rendered drag after `commit_block` is required before Core copy can receive a `BlockRange`. This makes a focused interior ineligible by contract rather than pretending it cannot occur.
