class ChapterCandidate {
  final int page;
  final String title;
  final String source;     // comicinfo|folder|filename|ocr
  final String confidence; // high|medium|low

  const ChapterCandidate({
    required this.page,
    required this.title,
    required this.source,
    required this.confidence,
  });

  factory ChapterCandidate.fromJson(Map<String, dynamic> json) => ChapterCandidate(
        page: json['page'] as int? ?? 0,
        title: json['title'] as String? ?? '',
        source: json['source'] as String? ?? 'unknown',
        confidence: json['confidence'] as String? ?? 'medium',
      );
}
