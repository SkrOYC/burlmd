# ADR-012: Direct TextInputClient Proxy for Cross-Block Selection Editing

**Status:** Accepted

## Context

ADR-006 gives rendered Blocks one `SelectionArea`, while focused Blocks use an
ordinary raw-source field. A selection across rendered Blocks must support
typing, Delete, Backspace, and clipboard paste without turning the whole Note
into a Dart-owned text field or dispatching one edit per Block. The latter
would expose intermediate states, break one-operation undo and draft
durability, and leave Flutter to guess the post-reparse caret.

Flutter's pinned **3.44.3 / Dart 3.12.2** SDK exposes the needed platform
surface in `packages/flutter/lib/src/services/text_input.dart`: a
`TextInputClient` receives `updateEditingValue`, `performAction`,
`performPrivateCommand`, and `connectionClosed`; `TextInput.attach(client,
configuration)` creates a `TextInputConnection`; and that connection exposes
`show`, `setEditingState`, and `close`. This was verified in the Nix-pinned SDK
source at this ADR's acceptance date. The decision is conditional on that exact
surface and must be re-verified with the pinned Flutter SDK on upgrade.

## Decision

1. **Use a direct, ephemeral `TextInputClient` proxy while a rendered
   multi-Block selection is active.** It is not an `EditableText`, hidden
   `TextField`, or a Dart document model. It represents the selection only and
   holds no durable Note content.
2. **The proxy owns exactly one `TextInputConnection`.** It creates it with
   `TextInput.attach`, shows it only for that active selection, updates the
   platform editing state after a Core result, and closes it before focus
   promotion, selection dismissal, disposal, or a replacement proxy. A stale
   callback after close has no authority to mutate the Note.
3. **One completed platform edit becomes one Core range operation.** Typing and
   paste invoke `replace_range`; Delete and Backspace invoke `delete_range`.
   The proxy dispatches neither per-Block mutations nor a sequence of Core
   calls. Core does the source splice, reparse, draft write, undo bookkeeping,
   and returns `RangeEditResult { state, caret }`. The proxy renders that
   result and uses `RangeEditCaret::Block` or `::Phantom` verbatim.
4. **Composition is a lifecycle boundary.** While `TextEditingValue.composing`
   is valid and non-collapsed, the proxy reflects the platform value but sends
   no Core mutation and never installs a Core result over the composing range.
   It dispatches only after composition is committed/collapsed, or cancels the
   connection before a focus/selection transition. This prevents a CJK/IME
   pre-edit string from being split across mutations, lost, duplicated, or
   reordered.
5. **Keyboard and clipboard stay platform-native.** The proxy receives normal
   text input, Delete/Backspace and paste through Flutter's text-input path;
   it does not synthesize characters from key events. Shortcut handling remains
   focused-Block behavior. `performAction` and private commands are forwarded
   only when their behavior is explicitly specified; unsupported actions do
   not invent editing semantics.

## Alternatives considered

- **Sequence existing per-Block edits in Dart.** Rejected: it violates Core
  atomicity, produces intermediate render states, and cannot provide one
  authoritative caret or undo entry.
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
