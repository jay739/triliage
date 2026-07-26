import 'package:flutter_test/flutter_test.dart';
import 'package:triliage/src/etapi/trilium_date.dart';

void main() {
  group('parseTriliumDate', () {
    test('parses Trilium\'s space-separated form with a colonless offset', () {
      final parsed = parseTriliumDate('2021-12-31 20:18:11.939+0100');

      expect(parsed, isNotNull);
      expect(parsed!.toUtc().year, 2021);
      expect(parsed.toUtc().month, 12);
      expect(parsed.toUtc().day, 31);
      // 20:18 at +0100 is 19:18 UTC. This is the whole point of the helper:
      // DateTime.parse rejects the string outright, so a naive fallback would
      // silently lose the offset.
      expect(parsed.toUtc().hour, 19);
      expect(parsed.toUtc().minute, 18);
    });

    test('parses a negative offset', () {
      final parsed = parseTriliumDate('2022-06-01 10:00:00.000-0430');

      expect(parsed, isNotNull);
      expect(parsed!.toUtc().hour, 14);
      expect(parsed.toUtc().minute, 30);
    });

    test('parses plain ISO 8601 unchanged', () {
      final parsed = parseTriliumDate('2022-02-09T22:52:36Z');

      expect(parsed, isNotNull);
      expect(parsed!.toUtc().hour, 22);
    });

    test('returns null for null, empty, and unparseable input', () {
      expect(parseTriliumDate(null), isNull);
      expect(parseTriliumDate(''), isNull);
      expect(parseTriliumDate('   '), isNull);
      expect(parseTriliumDate('not a date'), isNull);
    });
  });
}
