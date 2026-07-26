import '../etapi/etapi_client.dart';

/// Everything needed to reach one Trilium instance.
///
/// Multi-instance support is on the roadmap, so this is modelled as a named
/// profile from the start rather than as two loose strings that would have to
/// be untangled later.
class ConnectionProfile {
  const ConnectionProfile({required this.serverUrl, required this.token});

  /// The URL exactly as the user typed it, kept so the settings field can show
  /// it back to them unchanged. Use [baseUri] for anything that makes requests.
  final String serverUrl;

  final String token;

  Uri get baseUri => normalizeBaseUrl(serverUrl);

  /// A short label for the connection, suitable for a title bar.
  String get displayName {
    try {
      return baseUri.host;
    } on Object {
      return serverUrl;
    }
  }

  ConnectionProfile copyWith({String? serverUrl, String? token}) {
    return ConnectionProfile(
      serverUrl: serverUrl ?? this.serverUrl,
      token: token ?? this.token,
    );
  }
}
