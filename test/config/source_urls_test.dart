import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/source_urls.dart';
import 'package:comic_reader_app/models/server_source.dart';

void main() {
  ServerSource source(SourceType type) => ServerSource(
      id: 's', name: 'S', type: type, baseUrl: 'http://h', authType: AuthType.none);

  test('Gutter server layout', () {
    final s = source(SourceType.custom);
    expect(s.comicCover('a'), 'http://h/comics/a/cover');
    expect(s.seriesCover('a'), 'http://h/library/a/cover');
    expect(s.page('a', 0), 'http://h/comics/a/pages/0');
  });

  test('Komga layout, 1-based pages', () {
    final s = source(SourceType.komga);
    expect(s.comicCover('a'), 'http://h/api/v1/books/a/thumbnail');
    expect(s.seriesCover('a'), 'http://h/api/v1/series/a/thumbnail');
    expect(s.page('a', 0), 'http://h/api/v1/books/a/pages/1');
  });

  test('Kavita layout, 0-based pages with the key', () {
    const s = ServerSource(
        id: 's', name: 'S', type: SourceType.kavita, baseUrl: 'http://h',
        authType: AuthType.apiKey, apiKey: 'k');
    expect(s.comicCover('3'), 'http://h/api/Image/chapter-cover?chapterId=3');
    expect(s.seriesCover('7'), 'http://h/api/Image/series-cover?seriesId=7');
    expect(s.page('3', 0), 'http://h/api/Reader/image?chapterId=3&page=0&apiKey=k');
    expect(s.comicDownload('3'), 'http://h/api/Chapter?chapterId=3');
    expect(s.imageHeaders, {'X-API-Key': 'k'});
  });

  test('image headers carry auth', () {
    const s = ServerSource(
        id: 's', name: 'S', type: SourceType.komga, baseUrl: 'http://h',
        authType: AuthType.apiKey, apiKey: 'k');
    expect(s.imageHeaders, {'X-API-Key': 'k'});
  });
}
