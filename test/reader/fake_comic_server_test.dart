import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'fake_comic_server.dart';

void main() {
  late FakeComicServer server;

  setUp(() async {
    server = FakeComicServer()
      ..comics['c1'] = [portraitPage, landscapeSpread];
    await server.start();
  });

  tearDown(() => server.stop());

  test('serves pages with declared dimensions and records requests', () async {
    final resp = await http.get(Uri.parse('${server.url}/comics/c1/pages/1'));
    expect(resp.statusCode, 200);
    final decoded = img.decodePng(resp.bodyBytes)!;
    expect(decoded.width, 2400);
    expect(decoded.height, 1500);
    expect(server.requests.single.path, '/comics/c1/pages/1');
  });

  test('serves info with page_count', () async {
    final resp = await http.get(Uri.parse('${server.url}/comics/c1/info'));
    expect(resp.body, contains('"page_count":2'));
  });

  test('settings endpoint returns configured map', () async {
    server.settings = {'page_fit': 'fitWidth'};
    final resp = await http.get(Uri.parse('${server.url}/settings'));
    expect(resp.body, contains('fitWidth'));
  });

  test('PUT /reading records body; failProgressWrites returns 500', () async {
    final ok = await http.put(Uri.parse('${server.url}/reading/c1'),
        body: '{"current_page":3,"total_pages":10}');
    expect(ok.statusCode, 200);
    expect(server.requests.last.jsonBody!['current_page'], 3);

    server.failProgressWrites = true;
    final fail = await http.put(Uri.parse('${server.url}/reading/c1'),
        body: '{"current_page":4,"total_pages":10}');
    expect(fail.statusCode, 500);
  });

  test('unknown paths 404', () async {
    final resp = await http.get(Uri.parse('${server.url}/nope'));
    expect(resp.statusCode, 404);
  });
}
