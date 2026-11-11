import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:comic_reader_app/services/download_manager.dart';
import 'package:comic_reader_app/services/local_import.dart';

/// Writes a zip named [name] with [entries] (entry name → bytes).
String writeZip(Directory dir, String name, Map<String, List<int>> entries) {
  final archive = Archive();
  entries.forEach((n, bytes) => archive.addFile(ArchiveFile.bytes(n, bytes)));
  final path = p.join(dir.path, name);
  File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
  return path;
}

void main() {
  late Directory tmp;
  late String docs;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('local_import');
    docs = p.join(tmp.path, 'docs');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('parseComicFileName', () {
    final cases = {
      'Saga 003.cbz': ('Saga', '3'),
      'Saga (2012) 003 (digital) [group].cbz': ('Saga', '3'),
      'Saga #12.cbz': ('Saga', '12'),
      'Saga_v2.cbz': ('Saga', '2'),
      'Saga Vol. 10.cbz': ('Saga', '10'),
      'X-Men - 001.cbz': ('X-Men', '1'),
      '100 Bullets 000.cbz': ('100 Bullets', '0'),
      'Akira 1.5.cbz': ('Akira', '1.5'),
      '2000 AD.cbz': ('2000 AD', null),
      'Watchmen.cbz': ('Watchmen', null),
      '001.cbz': ('001', null),
    };
    cases.forEach((file, want) {
      test(file, () {
        final got = parseComicFileName(file);
        expect((got.series, got.number), want);
      });
    });
  });

  test('compareNatural orders digit runs as numbers', () {
    final names = ['p10.jpg', 'P2.jpg', 'p1.jpg', 'a/p3.jpg']..sort(compareNatural);
    expect(names, ['a/p3.jpg', 'p1.jpg', 'P2.jpg', 'p10.jpg']);
  });

  test('localId is stable, case-blind and safe as a directory name', () {
    expect(localId('c', 'Saga 003'), localId('c', 'saga 003'));
    expect(localId('c', 'Saga 003'), isNot(localId('c', 'Saga 004')));
    expect(localId('c', '日本語/..'), matches(RegExp(r'^c[0-9a-f]{16}$')));
  });

  test('imports pages in natural order into the downloads layout', () async {
    final zip = writeZip(tmp, 'Saga 003.cbz', {
      'Saga/page10.jpg': [10],
      'Saga/page2.png': [2, 2],
      'Saga/page1.JPG': [1],
      '__MACOSX/Saga/._page1.jpg': [9],
      'Saga/.hidden.jpg': [9],
      'Saga/notes.txt': [9],
      'ComicInfo.xml': [9],
    });
    final got = await importCbz(cbzPath: zip, docsDir: docs, sourceId: 'local');

    expect(got.seriesName, 'Saga');
    expect(got.number, '3');
    expect(got.pageCount, 3);
    final dir = p.join(docs, 'downloads', 'local', got.comicId);
    expect(isDownloadComplete(dir), true);
    final pages = Directory(p.join(dir, 'pages')).listSync().map((f) => p.basename(f.path)).toSet();
    expect(pages, {'1.jpg', '2.png', '3.jpg'});
    expect(File(p.join(dir, 'pages', '1.jpg')).readAsBytesSync(), [1]);
    expect(File(p.join(dir, 'pages', '2.png')).readAsBytesSync(), [2, 2]);
    expect(File(p.join(dir, 'pages', '3.jpg')).readAsBytesSync(), [10]);

    final meta = jsonDecode(File(p.join(dir, 'metadata.json')).readAsStringSync());
    expect(meta['series_id'], got.seriesId);
    expect(meta['series_name'], 'Saga');
    expect(meta['comic_name'], 'Saga 003');
    expect(meta['page_count'], 3);
    expect(meta['size_bytes'], 4);
    // The first page is the series cover, where the Library tile looks.
    expect(File(p.join(docs, 'covers', 'local', '${got.seriesId}.jpg')).readAsBytesSync(), [1]);
  });

  test('a second issue keeps the series cover', () async {
    final a = await importCbz(
        cbzPath: writeZip(tmp, 'Saga 001.cbz', {'1.jpg': [1]}), docsDir: docs, sourceId: 'local');
    final b = await importCbz(
        cbzPath: writeZip(tmp, 'Saga 002.cbz', {'1.jpg': [2]}), docsDir: docs, sourceId: 'local');
    expect(b.seriesId, a.seriesId);
    expect(b.comicId, isNot(a.comicId));
    expect(File(p.join(docs, 'covers', 'local', '${a.seriesId}.jpg')).readAsBytesSync(), [1]);
  });

  Future<LocalImportError> errorOf(String zip) async {
    try {
      await importCbz(cbzPath: zip, docsDir: docs, sourceId: 'local');
    } on LocalImportException catch (e) {
      expect(e.fileName, p.basename(zip));
      return e.error;
    }
    fail('import of $zip did not throw');
  }

  /// Every file under the temp dir except the source zips.
  List<String> written() => tmp
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => p.relative(f.path, from: tmp.path))
      .where((f) => !f.endsWith('.cbz'))
      .toList();

  test('entries that would leave the comic directory are refused', () async {
    final zip = writeZip(tmp, 'Evil 001.cbz', {
      '../../../evil.jpg': [6],
      '/abs/evil.jpg': [6],
      'a/../../evil2.jpg': [6],
      r'..\evil3.jpg': [6],
      'ok.jpg': [1],
    });
    final got = await importCbz(cbzPath: zip, docsDir: docs, sourceId: 'local');
    expect(got.pageCount, 1);
    final dir = p.join('docs', 'downloads', 'local', got.comicId);
    expect(written()..sort(), [
      p.join('docs', 'covers', 'local', '${got.seriesId}.jpg'),
      p.join(dir, 'metadata.json'),
      p.join(dir, 'pages', '1.jpg'),
    ]);
  });

  test('a zip with only traversal entries has no images', () async {
    final zip = writeZip(tmp, 'Evil 002.cbz', {'../evil.jpg': [6]});
    expect(await errorOf(zip), LocalImportError.noImages);
    expect(written(), isEmpty);
  });

  test('a zip with no images fails and leaves nothing behind', () async {
    final zip = writeZip(tmp, 'Notes.cbz', {'readme.txt': [1], 'ComicInfo.xml': [2]});
    expect(await errorOf(zip), LocalImportError.noImages);
    expect(written(), isEmpty);
  });

  test('a file that is not a zip fails', () async {
    final rar = p.join(tmp.path, 'Old 001.cbz');
    File(rar).writeAsBytesSync(utf8.encode('Rar!\x1a\x07\x00 not a zip at all'));
    expect(await errorOf(rar), LocalImportError.notAZip);
    final empty = p.join(tmp.path, 'Empty.cbz');
    File(empty).writeAsBytesSync([]);
    expect(await errorOf(empty), LocalImportError.notAZip);
    // Starts like a zip, then garbage.
    final cut = p.join(tmp.path, 'Cut 001.cbz');
    File(cut).writeAsBytesSync([0x50, 0x4b, 0x03, 0x04, 1, 2, 3, 4, 5, 6]);
    expect(await errorOf(cut), anyOf(LocalImportError.notAZip, LocalImportError.noImages));
    expect(written(), isEmpty);
  });

  test('the same file name twice is already imported', () async {
    final zip = writeZip(tmp, 'Saga 003.cbz', {'1.jpg': [1]});
    await importCbz(cbzPath: zip, docsDir: docs, sourceId: 'local');
    expect(await errorOf(zip), LocalImportError.alreadyImported);
    // The first import is untouched.
    final dir = p.join(docs, 'downloads', 'local', localId('c', 'Saga 003'));
    expect(isDownloadComplete(dir), true);
  });

  test('a half-finished import is replaced', () async {
    final dir = p.join(docs, 'downloads', 'local', localId('c', 'Saga 003'));
    File(p.join(dir, 'pages', '7.jpg'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([7]);
    final zip = writeZip(tmp, 'Saga 003.cbz', {'1.jpg': [1]});
    final got = await importCbz(cbzPath: zip, docsDir: docs, sourceId: 'local');
    expect(got.pageCount, 1);
    expect(File(p.join(dir, 'pages', '7.jpg')).existsSync(), false);
  });

  test('a zip that unpacks to more than the ceiling is too large', () {
    final zip = writeZip(tmp, 'Big 001.cbz', {'1.jpg': [1, 1], '2.jpg': [2, 2]});
    expect(
        () => importCbzSync(zip, docs, 'local', maxBytes: 3),
        throwsA(isA<LocalImportException>()
            .having((e) => e.error, 'error', LocalImportError.tooLarge)));
    expect(written(), isEmpty);
    // At the ceiling is fine.
    expect(importCbzSync(zip, docs, 'local', maxBytes: 4).pageCount, 2);
    expect(maxUnpackedBytes, 4 * 1024 * 1024 * 1024);
  });

  test('any failure, not only a bad zip, leaves no partial comic', () {
    // The covers directory can't be made: a plain file is in the way.
    File(p.join(docs, 'covers'))
      ..createSync(recursive: true)
      ..writeAsStringSync('in the way');
    final zip = writeZip(tmp, 'Saga 001.cbz', {'1.jpg': [1]});
    expect(() => importCbzSync(zip, docs, 'local'),
        throwsA(isA<FileSystemException>()));
    expect(Directory(p.join(docs, 'downloads', 'local', localId('c', 'Saga 001')))
        .existsSync(), false);
  });
}
