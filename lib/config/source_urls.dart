import '../models/server_source.dart';

/// Image URLs for a source's comics, in its server's layout. App pages are
/// 0-based; Komga's are 1-based.
extension SourceUrls on ServerSource {
  bool get _komga => type == SourceType.komga;

  String comicCover(String id) => _komga
      ? '$baseUrl/api/v1/books/${Uri.encodeComponent(id)}/thumbnail'
      : '$baseUrl/comics/${Uri.encodeComponent(id)}/cover';

  String seriesCover(String id) => _komga
      ? '$baseUrl/api/v1/series/${Uri.encodeComponent(id)}/thumbnail'
      : '$baseUrl/library/${Uri.encodeComponent(id)}/cover';

  String page(String id, int zeroBasedPage) => _komga
      ? '$baseUrl/api/v1/books/${Uri.encodeComponent(id)}/pages/${zeroBasedPage + 1}'
      : '$baseUrl/comics/${Uri.encodeComponent(id)}/pages/$zeroBasedPage';

  /// Where [DownloadManager] fetches a comic from: the Gutter server's
  /// `/comics/<id>` (it appends `/info` and `/pages/<n>`), or the Komga book.
  String comicDownload(String id) => _komga
      ? '$baseUrl/api/v1/books/${Uri.encodeComponent(id)}'
      : '$baseUrl/comics/${Uri.encodeComponent(id)}';

  /// The whole comic file; a HEAD gives its size.
  String comicFile(String id) => _komga
      ? '$baseUrl/api/v1/books/${Uri.encodeComponent(id)}/file'
      : '$baseUrl/comics/${Uri.encodeComponent(id)}/download';

  /// Headers for image requests (covers, pages, downloads).
  Map<String, String> get imageHeaders => authHeaders;
}
