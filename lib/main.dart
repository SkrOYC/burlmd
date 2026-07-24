import 'package:burlmd/src/providers/auth_provider.dart';
import 'package:burlmd/src/rust/frb_generated.dart';
import 'package:burlmd/src/screens/login.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: _Home());
  }
}

/// Least-invasive gate in front of the rest of the app: `main.dart` had no
/// notion of authentication state before SYNC-C002, so there is no existing
/// "already logged in" signal to check on startup — [authControllerProvider]
/// starts every process at [AuthStatus.idle], and only reaches
/// [AuthStatus.success] via a fresh, in-session `authenticate_workspace`
/// call. This means a restart currently re-shows [LoginScreen] even though
/// a token from a prior session may already be sitting in the OS Keychain;
/// wiring a real "check for an existing session" FFI call is out of scope
/// for this ticket (no such contract function exists) and is recorded as a
/// deferred follow-up rather than invented here.
class _Home extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(authControllerProvider);
    if (flow.status != AuthStatus.success) {
      return const LoginScreen();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('burlmd')),
      body: const Center(child: Text('burlmd')),
    );
  }
}
