class Chapter {
  final String id; // deterministic: "$comicId:$pageNum"
  final String comicId;
  final int pageNum;
  final String title;
  final DateTime createdAt;

  const Chapter({
    required this.id,
    required this.comicId,
    required this.pageNum,
    required this.title,
    required this.createdAt,
  });

  factory Chapter.create({
    required String comicId,
    required int pageNum,
    required String title,
  }) =>
      Chapter(
        id: '$comicId:$pageNum',
        comicId: comicId,
        pageNum: pageNum,
        title: title,
        createdAt: DateTime.now(),
      );

  factory Chapter.fromJson(Map<String, dynamic> json) {
    final comicId = json['comic_id'] as String? ?? '';
    final pageNum = json['page_num'] as int? ?? 0;
    return Chapter(
      id: '$comicId:$pageNum',
      comicId: comicId,
      pageNum: pageNum,
      title: json['title'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'comic_id': comicId,
        'page_num': pageNum,
        'title': title,
        // UTC (Z suffix) — the Go backend decodes created_at as time.Time,
        // which requires an RFC3339 timezone; a local toIso8601String() has
        // none and 400s the whole PUT /reading payload.
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  Chapter copyWith({String? title}) => Chapter(
        id: id,
        comicId: comicId,
        pageNum: pageNum,
        title: title ?? this.title,
        createdAt: createdAt,
      );
}
