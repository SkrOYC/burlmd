//! Durable, presentation-only Workspace session snapshots.
//!
//! The snapshot is a Core sidecar in application support, never a Note, Git
//! artifact, or SQL-index record. It carries only identifiers and small UI
//! state; Core remains authoritative for every Note session and its content.

use std::fmt::Write as _;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use sha2::{Digest as _, Sha256};

use crate::error::AppError;

const CURRENT_SCHEMA_VERSION: u32 = 1;
static NEXT_CORRUPT_FILE: AtomicU64 = AtomicU64::new(0);

/// Defines the saved presentation-only synchronization label.
#[frb]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SessionSyncPresentation {
    Local,
    Connected,
    Paused,
}

/// Presentation-only session state for the active Workspace.
///
/// Core writes the schema version and Workspace identifier into the durable
/// envelope. This FFI shape deliberately contains neither of those values.
#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActiveWorkspaceSessionSnapshot {
    /// Concept IDs of open Notes, in restore order.
    pub open_note_ids: Vec<String>,
    /// Concept ID of the active Note, if any.
    pub active_note_id: Option<String>,
    /// Expanded Directory IDs or bundle-relative paths.
    pub expanded_directory_ids: Vec<String>,
    /// The most recent search-box text.
    pub search_query: String,
    /// Presentation-only synchronization state.
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

/// The versioned JSON envelope stored in Core application support.
///
/// Keeping the Workspace identifier here makes stale or misrouted files
/// detectable. It does not cross FFI: the active Workspace is always Core
/// owned, so Dart cannot select where a snapshot is read or written.
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PersistedWorkspaceSessionSnapshot {
    schema_version: u32,
    workspace_id: String,
    open_note_ids: Vec<String>,
    active_note_id: Option<String>,
    expanded_directory_ids: Vec<String>,
    search_query: String,
    sync_presentation: SessionSyncPresentation,
}

impl PersistedWorkspaceSessionSnapshot {
    fn new(workspace_id: &str, snapshot: &ActiveWorkspaceSessionSnapshot) -> Self {
        Self {
            schema_version: CURRENT_SCHEMA_VERSION,
            workspace_id: workspace_id.to_string(),
            open_note_ids: snapshot.open_note_ids.clone(),
            active_note_id: snapshot.active_note_id.clone(),
            expanded_directory_ids: snapshot.expanded_directory_ids.clone(),
            search_query: snapshot.search_query.clone(),
            sync_presentation: snapshot.sync_presentation,
        }
    }

    fn is_current_for(&self, workspace_id: &str) -> bool {
        self.schema_version == CURRENT_SCHEMA_VERSION && self.workspace_id == workspace_id
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

/// Owns the application-support sidecar directory for versioned snapshots.
pub(crate) struct SessionSnapshotStore {
    root: PathBuf,
}

impl SessionSnapshotStore {
    /// Uses Core's application-support tree, outside Workspaces, Git, and the
    /// encrypted derived index.
    pub(crate) fn application_support() -> Result<Self, AppError> {
        let root = crate::db::connection::xdg_data_home()?
            .join("burlmd")
            .join("workspace-session-snapshots");
        std::fs::create_dir_all(&root)
            .map_err(|error| io_error(&root, "create session snapshot directory", error))?;
        Ok(Self { root })
    }

    #[cfg(test)]
    fn for_test(root: PathBuf) -> Self {
        Self { root }
    }

    /// A SHA-256 key avoids treating an opaque Workspace id as a path while
    /// retaining deterministic one-file-per-Workspace partitioning.
    fn snapshot_path(&self, workspace_id: &str) -> PathBuf {
        let digest = Sha256::digest(workspace_id.as_bytes());
        let mut key = String::with_capacity(digest.len() * 2);
        for byte in digest {
            write!(key, "{byte:02x}").expect("writing to a String cannot fail");
        }
        self.root.join(format!("{key}.json"))
    }

    fn corrupt_path(&self, workspace_id: &str) -> PathBuf {
        let snapshot = self.snapshot_path(workspace_id);
        let file_name = snapshot
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("workspace-session.json");
        let sequence = NEXT_CORRUPT_FILE.fetch_add(1, Ordering::Relaxed);
        self.root.join(format!(
            "{file_name}.corrupt.{}.{}",
            std::process::id(),
            sequence
        ))
    }

    pub(crate) fn load(
        &self,
        workspace_id: &str,
    ) -> Result<ActiveWorkspaceSessionSnapshot, AppError> {
        let path = self.snapshot_path(workspace_id);
        let bytes = match std::fs::read(&path) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok(ActiveWorkspaceSessionSnapshot::default());
            }
            Err(error) => return Err(io_error(&path, "read session snapshot", error)),
        };

        match serde_json::from_slice::<PersistedWorkspaceSessionSnapshot>(&bytes) {
            Ok(persisted) if persisted.is_current_for(workspace_id) => {
                Ok(persisted.into_snapshot())
            }
            Ok(_) | Err(_) => {
                self.isolate(&path, workspace_id)?;
                Ok(ActiveWorkspaceSessionSnapshot::default())
            }
        }
    }

    pub(crate) fn save(
        &self,
        workspace_id: &str,
        snapshot: &ActiveWorkspaceSessionSnapshot,
    ) -> Result<(), AppError> {
        std::fs::create_dir_all(&self.root)
            .map_err(|error| io_error(&self.root, "create session snapshot directory", error))?;
        let persisted = PersistedWorkspaceSessionSnapshot::new(workspace_id, snapshot);
        let bytes = serde_json::to_vec(&persisted).map_err(|error| {
            AppError::IoError(format!("serialize Workspace session snapshot: {error}"))
        })?;
        crate::workspace::persist::atomic_write(&self.snapshot_path(workspace_id), &bytes)
    }

    /// Removes the active snapshot by moving its bytes out of the live path.
    /// This is intentionally a preservation operation rather than deletion:
    /// callers clearing a corrupt snapshot never lose the bytes needed for
    /// diagnosis, and another Workspace's sidecar cannot be affected.
    pub(crate) fn clear_corrupt(&self, workspace_id: &str) -> Result<(), AppError> {
        let path = self.snapshot_path(workspace_id);
        match std::fs::metadata(&path) {
            Ok(_) => self.isolate(&path, workspace_id),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(io_error(&path, "inspect session snapshot", error)),
        }
    }

    fn isolate(&self, path: &Path, workspace_id: &str) -> Result<(), AppError> {
        let isolated = self.corrupt_path(workspace_id);
        match std::fs::rename(path, &isolated) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(io_error(path, "isolate corrupt session snapshot", error)),
        }
    }
}

fn io_error(path: &Path, operation: &str, error: std::io::Error) -> AppError {
    AppError::IoError(format!("{operation} {}: {error}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn snapshot() -> ActiveWorkspaceSessionSnapshot {
        ActiveWorkspaceSessionSnapshot {
            open_note_ids: vec!["inbox/today".to_string(), "projects/state".to_string()],
            active_note_id: Some("projects/state".to_string()),
            expanded_directory_ids: vec!["inbox".to_string(), "projects".to_string()],
            search_query: "durable session".to_string(),
            sync_presentation: SessionSyncPresentation::Connected,
        }
    }

    fn store() -> (tempfile::TempDir, SessionSnapshotStore) {
        let directory = tempfile::tempdir().expect("create session sidecar fixture");
        let store = SessionSnapshotStore::for_test(directory.path().to_path_buf());
        (directory, store)
    }

    #[test]
    fn round_trips_a_versioned_workspace_session_snapshot() {
        let (_directory, store) = store();
        let saved = snapshot();

        store.save("workspace-a", &saved).expect("save snapshot");

        assert_eq!(store.load("workspace-a").expect("load snapshot"), saved);
    }

    #[test]
    fn partitions_snapshots_by_workspace_id() {
        let (_directory, store) = store();
        let a = snapshot();
        let b = ActiveWorkspaceSessionSnapshot {
            search_query: "only workspace b".to_string(),
            ..ActiveWorkspaceSessionSnapshot::default()
        };

        store.save("workspace-a", &a).expect("save workspace a");
        store.save("workspace-b", &b).expect("save workspace b");

        assert_eq!(store.load("workspace-a").expect("load workspace a"), a);
        assert_eq!(store.load("workspace-b").expect("load workspace b"), b);
    }

    #[test]
    fn atomically_replaces_an_existing_snapshot() {
        let (_directory, store) = store();
        let first = snapshot();
        let replacement = ActiveWorkspaceSessionSnapshot {
            search_query: "replacement".to_string(),
            ..ActiveWorkspaceSessionSnapshot::default()
        };

        store
            .save("workspace-a", &first)
            .expect("save first snapshot");
        let path = store.snapshot_path("workspace-a");
        let before = std::fs::metadata(&path).expect("first snapshot metadata");
        store
            .save("workspace-a", &replacement)
            .expect("atomically replace snapshot");
        let after = std::fs::metadata(&path).expect("replacement snapshot metadata");

        assert_eq!(
            store.load("workspace-a").expect("load replacement"),
            replacement
        );
        #[cfg(unix)]
        assert_ne!(
            std::os::unix::fs::MetadataExt::ino(&before),
            std::os::unix::fs::MetadataExt::ino(&after),
            "an atomic rename must publish a fresh file rather than truncate the old one"
        );
        let leftovers = std::fs::read_dir(path.parent().expect("snapshot parent"))
            .expect("list snapshot parent")
            .map(|entry| entry.expect("snapshot entry").file_name())
            .filter_map(|name| name.into_string().ok())
            .filter(|name| name.ends_with(".tmp"))
            .collect::<Vec<_>>();
        assert!(
            leftovers.is_empty(),
            "temporary snapshot bytes remain: {leftovers:?}"
        );
    }

    #[test]
    fn corrupt_snapshot_is_isolated_and_falls_back_only_for_its_workspace() {
        let (_directory, store) = store();
        let unaffected = snapshot();
        store
            .save("workspace-b", &unaffected)
            .expect("save unaffected workspace");
        let corrupt_path = store.snapshot_path("workspace-a");
        std::fs::create_dir_all(corrupt_path.parent().expect("snapshot parent"))
            .expect("create snapshot parent");
        std::fs::write(&corrupt_path, b"not json").expect("write corrupt bytes");

        assert_eq!(
            store.load("workspace-a").expect("corrupt fallback"),
            ActiveWorkspaceSessionSnapshot::default()
        );
        assert_eq!(
            store.load("workspace-b").expect("unaffected workspace"),
            unaffected
        );
        assert!(!corrupt_path.exists(), "corrupt path must be cleared");
        let isolated = std::fs::read_dir(corrupt_path.parent().expect("snapshot parent"))
            .expect("list snapshot parent")
            .filter_map(Result::ok)
            .map(|entry| entry.file_name().to_string_lossy().into_owned())
            .any(|name| name.contains("corrupt"));
        assert!(
            isolated,
            "corrupt bytes must be isolated rather than discarded"
        );
    }

    #[test]
    fn unknown_schema_version_is_isolated_and_falls_back_to_default() {
        let (_directory, store) = store();
        let path = store.snapshot_path("workspace-a");
        std::fs::create_dir_all(path.parent().expect("snapshot parent"))
            .expect("create snapshot parent");
        std::fs::write(
            &path,
            r#"{"schema_version":2,"workspace_id":"workspace-a","open_note_ids":[],"active_note_id":null,"expanded_directory_ids":[],"search_query":"","sync_presentation":"local"}"#,
        )
        .expect("write unknown snapshot");

        assert_eq!(
            store.load("workspace-a").expect("unknown-version fallback"),
            ActiveWorkspaceSessionSnapshot::default()
        );
        assert!(!path.exists(), "unknown-version path must be cleared");
    }

    #[test]
    fn clear_corrupt_moves_only_the_active_workspace_bytes_out_of_the_live_path() {
        let (_directory, store) = store();
        store
            .save("workspace-b", &snapshot())
            .expect("save unaffected snapshot");
        let path = store.snapshot_path("workspace-a");
        std::fs::create_dir_all(path.parent().expect("snapshot parent"))
            .expect("create snapshot parent");
        std::fs::write(&path, b"corrupt bytes").expect("write corrupt snapshot");

        store
            .clear_corrupt("workspace-a")
            .expect("clear active corrupt snapshot");

        assert!(!path.exists(), "active corrupt path must be cleared");
        assert_eq!(
            store.load("workspace-b").expect("load unaffected snapshot"),
            snapshot()
        );
        let isolated_bytes = std::fs::read_dir(path.parent().expect("snapshot parent"))
            .expect("list snapshot parent")
            .filter_map(Result::ok)
            .find_map(|entry| {
                entry
                    .file_name()
                    .to_string_lossy()
                    .contains("corrupt")
                    .then(|| std::fs::read(entry.path()).expect("read isolated bytes"))
            });
        assert_eq!(isolated_bytes.as_deref(), Some(b"corrupt bytes".as_slice()));
    }

    #[test]
    fn snapshot_bytes_exclude_note_bodies_credentials_and_device_preferences() {
        let (_directory, store) = store();
        store
            .save("workspace-a", &snapshot())
            .expect("save snapshot");
        let bytes =
            std::fs::read(store.snapshot_path("workspace-a")).expect("read durable snapshot");
        let text = String::from_utf8(bytes).expect("snapshot JSON is UTF-8");

        assert!(text.contains("open_note_ids"));
        assert!(text.contains("workspace_id"));
        for forbidden in [
            "Note body that must not persist",
            "credential-token-value",
            "font_scale",
            "theme_mode",
            "update_notification",
        ] {
            assert!(
                !text.contains(forbidden),
                "snapshot bytes must not contain {forbidden:?}"
            );
        }
    }
}
