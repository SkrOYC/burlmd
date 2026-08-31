import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:burlmd/src/design/burl_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Resolves the Platform-owned application-support directory.
typedef ApplicationSupportDirectory = Future<Directory> Function();

/// Persists the versioned device-preferences payload outside Workspaces.
///
/// The store writes a sibling temporary file before atomically renaming it
/// into place. Invalid payloads are isolated before callers receive defaults,
/// so a bad local file can never stop the shell from starting.
class DevicePreferencesStore {
  DevicePreferencesStore({required this.applicationSupportDirectory});

  static const fileName = 'device-preferences.json';

  final ApplicationSupportDirectory applicationSupportDirectory;
  var _nextTemporaryFile = 0;

  Future<BurlPreferences> load() async {
    final file = await _preferencesFileOrNull();
    if (file == null) return BurlPreferences.defaults();

    try {
      if (!await file.exists()) return BurlPreferences.defaults();
      final payload = BurlPreferences.fromJson(
        jsonDecode(utf8.decode(await file.readAsBytes())),
      );
      if (payload == null) throw const FormatException('Invalid preferences');
      return payload;
    } on FormatException {
      await _isolateCorruptFile(file);
      return BurlPreferences.defaults();
    } catch (_) {
      // The Platform directory can be unavailable (including in a restricted
      // test or desktop session). Defaults keep the application usable.
      return BurlPreferences.defaults();
    }
  }

  Future<void> save(BurlPreferences preferences) async {
    File? temporary;
    try {
      final file = await _preferencesFileOrNull();
      if (file == null) return;
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
      // A failed best-effort preference write must not destabilize editing.
      if (temporary != null) {
        try {
          if (await temporary.exists()) await temporary.delete();
        } catch (_) {
          // Nothing more can be done without obscuring the user's change.
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

  Future<void> _isolateCorruptFile(File file) async {
    final isolated = File(
      '${file.path}.corrupt-${DateTime.now().microsecondsSinceEpoch}-${_nextTemporaryFile++}',
    );
    try {
      await file.rename(isolated.path);
    } catch (_) {
      // The corrupt bytes remain inaccessible to this process if the rename
      // cannot complete; loading still safely falls back to defaults.
    }
  }
}

final devicePreferencesStoreProvider = Provider<DevicePreferencesStore>(
  (ref) => DevicePreferencesStore(
    applicationSupportDirectory: getApplicationSupportDirectory,
  ),
);

/// Owns the user's device-global editor presentation preferences.
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
