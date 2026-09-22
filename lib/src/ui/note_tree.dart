import 'package:flutter/material.dart';

import '../etapi/etapi_client.dart';
import '../etapi/etapi_exception.dart';
import '../etapi/models/note.dart';
import 'note_presentation.dart';

/// Lazily loaded note tree.
///
/// Children are fetched the first time a node is expanded and then kept, so
/// collapsing and reopening a branch does not re-hit the server. A Trilium tree
/// can be arbitrarily deep with thousands of notes, so loading it eagerly is
/// not an option.
class NoteTreeView extends StatefulWidget {
  const NoteTreeView({
    super.key,
    required this.client,
    required this.selectedNoteId,
    required this.onSelect,
  });

  final EtapiClient client;
  final String? selectedNoteId;
  final ValueChanged<Note> onSelect;

  @override
  State<NoteTreeView> createState() => _NoteTreeViewState();
}

class _NoteTreeViewState extends State<NoteTreeView> {
  late Future<List<Note>> _roots;

  @override
  void initState() {
    super.initState();
    _roots = widget.client.children(rootNoteId);
  }

  void _reload() {
    setState(() => _roots = widget.client.children(rootNoteId));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Note>>(
      future: _roots,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _TreeError(error: snapshot.error!, onRetry: _reload);
        }

        final notes = snapshot.data ?? const <Note>[];
        if (notes.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('This instance has no notes yet.'),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: notes.length,
          itemBuilder: (context, index) => NoteTreeNode(
            note: notes[index],
            depth: 0,
            client: widget.client,
            selectedNoteId: widget.selectedNoteId,
            onSelect: widget.onSelect,
          ),
        );
      },
    );
  }
}

/// One row of the tree, plus its children once expanded.
@visibleForTesting
class NoteTreeNode extends StatefulWidget {
  const NoteTreeNode({
    super.key,
    required this.note,
    required this.depth,
    required this.client,
    required this.selectedNoteId,
    required this.onSelect,
  });

  final Note note;
  final int depth;
  final EtapiClient client;
  final String? selectedNoteId;
  final ValueChanged<Note> onSelect;

  @override
  State<NoteTreeNode> createState() => _NoteTreeNodeState();
}

class _NoteTreeNodeState extends State<NoteTreeNode> {
  bool _expanded = false;
  Future<List<Note>>? _children;

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      _children ??= widget.client.children(widget.note.noteId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = widget.note.noteId == widget.selectedNoteId;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => widget.onSelect(widget.note),
          child: Container(
            color: isSelected ? theme.colorScheme.secondaryContainer : null,
            padding: EdgeInsets.only(
              left: 4.0 + widget.depth * 16,
              right: 8,
              top: 6,
              bottom: 6,
            ),
            child: Row(
              children: [
                // Leaf notes still get the chevron's footprint, so titles at
                // the same depth line up whether or not they have children.
                SizedBox(
                  width: 24,
                  child: widget.note.hasChildren
                      ? InkWell(
                          onTap: _toggle,
                          borderRadius: BorderRadius.circular(4),
                          child: Icon(
                            _expanded
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_right,
                            size: 20,
                          ),
                        )
                      : null,
                ),
                Icon(
                  noteTypeIcon(widget.note),
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.note.title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          FutureBuilder<List<Note>>(
            future: _children,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: EdgeInsets.only(
                    left: 32.0 + widget.depth * 16,
                    top: 4,
                    bottom: 4,
                  ),
                  child: const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: EdgeInsets.only(
                    left: 32.0 + widget.depth * 16,
                    top: 4,
                    bottom: 4,
                  ),
                  child: Text(
                    'Could not load children.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                );
              }
              final children = snapshot.data ?? const <Note>[];
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final child in children)
                    NoteTreeNode(
                      key: ValueKey(child.noteId),
                      note: child,
                      depth: widget.depth + 1,
                      client: widget.client,
                      selectedNoteId: widget.selectedNoteId,
                      onSelect: widget.onSelect,
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _TreeError extends StatelessWidget {
  const _TreeError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message =
        error is EtapiException ? (error as EtapiException).message : '$error';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
