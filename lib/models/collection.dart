class Collection {
  final int id;
  final String name;
  final String icon;
  final String color;
  final int position;
  final List<String> seriesIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Collection({
    required this.id,
    required this.name,
    this.icon = 'bookmark',
    this.color = '#FFB74D',
    this.position = 0,
    this.seriesIds = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory Collection.fromJson(Map<String, dynamic> json) {
    return Collection(
      id: json['id'] as int,
      name: json['name'] as String,
      icon: json['icon'] as String? ?? 'bookmark',
      color: json['color'] as String? ?? '#FFB74D',
      position: json['position'] as int? ?? 0,
      seriesIds: (json['series_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
