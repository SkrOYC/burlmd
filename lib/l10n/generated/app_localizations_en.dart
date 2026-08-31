// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'burlmd';

  @override
  String get linkCompletionLabel => 'Link completion';

  @override
  String linkCompletionExisting(String title) {
    return 'Link to existing note $title';
  }

  @override
  String linkCompletionProspective(String title) {
    return 'Create and link new note $title';
  }

  @override
  String get linkCompletionProspectiveBadge => 'New note';

  @override
  String internalLinkExisting(String title) {
    return 'Open linked note $title';
  }

  @override
  String internalLinkMissing(String title) {
    return 'Open missing linked note $title';
  }

  @override
  String get createLinkedNoteTitle => 'Create linked note?';

  @override
  String createLinkedNoteBody(String title, String directoryPath) {
    return 'Create $title in $directoryPath?';
  }

  @override
  String get createLinkedNoteConfirm => 'Create note';

  @override
  String get createLinkedNoteCancel => 'Cancel';

  @override
  String linkOperationFailed(String error) {
    return 'Could not complete the linked-note action: $error';
  }

  @override
  String noteCloseFailed(String error) {
    return 'Could not switch notes: $error';
  }

  @override
  String lifecycleCommitWarning(String detail) {
    return 'The change is applied, but its Git commit failed: $detail';
  }

  @override
  String lifecycleSettlementWarning(String detail) {
    return 'The change is applied, but cleanup could not finish: $detail';
  }

  @override
  String editorOperationFailed(String error) {
    return 'Could not complete the editor operation: $error';
  }

  @override
  String get workspaceSearchNotes => 'Search notes…';

  @override
  String get workspaceSearchNotesTooltip => 'Search notes';

  @override
  String get workspaceSearchShortcutMacos => '⌘K';

  @override
  String get workspaceSearchShortcutControl => 'Ctrl+K';

  @override
  String get workspaceDismissOverlay => 'Dismiss overlay';

  @override
  String get workspaceLocalWorkspace => 'Local workspace';

  @override
  String get workspacePreferences => 'Preferences';

  @override
  String get workspaceOpenNavigator => 'Open navigator';

  @override
  String get workspaceCollapseSidebar => 'Collapse sidebar';

  @override
  String get workspaceDefaultPath => 'workspace';

  @override
  String get workspaceWelcomeTab => 'Welcome.md';

  @override
  String workspaceUntitledTab(int number) {
    return 'Untitled $number.md';
  }

  @override
  String get workspaceAddVisualTab => 'Add visual tab';

  @override
  String get workspaceCloseTab => 'Close tab';

  @override
  String get workspaceCloseOtherTabs => 'Close other tabs';

  @override
  String get workspaceCloseAllVisualTabs => 'Close all visual tabs';

  @override
  String workspaceTabLabel(String title) {
    return '$title tab';
  }

  @override
  String workspaceCloseNamedTab(String title) {
    return 'Close $title';
  }

  @override
  String workspaceRestoreSavedNotes(String noteIds) {
    return 'Could not restore saved notes: $noteIds';
  }

  @override
  String get workspaceCopiedPath => 'Copied path';

  @override
  String get workspaceCopyPath => 'Copy path';

  @override
  String get workspaceHistory => 'History';

  @override
  String workspaceBreadcrumb(String path) {
    return 'Workspace  ›  $path';
  }

  @override
  String get workspaceModifiedRecently => 'Modified recently';

  @override
  String get workspaceModifiedJustNow => 'Modified just now';

  @override
  String workspaceModifiedMinutesAgo(int minutes) {
    return 'Modified ${minutes}m ago';
  }

  @override
  String workspaceModifiedHoursAgo(int hours) {
    return 'Modified ${hours}h ago';
  }

  @override
  String workspaceModifiedDaysAgo(int days) {
    return 'Modified ${days}d ago';
  }

  @override
  String workspaceNoteSummary(String modified, int words, String wordLabel) {
    return '$modified · $words $wordLabel';
  }

  @override
  String get workspaceWordSingular => 'word';

  @override
  String get workspaceWordPlural => 'words';

  @override
  String get workspaceSelectNoteTitle => 'Select a note to open it';

  @override
  String get workspaceSelectNoteBody =>
      'Choose a note from the directory tree to begin writing.';

  @override
  String get workspaceCloseSearch => 'Close search';

  @override
  String get workspaceEditorPreferences => 'Editor Preferences';

  @override
  String get workspaceAppearanceTheme => 'Appearance theme';

  @override
  String get workspaceBaseReadingSize => 'Base reading size';

  @override
  String get workspaceProseLineMeasure => 'Prose line measure';

  @override
  String get workspaceFocusMode => 'Focus Mode (Zen)';

  @override
  String get workspaceFocusModeDescription =>
      'Dim non-active blocks while editing';

  @override
  String get workspaceUpdateNotifications => 'Update notifications';

  @override
  String get workspaceUpdateNotificationsDescription =>
      'Notify me about compatible new releases';

  @override
  String get workspaceDone => 'Done';

  @override
  String get themePreferenceSystem => 'System';

  @override
  String get themePreferenceLight => 'Light';

  @override
  String get themePreferenceDark => 'Dark';

  @override
  String get fontScaleCompact => 'Compact';

  @override
  String get fontScaleStandard => 'Standard';

  @override
  String get fontScaleComfortable => 'Comfortable';

  @override
  String get fontScaleLarge => 'Large';

  @override
  String get measureNarrow => '55ch · Narrow reading';

  @override
  String get measureStandard => '65ch · Standard prose';

  @override
  String get measureWide => '75ch · Wide';

  @override
  String get measureTechnical => '85ch · Code & tables';

  @override
  String get measureFull => 'Full width';

  @override
  String get syncInspectorTitle => 'Sync & Storage';

  @override
  String get syncCloseInspector => 'Close sync inspector';

  @override
  String syncInspectorPath(String path) {
    return 'Path: $path';
  }

  @override
  String get syncRemoteNotConfigured => 'Remote: Not configured';

  @override
  String get syncStatusUnavailable =>
      'Remote sync status becomes available when the Core exposes it.';

  @override
  String get syncRescanWorkspace => 'Rescan workspace';

  @override
  String get syncStateInSync => 'In Sync';

  @override
  String get syncStatePendingSuggestion => '1 Pending Suggestion';

  @override
  String get syncStateSyncing => 'Syncing';

  @override
  String get syncStateLocalOnly => 'Local Only';

  @override
  String get syncStateOffline => 'Offline';

  @override
  String get syncStateAuthRequired => 'Auth Required';

  @override
  String get syncStateUnreachable => 'Unreachable';

  @override
  String get syncStateExternalChanges => 'External Changes';

  @override
  String get syncDescriptionInSync =>
      'All notes match the remote Git repository.';

  @override
  String get syncDescriptionPendingSuggestion =>
      'A remote change is ready for in-line block review.';

  @override
  String get syncDescriptionSyncing =>
      'Synchronizing with the remote repository.';

  @override
  String get syncDescriptionLocalOnly =>
      'Local files on disk without a configured Remote.';

  @override
  String get syncDescriptionOffline =>
      'Working locally; Burl will sync again when reconnected.';

  @override
  String get syncDescriptionAuthRequired =>
      'An SSH key or access token is required.';

  @override
  String get syncDescriptionUnreachable =>
      'The configured remote could not be reached.';

  @override
  String get syncDescriptionExternalChanges =>
      'Files on disk were updated by another application.';

  @override
  String get historyTitle => 'Git History';

  @override
  String get historyNoSnapshotsAvailable =>
      'No snapshots are available yet. Git history will appear here when the Core exposes note snapshots.';

  @override
  String get historyStoredInGit => 'Stored in .git/';

  @override
  String get treeNewNote => 'New note';

  @override
  String get treeNewDirectory => 'New directory';

  @override
  String get treeTitle => 'Title';

  @override
  String get treeName => 'Name';

  @override
  String get treeDirectories => 'Directories';

  @override
  String get treeDirectoriesHeading => 'DIRECTORIES';

  @override
  String get treeFailedToLoad => 'Failed to load workspace tree';

  @override
  String get treeRetry => 'Retry';

  @override
  String get treeExpandedDirectory => 'Expanded directory';

  @override
  String get treeDirectory => 'Directory';

  @override
  String get treeDirectoryKind => 'directory';

  @override
  String get treeNote => 'Note';

  @override
  String get treeNoteKind => 'note';

  @override
  String treeDirectoryActions(String name) {
    return 'Actions for directory $name';
  }

  @override
  String treeNoteActions(String title) {
    return 'Actions for note $title';
  }

  @override
  String get treeNewNoteHere => 'New note here';

  @override
  String get treeNewSubdirectory => 'New subdirectory';

  @override
  String get treeRename => 'Rename';

  @override
  String get treeDelete => 'Delete';

  @override
  String get treeMoveToDirectory => 'Move to directory…';

  @override
  String treeNewNoteInDirectory(String name) {
    return 'New note in \"$name\"';
  }

  @override
  String treeNewSubdirectoryInDirectory(String name) {
    return 'New subdirectory in \"$name\"';
  }

  @override
  String treeRenameDirectory(String name) {
    return 'Rename directory \"$name\"';
  }

  @override
  String get treeNewName => 'New name';

  @override
  String get treeRenameNote => 'Rename note';

  @override
  String get treeNewTitle => 'New title';

  @override
  String treeDeleteDirectoryConsequence(String name) {
    return 'Every note inside \"$name\" is deleted with it. They stay recoverable from local version history.';
  }

  @override
  String get treeDeleteNoteConsequence =>
      'It stays recoverable from local version history, but links elsewhere that pointed at it will no longer resolve.';

  @override
  String get treeCancel => 'Cancel';

  @override
  String get treeConfirm => 'OK';

  @override
  String treeDeleteNamed(String kind, String name) {
    return 'Delete $kind \"$name\"?';
  }

  @override
  String get treeDeletedContentRecoverable =>
      'Deleted content remains recoverable from local version history.';

  @override
  String get treeWorkspaceRoot => '(workspace root)';

  @override
  String get treeMoveDestinationTitle => 'Move to which directory?';

  @override
  String treeActionFailed(String error) {
    return 'The action failed: $error';
  }

  @override
  String get codeCopy => 'Copy';

  @override
  String get codeCopied => 'Copied';

  @override
  String get recoveryLabel => 'Recovered';

  @override
  String get recoveryDrafts => 'Recovered drafts';

  @override
  String get recoveryDescription =>
      'Unsaved changes were recovered from a previous session.';

  @override
  String get recoveryDismiss => 'Dismiss notice';

  @override
  String get writeEditNotSaved => 'Edit not saved yet';

  @override
  String writeEditNotSavedDescription(String error) {
    return 'Your latest edit could not be saved yet ($error). Your text is still here; saving retries automatically.';
  }

  @override
  String get writeStatusUnavailable => 'Write status unavailable';

  @override
  String get writeStatusUnavailableDescription =>
      'The note\'s save status cannot be checked right now. Your latest edits may not be written to disk yet; checking continues automatically.';

  @override
  String get writeRevisionMismatch =>
      'This note changed on disk while you were editing (revision mismatch), so your latest text could not be written.';

  @override
  String get writeDiskFull =>
      'The disk is full. Changes cannot be saved until space is freed.';

  @override
  String writeFailed(String error) {
    return 'Writing the note failed: $error';
  }

  @override
  String get writeFailure => 'Write failure';

  @override
  String get writeReloadFromDisk => 'Reload from disk';

  @override
  String get writeReloadFromDiskTitle => 'Reload from disk?';

  @override
  String get writeReloadFromDiskDescription =>
      'Reloading discards your buffered text — everything you have typed that was not written to disk. The file changed while you were editing, so reloading cannot keep it.';

  @override
  String get writeKeepEditing => 'Keep editing';

  @override
  String get writeDiscardAndReload => 'Discard and reload';

  @override
  String get searchIconLabel => 'Search';

  @override
  String get searchNotesHint => 'Search notes';

  @override
  String get searchTypePrompt => 'Type to search your notes';

  @override
  String get searchNoMatches => 'No matching notes';

  @override
  String get searchErrorLabel => 'Error';

  @override
  String get searchFailed => 'Search failed';

  @override
  String get searchRescanHint =>
      'If this keeps happening, run \"Rescan workspace\" to rebuild the search index.';
}
