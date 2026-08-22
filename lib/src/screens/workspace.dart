import 'package:burlmd/src/components/workspace_tree.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The application's home surface: a Workspace shell with the Directory tree
/// as its navigation sidebar (`SHEL-E003`). The main pane's placeholder is
/// where `SHEL-E004` mounts the editor for the selected Note.
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
            const Expanded(child: SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}
