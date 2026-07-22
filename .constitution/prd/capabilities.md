# Functional Capabilities

## Epic: Core Editing & Formatting
- **Priority:** P0
- **Capability:** Users can format text inline (bold, italic, strikethrough, code) using standard keyboard shortcuts or a floating toolbar without seeing raw Markdown asterisks/backticks.
- **Rationale:** Delivers the expected Notion-like rich text experience.
- **Priority:** P0
- **Capability:** Users can structure content using diverse block types: Headings (H1-H6), Bulleted/Numbered Lists, Blockquotes, and Code Blocks.
- **Rationale:** Foundational elements for knowledge organization.
- **Priority:** P1
- **Capability:** Users can embed and preview images locally.
- **Rationale:** Visual knowledge capture is essential for general consumers.

## Epic: Knowledge Graph & Navigation
- **Priority:** P0
- **Capability:** Users can organize Notes into nested Directories.
- **Rationale:** Primary hierarchical navigation paradigm.
- **Priority:** P1
- **Capability:** Users can insert Links between Notes (typing `[[` or via UI) to construct a knowledge graph.
- **Rationale:** Enables lateral exploration of ideas and concepts.

## Epic: Seamless Synchronization & Security
- **Priority:** P0
- **Capability:** Users can authenticate via an OAuth provider (e.g., GitHub, GitLab) to automatically provision or connect their Workspace.
- **Rationale:** Removes the friction of manual Git setup.
- **Priority:** P0
- **Capability:** The system continuously and automatically syncs changes across devices in the background.
- **Rationale:** Ensures data is always up-to-date.
- **Priority:** P0
- **Capability:** All local data is protected at rest: Notes on disk are protected via OS-level Full Disk Encryption, and the SQLite search index is additionally encrypted at the application level (SQLCipher), with the decryption key stored securely in the OS-level Keychain/Keystore.
- **Rationale:** Ensures high data privacy if the physical device is compromised.
- **Priority:** P1
- **Capability:** The system surfaces concurrent offline edits as inline Suggestions for the user to accept or reject.
- **Rationale:** Abstracts away intimidating Git merge conflicts into a collaborative flow.

## Epic: Discovery & Retrieval
- **Priority:** P0
- **Capability:** Users can instantly search across all Notes in their Workspace.
- **Rationale:** Essential for retrieving knowledge quickly as volume scales.
- **Priority:** P2
- **Capability:** Users can visualize the relationships between their Notes through a graphical map.
- **Rationale:** Helps users understand the macro-structure of their knowledge graph.
