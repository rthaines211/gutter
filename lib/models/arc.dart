class Arc {
  final String id;
  final String name;
  final String imageUrl;
  final bool? selfContained;
  final int total;
  final int present;
  final String source;
  final String publisher;
  final int startYear;
  final int endYear;
  final int read;
  final String coverUrl;
  final DateTime? lastReadAt;
  final String description;
  const Arc({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.selfContained,
    required this.total,
    required this.present,
    required this.source,
    required this.publisher,
    required this.startYear,
    required this.endYear,
    required this.read,
    required this.coverUrl,
    required this.lastReadAt,
    this.description = '',
  });
}
