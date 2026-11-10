class Bookmark {
  final String id;
  final String comicId;
  final int pageNum;
  final String? note;
  final DateTime createdAt;

  const Bookmark({
    required this.id,
    required this.comicId,
    required this.pageNum,
    this.note,
    required this.createdAt,
  });

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      id: json['id'] as String? ?? '',
      comicId: json['comic_id'] as String? ?? '',
      pageNum: json['page_num'] as int? ?? 0,
      note: json['note'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      // No 'id': the server's is an integer and it rejected the whole
      // progress write when it got this string.
      'comic_id': comicId,
      'page_num': pageNum,
      if (note != null) 'note': note,
      // UTC (Z suffix) so the Go backend's time.Time decode accepts it (RFC3339
      // needs a timezone; a local toIso8601String() has none → 400).
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}
