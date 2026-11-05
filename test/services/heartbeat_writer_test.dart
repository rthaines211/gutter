import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/heartbeat_writer.dart';

Directory _tempDir() => Directory.systemTemp.createTempSync('hb_test_');

({String route, String? comicId, int? page, int? totalPages, String? lastAction, int cacheCount, int cacheBytes}) _snap = (
  route: '/library',
  comicId: null,
  page: null,
  totalPages: null,
  lastAction: 'route',
  cacheCount: 12,
  cacheBytes: 1024,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tickForTest writes heartbeat with current snapshot', () async {
    final dir = _tempDir();
    final w = HeartbeatWriter(
      heartbeatFile: File('${dir.path}/heartbeat.json'),
      snapshot: () => _snap,
    );

    await w.tickForTest();

    final raw = await File('${dir.path}/heartbeat.json').readAsString();
    final json = jsonDecode(raw) as Map<String, Object?>;
    expect(json['state'], 'resumed');
    expect(json['route'], '/library');
    expect(json['imageCache'], {'count': 12, 'bytes': 1024});
    expect(json['ts'], isA<String>());
    expect(File('${dir.path}/heartbeat.json.tmp').existsSync(), isFalse);
    dir.deleteSync(recursive: true);
  });

  test('tickForTest omits null comic fields', () async {
    final dir = _tempDir();
    final w = HeartbeatWriter(
      heartbeatFile: File('${dir.path}/heartbeat.json'),
      snapshot: () => _snap,
    );

    await w.tickForTest();
    final json = jsonDecode(
            await File('${dir.path}/heartbeat.json').readAsString())
        as Map<String, Object?>;
    expect(json.containsKey('comicId'), isFalse);
    expect(json.containsKey('page'), isFalse);
    dir.deleteSync(recursive: true);
  });

  test('overrideStateForTest forces non-resumed state', () async {
    final dir = _tempDir();
    final w = HeartbeatWriter(
      heartbeatFile: File('${dir.path}/heartbeat.json'),
      snapshot: () => _snap,
    );

    w.overrideStateForTest('paused');
    await w.tickForTest();

    final json = jsonDecode(
            await File('${dir.path}/heartbeat.json').readAsString())
        as Map<String, Object?>;
    expect(json['state'], 'paused');
    dir.deleteSync(recursive: true);
  });

  test('write failure does not throw', () async {
    final w = HeartbeatWriter(
      heartbeatFile: File('/nonexistent_dir/heartbeat.json'),
      snapshot: () => _snap,
    );
    await w.tickForTest(); // should not throw
  });
}
