import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'etapi_exception.dart';
import 'models/app_info.dart';
import 'models/note.dart';

/// Turns whatever the user typed into a usable origin.
///
/// People paste all of `notes.example.com`, `https://notes.example.com/`, and
/// `https://notes.example.com/etapi` into a server field, and all three mean
/// the same instance. Rejecting two of them would be pedantry, so normalise
/// instead: default the scheme to https, drop a trailing slash, and drop a
/// trailing `/etapi` segment that we are about to append ourselves.
Uri normalizeBaseUrl(String raw) {
  var text = raw.trim();
  if (text.isEmpty) {
    throw const EtapiFormatException('Server URL is empty.');
  }
  if (!text.contains('://')) {
    text = 'https://$text';
  }

  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) {
    throw EtapiFormatException('"$raw" is not a valid URL.');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw EtapiFormatException(
      'Unsupported scheme "${uri.scheme}". Use http or https.',
    );
  }

  final segments = List<String>.from(uri.pathSegments)
    ..removeWhere((s) => s.isEmpty);
  if (segments.isNotEmpty && segments.last == 'etapi') {
    segments.removeLast();
  }

  // Built fresh rather than via replace(), because replace() treats a null
  // query or fragment as "leave unchanged" and would carry them through.
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: segments,
  );
}

/// Builds an ETAPI endpoint URL beneath [baseUrl].
///
/// Path segments are appended explicitly instead of using [Uri.resolve],
/// because resolving a relative path against a base like
/// `https://example.com/trilium` replaces the last segment rather than nesting
/// under it, silently breaking every reverse-proxied sub-path install.
/// Appending also means [Uri] percent-encodes each segment for us, so a note id
/// containing a slash cannot escape its position in the path.
Uri etapiUri(
  Uri baseUrl,
  List<String> segments, {
  Map<String, String>? queryParameters,
}) {
  return baseUrl.replace(
    pathSegments: [
      ...baseUrl.pathSegments.where((s) => s.isNotEmpty),
      ...segments,
    ],
    queryParameters: queryParameters,
  );
}

/// A read-only client for Trilium's External API.
///
/// One instance is bound to one server and one token. Construct a new client
/// rather than mutating credentials, so an in-flight request can never pick up
/// a half-changed configuration.
class EtapiClient {
  EtapiClient({
    required Uri baseUrl,
    required String token,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  })  : _baseUrl = baseUrl,
        _token = token,
        _http = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

  final Uri _baseUrl;
  final String _token;
  final http.Client _http;
  final bool _ownsHttpClient;
  final Duration timeout;

  Uri get baseUrl => _baseUrl;

  /// Exchanges a Trilium password for an ETAPI token.
  ///
  /// Offered alongside token entry because creating a token by hand means
  /// digging through Trilium's options UI, and a password the user already
  /// knows is a lower barrier to a first successful connection. The token this
  /// returns is what gets stored; the password is never persisted.
  static Future<String> login({
    required Uri baseUrl,
    required String password,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final client = httpClient ?? http.Client();
    try {
      final response = await client
          .post(
            etapiUri(baseUrl, const ['etapi', 'auth', 'login']),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'password': password}),
          )
          .timeout(timeout);

      final body = _decodeBody(response);
      if (response.statusCode >= 400) {
        throw _errorFor(response.statusCode, body);
      }
      final token = body is Map<String, dynamic>
          ? body['authToken'] as String?
          : null;
      if (token == null || token.isEmpty) {
        throw const EtapiFormatException(
          'Login succeeded but the server returned no token.',
        );
      }
      return token;
    } on TimeoutException {
      throw EtapiNetworkException('Timed out contacting $baseUrl.');
    } on http.ClientException catch (e) {
      throw EtapiNetworkException(e.message, cause: e);
    } finally {
      if (httpClient == null) client.close();
    }
  }

  /// Server version and identity. Doubles as the connection test.
  Future<AppInfo> appInfo() async {
    final json = await _getJson(const ['etapi', 'app-info']);
    if (json is! Map<String, dynamic>) {
      throw const EtapiFormatException(
        'The server responded, but not with Trilium app info. '
        'Check that the URL points at a Trilium instance.',
      );
    }
    return AppInfo.fromJson(json);
  }

  Future<Note> note(String noteId) async {
    final json = await _getJson(['etapi', 'notes', noteId]);
    if (json is! Map<String, dynamic>) {
      throw const EtapiFormatException('Unexpected note payload.');
    }
    return Note.fromJson(json);
  }

  /// The raw body of a note, as stored: HTML for text notes, source for code
  /// notes.
  Future<String> noteContent(String noteId) async {
    final response = await _get(['etapi', 'notes', noteId, 'content']);
    if (response.statusCode >= 400) {
      throw _errorFor(response.statusCode, _decodeBody(response));
    }
    // Content is returned as-is rather than JSON-wrapped, and Trilium does not
    // always send a charset, so decode as UTF-8 explicitly instead of trusting
    // http's latin-1 default.
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  /// Fetches the direct children of [noteId] in the order Trilium lists them.
  ///
  /// ETAPI has no "get many notes" call, so this fans out one request per
  /// child. Children are fetched concurrently because a tree level of twenty
  /// notes issued serially is a visible stall, and any child that fails to load
  /// is dropped rather than failing the whole level: one unreadable note should
  /// not blank out its siblings.
  Future<List<Note>> children(String noteId) async {
    final parent = await note(noteId);
    if (parent.childNoteIds.isEmpty) return const [];

    final results = await Future.wait(
      parent.childNoteIds.map((id) async {
        try {
          return await note(id);
        } on EtapiException {
          return null;
        }
      }),
    );
    return results.whereType<Note>().toList(growable: false);
  }

  /// Full-text and attribute search using Trilium's own query syntax.
  Future<List<Note>> search(
    String query, {
    bool fastSearch = false,
    bool includeArchivedNotes = false,
    String? ancestorNoteId,
    int? limit,
  }) async {
    final json = await _getJson(const ['etapi', 'notes'], queryParameters: {
      'search': query,
      'fastSearch': '$fastSearch',
      'includeArchivedNotes': '$includeArchivedNotes',
      if (ancestorNoteId != null) 'ancestorNoteId': ancestorNoteId,
      if (limit != null) 'limit': '$limit',
    });

    if (json is! Map<String, dynamic>) {
      throw const EtapiFormatException('Unexpected search payload.');
    }
    final results = json['results'];
    if (results is! List) return const [];
    return results
        .whereType<Map<String, dynamic>>()
        .map(Note.fromJson)
        .toList(growable: false);
  }

  /// Releases the underlying HTTP client, unless one was injected: an injected
  /// client belongs to the caller and closing it would be a surprise.
  void close() {
    if (_ownsHttpClient) _http.close();
  }

  Future<http.Response> _get(
    List<String> segments, {
    Map<String, String>? queryParameters,
  }) async {
    final uri = etapiUri(
      _baseUrl,
      segments,
      queryParameters: queryParameters,
    );

    try {
      return await _http.get(
        uri,
        // ETAPI expects the bare token as the Authorization value, with no
        // "Bearer " prefix. Sending the prefix fails authentication.
        headers: {'Authorization': _token, 'Accept': 'application/json'},
      ).timeout(timeout);
    } on TimeoutException {
      throw EtapiNetworkException('Timed out contacting $uri.');
    } on http.ClientException catch (e) {
      throw EtapiNetworkException(e.message, cause: e);
    }
  }

  Future<Object?> _getJson(
    List<String> segments, {
    Map<String, String>? queryParameters,
  }) async {
    final response = await _get(segments, queryParameters: queryParameters);
    final body = _decodeBody(response);
    if (response.statusCode >= 400) {
      throw _errorFor(response.statusCode, body);
    }
    return body;
  }

  /// Decodes a response body as JSON, returning the raw string when it is not
  /// JSON at all. Callers decide whether that is fatal.
  static Object? _decodeBody(http.Response response) {
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  static EtapiException _errorFor(int statusCode, Object? body) {
    if (body is Map<String, dynamic>) {
      return EtapiHttpException(
        statusCode: statusCode,
        code: body['code'] as String?,
        message: body['message'] as String? ?? 'Request failed ($statusCode).',
      );
    }
    // A non-JSON error body almost always means we hit something that is not
    // ETAPI, so say that rather than echoing a page of HTML at the user.
    return EtapiHttpException(
      statusCode: statusCode,
      message: statusCode == 404
          ? 'Not found. Check that the URL points at a Trilium instance.'
          : 'Request failed ($statusCode).',
    );
  }
}
