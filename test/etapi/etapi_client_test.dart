import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:triliage/src/etapi/etapi_client.dart';
import 'package:triliage/src/etapi/etapi_exception.dart';

/// JSON responses must declare utf-8, otherwise package:http decodes the body
/// as latin-1 and any non-ASCII assertion fails for the wrong reason.
http.Response _json(Object body, {int status = 200}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  group('normalizeBaseUrl', () {
    test('defaults a bare host to https', () {
      expect(normalizeBaseUrl('notes.example.com').toString(),
          'https://notes.example.com');
    });

    test('strips a trailing slash', () {
      expect(normalizeBaseUrl('https://notes.example.com/').toString(),
          'https://notes.example.com');
    });

    test('strips a trailing /etapi the user pasted from the docs', () {
      expect(normalizeBaseUrl('https://notes.example.com/etapi').toString(),
          'https://notes.example.com');
    });

    test('keeps a sub-path where Trilium is reverse-proxied', () {
      expect(normalizeBaseUrl('https://example.com/trilium').toString(),
          'https://example.com/trilium');
    });

    test('preserves an explicit port and http scheme', () {
      expect(normalizeBaseUrl('http://10.0.0.101:8080').toString(),
          'http://10.0.0.101:8080');
    });

    test('drops a query string and fragment', () {
      expect(normalizeBaseUrl('https://notes.example.com/?a=1#x').toString(),
          'https://notes.example.com');
    });

    test('rejects empty and non-http schemes', () {
      expect(() => normalizeBaseUrl(''), throwsA(isA<EtapiFormatException>()));
      expect(() => normalizeBaseUrl('   '),
          throwsA(isA<EtapiFormatException>()));
      expect(() => normalizeBaseUrl('ftp://notes.example.com'),
          throwsA(isA<EtapiFormatException>()));
    });
  });

  group('EtapiClient request shape', () {
    test('sends the bare token as Authorization, with no Bearer prefix', () async {
      late http.Request captured;
      final client = EtapiClient(
        baseUrl: Uri.parse('https://notes.example.com'),
        token: 'tok_abc',
        httpClient: MockClient((request) async {
          captured = request;
          return _json({'appVersion': '0.63.3', 'dbVersion': 214});
        }),
      );

      await client.appInfo();

      // Trilium authenticates on the raw value. Prefixing "Bearer " is the
      // single most likely way to get a mysterious 401 here.
      expect(captured.headers['Authorization'], 'tok_abc');
      expect(captured.url.path, '/etapi/app-info');
    });

    test('resolves paths under a proxied sub-path base URL', () async {
      late Uri captured;
      final client = EtapiClient(
        baseUrl: normalizeBaseUrl('https://example.com/trilium'),
        token: 't',
        httpClient: MockClient((request) async {
          captured = request.url;
          return _json({'noteId': 'root', 'title': 'root'});
        }),
      );

      await client.note('root');

      expect(captured.path, '/trilium/etapi/notes/root');
    });

    test('percent-encodes note ids', () async {
      late Uri captured;
      final client = EtapiClient(
        baseUrl: Uri.parse('https://notes.example.com'),
        token: 't',
        httpClient: MockClient((request) async {
          captured = request.url;
          return _json({'noteId': 'a b/c'});
        }),
      );

      await client.note('a b/c');

      expect(captured.path, '/etapi/notes/a%20b%2Fc');
    });
  });

  group('EtapiClient.appInfo', () {
    test('parses a version payload', () async {
      final client = EtapiClient(
        baseUrl: Uri.parse('https://notes.example.com'),
        token: 't',
        httpClient: MockClient(
          (_) async => _json({'appVersion': '0.63.3', 'dbVersion': 214}),
        ),
      );

      final info = await client.appInfo();

      expect(info.appVersion, '0.63.3');
      expect(info.dbVersion, 214);
    });

    test('maps a 401 to an auth failure carrying Trilium\'s own code', () async {
      final client = EtapiClient(
        baseUrl: Uri.parse('https://notes.example.com'),
        token: 'bad',
        httpClient: MockClient(
          (_) async => _json(
            {
              'status': 401,
              'code': 'NOT_AUTHENTICATED',
              'message': 'Not authenticated',
            },
            status: 401,
          ),
        ),
      );

      await expectLater(
        client.appInfo(),
        throwsA(
          isA<EtapiHttpException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.code, 'code', 'NOT_AUTHENTICATED')
              .having((e) => e.isAuthFailure, 'isAuthFailure', isTrue),
        ),
      );
    });

    test('explains a non-Trilium URL that answers with HTML', () async {
      // A wrong URL usually hits a real web server, so the failure is a valid
      // 200 full of HTML rather than an HTTP error.
      final client = EtapiClient(
        baseUrl: Uri.parse('https://example.com'),
        token: 't',
        httpClient: MockClient(
          (_) async => http.Response(
            '<!doctype html><title>Hello</title>',
            200,
            headers: {'content-type': 'text/html'},
          ),
        ),
      );

      await expectLater(
        client.appInfo(),
        throwsA(
          isA<EtapiFormatException>().having(
            (e) => e.message,
            'message',
            contains('Trilium'),
          ),
        ),
      );
    });

    test('turns a non-JSON 404 body into an actionable message', () async {
      final client = EtapiClient(
        baseUrl: Uri.parse('https://example.com'),
        token: 't',
        httpClient: MockClient(
          (_) async => http.Response('<html>404</html>', 404),
        ),
      );

      await expectLater(
        client.appInfo(),
        throwsA(
          isA<EtapiHttpException>().having(
            (e) => e.message,
            'message',
            contains('Trilium instance'),
          ),
        ),
      );
    });

    test('reports an unreachable server as a network failure', () async {
      final client = EtapiClient(
        baseUrl: Uri.parse('https://notes.example.com'),
        token: 't',
        httpClient: MockClient(
          (_) async => throw http.ClientException('Connection refused'),
        ),
      );

      await expectLater(
        client.appInfo(),
        throwsA(isA<EtapiNetworkException>()),
      );
    });
  });

  group('EtapiClient.noteContent', () {
    test('decodes the body as UTF-8 regardless of declared charset', () async {
      // Trilium does not always send a charset, and http would otherwise fall
      // back to latin-1 and mangle every non-ASCII character.
      final client = EtapiClient(
        baseUrl: Uri.parse('https://notes.example.com'),
        token: 't',
        httpClient: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode('<p>café — naïve</p>'),
            200,
            headers: {'content-type': 'text/html'},
          ),
        ),
      );

      expect(await client.noteContent('n1'), '<p>café — naïve</p>');
    });

    test('propagates a not-found error', () async {
      final client = EtapiClient(
        baseUrl: Uri.parse('https://notes.example.com'),
        token: 't',
        httpClient: MockClient(
          (_) async => _json(
            {'status': 404, 'code': 'NOTE_NOT_FOUND', 'message': 'No such note'},
            status: 404,
          ),
        ),
      );

      await expectLater(
        client.noteContent('missing'),
        throwsA(
          isA<EtapiHttpException>()
              .having((e) => e.code, 'code', 'NOTE_NOT_FOUND')
              .having((e) => e.isAuthFailure, 'isAuthFailure', isFalse),
        ),
      );
    });
  });

  group('EtapiClient.children', () {
    test('fetches each child of the parent, in order', () async {
      final client = EtapiClient(
        baseUrl: Uri.parse('https://notes.example.com'),
        token: 't',
        httpClient: MockClient((request) async {
          final id = request.url.pathSegments.last;
          if (id == 'root') {
            return _json({
              'noteId': 'root',
              'title': 'root',
              'childNoteIds': ['c1', 'c2'],
            });
          }
          return _json({'noteId': id, 'title': 'Child $id'});
        }),
      );

      final children = await client.children('root');

      expect(children.map((n) => n.noteId), ['c1', 'c2']);
      expect(children.first.title, 'Child c1');
    });

    test('returns an empty list without extra requests when there are none',
        () async {
      var requests = 0;
      final client = EtapiClient(
        baseUrl: Uri.parse('https://notes.example.com'),
        token: 't',
        httpClient: MockClient((_) async {
          requests++;
          return _json({'noteId': 'leaf', 'title': 'Leaf'});
        }),
      );

      expect(await client.children('leaf'), isEmpty);
      expect(requests, 1);
    });

    test('drops a child that fails to load instead of failing the level',
        () async {
      // One unreadable note must not blank out its siblings in the tree.
      final client = EtapiClient(
        baseUrl: Uri.parse('https://notes.example.com'),
        token: 't',
        httpClient: MockClient((request) async {
          final id = request.url.pathSegments.last;
          if (id == 'root') {
            return _json({
              'noteId': 'root',
              'childNoteIds': ['good', 'broken'],
            });
          }
          if (id == 'broken') {
            return _json(
              {'status': 500, 'code': 'BOOM', 'message': 'kaboom'},
              status: 500,
            );
          }
          return _json({'noteId': 'good', 'title': 'Good'});
        }),
      );

      final children = await client.children('root');

      expect(children.map((n) => n.noteId), ['good']);
    });

    test('propagates failure to load the parent itself', () async {
      final client = EtapiClient(
        baseUrl: Uri.parse('https://notes.example.com'),
        token: 't',
        httpClient: MockClient(
          (_) async => _json(
            {'status': 401, 'code': 'NOT_AUTHENTICATED', 'message': 'nope'},
            status: 401,
          ),
        ),
      );

      await expectLater(
        client.children('root'),
        throwsA(isA<EtapiHttpException>()),
      );
    });
  });

  group('EtapiClient.search', () {
    test('sends the query and flags, and parses results', () async {
      late Uri captured;
      final client = EtapiClient(
        baseUrl: Uri.parse('https://notes.example.com'),
        token: 't',
        httpClient: MockClient((request) async {
          captured = request.url;
          return _json({
            'results': [
              {'noteId': 'n1', 'title': 'Hit one'},
              {'noteId': 'n2', 'title': 'Hit two'},
            ],
          });
        }),
      );

      final results = await client.search('#homelab', limit: 25);

      expect(captured.queryParameters['search'], '#homelab');
      expect(captured.queryParameters['limit'], '25');
      expect(captured.queryParameters['includeArchivedNotes'], 'false');
      expect(results.map((n) => n.title), ['Hit one', 'Hit two']);
    });

    test('returns empty when the server omits results', () async {
      final client = EtapiClient(
        baseUrl: Uri.parse('https://notes.example.com'),
        token: 't',
        httpClient: MockClient((_) async => _json({'debugInfo': {}})),
      );

      expect(await client.search('nothing'), isEmpty);
    });
  });

  group('EtapiClient.login', () {
    test('exchanges a password for a token', () async {
      late http.Request captured;
      final token = await EtapiClient.login(
        baseUrl: Uri.parse('https://notes.example.com'),
        password: 'hunter2',
        httpClient: MockClient((request) async {
          captured = request;
          return _json({'authToken': 'tok_from_login'});
        }),
      );

      expect(token, 'tok_from_login');
      expect(captured.url.path, '/etapi/auth/login');
      expect(jsonDecode(captured.body), {'password': 'hunter2'});
    });

    test('surfaces a rejected password as an auth failure', () async {
      await expectLater(
        EtapiClient.login(
          baseUrl: Uri.parse('https://notes.example.com'),
          password: 'wrong',
          httpClient: MockClient(
            (_) async => _json(
              {
                'status': 401,
                'code': 'NOT_AUTHENTICATED',
                'message': 'Incorrect password',
              },
              status: 401,
            ),
          ),
        ),
        throwsA(
          isA<EtapiHttpException>()
              .having((e) => e.isAuthFailure, 'isAuthFailure', isTrue),
        ),
      );
    });

    test('fails clearly when a 200 carries no token', () async {
      await expectLater(
        EtapiClient.login(
          baseUrl: Uri.parse('https://notes.example.com'),
          password: 'x',
          httpClient: MockClient((_) async => _json({'unexpected': true})),
        ),
        throwsA(isA<EtapiFormatException>()),
      );
    });
  });
}
