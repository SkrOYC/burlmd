# Out of Scope: Telemetry Upload

**Status:** Rejected
**Related:** Zero Content Telemetry constraint (`constraints.md`), CAP-SUP-01 (Diagnostics Export)

## The rejected concept
Collecting and uploading usage metrics or error reports from installed applications to a project-operated endpoint — even behind an explicit opt-in consent step.

## Why it was considered
Telemetry is how most products learn what breaks in the field. Without any upload path, the project depends entirely on users choosing to run diagnostics and report problems.

## Why it was rejected
1. **The product's premise is sovereignty.** A tool whose pitch is "your Notes never pass through anyone's servers" starts every relationship with a consent dialog at odds with its own vision, however honest the consent is.
2. **Metadata is content-adjacent here.** Note counts, workspace sizes, feature timings, and error signatures sketch a portrait of someone's thinking life. Every collected byte would need re-litigating against the privacy constraint forever.
3. **A supported alternative exists.** CAP-SUP-01 produces a redacted diagnostics bundle on demand, containing errors and failures with Note content excluded. It answers the question telemetry answers — what broke, for whom, how often is lost — without any standing collection.

## What replaced it
CAP-SUP-01. Users who hit a problem produce and share diagnostics deliberately.

## Conditions that would reopen this
None foreseen while the product remains local-first. A hosted or team offering would reopen the whole privacy posture, not this entry alone.
