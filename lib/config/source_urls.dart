import '../models/server_source.dart';
import '../services/kavita_client.dart' show kavitaPageUrl;
import '../services/opds_client.dart' show opdsDownloadUrl, opdsPageUrl;

/// Image URLs for a source's comics, in its server's layout. App pages are
/// 0-based; Komga's are 1-based.
extension SourceUrls on ServerSource {
  String _id(String id) => Uri.encodeComponent(id);

  String comicCover(String id) => switch (type) {
        SourceType.komga => '$baseUrl/api/v1/books/${_id(id)}/thumbnail',
        SourceType.kavita => '$baseUrl/api/Image/chapter-cover?chapterId=${_id(id)}',
        // No cover URL without the feed: the first page stands in.
        SourceType.opds => page(id, 0),
        _ => '$baseUrl/comics/${_id(id)}/cover',
      };

  String seriesCover(String id) => switch (type) {
        SourceType.komga => '$baseUrl/api/v1/series/${_id(id)}/thumbnail',
        SourceType.kavita => '$baseUrl/api/Image/series-cover?seriesId=${_id(id)}',
        SourceType.opds => '',
        _ => '$baseUrl/library/${_id(id)}/cover',
      };

  String page(String id, int zeroBasedPage) => switch (type) {
        SourceType.komga =>
          '$baseUrl/api/v1/books/${_id(id)}/pages/${zeroBasedPage + 1}',
        SourceType.kavita => kavitaPageUrl(baseUrl, id, zeroBasedPage, apiKey ?? ''),
        SourceType.opds =>
          opdsPageUrl(baseUrl, catalogPath ?? '', id, zeroBasedPage),
        _ => '$baseUrl/comics/${_id(id)}/pages/$zeroBasedPage',
      };

  /// Where [DownloadManager] fetches a comic from: the Gutter server's
  /// `/comics/<id>` (it appends `/info` and `/pages/<n>`), the Komga book,
  /// the Kavita chapter, or the OPDS page template and count.
  String comicDownload(String id) => switch (type) {
        SourceType.komga => '$baseUrl/api/v1/books/${_id(id)}',
        SourceType.kavita => '$baseUrl/api/Chapter?chapterId=${_id(id)}',
        SourceType.opds => opdsDownloadUrl(baseUrl, catalogPath ?? '', id),
        _ => '$baseUrl/comics/${_id(id)}',
      };

  /// The whole comic file; a HEAD gives its size (Gutter server only).
  String comicFile(String id) => switch (type) {
        SourceType.komga => '$baseUrl/api/v1/books/${_id(id)}/file',
        SourceType.kavita => '$baseUrl/api/Download/chapter?chapterId=${_id(id)}',
        _ => '$baseUrl/comics/${_id(id)}/download',
      };

  /// Headers for image requests (covers, pages, downloads).
  Map<String, String> get imageHeaders => authHeaders;
}
