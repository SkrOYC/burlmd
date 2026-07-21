# Architectural Blueprint: Git-Backed Local-First Note-Taking Application

## 1. Executive Summary & Philosophy
This application is designed as a high-performance, local-first note-taking ecosystem that enforces data sovereignty and transparency. By choosing Git as the storage and versioning engine, the system eliminates platform lock-in. If the application layer disappears, the user is left with a clean, fully portable directory of standard Markdown files and an intact cryptographic history of their thoughts. The architecture implements a strict separation of concerns, decoupling the user interface from state management and data storage.

## 2. Core Technical Architecture
*   **The UI Layer (Presentation & Interaction):** A strictly layered, declarative multiplatform interface (Flutter). This layer focuses entirely on projecting state to the user and capturing input, remaining devoid of business logic. 
*   **The FFI Boundary (The Bridge):** A zero-overhead, shared-memory interface connecting the frontend to the core.
*   **The Core Engine (Rust):** Compiled to native targets from a unified Rust codebase. It encapsulates the local SQLite index, markdown parsing, and low-level Git plumbing.
*   **The Storage Target:** A private GitHub repository acting as a reliable, highly available central coordinator.

## 3. Data Boundary & Serialization
Because the system will support complex graph relationships between notes, the FFI boundary relies on strict data contracts to maintain state integrity.
*   **Granular Serialization:** Raw Markdown strings are not blindly passed back and forth. The Rust engine parses the documents and graph relationships into strictly typed Abstract Syntax Trees (AST) or node-and-edge structures.
*   **Automated Data Models:** These structures are rigorously serialized (e.g., via JSON) across the bridge. The presentation layer consumes predictable model classes with exact properties, ensuring the UI interacts with structured data.

## 4. State Management & The Sync Loop
To avoid developer-facing frictions, synchronization operates as an ambient background process.
*   **Event-Driven Synchronization:** Every user action is logged as a discrete event rather than directly overwriting data. 
*   **Single Source of Truth:** The local database acts as the single source of truth for the active session. 
*   **Optimistic UI Updates:** Because writes occur instantly on the client, changes are reflected immediately in the interface without waiting for the background engine to complete the remote Git push.
*   **Reactive Subscriptions:** The frontend listens to a continuous stream of events from the core engine. When the background loop successfully fetches and merges upstream changes, the interface reacts to these state emissions and updates the affected components.

## 5. Spatial Layout & Routing 
The presentation layer adapts its layout dynamically based on the device format.
*   **Responsive Information Density:** On desktop environments, it expands into a dense, multi-pane architecture tailored for simultaneous graph visualization. On mobile, it condenses into a focused view optimized for smaller screens.
*   **Declarative Path-Based Routing:** Every note, block, and graph segment is addressable. A declarative routing structure manages complex view states, enabling users to navigate directly to a targeted node via internal links or system-level searches.

## 6. Programmatic Conflict Resolution
Traditional Git relies on human intervention to resolve merge conflicts, outputting standard text diff markers that ruin file parsing. To make sync invisible, the core handles text reconciliation at the application layer before Git flags a fatal merge block.
*   **Isolated Branching Topology:** Each authorized device is allocated its own persistent, isolated branch in the remote repository (e.g., `device-macbook`, `device-iphone`). Because every device owns its dedicated branch on the remote, pushes are always non-blocking and never rejected for fast-forward failures.
*   **Visual Diffing Interface:** If concurrent updates occur on the exact same block or line, the system avoids throwing an error. Instead, it preserves both blocks as a deterministic fork and pushes them to the UI layer.
*   **Contextual Reconciliation:** The user is presented with a clear visual diff (side-by-side on desktop, or top-to-bottom on mobile). This allows the user to select the preferred wording in context without breaking the text file format.

