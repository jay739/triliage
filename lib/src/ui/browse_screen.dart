import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_session.dart';
import '../etapi/etapi_client.dart';
import '../etapi/models/note.dart';
import 'note_tree.dart';
import 'note_viewer.dart';
import 'search_panel.dart';

/// Which view the sidebar is currently showing.
enum SidebarTab { tree, search }

/// The main window once connected: note tree on the left, reader on the right.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.session});

  final AppSession session;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  Note? _selected;
  SidebarTab _tab = SidebarTab.tree;

  /// Held here rather than inside the panel so Ctrl+F can move the cursor into
  /// the query field from anywhere in the window.
  final _searchFocus = FocusNode();

  /// Width of the tree pane. Draggable, because note titles vary wildly in
  /// length and a fixed sidebar truncates either constantly or never.
  double _sidebarWidth = 320;

  static const _minSidebar = 200.0;
  static const _maxSidebar = 560.0;

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  void _showSearch() {
    setState(() => _tab = SidebarTab.search);
    // Deferred to after the rebuild: until then the query field is still the
    // hidden child of the IndexedStack, and asking a hidden field for focus
    // does not reliably stick.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final client = session.client;
    if (client == null) {
      // Only reachable in the instant between disconnect and the parent
      // swapping this screen out.
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _showSearch,
      },
      // Something in the subtree has to hold focus for the shortcut to be
      // reached, and nothing is focused at the moment the window opens.
      child: Focus(
        autofocus: true,
        child: _buildScaffold(context, theme, client, session),
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    ThemeData theme,
    EtapiClient client,
    AppSession session,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(session.profile?.displayName ?? 'triliage'),
        actions: [
          if (session.appInfo case final info?)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  'Trilium ${info.appVersion}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Disconnect',
            onPressed: () => _confirmDisconnect(context),
          ),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: _sidebarWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: SegmentedButton<SidebarTab>(
                    segments: const [
                      ButtonSegment(
                        value: SidebarTab.tree,
                        icon: Icon(Icons.account_tree_outlined, size: 18),
                        label: Text('Tree'),
                      ),
                      ButtonSegment(
                        value: SidebarTab.search,
                        icon: Icon(Icons.search, size: 18),
                        label: Text('Search'),
                      ),
                    ],
                    selected: {_tab},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      if (selection.first == SidebarTab.search) {
                        _showSearch();
                      } else {
                        setState(() => _tab = selection.first);
                      }
                    },
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const Divider(height: 1),
                // IndexedStack rather than swapping widgets, because the tree
                // caches every branch it has expanded in its own State. Taking
                // it off the tree to show search would throw that away and
                // refetch the whole visible tree on the way back.
                Expanded(
                  child: IndexedStack(
                    index: _tab.index,
                    children: [
                      NoteTreeView(
                        client: client,
                        selectedNoteId: _selected?.noteId,
                        onSelect: (note) => setState(() => _selected = note),
                      ),
                      SearchPanel(
                        client: client,
                        focusNode: _searchFocus,
                        selectedNoteId: _selected?.noteId,
                        onSelect: (note) => setState(() => _selected = note),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _SidebarDivider(
            onDrag: (delta) => setState(() {
              _sidebarWidth = (_sidebarWidth + delta).clamp(
                _minSidebar,
                _maxSidebar,
              );
            }),
          ),
          Expanded(
            child: _selected == null
                ? const _EmptyReader()
                : NoteViewer(
                    // Keyed so switching notes rebuilds cleanly rather than
                    // briefly showing the previous note's body under the new
                    // title.
                    key: ValueKey(_selected!.noteId),
                    client: client,
                    note: _selected!,
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDisconnect(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect?'),
        content: const Text(
          'The saved token will be removed from this machine. '
          'You will need it again to reconnect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await widget.session.disconnect();
    }
  }
}

class _SidebarDivider extends StatelessWidget {
  const _SidebarDivider({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        // The visible line is 1px but the grab target is 8px, because a 1px
        // hit area is miserable to actually grab with a mouse.
        child: SizedBox(
          width: 8,
          child: Center(
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: Theme.of(context).dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyReader extends StatelessWidget {
  const _EmptyReader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.description_outlined,
            size: 44,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          Text(
            'Select a note to read it.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
