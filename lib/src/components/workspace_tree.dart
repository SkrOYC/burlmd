import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
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
/// (`SHEL-E003`) — the primary navigation surface.
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
    // Watched, not read: this is the selected-row highlight's only rebuild
    // trigger. Reading it left every row's `selected` stale after the first
    // tap (the P2 carried over from E003's review) — with a watch, a
    // selection change rebuilds the rows and moves the highlight.
    final selectedId = ref.watch(selectedNoteIdProvider);

    return tree.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Failed to load workspace tree',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
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

class _DirectoryRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: 8.0 + depth * 16.0, right: 8.0),
      leading: Icon(
        expanded ? Icons.folder_open : Icons.folder,
        semanticLabel: expanded ? 'Expanded folder' : 'Folder',
      ),
      title: Text(node.name, overflow: TextOverflow.ellipsis),
      trailing: Icon(
        expanded ? Icons.expand_less : Icons.expand_more,
        semanticLabel: expanded ? 'Collapse' : 'Expand',
      ),
      onTap: onTap,
    );
  }
}

class _NoteRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: 24.0 + depth * 16.0, right: 8.0),
      leading: const Icon(Icons.description, semanticLabel: 'Note'),
      title: Text(node.title, overflow: TextOverflow.ellipsis),
      selected: selected,
      onTap: onTap,
    );
  }
}
