# Execution Flow: Workspace Export

**Maps to PRD Capability:** CAP-PORT-02 (Export the Workspace as a plain bundle copy or a single `.okf` Bundle Archive, readable with no application-specific tooling).

```mermaid
sequenceDiagram
    participant UI as Presentation Container
    participant Core as Core Engine
    participant Local as Local Repository
    participant FS as Destination (user-chosen)

    UI->>Core: Export (destination, form: copy | archive)
    Core->>Local: Read bundle tree (version history excluded)

    alt Plain copy
        Core->>FS: Write every Note, Directory and Attachment verbatim
    else Bundle Archive
        Core->>FS: Write one .okf archive of the same tree
    end

    Core->>Core: Conformance check over what was written
    Core-->>UI: Result — including any non-conformant Notes found

    Note over UI,FS: The conformance check reports; it never gates. Refusing to hand users their own data would invert the capability's purpose.
```

## Design notes

- **Cheap by construction, for the right reason.** The copy is cheap because the live Workspace is plaintext at all times — not because it is guaranteed conformant. CAP-PORT-01 scopes conformance to Notes this application creates, and foreign files are exported exactly as their author wrote them.
- **Version history is excluded by default.** Export answers "take my Notes elsewhere"; the Git history belongs to the local repository and is not part of the format's bundle.
- **The `.okf` archive is the packaged distribution form the Open Knowledge Format itself names** (§3): a zip of the directory, nothing proprietary inside.

## Failure path

- **Destination unwritable** (permissions, full disk, path occupied): fail with a destination-specific error before writing anything partial; a failed export leaves no half-written tree behind.
- **Read errors mid-copy** (a file vanished or became unreadable during the walk): report which paths could not be exported rather than failing silently — partial output plus an explicit list is more honest than either aborting everything or pretending completeness.
- **Non-conformant content:** never blocks. The result names such Notes so the user knows what another tool will see; that is the whole obligation.
