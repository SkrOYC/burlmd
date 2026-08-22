# Non-Functional Constraints

Scalar constraints use Planguage fields: **Scale** (what is measured), **Meter** (how), **Goal** (target to hit), **Stretch** (optional better target), **Fail** (level that makes the design unacceptable). Constraints without an honest meter stay prose and say so.

## Performance

- **Search Latency**
  - **Scale:** Time from submitting a full-text search or title-filter query to receiving results.
  - **Meter:** Benchmark query set executed against the index at the Corpus Scale Goal below.
  - **Goal:** Under 100 milliseconds.
  - **Stretch:** Under 25 milliseconds.
  - **Fail:** Over 250 milliseconds, or any growth curve that reaches 100 milliseconds before the Corpus Scale Fail point.

- **UI Responsiveness**
  - **Scale:** Frame time of writing and editing interactions, including the transition of a Block into and out of its raw editing state.
  - **Meter:** Frame timing captured over a scripted editing session spanning Block types, splices, and range operations.
  - **Goal:** Every interaction within the 16-millisecond budget (60fps).
  - **Stretch:** Headroom such that whole-file reparses at the ADR-measured sizes never approach the budget.
  - **Fail:** Any discrete editing action regularly dropping frames on Notes within ordinary length.

- **Workspace Open Latency**
  - **Scale:** Time from launch request to an interactable shell with the Workspace open.
  - **Meter:** Timed opens across corpora at the Corpus Scale Goal.
  - **Goal:** No more than 1 second regardless of Note count. Index construction beyond that proceeds incrementally in the background while the Workspace is usable.
  - **Stretch:** Sub-second open at the Corpus Scale Stretch.
  - **Fail:** Open blocking longer than 3 seconds at the Corpus Scale Goal.

- **Cold Start**
  - **Scale:** Time from process launch to the interactive shell, cold — no warm caches assumed.
  - **Meter:** Timed launches on reference hardware after process start, covering runtime initialization, keychain access, and encrypted-index open.
  - **Goal:** 1 second.
  - **Stretch:** 500 milliseconds.
  - **Fail:** 3 seconds. The Goal is deliberately aggressive, chosen by operator intent to force optimization rather than neglect; if first measurement lands above it, rebaseline explicitly through this file rather than silently accepting.

- **Idle Memory**
  - **Scale:** Resident memory at rest, after opening a Workspace at the Corpus Scale Goal and letting activity settle.
  - **Meter:** Operating-system process metrics on reference hardware.
  - **Goal:** 400 MB.
  - **Stretch:** 250 MB.
  - **Fail:** 1 GB, or unbounded growth over a multi-hour session.

## Scale & Capacity

- **Corpus Scale**
  - **Scale:** Number of Notes in the Workspace over which every other meter in this file must hold.
  - **Meter:** Synthetic corpora at each level, exercising search, tree building, open, and indexing.
  - **Goal:** 10,000 Notes.
  - **Stretch:** 50,000 Notes.
  - **Fail:** 1,000 Notes. Below the Fail point, any missed meter is a defect rather than a scaling story.

## Synchronization Freshness

- **Sync Latency While Connected**
  - **Scale:** Time from a local commit landing in version history to its publication on the Remote, while online and authorized.
  - **Meter:** End-to-end timed pushes on a live connection.
  - **Goal:** Within 60 seconds.
  - **Stretch:** Within 15 seconds.
  - **Fail:** Beyond 15 minutes while the connection is healthy.

- **Remote Poll Cadence**
  - **Scale:** How often the Remote is checked for upstream changes while online.
  - **Meter:** Interval instrumentation of the background scheduler.
  - **Goal:** Every 60 seconds, backing off when offline with a ceiling of 15 minutes between attempts.
  - **Fail:** An offline backoff ceiling beyond one hour, or polling that stops entirely while authorization remains valid.

## Reliability
- **Local-First Mandate:** The application must be 100% functional when completely disconnected from the internet, and must never require an account, credential, or provider authorization in order to create, read, edit, search, or organize Notes. Reads, writes, searches, and Link traversals must all resolve locally.
- **Non-Blocking Sync:** Background synchronization must never block the main UI thread or interrupt the user's editing flow. Reconciliation is included: unresolved Suggestions never gate commits, pushes, or any editing capability, and may flow through version history until resolved. The ambient synchronization state distinguishes "pending Suggestions" from clean.
- **Durability of In-Progress Work:** Edits not yet written to a Note must survive abrupt process termination, including termination the application receives no opportunity to handle.

## Correctness & Fidelity
- **Edit Fidelity:** Writing a Note to disk must not alter any region of that Note the user did not edit. A session that modifies one Block must produce a change confined to that Block's source, leaving all other bytes — including whitespace, delimiter style, and any metadata keys the application does not itself manage — byte-identical.
- **Format Conformance:** Every Note the application **creates** satisfies the Open Knowledge Format's conformance rules from the moment it is created, not only at Export time, and no operation the application performs makes a conformant Note non-conformant. Stated as *creates* rather than *writes* because the two differ in a case the design explicitly supports: under CAP-WS-05 and CAP-PORT-03 a user may open a Workspace another tool wrote and edit a file that has no frontmatter, and the application will write that file while it remains non-conformant. Repairing it is an explicit user action, never automatic, because prepending a frontmatter block writes bytes outside the edited Block's span, which Edit Fidelity forbids.
- **Non-Destructive Reconciliation:** Reconciling concurrent edits must never discard either side's content or duplicate a Note. Both variants must remain recoverable until the user resolves the Suggestion.

## Security & Sovereignty
- **Decentralized Storage:** Note content is stored exclusively on the user's own device and, when connected, in the user's designated Remote. No component operated by this project may act as a storage broker, relay, or intermediary for Note content.
- **At-Rest Protection (Local):** Notes are written to disk as plaintext, deliberately, so that standard version-control tooling can operate on them directly. Their at-rest protection is therefore **whatever full-disk encryption the user's operating system provides, which on the primary desktop target is an install-time choice rather than a platform guarantee** — the application does not and cannot assure it. This is an accepted limitation of the plaintext trade-off, not a protection the system delivers. What the application *does* guarantee is narrower and unconditional: the local search index, which aggregates the content of every Note into one file, must be encrypted by the application independently of the operating system, and its key must reside in operating-system secure storage rather than in application memory or configuration.
- **Credential Isolation:** Provider credentials must never be persisted outside operating-system secure storage, and must never be written to logs, diagnostics, or version history.
- **Non-Proprietary Storage:** Every Note must remain a plain-text file in a published, openly specified format, fully readable and editable with any text editor and with no tooling produced by this project.

## Privacy
- **Zero Content Telemetry:** The application must not collect, transmit, or analyze the contents of the user's Notes for analytics, telemetry, or diagnostic purposes.

## Verification

Every scalar meter above is verified by a scheduled nightly benchmark run once continuous integration exists, reporting regressions without blocking merges; until then they are verified ticket-by-ticket when work touches their path. A meter nobody measures again after the spike that first reads it will drift silently — this project has already shipped one persistence-cost assumption that measurement proved wrong by roughly 36× against what a naive benchmark reported (recorded in `tech-spec/changelog.md` v1.2.0).
