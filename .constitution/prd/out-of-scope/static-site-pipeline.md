# Out of Scope: Static-Site Publication Pipeline

**Status:** Rejected
**Related:** CAP-PORT-04 (HTML Rendition)

## The rejected concept
Generating a multi-page static website from a Workspace — index pages, per-Note routes, navigation chrome, asset pipelines, incremental rebuilds — as the publishing story.

## Why it was considered
Publishing a knowledge base to the web naturally suggests a site, and multi-page output is the conventional shape for one.

## Why it was rejected
1. **It is a product wearing an export's clothing.** A site generator brings templating, URL design, rebuild machinery, and its own failure modes — a second product to maintain alongside the first.
2. **The single-file rendition already serves the reader.** CAP-PORT-04 follows the shape the format's own reference tooling demonstrates: one self-contained HTML file, Links navigable inside it, hostable anywhere or readable from disk. For sharing what I wrote with someone, that is the need.
3. **Scope discipline.** "Export" otherwise accretes a rendering engine invisibly, one plausible-sounding feature at a time.

## What replaced it
CAP-PORT-04. One file, offline-readable, no external scripts, no load-time network calls — Zero Content Telemetry applies absolutely to published output.

## Conditions that would reopen this
A deliberate product decision to serve public, audience-facing publishing of Workspaces as a goal in itself. That needs its own requirements pass; it will not grow out of the export epic.
