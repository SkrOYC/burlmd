# Non-functional constraints

Scalar constraints use Planguage fields: **Scale** (what is measured), **Meter** (how), **Goal** (target to hit), **Stretch** (optional better target), **Fail** (level that makes the design unacceptable). Constraints without an honest meter stay prose and say so.

## Reference classes

Performance meters run in reproducible managed continuous-integration environments for both reference classes:

- **Linux x86-64 performance reference:** 4 logical CPUs and 16 GB of available memory.
- **Apple Silicon macOS performance and visual reference:** M1-class compute, 3 logical CPUs, and 7 GB of available memory on macOS 26.

Each run uses a fixed 1920x1080 logical viewport at 60 Hz. Before measurement, each run records the environment image identity, operating-system release, architecture, CPU allocation and model class, available memory, and storage characteristics. It also records the viewport, refresh rate, build identity, and corpus identity. Evidence without this identity is invalid.

The Goal corpus contains 10,000 Notes with a 4 KiB median, a 64 KiB 95th percentile, and a 1 MiB maximum Note. The scripted editing Note contains 2,000 Blocks across every supported syntax class and is 1 MiB before edits. The Technical Implementation stage must publish deterministic corpus generation and reference-class setup specifications.

Functional release gates run on every named supported system. macOS 15 is a release-blocking functional compatibility target only. It doesn't define a performance baseline or visual reference. Performance gates run on both reference classes. macOS 26 is the sole authoritative product visual reference. Linux also requires exact zero-pixel platform-regression evidence from its isolated environment, but that implementation-specific gate isn't a product visual reference and can't substitute for macOS 26 visual evidence.

## Performance

- **Search Latency**
  - **Scale:** Time from submitting a full-text search or title-filter query to receiving results.
  - **Meter:** The 95th percentile over 1,000 deterministic queries against the Goal corpus on each reference class.
  - **Goal:** Under 100 milliseconds.
  - **Stretch:** Under 25 milliseconds.
  - **Fail:** Over 250 milliseconds at 10,000 Notes, or over 100 milliseconds at 1,000 Notes.

- **UI Responsiveness**
  - **Scale:** Frame time of writing and editing interactions, including the transition of a Block into and out of its raw editing state.
  - **Meter:** Frame timing over a 5-minute scripted session on the editing Note and each reference class.
  - **Goal:** At least 99% of frames complete within 16.7 milliseconds, with no input-to-effect delay above 50 milliseconds.
  - **Stretch:** At least 99.9% of frames complete within 16.7 milliseconds.
  - **Fail:** More than 1% of frames exceed 33.3 milliseconds or any input-to-effect delay exceeds 100 milliseconds.

- **Workspace Open Latency**
  - **Scale:** Time from launch request to an interactable shell with the Workspace open.
  - **Meter:** The 95th percentile of 20 opens of the Goal corpus on each reference class.
  - **Goal:** No more than 1 second at the Corpus Scale Goal. Remaining index construction proceeds without blocking Workspace use.
  - **Stretch:** No more than 1 second at the Corpus Scale Stretch.
  - **Fail:** Open blocking longer than 3 seconds at the Corpus Scale Goal.

- **Cold Start**
  - **Scale:** Time from process launch to the interactive shell, cold — no warm caches assumed.
  - **Meter:** The 95th percentile of 20 cold launches on each reference class, including secure-storage and encrypted-index access.
  - **Goal:** 1 second.
  - **Stretch:** 500 milliseconds.
  - **Fail:** 3 seconds. The Goal is deliberately aggressive, chosen by operator intent to force optimization rather than neglect; if first measurement lands above it, rebaseline explicitly through this file rather than silently accepting.

- **Idle Memory**
  - **Scale:** Resident memory at rest, after opening a Workspace at the Corpus Scale Goal and letting activity settle.
  - **Meter:** Resident memory sampled each second for 10 minutes after a 5-minute settling period on each reference class.
  - **Goal:** 400 MB.
  - **Stretch:** 250 MB.
  - **Fail:** 1 GB, or growth above 5% during a 4-hour idle run after the settling period.

- **External Change Detection**
  - **Scale:** Time from a guest filesystem change to a visible reconciled state or required Writer decision while the Workspace is open.
  - **Meter:** Timed create, edit, rename, move, and delete operations on supported filesystems, including burst writes.
  - **Goal:** Within 2 seconds after the final write in a burst.
  - **Stretch:** Within 500 milliseconds after the final write in a burst.
  - **Fail:** More than 10 seconds, a missed event, or duplicate history from one burst.

## Scale and capacity

- **Corpus Scale**
  - **Scale:** Number of Notes in the Workspace over which every other meter in this file must hold.
  - **Meter:** Synthetic corpora at each level, exercising search, tree building, open, and indexing.
  - **Goal:** 10,000 Notes.
  - **Stretch:** 50,000 Notes.
  - **Fail:** 1,000 Notes. Below the Fail point, any missed meter is a defect rather than a scaling story.

- **Image Import Size**
  - **Scale:** Encoded bytes in one imported image.
  - **Meter:** Import, decode, local persistence, and second-device hydration across representative image dimensions and formats.
  - **Goal:** Accept and use images up to the provisional 25 MiB limit without violating the UI Responsiveness or Idle Memory goals.
  - **Stretch:** The asset Spike can recommend a larger limit when every dependent meter remains within its Goal.
  - **Fail:** Accepting an image above the supported limit without an explicit refusal, or violating another Fail threshold below the limit.

- **History Storage Health Warning**
  - **Scale:** Stored textual and manifest history in the local Version store.
  - **Meter:** Storage size, second-device bootstrap time, synchronization retrieval time, maintenance cost, and index cost at the Corpus Scale Goal.
  - **Goal:** Warn the Writer before the history store reaches the provisional 1 GiB threshold.
  - **Stretch:** The asset or performance Spike can recommend an evidence-based threshold that warns before user-visible degradation.
  - **Fail:** No warning at the accepted threshold or a threshold that another PRD Fail meter disproves.

## Synchronization freshness

- **Sync Latency While Connected**
  - **Scale:** Time from a local Version landing in history to its publication on the Remote, while online and authorized.
  - **Meter:** End-to-end timed pushes on a live connection.
  - **Goal:** Within 60 seconds.
  - **Stretch:** Within 15 seconds.
  - **Fail:** Beyond 15 minutes while the connection is healthy.

- **Remote Change Freshness**
  - **Scale:** Time from an incoming Remote change becoming available to burlmd presenting or applying that change while online and authorized.
  - **Meter:** End-to-end observation across 100 incoming changes and reconnection after 1 hour offline.
  - **Goal:** Within 60 seconds while connected and within 60 seconds after connectivity returns.
  - **Stretch:** Within 15 seconds while connected.
  - **Fail:** Beyond 15 minutes while connected or beyond 1 hour after connectivity returns.

## Reliability
- **Local-First Mandate:** The application must be 100% functional when completely disconnected from the internet, and must never require an account, credential, or Provider authorization in order to create, read, edit, search, or organize Notes. Reads, writes, searches, and Link traversals must all resolve locally.
- **Non-Blocking Sync:** Background synchronization must never block the main UI thread or interrupt editing. Unresolved Suggestions don't gate commits or pushes after burlmd records a valid reconciled state. A pending Lifecycle Decision or Asset Decision pauses Workspace synchronization but doesn't block local editing or history.
- **Durability of In-Progress Work:** Edits not yet written to a Note must survive abrupt process termination, including termination the application receives no opportunity to handle.
- **Orderly Session Closure:** Every orderly tab close, Workspace switch, and application exit must run the Note durability and history lifecycle. A partial batch close must report which Notes closed and preserve every unprocessed session.
- **Recoverable Reconciliation:** After a crash or local branch advance, burlmd must recover recorded reconciliation inputs, reject stale tentative outcomes, and preserve every local and incoming state.
- **Object Availability:** A connected Workspace must not publish Note history that references an Object until that Object is verified in the configured Object Store.

## Correctness & Fidelity
- **Edit Fidelity:** Writing a Note to disk must not alter any region of that Note the user did not edit. A session that modifies one Block must produce a change confined to that Block's source, leaving all other bytes — including whitespace, delimiter style, and any metadata keys the application does not itself manage — byte-identical.
- **Format Conformance:** Every Note that burlmd creates satisfies the Open Knowledge Format from creation, and no burlmd operation makes a conformant Note nonconformant. An invalid guest Note remains outside authoritative Workspace state and isn't editable until the Writer accepts a previewed repair that makes it conformant. Exclusion preserves the original bytes without admitting the Note.
- **Non-Destructive Reconciliation:** Reconciling concurrent edits must never discard either side's content or duplicate a Note. Both variants must remain recoverable until the user resolves the Suggestion.
- **Guest Authority Boundary:** burlmd must validate guest filesystem writes before they enter authoritative Workspace state. Invalid input must not replace the last known-good Note or trigger silent repair.
- **Cross-Platform Path Identity:** A path that burlmd creates must retain one identity under supported Linux and macOS filesystems and Windows-compatible path rules. Case, Unicode normalization, reserved names, and trailing characters must not create an ambiguous second identity.
- **Object Integrity:** burlmd must verify Object bytes against their content identity before exposing, publishing, migrating, restoring, or deleting them.
- **Protected History:** burlmd must retain every Object reachable from a Protected State, including current Workspace state, all retained or unpublished local history, all reachable published Remote history, pending reconciliation, and Consolidation. During `0.x`, burlmd must not delete authoritative Object Store bytes; only verified local cache copies can be evicted.
- **Workspace Containment:** Workspace-controlled paths and indirections must never grant access outside the Workspace boundary. burlmd must reject unsupported filesystem aliases or nested external repositories during adoption, monitoring, and synchronization.

## Security and sovereignty
- **Decentralized Storage:** Note content is stored exclusively on the user's own device and, when connected, in the user's designated Remote. No component operated by this project may act as a storage broker, relay, or intermediary for Note content.
- **At-Rest Protection (Local):** Notes remain plaintext so standard tools can operate on them. The Platform's storage protection is a user-controlled installation choice that burlmd can't guarantee. burlmd must encrypt the aggregate search index independently. Persistent key material must exist only in Platform secure storage. burlmd can use narrowly scoped transient key material in memory and must zeroize it promptly after use.
- **Credential Isolation:** Remote and Object Store credentials must never be persisted outside operating-system secure storage, and must never be written to logs, diagnostics, or version history.
- **Non-Proprietary Storage:** Every Note must remain a plain-text file in a published, openly specified format, fully readable and editable with any text editor and with no tooling produced by this project.
- **Private Remote Boundary:** A connected Remote must remain private. burlmd must pause synchronization if the Remote becomes public or if required access is lost.
- **Remote Automation Boundary:** burlmd must not request GitHub workflow-modification authority or publish a commit reachable from a local publication ref when that commit contains `.github/workflows/**`. Local Workspace access remains available. Remote preflight or synchronization must stop and offer Consolidation into a clean Workspace.
- **Private Object Store Boundary:** burlmd must refuse or pause an Object Store when anonymous list, read, write, or delete access is detected, or when the complete storage-privacy result is missing or stale.

## Privacy
- **Zero Automatic Off-Device Telemetry:** burlmd may record bounded structured diagnostics locally so the Writer can inspect product health, but it must not automatically transmit usage metrics, errors, diagnostics, Note content, Asset content, signed locations, or content-derived metadata. Local diagnostics must exclude content, credentials, signed locations, and content-derived telemetry. A Writer-created and Writer-shared Diagnostics Export is the only product reporting path.

## Release support

- **Feature Parity:** Every supported release system must pass the same release-blocking capability matrix. A launch-only check isn't sufficient.
- **Version Policy:** Releases remain in the `0.x` series until the user explicitly declares stability. Downgrade compatibility isn't guaranteed.
- **Migration Safety:** Application-state migrations must create a backup, apply atomically, and restore the earlier state after failure. Migrations must not rewrite Note content unless an explicit product operation requires it.

## Verification

Every scalar meter above is verified in each applicable reference class by scheduled nightly benchmark runs in managed continuous integration. The runs report regressions without blocking merges and capture the required environment identity. A meter that isn't measured after its first spike drifts silently. This project has shipped a persistence-cost assumption that measurement disproved by roughly 36×. `tech-spec/changelog.md` v1.2.0 records the result.
