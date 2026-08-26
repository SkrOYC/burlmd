# Actors

## Markdown-literate knowledge worker

- **Role name:** Writer
- **Operating context:** Works primarily on a desktop and expects multi-device access. Moves between connected and disconnected states. Writes Markdown fluently, often in more than one tool. Understands version control but doesn't want to perform merges by hand.
- **Concrete goals:**
  - Write Markdown directly, seeing the real source of whatever they are currently editing.
  - Read a Note as a finished document without switching into a separate preview mode.
  - Begin writing immediately on a new machine, with no account and no network.
  - Maintain a reliable, organized, searchable archive of their thoughts.
  - Keep Notes synchronized across their devices without manual intervention.
  - Retain files that remain fully usable if this application disappears tomorrow.
- **User frictions:**
  - Editors that hide Markdown syntax behind a formatted-only surface, making it unclear what is actually stored.
  - Tools that silently reformat or normalize parts of a file the user did not touch, producing noisy version history.
  - Applications that require an account, a network round trip, or a provider connection before the first word can be written.
  - Sync conflicts that surface as raw conflict markers demanding manual repair, or that resolve by duplicating files.
  - Proprietary storage formats that make leaving the product expensive, and the longevity risk of cloud-only vendors.

## Automated consumer

- **Role name:** Agent
- **Operating context:** Uses read or write access that the Writer grants to the Workspace on disk. Operates independently and can act while burlmd is open. The Agent is a guest. burlmd remains the authority for Workspace semantics and conformance.
- **Concrete goals:**
  - Read and traverse the Workspace's knowledge graph using a published specification rather than reverse-engineered conventions.
  - Resolve a Link to its target Note without application-specific parsing.
  - Add or amend Notes in place and have burlmd reconcile the changes without silent data loss.
- **User frictions:**
  - Bespoke or undocumented on-disk conventions that require a custom parser per application.
  - Knowledge locked behind an export step, an API, or a running process.
  - Link syntaxes that are not resolvable by standard Markdown tooling.
  - Ambiguous rules for valid paths, assets, and concurrent writes.

## Host operating system

- **Role name:** Platform
- **Operating context:** Owns window chrome, filesystem behavior, secure credential storage, process lifecycle, and application installation on a supported desktop system.
- **Concrete goals:**
  - Present the application's window through platform-owned chrome.
  - Enforce filesystem and credential-store rules without application-specific emulation.
  - Stop or restart the process without corrupting durable Workspace state.
- **User frictions:**
  - Application behavior that assumes one filesystem's case, path, or normalization rules.
  - Fake platform controls that conflict with the host window.
  - Release artifacts that don't match the host architecture or runtime baseline.
