# Out of Scope: Hidden-Markdown WYSIWYG Editing

**Status:** Rejected (was P0 through v1.0.1)
**Superseded by:** CAP-EDIT-01 (Live Preview)

## The rejected concept
Formatting text inline "without seeing raw Markdown asterisks/backticks" — an editing surface that renders every Block as formatted output at all times and never exposes the underlying source, in the manner of a conventional rich-text or block-based document editor.

## Why it was in the PRD
The original product framing targeted a "General Consumer" who was assumed to be intimidated by raw Markdown syntax, and positioned the product against a Notion-like reference experience. That framing drove the executive summary, the primary actor's frictions, and the first P0 capability.

## Why it was rejected
The premise was wrong about the actual primary actor. The Writer persona writes Markdown by preference, not under duress, and specifically wants to see the real stored source of whatever they are editing. Hiding it removes information they actively want.

Three consequences reinforced the decision rather than caused it:

1. **It fought the storage guarantee.** An editor that never shows source must reconstruct source on every save, which makes Edit Fidelity (leaving untouched regions byte-identical) substantially harder to guarantee and produces version history full of changes the user did not make.
2. **It was the most expensive thing in the plan.** Rendering formatted output *inside* an editable surface — mapping inline emphasis runs to editable spans and back — was the single largest engineering risk identified, and the source of a real shipped regression where multi-run paragraphs silently lost all formatting the moment they became editable.
3. **It bought nothing for the Automated Consumer.** The on-disk format is what agents read; how the application renders it while editing is irrelevant to them.

## What replaced it
Live Preview (CAP-EDIT-01): the focused Block shows raw source, every other Block renders formatted. The user reads a finished document and edits real text, with no mode toggle.

## Conditions that would reopen this
A deliberate decision to target a Markdown-averse audience as a *primary* actor rather than this project's actual user. That would be a change of product, not a change of feature, and would need its own PRD pass rather than an amendment to this one.
