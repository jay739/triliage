import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../etapi/etapi_client.dart';
import '../etapi/etapi_exception.dart';
import '../etapi/models/note.dart';

/// Read-only rendering of a single note's body.
///
/// Trilium stores ordinary text notes as HTML, so HTML is the primary path.
/// Code notes are shown as monospaced source, and anything needing a renderer
/// we do not have yet says so plainly rather than rendering an empty pane.
class NoteViewer extends StatefulWidget {
  const NoteViewer({super.key, required this.client, required this.note});

  final EtapiClient client;
  final Note note;

  @override
  State<NoteViewer> createState() => _NoteViewerState();
}

class _NoteViewerState extends State<NoteViewer> {
  late Future<String> _content;

  @override
  void initState() {
    super.initState();
    _content = _load();
  }

  @override
  void didUpdateWidget(NoteViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent reuses this widget when the selection changes, so refetch
    // whenever the note actually differs.
    if (oldWidget.note.noteId != widget.note.noteId) {
      _content = _load();
    }
  }

  Future<String> _load() => widget.client.noteContent(widget.note.noteId);

  @override
  Widget build(BuildContext context) {
    final note = widget.note;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NoteHeader(note: note),
        const Divider(height: 1),
        Expanded(
          child: note.isReadable
              ? _buildBody(context)
              : _Unsupported(note: note),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    return FutureBuilder<String>(
      future: _content,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          final error = snapshot.error!;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error is EtapiException
                    ? error.message
                    : 'Could not load this note.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          );
        }

        final body = snapshot.data ?? '';
        if (body.trim().isEmpty) {
          return const Center(child: Text('This note is empty.'));
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: widget.note.isCode
              ? SelectableText(
                  body,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                )
              : SelectionArea(child: HtmlWidget(body)),
        );
      },
    );
  }
}

class _NoteHeader extends StatelessWidget {
  const _NoteHeader({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modified = note.dateModified;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(note.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            [
              note.type,
              if (modified != null) 'modified ${_formatDate(modified)}',
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (note.attributes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final attribute in note.attributes)
                  Chip(
                    label: Text(attribute.displayForm),
                    labelStyle: theme.textTheme.labelSmall,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Deliberately plain and locale-independent. Pulling in `intl` for one
  /// timestamp is not worth the dependency yet.
  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _Unsupported extends StatelessWidget {
  const _Unsupported({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, message) = switch (note) {
      Note(isProtected: true) => (
          Icons.lock_outline,
          'This note is protected. Trilium encrypts protected notes and the '
              'External API cannot decrypt them, so it can only be read in '
              'Trilium itself.',
        ),
      Note(type: 'image') => (
          Icons.image_outlined,
          'Image notes are not rendered yet.',
        ),
      Note(type: 'file') => (
          Icons.attach_file,
          'File attachments are not rendered yet.',
        ),
      _ => (
          Icons.help_outline,
          'Notes of type "${note.type}" are not rendered yet.',
        ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
