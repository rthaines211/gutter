import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class CacheLayer {
  final String cacheDir;

  CacheLayer({required this.cacheDir});

  void _validateKey(String key) {
    if (key.contains('..')) {
      throw ArgumentError('Cache key must not contain "..": $key');
    }
    final resolved = File(p.join(cacheDir, '$key.json')).path;
    final normalizedCache = p.normalize(cacheDir);
    final normalizedResolved = p.normalize(resolved);
    if (!normalizedResolved.startsWith(normalizedCache)) {
      throw ArgumentError('Cache key resolves outside cache directory: $key');
    }
  }

  Future<void> write(String key, dynamic jsonData) async {
    _validateKey(key);
    final file = File(p.join(cacheDir, '$key.json'));
    await file.parent.create(recursive: true);
    final envelope = {
      'cached_at': DateTime.now().toIso8601String(),
      'data': jsonData,
    };
    await file.writeAsString(jsonEncode(envelope));
  }

  Future<Map<String, dynamic>?> read(String key) async {
    _validateKey(key);
    final file = File(p.join(cacheDir, '$key.json'));
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  Future<void> clear() async {
    final dir = Directory(cacheDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
