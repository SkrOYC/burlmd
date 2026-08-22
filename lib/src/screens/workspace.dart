import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The application's home surface: a minimal Workspace shell. This milestone
/// (`SHEL-E002`) presents it directly on launch, with no authentication gate;
/// `SHEL-E003` fills its body with the Directory tree.
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Failed to open workspace'),
              const SizedBox(height: 8),
              Text('$error'),
            ],
          ),
        ),
        data: (info) => Center(child: Text(info.name)),
      ),
    );
  }
}
