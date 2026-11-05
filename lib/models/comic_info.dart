class ComicInfoChapter {
  final int page;
  final String title;
  const ComicInfoChapter({required this.page, required this.title});

  factory ComicInfoChapter.fromJson(Map<String, dynamic> json) =>
      ComicInfoChapter(
        page: json['page'] as int? ?? 0,
        title: json['title'] as String? ?? '',
      );
}

class ComicInfo {
  final String title;
  final String? series;
  final String? number;
  final String? writer;
  final String? penciller;
  final String? summary;
  final String? publisher;
  final int pageCount;
  final List<ComicInfoChapter> chapters;

  const ComicInfo({
    required this.title,
    this.series,
    this.number,
    this.writer,
    this.penciller,
    this.summary,
    this.publisher,
    required this.pageCount,
    this.chapters = const [],
  });

  factory ComicInfo.fromJson(Map<String, dynamic> json) {
    return ComicInfo(
      title: json['title'] as String? ?? '',
      series: json['series'] as String?,
      number: json['number'] as String?,
      writer: json['writer'] as String?,
      penciller: json['penciller'] as String?,
      summary: json['summary'] as String?,
      publisher: json['publisher'] as String?,
      pageCount: json['page_count'] as int? ?? 0,
      chapters: (json['chapters'] as List<dynamic>? ?? [])
          .map((e) => ComicInfoChapter.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
