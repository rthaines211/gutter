import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../models/download_item.dart';
import 'local_pages.dart';
import 'page_fetcher.dart';

/// A download is complete iff its metadata.json exists. It's written last,
/// atomically, after pages/ — so a kill or failure partway
/// through never leaves a comic that looks downloaded but has missing pages.
bool isDownloadComplete(String comicDir) =>
    File(p.join(comicDir, 'metadata.json')).existsSync();

class DownloadManager {
  final PageFetcher _fetcher;
  final http.Client _httpClient;
  final String _baseDir;
  final List<DownloadItem> _queue = [];
  final List<DownloadItem> _completed = [];
  bool _processing = false;

  final _stateController = StreamController<DownloadManagerState>.broadcast();
  Stream<DownloadManagerState> get stateStream => _stateController.stream;

  // URL, headers and fetch task id per queued item (keyed by sourceId:comicId)
  final Map<String, _DownloadMeta> _downloadMeta = {};

  // In-flight hand-offs to the fetcher (page count lookup + start), awaited
  // by the work loop so a failed lookup fails the item.
  final Map<String, Future<void>> _starts = {};

  static const _journalName = 'queue.json';

  String get _downloadsRoot => p.join(_baseDir, 'downloads');
  String get _journalPath => p.join(_downloadsRoot, _journalName);

  /// Auth headers for a source, merged in at fetch time. Never stored in
  /// [_DownloadMeta] or the journal, so credentials stay out of queue.json.
  final Map<String, String> Function(String sourceId)? authFor;

  /// Called after [delete] removed a comic of [sourceId] from disk;
  /// [seriesId] is the series it was listed under ('' if it wasn't listed).
  final void Function(String sourceId, String seriesId)? onDeleted;

  /// Each comic is downloaded page by page from the server's page endpoint,
  /// so page N on disk is the server's page N. Every queued comic's pages are
  /// handed to [fetcher] up front (a background fetcher keeps them all going
  /// while the app is suspended); the work loop waits for each comic in order
  /// and marks it complete. Defaults to plain HTTP.
  DownloadManager({
    required String baseDir,
    http.Client? httpClient,
    PageFetcher? fetcher,
    this.authFor,
    this.onDeleted,
  })  : _baseDir = baseDir,
        _httpClient = httpClient ?? http.Client(),
        _fetcher = fetcher ?? HttpFetcher(httpClient ?? http.Client());

  /// Restore pending downloads from the journal and resume processing.
  /// Call once after construction. Safe to call when no journal exists.
  Future<void> init() async {
    await _restoreJournal();
    await _scanDisk();
    // Not fresh: pages may have finished in the background.
    for (final item in _queue) {
      _startFetch(item, fresh: false);
    }
    _emit();
    _processNext();
  }

  /// Load finished downloads into [_completed] (so the Downloads screen and
  /// issue rows know them after a relaunch), and delete incomplete dirs with
  /// no pending queue entry.
  Future<void> _scanDisk() async {
    final downloadsDir = Directory(_downloadsRoot);
    if (!downloadsDir.existsSync()) return;
    await for (final sourceDir in downloadsDir.list()) {
      if (sourceDir is! Directory) continue;
      final sourceId = p.basename(sourceDir.path);
      await for (final comicDir in sourceDir.list()) {
        if (comicDir is! Directory) continue;
        try {
          final comicId = p.basename(comicDir.path);
          final hasPages = _isDownloadedOnDisk(comicId, sourceId);
          final inQueue = _queue.any(
              (i) => i.comicId == comicId && i.sourceId == sourceId);
          if (!hasPages && !inQueue) {
            await comicDir.delete(recursive: true);
            continue;
          }
          if (hasPages && !_isKnown(comicId, sourceId)) {
            _completed.add(await _completedFromDisk(comicDir, comicId, sourceId));
          }
        } catch (_) {
          // Skip — a missed orphan is retried on the next launch.
        }
      }
    }
  }

  Future<DownloadItem> _completedFromDisk(
      Directory comicDir, String comicId, String sourceId) async {
    Map<String, dynamic> meta = const {};
    try {
      meta = jsonDecode(await File(p.join(comicDir.path, 'metadata.json'))
          .readAsString()) as Map<String, dynamic>;
    } catch (_) {}
    // Downloads from before size_bytes was recorded: sum the pages.
    var size = meta['size_bytes'] as int? ?? 0;
    if (size == 0) {
      await for (final f in Directory(p.join(comicDir.path, 'pages')).list()) {
        if (f is File) size += await f.length();
      }
    }
    return DownloadItem(
      comicId: comicId,
      sourceId: sourceId,
      seriesId: meta['series_id'] as String? ?? '',
      seriesName: meta['series_name'] as String? ?? '',
      comicName: meta['comic_name'] as String? ?? comicId,
      totalBytes: size,
      downloadedBytes: size,
      status: DownloadStatus.completed,
      addedAt: DateTime.tryParse(meta['downloaded_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Future<void> _restoreJournal() async {
    final file = File(_journalPath);
    if (!file.existsSync()) return;
    try {
      final entries = jsonDecode(file.readAsStringSync()) as List;
      for (final raw in entries) {
        final map = raw as Map<String, dynamic>;
        final item =
            DownloadItem.fromJson(map['item'] as Map<String, dynamic>);
        var url = map['url'] as String?;
        if (url == null) continue;
        // Journals from the archive design stored the /download URL.
        if (url.endsWith('/download')) url = url.substring(0, url.length - 9);
        if (_isDownloadedOnDisk(item.comicId, item.sourceId)) continue;
        if (_isKnown(item.comicId, item.sourceId)) continue;
        _downloadMeta[_metaKey(item.comicId, item.sourceId)] = _DownloadMeta(
          url: url,
          headers: Map<String, String>.from(map['headers'] as Map? ?? {}),
          taskId: map['task_id'] as String? ?? _newTaskId(item.comicId, item.sourceId),
          pageCount: map['page_count'] as int?,
        );
        _queue.add(item.copyWith(
          status: DownloadStatus.queued,
          downloadedBytes: 0,
          totalBytes: 0,
        ));
      }
    } catch (_) {
      // Corrupt journal: restore what parsed, drop the rest. The launch sweep
      // removes any partials the lost entries left behind.
    }
  }

  /// Synchronous + atomic (tmp file, then rename) so concurrent mutation
  /// sites can't interleave partial writes.
  void _persistJournal() {
    final dir = Directory(_downloadsRoot);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final entries = _queue.map((i) {
      final meta = _downloadMeta[_metaKey(i.comicId, i.sourceId)];
      return {
        'item': i.toJson(),
        'url': meta?.url,
        'headers': meta?.headers,
        'task_id': meta?.taskId,
        'page_count': meta?.pageCount,
      };
    }).toList();
    final tmp = File('$_journalPath.tmp');
    tmp.writeAsStringSync(jsonEncode(entries));
    tmp.renameSync(_journalPath);
  }

  bool _isDownloadedOnDisk(String comicId, String sourceId) =>
      isDownloadComplete(p.join(_downloadsRoot, sourceId, comicId));

  DownloadManagerState get currentState => DownloadManagerState(
        queue: List.unmodifiable(_queue),
        completed: List.unmodifiable(_completed),
      );

  /// Enqueue a download. Skipped if the comic is already queued or completed.
  /// A previously-failed entry is dropped from completed so the user can retry.
  /// [comicUrl] is the comic's API base, `<server>/comics/<id>`.
  void enqueue({
    required String comicId,
    required String sourceId,
    required String seriesId,
    required String seriesName,
    required String comicName,
    required String comicUrl,
    required Map<String, String> headers,
  }) {
    _completed.removeWhere((i) =>
        i.comicId == comicId &&
        i.sourceId == sourceId &&
        i.status == DownloadStatus.failed);
    if (_isKnown(comicId, sourceId)) return;
    if (_isDownloadedOnDisk(comicId, sourceId)) return;

    _downloadMeta[_metaKey(comicId, sourceId)] = _DownloadMeta(
      url: comicUrl,
      headers: headers,
      taskId: _newTaskId(comicId, sourceId),
    );

    final item = DownloadItem(
      comicId: comicId,
      sourceId: sourceId,
      seriesId: seriesId,
      seriesName: seriesName,
      comicName: comicName,
      totalBytes: 0,
      downloadedBytes: 0,
      status: DownloadStatus.queued,
      addedAt: DateTime.now(),
    );
    _queue.add(item);
    _persistJournal();
    _startFetch(item);
    _emit();
    _processNext();
  }

  String _comicDir(DownloadItem item) =>
      p.join(_downloadsRoot, item.sourceId, item.comicId);

  String _newTaskId(String comicId, String sourceId) =>
      '${sourceId}_${comicId}_${DateTime.now().microsecondsSinceEpoch}';

  /// Hand the comic's pages to the fetcher. [fresh] wipes leftovers from an
  /// earlier attempt; a restored item keeps its dir (pages may be done).
  void _startFetch(DownloadItem item, {bool fresh = true}) {
    final key = _metaKey(item.comicId, item.sourceId);
    if (!_downloadMeta.containsKey(key)) return;
    final dir = Directory(_comicDir(item));
    if (fresh && dir.existsSync()) dir.deleteSync(recursive: true);
    Directory(p.join(dir.path, 'pages')).createSync(recursive: true);
    _starts[key] = _handOff(key, item.sourceId, dir.path)..ignore();
  }

  Future<void> _handOff(String key, String sourceId, String comicDir) async {
    var meta = _downloadMeta[key]!;
    final auth = authFor?.call(sourceId) ?? const <String, String>{};
    final headers = {...meta.headers, ...auth};
    // Komga (`<server>/api/v1/books/<id>`): the book itself has the page
    // count, and its pages are 1-based.
    final komga = meta.url.contains('/api/v1/books/');
    // Kavita (`<server>/api/Chapter?chapterId=<id>`): the chapter has the
    // page count; pages are 0-based and need the key as a query parameter.
    final kavita = meta.url.contains('/api/Chapter?chapterId=');
    // OPDS (`<page template>#<count>`, SourceUrls.comicDownload): the count
    // is in the URL; pages are 0-based into the PSE template.
    final opds = meta.url.contains('{pageNumber}');
    if (opds && meta.pageCount == null) {
      final count = int.tryParse(meta.url.substring(meta.url.lastIndexOf('#') + 1)) ?? 0;
      if (count == 0) throw Exception('No pages in comic');
      meta = _downloadMeta[key] = meta.withPageCount(count);
      _persistJournal();
    }
    if (meta.pageCount == null) {
      final res = await _httpClient
          .get(Uri.parse(komga || kavita ? meta.url : '${meta.url}/info'),
              headers: headers)
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw Exception('Comic info failed: ${res.statusCode}');
      }
      final info = jsonDecode(res.body) as Map;
      final media = info['media'] as Map? ?? const {};
      final count = (komga
              ? media['pagesCount']
              : kavita
                  ? info['pages']
                  : info['page_count']) as int? ??
          0;
      if (count == 0) throw Exception('No pages in comic');
      // Saved so a relaunch can resume without asking again.
      meta = _downloadMeta[key] = meta.withPageCount(count);
      _persistJournal();
    }
    await _fetcher.start(meta.taskId, [
      for (var i = 0; i < meta.pageCount!; i++)
        (
          url: opds
              ? meta.url
                  .substring(0, meta.url.lastIndexOf('#'))
                  .replaceAll('{pageNumber}', '$i')
                  .replaceAll('{maxWidth}', '2048')
              : kavita
              ? '${meta.url.replaceFirst('/api/Chapter?', '/api/Reader/image?')}'
                  '&page=$i&apiKey=${Uri.encodeQueryComponent(headers['X-API-Key'] ?? '')}'
              : '${meta.url}/pages/${komga ? i + 1 : i}',
          // Name = 1-based page number; readers match on it, and decode by
          // content, so no extension is needed.
          dest: p.join(comicDir, 'pages', (i + 1).toString().padLeft(3, '0')),
        ),
    ], headers);
  }

  /// Clear failed entries. Finished downloads stay — they're files on disk
  /// and are removed with [delete].
  void clearFailed() {
    _completed.removeWhere((i) => i.status == DownloadStatus.failed);
    _emit();
  }

  /// Re-queue a failed download with the URL and headers it was queued with.
  void retry(String comicId, String sourceId) {
    final i = _completed.indexWhere((i) =>
        i.comicId == comicId &&
        i.sourceId == sourceId &&
        i.status == DownloadStatus.failed);
    final meta = _downloadMeta[_metaKey(comicId, sourceId)];
    if (i < 0 || meta == null) return;
    _downloadMeta[_metaKey(comicId, sourceId)] = _DownloadMeta(
        url: meta.url,
        headers: meta.headers,
        taskId: _newTaskId(comicId, sourceId),
        pageCount: meta.pageCount);
    final item = _completed.removeAt(i).copyWith(
        status: DownloadStatus.queued, downloadedBytes: 0, totalBytes: 0);
    _queue.add(item);
    _persistJournal();
    _startFetch(item);
    _emit();
    _processNext();
  }

  /// Delete a finished download's files and forget it, so every watcher
  /// (issue rows, downloaded-id sets, the Downloads screen) refreshes.
  Future<void> delete(String comicId, String sourceId) async {
    final dir = Directory(p.join(_downloadsRoot, sourceId, comicId));
    if (await dir.exists()) await dir.delete(recursive: true);
    forgetLocalPages(p.join(dir.path, 'pages'));
    final seriesId = _completed
            .where((i) => i.comicId == comicId && i.sourceId == sourceId)
            .firstOrNull
            ?.seriesId ??
        '';
    _completed.removeWhere(
        (i) => i.comicId == comicId && i.sourceId == sourceId);
    _emit();
    onDeleted?.call(sourceId, seriesId);
  }

  /// Lists a comic that is already complete on disk (a local import) as
  /// downloaded, without a relaunch. No-op if it's incomplete or known.
  Future<void> adopt(String comicId, String sourceId) async {
    if (!_isDownloadedOnDisk(comicId, sourceId) || _isKnown(comicId, sourceId)) {
      return;
    }
    final dir = Directory(p.join(_downloadsRoot, sourceId, comicId));
    // A re-import of the same name may have other page files.
    forgetLocalPages(p.join(dir.path, 'pages'));
    _completed.add(await _completedFromDisk(dir, comicId, sourceId));
    _emit();
  }

  /// Forget everything downloaded or queued for [sourceId] (signing out of,
  /// or replacing, a server).
  Future<void> deleteSource(String sourceId) async {
    for (final item in [..._queue]) {
      if (item.sourceId == sourceId) cancel(item.comicId, sourceId);
    }
    _completed.removeWhere((i) => i.sourceId == sourceId);
    // ponytail: an in-flight page may land after the dir delete; it stays
    // an orphan file (nothing sweeps it).
    try {
      final dir = Directory(p.join(_downloadsRoot, sourceId));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    _persistJournal();
    _emit();
  }

  /// Cancel a download. A queued item is removed at once; the active one
  /// is removed by the work loop when its fetch reports the cancel.
  void cancel(String comicId, String sourceId) {
    final i = _queue
        .indexWhere((i) => i.comicId == comicId && i.sourceId == sourceId);
    if (i < 0) return;
    final item = _queue[i];
    final key = _metaKey(comicId, sourceId);
    final taskId = _downloadMeta[key]?.taskId;
    if (_processing && i == 0) {
      if (taskId != null) _fetcher.cancel(taskId);
      return;
    }
    if (taskId != null) _fetcher.cancel(taskId);
    _queue.removeAt(i);
    _downloadMeta.remove(key);
    _starts.remove(key);
    try {
      final dir = Directory(_comicDir(item));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
    _persistJournal();
    _emit();
  }

  bool isDownloaded(String comicId, String sourceId) {
    return _completed.any((i) =>
        i.comicId == comicId &&
        i.sourceId == sourceId &&
        i.status == DownloadStatus.completed);
  }

  bool _isKnown(String comicId, String sourceId) {
    return _queue.any((i) => i.comicId == comicId && i.sourceId == sourceId) ||
        _completed.any((i) => i.comicId == comicId && i.sourceId == sourceId);
  }

  String _metaKey(String comicId, String sourceId) => '$sourceId:$comicId';

  Future<void> _processNext() async {
    if (_processing || _queue.isEmpty) return;
    _processing = true;
    // finally: an error escaping a handler (the journal write hitting ENOSPC)
    // used to leave _processing stuck true, and nothing downloaded again
    // until relaunch.
    try {
    while (_queue.isNotEmpty) {
      final item = _queue.first;
      try {
        await _download(item);
      } on DownloadCancelled {
        try {
          final dir = Directory(
              p.join(_downloadsRoot, item.sourceId, item.comicId));
          if (dir.existsSync()) await dir.delete(recursive: true);
        } catch (_) {
          // Racing native page writes after cancel; the disk scan sweeps it.
        }
        _queue.removeAt(0);
        _downloadMeta.remove(_metaKey(item.comicId, item.sourceId));
        _persistJournal();
        _emit();
      } catch (e) {
        // Drop the partial files so a retry starts clean.
        try {
          final dir = Directory(
              p.join(_downloadsRoot, item.sourceId, item.comicId));
          if (dir.existsSync()) await dir.delete(recursive: true);
        } catch (_) {}
        _queue[0] = item.copyWith(
          status: DownloadStatus.failed,
          error: e is FileSystemException && e.osError?.errorCode == 28 // ENOSPC
              ? 'Not enough storage on this device'
              : e.toString(),
        );
        // Meta stays so retry() can re-queue it.
        _completed.add(_queue.removeAt(0));
        _persistJournal();
        _emit();
      }
    }
    } finally {
      _processing = false;
    }
  }

  Future<void> _download(DownloadItem item) async {
    final key = _metaKey(item.comicId, item.sourceId);
    final downloadDir = _comicDir(item);
    _queue[0] = item.copyWith(status: DownloadStatus.downloading);
    _emit();

    await (_starts.remove(key) ?? Future.value());
    final meta = _downloadMeta[key];
    if (meta == null) throw Exception('Missing download metadata');

    // ponytail: progress is pages, carried in the byte fields — the UI only
    // shows the ratio while downloading; real bytes are set on completion.
    await _fetcher.wait(meta.taskId, (done, total) {
      if (_queue.isEmpty) return;
      _queue[0] = _queue[0].copyWith(downloadedBytes: done, totalBytes: total);
      _emit();
    });

    final pages = Directory(p.join(downloadDir, 'pages'))
        .listSync()
        .whereType<File>()
        .toList();
    if (pages.isEmpty) throw Exception('No pages in comic');
    var size = 0;
    for (final f in pages) {
      size += f.lengthSync();
    }

    // metadata.json marks the download complete, so it goes last, atomically.
    final metadataTmp = File(p.join(downloadDir, 'metadata.json.tmp'));
    await metadataTmp.writeAsString(jsonEncode({
      'comic_id': item.comicId,
      'source_id': item.sourceId,
      'series_id': item.seriesId,
      'series_name': item.seriesName,
      'comic_name': item.comicName,
      'page_count': pages.length,
      'downloaded_at': DateTime.now().toIso8601String(),
      'size_bytes': size,
    }), flush: true);
    await metadataTmp.rename(p.join(downloadDir, 'metadata.json'));

    _completed.add(_queue[0].copyWith(
      status: DownloadStatus.completed,
      totalBytes: size,
      downloadedBytes: size,
    ));
    _queue.removeAt(0);
    _downloadMeta.remove(key);
    _persistJournal();
    _emit();
  }

  void _emit() {
    if (_stateController.isClosed) return; // a download finishing after dispose
    _stateController.add(currentState);
  }

  void dispose() {
    _stateController.close();
  }
}

class _DownloadMeta {
  final String url; // <server>/comics/<id>, Komga's <server>/api/v1/books/<id>, Kavita's <server>/api/Chapter?chapterId=<id>, or OPDS's <page template>#<count>
  final Map<String, String> headers;
  final String taskId;
  final int? pageCount; // null until /info answers
  const _DownloadMeta(
      {required this.url,
      required this.headers,
      required this.taskId,
      this.pageCount});

  _DownloadMeta withPageCount(int count) => _DownloadMeta(
      url: url, headers: headers, taskId: taskId, pageCount: count);
}

class DownloadManagerState {
  final List<DownloadItem> queue;
  final List<DownloadItem> completed;

  const DownloadManagerState({
    this.queue = const [],
    this.completed = const [],
  });

  List<DownloadItem> get all => [...queue, ...completed];

  /// The currently active item (downloading), if any.
  DownloadItem? get active =>
      queue.isNotEmpty && queue.first.status != DownloadStatus.queued
          ? queue.first
          : null;
}
