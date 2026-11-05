// test/services/api_client_detect_status_test.dart
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
  tearDown(() => AppLogger.resetForTest());

  test('parses state/scanned/total/candidates', () async {
    final mock = MockClient((req) async {
      expect(req.url.path, '/comics/abc/detect-chapters/status');
      return http.Response(
        jsonEncode({
          'state': 'running',
          'scanned': 42,
          'total': 435,
          'candidates': [
            {'page': 3, 'title': 'Issue 1', 'source': 'ocr', 'confidence': 'medium'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = ApiClient(baseUrl: 'http://test', deviceId: 'd', httpClient: mock);
    final st = await client.detectChaptersStatus('abc', 'job1');
    expect(st.state, 'running');
    expect(st.scanned, 42);
    expect(st.total, 435);
    expect(st.candidates.single.page, 3);
  });

  test('derives state from legacy done:true when state absent', () async {
    final mock = MockClient((req) async => http.Response(
          jsonEncode({'done': true, 'candidates': []}),
          200,
          headers: {'content-type': 'application/json'},
        ));
    final client = ApiClient(baseUrl: 'http://test', deviceId: 'd', httpClient: mock);
    final st = await client.detectChaptersStatus('abc', 'job1');
    expect(st.state, 'done');
  });
}
