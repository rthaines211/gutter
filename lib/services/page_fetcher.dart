import 'dart:async';
import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Thrown from [PageFetcher.wait] when the comic was cancelled.
class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

typedef PageFile = ({String url, String dest});

/// Gets a comic's page files to disk. [start] hands them off (they may keep
/// downloading while the app is suspended); [wait] resolves once every file
/// is at its dest. A file at its dest is complete — both fetchers write it
/// only when its download has finished — so a relaunch resumes from disk.
/// Task ids are unique per attempt, so a stale event can't hit a retry.
abstract class PageFetcher {
  /// Never throws — failures surface from [wait].
  Future<void> start(
      String taskId, List<PageFile> files, Map<String, String> headers);

  Future<void> wait(String taskId, void Function(int done, int total) onProgress);

  Future<void> cancel(String taskId);
}

/// Plain HTTP in the Dart isolate, one page at a time: tests, and http://
/// sources (iOS refuses non-HTTPS background transfers). Stops when the app
/// is suspended.
class HttpFetcher implements PageFetcher {
  HttpFetcher(this._client);

  final http.Client _client;
  final _jobs =
      <String, ({List<PageFile> files, Map<String, String> headers})>{};
  final _cancels = <String, Completer<void>>{};

  Completer<void> _cancelSignal(String taskId) =>
      _cancels.putIfAbsent(taskId, Completer.new);

  @override
  Future<void> start(String taskId, List<PageFile> files,
      Map<String, String> headers) async {
    _jobs[taskId] = (files: files, headers: headers);
  }

  @override
  Future<void> cancel(String taskId) async {
    final c = _cancelSignal(taskId);
    if (!c.isCompleted) c.complete();
  }

  @override
  Future<void> wait(
      String taskId, void Function(int done, int total) onProgress) async {
    final job = _jobs.remove(taskId);
    final cancelled = _cancelSignal(taskId).future;
    if (job == null) throw const DownloadCancelled();
    try {
      for (final (i, f) in job.files.indexed) {
        if (!File(f.dest).existsSync()) {
          final res = await Future.any([
            _client
                .get(Uri.parse(f.url), headers: job.headers)
                .timeout(const Duration(seconds: 60)),
            cancelled.then<http.Response>((_) => throw const DownloadCancelled()),
          ]);
          if (res.statusCode != 200) {
            throw Exception('Download failed: ${res.statusCode}');
          }
          // .part then rename: a file at its dest is always complete.
          final part = File('${f.dest}.part');
          await part.writeAsBytes(res.bodyBytes, flush: true);
          await part.rename(f.dest);
        }
        onProgress(i + 1, job.files.length);
      }
    } finally {
      _cancels.remove(taskId);
    }
  }
}

/// iOS background URLSession via background_downloader: every page is
/// handed to iOS at once, so a whole series keeps downloading while the app
/// is suspended.
class BackgroundFetcher implements PageFetcher {
  BackgroundFetcher(this._docsDir, http.Client client)
      : _http = HttpFetcher(client) {
    // One notification per batch, when every queued download has finished.
    // Counts would be pages, not comics, so the text has none. iOS can't
    // show live progress here, so no `running` notification.
    FileDownloader().configureNotification(
      complete: const TaskNotification(
          'Downloads finished', 'Your comics are ready to read'),
      error: const TaskNotification(
          'Some downloads failed', 'Retry them in Downloads'),
      groupNotificationId: 'comic-downloads',
    );
    // Callbacks before start(): start() replays updates from while we were
    // suspended.
    FileDownloader().registerCallbacks(taskStatusCallback: _onStatus);
    _ready = FileDownloader().start(autoCleanDatabase: true)
      ..ignore(); // errors reach start()'s await; unawaited it's not a crash
  }

  final String _docsDir;
  final HttpFetcher _http;
  late final Future<void> _ready;
  final _jobs = <String, _Job>{};
  final _viaHttp = <String>{};

  static String _pageTaskId(String taskId, int i) => '$taskId#$i';

  @override
  Future<void> start(String taskId, List<PageFile> files,
      Map<String, String> headers) async {
    if (files.isNotEmpty && files.first.url.startsWith('http:')) {
      _viaHttp.add(taskId);
      return _http.start(taskId, files, headers);
    }
    final job = _jobs.putIfAbsent(taskId, () => _Job(files.length));
    try {
      for (final (i, f) in files.indexed) {
        if (File(f.dest).existsSync()) job.done.add(i);
      }
      await _ready;
      // On relaunch, pages still running natively report in by themselves.
      final running = (await FileDownloader().allTaskIds()).toSet();
      final tasks = [
        for (final (i, f) in files.indexed)
          if (!job.done.contains(i) && !running.contains(_pageTaskId(taskId, i)))
            DownloadTask(
              taskId: _pageTaskId(taskId, i),
              url: f.url,
              headers: headers,
              baseDirectory: BaseDirectory.applicationDocuments,
              directory: p.relative(p.dirname(f.dest), from: _docsDir),
              filename: p.basename(f.dest),
              retries: 3,
            ),
      ];
      final ok = await FileDownloader().enqueueAll(tasks);
      if (ok.contains(false)) throw Exception('Could not start download');
      job.check();
    } catch (e) {
      job.fail(e);
    }
  }

  @override
  Future<void> wait(
      String taskId, void Function(int done, int total) onProgress) async {
    if (_viaHttp.remove(taskId)) return _http.wait(taskId, onProgress);
    final job = _jobs[taskId];
    if (job == null) throw const DownloadCancelled();
    job.onProgress = onProgress;
    onProgress(job.done.length, job.total);
    try {
      await job.completer.future;
    } finally {
      _jobs.remove(taskId);
    }
  }

  @override
  Future<void> cancel(String taskId) async {
    if (_viaHttp.contains(taskId)) return _http.cancel(taskId);
    final job = _jobs.remove(taskId);
    job?.fail(const DownloadCancelled());
    await _cancelPages(taskId, job?.total ?? 0);
  }

  Future<void> _cancelPages(String taskId, int total) async {
    try {
      await FileDownloader().cancelTasksWithIds(
          [for (var i = 0; i < total; i++) _pageTaskId(taskId, i)]);
    } catch (_) {}
  }

  void _onStatus(TaskStatusUpdate u) {
    final id = u.task.taskId;
    final hash = id.lastIndexOf('#');
    if (hash < 0) return;
    final taskId = id.substring(0, hash);
    final job = _jobs[taskId];
    if (job == null || job.completer.isCompleted) return;
    switch (u.status) {
      case TaskStatus.complete:
        job.done.add(int.parse(id.substring(hash + 1)));
        job.onProgress?.call(job.done.length, job.total);
        job.check();
      case TaskStatus.failed || TaskStatus.notFound:
        // Retries are spent: the comic can't complete, stop its other pages.
        job.fail(Exception('Download failed: '
            '${u.responseStatusCode ?? u.exception?.description ?? u.status.name}'));
        _cancelPages(taskId, job.total);
      default:
    }
  }
}

class _Job {
  _Job(this.total) {
    completer.future.ignore(); // may fail before anyone waits; waiters still see it
  }

  final int total;
  final done = <int>{};
  final completer = Completer<void>();
  void Function(int, int)? onProgress;

  void check() {
    if (done.length >= total && !completer.isCompleted) completer.complete();
  }

  void fail(Object e) {
    if (!completer.isCompleted) completer.completeError(e);
  }
}
