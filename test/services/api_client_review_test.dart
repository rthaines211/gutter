import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:comic_reader_app/models/review_item.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';

void main() {
  setUpAll(() async {
    await AppLogger.init(logDirFactory: () async => null);
  });

  late List<http.Request> requests;

  ApiClient clientReturning(int status, String body) {
    requests = [];
    return ApiClient(
      baseUrl: 'http://x',
      deviceId: 'test',
      httpClient: MockClient((req) async {
        requests.add(req);
        return http.Response(body, status);
      }),
    );
  }

  test('fetchReviewQueue parses count and items', () async {
    final client = clientReturning(
      200,
      jsonEncode({
        'count': 1,
        'items': [
          {
            'series_id': 's1',
            'name': 'World\'s Finest',
            'state': 'collection',
            'local_cover_url': '/library/s1/cover',
            'guess_volume_id': '141907',
            'guess_source': 'comicvine',
            'guess_name': 'Batman/Superman: World\'s Finest',
            'guess_publisher': 'DC',
            'guess_year': '2022',
            'guess_issue_count': 32,
            'guess_cover_url': 'http://img/c.jpg',
          }
        ],
      }),
    );
    final r = await client.fetchReviewQueue();
    expect(r.count, 1);
    expect(r.items.single.guessName, 'Batman/Superman: World\'s Finest');
    expect(r.items.single.hasGuess, true);
    expect(r.items.single.isCollection, true);
    expect(requests.single.url.path, '/review');
  });

  test('searchReviewVolumes blank query makes no request', () async {
    final client = clientReturning(200, '[]');
    expect(await client.searchReviewVolumes('  '), isEmpty);
    expect(requests, isEmpty);
  });

  test('searchReviewVolumes parses hits', () async {
    final client = clientReturning(
      200,
      jsonEncode([
        {
          'source': 'comicvine',
          'volume_id': '9',
          'name': 'N',
          'year': '2020',
          'publisher': 'P',
          'issue_count': 3,
          'cover_url': '',
        }
      ]),
    );
    final hits = await client.searchReviewVolumes('bat man');
    expect(hits.single.volumeId, '9');
    expect(requests.single.url.queryParameters['q'], 'bat man');
  });

  test('pinReviewVolume posts source and volume_id', () async {
    final client = clientReturning(204, '');
    await client.pinReviewVolume(
      's/1',
      const VolumeHit(
        source: 'comicvine',
        volumeId: '141907',
        name: 'n',
        year: '',
        publisher: '',
        issueCount: 0,
        coverUrl: '',
      ),
    );
    final req = requests.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/review/s%2F1/volume');
    expect(jsonDecode(req.body), {'source': 'comicvine', 'volume_id': '141907'});
  });

  test('confirmReview and dontMatchReview accept 204', () async {
    final client = clientReturning(204, '');
    await client.confirmReview('a');
    await client.dontMatchReview('a');
    expect(requests.map((r) => r.url.path), ['/review/a/confirm', '/review/a/dont-match']);
  });

  test('confirmReview throws ApiException on 409', () async {
    final client = clientReturning(409, '{"error":"x"}');
    await expectLater(() => client.confirmReview('a'), throwsA(isA<ApiException>()));
  });
}
