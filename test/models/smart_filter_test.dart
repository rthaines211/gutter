import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/smart_filter.dart';

void main() {
  group('FilterCondition', () {
    test('fromJson/toJson round-trip', () {
      final json = {'field': 'status', 'op': 'eq', 'value': 'unread'};
      final cond = FilterCondition.fromJson(json);
      expect(cond.field, 'status');
      expect(cond.op, 'eq');
      expect(cond.value, 'unread');
      expect(cond.toJson(), json);
    });
  });

  group('SmartFilter', () {
    test('fromJson parses all fields', () {
      final json = {
        'id': 1,
        'name': 'Unread Horror',
        'icon': 'filter_list',
        'color': '#64B5F6',
        'conditions': '[{"field":"status","op":"eq","value":"unread"}]',
        'position': 0,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      };
      final sf = SmartFilter.fromJson(json);
      expect(sf.id, 1);
      expect(sf.name, 'Unread Horror');
      expect(sf.conditions.length, 1);
      expect(sf.conditions[0].field, 'status');
    });

    test('fromJson handles conditions as list', () {
      final json = {
        'id': 2,
        'name': 'Test',
        'icon': 'star',
        'color': '#FF0000',
        'conditions': [
          {'field': 'genre', 'op': 'eq', 'value': 'Horror'}
        ],
        'position': 0,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      };
      final sf = SmartFilter.fromJson(json);
      expect(sf.conditions.length, 1);
      expect(sf.conditions[0].field, 'genre');
    });

    test('toCreateJson produces correct format', () {
      final sf = SmartFilter(
        id: 0,
        name: 'Big Series',
        icon: 'filter_list',
        color: '#64B5F6',
        conditions: [
          FilterCondition(field: 'issue_count', op: 'gte', value: '10'),
        ],
        position: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final json = sf.toCreateJson();
      expect(json['name'], 'Big Series');
      expect(json['conditions'], isA<List>());
      expect((json['conditions'] as List).length, 1);
    });
  });
}
