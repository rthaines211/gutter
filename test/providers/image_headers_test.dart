import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/server_source.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/source_provider.dart';
import 'package:comic_reader_app/widgets/filmstrip_scrubber.dart';

ServerSource _source(String baseUrl) =>
    ServerSource.createDefault(url: baseUrl)
        .copyWith(authType: AuthType.apiKey, apiKey: 'k');

const _auth = {'Authorization': 'Bearer k'};

void main() {
  group('imageHeadersFor', () {
    test('same-origin URL gets the source headers', () {
      final s = _source('https://myserver.com');
      expect(imageHeadersFor(s, 'https://myserver.com/comics/1/cover'), _auth);
    });

    test('trailing slash on baseUrl is normalized', () {
      final s = _source('https://myserver.com/');
      expect(imageHeadersFor(s, 'https://myserver.com/comics/1/cover'), _auth);
    });

    test('third-party image host gets nothing', () {
      final s = _source('https://myserver.com');
      expect(
          imageHeadersFor(
              s, 'https://comicvine.gamespot.com/a/uploads/scale_small/1.jpg'),
          isEmpty);
    });

    test('host-prefix trick gets nothing', () {
      final s = _source('https://myserver.com');
      expect(imageHeadersFor(s, 'https://myserver.com.evil.com/x.jpg'),
          isEmpty);
      expect(imageHeadersFor(s, 'https://myserver.com:9999/x.jpg'), isEmpty);
    });

    test('empty baseUrl sends nothing', () {
      expect(imageHeadersFor(_source(''), 'https://a.b/x.jpg'), isEmpty);
    });
  });

  testWidgets('a display widget sends source auth on a same-origin page URL',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        activeSourceProvider.overrideWithValue(_source('https://myserver.com')),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: FilmstripScrubber(
            currentPage: 1,
            totalPages: 3,
            pageUrlBuilder: (p) => 'https://myserver.com/comics/c/pages/$p',
            onPageSelected: (_) {},
          ),
        ),
      ),
    ));
    await tester.pump();
    final images =
        tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(images, isNotEmpty);
    for (final img in images) {
      expect(img.httpHeaders, _auth);
    }
  });
}
