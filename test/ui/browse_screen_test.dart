import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:triliage/src/app_session.dart';
import 'package:triliage/src/storage/connection_profile.dart';
import 'package:triliage/src/storage/credential_store.dart';
import 'package:triliage/src/ui/browse_screen.dart';

Map<String, dynamic> _note(
  String id,
  String title, {
  List<String> children = const [],
}) {
  return {
    'noteId': id,
    'title': title,
    'type': 'text',
    'mime': 'text/html',
    'isProtected': false,
    'attributes': <dynamic>[],
    'parentNoteIds': <String>[],
    'childNoteIds': children,
  };
}

http.Response _json(Object body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

/// A session already connected to a fake instance holding one top-level note.
///
/// [rootFetches] counts how often the tree's root level was loaded, which is
/// how the sidebar's state-preservation claim is checked.
Future<AppSession> _connectedSession(List<String> requestLog) async {
  final session = AppSession(
    store: InMemoryCredentialStore(),
    httpClient: MockClient((request) async {
      final path = request.url.path;
      requestLog.add(path);
      return switch (path) {
        '/etapi/app-info' => _json({'appVersion': '0.63.3', 'dbVersion': 214}),
        '/etapi/notes/root' => _json(_note('root', 'root', children: ['n1'])),
        '/etapi/notes/n1' => _json(_note('n1', 'Homelab runbook')),
        _ => _json({'results': <dynamic>[]}),
      };
    }),
  );
  await session.connect(
    const ConnectionProfile(
      serverUrl: 'https://notes.example.com',
      token: 'tok',
    ),
  );
  return session;
}

Future<void> _pump(WidgetTester tester, AppSession session) async {
  await tester.pumpWidget(
    MaterialApp(home: BrowseScreen(session: session)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starts on the tree', (tester) async {
    final session = await _connectedSession([]);
    addTearDown(session.dispose);

    await _pump(tester, session);

    expect(find.text('Homelab runbook'), findsOneWidget);
    expect(find.textContaining('query syntax'), findsNothing);
  });

  testWidgets('the Search button swaps the sidebar over to search',
      (tester) async {
    final session = await _connectedSession([]);
    addTearDown(session.dispose);

    await _pump(tester, session);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.textContaining('query syntax'), findsOneWidget);
  });

  testWidgets('Ctrl+F reaches search from the tree', (tester) async {
    final session = await _connectedSession([]);
    addTearDown(session.dispose);

    await _pump(tester, session);
    expect(find.textContaining('query syntax'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.textContaining('query syntax'), findsOneWidget);
  });

  testWidgets('leaving the tree and coming back does not refetch it',
      (tester) async {
    final log = <String>[];
    final session = await _connectedSession(log);
    addTearDown(session.dispose);

    await _pump(tester, session);
    final fetchesAfterFirstPaint =
        log.where((path) => path == '/etapi/notes/root').length;

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tree'));
    await tester.pumpAndSettle();

    expect(
      log.where((path) => path == '/etapi/notes/root').length,
      fetchesAfterFirstPaint,
      reason: 'the tree is kept alive across tab switches, so returning to it '
          'must not re-hit the server',
    );
    expect(find.text('Homelab runbook'), findsOneWidget);
  });
}
