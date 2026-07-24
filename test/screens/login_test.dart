import 'package:burlmd/src/providers/auth_provider.dart';
import 'package:burlmd/src/screens/login.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// An [AuthController] whose state is fixed at construction, mirroring
/// `editor_test.dart`'s `_FixedNoteController` pattern: lets these tests
/// pump [LoginScreen] against a known [AuthFlowState] without driving the
/// real flow (real network calls, a real loopback `HttpServer`, or
/// `url_launcher`), none of which are available/desirable in a widget test.
class _FixedAuthController extends AuthController {
  _FixedAuthController(this._initial, {this.onLogin});

  final AuthFlowState _initial;
  final void Function()? onLogin;

  @override
  AuthFlowState build() => _initial;

  @override
  Future<void> loginWithGitHub({String provider = 'github'}) async {
    onLogin?.call();
  }
}

Future<void> pumpLogin(
  WidgetTester tester,
  AuthFlowState state, {
  void Function()? onLogin,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(
        () => _FixedAuthController(state, onLogin: onLogin),
      ),
    ],
    child: const MaterialApp(home: LoginScreen()),
  ),
);

void main() {
  testWidgets('idle state shows a sign-in button and no error', (tester) async {
    await pumpLogin(tester, const AuthFlowState.idle());

    expect(find.text('Sign in with GitHub'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('waitingForBrowser state shows a spinner and no button', (
    tester,
  ) async {
    await pumpLogin(tester, const AuthFlowState.waitingForBrowser());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('Waiting for you to authorize'), findsOneWidget);
    expect(find.text('Sign in with GitHub'), findsNothing);
  });

  testWidgets('exchanging state shows a spinner with a different message', (
    tester,
  ) async {
    await pumpLogin(tester, const AuthFlowState.exchanging());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('Finishing sign-in'), findsOneWidget);
  });

  testWidgets('success state shows the workspace id and no button', (
    tester,
  ) async {
    await pumpLogin(tester, const AuthFlowState.success('octocat'));

    expect(find.textContaining('octocat'), findsOneWidget);
    expect(find.text('Sign in with GitHub'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('error state shows the error message and a retry button', (
    tester,
  ) async {
    await pumpLogin(
      tester,
      const AuthFlowState.error('The user has denied your application access.'),
    );

    expect(
      find.text('The user has denied your application access.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('tapping "Sign in with GitHub" invokes the controller', (
    tester,
  ) async {
    var loginCalls = 0;
    await pumpLogin(
      tester,
      const AuthFlowState.idle(),
      onLogin: () => loginCalls++,
    );

    await tester.tap(find.text('Sign in with GitHub'));
    await tester.pump();

    expect(loginCalls, 1);
  });

  testWidgets(
    'tapping "Try again" from an error state invokes the controller',
    (tester) async {
      var loginCalls = 0;
      await pumpLogin(
        tester,
        const AuthFlowState.error('token exchange failed'),
        onLogin: () => loginCalls++,
      );

      await tester.tap(find.text('Try again'));
      await tester.pump();

      expect(loginCalls, 1);
    },
  );
}
