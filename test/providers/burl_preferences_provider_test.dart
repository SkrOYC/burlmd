import 'dart:async';
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

class _ControlledDevicePreferencesStore extends DevicePreferencesStore {
  _ControlledDevicePreferencesStore({
    required super.applicationSupportDirectory,
    this.writeFailure,
    this.renameFailure,
    this.loadGate,
  });

  Object? writeFailure;
  Object? renameFailure;
  Future<BurlPreferences>? loadGate;
  Completer<void>? renameStarted;
  Future<void>? renameGate;
  List<Completer<void>>? renameStartedGates;
  List<Future<void>>? renameGates;
  var _renameAttempt = 0;

  @override
  Future<BurlPreferences> load() {
    final gate = loadGate;
    if (gate != null) return gate;
    return super.load();
  }

  @override
  Future<void> writeTemporaryFile(File file, String contents) async {
    final failure = writeFailure;
    if (failure != null) throw failure;
    await super.writeTemporaryFile(file, contents);
  }

  @override
  Future<File> renameTemporaryFile(File temporary, String destination) async {
    final attempt = _renameAttempt++;
    final started = renameStarted;
    if (started != null && !started.isCompleted) started.complete();
    final startedGates = renameStartedGates;
    if (startedGates != null && attempt < startedGates.length) {
      final gate = startedGates[attempt];
      if (!gate.isCompleted) gate.complete();
    }
    final failure = renameFailure;
    if (failure != null) throw failure;
    final gate = renameGate;
    if (gate != null) await gate;
    final gates = renameGates;
    if (gates != null && attempt < gates.length) await gates[attempt];
    return super.renameTemporaryFile(temporary, destination);
  }
}

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

        store = DevicePreferencesStore(
          applicationSupportDirectory: () async => applicationSupport,
        );
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

    test('corrupt bytes remain preserved and disable replacement', () async {
      await applicationSupport.create(recursive: true);
      final file = File('${applicationSupport.path}/device-preferences.json');
      final bytes = [0xff, 0xfe, 0xfd];
      await file.writeAsBytes(bytes);

      expect(await store.load(), BurlPreferences.defaults());
      final quarantined = await _quarantinedFile(applicationSupport);
      expect(await quarantined.readAsBytes(), bytes);
      expect(await file.exists(), isFalse);

      await expectLater(
        store.save(const BurlPreferences(theme: BurlThemePreference.dark)),
        throwsA(isA<StateError>()),
      );
      expect(await file.exists(), isFalse);
      expect(await quarantined.readAsBytes(), bytes);

      final restartedStore = DevicePreferencesStore(
        applicationSupportDirectory: () async => applicationSupport,
      );
      expect(await restartedStore.load(), BurlPreferences.defaults());
      await expectLater(
        restartedStore.save(
          const BurlPreferences(theme: BurlThemePreference.light),
        ),
        throwsA(isA<StateError>()),
      );
      expect(await file.exists(), isFalse);
      expect(await quarantined.readAsBytes(), bytes);
    });

    test(
      'later-version bytes remain preserved and disable replacement',
      () async {
        await applicationSupport.create(recursive: true);
        final file = File('${applicationSupport.path}/device-preferences.json');
        final bytes = utf8.encode(
          '{"schema_version":2,"theme":"dark","font_scale":"spacious",'
          '"measure":"technical","focus_mode":true,'
          '"update_notifications":false}',
        );
        await file.writeAsBytes(bytes);

        expect(await store.load(), BurlPreferences.defaults());
        final quarantined = await _quarantinedFile(applicationSupport);
        expect(await quarantined.readAsBytes(), bytes);
        expect(await file.exists(), isFalse);

        await expectLater(
          store.save(const BurlPreferences(theme: BurlThemePreference.dark)),
          throwsA(isA<StateError>()),
        );
        expect(await file.exists(), isFalse);
        expect(await quarantined.readAsBytes(), bytes);
      },
    );

    test('save verifies an existing destination before replacement', () async {
      await applicationSupport.create(recursive: true);
      final file = File('${applicationSupport.path}/device-preferences.json');
      final bytes = utf8.encode(
        '{"schema_version":2,"theme":"dark","font_scale":"spacious",'
        '"measure":"technical","focus_mode":true,'
        '"update_notifications":false}',
      );
      await file.writeAsBytes(bytes);

      await expectLater(
        store.save(const BurlPreferences(theme: BurlThemePreference.light)),
        throwsA(isA<StateError>()),
      );

      expect(await file.exists(), isFalse);
      expect(
        await (await _quarantinedFile(applicationSupport)).readAsBytes(),
        bytes,
      );
    });

    test('application-support resolution failures remain observable', () async {
      await applicationSupport.create(recursive: true);
      final file = File('${applicationSupport.path}/device-preferences.json');
      final bytes = utf8.encode(
        '{"schema_version":2,"theme":"dark","font_scale":"spacious",'
        '"measure":"technical","focus_mode":true,'
        '"update_notifications":false}',
      );
      await file.writeAsBytes(bytes);
      var resolutionFails = true;
      store = DevicePreferencesStore(
        applicationSupportDirectory: () async {
          if (resolutionFails) {
            throw StateError('application support unavailable');
          }
          return applicationSupport;
        },
      );

      await expectLater(store.load(), throwsA(isA<StateError>()));

      resolutionFails = false;
      await expectLater(
        store.save(const BurlPreferences(theme: BurlThemePreference.light)),
        throwsA(isA<StateError>()),
      );

      expect(
        await (await _quarantinedFile(applicationSupport)).readAsBytes(),
        bytes,
      );
    });

    test('read failure blocks later saves', () async {
      if (!Platform.isLinux) {
        return;
      }

      await applicationSupport.create(recursive: true);
      final file = File('${applicationSupport.path}/device-preferences.json');
      final bytes = utf8.encode(
        '{"schema_version":2,"theme":"dark","font_scale":"spacious",'
        '"measure":"technical","focus_mode":true,'
        '"update_notifications":false}',
      );
      await file.writeAsBytes(bytes);
      final originalMode = (await file.stat()).mode & 0x1ff;
      await _chmod(file, '0200');
      try {
        await expectLater(store.load(), throwsA(isA<FileSystemException>()));
      } finally {
        await _chmod(file, originalMode.toRadixString(8));
      }

      await expectLater(
        store.save(const BurlPreferences(theme: BurlThemePreference.light)),
        throwsA(isA<StateError>()),
      );
      expect(await file.readAsBytes(), bytes);
    });

    test('save exposes write and rename failures', () async {
      final writeFailure = FileSystemException('preferences disk is full');
      final writeFailingStore = _ControlledDevicePreferencesStore(
        applicationSupportDirectory: () async => applicationSupport,
        writeFailure: writeFailure,
      );

      await expectLater(
        writeFailingStore.save(
          const BurlPreferences(theme: BurlThemePreference.dark),
        ),
        throwsA(same(writeFailure)),
      );

      final renameFailure = FileSystemException('preferences rename failed');
      final renameFailingStore = _ControlledDevicePreferencesStore(
        applicationSupportDirectory: () async => applicationSupport,
        renameFailure: renameFailure,
      );

      await expectLater(
        renameFailingStore.save(
          const BurlPreferences(theme: BurlThemePreference.dark),
        ),
        throwsA(same(renameFailure)),
      );
      expect(
        await File(
          '${applicationSupport.path}/device-preferences.json',
        ).exists(),
        isFalse,
      );
    });

    test(
      'quarantined restoration does not report a failure without a write',
      () async {
        await applicationSupport.create(recursive: true);
        await File(
          '${applicationSupport.path}/device-preferences.json',
        ).writeAsString('{not valid json');

        final scopedContainer = container();
        final writer = scopedContainer.read(burlPreferencesProvider.notifier);
        await writer.flushPendingWrites();

        expect(
          scopedContainer.read(preferencesPersistenceFailureProvider),
          isNull,
        );
      },
    );

    test(
      'reports failed writes, recovers, and flushes every admitted write',
      () async {
        final renameFailure = FileSystemException('preferences rename failed');
        final controlledStore = _ControlledDevicePreferencesStore(
          applicationSupportDirectory: () async => applicationSupport,
          renameFailure: renameFailure,
        );
        store = controlledStore;
        final scopedContainer = container();
        final writer = scopedContainer.read(burlPreferencesProvider.notifier);

        await writer.setTheme(BurlThemePreference.dark);

        expect(
          scopedContainer.read(preferencesPersistenceFailureProvider),
          same(renameFailure),
        );
        await expectLater(
          writer.flushPendingWrites(),
          throwsA(same(renameFailure)),
        );

        controlledStore.renameFailure = null;
        await writer.setFontScale(BurlFontScale.spacious);

        expect(
          scopedContainer.read(preferencesPersistenceFailureProvider),
          isNull,
        );

        final renameStarted = Completer<void>();
        final renameGate = Completer<void>();
        controlledStore
          ..renameStarted = renameStarted
          ..renameGate = renameGate.future;
        final write = writer.setFocusMode(true);
        await renameStarted.future;

        var flushFinished = false;
        final flush = writer.flushPendingWrites().then((_) {
          flushFinished = true;
        });
        await Future<void>.delayed(Duration.zero);
        expect(flushFinished, isFalse);

        renameGate.complete();
        await Future.wait([write, flush]);

        expect(
          scopedContainer.read(preferencesPersistenceFailureProvider),
          isNull,
        );
        final persisted = await DevicePreferencesStore(
          applicationSupportDirectory: () async => applicationSupport,
        ).load();
        expect(persisted.theme, BurlThemePreference.dark);
        expect(persisted.fontScale, BurlFontScale.spacious);
        expect(persisted.focusMode, isTrue);
      },
    );

    test(
      'an early change preserves delayed restored fields in memory and storage',
      () async {
        final restored = const BurlPreferences(
          fontScale: BurlFontScale.spacious,
          measure: BurlMeasure.wide,
          focusMode: true,
          updateNotifications: false,
        );
        final loadGate = Completer<BurlPreferences>();
        store = _ControlledDevicePreferencesStore(
          applicationSupportDirectory: () async => applicationSupport,
          loadGate: loadGate.future,
        );
        final scopedContainer = container();
        final writer = scopedContainer.read(burlPreferencesProvider.notifier);

        final write = writer.setTheme(BurlThemePreference.dark);
        loadGate.complete(restored);
        await write;
        await writer.flushPendingWrites();

        final inMemory = scopedContainer.read(burlPreferencesProvider);
        expect(inMemory.theme, BurlThemePreference.dark);
        expect(inMemory.fontScale, BurlFontScale.spacious);
        expect(inMemory.measure, BurlMeasure.wide);
        expect(inMemory.focusMode, isTrue);
        expect(inMemory.updateNotifications, isFalse);

        final persisted = await DevicePreferencesStore(
          applicationSupportDirectory: () async => applicationSupport,
        ).load();
        expect(persisted.theme, BurlThemePreference.dark);
        expect(persisted.fontScale, BurlFontScale.spacious);
        expect(persisted.measure, BurlMeasure.wide);
        expect(persisted.focusMode, isTrue);
        expect(persisted.updateNotifications, isFalse);
      },
    );

    test(
      'flush drains writes admitted while an earlier write is pending',
      () async {
        final firstRenameStarted = Completer<void>();
        final secondRenameStarted = Completer<void>();
        final firstRenameGate = Completer<void>();
        final secondRenameGate = Completer<void>();
        final controlledStore =
            _ControlledDevicePreferencesStore(
                applicationSupportDirectory: () async => applicationSupport,
              )
              ..renameStartedGates = [firstRenameStarted, secondRenameStarted]
              ..renameGates = [firstRenameGate.future, secondRenameGate.future];
        store = controlledStore;
        final writer = container().read(burlPreferencesProvider.notifier);

        final firstWrite = writer.setTheme(BurlThemePreference.dark);
        await firstRenameStarted.future;

        var flushFinished = false;
        final flush = writer.flushPendingWrites().then((_) {
          flushFinished = true;
        });
        final secondWrite = writer.setFocusMode(true);
        firstRenameGate.complete();
        await secondRenameStarted.future;
        await Future<void>.delayed(Duration.zero);

        expect(flushFinished, isFalse);

        secondRenameGate.complete();
        await Future.wait([firstWrite, secondWrite, flush]);
        expect(flushFinished, isTrue);
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

Future<File> _quarantinedFile(Directory directory) async {
  final candidates = <File>[];
  await for (final entity in directory.list()) {
    if (entity is File && entity.path.contains('.quarantine-')) {
      candidates.add(entity);
    }
  }
  expect(candidates, hasLength(1));
  return candidates.single;
}

Future<String> _git(Directory workspace, List<String> arguments) async {
  final result = await Process.run('git', ['-C', workspace.path, ...arguments]);
  if (result.exitCode != 0) {
    throw TestFailure('git ${arguments.join(' ')} failed:\n${result.stderr}');
  }
  return result.stdout as String;
}

Future<void> _chmod(File file, String mode) async {
  final result = await Process.run('chmod', [mode, file.path]);
  if (result.exitCode != 0) {
    throw TestFailure('chmod $mode failed:\n${result.stderr}');
  }
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
