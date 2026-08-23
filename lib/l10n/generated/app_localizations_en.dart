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
}
