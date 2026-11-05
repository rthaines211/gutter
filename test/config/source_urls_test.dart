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

  test('image headers carry auth', () {
    const s = ServerSource(
        id: 's', name: 'S', type: SourceType.komga, baseUrl: 'http://h',
        authType: AuthType.apiKey, apiKey: 'k');
    expect(s.imageHeaders, {'X-API-Key': 'k'});
  });
}
