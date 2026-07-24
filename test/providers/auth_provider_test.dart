import 'dart:async';
import 'dart:io';

import 'package:burlmd/src/providers/auth_provider.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// A [RustApi] whose `beginOAuthFlow` always returns a fixed, known PKCE
/// flow (so tests can assert against `test-state`/`test-code-verifier`),
/// and whose `authenticateWorkspace` either returns a fixed workspace id or
/// throws a fixed error, without touching the real Rust dylib.
class _FakeRustApi extends RustApi {
  const _FakeRustApi({this.authenticateWorkspaceResult, this.onAuthenticate});

  final String? authenticateWorkspaceResult;
  final void Function()? onAuthenticate;

  @override
  OAuthFlowStart beginOAuthFlow(String provider, String redirectUri) =>
      OAuthFlowStart(
        authorizeUrl: Uri(
          scheme: 'https',
          host: 'github.com',
          path: '/login/oauth/authorize',
          queryParameters: {
            'client_id': 'test-client-id',
            'redirect_uri': redirectUri,
            'state': 'test-state',
            'code_challenge': 'test-challenge',
            'code_challenge_method': 'S256',
          },
        ).toString(),
        codeVerifier: 'test-code-verifier',
        state: 'test-state',
      );

  @override
  Future<String> authenticateWorkspace(
    String provider,
    String authCode,
    String codeVerifier,
  ) async {
    onAuthenticate?.call();
    return authenticateWorkspaceResult ?? (throw StateError('unexpected call'));
  }
}

/// A minimal `url_launcher` platform fake: records the URL it was asked to
/// open instead of actually opening a system browser (unavailable, and
/// undesirable, in a test run).
class _FakeUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  Uri? launchedUri;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUri = Uri.parse(url);
    return true;
  }
}

/// Fires a real loopback GET request against the `redirect_uri` baked into
/// the authorize URL the controller requested — exactly what the system
/// browser does after the user finishes (or cancels) the GitHub flow —
/// against the controller's real `HttpServer`.
Future<void> _simulateRedirect(
  Uri authorizeUrl,
  Map<String, String> params,
) async {
  final redirectUri = Uri.parse(authorizeUrl.queryParameters['redirect_uri']!);
  final callback = redirectUri.replace(queryParameters: params);
  final client = HttpClient();
  try {
    final request = await client.getUrl(callback);
    final response = await request.close();
    await response.drain<void>();
  } finally {
    client.close();
  }
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition never became true within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late _FakeUrlLauncher fakeLauncher;

  setUp(() {
    fakeLauncher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fakeLauncher;
  });

  test('happy path drives idle -> waitingForBrowser -> exchanging -> success '
      'and returns the workspace id from authenticate_workspace', () async {
    final container = ProviderContainer(
      overrides: [
        rustApiProvider.overrideWithValue(
          const _FakeRustApi(authenticateWorkspaceResult: 'octocat'),
        ),
      ],
    );
    addTearDown(container.dispose);

    final states = <AuthStatus>[];
    container.listen(
      authControllerProvider,
      (_, next) => states.add(next.status),
      fireImmediately: true,
    );

    final loginFuture = container
        .read(authControllerProvider.notifier)
        .loginWithGitHub();

    await _waitUntil(() => fakeLauncher.launchedUri != null);
    await _simulateRedirect(fakeLauncher.launchedUri!, {
      'code': 'test-auth-code',
      'state': 'test-state',
    });

    await loginFuture;

    expect(states, [
      AuthStatus.idle,
      AuthStatus.waitingForBrowser,
      AuthStatus.exchanging,
      AuthStatus.success,
    ]);
    expect(container.read(authControllerProvider).workspaceId, 'octocat');
  });

  test('a state-parameter mismatch on the redirect is rejected before ever '
      'calling authenticate_workspace', () async {
    var authenticateCalls = 0;
    final container = ProviderContainer(
      overrides: [
        rustApiProvider.overrideWithValue(
          _FakeRustApi(
            authenticateWorkspaceResult: 'octocat',
            onAuthenticate: () => authenticateCalls++,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final loginFuture = container
        .read(authControllerProvider.notifier)
        .loginWithGitHub();

    await _waitUntil(() => fakeLauncher.launchedUri != null);
    await _simulateRedirect(fakeLauncher.launchedUri!, {
      'code': 'test-auth-code',
      'state': 'not-the-expected-state',
    });

    await loginFuture;

    expect(container.read(authControllerProvider).status, AuthStatus.error);
    expect(
      authenticateCalls,
      0,
      reason: 'a mismatched state must never reach the token exchange',
    );
  });

  test('an access_denied redirect surfaces GitHub\'s error_description without '
      'calling authenticate_workspace', () async {
    var authenticateCalls = 0;
    final container = ProviderContainer(
      overrides: [
        rustApiProvider.overrideWithValue(
          _FakeRustApi(onAuthenticate: () => authenticateCalls++),
        ),
      ],
    );
    addTearDown(container.dispose);

    final loginFuture = container
        .read(authControllerProvider.notifier)
        .loginWithGitHub();

    await _waitUntil(() => fakeLauncher.launchedUri != null);
    await _simulateRedirect(fakeLauncher.launchedUri!, {
      'error': 'access_denied',
      'error_description': 'The user has denied your application access.',
    });

    await loginFuture;

    final state = container.read(authControllerProvider);
    expect(state.status, AuthStatus.error);
    expect(state.errorMessage, 'The user has denied your application access.');
    expect(authenticateCalls, 0);
  });

  test(
    'a failing authenticate_workspace call surfaces as an error state',
    () async {
      final container = ProviderContainer(
        overrides: [
          rustApiProvider.overrideWithValue(
            const _FakeRustApi(authenticateWorkspaceResult: null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final loginFuture = container
          .read(authControllerProvider.notifier)
          .loginWithGitHub();

      await _waitUntil(() => fakeLauncher.launchedUri != null);
      await _simulateRedirect(fakeLauncher.launchedUri!, {
        'code': 'test-auth-code',
        'state': 'test-state',
      });

      await loginFuture;

      expect(container.read(authControllerProvider).status, AuthStatus.error);
    },
  );
}
