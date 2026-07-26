import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'etapi/etapi_client.dart';
import 'etapi/etapi_exception.dart';
import 'etapi/models/app_info.dart';
import 'storage/connection_profile.dart';
import 'storage/credential_store.dart';

enum SessionStatus {
  /// Reading saved credentials on launch. Shown as a splash, not a UI state
  /// the user can act on.
  restoring,

  /// No usable connection: either nothing was saved, or what was saved no
  /// longer works.
  disconnected,

  connected,
}

/// Owns the connection lifecycle: restore on launch, connect, disconnect.
///
/// The rest of the app reads [client] and never builds one itself, so there is
/// exactly one place where a token turns into an authenticated client.
class AppSession extends ChangeNotifier {
  AppSession({required CredentialStore store, http.Client? httpClient})
      : _store = store,
        _httpClient = httpClient;

  final CredentialStore _store;
  final http.Client? _httpClient;

  SessionStatus _status = SessionStatus.restoring;
  ConnectionProfile? _profile;
  EtapiClient? _client;
  AppInfo? _appInfo;
  String? _restoreError;

  SessionStatus get status => _status;
  ConnectionProfile? get profile => _profile;
  EtapiClient? get client => _client;
  AppInfo? get appInfo => _appInfo;

  /// Why a previously saved connection stopped working, if it did.
  ///
  /// Surfaced on the connect screen so a revoked token explains itself instead
  /// of silently dumping the user back at an empty form.
  String? get restoreError => _restoreError;

  /// Loads any saved profile and verifies it still works.
  ///
  /// A saved token that no longer authenticates is discarded here rather than
  /// left to fail on the first note fetch, which would be a much more confusing
  /// place to discover it.
  Future<void> restore() async {
    final saved = await _store.read();
    if (saved == null) {
      _setDisconnected();
      return;
    }

    try {
      final client = _buildClient(saved);
      final info = await client.appInfo();
      _adopt(saved, client, info);
    } on EtapiException catch (e) {
      // Only a definite rejection invalidates the token. A server that is
      // merely unreachable right now (laptop offline, homelab rebooting) must
      // not cost the user their saved credentials.
      final isRejected = e is EtapiHttpException && e.isAuthFailure;
      if (isRejected) {
        await _store.clear();
        _setDisconnected('Saved token was rejected. Reconnect to continue.');
      } else {
        _setDisconnected('Could not reach the server: ${e.message}');
      }
    }
  }

  /// Verifies [profile] against the server and, if it works, saves and adopts
  /// it. Throws [EtapiException] on failure so the form can show why.
  Future<void> connect(ConnectionProfile profile) async {
    final client = _buildClient(profile);
    try {
      final info = await client.appInfo();
      await _store.save(profile);
      _adopt(profile, client, info);
    } on EtapiException {
      client.close();
      rethrow;
    }
  }

  /// Exchanges a Trilium password for a token, then connects with it.
  ///
  /// Lives here rather than in the UI so every outbound request in the app
  /// goes through the session's own HTTP client. Doing the exchange from the
  /// widget bypassed that client entirely, which made the flow untestable and
  /// meant password login used a different transport from everything else.
  Future<void> connectWithPassword({
    required String serverUrl,
    required String password,
  }) async {
    final token = await EtapiClient.login(
      baseUrl: normalizeBaseUrl(serverUrl),
      password: password,
      httpClient: _httpClient,
    );
    await connect(ConnectionProfile(serverUrl: serverUrl, token: token));
  }

  Future<void> disconnect() async {
    await _store.clear();
    _setDisconnected();
  }

  EtapiClient _buildClient(ConnectionProfile profile) {
    return EtapiClient(
      baseUrl: profile.baseUri,
      token: profile.token,
      httpClient: _httpClient,
    );
  }

  void _adopt(ConnectionProfile profile, EtapiClient client, AppInfo info) {
    // Never leak the client being replaced; disconnect-then-reconnect would
    // otherwise strand a live HTTP client per attempt.
    _closeClient();
    _profile = profile;
    _client = client;
    _appInfo = info;
    _restoreError = null;
    _status = SessionStatus.connected;
    notifyListeners();
  }

  void _setDisconnected([String? error]) {
    _closeClient();
    _profile = null;
    _appInfo = null;
    _restoreError = error;
    _status = SessionStatus.disconnected;
    notifyListeners();
  }

  void _closeClient() {
    _client?.close();
    _client = null;
  }

  @override
  void dispose() {
    _closeClient();
    super.dispose();
  }
}
