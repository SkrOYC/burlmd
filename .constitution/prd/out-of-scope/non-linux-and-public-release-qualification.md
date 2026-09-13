---
decision: deferred
date: 2026-09-13
ruling: "User message, 2026-09-13: \"Prioritize Linux, let's defer our focus on other platforms to avoid more time costs.\""
revisit_when: "The user explicitly resumes packaged, supported, or other-platform delivery during later roadmap planning."
---

# Non-Linux and public-release qualification

## Context

The first usable milestone serves one Writer on Linux and runs locally from a checkout. The product also retains a longer-term public `0.x` release scope for supported Linux and macOS artifacts.

## Decision

Defer public-release qualification and qualification outside local Linux for the private first-usable milestone.

## Reason

The sole Writer needs a dependable local Linux path before spending time on packaging, public delivery, or qualification of other platforms.

## Consequences

The milestone does not produce a package, publish an artifact, or make a supported-platform claim. Local Linux data-safety evidence supports private use only. It does not pass CAP-075, CAP-076, CAP-079, CAP-080, NFC-34, NFC-37, or NFC-39.

Cross-platform Workspace format and path portability remain requirements. This deferral does not permit data loss, Linux-only path identities, or a file format that prevents a Workspace from moving to a supported platform.

Reopening this decision requires Product Requirements Evolution after the user resumes packaged, supported, or other-platform delivery.
