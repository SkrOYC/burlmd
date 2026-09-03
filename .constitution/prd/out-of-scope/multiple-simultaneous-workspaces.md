---
decision: deferred
date: "2026-09-03"
---
# Out of Scope: Multiple Simultaneous Workspaces

**Status:** Deferred
**Related:** CAP-WS-01, CAP-WS-05

## The deferred concept
Managing several Workspaces at once — a switcher, cross-Workspace search, Links that cross Workspace boundaries, or more than one Workspace open concurrently.

## Reasoning
The Workspace is defined as "the root container holding all Notes and Directories." A user with one archive of their own thinking has one such root. Separating personal from work notes is real, but it is more naturally a Directory-level concern than a second root, and Directories already nest arbitrarily.

Supporting several roots at once would affect nearly every other capability. Search would need a scope selector, Links would need a Workspace target, and the Directory tree would gain another level. That cost buys little before the single-Workspace experience is proven.

## What is in scope instead
One Workspace is active at a time. The Writer can open or switch to another Workspace without keeping both active simultaneously.

## Conditions that would reopen this
Real, sustained use of two genuinely separate archives, where the friction of opening one at a time is felt in practice rather than anticipated. Worth noting the deferral is cheap to reverse: the model already treats a Workspace as an identified container rather than as an implicit global, so a second one is additive rather than structural.
