import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/collection.dart';

void main() {
  group('Collection', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 1,
        'name': 'Favorites',
        'icon': 'star',
        'color': '#FFD700',
        'position': 0,
        'series_ids': ['batman', 'spider-man'],
        'created_at': '2026-04-21T12:00:00Z',
        'updated_at': '2026-04-21T12:00:00Z',
      };
      final c = Collection.fromJson(json);
      expect(c.id, 1);
      expect(c.name, 'Favorites');
      expect(c.icon, 'star');
      expect(c.color, '#FFD700');
      expect(c.position, 0);
      expect(c.seriesIds, ['batman', 'spider-man']);
    });

    test('fromJson handles empty series_ids', () {
      final json = {
        'id': 2,
        'name': 'Empty',
        'icon': 'bookmark',
        'color': '#FFB74D',
        'position': 1,
        'series_ids': <dynamic>[],
        'created_at': '2026-04-21T12:00:00Z',
        'updated_at': '2026-04-21T12:00:00Z',
      };
      final c = Collection.fromJson(json);
      expect(c.seriesIds, isEmpty);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 3,
        'name': 'Minimal',
      };
      final c = Collection.fromJson(json);
      expect(c.icon, 'bookmark');
      expect(c.color, '#FFB74D');
      expect(c.seriesIds, isEmpty);
    });
  });
}
