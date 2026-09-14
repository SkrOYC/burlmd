//! Core-owned, presentation-only Workspace session snapshots.
//!
//! The JSON sidecar lives in application support, never in a Workspace, Git,
//! or the encrypted index. It records only small UI state; it cannot create a
//! Note session or become authority for Note content.

use std::collections::HashSet;
use std::fmt::Write as _;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest as _, Sha256};

use crate::error::AppError;
use crate::workspace::persist::Workspace;

const CURRENT_SCHEMA_VERSION: u32 = 1;

#[frb]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SessionSyncPresentation {
    Local,
    Connected,
    Paused,
}

/// The FFI shape excludes Core-selected `workspace_id` and `schema_version`.
#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActiveWorkspaceSessionSnapshot {
    pub open_note_ids: Vec<String>,
    pub active_note_id: Option<String>,
    pub expanded_directory_ids: Vec<String>,
    pub search_query: String,
    pub sync_presentation: SessionSyncPresentation,
}

impl Default for ActiveWorkspaceSessionSnapshot {
    fn default() -> Self {
        Self {
            open_note_ids: Vec::new(),
            active_note_id: None,
            expanded_directory_ids: Vec::new(),
            search_query: String::new(),
            sync_presentation: SessionSyncPresentation::Local,
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PersistedWorkspaceSessionSnapshot {
    schema_version: u32,
    workspace_id: String,
    open_note_ids: Vec<String>,
    // `Option` otherwise accepts a missing field as `None`; raw schema
    // validation below proves required-but-nullable presence before serde.
    active_note_id: Option<String>,
    expanded_directory_ids: Vec<String>,
    search_query: String,
    sync_presentation: SessionSyncPresentation,
}

impl PersistedWorkspaceSessionSnapshot {
    fn from_snapshot(workspace: &Workspace, snapshot: &ActiveWorkspaceSessionSnapshot) -> Self {
        Self {
            schema_version: CURRENT_SCHEMA_VERSION,
            workspace_id: workspace.id().to_string(),
            open_note_ids: snapshot.open_note_ids.clone(),
            active_note_id: snapshot.active_note_id.clone(),
            expanded_directory_ids: snapshot.expanded_directory_ids.clone(),
            search_query: snapshot.search_query.clone(),
            sync_presentation: snapshot.sync_presentation,
        }
    }

    fn into_snapshot(self) -> ActiveWorkspaceSessionSnapshot {
        ActiveWorkspaceSessionSnapshot {
            open_note_ids: self.open_note_ids,
            active_note_id: self.active_note_id,
            expanded_directory_ids: self.expanded_directory_ids,
            search_query: self.search_query,
            sync_presentation: self.sync_presentation,
        }
    }
}

/// Application-support persistence partitioned by a SHA-256 of the Core-owned
/// Workspace id. Hashing prevents an opaque id from becoming a filesystem path.
pub(crate) struct SessionSnapshotStore {
    root: PathBuf,
    next_quarantine_file: AtomicU64,
}

impl SessionSnapshotStore {
    pub(crate) fn application_support() -> Result<Self, AppError> {
        let root = crate::db::connection::xdg_data_home()?
            .join("burlmd")
            .join("workspace-session-snapshots");
        std::fs::create_dir_all(&root)
            .map_err(|error| io_error(&root, "create session snapshot directory", error))?;
        Ok(Self {
            root,
            next_quarantine_file: AtomicU64::new(0),
        })
    }

    #[cfg(test)]
    fn for_test(root: PathBuf) -> Self {
        Self {
            root,
            next_quarantine_file: AtomicU64::new(0),
        }
    }

    fn key(&self, workspace_id: &str) -> String {
        let digest = Sha256::digest(workspace_id.as_bytes());
        let mut key = String::with_capacity(digest.len() * 2);
        for byte in digest {
            write!(key, "{byte:02x}").expect("writing to String cannot fail");
        }
        key
    }

    fn snapshot_path(&self, workspace_id: &str) -> PathBuf {
        self.root.join(format!("{}.json", self.key(workspace_id)))
    }

    /// Durable guard which prevents the normal path from being recreated after
    /// unverified or newer-schema bytes were refused. BURL-O005 owns any
    /// future safe path.
    fn later_version_guard_path(&self, workspace_id: &str) -> PathBuf {
        self.root
            .join(format!("{}.later-version-refused", self.key(workspace_id)))
    }

    fn quarantine_path(&self, workspace_id: &str, reason: &str, sequence: u64) -> PathBuf {
        self.root.join(format!(
            "{}.{}.{}.{}",
            self.snapshot_path(workspace_id)
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or("workspace-session.json"),
            reason,
            std::process::id(),
            sequence,
        ))
    }

    pub(crate) fn load(
        &self,
        workspace: &Workspace,
    ) -> Result<ActiveWorkspaceSessionSnapshot, AppError> {
        let path = self.snapshot_path(workspace.id());
        let bytes = match std::fs::read(&path) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok(ActiveWorkspaceSessionSnapshot::default());
            }
            Err(error) => return Err(io_error(&path, "read session snapshot", error)),
        };

        let raw = match serde_json::from_slice::<Value>(&bytes) {
            Ok(raw) => raw,
            Err(_) => return self.quarantine_and_default(&path, workspace.id(), "corrupt", true),
        };
        match snapshot_version(&raw) {
            SnapshotVersion::Later => {
                return self.quarantine_and_default(&path, workspace.id(), "later", true);
            }
            SnapshotVersion::Unknown => {
                return self.quarantine_and_default(&path, workspace.id(), "unknown", true);
            }
            SnapshotVersion::Current => {}
        }

        let persisted = match parse_current_schema(raw) {
            Ok(snapshot) => snapshot,
            Err(()) => return self.quarantine_and_default(&path, workspace.id(), "invalid", false),
        };
        if validate_semantics(workspace, &persisted).is_err() {
            return self.quarantine_and_default(&path, workspace.id(), "invalid", false);
        }
        Ok(persisted.into_snapshot())
    }

    pub(crate) fn save(
        &self,
        workspace: &Workspace,
        snapshot: &ActiveWorkspaceSessionSnapshot,
    ) -> Result<(), AppError> {
        self.prepare_normal_path_write(workspace)?;
        std::fs::create_dir_all(&self.root)
            .map_err(|error| io_error(&self.root, "create session snapshot directory", error))?;
        let persisted = PersistedWorkspaceSessionSnapshot::from_snapshot(workspace, snapshot);
        validate_semantics(workspace, &persisted)?;
        let bytes = serde_json::to_vec(&persisted).map_err(|error| {
            AppError::IoError(format!("serialize Workspace session snapshot: {error}"))
        })?;
        crate::workspace::persist::atomic_write(&self.snapshot_path(workspace.id()), &bytes)
    }

    pub(crate) fn clear_corrupt(&self, workspace: &Workspace) -> Result<(), AppError> {
        let path = self.snapshot_path(workspace.id());
        let bytes = match std::fs::read(&path) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(error) => return Err(io_error(&path, "read session snapshot", error)),
        };
        let raw = match serde_json::from_slice::<Value>(&bytes) {
            Ok(raw) => raw,
            Err(_) => {
                return self
                    .quarantine_and_default(&path, workspace.id(), "corrupt", true)
                    .map(|_| ());
            }
        };
        match snapshot_version(&raw) {
            SnapshotVersion::Later => self
                .quarantine_and_default(&path, workspace.id(), "later", true)
                .map(|_| ()),
            SnapshotVersion::Unknown => self
                .quarantine_and_default(&path, workspace.id(), "unknown", true)
                .map(|_| ()),
            SnapshotVersion::Current => match parse_current_schema(raw) {
                Ok(snapshot) if validate_semantics(workspace, &snapshot).is_ok() => Ok(()),
                Ok(_) | Err(()) => self.quarantine(&path, workspace.id(), "cleared"),
            },
        }
    }

    /// Ensures that a save never replaces bytes whose version or validity has
    /// not first been established. Current malformed state gets the documented
    /// writable fallback only after its original bytes are quarantined.
    fn prepare_normal_path_write(&self, workspace: &Workspace) -> Result<(), AppError> {
        self.ensure_no_later_version_guard(workspace.id())?;
        let path = self.snapshot_path(workspace.id());
        let bytes = match std::fs::read(&path) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(error) => return Err(io_error(&path, "read session snapshot before save", error)),
        };
        let raw = match serde_json::from_slice::<Value>(&bytes) {
            Ok(raw) => raw,
            Err(_) => {
                self.quarantine_and_default(&path, workspace.id(), "corrupt", true)?;
                return Err(normal_path_refusal());
            }
        };
        match snapshot_version(&raw) {
            SnapshotVersion::Later => {
                self.quarantine_and_default(&path, workspace.id(), "later", true)?;
                return Err(normal_path_refusal());
            }
            SnapshotVersion::Unknown => {
                self.quarantine_and_default(&path, workspace.id(), "unknown", true)?;
                return Err(normal_path_refusal());
            }
            SnapshotVersion::Current => {}
        }
        let current = parse_current_schema(raw).and_then(|snapshot| {
            validate_semantics(workspace, &snapshot).map_err(|_| ())?;
            Ok(snapshot)
        });
        if current.is_err() {
            self.quarantine(&path, workspace.id(), "invalid")?;
        }
        Ok(())
    }

    fn ensure_no_later_version_guard(&self, workspace_id: &str) -> Result<(), AppError> {
        let guard = self.later_version_guard_path(workspace_id);
        match std::fs::metadata(&guard) {
            Ok(_) => Err(normal_path_refusal()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(io_error(&guard, "inspect later-version refusal", error)),
        }
    }

    fn quarantine_and_default(
        &self,
        path: &Path,
        workspace_id: &str,
        reason: &str,
        later: bool,
    ) -> Result<ActiveWorkspaceSessionSnapshot, AppError> {
        if later {
            let guard = self.later_version_guard_path(workspace_id);
            crate::workspace::persist::atomic_write(&guard, b"refused")?;
        }
        self.quarantine(path, workspace_id, reason)?;
        Ok(ActiveWorkspaceSessionSnapshot::default())
    }

    fn quarantine(&self, path: &Path, workspace_id: &str, reason: &str) -> Result<(), AppError> {
        loop {
            let sequence = self.next_quarantine_file.fetch_add(1, Ordering::Relaxed);
            let isolated = self.quarantine_path(workspace_id, reason, sequence);
            match std::fs::hard_link(path, &isolated) {
                Ok(()) => match std::fs::remove_file(path) {
                    Ok(()) => return Ok(()),
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
                    Err(error) => {
                        return Err(io_error(path, "remove quarantined session snapshot", error));
                    }
                },
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
                Err(error) => return Err(io_error(path, "quarantine session snapshot", error)),
            }
        }
    }
}

enum SnapshotVersion {
    Current,
    Later,
    Unknown,
}

fn snapshot_version(raw: &Value) -> SnapshotVersion {
    let Some(version) = raw
        .as_object()
        .and_then(|object| object.get("schema_version"))
    else {
        return SnapshotVersion::Unknown;
    };
    if is_current_schema_version(version) {
        SnapshotVersion::Current
    } else if is_later_integer_schema_version(version) {
        SnapshotVersion::Later
    } else {
        SnapshotVersion::Unknown
    }
}

/// JSON Schema's `integer` includes numbers with a zero fractional part, so
/// the current schema's `const: 1` accepts spellings such as `1.0` and `1e0`.
/// `serde_json` stores those spellings as floating-point numbers by default;
/// this predicate recognizes only the numerically equal current version.
fn is_current_schema_version(value: &Value) -> bool {
    value.as_u64() == Some(u64::from(CURRENT_SCHEMA_VERSION))
        || value
            .as_f64()
            .is_some_and(|version| version == f64::from(CURRENT_SCHEMA_VERSION))
}

fn is_later_integer_schema_version(value: &Value) -> bool {
    value
        .as_u64()
        .is_some_and(|version| version > u64::from(CURRENT_SCHEMA_VERSION))
        || value.as_f64().is_some_and(|version| {
            version.fract() == 0.0 && version > f64::from(CURRENT_SCHEMA_VERSION)
        })
}

fn normal_path_refusal() -> AppError {
    AppError::ParseError(
        "the active Workspace has preserved unverified or later session bytes; BURL-O005 owns any safe current-format recovery path".to_string(),
    )
}

fn parse_current_schema(mut raw: Value) -> Result<PersistedWorkspaceSessionSnapshot, ()> {
    let Some(object) = raw.as_object_mut() else {
        return Err(());
    };
    const KEYS: [&str; 7] = [
        "schema_version",
        "workspace_id",
        "open_note_ids",
        "active_note_id",
        "expanded_directory_ids",
        "search_query",
        "sync_presentation",
    ];
    if object.len() != KEYS.len() || KEYS.iter().any(|key| !object.contains_key(*key)) {
        return Err(());
    }
    let valid_version = object
        .get("schema_version")
        .is_some_and(is_current_schema_version);
    let active_is_nullable_string = object
        .get("active_note_id")
        .is_some_and(|value| value.is_null() || value.as_str().is_some());
    let arrays_are_strings = ["open_note_ids", "expanded_directory_ids"]
        .iter()
        .all(|key| {
            object
                .get(*key)
                .and_then(Value::as_array)
                .is_some_and(|items| items.iter().all(|item| item.as_str().is_some()))
        });
    if !valid_version
        || object.get("workspace_id").and_then(Value::as_str).is_none()
        || !active_is_nullable_string
        || !arrays_are_strings
        || object.get("search_query").and_then(Value::as_str).is_none()
        || !matches!(
            object.get("sync_presentation").and_then(Value::as_str),
            Some("local" | "connected" | "paused")
        )
    {
        return Err(());
    }
    // Normalize only this in-memory value. The source bytes remain untouched
    // on a successful read, while serde can deserialize its `u32` field.
    object.insert(
        "schema_version".to_string(),
        Value::from(CURRENT_SCHEMA_VERSION),
    );
    serde_json::from_value(raw).map_err(|_| ())
}

fn validate_semantics(
    workspace: &Workspace,
    snapshot: &PersistedWorkspaceSessionSnapshot,
) -> Result<(), AppError> {
    if snapshot.workspace_id.is_empty() || snapshot.workspace_id != workspace.id() {
        return Err(AppError::ParseError(
            "session snapshot Workspace identity does not match the active Workspace".to_string(),
        ));
    }
    validate_unique_note_ids(workspace, &snapshot.open_note_ids)?;
    validate_unique_directory_ids(&snapshot.expanded_directory_ids)?;
    if let Some(active) = &snapshot.active_note_id {
        if active.is_empty() || !snapshot.open_note_ids.iter().any(|id| id == active) {
            return Err(AppError::ParseError(
                "the active session Note must occur in open_note_ids".to_string(),
            ));
        }
        workspace.validate_persisted_note_id(active)?;
    }
    Ok(())
}

fn validate_unique_note_ids(workspace: &Workspace, ids: &[String]) -> Result<(), AppError> {
    let mut seen = HashSet::with_capacity(ids.len());
    for id in ids {
        if id.is_empty() || !seen.insert(id) {
            return Err(AppError::ParseError(
                "session snapshot has an empty or duplicate Note identity".to_string(),
            ));
        }
        // This is the existing Core lexical/containment validation. It does
        // not require the saved Note to still exist, which G003 must not do.
        workspace.validate_persisted_note_id(id)?;
    }
    Ok(())
}

fn validate_unique_directory_ids(ids: &[String]) -> Result<(), AppError> {
    let mut seen = HashSet::with_capacity(ids.len());
    for id in ids {
        if id.is_empty() || !seen.insert(id) {
            return Err(AppError::ParseError(
                "session snapshot has an empty or duplicate Directory identity".to_string(),
            ));
        }
        crate::workspace::lifecycle::validate_persisted_directory_id(id)?;
    }
    Ok(())
}

fn io_error(path: &Path, operation: &str, error: std::io::Error) -> AppError {
    AppError::IoError(format!("{operation} {}: {error}", path.display()))
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;
    use std::time::Duration;

    use rusqlite::Connection;

    use super::*;

    fn workspace(root: &Path) -> Arc<Workspace> {
        workspace_with_id(root, "workspace-a")
    }

    fn workspace_with_id(root: &Path, id: &str) -> Arc<Workspace> {
        std::fs::create_dir_all(root).unwrap();
        Workspace::for_test(
            Connection::open_in_memory().unwrap(),
            id,
            root.to_path_buf(),
            Duration::from_secs(1),
        )
    }

    fn store() -> (tempfile::TempDir, SessionSnapshotStore, Arc<Workspace>) {
        let directory = tempfile::tempdir().unwrap();
        let workspace = workspace(&directory.path().join("bundle"));
        let store = SessionSnapshotStore::for_test(directory.path().join("sidecars"));
        (directory, store, workspace)
    }

    fn snapshot(active: Option<&str>) -> ActiveWorkspaceSessionSnapshot {
        ActiveWorkspaceSessionSnapshot {
            open_note_ids: vec!["inbox/today".to_string(), "projects/state".to_string()],
            active_note_id: active.map(str::to_string),
            expanded_directory_ids: vec!["inbox".to_string(), "projects".to_string()],
            search_query: "durable session".to_string(),
            sync_presentation: SessionSyncPresentation::Connected,
        }
    }

    #[test]
    fn round_trips_null_and_present_active_notes() {
        let (_directory, store, workspace) = store();
        for active in [None, Some("projects/state")] {
            let saved = snapshot(active);
            store.save(&workspace, &saved).unwrap();
            assert_eq!(store.load(&workspace).unwrap(), saved);
        }
    }

    #[test]
    fn partitions_and_atomically_replaces_workspace_snapshots() {
        let (directory, store, workspace_a) = store();
        let workspace_b = workspace_with_id(&directory.path().join("other-bundle"), "workspace-b");
        let first = snapshot(None);
        let replacement = ActiveWorkspaceSessionSnapshot {
            search_query: "replacement".to_string(),
            ..snapshot(None)
        };
        store.save(&workspace_a, &first).unwrap();
        let path = store.snapshot_path(workspace_a.id());
        let before = std::fs::metadata(&path).unwrap();
        store.save(&workspace_a, &replacement).unwrap();
        store
            .save(&workspace_b, &snapshot(Some("projects/state")))
            .unwrap();
        assert_eq!(store.load(&workspace_a).unwrap(), replacement);
        assert_eq!(
            store.load(&workspace_b).unwrap().search_query,
            "durable session"
        );
        #[cfg(unix)]
        assert_ne!(
            std::os::unix::fs::MetadataExt::ino(&before),
            std::os::unix::fs::MetadataExt::ino(&std::fs::metadata(path).unwrap())
        );
    }

    #[test]
    fn malformed_current_schema_is_preserved_and_leaves_normal_path_writable() {
        let (_directory, store, workspace) = store();
        let path = store.snapshot_path(workspace.id());
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        let original = br#"{"schema_version":1,"workspace_id":"workspace-a","open_note_ids":[],"expanded_directory_ids":[],"search_query":"","sync_presentation":"local"}"#;
        std::fs::write(&path, original).unwrap();
        assert_eq!(
            store.load(&workspace).unwrap(),
            ActiveWorkspaceSessionSnapshot::default()
        );
        assert!(!path.exists());
        let preserved = std::fs::read_dir(path.parent().unwrap())
            .unwrap()
            .find_map(|entry| {
                let entry = entry.unwrap();
                entry
                    .file_name()
                    .to_string_lossy()
                    .contains("invalid")
                    .then(|| std::fs::read(entry.path()).unwrap())
            });
        assert_eq!(preserved.as_deref(), Some(original.as_slice()));
        store.save(&workspace, &snapshot(None)).unwrap();
        assert!(path.exists());
    }

    #[test]
    fn rejects_schema_and_semantic_violations_before_restore_and_preserves_bytes() {
        let (_directory, store, workspace) = store();
        let fixtures = [
            br#"{"schema_version":1,"workspace_id":"","open_note_ids":[],"active_note_id":null,"expanded_directory_ids":[],"search_query":"","sync_presentation":"local"}"#.as_slice(),
            br#"{"schema_version":1,"workspace_id":"workspace-a","open_note_ids":[""],"active_note_id":null,"expanded_directory_ids":[],"search_query":"","sync_presentation":"local"}"#.as_slice(),
            br#"{"schema_version":1,"workspace_id":"workspace-a","open_note_ids":["a","a"],"active_note_id":null,"expanded_directory_ids":[],"search_query":"","sync_presentation":"local"}"#.as_slice(),
            br#"{"schema_version":1,"workspace_id":"workspace-a","open_note_ids":["../escape"],"active_note_id":null,"expanded_directory_ids":[],"search_query":"","sync_presentation":"local"}"#.as_slice(),
            br#"{"schema_version":1,"workspace_id":"workspace-a","open_note_ids":[],"active_note_id":null,"expanded_directory_ids":[""],"search_query":"","sync_presentation":"local"}"#.as_slice(),
            br#"{"schema_version":1,"workspace_id":"workspace-a","open_note_ids":[],"active_note_id":null,"expanded_directory_ids":["dir","dir"],"search_query":"","sync_presentation":"local"}"#.as_slice(),
            br#"{"schema_version":1,"workspace_id":"workspace-a","open_note_ids":[],"active_note_id":null,"expanded_directory_ids":["../escape"],"search_query":"","sync_presentation":"local"}"#.as_slice(),
            br#"{"schema_version":1,"workspace_id":"workspace-a","open_note_ids":["a"],"active_note_id":"b","expanded_directory_ids":[],"search_query":"","sync_presentation":"local"}"#.as_slice(),
            br#"{"schema_version":1,"workspace_id":"other","open_note_ids":[],"active_note_id":null,"expanded_directory_ids":[],"search_query":"","sync_presentation":"local"}"#.as_slice(),
            br#"{"schema_version":1,"workspace_id":"workspace-a","open_note_ids":[],"expanded_directory_ids":[],"search_query":"","sync_presentation":"local"}"#.as_slice(),
            br#"{"schema_version":1,"workspace_id":"workspace-a","open_note_ids":[],"active_note_id":null,"expanded_directory_ids":[],"search_query":"","sync_presentation":"local","unknown":true}"#.as_slice(),
        ];
        let path = store.snapshot_path(workspace.id());
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        for fixture in fixtures {
            std::fs::write(&path, fixture).unwrap();
            assert_eq!(
                store.load(&workspace).unwrap(),
                ActiveWorkspaceSessionSnapshot::default()
            );
            assert!(!path.exists());
        }
        let preserved = std::fs::read_dir(path.parent().unwrap())
            .unwrap()
            .filter_map(Result::ok)
            .filter(|entry| entry.file_name().to_string_lossy().contains(".invalid."))
            .map(|entry| std::fs::read(entry.path()).unwrap())
            .collect::<Vec<_>>();
        assert_eq!(preserved.len(), fixtures.len());
        for fixture in fixtures {
            assert!(preserved.iter().any(|bytes| bytes.as_slice() == fixture));
        }
    }

    #[test]
    fn later_version_bytes_are_preserved_and_block_normal_recreation() {
        let (_directory, store, workspace) = store();
        let path = store.snapshot_path(workspace.id());
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        let original = br#"{"schema_version":2,"workspace_id":"workspace-a","open_note_ids":[],"active_note_id":null,"expanded_directory_ids":[],"search_query":"","sync_presentation":"local"}"#;
        std::fs::write(&path, original).unwrap();
        assert_eq!(
            store.load(&workspace).unwrap(),
            ActiveWorkspaceSessionSnapshot::default()
        );
        assert!(store.later_version_guard_path(workspace.id()).exists());
        assert!(store.save(&workspace, &snapshot(None)).is_err());
        assert!(!path.exists());
        let preserved = std::fs::read_dir(path.parent().unwrap())
            .unwrap()
            .find_map(|entry| {
                let entry = entry.unwrap();
                entry
                    .file_name()
                    .to_string_lossy()
                    .contains(".later.")
                    .then(|| std::fs::read(entry.path()).unwrap())
            });
        assert_eq!(preserved.as_deref(), Some(original.as_slice()));
    }

    #[test]
    fn fresh_save_refuses_an_unseen_later_version_without_overwriting_it() {
        let (_directory, store, workspace) = store();
        let path = store.snapshot_path(workspace.id());
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        let original = br#"{"schema_version":2,"workspace_id":"workspace-a","open_note_ids":[],"active_note_id":null,"expanded_directory_ids":[],"search_query":"future","sync_presentation":"local"}"#;
        std::fs::write(&path, original).unwrap();

        assert!(store.save(&workspace, &snapshot(None)).is_err());
        assert!(store.later_version_guard_path(workspace.id()).exists());
        assert!(!path.exists());
        let preserved = std::fs::read_dir(path.parent().unwrap())
            .unwrap()
            .find_map(|entry| {
                let entry = entry.unwrap();
                entry
                    .file_name()
                    .to_string_lossy()
                    .contains(".later.")
                    .then(|| std::fs::read(entry.path()).unwrap())
            });
        assert_eq!(preserved.as_deref(), Some(original.as_slice()));
    }

    #[test]
    fn fresh_save_refuses_unverified_bytes_without_recreating_the_normal_path() {
        let (_directory, store, workspace) = store();
        let path = store.snapshot_path(workspace.id());
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        let original = b"not a session snapshot";
        std::fs::write(&path, original).unwrap();

        assert!(store.save(&workspace, &snapshot(None)).is_err());

        assert!(store.later_version_guard_path(workspace.id()).exists());
        assert!(!path.exists());
        let preserved = std::fs::read_dir(path.parent().unwrap())
            .unwrap()
            .find_map(|entry| {
                let entry = entry.unwrap();
                entry
                    .file_name()
                    .to_string_lossy()
                    .contains(".corrupt.")
                    .then(|| std::fs::read(entry.path()).unwrap())
            });
        assert_eq!(preserved.as_deref(), Some(original.as_slice()));
    }

    #[test]
    fn fresh_save_refuses_an_unknown_schema_version_without_recreating_the_normal_path() {
        let (_directory, store, workspace) = store();
        let path = store.snapshot_path(workspace.id());
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        let original = br#"{"schema_version":0,"workspace_id":"workspace-a","open_note_ids":[],"active_note_id":null,"expanded_directory_ids":[],"search_query":"legacy","sync_presentation":"local"}"#;
        std::fs::write(&path, original).unwrap();

        assert!(store.save(&workspace, &snapshot(None)).is_err());
        assert!(store.later_version_guard_path(workspace.id()).exists());
        assert!(!path.exists());
        let preserved = std::fs::read_dir(path.parent().unwrap())
            .unwrap()
            .find_map(|entry| {
                let entry = entry.unwrap();
                entry
                    .file_name()
                    .to_string_lossy()
                    .contains(".unknown.")
                    .then(|| std::fs::read(entry.path()).unwrap())
            });
        assert_eq!(preserved.as_deref(), Some(original.as_slice()));
    }

    #[test]
    fn clearing_an_unseen_later_version_keeps_normal_writes_refused() {
        let (_directory, store, workspace) = store();
        let path = store.snapshot_path(workspace.id());
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        let original = br#"{"schema_version":2,"workspace_id":"workspace-a","open_note_ids":[],"active_note_id":null,"expanded_directory_ids":[],"search_query":"future","sync_presentation":"local"}"#;
        std::fs::write(&path, original).unwrap();

        store.clear_corrupt(&workspace).unwrap();

        assert!(store.later_version_guard_path(workspace.id()).exists());
        assert!(store.save(&workspace, &snapshot(None)).is_err());
        assert!(!path.exists());
        let preserved = std::fs::read_dir(path.parent().unwrap())
            .unwrap()
            .find_map(|entry| {
                let entry = entry.unwrap();
                entry
                    .file_name()
                    .to_string_lossy()
                    .contains(".later.")
                    .then(|| std::fs::read(entry.path()).unwrap())
            });
        assert_eq!(preserved.as_deref(), Some(original.as_slice()));
    }

    #[test]
    fn clearing_a_valid_current_snapshot_leaves_its_live_bytes_untouched() {
        let (_directory, store, workspace) = store();
        let saved = snapshot(Some("projects/state"));
        store.save(&workspace, &saved).unwrap();
        let path = store.snapshot_path(workspace.id());
        let original = std::fs::read(&path).unwrap();

        store.clear_corrupt(&workspace).unwrap();

        assert_eq!(std::fs::read(&path).unwrap(), original);
        assert_eq!(store.load(&workspace).unwrap(), saved);
    }

    #[test]
    fn clearing_malformed_current_state_preserves_it_and_leaves_the_path_writable() {
        let (_directory, store, workspace) = store();
        let path = store.snapshot_path(workspace.id());
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        let original = br#"{"schema_version":1,"workspace_id":"workspace-a","open_note_ids":[],"expanded_directory_ids":[],"search_query":"","sync_presentation":"local"}"#;
        std::fs::write(&path, original).unwrap();

        store.clear_corrupt(&workspace).unwrap();

        assert!(!path.exists());
        let preserved = std::fs::read_dir(path.parent().unwrap())
            .unwrap()
            .find_map(|entry| {
                let entry = entry.unwrap();
                entry
                    .file_name()
                    .to_string_lossy()
                    .contains(".cleared.")
                    .then(|| std::fs::read(entry.path()).unwrap())
            });
        assert_eq!(preserved.as_deref(), Some(original.as_slice()));
        store.save(&workspace, &snapshot(None)).unwrap();
        assert!(path.exists());
    }

    #[test]
    fn failed_later_version_guard_write_keeps_bytes_for_restart_refusal() {
        let (directory, store, workspace) = store();
        let path = store.snapshot_path(workspace.id());
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        let original = br#"{"schema_version":2,"workspace_id":"workspace-a","open_note_ids":[],"active_note_id":null,"expanded_directory_ids":[],"search_query":"future","sync_presentation":"local"}"#;
        std::fs::write(&path, original).unwrap();
        let guard = store.later_version_guard_path(workspace.id());
        std::fs::create_dir(&guard).unwrap();

        assert!(store.load(&workspace).is_err());
        assert_eq!(std::fs::read(&path).unwrap(), original);

        std::fs::remove_dir(&guard).unwrap();
        let restarted = SessionSnapshotStore::for_test(directory.path().join("sidecars"));
        assert!(restarted.save(&workspace, &snapshot(None)).is_err());
        assert!(restarted.later_version_guard_path(workspace.id()).exists());
        assert!(!path.exists());
    }

    #[test]
    fn quarantine_collision_keeps_the_existing_and_new_payloads() {
        let (_directory, store, workspace) = store();
        let path = store.snapshot_path(workspace.id());
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        let existing = store.quarantine_path(workspace.id(), "corrupt", 0);
        let old_payload = b"an earlier preserved payload";
        let new_payload = b"a newly quarantined payload";
        std::fs::write(&existing, old_payload).unwrap();
        std::fs::write(&path, new_payload).unwrap();

        store.quarantine(&path, workspace.id(), "corrupt").unwrap();

        assert!(!path.exists());
        let preserved = std::fs::read_dir(path.parent().unwrap())
            .unwrap()
            .filter_map(Result::ok)
            .filter(|entry| entry.file_name().to_string_lossy().contains(".corrupt."))
            .map(|entry| std::fs::read(entry.path()).unwrap())
            .collect::<Vec<_>>();
        assert_eq!(preserved.len(), 2);
        assert!(preserved.iter().any(|payload| payload == old_payload));
        assert!(preserved.iter().any(|payload| payload == new_payload));
    }

    #[test]
    fn restores_current_schema_from_json_schema_integer_spellings() {
        let (_directory, store, workspace) = store();
        let schema: Value = serde_json::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../.constitution/tech-spec/data-models/workspace-session-snapshot.schema.json"
        )))
        .unwrap();
        assert_eq!(schema["properties"]["schema_version"]["type"], "integer");
        assert_eq!(schema["properties"]["schema_version"]["const"], 1);

        for spelling in ["1.0", "1e0"] {
            let path = store.snapshot_path(workspace.id());
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            let raw = format!(
                r#"{{"schema_version":{spelling},"workspace_id":"workspace-a","open_note_ids":[],"active_note_id":null,"expanded_directory_ids":[],"search_query":"","sync_presentation":"local"}}"#
            );
            std::fs::write(&path, raw.as_bytes()).unwrap();

            assert_eq!(
                store.load(&workspace).unwrap(),
                ActiveWorkspaceSessionSnapshot::default()
            );
            assert!(path.exists());
            assert_eq!(std::fs::read(&path).unwrap(), raw.as_bytes());
        }
    }

    #[test]
    fn rejects_fractional_and_string_schema_versions() {
        let (_directory, store, workspace) = store();
        for spelling in ["1.5", r#""1""#] {
            let path = store.snapshot_path(workspace.id());
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            let raw = format!(
                r#"{{"schema_version":{spelling},"workspace_id":"workspace-a","open_note_ids":[],"active_note_id":null,"expanded_directory_ids":[],"search_query":"","sync_presentation":"local"}}"#
            );
            std::fs::write(&path, raw.as_bytes()).unwrap();

            assert_eq!(
                store.load(&workspace).unwrap(),
                ActiveWorkspaceSessionSnapshot::default()
            );
            assert!(!path.exists());
        }
    }

    #[test]
    fn serialized_snapshot_matches_the_checked_in_schema_contract() {
        let (_directory, _store, workspace) = store();
        let schema: Value = serde_json::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../.constitution/tech-spec/data-models/workspace-session-snapshot.schema.json"
        )))
        .unwrap();
        let serialized = serde_json::to_value(PersistedWorkspaceSessionSnapshot::from_snapshot(
            &workspace,
            &snapshot(Some("projects/state")),
        ))
        .unwrap();
        let object = serialized.as_object().unwrap();
        let required = schema["required"].as_array().unwrap();
        let properties = schema["properties"].as_object().unwrap();

        assert_eq!(schema["additionalProperties"], false);
        assert_eq!(object.len(), required.len());
        assert!(required
            .iter()
            .all(|key| key.as_str().is_some_and(|key| object.contains_key(key))));
        assert_eq!(properties.len(), object.len());
        assert!(object.keys().all(|key| properties.contains_key(key)));
        assert_eq!(
            serialized["schema_version"],
            properties["schema_version"]["const"]
        );
        assert_eq!(
            properties["active_note_id"]["type"],
            serde_json::json!(["string", "null"])
        );
        assert_eq!(serialized["active_note_id"], "projects/state");
        assert!(
            serde_json::to_value(PersistedWorkspaceSessionSnapshot::from_snapshot(
                &workspace,
                &snapshot(None),
            ))
            .unwrap()["active_note_id"]
                .is_null()
        );
        assert_eq!(
            properties["sync_presentation"]["enum"],
            serde_json::json!(["local", "connected", "paused"])
        );
        assert_eq!(serialized["sync_presentation"], "connected");
    }

    #[test]
    fn serialized_snapshot_excludes_note_bodies_credentials_and_preferences() {
        let (_directory, store, workspace) = store();
        store
            .save(&workspace, &snapshot(Some("projects/state")))
            .unwrap();
        let value: Value =
            serde_json::from_slice(&std::fs::read(store.snapshot_path(workspace.id())).unwrap())
                .unwrap();
        assert_eq!(value.as_object().unwrap().len(), 7);
        assert_eq!(value["active_note_id"], "projects/state");
        for forbidden in [
            "body",
            "credential",
            "token",
            "theme",
            "font_scale",
            "device_preference",
        ] {
            assert!(value.get(forbidden).is_none());
        }
    }
}
