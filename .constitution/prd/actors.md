# Actors

## Primary Actor: Markdown-Literate Knowledge Worker
- **Role Name:** Writer
- **Operating Context:** Works primarily at a desktop, with an expectation of eventual multi-device access. Frequently transitions between connected and disconnected states. Already writes Markdown fluently and habitually, often in more than one tool, and is comfortable with version control as a concept even when unwilling to perform merges by hand.
- **Concrete Goals:**
  - Write Markdown directly, seeing the real source of whatever they are currently editing.
  - Read a Note as a finished document without switching into a separate preview mode.
  - Begin writing immediately on a new machine, with no account and no network.
  - Maintain a reliable, organized, searchable archive of their thoughts.
  - Keep Notes synchronized across their devices without manual intervention.
  - Retain files that remain fully usable if this application disappears tomorrow.
- **User Frictions:**
  - Editors that hide Markdown syntax behind a formatted-only surface, making it unclear what is actually stored.
  - Tools that silently reformat or normalize parts of a file the user did not touch, producing noisy version history.
  - Applications that require an account, a network round trip, or a provider connection before the first word can be written.
  - Sync conflicts that surface as raw conflict markers demanding manual repair, or that resolve by duplicating files.
  - Proprietary storage formats that make leaving the product expensive, and the longevity risk of cloud-only vendors.

## Secondary Actor: Automated Consumer
- **Role Name:** Agent
- **Operating Context:** A tool, script, or AI agent granted read (and occasionally write) access to the Workspace directory on disk, operating independently of the application and often while it is not running.
- **Concrete Goals:**
  - Read and traverse the Workspace's knowledge graph using a published specification rather than reverse-engineered conventions.
  - Resolve a Link to its target Note without application-specific parsing.
  - Add or amend Notes in place, and have those changes recognized by the application on next open.
- **User Frictions:**
  - Bespoke or undocumented on-disk conventions that require a custom parser per application.
  - Knowledge locked behind an export step, an API, or a running process.
  - Link syntaxes that are not resolvable by standard Markdown tooling.
