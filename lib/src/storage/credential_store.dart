import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'connection_profile.dart';

/// Persistence for the saved connection.
///
/// Kept behind an interface so tests never touch the platform keystore, and so
/// a future multi-profile store can be swapped in without the UI changing.
abstract class CredentialStore {
  Future<ConnectionProfile?> read();
  Future<void> save(ConnectionProfile profile);
  Future<void> clear();
}

/// Stores the token in the OS credential store: DPAPI on Windows, Keychain on
/// macOS, libsecret on Linux.
///
/// An ETAPI token is a bearer credential with full read and write access to
/// every note on the instance, so it does not belong in shared preferences or
/// a plain file next to the executable.
class SecureCredentialStore implements CredentialStore {
  const SecureCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _serverUrlKey = 'triliage.serverUrl';
  static const _tokenKey = 'triliage.token';

  @override
  Future<ConnectionProfile?> read() async {
    final serverUrl = await _storage.read(key: _serverUrlKey);
    final token = await _storage.read(key: _tokenKey);
    if (serverUrl == null || token == null) return null;
    if (serverUrl.isEmpty || token.isEmpty) return null;
    return ConnectionProfile(serverUrl: serverUrl, token: token);
  }

  @override
  Future<void> save(ConnectionProfile profile) async {
    await _storage.write(key: _serverUrlKey, value: profile.serverUrl);
    await _storage.write(key: _tokenKey, value: profile.token);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _serverUrlKey);
    await _storage.delete(key: _tokenKey);
  }
}

/// A store that keeps the profile for the lifetime of the process only.
///
/// Used by tests, and as the fallback when the platform keystore is
/// unavailable, so the app degrades to "you must reconnect each launch"
/// instead of refusing to start.
class InMemoryCredentialStore implements CredentialStore {
  InMemoryCredentialStore([this._profile]);

  ConnectionProfile? _profile;

  @override
  Future<ConnectionProfile?> read() async => _profile;

  @override
  Future<void> save(ConnectionProfile profile) async => _profile = profile;

  @override
  Future<void> clear() async => _profile = null;
}
