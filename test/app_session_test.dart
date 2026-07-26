import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:triliage/src/app_session.dart';
import 'package:triliage/src/etapi/etapi_exception.dart';
import 'package:triliage/src/storage/connection_profile.dart';
import 'package:triliage/src/storage/credential_store.dart';

http.Response _json(Object body, {int status = 200}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

MockClient _serverOk() => MockClient(
      (_) async => _json({'appVersion': '0.63.3', 'dbVersion': 214}),
    );

const _profile = ConnectionProfile(
  serverUrl: 'https://notes.example.com',
  token: 'tok',
);

void main() {
  group('restore', () {
    test('lands disconnected when nothing was saved', () async {
      final session = AppSession(
        store: InMemoryCredentialStore(),
        httpClient: _serverOk(),
      );

      await session.restore();

      expect(session.status, SessionStatus.disconnected);
      expect(session.restoreError, isNull);
      expect(session.client, isNull);
    });

    test('connects when the saved token still works', () async {
      final session = AppSession(
        store: InMemoryCredentialStore(_profile),
        httpClient: _serverOk(),
      );

      await session.restore();

      expect(session.status, SessionStatus.connected);
      expect(session.client, isNotNull);
      expect(session.appInfo?.appVersion, '0.63.3');
      expect(session.profile?.token, 'tok');
    });

    test('discards a token the server rejects, and says why', () async {
      final store = InMemoryCredentialStore(_profile);
      final session = AppSession(
        store: store,
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

      await session.restore();

      expect(session.status, SessionStatus.disconnected);
      expect(session.restoreError, contains('rejected'));
      expect(await store.read(), isNull, reason: 'a rejected token is useless');
    });

    test('keeps the saved token when the server is merely unreachable', () async {
      // Offline laptop or a rebooting homelab must not cost the user their
      // credentials. This is the distinction the restore path exists to make.
      final store = InMemoryCredentialStore(_profile);
      final session = AppSession(
        store: store,
        httpClient: MockClient(
          (_) async => throw http.ClientException('Connection refused'),
        ),
      );

      await session.restore();

      expect(session.status, SessionStatus.disconnected);
      expect(session.restoreError, contains('Could not reach'));
      expect(await store.read(), isNotNull, reason: 'the token may still be good');
    });

    test('keeps the saved token on a server-side 500', () async {
      final store = InMemoryCredentialStore(_profile);
      final session = AppSession(
        store: store,
        httpClient: MockClient(
          (_) async => _json(
            {'status': 500, 'code': 'BOOM', 'message': 'kaboom'},
            status: 500,
          ),
        ),
      );

      await session.restore();

      expect(session.status, SessionStatus.disconnected);
      expect(await store.read(), isNotNull);
    });
  });

  group('connect', () {
    test('verifies against the server before saving anything', () async {
      final store = InMemoryCredentialStore();
      final session = AppSession(
        store: store,
        httpClient: MockClient(
          (_) async => _json(
            {'status': 401, 'code': 'NOT_AUTHENTICATED', 'message': 'no'},
            status: 401,
          ),
        ),
      );

      await expectLater(
        session.connect(_profile),
        throwsA(isA<EtapiHttpException>()),
      );
      expect(await store.read(), isNull, reason: 'never save an unverified token');
      expect(session.status, SessionStatus.restoring, reason: 'state unchanged');
    });

    test('saves and adopts a working profile, notifying listeners', () async {
      final store = InMemoryCredentialStore();
      final session = AppSession(store: store, httpClient: _serverOk());
      var notifications = 0;
      session.addListener(() => notifications++);

      await session.connect(_profile);

      expect(session.status, SessionStatus.connected);
      expect((await store.read())?.token, 'tok');
      expect(notifications, 1);
    });
  });

  test('disconnect clears storage and drops the client', () async {
    final store = InMemoryCredentialStore();
    final session = AppSession(store: store, httpClient: _serverOk());
    await session.connect(_profile);

    await session.disconnect();

    expect(session.status, SessionStatus.disconnected);
    expect(session.client, isNull);
    expect(session.profile, isNull);
    expect(await store.read(), isNull);
  });

  test('reconnecting does not strand the previous client', () async {
    final session = AppSession(
      store: InMemoryCredentialStore(),
      httpClient: _serverOk(),
    );

    await session.connect(_profile);
    final first = session.client;
    await session.connect(_profile.copyWith(token: 'tok2'));

    expect(session.client, isNot(same(first)));
    expect(session.profile?.token, 'tok2');
  });

  group('ConnectionProfile', () {
    test('derives a display name from the host', () {
      expect(_profile.displayName, 'notes.example.com');
    });

    test('falls back to the raw string when the URL is unusable', () {
      const broken = ConnectionProfile(serverUrl: '', token: 't');
      expect(broken.displayName, '');
    });
  });
}
