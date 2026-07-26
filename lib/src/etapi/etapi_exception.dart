/// Errors raised by [EtapiClient].
///
/// Trilium reports failures as a JSON body of the shape
/// `{"status": 401, "code": "NOT_AUTHENTICATED", "message": "..."}`, so where
/// that body is present we surface Trilium's own [code] and [message] rather
/// than inventing our own wording.
library;

/// Base class for every failure surfaced by the ETAPI layer.
sealed class EtapiException implements Exception {
  const EtapiException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The server was reachable but rejected or could not fulfil the request.
class EtapiHttpException extends EtapiException {
  const EtapiHttpException({
    required this.statusCode,
    required String message,
    this.code,
  }) : super(message);

  /// HTTP status code returned by Trilium.
  final int statusCode;

  /// Trilium's machine-readable error code, when the body carried one.
  ///
  /// Examples seen in practice: `NOT_AUTHENTICATED`, `NOTE_NOT_FOUND`.
  final String? code;

  /// Whether this failure means the token is missing, wrong, or revoked.
  bool get isAuthFailure => statusCode == 401 || code == 'NOT_AUTHENTICATED';

  @override
  String toString() =>
      'EtapiHttpException($statusCode${code == null ? '' : ', $code'}): '
      '$message';
}

/// The server could not be reached at all: DNS failure, refused connection,
/// TLS problem, or timeout.
class EtapiNetworkException extends EtapiException {
  const EtapiNetworkException(super.message, {this.cause});

  /// The underlying error, kept for logging rather than display.
  final Object? cause;
}

/// The server responded, but not with anything we could parse as ETAPI.
///
/// In practice this is what a wrong base URL looks like: pointing at a plain
/// web server returns a perfectly valid 200 full of HTML, which is not an
/// error at the HTTP layer but is useless to us.
class EtapiFormatException extends EtapiException {
  const EtapiFormatException(super.message);
}
