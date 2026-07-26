import '../trilium_date.dart';

/// A label or relation attached to a note.
///
/// Trilium uses attributes for almost all metadata: `#book`, `#archived`,
/// `~author=<noteId>`, and so on. Labels carry a plain string value, relations
/// carry a target note id in [value].
class Attribute {
  const Attribute({
    required this.attributeId,
    required this.noteId,
    required this.type,
    required this.name,
    required this.value,
    required this.position,
    required this.isInheritable,
    this.utcDateModified,
  });

  factory Attribute.fromJson(Map<String, dynamic> json) {
    return Attribute(
      attributeId: json['attributeId'] as String? ?? '',
      noteId: json['noteId'] as String? ?? '',
      type: AttributeType.parse(json['type'] as String?),
      name: json['name'] as String? ?? '',
      value: json['value'] as String? ?? '',
      position: (json['position'] as num?)?.toInt() ?? 0,
      isInheritable: json['isInheritable'] as bool? ?? false,
      utcDateModified: parseTriliumDate(json['utcDateModified'] as String?),
    );
  }

  final String attributeId;
  final String noteId;
  final AttributeType type;
  final String name;
  final String value;
  final int position;
  final bool isInheritable;
  final DateTime? utcDateModified;

  /// How Trilium itself writes this attribute: `#name=value` or `~name=value`.
  String get displayForm {
    final prefix = type == AttributeType.relation ? '~' : '#';
    return value.isEmpty ? '$prefix$name' : '$prefix$name=$value';
  }
}

enum AttributeType {
  label,
  relation;

  /// Unknown types degrade to [label] rather than throwing, so a future Trilium
  /// version adding a third kind cannot break note loading.
  static AttributeType parse(String? raw) {
    return raw == 'relation' ? AttributeType.relation : AttributeType.label;
  }
}
