/// Trilium stamps dates as `2021-12-31 20:18:11.939+0100`: a space instead of
/// `T`, and a UTC offset with no colon. `DateTime.parse` rejects both, so every
/// date coming off ETAPI needs normalising first.
library;

final RegExp _offsetWithoutColon = RegExp(r'([+-])(\d{2})(\d{2})$');

/// Parses a Trilium timestamp, returning null rather than throwing when the
/// value is absent or unrecognisable.
///
/// A malformed date is never worth failing a whole note fetch over, so callers
/// get a null and carry on.
DateTime? parseTriliumDate(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  var normalised = trimmed.replaceFirst(' ', 'T');
  normalised = normalised.replaceFirstMapped(
    _offsetWithoutColon,
    (m) => '${m[1]}${m[2]}:${m[3]}',
  );

  return DateTime.tryParse(normalised);
}
