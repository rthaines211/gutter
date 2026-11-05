// updateProgress must OMIT the chapters field when chapters is null, so a
// routine progress save doesn't tell the backend to replace (wipe) the set.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:comic_reader_app/models/chapter.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';

void main() {
  setUp(() async => AppLogger.init(logDirFactory: () async => null));
  tearDown(() => AppLogger.resetForTest());

  test('chapters omitted from body when null', () async {
    Map<String, dynamic>? sent;
    final mock = MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response('{}', 200, headers: {'content-type': 'application/json'});
    });
    final client = ApiClient(baseUrl: 'http://t', deviceId: 'd', httpClient: mock);
    await client.updateProgress(comicId: 'c', currentPage: 5, totalPages: 100);
    expect(sent!.containsKey('chapters'), isFalse,
        reason: 'progress-only save must not carry chapters');
    expect(sent!['current_page'], 5);
  });

  test('chapters present in body when provided', () async {
    Map<String, dynamic>? sent;
    final mock = MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response('{}', 200, headers: {'content-type': 'application/json'});
    });
    final client = ApiClient(baseUrl: 'http://t', deviceId: 'd', httpClient: mock);
    await client.updateProgress(
      comicId: 'c',
      currentPage: 5,
      totalPages: 100,
      chapters: [Chapter.create(comicId: 'c', pageNum: 3, title: 'X')],
    );
    expect(sent!.containsKey('chapters'), isTrue);
    expect((sent!['chapters'] as List).length, 1);
  });
}
