import 'dart:convert';
import 'dart:io';

import 'package:burlmd/src/design/burl_theme.dart';
import 'package:burlmd/src/providers/burl_preferences_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BurlPreferencesController', () {
    late Directory root;
    late Directory applicationSupport;
    late Directory workspace;
    late DevicePreferencesStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('burl-preferences-test.');
      applicationSupport = Directory('${root.path}/application-support');
      workspace = Directory('${root.path}/workspace');
      await workspace.create();
      store = DevicePreferencesStore(
        applicationSupportDirectory: () async => applicationSupport,
      );
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    ProviderContainer container() {
      final container = ProviderContainer(
        overrides: [devicePreferencesStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test(
      'round-trips every device preference across a new controller',
      () async {
        final first = container();
        final writer = first.read(burlPreferencesProvider.notifier);

        await writer.setTheme(BurlThemePreference.dark);
        await writer.setFontScale(BurlFontScale.spacious);
        await writer.setMeasure(BurlMeasure.technical);
        await writer.setFocusMode(true);
        await writer.setUpdateNotifications(false);

        final persisted = jsonDecode(
          await File(
            '${applicationSupport.path}/device-preferences.json',
          ).readAsString(),
        );
        expect(persisted, {
          'schema_version': 1,
          'theme': 'dark',
          'font_scale': 'spacious',
          'measure': 'technical',
          'focus_mode': true,
          'update_notifications': false,
        });

        final second = container();
        final initial = second.read(burlPreferencesProvider);
        expect(initial.theme, BurlThemePreference.system);
        expect(initial.fontScale, BurlFontScale.standard);
        expect(initial.measure, BurlMeasure.standard);
        expect(initial.focusMode, isFalse);
        expect(initial.updateNotifications, isTrue);

        await _waitForPreferences(
          second,
          (preferences) =>
              preferences.theme == BurlThemePreference.dark &&
              preferences.fontScale == BurlFontScale.spacious &&
              preferences.measure == BurlMeasure.technical &&
              preferences.focusMode &&
              !preferences.updateNotifications,
        );
      },
    );

    test('corrupt JSON falls back to defaults and isolates the file', () async {
      await applicationSupport.create(recursive: true);
      final file = File('${applicationSupport.path}/device-preferences.json');
      await file.writeAsBytes([0xff, 0xfe, 0xfd]);

      final restored = container();
      restored.read(burlPreferencesProvider);
      await _waitForFileToBeIsolated(file);
      await _waitForDefaults(restored);

      expect(await file.exists(), isFalse);
      expect(
        await applicationSupport
            .list()
            .where((entity) => entity is File)
            .map((entity) => entity.path)
            .any((path) => path.contains('device-preferences.json.corrupt-')),
        isTrue,
      );
    });

    test(
      'an unknown schema version falls back to defaults and isolates the file',
      () async {
        await applicationSupport.create(recursive: true);
        final file = File('${applicationSupport.path}/device-preferences.json');
        await file.writeAsString('''
        {"schema_version": 2, "theme": "dark", "font_scale": "spacious", "measure": "technical", "focus_mode": true, "update_notifications": false}
      ''');

        final restored = container();
        restored.read(burlPreferencesProvider);
        await _waitForFileToBeIsolated(file);
        await _waitForDefaults(restored);

        expect(await file.exists(), isFalse);
        expect(
          await applicationSupport
              .list()
              .where((entity) => entity is File)
              .map((entity) => entity.path)
              .any((path) => path.contains('device-preferences.json.corrupt-')),
          isTrue,
        );
      },
    );

    test(
      'persists outside the Workspace without preference keys in its files',
      () async {
        final workspaceFile = File('${workspace.path}/Note.md');
        await workspaceFile.writeAsString('# A workspace note');
        final writer = container().read(burlPreferencesProvider.notifier);

        await writer.setTheme(BurlThemePreference.dark);
        await writer.setUpdateNotifications(false);

        final preferenceFile = File(
          '${applicationSupport.path}/device-preferences.json',
        );
        expect(await preferenceFile.exists(), isTrue);
        expect(preferenceFile.path.startsWith(workspace.path), isFalse);

        await for (final entity in workspace.list(recursive: true)) {
          if (entity is! File) continue;
          final content = await entity.readAsString();
          expect(content, isNot(contains('update_notifications')));
          expect(content, isNot(contains('theme')));
        }
      },
    );
  });
}

Future<void> _waitForDefaults(ProviderContainer container) =>
    _waitForPreferences(
      container,
      (preferences) =>
          preferences.theme == BurlThemePreference.system &&
          preferences.fontScale == BurlFontScale.standard &&
          preferences.measure == BurlMeasure.standard &&
          !preferences.focusMode &&
          preferences.updateNotifications,
    );

Future<void> _waitForFileToBeIsolated(File file) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (!await file.exists()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TestFailure('corrupt preferences file was not isolated');
}

Future<void> _waitForPreferences(
  ProviderContainer container,
  bool Function(BurlPreferences preferences) matches,
) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (matches(container.read(burlPreferencesProvider))) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TestFailure('preferences were not restored');
}
