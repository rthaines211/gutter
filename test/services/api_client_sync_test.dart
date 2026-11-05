import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';

void main() {
  setUp(() async {
    await AppLogger.init(logDirFactory: () async => null);
  });

  tearDown(() {
    AppLogger.resetForTest();
  });

  test('fetchSync hits /sync with since param and parses response', () async {
    final mock = MockClient((req) async {
      expect(req.url.path, '/sync');
      expect(req.url.queryParameters['since'], '123');
      return http.Response(
        jsonEncode({
          'server_time': 999,
          'series': [
            {'id': 's1', 'name': 'Batman', 'updated_at': '2026-01-01T00:00:00Z', 'issues': []}
          ],
          'progress': [],
          'series_ids': ['s1'],
          'progress_ids': [],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client =
        ApiClient(baseUrl: 'http://test', deviceId: 'dev1', httpClient: mock);
    final resp = await client.fetchSync(since: 123);
    expect(resp.serverTime, 999);
    expect(resp.series.single['id'], 's1');
    expect(resp.seriesIds, ['s1']);
  });
}
