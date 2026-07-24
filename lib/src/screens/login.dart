import 'package:burlmd/src/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The GitHub OAuth login screen (SYNC-C002). Stateless regarding the flow
/// itself — all state lives in [authControllerProvider]; this widget only
/// renders whichever [AuthFlowState] it's currently in and forwards the
/// "sign in" tap to [AuthController.loginWithGitHub].
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(authControllerProvider);
    final controller = ref.read(authControllerProvider.notifier);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'burlmd',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('Sign in to sync your notes.'),
                const SizedBox(height: 24),
                _FlowBody(flow: flow, controller: controller),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlowBody extends StatelessWidget {
  const _FlowBody({required this.flow, required this.controller});

  final AuthFlowState flow;
  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    switch (flow.status) {
      case AuthStatus.idle:
        return _SignInButton(onPressed: controller.loginWithGitHub);
      case AuthStatus.waitingForBrowser:
        return const _Busy(
          message: 'Waiting for you to authorize in the browser…',
        );
      case AuthStatus.exchanging:
        return const _Busy(message: 'Finishing sign-in…');
      case AuthStatus.success:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 40),
            const SizedBox(height: 12),
            Text('Signed in as ${flow.workspaceId}'),
          ],
        );
      case AuthStatus.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              flow.errorMessage ?? 'Sign-in failed.',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _SignInButton(
              label: 'Try again',
              onPressed: controller.loginWithGitHub,
            ),
          ],
        );
    }
  }
}

class _SignInButton extends StatelessWidget {
  const _SignInButton({
    required this.onPressed,
    this.label = 'Sign in with GitHub',
  });

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(onPressed: onPressed, child: Text(label));
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
      ],
    );
  }
}
