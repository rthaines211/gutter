import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'download_manager.dart' show isDownloadComplete;

enum LocalImportError { notAZip, noImages, alreadyImported, tooLarge }

/// ponytail: one fixed ceiling on what a zip may unpack to (a zip bomb
/// would fill the disk); compare with free space if 4 GB is ever too low.
const maxUnpackedBytes = 4 * 1024 * 1024 * 1024;

class LocalImportException implements Exception {
  final LocalImportError error;

  /// The file's name, for the message the person sees.
  final String fileName;
  const LocalImportException(this.error, this.fileName);

  @override
  String toString() => 'LocalImportException(${error.name}, $fileName)';
}

typedef ImportedComic = ({
  String comicId,
  String seriesId,
  String seriesName,
  String comicName,
  String? number,
  int pageCount,
});

/// Series name and issue number from a comic's file name: bracketed groups
/// and underscores go, and a trailing number (`#3`, `003`, `v2`, `Vol. 2`)
/// is the issue. "Saga (2012) 003 (digital).cbz" → Saga, 3.
({String series, String? number}) parseComicFileName(String fileName) {
  final name = p
      .basenameWithoutExtension(fileName)
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final m = RegExp(
          r'^(.*?\S)\s*(?:#|\s(?:v|vol\.?|volume)\s*|\s)(\d{1,4}(?:\.\d+)?)$',
          caseSensitive: false)
      .firstMatch(name);
  if (m == null) {
    return (
      series: name.isEmpty ? p.basenameWithoutExtension(fileName) : name,
      number: null
    );
  }
  final series = m[1]!.replaceAll(RegExp(r'[\s\-,]+$'), '');
  if (series.isEmpty) return (series: name, number: null);
  return (series: series, number: m[2]!.replaceFirst(RegExp(r'^0+(?=\d)'), ''));
}

/// Text order with runs of digits compared as numbers ("page2" < "page10"),
/// ignoring case.
int compareNatural(String a, String b) {
  final chunk = RegExp(r'\d+|\D+');
  final x = chunk.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final y = chunk.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final nx = BigInt.tryParse(x[i]), ny = BigInt.tryParse(y[i]);
    final c = nx != null && ny != null ? nx.compareTo(ny) : x[i].compareTo(y[i]);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

/// A stable id from a name. ponytail: 64-bit FNV-1a, so two names can
/// collide in theory; use a real digest if that ever shows.
String localId(String prefix, String name) {
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode(name.toLowerCase())) {
    h = (h ^ b) * 0x100000001b3;
  }
  String hex(int v) => v.toRadixString(16).padLeft(8, '0');
  return '$prefix${hex(h >>> 32)}${hex(h & 0xffffffff)}';
}

const _imageExts = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};

/// Whether a zip entry is a comic page. The name is untrusted: an absolute
/// path or a `..` segment is refused, as are `__MACOSX`, dotfiles and
/// anything that isn't an image. (Pages are written as `<n>.<ext>`, never
/// under the entry's own name.)
bool isPageEntry(String entryName) {
  final name = entryName.replaceAll('\\', '/');
  if (name.startsWith('/')) return false;
  final parts = name.split('/');
  if (parts.any((s) => s == '..' || s == '__MACOSX' || s.startsWith('.'))) {
    return false;
  }
  return _imageExts.contains(p.extension(parts.last).toLowerCase());
}

/// Unpacks the CBZ at [cbzPath] into the downloads layout
/// (`<docsDir>/downloads/<sourceId>/<comicId>/pages/<n>.<ext>`, then
/// `metadata.json` last), so the reader opens it like any downloaded comic.
/// The first page becomes the series cover if the series has none. Runs in
/// an isolate; throws [LocalImportException]. Free: never goes through
/// DownloadManager.enqueue or the Pro gate.
Future<ImportedComic> importCbz({
  required String cbzPath,
  required String docsDir,
  required String sourceId,
}) =>
    Isolate.run(() => importCbzSync(cbzPath, docsDir, sourceId));

ImportedComic importCbzSync(String cbzPath, String docsDir, String sourceId,
    {int maxBytes = maxUnpackedBytes}) {
  final fileName = p.basename(cbzPath);
  Never fail(LocalImportError e) => throw LocalImportException(e, fileName);

  final parsed = parseComicFileName(fileName);
  final comicName = p.basenameWithoutExtension(fileName);
  // ponytail: the id is the file name, so a different file with the same
  // name counts as already imported.
  final comicId = localId('c', comicName);
  final seriesId = localId('s', parsed.series);
  final comicDir = p.join(docsDir, 'downloads', sourceId, comicId);
  if (isDownloadComplete(comicDir)) fail(LocalImportError.alreadyImported);

  final head = File(cbzPath).openSync();
  final List<int> magic;
  try {
    magic = head.readSync(2);
  } finally {
    head.closeSync();
  }
  if (magic.length < 2 || magic[0] != 0x50 || magic[1] != 0x4b) {
    fail(LocalImportError.notAZip);
  }

  final dir = Directory(comicDir);
  // A leftover from an import that was killed partway.
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  final input = InputFileStream(cbzPath);
  try {
    final List<ArchiveFile> pages;
    try {
      pages = ZipDecoder()
          .decodeStream(input)
          .files
          .where((f) => f.isFile && !f.isSymbolicLink && isPageEntry(f.name))
          .toList()
        ..sort((a, b) => compareNatural(a.name, b.name));
    } catch (_) {
      fail(LocalImportError.notAZip);
    }
    if (pages.isEmpty) fail(LocalImportError.noImages);
    // The declared sizes, checked before anything is written.
    if (pages.fold<int>(0, (n, f) => n + f.size) > maxBytes) {
      fail(LocalImportError.tooLarge);
    }

    final pagesDir = p.join(comicDir, 'pages');
    Directory(pagesDir).createSync(recursive: true);
    var size = 0;
    for (var i = 0; i < pages.length; i++) {
      final ext = p.extension(pages[i].name).toLowerCase();
      final dest = p.join(pagesDir, '${i + 1}$ext');
      final out = OutputFileStream(dest);
      try {
        pages[i].writeContent(out);
      } on FileSystemException {
        rethrow; // disk full: not the zip's fault
      } catch (_) {
        fail(LocalImportError.notAZip);
      } finally {
        out.closeSync();
      }
      size += File(dest).lengthSync();
      // A size the zip lied about.
      if (size > maxBytes) fail(LocalImportError.tooLarge);
    }

    // ponytail: the first issue imported gives the series its cover, not
    // the lowest-numbered one.
    final cover = File(p.join(docsDir, 'covers', sourceId, '$seriesId.jpg'));
    if (!cover.existsSync()) {
      cover.parent.createSync(recursive: true);
      final first = p.extension(pages.first.name).toLowerCase();
      File(p.join(pagesDir, '1$first')).copySync(cover.path);
    }

    // metadata.json marks the comic complete, so it goes last, atomically.
    final tmp = File(p.join(comicDir, 'metadata.json.tmp'));
    tmp.writeAsStringSync(
        jsonEncode({
          'comic_id': comicId,
          'source_id': sourceId,
          'series_id': seriesId,
          'series_name': parsed.series,
          'comic_name': comicName,
          'number': parsed.number,
          'page_count': pages.length,
          'downloaded_at': DateTime.now().toUtc().toIso8601String(),
          'size_bytes': size,
        }),
        flush: true);
    tmp.renameSync(p.join(comicDir, 'metadata.json'));
    return (
      comicId: comicId,
      seriesId: seriesId,
      seriesName: parsed.series,
      comicName: comicName,
      number: parsed.number,
      pageCount: pages.length,
    );
  } catch (_) {
    // Any failure (a bad zip, a full disk): leave no partial comic behind.
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
    rethrow;
  } finally {
    input.closeSync();
  }
}
