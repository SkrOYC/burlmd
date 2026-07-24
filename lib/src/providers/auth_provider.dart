import 'dart:async';
import 'dart:io';

import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// The GitHub OAuth PKCE flow's current phase (SYNC-C002). Widgets read
/// this via [authControllerProvider] rather than holding any flow state of
/// their own — `guidelines.md`'s Dart statelessness rule.
enum AuthStatus { idle, waitingForBrowser, exchanging, success, error }

/// Immutable snapshot of the OAuth flow. `workspaceId` is only set once
/// [status] is [AuthStatus.success]; `errorMessage` only once it's
/// [AuthStatus.error]. Never carries an access/refresh token — Core stores
/// those directly in the OS Keychain and only ever returns the workspace id
/// across the FFI boundary.
class AuthFlowState {
  const AuthFlowState._(this.status, {this.workspaceId, this.errorMessage});

  const AuthFlowState.idle() : this._(AuthStatus.idle);

  const AuthFlowState.waitingForBrowser()
    : this._(AuthStatus.waitingForBrowser);

  const AuthFlowState.exchanging() : this._(AuthStatus.exchanging);

  const AuthFlowState.success(String workspaceId)
    : this._(AuthStatus.success, workspaceId: workspaceId);

  const AuthFlowState.error(String message)
    : this._(AuthStatus.error, errorMessage: message);

  final AuthStatus status;
  final String? workspaceId;
  final String? errorMessage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthFlowState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          workspaceId == other.workspaceId &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(status, workspaceId, errorMessage);
}

/// A minimal "you can close this tab" landing page served to the browser on
/// the loopback redirect, so the user isn't left staring at a blank tab or
/// a connection-reset error after GitHub redirects back.
const String _redirectLandingPageHtml = '''
<!DOCTYPE html>
<html>
  <head><title>burlmd</title></head>
  <body style="font-family: sans-serif; text-align: center; margin-top: 3em;">
    <p>Signed in. You can close this tab and return to burlmd.</p>
  </body>
</html>
''';

/// Drives the OAuth PKCE flow (SYNC-C002): asks Core for the authorize URL
/// and PKCE verifier/state ([RustApi.beginOAuthFlow]), opens it in the
/// system browser, runs a loopback [HttpServer] to capture the redirect,
/// validates `state`, and hands the authorization code plus verifier back
/// to Core ([RustApi.authenticateWorkspace]) to complete the exchange.
class AuthController extends Notifier<AuthFlowState> {
  HttpServer? _server;

  @override
  AuthFlowState build() {
    ref.onDispose(() {
      unawaited(_closeServer());
    });
    return const AuthFlowState.idle();
  }

  /// Runs the full flow. Safe to call again after an [AuthStatus.error]
  /// state to retry.
  Future<void> loginWithGitHub({String provider = 'github'}) async {
    state = const AuthFlowState.waitingForBrowser();

    final HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } catch (e) {
      state = AuthFlowState.error(
        'Could not start the local callback listener: $e',
      );
      return;
    }
    _server = server;

    final redirectUri = 'http://127.0.0.1:${server.port}/callback';

    final OAuthFlowStart flow;
    try {
      flow = ref.read(rustApiProvider).beginOAuthFlow(provider, redirectUri);
    } catch (e) {
      await _closeServer();
      state = AuthFlowState.error('Failed to start the OAuth flow: $e');
      return;
    }

    bool opened;
    try {
      opened = await launchUrl(
        Uri.parse(flow.authorizeUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      opened = false;
    }
    if (!opened) {
      await _closeServer();
      state = const AuthFlowState.error('Could not open the system browser.');
      return;
    }

    final HttpRequest request;
    try {
      // A loopback redirect can, in principle, be preceded by an unrelated
      // probe request (e.g. a stray `/favicon.ico` fetch); wait specifically
      // for the one carrying either `code` or `error`, the two query params
      // GitHub's redirect always sets.
      request = await server
          .firstWhere(
            (req) =>
                req.uri.queryParameters.containsKey('code') ||
                req.uri.queryParameters.containsKey('error'),
          )
          .timeout(const Duration(minutes: 5));
    } catch (e) {
      await _closeServer();
      state = const AuthFlowState.error(
        'Timed out waiting for GitHub to redirect back.',
      );
      return;
    }

    final params = request.uri.queryParameters;
    await _respondAndClose(request);
    await _closeServer();

    final oauthError = params['error'];
    if (oauthError != null) {
      state = AuthFlowState.error(params['error_description'] ?? oauthError);
      return;
    }

    final returnedState = params['state'];
    final code = params['code'];
    if (code == null || returnedState == null || returnedState != flow.state) {
      state = const AuthFlowState.error(
        'Invalid redirect from GitHub (missing code or mismatched state).',
      );
      return;
    }

    state = const AuthFlowState.exchanging();
    try {
      final workspaceId = await ref
          .read(rustApiProvider)
          .authenticateWorkspace(provider, code, flow.codeVerifier);
      state = AuthFlowState.success(workspaceId);
    } catch (e) {
      state = AuthFlowState.error('Token exchange failed: $e');
    }
  }

  /// Resets back to [AuthStatus.idle], e.g. so a "try again" button can
  /// clear a stale [AuthStatus.error]/[AuthStatus.success] state.
  void reset() {
    state = const AuthFlowState.idle();
  }

  Future<void> _respondAndClose(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(_redirectLandingPageHtml);
    await request.response.close();
  }

  Future<void> _closeServer() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthFlowState>(
  AuthController.new,
);
