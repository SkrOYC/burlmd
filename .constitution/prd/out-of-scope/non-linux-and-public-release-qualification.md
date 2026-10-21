---
decision: deferred
date: 2026-10-14
ruling: reports/2026-10-14-interview-tasks.md
revisit_when: "The roadmap begins P2 macOS support or the user explicitly resumes packaged public-release delivery."
---

# Non-Linux and public-release qualification

## Context

The first usable milestone serves one Writer on Linux and runs locally from a checkout. Private development uses repository checks and isolated headless workflows on that machine. The product retains longer-term public `0.x` release commitments for Linux and macOS.

## Decision

Defer packaging, publication, hosted release gates, and supported-platform claims from the private Linux and synchronization milestones. macOS support and qualification become eligible for planning after P1, with no required ordering relative to the P2 Markdown increment and no public-packaging prerequisite.

## Reason

The sole Writer needs a dependable local Linux path before spending time on packaging, public delivery, or qualification of other platforms.

## Consequences

The private Linux milestones don't produce a package, publish an artifact, or make a supported-platform claim. Local Linux data-safety evidence supports private use only. It doesn't pass CAP-075 through CAP-077, CAP-079, CAP-080, CAP-104, CAP-105, NFC-34, NFC-37, or NFC-39. The replacement near-term roadmap must not create implementation tickets for the public-release outcomes. CAP-104 and CAP-105 can receive detailed planning when the roadmap reaches P2 macOS support.

Cross-platform Workspace format and path portability remain requirements. This deferral does not permit data loss, Linux-only path identities, or a file format that prevents a Workspace from moving to a supported platform.

CAP-078 and NFC-36 remain active migration safety for private use and upgrades. The public-release capabilities, release safety requirements, and hosted-gate integrity commitments remain product scope. Public packaging reopens when the user resumes that delivery outcome; macOS runtime support reopens independently when P2 planning begins.
