import 'dart:io';

import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/frb_generated.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
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
class _Home extends ConsumerStatefulWidget {
  @override
  ConsumerState<_Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<_Home> {
  @override
  void initState() {
    super.initState();
    if (Platform.environment.containsKey('BURLMD_SMOKE_F002')) {
      _stageSmokeF002();
    }
    if (Platform.environment.containsKey('BURLMD_SMOKE_F003')) {
      _stageSmokeF003();
    }
  }

  @override
  Widget build(BuildContext context) => const WorkspaceScreen();

  // -- BURLMD_SMOKE_F002 / BURLMD_SMOKE_F003 (staging half) ----------------
  //
  // Manual-QA staging for `scripts/smoke-shot.sh f002-live-preview` and
  // `f003-selection`: build a demo Note *through the Core* (create_note +
  // insert_block — no Dart-held content), refresh the tree, and select it so
  // the editor pane mounts. The Editor only mounts once a Note is selected,
  // so it cannot stage its own Note; the promote/select-all halves of these
  // hooks live in the editor. Gated behind environment variables set only by
  // the QA harness; inert in normal use.

  Future<void> _stageSmokeF002() async {
    const title = 'F002 live preview';
    final api = ref.read(rustApiProvider);
    // Wait for the workspace bootstrap to finish before creating anything.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (ref.read(workspaceProvider).hasValue) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    NoteState? state;
    try {
      state = await api.createNote('', title);
    } catch (_) {
      // A previous smoke run left the Note behind: delete and recreate.
      try {
        await api.deleteNote(title);
        state = await api.createNote('', title);
      } catch (_) {
        return;
      }
    }
    final sources = [
      'Intro with **bold** words mid-sentence here',
      '## A section heading',
      '- first list item',
      '> quoted words',
      '---',
    ];
    for (final source in sources) {
      if (!mounted) return;
      state = api.insertBlock(state!.metadata.id, [state.ast.length], source);
    }
    ref.invalidate(workspaceTreeProvider);
    // Selecting drives the shell's editor-pane listener, which opens the
    // Note through [NoteController.open] — the same path a user tap takes.
    ref.read(selectedNoteIdProvider.notifier).select(state!.metadata.id);
  }

  Future<void> _stageSmokeF003() async {
    const title = 'F003 cross-block selection';
    final api = ref.read(rustApiProvider);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (ref.read(workspaceProvider).hasValue) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    NoteState? state;
    try {
      state = await api.createNote('', title);
    } catch (_) {
      // A previous smoke run left the Note behind: delete and recreate.
      try {
        await api.deleteNote(title);
        state = await api.createNote('', title);
      } catch (_) {
        return;
      }
    }
    // Heterogeneous fixture — code block, list, paragraph — because the
    // rendered-text offsets a BlockRange carries are defined per AstNode
    // variant; three paragraphs would exercise exactly one definition.
    final sources = [
      '```rust\nlet answer = 42;\nprintln!("{answer}");\n```',
      '- gather notes\n- link ideas\n- review draft',
      'A closing **paragraph** across Blocks',
    ];
    for (final source in sources) {
      if (!mounted) return;
      state = api.insertBlock(state!.metadata.id, [state.ast.length], source);
    }
    ref.invalidate(workspaceTreeProvider);
    ref.read(selectedNoteIdProvider.notifier).select(state!.metadata.id);
  }
}
