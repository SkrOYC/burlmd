---
decision: deferred
date: "2026-08-25"
---
# Screen-reader certification

**Status:** Deferred
**Related:** Q20 ruling (accessibility baseline), open decision OD-02 in `.constitution/reports/2026-08-25-open-decisions.md`

## The deferred concept
Formally verifying and gating releases on screen-reader operation — Orca on Linux, VoiceOver on macOS — so that non-visual use of the application is a tested guarantee rather than an aspiration.

## Reasoning
The baseline standard adopted at Q20 requires keyboard completeness and semantic labels. Certification is different in kind. Screen-reader coverage of custom-rendered desktop content varies across host systems, so certification requires a dedicated interaction harness and might include platform limitations that burlmd doesn't control.

## What is in scope instead
The baseline: keyboard-completeness review bars and semantic labels adopted before Epics E and F paint widgets, so the accessible structure exists from the start rather than arriving as a retrofit.

## Conditions that would reopen this
**Deliberately unnamed.** The interview deferred certification without naming the condition that would revive it. OD-02 in `.constitution/reports/2026-08-25-open-decisions.md` records that omission. Until the operator names a platform maturity threshold, accessibility-driven request, or regulatory need, this deferral has no trigger. Downstream stages must treat the trigger as unknown, not as "never."
