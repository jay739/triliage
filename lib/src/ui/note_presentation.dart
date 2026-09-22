/// How a note is presented wherever it is listed or headed.
///
/// Shared rather than duplicated per screen, so the same note cannot show one
/// icon in the tree and a different one in search results.
library;

import 'package:flutter/material.dart';

import '../etapi/models/note.dart';

/// The icon for a note, chosen from its Trilium type.
IconData noteTypeIcon(Note note) {
  if (note.isProtected) return Icons.lock_outline;
  return switch (note.type) {
    'code' => Icons.code,
    'image' => Icons.image_outlined,
    'file' => Icons.attach_file,
    'book' => Icons.menu_book_outlined,
    'search' => Icons.saved_search,
    'canvas' => Icons.brush_outlined,
    'mermaid' => Icons.account_tree_outlined,
    'render' || 'webView' => Icons.web_outlined,
    _ => Icons.description_outlined,
  };
}

/// Deliberately plain and locale-independent. Pulling in `intl` for one
/// timestamp is not worth the dependency yet.
String formatNoteDate(DateTime date) {
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
