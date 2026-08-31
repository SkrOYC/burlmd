import 'dart:convert';
import 'dart:io';

import 'package:burlmd/src/design/burl_theme.dart';
import 'package:burlmd/src/providers/burl_preferences_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _devicePreferenceSchemaKeys = {
  'schema_version',
  'theme',
  'font_scale',
  'measure',
  'focus_mode',
  'update_notifications',
};

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
      await _git(workspace, ['init']);
      await _git(workspace, ['config', 'user.email', 'test@example.com']);
      await _git(workspace, ['config', 'user.name', 'Burlmd Test']);
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
      'persists outside the Workspace without preference keys or Git changes',
      () async {
        final workspaceFile = File('${workspace.path}/Note.md');
        await workspaceFile.writeAsString('# A workspace note');
        await _git(workspace, ['add', 'Note.md']);
        await _git(workspace, ['commit', '-m', 'Add workspace note']);
        final statusBeforePersist = await _git(workspace, [
          'status',
          '--porcelain',
        ]);
        expect(statusBeforePersist, isEmpty);

        final writer = container().read(burlPreferencesProvider.notifier);
        await writer.setTheme(BurlThemePreference.dark);
        await writer.setFontScale(BurlFontScale.spacious);
        await writer.setMeasure(BurlMeasure.technical);
        await writer.setFocusMode(true);
        await writer.setUpdateNotifications(false);

        final preferenceFile = File(
          '${applicationSupport.path}/device-preferences.json',
        );
        expect(await preferenceFile.exists(), isTrue);
        expect(preferenceFile.parent.path, applicationSupport.path);
        expect(await _filesNamed(root, 'device-preferences.json'), [
          preferenceFile.path,
        ]);

        final workspacePaths = <String>[];
        final workspaceContents = <String>[];
        await for (final entity in workspace.list(recursive: true)) {
          workspacePaths.add(entity.path);
          if (entity is File) {
            workspaceContents.add(
              utf8.decode(await entity.readAsBytes(), allowMalformed: true),
            );
          }
        }
        final gitDiff = await _git(workspace, ['diff', '--no-ext-diff']);
        final gitStatus = await _git(workspace, ['status', '--porcelain']);
        expect(gitStatus, statusBeforePersist);
        expect(gitStatus, isEmpty);

        for (final schemaKey in _devicePreferenceSchemaKeys) {
          expect(workspacePaths.join('\n'), isNot(contains(schemaKey)));
          expect(workspaceContents.join('\n'), isNot(contains(schemaKey)));
          expect(gitDiff, isNot(contains(schemaKey)));
          expect(gitStatus, isNot(contains(schemaKey)));
        }
      },
    );
  });
}

Future<List<String>> _filesNamed(Directory directory, String name) async {
  final paths = <String>[];
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File && entity.uri.pathSegments.last == name) {
      paths.add(entity.path);
    }
  }
  return paths;
}

Future<String> _git(Directory workspace, List<String> arguments) async {
  final result = await Process.run('git', ['-C', workspace.path, ...arguments]);
  if (result.exitCode != 0) {
    throw TestFailure('git ${arguments.join(' ')} failed:\n${result.stderr}');
  }
  return result.stdout as String;
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
