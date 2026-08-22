import 'package:burlmd/src/rust/frb_generated.dart';
import 'package:burlmd/src/screens/workspace.dart';
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

/// Launches directly into the Workspace shell (SHEL-E002): with no
/// credentials and no network, [workspaceProvider] opens the local
/// Workspace through the Core's open-or-create path before anything else
/// happens, so no login gate stands in front of editing or navigation
/// (CAP-WS-01). Authentication state governs synchronization only; the login
/// screen and auth provider remain in place for the deferred connect flow
/// but are no longer a startup gate.
class _Home extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const WorkspaceScreen();
}
