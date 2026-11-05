class ReadingSession {
  final int id;
  final String comicId;
  final String seriesId;
  final String seriesName;
  final String comicName;
  final String coverUrl;
  final DateTime startedAt;
  final int pagesRead;
  final int durationS;

  const ReadingSession({
    required this.id,
    required this.comicId,
    required this.seriesId,
    required this.seriesName,
    required this.comicName,
    required this.coverUrl,
    required this.startedAt,
    required this.pagesRead,
    required this.durationS,
  });

  factory ReadingSession.fromJson(Map<String, dynamic> json) {
    return ReadingSession(
      id: json['id'] as int,
      comicId: json['comic_id'] as String,
      seriesId: json['series_id'] as String? ?? '',
      seriesName: json['series_name'] as String? ?? '',
      comicName: json['comic_name'] as String? ?? '',
      coverUrl: json['cover_url'] as String? ?? '',
      startedAt: DateTime.parse(json['started_at'] as String),
      pagesRead: json['pages_read'] as int? ?? 0,
      durationS: json['duration_s'] as int? ?? 0,
    );
  }

  String get formattedDuration {
    final hours = durationS ~/ 3600;
    final minutes = (durationS % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}
