import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:triliage/src/app_session.dart';
import 'package:triliage/src/storage/connection_profile.dart';
import 'package:triliage/src/storage/credential_store.dart';
import 'package:triliage/src/ui/connect_screen.dart';

http.Response _json(Object body, {int status = 200}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Future<void> _pump(WidgetTester tester, AppSession session) {
  return tester.pumpWidget(
    MaterialApp(home: ConnectScreen(session: session)),
  );
}

Future<void> _fillForm(
  WidgetTester tester, {
  String server = 'https://notes.example.com',
  String secret = 'tok',
}) async {
  await tester.enterText(find.byType(TextFormField).first, server);
  await tester.enterText(find.byType(TextFormField).last, secret);
}

void main() {
  testWidgets('refuses to submit an empty form', (tester) async {
    var requests = 0;
    final session = AppSession(
      store: InMemoryCredentialStore(),
      httpClient: MockClient((_) async {
        requests++;
        return _json({'appVersion': '1', 'dbVersion': 1});
      }),
    );

    await _pump(tester, session);
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsNWidgets(2));
    expect(requests, 0, reason: 'validation must run before any network call');
  });

  testWidgets('rejects a malformed server URL before calling out',
      (tester) async {
    final session = AppSession(
      store: InMemoryCredentialStore(),
      httpClient: MockClient((_) async => throw StateError('should not run')),
    );

    await _pump(tester, session);
    await _fillForm(tester, server: 'ftp://notes.example.com');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Unsupported scheme'), findsOneWidget);
  });

  testWidgets('connects with a token and flips the session', (tester) async {
    final store = InMemoryCredentialStore();
    final session = AppSession(
      store: store,
      httpClient: MockClient(
        (_) async => _json({'appVersion': '0.63.3', 'dbVersion': 214}),
      ),
    );

    await _pump(tester, session);
    await _fillForm(tester);
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(session.status, SessionStatus.connected);
    expect((await store.read())?.token, 'tok');
  });

  testWidgets('explains a rejected token instead of echoing a raw error',
      (tester) async {
    final session = AppSession(
      store: InMemoryCredentialStore(),
      httpClient: MockClient(
        (_) async => _json(
          {'status': 401, 'code': 'NOT_AUTHENTICATED', 'message': 'nope'},
          status: 401,
        ),
      ),
    );

    await _pump(tester, session);
    await _fillForm(tester, secret: 'bad-token');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.textContaining('rejected that token'), findsOneWidget);
    expect(session.status, isNot(SessionStatus.connected));
  });

  testWidgets('password mode exchanges the password for a token and stores '
      'only the token', (tester) async {
    final store = InMemoryCredentialStore();
    final paths = <String>[];
    final session = AppSession(
      store: store,
      httpClient: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/auth/login')) {
          return _json({'authToken': 'tok_from_login'});
        }
        return _json({'appVersion': '0.63.3', 'dbVersion': 214});
      }),
    );

    await _pump(tester, session);
    await tester.tap(find.text('Password'));
    await tester.pumpAndSettle();
    await _fillForm(tester, secret: 'hunter2');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(paths, ['/etapi/auth/login', '/etapi/app-info']);
    final saved = await store.read();
    expect(saved?.token, 'tok_from_login');
    expect(saved?.token, isNot(contains('hunter2')),
        reason: 'the password itself is never persisted');
  });

  testWidgets('surfaces why a restored session was dropped', (tester) async {
    // Drive a real failed restore so the screen picks up the message exactly
    // the way it does at launch, rather than being handed one directly.
    final session = AppSession(
      store: InMemoryCredentialStore(
        const ConnectionProfile(
          serverUrl: 'https://notes.example.com',
          token: 'revoked',
        ),
      ),
      httpClient: MockClient(
        (_) async => _json(
          {'status': 401, 'code': 'NOT_AUTHENTICATED', 'message': 'nope'},
          status: 401,
        ),
      ),
    );
    await session.restore();

    await _pump(tester, session);
    await tester.pump();

    expect(find.textContaining('rejected'), findsOneWidget);
  });
}
