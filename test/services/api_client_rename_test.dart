import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/api_client.dart';

void main() {
  group('ApiClient.renameComic validation', () {
    late ApiClient client;

    setUp(() {
      client = ApiClient(baseUrl: 'http://localhost:8080', deviceId: 'test');
    });

    test('rejects names with path separators', () {
      expect(() => client.renameComic('abc', '../etc/passwd'), throwsArgumentError);
      expect(() => client.renameComic('abc', 'foo/bar'), throwsArgumentError);
      expect(() => client.renameComic('abc', 'foo\\bar'), throwsArgumentError);
    });

    test('rejects names with null bytes', () {
      expect(() => client.renameComic('abc', 'foo\x00bar'), throwsArgumentError);
    });

    test('rejects empty names', () {
      expect(() => client.renameComic('abc', ''), throwsArgumentError);
    });
  });
}
