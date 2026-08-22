import 'package:burlmd/main.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/screens/login.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stub [RustApi] whose bootstrap call never touches FFI, mirroring
/// `login_test.dart`'s fixed-controller pattern. Records how many times the
/// app drove the Core's open-or-create path so tests can assert the startup
/// behavior without a real Rust library.
class _StubRustApi extends RustApi {
  final WorkspaceInfo workspace;
  int openOrCreateCalls = 0;

  _StubRustApi(this.workspace);

  @override
  Future<WorkspaceInfo> openOrCreateLocalWorkspace({String? path}) async {
    openOrCreateCalls++;
    return workspace;
  }
}

WorkspaceInfo _localWorkspace() => const WorkspaceInfo(
  id: 'ws-1',
  name: 'workspace',
  provider: 'local',
  localPath: '/tmp/burlmd-workspace',
);

void main() {
  // SHEL-E002: with no credentials and no network, launching the application
  // opens the local Workspace directly. The stub's `openOrCreateLocalWorkspace`
  // is exactly what the real Core path is — no credential, no network
  // (`WSPC-D004`) — and its reuse semantics ("existing repository and
  // Workspace row are reused") are the Core contract's own guarantee.
  testWidgets('launches into the workspace shell with no login gate', (
    WidgetTester tester,
  ) async {
    final api = _StubRustApi(_localWorkspace());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustApiProvider.overrideWithValue(api)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.openOrCreateCalls, 1);
    expect(find.byType(LoginScreen), findsNothing);
    // The minimal shell this milestone asserts on; SHEL-E003 fills it.
    expect(find.text('burlmd'), findsOneWidget);
    expect(find.text('workspace'), findsOneWidget);
  });

  testWidgets('a bootstrap failure surfaces instead of the login screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustApiProvider.overrideWithValue(_FailingRustApi())],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('Failed to open workspace'), findsOneWidget);
  });
}

class _FailingRustApi extends RustApi {
  @override
  Future<WorkspaceInfo> openOrCreateLocalWorkspace({String? path}) async {
    throw StateError('bootstrap failed');
  }
}
