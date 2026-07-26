@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:triliage/src/etapi/etapi_client.dart';
import 'package:triliage/src/etapi/models/note.dart';

/// Opt-in integration test against a real Trilium instance.
///
/// Mocked responses only ever prove the client handles the shapes we imagined.
/// This proves it handles the shapes Trilium actually sends, which is where
/// field-name and date-format surprises live.
///
/// Skipped unless both environment variables are set, so CI and ordinary
/// `flutter test` runs are unaffected:
///
/// ```
/// TRILIAGE_LIVE_URL=https://notes.example.com \
/// TRILIAGE_LIVE_TOKEN=... \
/// flutter test test/live/live_etapi_test.dart
/// ```
///
/// The token is read from the environment on purpose. Do not paste one into
/// this file.
void main() {
  final url = Platform.environment['TRILIAGE_LIVE_URL'];
  final token = Platform.environment['TRILIAGE_LIVE_TOKEN'];

  if (url == null || token == null || url.isEmpty || token.isEmpty) {
    test('live ETAPI checks', () {}, skip: 'Set TRILIAGE_LIVE_URL and TRILIAGE_LIVE_TOKEN to run.');
    return;
  }

  late EtapiClient client;

  setUpAll(() {
    client = EtapiClient(baseUrl: normalizeBaseUrl(url), token: token);
  });

  tearDownAll(() => client.close());

  test('authenticates and reports a server version', () async {
    final info = await client.appInfo();

    expect(info.appVersion, isNotEmpty);
    expect(info.appVersion, isNot('unknown'),
        reason: 'appVersion missing means the payload shape changed');
    expect(info.dbVersion, greaterThan(0));
  });

  test('fetches the root note', () async {
    final root = await client.note(rootNoteId);

    expect(root.noteId, rootNoteId);
    expect(root.type, isNotEmpty);
  });

  test('lists real top-level notes', () async {
    final children = await client.children(rootNoteId);

    expect(children, isNotEmpty,
        reason: 'an instance with notes should have top-level children');
    for (final note in children) {
      expect(note.noteId, isNotEmpty);
      expect(note.title, isNotEmpty);
    }
  });

  test('parses real timestamps rather than dropping them', () async {
    // The whole reason parseTriliumDate exists. If Trilium's format changed,
    // dates would silently come back null everywhere instead of failing loudly,
    // so assert on real data.
    final children = await client.children(rootNoteId);
    final dated = children.where((n) => n.dateModified != null);

    expect(dated, isNotEmpty,
        reason: 'no real note parsed a dateModified, the format likely changed');
  });

  test('reads the content of a real text note', () async {
    final children = await client.children(rootNoteId);
    Note? target;
    for (final note in children) {
      if (note.isHtml && !note.isProtected) {
        target = note;
        break;
      }
    }
    if (target == null) {
      markTestSkipped('No unprotected text note at the top level.');
      return;
    }

    // Content may legitimately be empty; the assertion is that the call
    // succeeds and returns a string rather than throwing or returning JSON.
    expect(await client.noteContent(target.noteId), isA<String>());
  });

  test('search returns parseable notes', () async {
    final results = await client.search('note', limit: 5);

    for (final note in results) {
      expect(note.noteId, isNotEmpty);
    }
  });
}
