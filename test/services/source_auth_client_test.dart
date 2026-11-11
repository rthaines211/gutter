import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:comic_reader_app/services/source_auth_client.dart';

void main() {
  late Map<String, String> seen;
  final client = SourceAuthClient(MockClient((req) async {
    seen = req.headers;
    return http.Response('', 200);
  }));

  tearDown(() => SourceAuthClient.use('', const {}));

  test('adds the source credentials to its own URLs', () async {
    SourceAuthClient.use('http://k:25600/komga', const {'X-API-Key': 'key'});
    await client.get(Uri.parse('http://k:25600/komga/api/v1/books/b/thumbnail'));
    expect(seen['X-API-Key'], 'key');
  });

  test('never sends them to another host, port or path', () async {
    SourceAuthClient.use('http://k:25600/komga', const {'X-API-Key': 'key'});
    for (final url in [
      'http://k.evil:25600/komga/x',
      'http://k:9999/komga/x',
      'https://k:25600/komga/x',
      'http://k:25600/komgax/y',
      'https://images.example.com/cover.jpg',
    ]) {
      await client.get(Uri.parse(url));
      expect(seen.containsKey('X-API-Key'), isFalse, reason: url);
    }
  });

  test('a local source\'s cover and page URLs are its imported page files',
      () async {
    final dir = Directory.systemTemp.createTempSync('auth_local');
    addTearDown(() => dir.deleteSync(recursive: true));
    final pages = Directory('${dir.path}/c1/pages')..createSync(recursive: true);
    File('${pages.path}/1.png').writeAsBytesSync([1]);
    File('${pages.path}/2.jpg').writeAsBytesSync([2, 2]);
    File('${dir.path}/secret.jpg').writeAsBytesSync([9]);
    var network = 0;
    final local = SourceAuthClient(MockClient((_) async {
      network++;
      return http.Response('', 200);
    }));
    SourceAuthClient.use('local:', const {}, localDir: dir.path);

    final cover = await local.get(Uri.parse('local:/comics/c1/cover'));
    expect((cover.statusCode, cover.headers['content-type']), (200, 'image/png'));
    expect(cover.bodyBytes, [1]);
    final page = await local.get(Uri.parse('local:/comics/c1/pages/1'));
    expect(page.headers['content-type'], 'image/jpeg');
    expect(page.bodyBytes, [2, 2]);
    for (final url in [
      'local:/comics/nope/cover',
      'local:/comics/c1/pages/7',
      'local:/comics/..%2F..%2Fsecret/cover',
      'local:/comics/../cover',
      'local:/library/s1/cover',
    ]) {
      expect((await local.get(Uri.parse(url))).statusCode, 404, reason: url);
    }
    expect(network, 0);
    // No local source active: still no network, nothing served.
    SourceAuthClient.use('http://k', const {});
    expect((await local.get(Uri.parse('local:/comics/c1/cover'))).statusCode, 404);
    expect(network, 0);
  });
}
