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
      'visual gate owns a headless compositor and clears ambient DISPLAY',
      () async {
        final visual = await File(
          'scripts/visual-regression.sh',
        ).readAsString();
        final smoke = await File('scripts/smoke-shot.sh').readAsString();

        expect(visual, contains("'WLR_BACKENDS=headless'"));
        expect(visual, contains("'WLR_HEADLESS_OUTPUTS=1'"));
        expect(visual, contains('env -u DISPLAY'));
        expect(smoke, contains('env -u DISPLAY'));
      },
    );

    test(
      'clears ambient display variables before its first launcher helper',
      () async {
        final fixture = await _VisualLauncherEntryFixture.create();
        addTearDown(fixture.dispose);

        final result = await fixture.run();

        expect(result.exitCode, 93, reason: result.stderr.toString());
        expect(
          await fixture.environmentMarker.readAsString(),
          'DISPLAY=unset\nWAYLAND_DISPLAY=unset\nSWAYSOCK=unset\n',
        );
      },
    );
  });

  group('smoke PID handoff', () {
    late _SmokeHandoffFixture fixture;

    setUp(() async {
      fixture = await _SmokeHandoffFixture.create();
    });

    tearDown(() => fixture.dispose());

    test('publishes the launched PID and removes poisoned DISPLAY', () async {
      final handoff = File('${fixture.root.path}/handoff');
      final launched = File('${fixture.root.path}/launched');
      final display = File('${fixture.root.path}/display');
      final handoffIsolation = File('${fixture.root.path}/handoff-isolation');

      final result = await fixture.runWithInheritedHandoff(
        handoff: handoff,
        launched: launched,
        display: display,
        handoffIsolation: handoffIsolation,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(
        handoff.readAsStringSync().trim(),
        launched.readAsStringSync().trim(),
      );
      expect(
        handoff.readAsStringSync().trim(),
        matches(RegExp(r'^[1-9][0-9]*$')),
      );
      expect(display.readAsStringSync().trim(), 'unset');
      expect(handoffIsolation.readAsStringSync().trim(), 'revoked');
    });

    test('rejects an invalid inherited PID descriptor before launch', () async {
      final result = await fixture.run(
        environment: {'BURLMD_SMOKE_APP_PID_FD': 'not-a-descriptor'},
      );

      expect(result.exitCode, 64, reason: result.stderr.toString());
      expect(
        result.stderr,
        contains('must name an inherited owned regular-file FD'),
      );
    });

    test(
      'keeps an unlinked handoff undiscoverable and reads the actual app PID',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'burlmd-unlinked-pid-handoff.',
        );
        addTearDown(() => root.delete(recursive: true));
        final runtime = await Directory('${root.path}/runtime').create();
        final app = File('${root.path}/malicious-app');
        final discovery = File('${root.path}/discovery');
        final received = File('${root.path}/received');

        await app.writeAsString(r'''#!/usr/bin/env bash
set -euo pipefail
[[ ! -v BURLMD_SMOKE_APP_PID_FD ]] || exit 91
if find /proc/self/fd -maxdepth 1 -type l -exec readlink {} \; \
  | grep -q '\\.app-pid\\.'; then
  exit 92
fi
find "$XDG_RUNTIME_DIR" -maxdepth 1 -name '*.app-pid.*' -printf '%f\n' \
  > "$BURLMD_TEST_DISCOVERY"
while IFS= read -r handoff; do
  printf '%s\n' attacker > "$XDG_RUNTIME_DIR/$handoff"
done < "$BURLMD_TEST_DISCOVERY"
printf '%s\n' "$$" > "$BURLMD_TEST_RECEIVED"
sleep .5
''');
        await _SmokeHandoffFixture._makeExecutable(app);

        final result = await Process.run('bash', [
          '-c',
          r'''set -euo pipefail
runtime="$1"
app="$2"
discovery="$3"
received="$4"
handoff="$(mktemp "$runtime/.visual-regression-protocol.app-pid.XXXXXX")"
exec {writer_fd}<> "$handoff"
exec {reader_fd}< "$handoff"
rm -f -- "$handoff"
# A failed pre-publication read must not consume the reader's offset.
if IFS= read -r -u "$reader_fd" unexpected; then
  exit 1
fi
(
  # The visual parent keeps this reader private when it execs smoke-shot.
  exec {reader_fd}<&-
  BURLMD_SMOKE_APP_PID_FD="$writer_fd" \
    BURLMD_TEST_DISCOVERY="$discovery" \
    BURLMD_TEST_RECEIVED="$received" \
    bash -c '
      set -euo pipefail
      writer_fd="$BURLMD_SMOKE_APP_PID_FD"
      (
        unset BURLMD_SMOKE_APP_PID_FD
        exec {writer_fd}>&-
        exec "$0"
      ) &
      app_pid=$!
      printf "%s\\n" "$app_pid" >&"$writer_fd"
      wait "$app_pid"
    ' "$app"
) &
launcher_pid=$!
for _ in $(seq 1 100); do
  if IFS= read -r -u "$reader_fd" app_pid; then
    [[ "$app_pid" =~ ^[1-9][0-9]*$ ]]
    kill -0 "$app_pid"
    wait "$launcher_pid"
    exit 0
  fi
  sleep .01
done
wait "$launcher_pid"
exit 1
''',
          'unlinked-handoff-test',
          runtime.path,
          app.path,
          discovery.path,
          received.path,
        ]);

        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(await discovery.readAsString(), isEmpty);
        expect(
          (await received.readAsString()).trim(),
          matches(RegExp(r'^[1-9][0-9]*$')),
        );
      },
    );

    test(
      'visual gate unlinks the handoff and reads only its private reader',
      () async {
        final visual = await File(
          'scripts/visual-regression.sh',
        ).readAsString();

        expect(visual, contains(r'exec {APP_PID_READ_FD}< "$APP_PID_FILE"'));
        expect(visual, contains(r'rm -f -- "$APP_PID_FILE"'));
        expect(visual, contains(r'read -r -u "$APP_PID_READ_FD" app_pid'));
        expect(visual, contains(r'exec {APP_PID_READ_FD}<&-'));
        expect(
          visual,
          isNot(contains(r'head -n 1 "/proc/self/fd/$APP_PID_FD"')),
        );
      },
    );
  });
}

class _VisualLauncherEntryFixture {
  _VisualLauncherEntryFixture._(
    this.root,
    this.fakeBin,
    this.environmentMarker,
  );

  final Directory root;
  final Directory fakeBin;
  final File environmentMarker;

  static Future<_VisualLauncherEntryFixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'burlmd-visual-launcher-entry.',
    );
    final fakeBin = await Directory('${root.path}/fake-bin').create();
    final baseline = await File('${root.path}/baseline.png').create();
    final environmentMarker = File('${root.path}/launcher-environment');
    final mkdir = File('${fakeBin.path}/mkdir');
    await baseline.writeAsBytes(const []);
    await mkdir.writeAsString(r'''#!/usr/bin/env bash
set -euo pipefail
printf 'DISPLAY=%s\nWAYLAND_DISPLAY=%s\nSWAYSOCK=%s\n' \
  "${DISPLAY-unset}" "${WAYLAND_DISPLAY-unset}" "${SWAYSOCK-unset}" \
  > "$BURLMD_TEST_LAUNCHER_ENV_MARKER"
if [[ -v DISPLAY || -v WAYLAND_DISPLAY || -v SWAYSOCK ]]; then
  exit 92
fi
exit 93
''');
    await _SmokeHandoffFixture._makeExecutable(mkdir);

    return _VisualLauncherEntryFixture._(root, fakeBin, environmentMarker);
  }

  Future<ProcessResult> run() => Process.run(
    'bash',
    [
      'scripts/visual-regression.sh',
      'launcher-entry',
      '--baseline',
      '${root.path}/baseline.png',
      '--max-different-pixels',
      '0',
    ],
    environment: {
      ...Platform.environment,
      'PATH': '${fakeBin.path}:${Platform.environment['PATH'] ?? ''}',
      'BURLMD_VISUAL_REGRESSION_DIR': '${root.path}/capture',
      'BURLMD_TEST_LAUNCHER_ENV_MARKER': environmentMarker.path,
      'DISPLAY': 'poisoned-x11',
      'WAYLAND_DISPLAY': 'poisoned-wayland',
      'SWAYSOCK': 'poisoned-sway',
    },
  );

  Future<void> dispose() => root.delete(recursive: true);
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
if [[ "$output" == *smoke-shot-candidate* ]]; then
  { printf 'P6\n200 100\n255\n'; head -c 60000 /dev/zero; } > "$output"
else
  { printf 'P6\n200 100\n255\n'; head -c 60000 /dev/zero | tr '\0' '\377'; } > "$output"
fi
''');
    await _makeExecutable(grim);

    final app = File('${root.path}/build/linux/x64/release/bundle/burlmd');
    await app.parent.create(recursive: true);
    await app.writeAsString(r'''#!/usr/bin/env bash
set -euo pipefail
if [[ -v BURLMD_SMOKE_APP_PID_FD ]]; then
  printf '%s\n' 'environment-leaked' > "$BURLMD_TEST_APP_HANDOFF_MARKER"
  exit 91
fi
# The fixture reserves FD 9 for the parent-only handoff. Do not derive this
# number from an environment capability: the child must not be able to write it.
if { : >&9; } 2>/dev/null; then
  printf '%s\n' 'descriptor-leaked' > "$BURLMD_TEST_APP_HANDOFF_MARKER"
  exit 92
fi
printf '%s\n' 'revoked' > "$BURLMD_TEST_APP_HANDOFF_MARKER"
printf '%s\n' "$$" > "$BURLMD_TEST_APP_LAUNCH_MARKER"
printf '%s\n' "${DISPLAY-unset}" > "$BURLMD_TEST_APP_DISPLAY_MARKER"
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

  Future<ProcessResult> runWithInheritedHandoff({
    required File handoff,
    required File launched,
    required File display,
    required File handoffIsolation,
  }) => Process.run('bash', [
    '-c',
    r'''set -euo pipefail
handoff="$1"
launched="$2"
display="$3"
handoff_isolation="$4"
script="$5"
exec 9<> "$handoff"
DISPLAY='poisoned-ambient-display' BURLMD_SMOKE_APP_PID_FD=9 \
  BURLMD_TEST_APP_LAUNCH_MARKER="$launched" \
  BURLMD_TEST_APP_DISPLAY_MARKER="$display" \
  BURLMD_TEST_APP_HANDOFF_MARKER="$handoff_isolation" \
  "$script" handoff &
smoke_pid=$!
for _ in $(seq 1 200); do
  if [[ -s "$handoff" && -s "$launched" && -s "$display" && -s "$handoff_isolation" ]]; then
    published_pid="$(<"$handoff")"
    launched_pid="$(<"$launched")"
    kill -0 "$published_pid"
    [[ "$published_pid" == "$launched_pid" ]]
    kill "$smoke_pid" 2>/dev/null || true
    wait "$smoke_pid" 2>/dev/null || true
    exit 0
  fi
  sleep .02
done
kill "$smoke_pid" 2>/dev/null || true
wait "$smoke_pid" 2>/dev/null || true
exit 1
''',
    'smoke-handoff-test',
    handoff.path,
    launched.path,
    display.path,
    handoffIsolation.path,
    script.path,
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
