---
decision: rejected
date: "2026-09-03"
---
# Out of Scope: Static-Site Publication Pipeline

**Status:** Rejected
**Related:** `html-export-and-publishing.md`

## The rejected concept
Generating a multi-page static website from a Workspace — index pages, per-Note routes, navigation chrome, asset pipelines, incremental rebuilds — as the publishing story.

## Why it was considered
Publishing a knowledge base to the web naturally suggests a site, and multi-page output is the conventional shape for one.

## Why it was rejected
1. **It is a product wearing an export's clothing.** A site generator brings templating, URL design, rebuild machinery, and its own failure modes — a second product to maintain alongside the first.
2. **A narrower output needs its own decision.** A single-Note HTML export is more useful than a Workspace website, but all HTML output remains deferred in this phase.
3. **Scope discipline.** "Export" otherwise accretes a rendering engine invisibly, one plausible-sounding feature at a time.

## What replaced it

Nothing in this phase. Plain-copy Export and the Bundle Archive remain the supported portability outcomes.

## Conditions that would reopen this
A deliberate product decision to serve public, audience-facing publishing of Workspaces as a goal in itself. That needs its own requirements pass; it will not grow out of the export epic.
