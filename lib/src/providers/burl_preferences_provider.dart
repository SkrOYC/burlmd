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
    if (_persistenceBlocked) return BurlPreferences.defaults();
    final file = await _preferencesFile();

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
    } catch (error, stackTrace) {
      _persistenceBlocked = true;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> save(BurlPreferences preferences) async {
    File? temporary;
    try {
      await load();
      if (_persistenceBlocked) {
        throw StateError(
          'Device preferences are preserved and cannot be saved.',
        );
      }
      final file = await _preferencesFile();
      if (await _hasPreservedPayload(file.parent)) {
        _persistenceBlocked = true;
        throw StateError(
          'Device preferences are preserved and cannot be saved.',
        );
      }
      await file.parent.create(recursive: true);
      temporary = File(
        '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-${_nextTemporaryFile++}',
      );
      await writeTemporaryFile(temporary, jsonEncode(preferences.toJson()));
      await renameTemporaryFile(temporary, file.path);
    } catch (error, stackTrace) {
      if (temporary != null) {
        try {
          if (await temporary.exists()) await temporary.delete();
        } catch (_) {
          // A failed cleanup does not change the persisted preference state.
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Writes a complete temporary payload before it replaces the destination.
  ///
  /// This is overridable so regression tests can deterministically exercise
  /// write failures without depending on host filesystem permissions.
  Future<void> writeTemporaryFile(File file, String contents) =>
      file.writeAsString(contents, flush: true);

  /// Atomically promotes a completed temporary payload to the destination.
  ///
  /// This is overridable so regression tests can deterministically exercise
  /// rename failures without depending on host filesystem permissions.
  Future<File> renameTemporaryFile(File temporary, String destination) =>
      temporary.rename(destination);

  Future<File> _preferencesFile() async {
    final directory = await applicationSupportDirectory();
    return File('${directory.path}/$fileName');
  }

  Future<bool> _hasPreservedPayload(Directory directory) async {
    if (!await directory.exists()) return false;
    await for (final entity in directory.list()) {
      if (entity is File &&
          entity.uri.pathSegments.last.startsWith(_quarantineMarker)) {
        return true;
      }
    }
    return false;
  }

  /// Produces the next same-directory quarantine filename to reserve.
  ///
  /// Keeping this overridable permits deterministic collision coverage without
  /// relying on wall-clock timing.
  String nextQuarantinePath(File file) =>
      '${file.path}.quarantine-${DateTime.now().microsecondsSinceEpoch}-${_nextTemporaryFile++}';

  /// Exclusively reserves a quarantine filename before its payload is moved.
  ///
  /// `File.rename` replaces an existing file, so [_quarantine] only ever
  /// replaces the empty file this method just created. This is overridable for
  /// deterministic filesystem-failure coverage.
  Future<File> createQuarantineReservation(File destination) =>
      destination.create(exclusive: true);

  Future<void> _quarantine(File file) async {
    _persistenceBlocked = true;
    try {
      while (true) {
        final destination = File(nextQuarantinePath(file));
        try {
          await createQuarantineReservation(destination);
        } on PathExistsException {
          // A previous process owns this name; reserve a distinct one.
          continue;
        }
        await file.rename(destination.path);
        return;
      }
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

/// The most recent unresolved device-preference persistence failure.
///
/// A null value means there is no known pending failure. The controller clears
/// a prior failure after a later write succeeds, so orderly exit can retry a
/// transient filesystem error without treating preserved legacy data as one.
class PreferencesPersistenceFailure extends Notifier<Object?> {
  @override
  Object? build() => null;

  void report(Object error) => state = error;

  void clear() => state = null;
}

final preferencesPersistenceFailureProvider =
    NotifierProvider<PreferencesPersistenceFailure, Object?>(
      PreferencesPersistenceFailure.new,
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
  var _hasFailedWrite = false;

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

  /// Waits for restoration and every admitted write.
  ///
  /// Setters report failures instead of completing with an error because UI
  /// callbacks invoke them without awaiting. Callers that need an orderly
  /// shutdown use this method to surface any unresolved failure explicitly.
  Future<void> flushPendingWrites() async {
    await _restoration;
    await _drainWrites();
    if (_hasFailedWrite) {
      // A failed setter is acknowledged by its caller without throwing. Give
      // transient storage failures one exit-time retry, through the same tail.
      // A further failure stays visible; this deliberately does not loop.
      _enqueuePersistence();
      await _drainWrites();
    }
    final failure = ref.read(preferencesPersistenceFailureProvider);
    if (failure != null) throw failure;
  }

  Future<void> _drainWrites() async {
    while (true) {
      final writes = _writes;
      await writes;
      // Setters replace the tail synchronously, including while this await is
      // pending. Keep draining until no later admitted write remains.
      if (identical(writes, _writes)) return;
    }
  }

  Future<void> _restore() async {
    try {
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
    } catch (error) {
      _reportPersistenceFailure(error);
    }
  }

  Future<void> _update(
    BurlPreferences preferences,
    _PreferenceField changedField,
  ) {
    _locallyChanged.add(changedField);
    state = preferences;
    _enqueuePersistence();
    return _writes;
  }

  void _enqueuePersistence() {
    _writes = _writes.then(
      (_) async {
        await _restoration;
        await _persist(state);
      },
      onError: (_, _) async {
        await _restoration;
        await _persist(state);
      },
    );
  }

  Future<void> _persist(BurlPreferences preferences) async {
    try {
      await _store.save(preferences);
      _hasFailedWrite = false;
      _clearPersistenceFailure();
    } catch (error) {
      _hasFailedWrite = true;
      _reportPersistenceFailure(error);
    }
  }

  void _reportPersistenceFailure(Object error) {
    if (!ref.mounted) return;
    ref.read(preferencesPersistenceFailureProvider.notifier).report(error);
  }

  void _clearPersistenceFailure() {
    if (!ref.mounted) return;
    ref.read(preferencesPersistenceFailureProvider.notifier).clear();
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
