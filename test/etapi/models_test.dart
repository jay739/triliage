import 'package:flutter_test/flutter_test.dart';
import 'package:triliage/src/etapi/models/attribute.dart';
import 'package:triliage/src/etapi/models/note.dart';

void main() {
  group('Note.fromJson', () {
    test('reads a full note payload', () {
      final note = Note.fromJson({
        'noteId': 'abc123',
        'title': 'Homelab runbook',
        'type': 'text',
        'mime': 'text/html',
        'isProtected': false,
        'blobId': 'blob1',
        'parentNoteIds': ['root'],
        'childNoteIds': ['c1', 'c2'],
        'dateCreated': '2021-12-31 20:18:11.939+0100',
        'dateModified': '2022-01-05 08:00:00.000+0100',
        'attributes': [
          {
            'attributeId': 'a1',
            'noteId': 'abc123',
            'type': 'label',
            'name': 'archived',
            'value': '',
            'position': 10,
            'isInheritable': false,
          },
        ],
      });

      expect(note.noteId, 'abc123');
      expect(note.title, 'Homelab runbook');
      expect(note.childNoteIds, ['c1', 'c2']);
      expect(note.hasChildren, isTrue);
      expect(note.isHtml, isTrue);
      expect(note.isReadable, isTrue);
      expect(note.isArchived, isTrue);
      expect(note.dateCreated, isNotNull);
      expect(note.attributes.single.displayForm, '#archived');
    });

    test('survives a minimal payload without throwing', () {
      // Trilium omits fields rather than sending nulls in some versions, and a
      // missing field must never take down the whole tree.
      final note = Note.fromJson({'noteId': 'x'});

      expect(note.noteId, 'x');
      expect(note.title, 'Untitled');
      expect(note.type, 'text');
      expect(note.attributes, isEmpty);
      expect(note.childNoteIds, isEmpty);
      expect(note.hasChildren, isFalse);
      expect(note.dateCreated, isNull);
    });

    test('substitutes a placeholder for a blank title', () {
      expect(Note.fromJson({'noteId': 'x', 'title': '   '}).title, 'Untitled');
    });

    test('ignores malformed entries inside list fields', () {
      final note = Note.fromJson({
        'noteId': 'x',
        'childNoteIds': ['ok', 42, null],
        'attributes': ['not a map'],
      });

      expect(note.childNoteIds, ['ok']);
      expect(note.attributes, isEmpty);
    });

    test('treats an untyped text note as HTML', () {
      final note = Note.fromJson({'noteId': 'x', 'type': 'text', 'mime': ''});

      expect(note.isHtml, isTrue);
    });

    test('marks protected notes unreadable regardless of type', () {
      final note = Note.fromJson({
        'noteId': 'x',
        'type': 'text',
        'mime': 'text/html',
        'isProtected': true,
      });

      expect(note.isReadable, isFalse);
    });

    test('marks image notes unreadable until a renderer exists', () {
      final note = Note.fromJson({
        'noteId': 'x',
        'type': 'image',
        'mime': 'image/png',
      });

      expect(note.isReadable, isFalse);
      expect(note.isCode, isFalse);
    });
  });

  group('Attribute', () {
    test('formats labels and relations the way Trilium writes them', () {
      final label = Attribute.fromJson({
        'attributeId': 'a',
        'type': 'label',
        'name': 'book',
        'value': '',
      });
      final valuedLabel = Attribute.fromJson({
        'attributeId': 'b',
        'type': 'label',
        'name': 'priority',
        'value': 'high',
      });
      final relation = Attribute.fromJson({
        'attributeId': 'c',
        'type': 'relation',
        'name': 'author',
        'value': 'note123',
      });

      expect(label.displayForm, '#book');
      expect(valuedLabel.displayForm, '#priority=high');
      expect(relation.displayForm, '~author=note123');
    });

    test('falls back to label for an unrecognised type', () {
      expect(AttributeType.parse('somethingNew'), AttributeType.label);
      expect(AttributeType.parse(null), AttributeType.label);
      expect(AttributeType.parse('relation'), AttributeType.relation);
    });
  });
}
