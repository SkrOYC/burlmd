import 'dart:io';

import 'package:burlmd/src/smoke_isolation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateSmokeIsolation', () {
    late _SmokeState state;

    setUp(() async {
      state = await _SmokeState.create();
    });

    tearDown(() async {
      await state.dispose();
    });

    test('rejects a direct copied isolation boolean', () async {
      final result = await validateSmokeIsolation({
        'BURLMD_SMOKE_ISOLATED': '1',
        'BURLMD_SMOKE_F002': '1',
      });

      expect(result, isNotNull);
    });

    test('rejects a missing or mismatched nonce capability', () async {
      final missingNonce = Map<String, String>.from(state.environment)
        ..remove('BURLMD_SMOKE_NONCE');
      expect(await validateSmokeIsolation(missingNonce), isNotNull);

      final mismatchedNonce = Map<String, String>.from(state.environment)
        ..['BURLMD_SMOKE_NONCE'] = 'f' * 64;
      expect(await validateSmokeIsolation(mismatchedNonce), isNotNull);
    });

    test('rejects a missing or non-private harness root', () async {
      final missingRoot = Map<String, String>.from(state.environment)
        ..remove('BURLMD_SMOKE_ROOT');
      expect(await validateSmokeIsolation(missingRoot), isNotNull);

      final nonPrivateRoot = Map<String, String>.from(state.environment)
        ..['BURLMD_SMOKE_ROOT'] = Directory.systemTemp.path;
      expect(await validateSmokeIsolation(nonPrivateRoot), isNotNull);
    });

    test('rejects a real/default Workspace path', () async {
      final realWorkspace = await Directory.systemTemp.createTemp(
        'burlmd-real-workspace.',
      );
      addTearDown(() => realWorkspace.delete(recursive: true));
      final environment = Map<String, String>.from(state.environment)
        ..['BURLMD_SMOKE_WORKSPACE'] = realWorkspace.path;

      expect(await validateSmokeIsolation(environment), isNotNull);
    });

    test(
      'rejects a traversal path outside the private state directory',
      () async {
        final outsideDatabase = File('${state.root.path}/outside.sqlite');
        await outsideDatabase.create();
        final environment = Map<String, String>.from(state.environment)
          ..['BURLMD_DB_PATH'] =
              '${state.root.path}/data/burlmd/../../outside.sqlite';

        expect(await validateSmokeIsolation(environment), isNotNull);
      },
    );

    test(
      'rejects a symlink that escapes the private state directory',
      () async {
        final escape = await Directory.systemTemp.createTemp('burlmd-escape.');
        addTearDown(() => escape.delete(recursive: true));
        await state.workspace.delete();
        await Link(state.workspace.path).create(escape.path);

        expect(await validateSmokeIsolation(state.environment), isNotNull);
      },
    );

    test('accepts the complete canonical harness contract', () async {
      expect(await validateSmokeIsolation(state.environment), isNull);
    });
  });
}

class _SmokeState {
  _SmokeState._(this.root, this.workspace, this.environment);

  final Directory root;
  final Directory workspace;
  final Map<String, String> environment;

  static Future<_SmokeState> create() async {
    final root = await Directory('/tmp').createTemp('burlmd-smoke-state.');
    final home = Directory('${root.path}/home');
    final data = Directory('${root.path}/data');
    final workspace = Directory('${data.path}/burlmd/workspace');
    final database = File('${data.path}/burlmd/index.sqlite3');
    final nonceFile = File('${root.path}/.burlmd-smoke-nonce');
    const nonce =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    await home.create();
    await workspace.create(recursive: true);
    await database.create();
    await nonceFile.writeAsString('$nonce\n');

    return _SmokeState._(root, workspace, {
      'BURLMD_SMOKE_ISOLATED': '1',
      'BURLMD_SMOKE_ROOT': root.path,
      'BURLMD_SMOKE_NONCE': nonce,
      'BURLMD_SMOKE_NONCE_FILE': nonceFile.path,
      'BURLMD_SMOKE_WORKSPACE': workspace.path,
      'HOME': home.path,
      'XDG_DATA_HOME': data.path,
      'BURLMD_DB_PATH': database.path,
    });
  }

  Future<void> dispose() => root.delete(recursive: true);
}
