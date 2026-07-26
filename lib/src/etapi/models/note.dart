import '../trilium_date.dart';
import 'attribute.dart';

/// The id of the tree root, which every Trilium instance has and which is the
/// entry point for browsing.
const String rootNoteId = 'root';

/// A note as returned by `GET /etapi/notes/{noteId}`.
///
/// Note that ETAPI returns metadata only. Body text comes from a separate
/// `/content` call, which is why [Note] has no content field: a tree of a few
/// hundred notes should not drag every note body across the wire.
class Note {
  const Note({
    required this.noteId,
    required this.title,
    required this.type,
    required this.mime,
    required this.isProtected,
    required this.attributes,
    required this.parentNoteIds,
    required this.childNoteIds,
    this.blobId,
    this.dateCreated,
    this.dateModified,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      noteId: json['noteId'] as String? ?? '',
      // A note with an empty title is legal in Trilium but renders as a blank
      // row, so give it something selectable instead.
      title: switch (json['title']) {
        final String t when t.trim().isNotEmpty => t,
        _ => 'Untitled',
      },
      type: json['type'] as String? ?? 'text',
      mime: json['mime'] as String? ?? '',
      isProtected: json['isProtected'] as bool? ?? false,
      attributes: _attributesFrom(json['attributes']),
      parentNoteIds: _stringList(json['parentNoteIds']),
      childNoteIds: _stringList(json['childNoteIds']),
      blobId: json['blobId'] as String?,
      dateCreated: parseTriliumDate(json['dateCreated'] as String?),
      dateModified: parseTriliumDate(json['dateModified'] as String?),
    );
  }

  final String noteId;
  final String title;

  /// Trilium's note type: `text`, `code`, `book`, `image`, `canvas`, and so on.
  final String type;

  /// MIME type of the content, e.g. `text/html` for a normal note or
  /// `text/x-python` for a code note.
  final String mime;

  /// Protected notes are encrypted at rest and unreadable over ETAPI without a
  /// protected session, which ETAPI does not offer. We show them in the tree
  /// but cannot render their content.
  final bool isProtected;

  final List<Attribute> attributes;
  final List<String> parentNoteIds;
  final List<String> childNoteIds;
  final String? blobId;
  final DateTime? dateCreated;
  final DateTime? dateModified;

  bool get hasChildren => childNoteIds.isNotEmpty;

  /// True when the note body is HTML, which is what Trilium stores for ordinary
  /// text notes.
  bool get isHtml => mime == 'text/html' || (type == 'text' && mime.isEmpty);

  /// True when the body should be shown as monospaced source rather than
  /// rendered.
  bool get isCode => type == 'code';

  /// Whether this note can meaningfully be displayed by the reader at all.
  ///
  /// Images, canvases, and file attachments need renderers that do not exist
  /// yet, so the viewer shows an explanatory placeholder instead of a blank
  /// pane or a wall of binary.
  bool get isReadable => !isProtected && (isHtml || isCode || type == 'book');

  bool get isArchived =>
      attributes.any((a) => a.name == 'archived' && a.type == AttributeType.label);

  static List<Attribute> _attributesFrom(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Attribute.fromJson)
        .toList(growable: false);
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().toList(growable: false);
  }
}
