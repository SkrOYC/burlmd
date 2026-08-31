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

    test('visual gate owns a headless compositor', () async {
      final script = await File('scripts/visual-regression.sh').readAsString();

      expect(script, contains("'WLR_BACKENDS=headless'"));
      expect(script, contains("'WLR_HEADLESS_OUTPUTS=1'"));
      expect(script, isNot(contains('hyprctl clients -j')));
    });
  });

  group('smoke PID handoff', () {
    late _SmokeHandoffFixture fixture;

    setUp(() async {
      fixture = await _SmokeHandoffFixture.create();
    });

    tearDown(() => fixture.dispose());

    test(
      'publishes the PID of an actually launched app through an inherited FD',
      () async {
        final handoff = File('${fixture.root.path}/handoff');
        final launched = File('${fixture.root.path}/launched');

        final result = await fixture.runWithInheritedHandoff(
          handoff: handoff,
          launched: launched,
        );

        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(
          _lastLine(result.stdout.toString()),
          launched.readAsStringSync().trim(),
        );
        expect(
          _lastLine(result.stdout.toString()),
          matches(RegExp(r'^[1-9][0-9]*$')),
        );
      },
    );

    test(
      'rejects invalid, closed, and non-regular descriptors before launch',
      () async {
        final launched = File('${fixture.root.path}/should-not-launch');
        final invalid = await fixture.run(
          environment: {'BURLMD_SMOKE_APP_PID_FD': 'not-a-descriptor'},
        );
        final closed = await fixture.runBash(
          r'exec 9>&-; BURLMD_SMOKE_APP_PID_FD=9 "$1" rejected',
        );
        final nonRegular = await fixture.runBash(
          r'exec 9<> /dev/null; BURLMD_SMOKE_APP_PID_FD=9 "$1" rejected',
        );

        for (final result in [invalid, closed, nonRegular]) {
          expect(result.exitCode, 64, reason: result.stderr.toString());
          expect(
            result.stderr,
            contains('must name an inherited owned regular-file FD'),
          );
        }
        expect(await launched.exists(), isFalse);
      },
    );

    test('a caller pathname substitution stays harmless', () async {
      final handoff = File('${fixture.root.path}/handoff');
      final launched = File('${fixture.root.path}/launched');
      final substitutedPath = File(
        '${fixture.root.path}/attacker-selected-path',
      );
      await substitutedPath.writeAsString('leave this unchanged\n');

      final result = await fixture.runWithInheritedHandoff(
        handoff: handoff,
        launched: launched,
        callerPathname: substitutedPath,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(await substitutedPath.readAsString(), 'leave this unchanged\n');
      expect(await handoff.readAsString(), await launched.readAsString());
    });
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

class _SmokeHandoffFixture {
  _SmokeHandoffFixture._(this.root, this.script, this.fakeBin);

  final Directory root;
  final File script;
  final Directory fakeBin;

  static Future<_SmokeHandoffFixture> create() async {
    final root = await Directory.systemTemp.createTemp('burlmd-smoke-handoff.');
    final scripts = Directory('${root.path}/scripts');
    final fakeBin = Directory('${root.path}/fake-bin');
    await scripts.create();
    await fakeBin.create();
    await Directory('${root.path}/rust').create();
    final script = File('${scripts.path}/smoke-shot.sh');
    await File('scripts/smoke-shot.sh').copy(script.path);

    for (final command in ['cargo', 'flutter']) {
      final executable = File('${fakeBin.path}/$command');
      await executable.writeAsString('#!/usr/bin/env bash\nexit 0\n');
      await _makeExecutable(executable);
    }
    final grim = File('${fakeBin.path}/grim');
    await grim.writeAsString(r'''#!/usr/bin/env bash
set -euo pipefail
output="${!#}"
printf 'P6\n1 1\n255\n\0\0\0' > "$output"
''');
    await _makeExecutable(grim);

    final app = File('${root.path}/build/linux/x64/release/bundle/burlmd');
    await app.parent.create(recursive: true);
    await app.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "\$\$" > "\$BURLMD_TEST_APP_LAUNCH_MARKER"
trap 'exit 0' TERM INT
while :; do sleep .1; done
''');
    await _makeExecutable(app);

    return _SmokeHandoffFixture._(root, script, fakeBin);
  }

  Future<ProcessResult> run({Map<String, String> environment = const {}}) =>
      Process.run('bash', [
        script.path,
        'rejected',
      ], environment: _environment(environment));

  Future<ProcessResult> runBash(String command) => Process.run('bash', [
    '-c',
    command,
    'smoke-handoff-test',
    script.path,
  ], environment: _environment(const {}));

  Future<ProcessResult> runWithInheritedHandoff({
    required File handoff,
    required File launched,
    File? callerPathname,
  }) => Process.run('bash', [
    '-c',
    '''
set -euo pipefail
handoff="\$1"
launched="\$2"
script="\$3"
caller_pathname="\$4"
exec 9<> "\$handoff"
BURLMD_SMOKE_APP_PID_FD=9 \\
  BURLMD_TEST_APP_LAUNCH_MARKER="\$launched" \\
  BURLMD_SMOKE_APP_PID_FILE="\$caller_pathname" \\
  "\$script" handoff &
smoke_pid=\$!
for _ in \$(seq 1 200); do
  if [[ -s "\$handoff" && -s "\$launched" ]]; then
    published_pid="\$(<"\$handoff")"
    launched_pid="\$(<"\$launched")"
    kill -0 "\$published_pid"
    [[ "\$published_pid" == "\$launched_pid" ]]
    kill "\$smoke_pid" 2>/dev/null || true
    wait "\$smoke_pid" 2>/dev/null || true
    printf '%s\\n' "\$published_pid"
    exit 0
  fi
  sleep .02
done
kill "\$smoke_pid" 2>/dev/null || true
wait "\$smoke_pid" 2>/dev/null || true
exit 1
''',
    'smoke-handoff-test',
    handoff.path,
    launched.path,
    script.path,
    callerPathname?.path ?? '${root.path}/not-used',
  ], environment: _environment({'BURLMD_SMOKE_SHOT_DIR': '${root.path}/qa'}));

  Map<String, String> _environment(Map<String, String> additions) => {
    ...Platform.environment,
    'PATH': '${fakeBin.path}:${Platform.environment['PATH']}',
    ...additions,
  };

  Future<void> dispose() => root.delete(recursive: true);

  static Future<void> _makeExecutable(File file) async {
    final result = await Process.run('chmod', ['u+x', file.path]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'chmod',
        ['u+x', file.path],
        result.stderr.toString(),
        result.exitCode,
      );
    }
  }
}

String _lastLine(String value) => value.trim().split('\n').last;
