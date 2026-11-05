class ReadingProgress {
  final String comicId;
  final int currentPage;
  final int totalPages;
  final DateTime? updatedAt;
  final String? seriesId;

  const ReadingProgress({
    required this.comicId,
    required this.currentPage,
    required this.totalPages,
    this.updatedAt,
    this.seriesId,
  });

  factory ReadingProgress.fromJson(Map<String, dynamic> json) {
    return ReadingProgress(
      comicId: json['comic_id'] as String? ?? '',
      currentPage: json['current_page'] as int? ?? 0,
      totalPages: json['total_pages'] as int? ?? 1,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      seriesId: json['series_id'] as String?,
    );
  }

  double get progress =>
      totalPages > 0 ? (currentPage / totalPages).clamp(0.0, 1.0) : 0.0;
}
