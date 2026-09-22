import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:triliage/src/etapi/etapi_client.dart';
import 'package:triliage/src/etapi/models/note.dart';
import 'package:triliage/src/ui/search_panel.dart';

Map<String, dynamic> _note(String id, String title, {String type = 'text'}) {
  return {
    'noteId': id,
    'title': title,
    'type': type,
    'mime': 'text/html',
    'isProtected': false,
    'attributes': <dynamic>[],
    'parentNoteIds': <String>['root'],
    'childNoteIds': <String>[],
  };
}

http.Response _results(List<Map<String, dynamic>> notes, {int status = 200}) {
  return http.Response(
    jsonEncode({'results': notes}),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

EtapiClient _client(MockClient mock) {
  return EtapiClient(
    baseUrl: Uri.parse('https://notes.example.com'),
    token: 'tok',
    httpClient: mock,
  );
}

Future<void> _pump(
  WidgetTester tester,
  EtapiClient client, {
  ValueChanged<Note>? onSelect,
  String? selectedNoteId,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 600,
          child: SearchPanel(
            client: client,
            selectedNoteId: selectedNoteId,
            onSelect: onSelect ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

Future<void> _submit(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the query syntax hint before anything is searched',
      (tester) async {
    await _pump(
      tester,
      _client(MockClient((_) async => throw StateError('should not run'))),
    );

    expect(find.textContaining('query syntax'), findsOneWidget);
    expect(find.text('#book'), findsOneWidget);
  });

  testWidgets('an empty query never reaches the server', (tester) async {
    var requests = 0;
    await _pump(
      tester,
      _client(MockClient((_) async {
        requests++;
        return _results([]);
      })),
    );

    await _submit(tester, '   ');

    expect(requests, 0,
        reason: 'an empty search means "match everything" to Trilium');
    expect(find.textContaining('query syntax'), findsOneWidget);
  });

  testWidgets('lists matches and passes the query through to ETAPI',
      (tester) async {
    Uri? captured;
    await _pump(
      tester,
      _client(MockClient((request) async {
        captured = request.url;
        return _results([
          _note('a1', 'Homelab runbook'),
          _note('a2', 'Homelab DNS', type: 'code'),
        ]);
      })),
    );

    await _submit(tester, '#homelab');

    expect(captured!.path, '/etapi/notes');
    expect(captured!.queryParameters['search'], '#homelab');
    expect(captured!.queryParameters['fastSearch'], 'false');
    expect(captured!.queryParameters['includeArchivedNotes'], 'false');
    expect(captured!.queryParameters['limit'], '$searchResultLimit');

    expect(find.text('Homelab runbook'), findsOneWidget);
    expect(find.text('Homelab DNS'), findsOneWidget);
    expect(find.text('2 matches'), findsOneWidget);
  });

  testWidgets('tapping a result hands the note to the reader', (tester) async {
    Note? picked;
    await _pump(
      tester,
      _client(MockClient((_) async => _results([_note('a1', 'Pick me')]))),
      onSelect: (note) => picked = note,
    );

    await _submit(tester, 'pick');
    await tester.tap(find.text('Pick me'));
    await tester.pump();

    expect(picked?.noteId, 'a1');
  });

  testWidgets('says so plainly when nothing matches', (tester) async {
    await _pump(
      tester,
      _client(MockClient((_) async => _results([]))),
    );

    await _submit(tester, 'nothing-matches-this');

    expect(find.textContaining('No notes match'), findsOneWidget);
  });

  testWidgets('surfaces Trilium\'s own message for a bad query',
      (tester) async {
    await _pump(
      tester,
      _client(MockClient(
        (_) async => http.Response(
          jsonEncode({
            'status': 400,
            'code': 'INVALID_SEARCH',
            'message': 'Unrecognised expression',
          }),
          400,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      )),
    );

    await _submit(tester, '#bad =');

    expect(find.text('Unrecognised expression'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('the titles-only toggle re-runs the search as a fast search',
      (tester) async {
    final searches = <String>[];
    await _pump(
      tester,
      _client(MockClient((request) async {
        searches.add(request.url.queryParameters['fastSearch']!);
        return _results([_note('a1', 'Found')]);
      })),
    );

    await _submit(tester, 'homelab');
    expect(searches, ['false']);

    await tester.tap(find.text('Titles only'));
    await tester.pumpAndSettle();

    expect(searches, ['false', 'true'],
        reason: 'a toggle that waits for another Enter reads as broken');
  });

  testWidgets('the archived toggle re-runs the search including archived '
      'notes', (tester) async {
    final flags = <String>[];
    await _pump(
      tester,
      _client(MockClient((request) async {
        flags.add(request.url.queryParameters['includeArchivedNotes']!);
        return _results([_note('a1', 'Found')]);
      })),
    );

    await _submit(tester, 'homelab');
    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();

    expect(flags, ['false', 'true']);
  });

  testWidgets('toggling before any search has run stays quiet', (tester) async {
    var requests = 0;
    await _pump(
      tester,
      _client(MockClient((_) async {
        requests++;
        return _results([]);
      })),
    );

    await tester.tap(find.text('Titles only'));
    await tester.pumpAndSettle();

    expect(requests, 0,
        reason: 'there is no query yet, so there is nothing to re-run');
  });

  testWidgets('a slow earlier search cannot overwrite a later one',
      (tester) async {
    final pending = <String, Completer<http.Response>>{};
    await _pump(
      tester,
      _client(MockClient((request) {
        final query = request.url.queryParameters['search']!;
        return pending.putIfAbsent(query, Completer<http.Response>.new).future;
      })),
    );

    await tester.enterText(find.byType(TextField), 'slow');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'fast');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    // The newer search lands first, then the older one finally arrives.
    pending['fast']!.complete(_results([_note('f1', 'Fast result')]));
    await tester.pumpAndSettle();
    pending['slow']!.complete(_results([_note('s1', 'Stale result')]));
    await tester.pumpAndSettle();

    expect(find.text('Fast result'), findsOneWidget);
    expect(find.text('Stale result'), findsNothing,
        reason: 'a late response from a superseded query must be ignored');
  });

  testWidgets('admits when results were capped rather than claiming a total',
      (tester) async {
    await _pump(
      tester,
      _client(MockClient(
        (_) async => _results([
          for (var i = 0; i < searchResultLimit; i++)
            _note('n$i', 'Note number $i'),
        ]),
      )),
    );

    await _submit(tester, 'note');

    expect(
      find.textContaining('First $searchResultLimit matches'),
      findsOneWidget,
    );
  });

  testWidgets('clearing the box returns to the hint without searching again',
      (tester) async {
    var requests = 0;
    await _pump(
      tester,
      _client(MockClient((_) async {
        requests++;
        return _results([_note('a1', 'Homelab runbook')]);
      })),
    );

    await _submit(tester, 'homelab');
    expect(find.text('Homelab runbook'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Homelab runbook'), findsNothing);
    expect(find.textContaining('query syntax'), findsOneWidget);
    expect(requests, 1);
  });
}
