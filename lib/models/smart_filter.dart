import 'dart:convert';

class FilterCondition {
  final String field;
  final String op;
  final String value;

  const FilterCondition({
    required this.field,
    required this.op,
    required this.value,
  });

  factory FilterCondition.fromJson(Map<String, dynamic> json) {
    return FilterCondition(
      field: json['field'] as String,
      op: json['op'] as String,
      value: json['value'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'field': field,
        'op': op,
        'value': value,
      };
}

class SmartFilter {
  final int id;
  final String name;
  final String icon;
  final String color;
  final List<FilterCondition> conditions;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SmartFilter({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.conditions,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SmartFilter.fromJson(Map<String, dynamic> json) {
    List<FilterCondition> conditions;
    final raw = json['conditions'];
    if (raw is String) {
      final parsed = jsonDecode(raw) as List<dynamic>;
      conditions = parsed
          .map((e) => FilterCondition.fromJson(e as Map<String, dynamic>))
          .toList();
    } else if (raw is List) {
      conditions = raw
          .map((e) => FilterCondition.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      conditions = [];
    }

    return SmartFilter(
      id: json['id'] as int,
      name: json['name'] as String,
      icon: json['icon'] as String? ?? 'filter_list',
      color: json['color'] as String? ?? '#64B5F6',
      conditions: conditions,
      position: json['position'] as int? ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toCreateJson() => {
        'name': name,
        'icon': icon,
        'color': color,
        'conditions': conditions.map((c) => c.toJson()).toList(),
      };
}
