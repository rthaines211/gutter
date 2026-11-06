import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:comic_reader_app/services/source_files.dart';

void main() {
  late Directory docs;
  setUp(() async => docs = await Directory.systemTemp.createTemp('srcfiles_'));
  tearDown(() => docs.delete(recursive: true));

  List<String> pathsFor(String id) => [
        p.join(docs.path, 'mirror_$id.sqlite'),
        p.join(docs.path, 'mirror_$id.sqlite-wal'),
        p.join(docs.path, 'mirror_$id.sqlite-shm'),
        p.join(docs.path, 'covers', id, 's1.jpg'),
        p.join(docs.path, 'cache', id, 'sync_queue.json'),
      ];

  test('deleteSourceFiles removes only that source', () async {
    for (final f in [...pathsFor('a'), ...pathsFor('b')]) {
      File(f)
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
    }
    await deleteSourceFiles(docs.path, 'a');
    for (final f in pathsFor('a')) {
      expect(File(f).existsSync(), isFalse, reason: f);
    }
    expect(Directory(p.join(docs.path, 'covers', 'a')).existsSync(), isFalse);
    expect(Directory(p.join(docs.path, 'cache', 'a')).existsSync(), isFalse);
    for (final f in pathsFor('b')) {
      expect(File(f).existsSync(), isTrue, reason: f);
    }
  });

  test('deleteSourceFiles tolerates missing paths', () async {
    await deleteSourceFiles(docs.path, 'nothing');
  });
}
