import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/cache_layer.dart';

void main() {
  late Directory tempDir;
  late CacheLayer cache;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cache_test_');
    cache = CacheLayer(cacheDir: tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('write and read round-trips JSON data', () async {
    final data = [{'id': '1', 'name': 'Batman'}];
    await cache.write('library', data);
    final result = await cache.read('library');
    expect(result, isNotNull);
    expect(result!['data'], equals(data));
    expect(result.containsKey('cached_at'), isTrue);
  });

  test('read returns null for missing key', () async {
    final result = await cache.read('nonexistent');
    expect(result, isNull);
  });

  test('write creates nested directories for slashed keys', () async {
    await cache.write('series/batman-2024', {'id': 'batman-2024'});
    final result = await cache.read('series/batman-2024');
    expect(result, isNotNull);
    expect(result!['data']['id'], 'batman-2024');
  });

  test('write overwrites previous value', () async {
    await cache.write('library', [{'v': 1}]);
    await cache.write('library', [{'v': 2}]);
    final result = await cache.read('library');
    expect(result!['data'], equals([{'v': 2}]));
  });

  test('clear removes all cached files', () async {
    await cache.write('library', []);
    await cache.write('series/abc', {});
    await cache.clear();
    expect(await cache.read('library'), isNull);
    expect(await cache.read('series/abc'), isNull);
  });

  test('rejects keys with path traversal', () async {
    expect(() => cache.write('../../etc/passwd', {'bad': true}), throwsArgumentError);
  });

  test('rejects keys with parent directory references', () async {
    expect(() => cache.write('series/../../../secret', {'bad': true}), throwsArgumentError);
  });

  test('allows forward slashes for nested keys', () async {
    await cache.write('series/batman-2024', {'id': 'ok'});
    final result = await cache.read('series/batman-2024');
    expect(result, isNotNull);
  });
}
