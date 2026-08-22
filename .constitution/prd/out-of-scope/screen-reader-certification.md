# Out of Scope: Screen-Reader Certification

**Status:** Deferred
**Related:** Q20 ruling (accessibility baseline), open decision OD-02 in `.constitution/reports/2026-08-21-open-decisions.md`

## The deferred concept
Formally verifying and gating releases on screen-reader operation — Orca on Linux, VoiceOver on macOS — so that non-visual use of the application is a tested guarantee rather than an aspiration.

## Reasoning
The baseline standard adopted at Q20 keeps accessibility cheap where it is cheap: keyboard completeness as a hard review bar, and Flutter semantic labels as widgets are written. Certification is different in kind. Screen-reader coverage of custom-rendered desktop Flutter content is uneven today, especially under Orca, so certification means owning upstream framework gaps and maintaining a UI automation harness the project does not otherwise have. Committing to it now would buy a guarantee the underlying platform cannot consistently honor.

## What is in scope instead
The baseline: keyboard-completeness review bars and semantic labels adopted before Epics E and F paint widgets, so the accessible structure exists from the start rather than arriving as a retrofit.

## Conditions that would reopen this
**Deliberately unnamed.** The interview deferred certification without naming the condition that would revive it, and that omission is registered as open decision OD-02 rather than papered over here. Until the operator names a condition — a platform maturity threshold, an accessibility-driven user request, or regulatory need — this deferral has no stated trigger. Downstream stages must treat the trigger as unknown, not as "never."
