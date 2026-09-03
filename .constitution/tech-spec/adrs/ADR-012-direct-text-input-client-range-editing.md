---
id: ADR-0012
status: accepted
date: 2026-08-23
certainty: assumed
assumption: "Migrated; the decision's ruling reference was not found in the status line."
---
# ADR-012: Direct TextInputClient Proxy for Cross-Block Selection Editing

**Status:** Accepted

## Context

ADR-006 gives rendered Blocks one `SelectionArea`, while focused Blocks use an
ordinary raw-source field. A selection across rendered Blocks must support
typing, Delete, Backspace, and clipboard paste without turning the whole Note
into a Dart-owned text field or dispatching one edit per Block. The latter
would expose intermediate states, break the one-operation boundary a later undo
stack can consume, and leave Flutter to guess the post-reparse caret.

Flutter's pinned **3.44.3 / Dart 3.12.2** SDK exposes the needed platform
surface in `packages/flutter/lib/src/services/text_input.dart`: a
`TextInputClient` requires `currentTextEditingValue`, `currentAutofillScope`,
`updateEditingValue`, `performAction`, `performPrivateCommand`,
`updateFloatingCursor`, `showAutocorrectionPromptRect`, and `connectionClosed`.
`TextInput.attach(client, configuration)` creates a `TextInputConnection`; it
exposes `show`, `setEditingState`, and `close`. Flutter's
`widgets/actions.dart` provides the `Actions`/`CallbackAction` mechanism, and
the pinned `DefaultTextEditingShortcuts` maps desktop Delete/Backspace to
`DeleteCharacterIntent` and clipboard shortcuts to
`CopySelectionTextIntent`/`PasteTextIntent`. This was verified in the
Nix-pinned SDK source at this ADR's acceptance date. The decision is
conditional on that exact surface and must be re-verified with the pinned
Flutter SDK on upgrade.

## Decision

1. **Use a direct, ephemeral `TextInputClient` proxy while a rendered
   multi-Block selection is active.** It is not an `EditableText`, hidden
   `TextField`, or a Dart document model. It represents the selection only and
   holds no durable Note content.
2. **The proxy owns exactly one `TextInputConnection`.** Its initial ephemeral
   value is `TextEditingValue.empty` (empty text, collapsed zero selection,
   empty composing range), so it has no copy of the Note or selected Markdown.
   It calls `TextInput.attach`, then **must call**
   `connection.setEditingState(TextEditingValue.empty)` before `show`. After a
   Core result it resets that same empty value before accepting another edit.
   It closes the connection before focus promotion, selection dismissal,
   disposal, or a replacement proxy. A stale callback after close has no
   authority to mutate the Note.
3. **Every required `TextInputClient` member has a defined proxy behavior.**
   `currentTextEditingValue` returns the ephemeral current proxy value;
   `currentAutofillScope` returns `null`; `updateEditingValue` processes only
   ordinary committed text/IME input; `performAction` and
   `performPrivateCommand` are no-ops unless a future contract assigns one;
   `updateFloatingCursor` and `showAutocorrectionPromptRect` are no-ops for
   this desktop-only proxy; and `connectionClosed` clears the connection and
   invalidates callbacks. Default `insertContent`, focus-control, toolbar,
   placeholder, and selector hooks keep their framework no-op defaults. The
   proxy does not enable the delta model.
4. **One completed edit becomes one Core range operation.** Ordinary committed
   text and completed IME input arrive through `updateEditingValue` and invoke
   `replace_range`. A focused `Actions`/`Shortcuts` layer, compatible with the
   pinned `DefaultTextEditingShortcuts`, explicitly handles
   `DeleteCharacterIntent` for Delete/Backspace, `PasteTextIntent`, and
   `CopySelectionTextIntent` for copy/cut: delete invokes `delete_range`; cut
   first writes `copy_range_as_markdown` to the clipboard, then invokes one
   `delete_range`; paste invokes `replace_range`; and copy only writes the
   Core Markdown to the clipboard. They do **not** rely on
   `updateEditingValue`. The proxy
   dispatches neither per-Block mutations nor a sequence of Core calls. Core
   does the source splice, reparse, and draft write, then returns
   `RangeEditResult { state, caret }`. It is compatible with one future undo
   command but does not implement CAP-EDIT-08's deferred undo stack. The proxy
   renders that result and uses `RangeEditCaret::Block` or `::Phantom`
   verbatim.
5. **Composition is a lifecycle boundary.** While `TextEditingValue.composing`
   is valid and non-collapsed, the proxy reflects the platform value but sends
   no Core mutation and never installs a Core result over the composing range.
   It dispatches only after composition is committed/collapsed, or cancels the
   connection before a focus/selection transition. This prevents a CJK/IME
   pre-edit string from being split across mutations, lost, duplicated, or
   reordered.
6. **Keyboard and clipboard stay platform-native.** The explicit Actions own
   the default desktop edit intents while this proxy is focused; arrow/focus
   navigation belongs to the completion or rendered-Link surface, not to an
   invented text field. Unsupported actions do not invent editing semantics.

## Alternatives considered

- **Sequence existing per-Block edits in Dart.** Rejected: it violates Core
  atomicity, produces intermediate render states, and cannot provide one
  authoritative caret or later undo boundary.
- **Promote the whole selection into one hidden or visible `TextField`.**
  Rejected: it creates a second Dart-side text buffer/document mapping and
  changes the Block editing model ADR-006 selected.
- **Implement a custom Flutter selection/text-input engine.** Rejected: it
  would require reimplementing IME, clipboard, keyboard, composing-range and
  connection lifecycle behavior with no product benefit.

## Consequences

- **Positive:** The platform owns IME, clipboard and keyboard integration,
  while Core remains the sole owner of Note mutation and caret derivation.
- **Positive:** Delete, type-over and paste share one atomic boundary and one
  Core-returned postcondition, including an empty Note's phantom insertion
  slot and UTF-16 source caret.
- **Negative:** The proxy has explicit connection and composition lifecycle
  duties; failing to close or stale-reject it is a correctness bug, not a UI
  cleanup issue.
- **Negative:** This depends on Flutter's non-publicly-stable-in-spirit
  text-input protocol surface despite its public API types, so the pinned SDK
  verification is a release gate whenever Flutter changes.
