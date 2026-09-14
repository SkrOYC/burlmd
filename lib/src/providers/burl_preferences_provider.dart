import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:burlmd/src/design/burl_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Resolves the Platform-owned application-support directory.
typedef ApplicationSupportDirectory = Future<Directory> Function();

/// Persists versioned device preferences outside every Workspace.
///
/// A valid payload replaces the existing file atomically. A corrupt or unsupported
/// payload is moved aside byte-for-byte and permanently blocks writes in that
/// application-support directory. BURL-O005 owns any future recovery path.
class DevicePreferencesStore {
  DevicePreferencesStore({required this.applicationSupportDirectory});

  static const fileName = 'device-preferences.json';
  static const _quarantineMarker = '$fileName.quarantine-';

  final ApplicationSupportDirectory applicationSupportDirectory;
  var _nextTemporaryFile = 0;
  var _persistenceBlocked = false;

  Future<BurlPreferences> load() async {
    final file = await _preferencesFileOrNull();
    if (file == null) {
      _persistenceBlocked = true;
      return BurlPreferences.defaults();
    }
    if (_persistenceBlocked) return BurlPreferences.defaults();

    try {
      if (await _hasPreservedPayload(file.parent)) {
        _persistenceBlocked = true;
        return BurlPreferences.defaults();
      }
      if (!await file.exists()) return BurlPreferences.defaults();
      return BurlPreferences.fromJson(
        jsonDecode(utf8.decode(await file.readAsBytes())),
      );
    } on FormatException {
      await _quarantine(file);
      return BurlPreferences.defaults();
    } catch (_) {
      _persistenceBlocked = true;
      return BurlPreferences.defaults();
    }
  }

  Future<void> save(BurlPreferences preferences) async {
    File? temporary;
    try {
      await load();
      if (_persistenceBlocked) return;
      final file = await _preferencesFileOrNull();
      if (file == null || _persistenceBlocked) return;
      if (await _hasPreservedPayload(file.parent)) {
        _persistenceBlocked = true;
        return;
      }
      await file.parent.create(recursive: true);
      temporary = File(
        '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-${_nextTemporaryFile++}',
      );
      await temporary.writeAsString(
        jsonEncode(preferences.toJson()),
        flush: true,
      );
      await temporary.rename(file.path);
    } catch (_) {
      if (temporary != null) {
        try {
          if (await temporary.exists()) await temporary.delete();
        } catch (_) {
          // A failed cleanup does not change the persisted preference state.
        }
      }
    }
  }

  Future<File?> _preferencesFileOrNull() async {
    try {
      final directory = await applicationSupportDirectory();
      return File('${directory.path}/$fileName');
    } catch (_) {
      return null;
    }
  }

  Future<bool> _hasPreservedPayload(Directory directory) async {
    try {
      if (!await directory.exists()) return false;
      await for (final entity in directory.list()) {
        if (entity is File &&
            entity.uri.pathSegments.last.startsWith(_quarantineMarker)) {
          return true;
        }
      }
      return false;
    } catch (_) {
      // If the Platform cannot establish the directory contents, it must not
      // risk replacing bytes that could be a preserved payload.
      return true;
    }
  }

  Future<void> _quarantine(File file) async {
    _persistenceBlocked = true;
    try {
      await file.rename(
        '${file.path}.quarantine-${DateTime.now().microsecondsSinceEpoch}-${_nextTemporaryFile++}',
      );
    } catch (_) {
      // The original bytes remain in place. Later saves stay disabled.
    }
  }
}

final devicePreferencesStoreProvider = Provider<DevicePreferencesStore>(
  (ref) => DevicePreferencesStore(
    applicationSupportDirectory: getApplicationSupportDirectory,
  ),
);

/// Owns the user's in-session editor presentation preferences.
///
/// Theme tokens and the immutable preference value remain in the design
/// module; this provider is intentionally kept with the other application
/// state seams.
class BurlPreferencesController extends Notifier<BurlPreferences> {
  late final DevicePreferencesStore _store;
  late final Future<void> _restoration;
  Future<void> _writes = Future.value();
  final _locallyChanged = <_PreferenceField>{};

  @override
  BurlPreferences build() {
    _store = ref.read(devicePreferencesStoreProvider);
    _restoration = _restore();
    unawaited(_restoration);
    return BurlPreferences.defaults();
  }

  Future<void> setTheme(BurlThemePreference value) =>
      _update(state.copyWith(theme: value), _PreferenceField.theme);

  Future<void> setFontScale(BurlFontScale value) =>
      _update(state.copyWith(fontScale: value), _PreferenceField.fontScale);

  Future<void> setMeasure(BurlMeasure value) =>
      _update(state.copyWith(measure: value), _PreferenceField.measure);

  Future<void> setFocusMode(bool value) =>
      _update(state.copyWith(focusMode: value), _PreferenceField.focusMode);

  Future<void> setUpdateNotifications(bool value) => _update(
    state.copyWith(updateNotifications: value),
    _PreferenceField.updateNotifications,
  );

  Future<void> _restore() async {
    final restored = await _store.load();
    if (!ref.mounted) return;
    state = restored.copyWith(
      theme: _locallyChanged.contains(_PreferenceField.theme)
          ? state.theme
          : null,
      fontScale: _locallyChanged.contains(_PreferenceField.fontScale)
          ? state.fontScale
          : null,
      measure: _locallyChanged.contains(_PreferenceField.measure)
          ? state.measure
          : null,
      focusMode: _locallyChanged.contains(_PreferenceField.focusMode)
          ? state.focusMode
          : null,
      updateNotifications:
          _locallyChanged.contains(_PreferenceField.updateNotifications)
          ? state.updateNotifications
          : null,
    );
  }

  Future<void> _update(
    BurlPreferences preferences,
    _PreferenceField changedField,
  ) async {
    _locallyChanged.add(changedField);
    state = preferences;
    await _restoration;
    final current = state;
    _writes = _writes.then((_) => _store.save(current));
    await _writes;
  }
}

enum _PreferenceField {
  theme,
  fontScale,
  measure,
  focusMode,
  updateNotifications,
}

final burlPreferencesProvider =
    NotifierProvider<BurlPreferencesController, BurlPreferences>(
      BurlPreferencesController.new,
    );
