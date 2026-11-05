import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/series.dart';

void main() {
  group('Series metadata fields', () {
    test('fromJson parses publisher, genres, year', () {
      final series = Series.fromJson({
        'id': 'batman-2016',
        'name': 'Batman (2016)',
        'folder_path': '/comics/Batman',
        'issue_count': 10,
        'read_count': 3,
        'cover_url': '/library/batman-2016/cover',
        'writer': 'Tom King',
        'penciller': 'David Finch',
        'publisher': 'DC Comics',
        'genres': ['Action', 'Superhero'],
        'year': 2016,
        'updated_at': '2026-01-01T00:00:00Z',
      });
      expect(series.publisher, 'DC Comics');
      expect(series.genres, ['Action', 'Superhero']);
      expect(series.year, 2016);
    });

    test('fromJson handles missing metadata gracefully', () {
      final series = Series.fromJson({
        'id': 'old-comic',
        'name': 'Old Comic',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      expect(series.publisher, isNull);
      expect(series.genres, isEmpty);
      expect(series.year, isNull);
    });

    test('fromJson handles null genres', () {
      final series = Series.fromJson({
        'id': 'test',
        'name': 'Test',
        'genres': null,
        'updated_at': '2026-01-01T00:00:00Z',
      });
      expect(series.genres, isEmpty);
    });
  });

  group('SeriesDetail metadata fields', () {
    test('fromJson parses publisher, genres, year', () {
      final detail = SeriesDetail.fromJson({
        'id': 'saga',
        'name': 'Saga',
        'issue_count': 54,
        'read_count': 10,
        'cover_url': '/library/saga/cover',
        'writer': 'Brian K. Vaughan',
        'publisher': 'Image Comics',
        'genres': ['Sci-Fi', 'Fantasy'],
        'year': 2012,
        'issues': [],
      });
      expect(detail.publisher, 'Image Comics');
      expect(detail.genres, ['Sci-Fi', 'Fantasy']);
      expect(detail.year, 2012);
    });
  });
}
