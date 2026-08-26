# Glossary

| Term | Definition | Do not use |
| :--- | :--- | :--- |
| Writer | The primary person who creates, organizes, and synchronizes knowledge through burlmd. | User (when the Writer role is intended), Author, Customer |
| Agent | An automated guest that the Writer authorizes to read or write Workspace files. burlmd remains the authority for Workspace semantics. | Authority, Owner, Automated Consumer |
| Platform | The host operating system and filesystem that own window chrome, process lifecycle, secure storage, and installation behavior. | OS Emulator, Chrome Theme |
| Note | A single unit of knowledge that the Writer creates and edits as Markdown. | Page, Document, File, Concept |
| Directory | A hierarchical container used to logically group and organize Notes. | Folder, Collection |
| Link | A lateral connection from one Note to another, forming the knowledge graph structure. | Backlink (as a synonym for Link), Reference, Tag, Wikilink |
| Workspace | The root container holding all Notes and Directories. It is local by default and may optionally be connected to a Remote. | Vault, Brain, Repo, Database |
| Remote | The user's private hosted repository that a connected Workspace synchronizes with. A Workspace remains fully functional without a Remote. | Server, Backend, Cloud, Origin |
| Provider | An external service through which the Writer authorizes, selects, provisions, and uses a Remote. | Remote, Host, Backend |
| Suggestion | A persistent inline decision for resolving a concurrent content change without exposing raw conflict markers. | Conflict (as a synonym for Suggestion), Merge, Diff, Fork |
| Lifecycle Decision | A required user choice that resolves a conflicting add, delete, rename, move, Directory, type, or path-identity outcome. Delete-versus-edit remains a Suggestion instead. | Structural conflict (as a synonym), File conflict, Suggestion |
| Asset Decision | A required user choice that resolves conflicting asset bytes, references, or availability. | Binary conflict, Attachment conflict, Suggestion |
| Block | A structural element within a Note, such as a paragraph, list item, or heading. | Node, Segment, Element |
| Live Preview | The editing model in which the focused Block displays its raw Markdown source while every other Block renders formatted. | WYSIWYG, Rich text mode, Hybrid editor, Source mode |
| Open Knowledge Format | The published open contract that every burlmd-created Note satisfies and against which burlmd validates adopted or guest-written content. Abbreviated OKF. | Our format, Custom format, OKF-like, OKF-inspired |
| Export | Producing a copy of the Workspace readable with no application-specific tooling. | Backup, Dump, Download |
| Bundle Archive | A single-file `.okf` zip archive of an entire Workspace bundle, in the packaged distribution form the Open Knowledge Format itself names. | Package, Backup (use Export), Container |
| Consolidation | The guided, one-time migration of non-conflicting Notes from a previous local Workspace into a freshly connected one, with explicit resolution of every identity collision. | Merge, Migration, Import (as a synonym) |
| Diagnostics Export | A user-produced export describing recent application behavior — errors, retries, failures — with Note content excluded. | Log dump, Crash report, Telemetry |
| Version | A recoverable past state of one Note in local history. | Revision, Snapshot, Backup |
| Asset | User-visible non-Note content that a Note references, such as an image. | Attachment, Blob, Object |
| Object | Immutable asset bytes identified by their content. An Asset refers to one Object at a time. | Asset, Attachment, File |
| Local Asset Store | The Workspace area that keeps active Object bytes available through portable paths for offline use and guest tools. | Local Object Store, Asset Cache, Attachment Directory |
| Object Store | User-controlled remote storage that synchronizes Object bytes for a connected Workspace. | Remote, Cloud, Bucket, Backend |
| Protected State | Current or historical Workspace state whose reachable Objects burlmd must retain. | Retained History, Live Set, Cache Root |
