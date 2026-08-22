import 'package:burlmd/src/components/editor.dart';
import 'package:burlmd/src/components/workspace_tree.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The application's home surface: a Workspace shell with the Directory
/// tree as its navigation sidebar (`SHEL-E003`) and the editor for the
/// selected Note as its main pane (`SHEL-E004`).
class WorkspaceScreen extends ConsumerWidget {
  const WorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(workspaceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('burlmd')),
      body: workspace.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          // Soft-wrapped and scrollable so a long error can neither overflow
          // horizontally nor push its siblings off screen.
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Failed to open workspace'),
                    const SizedBox(height: 8),
                    Text('$error', textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        ),
        data: (info) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 280,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      info.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const Expanded(child: WorkspaceTree()),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            const Expanded(child: _EditorPane()),
          ],
        ),
      ),
    );
  }
}

/// The shell's main pane (`SHEL-E004`): the editor for whichever Note the
/// tree has selected. Selection is published by [WorkspaceTree] through
/// [selectedNoteIdProvider]; this pane reacts to it by driving
/// [NoteController.open], which closes the outgoing Note through the Core
/// before opening the new one, so navigation alone keeps every editing
/// session committed to version history.
class _EditorPane extends ConsumerWidget {
  const _EditorPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedNoteIdProvider);
    // Side effect lives in a listener, not in build's body: selection
    // changes fire exactly once per change, so no rebuild can re-issue an
    // open for a Note already being opened.
    ref.listen<String?>(selectedNoteIdProvider, (_, next) {
      if (next != null) ref.read(activeNoteProvider.notifier).open(next);
    });
    if (selectedId == null) {
      return const Center(child: Text('Select a note to open it'));
    }
    return const Editor();
  }
}
