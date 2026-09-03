---
decision: deferred
date: 2026-07-24
---
# Out of Scope: Mobile Targets

**Status:** Deferred
**Related:** vision.md JTBD ("Sync seamlessly"), CAP-SYNC-01

## The deferred concept
Running the application on phones and tablets, and the multi-device synchronization story that assumes a phone on one end of it.

## Reasoning
The primary actor's operating context is desktop-first with an *expectation* of eventual multi-device access. That expectation shapes the architecture — it is why synchronization, offline tolerance, and non-destructive conflict reconciliation are requirements rather than afterthoughts — but it does not require a phone to exist in the first phase.

Deferring it keeps the surface honest in two ways. Editing interactions are currently specified around a cursor, a keyboard, and selection spanning Blocks; a touch surface would need its own interaction design rather than a scaled-down version of this one. And the at-rest protection constraint currently leans on desktop operating-system facilities, which have direct mobile equivalents but not identical ones.

## What is in scope instead
Desktop targets, with every synchronization and conflict capability specified as though a second device exists — because it will, and because retrofitting those guarantees later is far more expensive than honouring them now.

## Conditions that would reopen this
The desktop experience reaching daily-use quality, at which point mobile becomes the highest-value expansion available. Reopening requires its own interaction-design pass for touch editing; it is not a build-target change.
