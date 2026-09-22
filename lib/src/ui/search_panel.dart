import 'package:flutter/material.dart';

import '../etapi/etapi_client.dart';
import '../etapi/etapi_exception.dart';
import '../etapi/models/note.dart';
import 'note_presentation.dart';

/// How many matches a single search asks for.
///
/// A bare word against a large instance can match thousands of notes, and
/// ETAPI returns a full note payload for every one of them. This pane is a
/// sidebar rather than a report, so fetch somewhat more than fits on screen and
/// say plainly when the cap was reached.
const int searchResultLimit = 100;

/// Search pane for the sidebar.
///
/// The input is Trilium's own query language rather than a set of filter
/// widgets, so anything expressible in Trilium is expressible here. The two
/// toggles cover only the flags ETAPI takes as separate parameters, which have
/// no query-syntax equivalent.
class SearchPanel extends StatefulWidget {
  const SearchPanel({
    super.key,
    required this.client,
    required this.selectedNoteId,
    required this.onSelect,
    this.focusNode,
  });

  final EtapiClient client;
  final String? selectedNoteId;
  final ValueChanged<Note> onSelect;

  /// Supplied by the parent when a window-level shortcut needs to put the
  /// cursor in the query field. When null the panel owns its own node.
  final FocusNode? focusNode;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();

  /// Matches from the last completed search. Null means nothing has been
  /// submitted yet, which is a different state from "searched and found
  /// nothing".
  List<Note>? _matches;

  bool _loading = false;
  Object? _error;

  /// The query behind [_matches], kept so the empty state can quote it back.
  String _submitted = '';

  /// Incremented per search so a response can tell whether it is still wanted.
  ///
  /// Awaiting the client directly rather than handing the future to a
  /// FutureBuilder, because a search that fails faster than the next rebuild
  /// would complete with an error nobody was listening for yet, which Dart
  /// reports as an unhandled async error.
  int _requestId = 0;

  bool _titlesOnly = false;
  bool _includeArchived = false;

  @override
  void dispose() {
    _controller.dispose();
    // Only dispose a node this widget created. The parent's node outlives us.
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      // Submitting an empty box clears rather than searching. Trilium treats an
      // empty query as "match everything", which would drag the whole instance
      // across the wire for what is almost always a stray Enter.
      setState(_reset);
      return;
    }

    final id = ++_requestId;
    setState(() {
      _submitted = query;
      _loading = true;
      _error = null;
      _matches = null;
    });

    try {
      final notes = await widget.client.search(
        query,
        fastSearch: _titlesOnly,
        includeArchivedNotes: _includeArchived,
        limit: searchResultLimit,
      );
      _settle(id, matches: notes);
    } on EtapiException catch (error) {
      _settle(id, error: error);
    } catch (error) {
      // The client throws nothing else today, but a spinner that never stops
      // would be a worse failure than an honest generic message if it ever
      // does.
      _settle(id, error: error);
    }
  }

  /// Applies a finished search, unless it has been superseded by a newer one or
  /// the panel is gone.
  void _settle(int id, {List<Note>? matches, Object? error}) {
    if (!mounted || id != _requestId) return;
    setState(() {
      _matches = matches;
      _error = error;
      _loading = false;
    });
  }

  void _reset() {
    // Bumping the id orphans any search still in flight, so a response that
    // lands after the box was cleared cannot repopulate it.
    _requestId++;
    _matches = null;
    _error = null;
    _loading = false;
    _submitted = '';
  }

  void _clear() {
    _controller.clear();
    setState(_reset);
    _focusNode.requestFocus();
  }

  /// Applies a flag change and re-runs, because a toggle that appears to do
  /// nothing until you press Enter again reads as broken.
  void _setFlag(VoidCallback change) {
    setState(change);
    if (_submitted.isNotEmpty) _run();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search notes',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, child) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Clear',
                        onPressed: _clear,
                      ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _FlagChip(
                label: 'Titles only',
                tooltip: 'Match titles instead of full note text. Much faster '
                    'on a large instance.',
                selected: _titlesOnly,
                onSelected: (value) => _setFlag(() => _titlesOnly = value),
              ),
              _FlagChip(
                label: 'Archived',
                tooltip: 'Include notes labelled archived, which Trilium '
                    'leaves out by default.',
                selected: _includeArchived,
                onSelected: (value) => _setFlag(() => _includeArchived = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(child: _buildResults()),
      ],
    );
  }

  Widget _buildResults() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error case final error?) {
      return _SearchError(error: error, onRetry: _run);
    }

    final notes = _matches;
    if (notes == null) return const _SearchHint();
    if (notes.isEmpty) return _NoMatches(query: _submitted);

    // One extra row at the top carries the count, so it scrolls away with the
    // results instead of stealing sidebar height permanently.
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: notes.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _ResultCount(count: notes.length);
        final note = notes[index - 1];
        return _ResultRow(
          note: note,
          selected: note.noteId == widget.selectedNoteId,
          onTap: () => widget.onSelect(note),
        );
      },
    );
  }
}

class _FlagChip extends StatelessWidget {
  const _FlagChip({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: onSelected,
        labelStyle: Theme.of(context).textTheme.labelSmall,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Trilium applies the limit server side, so a full page is indistinguishable
    // from a result set that happens to be exactly this size. Say "first" and
    // stay honest rather than claiming a total we cannot know.
    final capped = count >= searchResultLimit;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Text(
        capped
            ? 'First $searchResultLimit matches. Narrow the query to see fewer.'
            : '$count ${count == 1 ? 'match' : 'matches'}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.note,
    required this.selected,
    required this.onTap,
  });

  final Note note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modified = note.dateModified;
    final detail = [
      if (note.type != 'text') note.type,
      if (note.isArchived) 'archived',
      if (modified != null) formatNoteDate(modified),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? theme.colorScheme.secondaryContainer : null,
        padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                noteTypeIcon(note),
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown before anything has been searched.
///
/// Trilium's query syntax is genuinely not guessable, and an empty pane teaches
/// nothing, so the idle state doubles as the documentation for it.
class _SearchHint extends StatelessWidget {
  const _SearchHint();

  static const _examples = <(String, String)>[
    ('homelab', 'anywhere in the text'),
    ('#book', 'has the label'),
    ('#year >= 2020', 'label compared'),
    ('"exact phrase"', 'quoted phrase'),
    ('note.title *=* wiki', 'title contains'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Searches use Trilium\'s own query syntax.', style: muted),
          const SizedBox(height: 12),
          for (final (query, meaning) in _examples)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    query,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(meaning, style: muted),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No notes match $query.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // An invalid query is the common case here and Trilium explains it better
    // than we could, so show its own message when there is one.
    final message = error is EtapiException
        ? (error as EtapiException).message
        : 'The search could not be run.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
