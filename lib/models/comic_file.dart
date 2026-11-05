class ComicFile {
  final String name;
  final String type;
  final int size;
  final String? coverUrl;
  final String path;

  const ComicFile({
    required this.name,
    required this.type,
    required this.size,
    this.coverUrl,
    required this.path,
  });

  factory ComicFile.fromJson(Map<String, dynamic> json) {
    return ComicFile(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      coverUrl: json['cover_url'] as String?,
      path: json['path'] as String? ?? '',
    );
  }

  bool get isDir => type == 'dir';
  bool get isComic => !isDir;
}
