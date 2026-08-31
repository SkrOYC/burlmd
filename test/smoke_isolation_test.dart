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

    test(
      'rejects a private-looking root that does not own the nonce',
      () async {
        final mismatchedRoot = await Directory(
          '/tmp',
        ).createTemp('burlmd-smoke-state.');
        addTearDown(() => mismatchedRoot.delete(recursive: true));
        final environment = Map<String, String>.from(state.environment)
          ..['BURLMD_SMOKE_ROOT'] = mismatchedRoot.path;

        expect(await validateSmokeIsolation(environment), isNotNull);
      },
    );

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

    test('rejects an external existing readiness marker', () async {
      final externalRoot = await Directory.systemTemp.createTemp(
        'burlmd-external-ready.',
      );
      addTearDown(() => externalRoot.delete(recursive: true));
      final external = await File('${externalRoot.path}/ready').create();
      final environment = Map<String, String>.from(state.environment)
        ..['BURLMD_SMOKE_READY_FILE'] = external.path;

      expect(await validateSmokeIsolation(environment), isNotNull);
    });

    test(
      'rejects a readiness marker traversal outside the private state',
      () async {
        final externalRoot = await Directory.systemTemp.createTemp(
          'burlmd-traversed-ready.',
        );
        addTearDown(() => externalRoot.delete(recursive: true));
        final external = await File('${externalRoot.path}/ready').create();
        final environment = Map<String, String>.from(state.environment)
          ..['BURLMD_SMOKE_READY_FILE'] =
              '${state.root.path}/../${external.uri.pathSegments.last}';

        expect(await validateSmokeIsolation(environment), isNotNull);
      },
    );

    test(
      'rejects a readiness marker symlink that escapes the state root',
      () async {
        final externalRoot = await Directory.systemTemp.createTemp(
          'burlmd-ready-symlink-target.',
        );
        addTearDown(() => externalRoot.delete(recursive: true));
        final external = await File('${externalRoot.path}/ready').create();
        await state.readyFile.delete();
        await Link(state.readyFile.path).create(external.path);

        expect(await validateSmokeIsolation(state.environment), isNotNull);
      },
    );

    test('accepts the complete canonical harness contract', () async {
      expect(await validateSmokeIsolation(state.environment), isNull);
    });

    test(
      'harness creates and forwards only its root-bound readiness marker',
      () async {
        final script = await File('scripts/smoke-shot.sh').readAsString();

        expect(
          script,
          contains(r'READY_FILE="$SMOKE_STATE_DIR/.burlmd-smoke-ready"'),
        );
        expect(script, contains(r'touch -- "$READY_FILE"'));
        expect(script, contains(r'"BURLMD_SMOKE_READY_FILE=$READY_FILE"'));
        expect(script, isNot(contains('mktemp /tmp/burlmd-selection-ready.')));
      },
    );

    test(
      'harness publishes its launched PID only to a pre-created file',
      () async {
        final script = await File('scripts/smoke-shot.sh').readAsString();

        expect(
          script,
          contains(r'APP_PID_FILE="${BURLMD_SMOKE_APP_PID_FILE:-}"'),
        );
        expect(
          script,
          contains(r'[[ -n "$APP_PID_FILE" && ! -f "$APP_PID_FILE" ]]'),
        );
        expect(
          script,
          contains(r'''printf '%s\n' "$APP_PID" > "$APP_PID_FILE"'''),
        );
      },
    );

    test(
      'visual gate owns a headless compositor and checks the launched PID',
      () async {
        final script = await File(
          'scripts/visual-regression.sh',
        ).readAsString();

        expect(script, contains("'WLR_BACKENDS=headless'"));
        expect(script, contains("'WLR_HEADLESS_OUTPUTS=1'"));
        expect(script, contains(r'sway_client_geometry "$APP_PID"'));
        expect(script, contains(r'BURLMD_SMOKE_APP_PID_FILE="$APP_PID_FILE"'));
        expect(script, isNot(contains('hyprctl clients -j')));
      },
    );
  });
}

class _SmokeState {
  _SmokeState._(this.root, this.workspace, this.readyFile, this.environment);

  final Directory root;
  final Directory workspace;
  final File readyFile;
  final Map<String, String> environment;

  static Future<_SmokeState> create() async {
    final root = await Directory('/tmp').createTemp('burlmd-smoke-state.');
    final home = Directory('${root.path}/home');
    final data = Directory('${root.path}/data');
    final workspace = Directory('${data.path}/burlmd/workspace');
    final database = File('${data.path}/burlmd/index.sqlite3');
    final nonceFile = File('${root.path}/.burlmd-smoke-nonce');
    final readyFile = File('${root.path}/.burlmd-smoke-ready');
    const nonce =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    await home.create();
    await workspace.create(recursive: true);
    await database.create();
    await nonceFile.writeAsString('$nonce\n');
    await readyFile.create();

    return _SmokeState._(root, workspace, readyFile, {
      'BURLMD_SMOKE_ISOLATED': '1',
      'BURLMD_SMOKE_ROOT': root.path,
      'BURLMD_SMOKE_NONCE': nonce,
      'BURLMD_SMOKE_NONCE_FILE': nonceFile.path,
      'BURLMD_SMOKE_WORKSPACE': workspace.path,
      'BURLMD_SMOKE_READY_FILE': readyFile.path,
      'HOME': home.path,
      'XDG_DATA_HOME': data.path,
      'BURLMD_DB_PATH': database.path,
    });
  }

  Future<void> dispose() => root.delete(recursive: true);
}
