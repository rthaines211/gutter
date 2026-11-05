import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/reading_session.dart';

void main() {
  group('ReadingSession', () {
    test('fromJson parses all fields', () {
      final session = ReadingSession.fromJson({
        'id': 42,
        'comic_id': 'abc123',
        'series_id': 'batman-2016',
        'series_name': 'Batman (2016)',
        'comic_name': 'Batman 001',
        'cover_url': '/library/batman-2016/cover',
        'started_at': '2026-04-21T14:30:00Z',
        'pages_read': 24,
        'duration_s': 900,
      });
      expect(session.id, 42);
      expect(session.seriesName, 'Batman (2016)');
      expect(session.pagesRead, 24);
      expect(session.durationS, 900);
      expect(session.startedAt.year, 2026);
    });

    test('formattedDuration formats minutes only', () {
      final s = ReadingSession.fromJson({
        'id': 1, 'comic_id': 'a', 'series_id': 'b', 'series_name': 'S',
        'comic_name': 'C', 'cover_url': '', 'started_at': '2026-01-01T00:00:00Z',
        'pages_read': 5, 'duration_s': 300,
      });
      expect(s.formattedDuration, '5m');
    });

    test('formattedDuration formats hours and minutes', () {
      final s = ReadingSession.fromJson({
        'id': 2, 'comic_id': 'a', 'series_id': 'b', 'series_name': 'S',
        'comic_name': 'C', 'cover_url': '', 'started_at': '2026-01-01T00:00:00Z',
        'pages_read': 5, 'duration_s': 4920,
      });
      expect(s.formattedDuration, '1h 22m');
    });
  });
}
