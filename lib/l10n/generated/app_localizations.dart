import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Application title shown by the operating system.
  ///
  /// In en, this message translates to:
  /// **'burlmd'**
  String get appTitle;

  /// Accessible label for the internal link completion results.
  ///
  /// In en, this message translates to:
  /// **'Link completion'**
  String get linkCompletionLabel;

  /// Accessible label for an existing-note completion candidate.
  ///
  /// In en, this message translates to:
  /// **'Link to existing note {title}'**
  String linkCompletionExisting(String title);

  /// Accessible label for a prospective, not-yet-created completion candidate.
  ///
  /// In en, this message translates to:
  /// **'Create and link new note {title}'**
  String linkCompletionProspective(String title);

  /// Visible badge identifying a prospective link completion candidate.
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get linkCompletionProspectiveBadge;

  /// Accessible label for an internal link whose cached render state is existing.
  ///
  /// In en, this message translates to:
  /// **'Open linked note {title}'**
  String internalLinkExisting(String title);

  /// Accessible label for an internal link whose cached render state is missing.
  ///
  /// In en, this message translates to:
  /// **'Open missing linked note {title}'**
  String internalLinkMissing(String title);

  /// Title of the create-on-follow confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Create linked note?'**
  String get createLinkedNoteTitle;

  /// Body of the create-on-follow confirmation dialog using Core-derived values.
  ///
  /// In en, this message translates to:
  /// **'Create {title} in {directoryPath}?'**
  String createLinkedNoteBody(String title, String directoryPath);

  /// Confirmation action for creating a missing linked note.
  ///
  /// In en, this message translates to:
  /// **'Create note'**
  String get createLinkedNoteConfirm;

  /// Cancellation action for create-on-follow.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get createLinkedNoteCancel;

  /// Dismissible status message after resolving or creating a linked note fails while the source note stays open.
  ///
  /// In en, this message translates to:
  /// **'Could not complete the linked-note action: {error}'**
  String linkOperationFailed(String error);

  /// Dismissible status message when closing the current note fails and its editor remains available.
  ///
  /// In en, this message translates to:
  /// **'Could not switch notes: {error}'**
  String noteCloseFailed(String error);

  /// Dismissible status message after a Note or Directory lifecycle operation completes but Git cannot record it.
  ///
  /// In en, this message translates to:
  /// **'The change is applied, but its Git commit failed: {detail}'**
  String lifecycleCommitWarning(String detail);

  /// Dismissible status message after a lifecycle operation completes but Core cannot finish a post-publication cleanup step.
  ///
  /// In en, this message translates to:
  /// **'The change is applied, but cleanup could not finish: {detail}'**
  String lifecycleSettlementWarning(String detail);

  /// Dismissible status message when a retryable editor operation fails while the current note stays open.
  ///
  /// In en, this message translates to:
  /// **'Could not complete the editor operation: {error}'**
  String editorOperationFailed(String error);

  /// Label for the workspace search command.
  ///
  /// In en, this message translates to:
  /// **'Search notes…'**
  String get workspaceSearchNotes;

  /// Tooltip for the workspace search command.
  ///
  /// In en, this message translates to:
  /// **'Search notes'**
  String get workspaceSearchNotesTooltip;

  /// Displayed search shortcut on macOS.
  ///
  /// In en, this message translates to:
  /// **'⌘K'**
  String get workspaceSearchShortcutMacos;

  /// Displayed search shortcut on non-macOS desktop platforms.
  ///
  /// In en, this message translates to:
  /// **'Ctrl+K'**
  String get workspaceSearchShortcutControl;

  /// Accessible label for dismissing a modal workspace overlay.
  ///
  /// In en, this message translates to:
  /// **'Dismiss overlay'**
  String get workspaceDismissOverlay;

  /// Label for the local workspace inspector command.
  ///
  /// In en, this message translates to:
  /// **'Local workspace'**
  String get workspaceLocalWorkspace;

  /// Label for the preferences command.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get workspacePreferences;

  /// Tooltip for opening the compact workspace navigator.
  ///
  /// In en, this message translates to:
  /// **'Open navigator'**
  String get workspaceOpenNavigator;

  /// Tooltip for collapsing the wide workspace navigator.
  ///
  /// In en, this message translates to:
  /// **'Collapse sidebar'**
  String get workspaceCollapseSidebar;

  /// Fallback path shown before a note is selected.
  ///
  /// In en, this message translates to:
  /// **'workspace'**
  String get workspaceDefaultPath;

  /// Initial visual tab name before a note is selected.
  ///
  /// In en, this message translates to:
  /// **'Welcome.md'**
  String get workspaceWelcomeTab;

  /// Name for a newly added visual-only tab.
  ///
  /// In en, this message translates to:
  /// **'Untitled {number}.md'**
  String workspaceUntitledTab(int number);

  /// Tooltip for adding a local visual-only tab.
  ///
  /// In en, this message translates to:
  /// **'Add visual tab'**
  String get workspaceAddVisualTab;

  /// Tab context-menu action.
  ///
  /// In en, this message translates to:
  /// **'Close tab'**
  String get workspaceCloseTab;

  /// Tab context-menu action.
  ///
  /// In en, this message translates to:
  /// **'Close other tabs'**
  String get workspaceCloseOtherTabs;

  /// Tab context-menu action that preserves provider-owned note tabs.
  ///
  /// In en, this message translates to:
  /// **'Close all visual tabs'**
  String get workspaceCloseAllVisualTabs;

  /// Accessible label for a workspace tab.
  ///
  /// In en, this message translates to:
  /// **'{title} tab'**
  String workspaceTabLabel(String title);

  /// Tooltip for closing a named workspace tab.
  ///
  /// In en, this message translates to:
  /// **'Close {title}'**
  String workspaceCloseNamedTab(String title);

  /// One startup report listing saved Note identities Core could not reopen.
  ///
  /// In en, this message translates to:
  /// **'Could not restore saved notes: {noteIds}'**
  String workspaceRestoreSavedNotes(String noteIds);

  /// Tooltip shown after copying the current note path.
  ///
  /// In en, this message translates to:
  /// **'Copied path'**
  String get workspaceCopiedPath;

  /// Tooltip for copying the current note path.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get workspaceCopyPath;

  /// Label and tooltip for the note history command.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get workspaceHistory;

  /// Breadcrumb used for a root-level note or workspace path.
  ///
  /// In en, this message translates to:
  /// **'Workspace  ›  {path}'**
  String workspaceBreadcrumb(String path);

  /// Fallback note modification summary.
  ///
  /// In en, this message translates to:
  /// **'Modified recently'**
  String get workspaceModifiedRecently;

  /// Recent note modification summary.
  ///
  /// In en, this message translates to:
  /// **'Modified just now'**
  String get workspaceModifiedJustNow;

  /// Note modification summary measured in minutes.
  ///
  /// In en, this message translates to:
  /// **'Modified {minutes}m ago'**
  String workspaceModifiedMinutesAgo(int minutes);

  /// Note modification summary measured in hours.
  ///
  /// In en, this message translates to:
  /// **'Modified {hours}h ago'**
  String workspaceModifiedHoursAgo(int hours);

  /// Note modification summary measured in days.
  ///
  /// In en, this message translates to:
  /// **'Modified {days}d ago'**
  String workspaceModifiedDaysAgo(int days);

  /// Compact current-note summary.
  ///
  /// In en, this message translates to:
  /// **'{modified} · {words} {wordLabel}'**
  String workspaceNoteSummary(String modified, int words, String wordLabel);

  /// Singular word-count unit.
  ///
  /// In en, this message translates to:
  /// **'word'**
  String get workspaceWordSingular;

  /// Plural word-count unit.
  ///
  /// In en, this message translates to:
  /// **'words'**
  String get workspaceWordPlural;

  /// Empty editor title.
  ///
  /// In en, this message translates to:
  /// **'Select a note to open it'**
  String get workspaceSelectNoteTitle;

  /// Empty editor explanatory text.
  ///
  /// In en, this message translates to:
  /// **'Choose a note from the directory tree to begin writing.'**
  String get workspaceSelectNoteBody;

  /// Tooltip for closing the search palette.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get workspaceCloseSearch;

  /// Preferences drawer title.
  ///
  /// In en, this message translates to:
  /// **'Editor Preferences'**
  String get workspaceEditorPreferences;

  /// Preferences section label for the app theme.
  ///
  /// In en, this message translates to:
  /// **'Appearance theme'**
  String get workspaceAppearanceTheme;

  /// Preferences section label for prose font size.
  ///
  /// In en, this message translates to:
  /// **'Base reading size'**
  String get workspaceBaseReadingSize;

  /// Preferences section label for prose width.
  ///
  /// In en, this message translates to:
  /// **'Prose line measure'**
  String get workspaceProseLineMeasure;

  /// Preferences toggle title for focus mode.
  ///
  /// In en, this message translates to:
  /// **'Focus Mode (Zen)'**
  String get workspaceFocusMode;

  /// Preferences toggle description for focus mode.
  ///
  /// In en, this message translates to:
  /// **'Dim non-active blocks while editing'**
  String get workspaceFocusModeDescription;

  /// Preferences toggle title for release-update notifications.
  ///
  /// In en, this message translates to:
  /// **'Update notifications'**
  String get workspaceUpdateNotifications;

  /// Preferences toggle description for release-update notifications.
  ///
  /// In en, this message translates to:
  /// **'Notify me about compatible new releases'**
  String get workspaceUpdateNotificationsDescription;

  /// Generic close or completion action in workspace surfaces.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get workspaceDone;

  /// Theme preference that follows the operating system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themePreferenceSystem;

  /// Light theme preference.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themePreferenceLight;

  /// Dark theme preference.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themePreferenceDark;

  /// Compact editor font-scale preference.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get fontScaleCompact;

  /// Standard editor font-scale preference.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get fontScaleStandard;

  /// Comfortable editor font-scale preference.
  ///
  /// In en, this message translates to:
  /// **'Comfortable'**
  String get fontScaleComfortable;

  /// Large editor font-scale preference.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get fontScaleLarge;

  /// Narrow prose line-measure preference.
  ///
  /// In en, this message translates to:
  /// **'55ch · Narrow reading'**
  String get measureNarrow;

  /// Standard prose line-measure preference.
  ///
  /// In en, this message translates to:
  /// **'65ch · Standard prose'**
  String get measureStandard;

  /// Wide prose line-measure preference.
  ///
  /// In en, this message translates to:
  /// **'75ch · Wide'**
  String get measureWide;

  /// Technical prose line-measure preference.
  ///
  /// In en, this message translates to:
  /// **'85ch · Code & tables'**
  String get measureTechnical;

  /// Full-width prose line-measure preference.
  ///
  /// In en, this message translates to:
  /// **'Full width'**
  String get measureFull;

  /// Title of the local workspace inspector.
  ///
  /// In en, this message translates to:
  /// **'Sync & Storage'**
  String get syncInspectorTitle;

  /// Tooltip for closing the local workspace inspector.
  ///
  /// In en, this message translates to:
  /// **'Close sync inspector'**
  String get syncCloseInspector;

  /// Actual local workspace path shown by the inspector.
  ///
  /// In en, this message translates to:
  /// **'Path: {path}'**
  String syncInspectorPath(String path);

  /// Repository remote state when Core has no configured remote.
  ///
  /// In en, this message translates to:
  /// **'Remote: Not configured'**
  String get syncRemoteNotConfigured;

  /// Honest production note for deferred remote status support.
  ///
  /// In en, this message translates to:
  /// **'Remote sync status becomes available when the Core exposes it.'**
  String get syncStatusUnavailable;

  /// Action that refreshes only the local workspace index.
  ///
  /// In en, this message translates to:
  /// **'Rescan workspace'**
  String get syncRescanWorkspace;

  /// Local visual state label for a synchronized workspace.
  ///
  /// In en, this message translates to:
  /// **'In Sync'**
  String get syncStateInSync;

  /// Local visual state label for pending review.
  ///
  /// In en, this message translates to:
  /// **'1 Pending Suggestion'**
  String get syncStatePendingSuggestion;

  /// Local visual state label for syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get syncStateSyncing;

  /// Local visual state label for a workspace without a remote.
  ///
  /// In en, this message translates to:
  /// **'Local Only'**
  String get syncStateLocalOnly;

  /// Local visual state label for disconnected state.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get syncStateOffline;

  /// Local visual state label for missing credentials.
  ///
  /// In en, this message translates to:
  /// **'Auth Required'**
  String get syncStateAuthRequired;

  /// Local visual state label for an unreachable remote.
  ///
  /// In en, this message translates to:
  /// **'Unreachable'**
  String get syncStateUnreachable;

  /// Local visual state label for filesystem changes.
  ///
  /// In en, this message translates to:
  /// **'External Changes'**
  String get syncStateExternalChanges;

  /// Description for the synchronized visual state.
  ///
  /// In en, this message translates to:
  /// **'All notes match the remote Git repository.'**
  String get syncDescriptionInSync;

  /// Description for the pending-review visual state.
  ///
  /// In en, this message translates to:
  /// **'A remote change is ready for in-line block review.'**
  String get syncDescriptionPendingSuggestion;

  /// Description for the syncing visual state.
  ///
  /// In en, this message translates to:
  /// **'Synchronizing with the remote repository.'**
  String get syncDescriptionSyncing;

  /// Description for the local-only visual state.
  ///
  /// In en, this message translates to:
  /// **'Local files on disk without a configured Remote.'**
  String get syncDescriptionLocalOnly;

  /// Description for the offline visual state.
  ///
  /// In en, this message translates to:
  /// **'Working locally; Burl will sync again when reconnected.'**
  String get syncDescriptionOffline;

  /// Description for the authentication-required visual state.
  ///
  /// In en, this message translates to:
  /// **'An SSH key or access token is required.'**
  String get syncDescriptionAuthRequired;

  /// Description for the unreachable visual state.
  ///
  /// In en, this message translates to:
  /// **'The configured remote could not be reached.'**
  String get syncDescriptionUnreachable;

  /// Description for the external-changes visual state.
  ///
  /// In en, this message translates to:
  /// **'Files on disk were updated by another application.'**
  String get syncDescriptionExternalChanges;

  /// Title for the history drawer.
  ///
  /// In en, this message translates to:
  /// **'Git History'**
  String get historyTitle;

  /// Honest production history unavailable state.
  ///
  /// In en, this message translates to:
  /// **'No snapshots are available yet. Git history will appear here when the Core exposes note snapshots.'**
  String get historyNoSnapshotsAvailable;

  /// History drawer persistence note.
  ///
  /// In en, this message translates to:
  /// **'Stored in .git/'**
  String get historyStoredInGit;

  /// Workspace tree action to create a note.
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get treeNewNote;

  /// Workspace tree action to create a directory.
  ///
  /// In en, this message translates to:
  /// **'New directory'**
  String get treeNewDirectory;

  /// Text-field label for a note title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get treeTitle;

  /// Text-field label for a directory name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get treeName;

  /// Accessible label for the workspace directory section.
  ///
  /// In en, this message translates to:
  /// **'Directories'**
  String get treeDirectories;

  /// Visible uppercase workspace directory section heading.
  ///
  /// In en, this message translates to:
  /// **'DIRECTORIES'**
  String get treeDirectoriesHeading;

  /// Workspace tree load failure state.
  ///
  /// In en, this message translates to:
  /// **'Failed to load workspace tree'**
  String get treeFailedToLoad;

  /// Retry a failed workspace tree load or search.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get treeRetry;

  /// Accessible label for an expanded directory icon.
  ///
  /// In en, this message translates to:
  /// **'Expanded directory'**
  String get treeExpandedDirectory;

  /// Accessible label for a directory icon.
  ///
  /// In en, this message translates to:
  /// **'Directory'**
  String get treeDirectory;

  /// Lowercase directory noun in a delete confirmation.
  ///
  /// In en, this message translates to:
  /// **'directory'**
  String get treeDirectoryKind;

  /// Accessible label for a note icon.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get treeNote;

  /// Lowercase note noun in a delete confirmation.
  ///
  /// In en, this message translates to:
  /// **'note'**
  String get treeNoteKind;

  /// Tooltip for a directory overflow menu.
  ///
  /// In en, this message translates to:
  /// **'Actions for directory {name}'**
  String treeDirectoryActions(String name);

  /// Tooltip for a note overflow menu.
  ///
  /// In en, this message translates to:
  /// **'Actions for note {title}'**
  String treeNoteActions(String title);

  /// Directory context-menu action.
  ///
  /// In en, this message translates to:
  /// **'New note here'**
  String get treeNewNoteHere;

  /// Directory context-menu action.
  ///
  /// In en, this message translates to:
  /// **'New subdirectory'**
  String get treeNewSubdirectory;

  /// Workspace tree context-menu action.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get treeRename;

  /// Workspace tree destructive action.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get treeDelete;

  /// Note context-menu move action.
  ///
  /// In en, this message translates to:
  /// **'Move to directory…'**
  String get treeMoveToDirectory;

  /// Create-note dialog title for a directory.
  ///
  /// In en, this message translates to:
  /// **'New note in \"{name}\"'**
  String treeNewNoteInDirectory(String name);

  /// Create-directory dialog title for a directory.
  ///
  /// In en, this message translates to:
  /// **'New subdirectory in \"{name}\"'**
  String treeNewSubdirectoryInDirectory(String name);

  /// Rename-directory dialog title.
  ///
  /// In en, this message translates to:
  /// **'Rename directory \"{name}\"'**
  String treeRenameDirectory(String name);

  /// Text-field label for a renamed directory.
  ///
  /// In en, this message translates to:
  /// **'New name'**
  String get treeNewName;

  /// Rename-note dialog title.
  ///
  /// In en, this message translates to:
  /// **'Rename note'**
  String get treeRenameNote;

  /// Text-field label for a renamed note.
  ///
  /// In en, this message translates to:
  /// **'New title'**
  String get treeNewTitle;

  /// Delete-directory confirmation consequence.
  ///
  /// In en, this message translates to:
  /// **'Every note inside \"{name}\" is deleted with it. They stay recoverable from local version history.'**
  String treeDeleteDirectoryConsequence(String name);

  /// Delete-note confirmation consequence.
  ///
  /// In en, this message translates to:
  /// **'It stays recoverable from local version history, but links elsewhere that pointed at it will no longer resolve.'**
  String get treeDeleteNoteConsequence;

  /// Cancel a lifecycle dialog.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get treeCancel;

  /// Confirm entered lifecycle dialog text.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get treeConfirm;

  /// Delete confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Delete {kind} \"{name}\"?'**
  String treeDeleteNamed(String kind, String name);

  /// Delete confirmation safety note.
  ///
  /// In en, this message translates to:
  /// **'Deleted content remains recoverable from local version history.'**
  String get treeDeletedContentRecoverable;

  /// Move dialog label for the workspace root.
  ///
  /// In en, this message translates to:
  /// **'(workspace root)'**
  String get treeWorkspaceRoot;

  /// Move-note destination dialog title.
  ///
  /// In en, this message translates to:
  /// **'Move to which directory?'**
  String get treeMoveDestinationTitle;

  /// Lifecycle action failure status.
  ///
  /// In en, this message translates to:
  /// **'The action failed: {error}'**
  String treeActionFailed(String error);

  /// Code-block copy button label.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get codeCopy;

  /// Code-block copy feedback label.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get codeCopied;

  /// Accessible label for recovered-draft indicator.
  ///
  /// In en, this message translates to:
  /// **'Recovered'**
  String get recoveryLabel;

  /// Recovered-drafts panel title.
  ///
  /// In en, this message translates to:
  /// **'Recovered drafts'**
  String get recoveryDrafts;

  /// Recovered-draft row description.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes were recovered from a previous session.'**
  String get recoveryDescription;

  /// Tooltip to hide a recovered-draft notice.
  ///
  /// In en, this message translates to:
  /// **'Dismiss notice'**
  String get recoveryDismiss;

  /// Accessible label for a transient write failure.
  ///
  /// In en, this message translates to:
  /// **'Edit not saved yet'**
  String get writeEditNotSaved;

  /// Transient write failure explanation.
  ///
  /// In en, this message translates to:
  /// **'Your latest edit could not be saved yet ({error}). Your text is still here; saving retries automatically.'**
  String writeEditNotSavedDescription(String error);

  /// Accessible label for unavailable write status.
  ///
  /// In en, this message translates to:
  /// **'Write status unavailable'**
  String get writeStatusUnavailable;

  /// Unavailable write status explanation.
  ///
  /// In en, this message translates to:
  /// **'The note\'s save status cannot be checked right now. Your latest edits may not be written to disk yet; checking continues automatically.'**
  String get writeStatusUnavailableDescription;

  /// Revision mismatch write failure explanation.
  ///
  /// In en, this message translates to:
  /// **'This note changed on disk while you were editing (revision mismatch), so your latest text could not be written.'**
  String get writeRevisionMismatch;

  /// Disk-full write failure explanation.
  ///
  /// In en, this message translates to:
  /// **'The disk is full. Changes cannot be saved until space is freed.'**
  String get writeDiskFull;

  /// Generic write failure explanation.
  ///
  /// In en, this message translates to:
  /// **'Writing the note failed: {error}'**
  String writeFailed(String error);

  /// Accessible label for a write failure.
  ///
  /// In en, this message translates to:
  /// **'Write failure'**
  String get writeFailure;

  /// Action to reload a changed note from disk.
  ///
  /// In en, this message translates to:
  /// **'Reload from disk'**
  String get writeReloadFromDisk;

  /// Reload confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Reload from disk?'**
  String get writeReloadFromDiskTitle;

  /// Reload confirmation explanation.
  ///
  /// In en, this message translates to:
  /// **'Reloading discards your buffered text — everything you have typed that was not written to disk. The file changed while you were editing, so reloading cannot keep it.'**
  String get writeReloadFromDiskDescription;

  /// Cancel reload and keep buffered edits.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get writeKeepEditing;

  /// Confirm reload and discard buffered edits.
  ///
  /// In en, this message translates to:
  /// **'Discard and reload'**
  String get writeDiscardAndReload;

  /// Accessible label for a search icon.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchIconLabel;

  /// Search field hint.
  ///
  /// In en, this message translates to:
  /// **'Search notes'**
  String get searchNotesHint;

  /// Empty search state prompt.
  ///
  /// In en, this message translates to:
  /// **'Type to search your notes'**
  String get searchTypePrompt;

  /// Search state with no matching notes.
  ///
  /// In en, this message translates to:
  /// **'No matching notes'**
  String get searchNoMatches;

  /// Accessible label for search error icon.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get searchErrorLabel;

  /// Search error heading.
  ///
  /// In en, this message translates to:
  /// **'Search failed'**
  String get searchFailed;

  /// Search error recovery guidance.
  ///
  /// In en, this message translates to:
  /// **'If this keeps happening, run \"Rescan workspace\" to rebuild the search index.'**
  String get searchRescanHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
