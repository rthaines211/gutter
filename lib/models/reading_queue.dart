/// A named, ordered list of series the user plans to read. Mirrors the shape
/// the backend stores. `id` is client-generated (string) so queues can be
/// created offline.
class ReadingQueue {
  final String id;
  final String name;
  final String icon;
  final String color;
  final int position;
  final List<String> seriesIds; // ordered
  final DateTime createdAt;
  final DateTime updatedAt;

  const ReadingQueue({
    required this.id,
    required this.name,
    this.icon = 'bookmark',
    this.color = '#FFB74D',
    this.position = 0,
    this.seriesIds = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReadingQueue.fromJson(Map<String, dynamic> json) {
    return ReadingQueue(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String? ?? 'bookmark',
      color: json['color'] as String? ?? '#FFB74D',
      position: json['position'] as int? ?? 0,
      seriesIds:
          (json['series_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Body sent to the server (PUT /queues/{id}) and stored in the outbox.
  Map<String, dynamic> toSyncJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'color': color,
    'position': position,
    'series_ids': seriesIds,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  ReadingQueue copyWith({
    String? name,
    String? icon,
    String? color,
    int? position,
    List<String>? seriesIds,
    DateTime? updatedAt,
  }) {
    return ReadingQueue(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      position: position ?? this.position,
      seriesIds: seriesIds ?? this.seriesIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
