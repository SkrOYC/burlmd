// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

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
  String get workspaceDesktopPlatformChrome => 'Desktop platform chrome';

  @override
  String get workspaceFocusMode => 'Focus Mode (Zen)';

  @override
  String get workspaceFocusModeDescription =>
      'Dim non-active blocks while editing';

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
  String get platformChromeMacos => 'macOS';

  @override
  String get platformChromeLinux => 'Linux';

  @override
  String get platformChromeMinimal => 'Minimal';

  @override
  String get syncInspectorTitle => 'Sync & Storage';

  @override
  String get syncCloseInspector => 'Close sync inspector';

  @override
  String get syncBranch => 'main';

  @override
  String syncInspectorPath(String path) {
    return 'Path: $path';
  }

  @override
  String get syncLocalOrigin => 'Origin: Local only';

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
      'Local files on disk without a configured remote origin.';

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
}
