import 'package:burlmd/src/components/lifecycle_actions.dart';
import 'package:burlmd/src/components/status_message.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/l10n/generated/app_localizations.dart';
// The generated `TreeNode` variant types (`TreeNode_Directory`,
// `TreeNode_Note`) are not re-exported by `rust_api_provider.dart`, which
// only shows the sealed base — so the component imports the generated file
// directly for the pattern-matchable variants. The base `TreeNode` and the
// provider still flow through the `rust_api_provider` seam.
import 'package:burlmd/src/rust/index/query.dart'
    show TreeNode_Directory, TreeNode_Note;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Workspace rendered as a nested, expandable Directory tree
/// (`SHEL-E003`) — the primary navigation surface — now also the surface
/// where Note and Directory lifecycle actions live (`SHEL-E005`): every row
/// carries an overflow menu offering creation (on Directories), rename,
/// move (Notes) and deletion. Deletion always passes through a confirmation
/// dialog before it reaches [LifecycleActions]; name collisions come back
/// from the Core as refusals and are reported verbatim, never retried under
/// a disambiguated name.
///
/// The whole hierarchy arrives from a single Core call
/// (`workspaceTreeProvider`, the `WSPC-D009` contract), so expanding or
/// collapsing a Directory only filters what is *rendered* from data already
/// in memory: no further round trip, and no Workspace-wide reload per level.
/// The set of expanded paths is ephemeral UI state — the one kind
/// `tech-spec/guidelines.md` permits in widget state. No Note content is
/// ever held here.
///
/// Directories sort before Notes at each level, each group by name; empty
/// Directories appear (which is why they are indexed at all). Selecting a
/// Note publishes its concept id to [selectedNoteIdProvider] — the seam
/// `SHEL-E004`'s editor consumes — and fires [onNoteSelected] if given.
class WorkspaceTree extends ConsumerStatefulWidget {
  const WorkspaceTree({super.key, this.onNoteSelected});

  /// Invoked when the user selects a Note, in addition to the provider
  /// update. Optional; tests and future surfaces can observe selection
  /// without reading Riverpod directly.
  ///
  /// Standing dual-seam API kept for headless/embedded consumers and tests:
  /// production mounts drive selection purely through
  /// [selectedNoteIdProvider].
  final ValueChanged<String>? onNoteSelected;

  @override
  ConsumerState<WorkspaceTree> createState() => _WorkspaceTreeState();
}

class _WorkspaceTreeState extends ConsumerState<WorkspaceTree> {
  /// Paths of currently expanded Directories. Ephemeral UI state only.
  final Set<String> _expanded = {};

  void _toggle(String directoryPath) {
    setState(() {
      if (!_expanded.remove(directoryPath)) _expanded.add(directoryPath);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(workspaceTreeProvider);
    // Riverpod 3 schedules its own background retry after a failed load and
    // parks the state in a loading-with-error value in between; keying the
    // error branch on `when(error:)` alone would flash the failure for one
    // frame and drop back to a spinner. The flow's error state stands until
    // data actually returns — the Retry button forces an immediate refetch
    // instead of waiting out that backoff.
    final treeError = tree.hasError && tree.value == null ? tree.error : null;

    // Watched, not read: this is the selected-row highlight's only rebuild
    // trigger. Reading it left every row's `selected` stale after the first
    // tap (the P2 carried over from E003's review) — with a watch, a
    // selection change rebuilds the rows and moves the highlight.
    final selectedId = ref.watch(selectedNoteIdProvider);

    if (treeError != null) return const _TreeErrorState();

    return tree.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const _TreeErrorState(),
      data: (root) => ListView(children: _rows(root, selectedId)),
    );
  }

  List<Widget> _rows(
    List<TreeNode> nodes,
    String? selectedId, {
    int depth = 0,
  }) {
    // Defensive ordering: the Core contract already returns Directories
    // before Notes sorted by name at each level, but the rendered tree owns
    // this criterion regardless of input order.
    final directories = nodes.whereType<TreeNode_Directory>().toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final notes = nodes.whereType<TreeNode_Note>().toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    return [
      for (final directory in directories) ...[
        _DirectoryRow(
          node: directory,
          depth: depth,
          expanded: _expanded.contains(directory.path),
          onTap: () => _toggle(directory.path),
        ),
        if (_expanded.contains(directory.path))
          ..._rows(directory.children, selectedId, depth: depth + 1),
      ],
      for (final note in notes)
        _NoteRow(
          node: note,
          depth: depth,
          selected: selectedId == note.id,
          onTap: () {
            ref.read(selectedNoteIdProvider.notifier).select(note.id);
            widget.onNoteSelected?.call(note.id);
          },
        ),
    ];
  }
}

/// The sidebar's error state (flow-workspace-navigation.md failure path):
/// names the failure and offers Retry, which invalidates the tree provider
/// for an immediate refetch rather than waiting out Riverpod's automatic
/// retry backoff.
class _TreeErrorState extends ConsumerWidget {
  const _TreeErrorState();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Failed to load workspace tree',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        TextButton.icon(
          key: const ValueKey('tree-retry'),
          onPressed: () => ref.invalidate(workspaceTreeProvider),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _DirectoryRow extends ConsumerWidget {
  const _DirectoryRow({
    required this.node,
    required this.depth,
    required this.expanded,
    required this.onTap,
  });

  final TreeNode_Directory node;
  final int depth;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: 8.0 + depth * 16.0, right: 8.0),
      leading: Icon(
        expanded ? Icons.folder_open : Icons.folder,
        semanticLabel: expanded ? 'Expanded directory' : 'Directory',
      ),
      title: Text(node.name, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<String>(
        tooltip: 'Actions for directory ${node.name}',
        onSelected: (action) => switch (action) {
          'new-note' => _createNote(context, ref),
          'new-directory' => _createDirectory(context, ref),
          'rename' => _rename(context, ref),
          'delete' => _delete(context, ref),
          _ => Future<void>.value(),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'new-note', child: Text('New note here')),
          PopupMenuItem(
            value: 'new-directory',
            child: Text('New subdirectory'),
          ),
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: onTap,
    );
  }

  Future<void> _createNote(BuildContext context, WidgetRef ref) => _run(
    context,
    ref,
    () => promptForText(
      context,
      title: 'New note in "${node.name}"',
      label: 'Title',
    ),
    (title) => ref.read(lifecycleActionsProvider).createNote(node.path, title),
  );

  // The Core validates the joined path's segments itself (`/`, `..`,
  // absolute paths, NULs and line terminators all come back as
  // `PathUnavailable`) — no client-side duplicate here.
  Future<void> _createDirectory(BuildContext context, WidgetRef ref) => _run(
    context,
    ref,
    () => promptForText(
      context,
      title: 'New subdirectory in "${node.name}"',
      label: 'Name',
    ),
    (name) => ref
        .read(lifecycleActionsProvider)
        .createDirectory(joinDirectoryPath(node.path, name)),
  );

  Future<void> _rename(BuildContext context, WidgetRef ref) => _run(
    context,
    ref,
    () async {
      final newName = await promptForText(
        context,
        title: 'Rename directory "${node.name}"',
        label: 'New name',
        initialValue: node.name,
      );
      return (newName == null || newName == node.name) ? null : newName;
    },
    (newName) =>
        ref.read(lifecycleActionsProvider).renameDirectory(node.path, newName),
  );

  Future<void> _delete(BuildContext context, WidgetRef ref) => _run<bool>(
    context,
    ref,
    () async {
      // STOP guard: deletion is never offered to the Core without the user
      // confirming this dialog first.
      return await confirmDeletion(
            context,
            kind: 'directory',
            name: node.name,
            consequence:
                'Every note inside "${node.name}" is deleted with it. '
                'They stay recoverable from local version history.',
          )
          ? true
          : null;
    },
    (_) => ref.read(lifecycleActionsProvider).deleteDirectory(node.path),
  );
}

class _NoteRow extends ConsumerWidget {
  const _NoteRow({
    required this.node,
    required this.depth,
    required this.selected,
    required this.onTap,
  });

  final TreeNode_Note node;
  final int depth;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: 24.0 + depth * 16.0, right: 8.0),
      leading: const Icon(Icons.description, semanticLabel: 'Note'),
      title: Text(node.title, overflow: TextOverflow.ellipsis),
      selected: selected,
      trailing: PopupMenuButton<String>(
        tooltip: 'Actions for note ${node.title}',
        onSelected: (action) => switch (action) {
          'rename' => _rename(context, ref),
          'move' => _move(context, ref),
          'delete' => _delete(context, ref),
          _ => Future<void>.value(),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'move', child: Text('Move to directory…')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: onTap,
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) => _run(
    context,
    ref,
    () async {
      final newTitle = await promptForText(
        context,
        title: 'Rename note',
        label: 'New title',
        initialValue: node.title,
      );
      return (newTitle == null || newTitle == node.title) ? null : newTitle;
    },
    (newTitle) =>
        ref.read(lifecycleActionsProvider).renameNote(node.id, newTitle),
  );

  /// Moving happens through this explicit destination picker; drag-and-drop
  /// is not required by SHEL-E005.
  Future<void> _move(BuildContext context, WidgetRef ref) => _run(
    context,
    ref,
    () => pickDirectory(context, ref),
    (destination) =>
        ref.read(lifecycleActionsProvider).moveNote(node.id, destination),
  );

  Future<void> _delete(BuildContext context, WidgetRef ref) =>
      _run<bool>(context, ref, () async {
        // STOP guard: deletion is never offered to the Core without the user
        // confirming this dialog first.
        return await confirmDeletion(
              context,
              kind: 'note',
              name: node.title,
              consequence:
                  'It stays recoverable from local version history, but links '
                  'elsewhere that pointed at it will no longer resolve.',
            )
            ? true
            : null;
      }, (_) => ref.read(lifecycleActionsProvider).deleteNote(node.id));
}

// -- Dialogs and outcome reporting ------------------------------------------

/// Runs one lifecycle action end to end: [collect] shows the gating dialog
/// and returns the value to send to the Core (or `null` when the user
/// cancelled, declined, or entered an unchanged/no-op value), then [act]
/// performs the operation and [report] surfaces its outcome. Both mounted
/// checks are load-bearing: an unmounted context after the dialog means the
/// action is never sent, and one after it means the outcome is never shown.
Future<void> _run<T>(
  BuildContext context,
  WidgetRef ref,
  Future<T?> Function() collect,
  Future<LifecycleOutcome> Function(T value) act,
) async {
  final value = await collect();
  if (value == null) return;
  if (!context.mounted) return;
  final outcome = await act(value);
  if (!context.mounted) return;
  report(context, outcome);
}

/// Asks for one line of text (a title or a directory name). Returns the
/// trimmed input, or `null` when the dialog was dismissed. An empty submit
/// is reported as `null` too: there is nothing to send to the Core, and
/// inventing a fallback name client-side would defeat the point of the
/// Core-side collision check.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  required String label,
  String? initialValue,
}) async {
  final controller = TextEditingController(text: initialValue ?? '');
  // Pushed as an explicit route so the dialog's `completed` future is
  // reachable: the controller must outlive the popping route's exit
  // transition (its TextField stays attached — and cursor-blink ticks read
  // it — until teardown finishes), so disposing right after `showDialog`
  // returns would risk a use-after-dispose. Awaiting `completed` disposes
  // deterministically instead of leaking past the dialog's lifetime.
  final route = DialogRoute<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  final String? result;
  try {
    result = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
  } finally {
    controller.dispose();
  }
  return (result == null || result.isEmpty) ? null : result;
}

/// The confirmation gate every deletion must pass before reaching the Core.
/// Returns whether the user confirmed; dismissal and cancellation both mean
/// "no".
Future<bool> confirmDeletion(
  BuildContext context, {
  required String kind,
  required String name,
  required String consequence,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete $kind "$name"?'),
      content: Text(consequence),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Lets the user pick a Move destination from the Directories the current
/// tree snapshot knows about, bundle root included. Returns `null` when the
/// dialog was cancelled or the tree has not loaded yet.
Future<String?> pickDirectory(BuildContext context, WidgetRef ref) async {
  final root = ref.read(workspaceTreeProvider).asData?.value;
  if (root == null) return null;

  final paths = <String>[''];
  void collect(List<TreeNode> nodes) {
    for (final directory in nodes.whereType<TreeNode_Directory>()) {
      paths.add(directory.path);
      collect(directory.children);
    }
  }

  collect(root);
  String label(String path) => path.isEmpty ? '(workspace root)' : path;

  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Move to which directory?'),
      children: [
        for (final path in paths)
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(path),
            child: Text(label(path)),
          ),
      ],
    ),
  );
}

/// Surfaces a [LifecycleOutcome] to the user. Completions are silent — the
/// invalidated tree is the visible result — while refusals (the Core's own
/// collision report) and failures get a SnackBar, because doing nothing
/// after the user asked for something is how boundary errors get swallowed.
void report(BuildContext context, LifecycleOutcome outcome) {
  final message = switch (outcome) {
    LifecycleCompleted(:final warning) => switch (warning) {
      null => null,
      LifecycleWarning(:final stage, :final detail) => switch (stage) {
        LifecycleWarningStage.commit => AppLocalizations.of(
          context,
        )!.lifecycleCommitWarning(detail),
        LifecycleWarningStage.settlement => AppLocalizations.of(
          context,
        )!.lifecycleSettlementWarning(detail),
      },
    },
    LifecycleRefused(:final reason) => reason,
    LifecycleFailed(:final error) => 'The action failed: $error',
  };
  if (message == null) return;
  showStatusMessage(context, message);
}

/// Joins a parent Directory path (bundle-relative, `/`-separated, no leading
/// or trailing slash; empty string at the root) with a new segment.
String joinDirectoryPath(String parent, String name) =>
    parent.isEmpty ? name : '$parent/$name';
