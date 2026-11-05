import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/reading_queue.dart';

void main() {
  group('ReadingQueue', () {
    test('fromJson parses ordered series_ids', () {
      final json = {
        'id': 'q1',
        'name': 'Weekend',
        'icon': 'star',
        'color': '#FFD700',
        'position': 2,
        'series_ids': ['batman', 'saga'],
        'created_at': '2026-06-16T12:00:00Z',
        'updated_at': '2026-06-16T12:00:00Z',
      };
      final q = ReadingQueue.fromJson(json);
      expect(q.id, 'q1');
      expect(q.name, 'Weekend');
      expect(q.position, 2);
      expect(q.seriesIds, ['batman', 'saga']);
    });

    test('fromJson applies defaults for missing optional fields', () {
      final q = ReadingQueue.fromJson({'id': 'q2', 'name': 'Minimal'});
      expect(q.icon, 'bookmark');
      expect(q.color, '#FFB74D');
      expect(q.position, 0);
      expect(q.seriesIds, isEmpty);
    });

    test('toSyncJson round-trips through fromJson', () {
      final q = ReadingQueue(
        id: 'q3',
        name: 'Marvel',
        icon: 'bolt',
        color: '#FF0000',
        position: 1,
        seriesIds: const ['a', 'b'],
        createdAt: DateTime.utc(2026, 6, 16),
        updatedAt: DateTime.utc(2026, 6, 16),
      );
      final back = ReadingQueue.fromJson(q.toSyncJson());
      expect(back.id, 'q3');
      expect(back.name, 'Marvel');
      expect(back.icon, 'bolt');
      expect(back.color, '#FF0000');
      expect(back.position, 1);
      expect(back.seriesIds, ['a', 'b']);
    });

    test('copyWith replaces only given fields', () {
      final q = ReadingQueue(
        id: 'q4',
        name: 'A',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final q2 = q.copyWith(seriesIds: const ['x']);
      expect(q2.id, 'q4');
      expect(q2.name, 'A');
      expect(q2.seriesIds, ['x']);
      expect(q.seriesIds, isEmpty); // original untouched
    });
  });
}
