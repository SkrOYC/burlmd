import 'dart:io';

import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/frb_generated.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/screens/workspace.dart';
import 'package:burlmd/l10n/generated/app_localizations.dart';
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
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _Home(),
    );
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
    if (Platform.environment.containsKey('BURLMD_SMOKE_F001')) {
      _stageSmokeF001();
    }
    if (Platform.environment.containsKey('BURLMD_SMOKE_F003')) {
      _stageSmokeF003();
    }
    if (Platform.environment.containsKey('BURLMD_SMOKE_F004')) {
      _stageSmokeF004();
    }
    if (Platform.environment.containsKey('BURLMD_SMOKE_F005')) {
      _stageSmokeF005();
    }
    if (Platform.environment.containsKey('BURLMD_SMOKE_F006')) {
      _stageSmokeF006();
    }
    if (Platform.environment.containsKey('BURLMD_SMOKE_F007')) {
      _stageSmokeF007();
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

  /// Production-font fixture for SPK-EDIT-F001's durable visual evidence.
  /// Each source sits deliberately near a natural wrap boundary in the real
  /// editor pane; `BURLMD_SMOKE_F001_FOCUSED_INDEX` chooses which one is raw.
  Future<void> _stageSmokeF001() async {
    const title = 'F001 promotion wrap evidence';
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
      try {
        await api.deleteNote(title);
        state = await api.createNote('', title);
      } catch (_) {
        return;
      }
    }
    const boundaryWords =
        'word word word word word word word word word word '
        'word word word word word word word word';
    for (final source in [
      '$boundaryWords **tail**',
      '## $boundaryWords **tail**',
      '- $boundaryWords **tail**',
    ]) {
      state = api.insertBlock(state!.metadata.id, [state.ast.length], source);
    }
    ref.invalidate(workspaceTreeProvider);
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

  /// Staging half of the `scripts/smoke-shot.sh f004-block-editing` hook
  /// (`EDIT-F004`); the promote-and-Enter half lives in the editor. Builds
  /// the demo Note through the Core and selects it — same structural reason
  /// as the F002/F003 halves above. Inert without the QA-harness variable.
  Future<void> _stageSmokeF004() async {
    const title = 'F004 block editing';
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
    final sources = [
      'First paragraph with a **bold** run inside',
      'Second paragraph stays formatted',
      'Third paragraph for company',
    ];
    for (final source in sources) {
      if (!mounted) return;
      state = api.insertBlock(state!.metadata.id, [state.ast.length], source);
    }
    ref.invalidate(workspaceTreeProvider);
    ref.read(selectedNoteIdProvider.notifier).select(state!.metadata.id);
  }

  /// Staging half of the `EDIT-F005` smoke hook. The editor owns promotion
  /// and the raw-source shortcut itself; this only creates and selects the
  /// Core-owned fixture required for an honest focused-Block interaction.
  Future<void> _stageSmokeF005() async {
    const title = 'F005 emphasis';
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
      try {
        await api.deleteNote(title);
        state = await api.createNote('', title);
      } catch (_) {
        return;
      }
    }
    state = api.insertBlock(state.metadata.id, [
      state.ast.length,
    ], 'shortcut target');
    ref.invalidate(workspaceTreeProvider);
    ref.read(selectedNoteIdProvider.notifier).select(state.metadata.id);
  }

  /// Builds both halves of F006 through Core: a real target Note for the
  /// completion resolver and a source Note whose only Block ends at a valid
  /// `[[` query. The Editor performs promotion, completion acceptance, commit
  /// and re-resolved link follow; the shell rejects all earlier states.
  Future<void> _stageSmokeF006() async {
    const targetTitle = 'F006 target';
    const title = 'F006 link completion';
    final api = ref.read(rustApiProvider);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (ref.read(workspaceProvider).hasValue) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    try {
      try {
        await api.deleteNote(targetTitle);
      } catch (_) {}
      try {
        await api.deleteNote(title);
      } catch (_) {}
      await api.createNote('', targetTitle);
      var state = await api.createNote('', title);
      state = api.insertBlock(state.metadata.id, [
        state.ast.length,
      ], '[[$targetTitle');
      ref.invalidate(workspaceTreeProvider);
      ref.read(selectedNoteIdProvider.notifier).select(state.metadata.id);
    } catch (_) {
      // No marker is emitted on a failed stage, so the smoke harness rejects
      // the generic shell window rather than producing misleading evidence.
    }
  }

  /// Stages the two Core-backed Notes used by the F007 proxy smoke. The UI
  /// driver performs type-over and paste on the first, then opens the second
  /// to prove a complete range deletion receives Core's phantom caret.
  Future<void> _stageSmokeF007() async {
    const typeTitle = 'F007 range type paste';
    const deleteTitle = 'F007 range delete phantom';
    final api = ref.read(rustApiProvider);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (ref.read(workspaceProvider).hasValue) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    try {
      for (final title in [typeTitle, deleteTitle]) {
        try {
          await api.deleteNote(title);
        } catch (_) {
          // The fixture may not exist yet.
        }
      }
      var type = await api.createNote('', typeTitle);
      for (final source in ['first range', 'middle range', 'tail range']) {
        type = api.insertBlock(type.metadata.id, [type.ast.length], source);
      }
      var deletion = await api.createNote('', deleteTitle);
      for (final source in ['delete first', 'delete middle', 'delete tail']) {
        deletion = api.insertBlock(deletion.metadata.id, [
          deletion.ast.length,
        ], source);
      }
      ref.invalidate(workspaceTreeProvider);
      ref.read(selectedNoteIdProvider.notifier).select(type.metadata.id);
    } catch (_) {
      // A missing readiness marker makes the shell reject this run.
    }
  }
}
