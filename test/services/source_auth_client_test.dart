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
}
