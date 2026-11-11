import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:comic_reader_app/models/download_item.dart';
import 'package:comic_reader_app/services/download_manager.dart';
import 'package:comic_reader_app/services/page_fetcher.dart';

/// Serves `/comics/<id>/info` with [pages] pages and `/comics/<id>/pages/<n>`
/// as the single byte n. [failPage] answers 500; [hangPages] never answers
/// page requests; [requests] logs paths.
http.Client comicClient({
  int pages = 2,
  int? failPage,
  int infoStatus = 200,
  bool hangPages = false,
  List<String>? requests,
}) {
  return MockClient((req) async {
    requests?.add(req.url.path);
    final path = req.url.path;
    if (path.endsWith('/info')) {
      return http.Response(jsonEncode({'page_count': pages}), infoStatus);
    }
    final m = RegExp(r'/pages/(\d+)$').firstMatch(path);
    if (m == null) return http.Response('nope', 404);
    if (hangPages) return Completer<http.Response>().future;
    final n = int.parse(m.group(1)!);
    if (n == failPage) return http.Response('boom', 500);
    return http.Response.bytes([n], 200);
  });
}

/// Never answers — downloads hang forever (items stay pending).
http.Client hangingClient() =>
    MockClient((request) => Completer<http.Response>().future);

/// Polls until [condition] is true or fails after 5 seconds.
Future<void> pumpUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('pumpUntil timed out');
    }
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

void enqueueTestItem(
  DownloadManager manager, {
  required String comicId,
  String sourceId = 'src1',
}) {
  manager.enqueue(
    comicId: comicId,
    sourceId: sourceId,
    seriesId: 'series1',
    seriesName: 'Test Series',
    comicName: 'Issue $comicId',
    comicUrl: 'http://localhost/comics/$comicId',
    headers: const {'X-Device-ID': 'test'},
  );
}

/// Records hand-offs; [wait] resolves when the test says the background
/// transfer finished.
class FakeFetcher implements PageFetcher {
  final started = <String, List<PageFile>>{};
  final cancelled = <String>[];
  final _done = <String, Completer<void>>{};
  Completer<void> done(String taskId) =>
      _done.putIfAbsent(taskId, () => Completer<void>()..future.ignore());

  @override
  Future<void> start(String taskId, List<PageFile> files,
          Map<String, String> headers) async =>
      started[taskId] = files;

  @override
  Future<void> wait(String taskId, void Function(int, int) onProgress) =>
      done(taskId).future;

  @override
  Future<void> cancel(String taskId) async {
    cancelled.add(taskId);
    final c = done(taskId);
    if (!c.isCompleted) c.completeError(const DownloadCancelled());
  }
}

void main() {
  late Directory tempDir;
  String comicDir(String id) => p.join(tempDir.path, 'downloads', 'src1', id);
  File journal() => File(p.join(tempDir.path, 'downloads', 'queue.json'));

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dlmgr_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('journal', () {
    test('enqueue writes pending items to queue.json', () async {
      final manager =
          DownloadManager(baseDir: tempDir.path, httpClient: hangingClient());
      enqueueTestItem(manager, comicId: 'c1');
      enqueueTestItem(manager, comicId: 'c2');

      final entries = jsonDecode(journal().readAsStringSync()) as List;
      expect(entries, hasLength(2));
      final first = entries.first as Map<String, dynamic>;
      expect((first['item'] as Map)['comic_id'], 'c1');
      expect(first['url'], 'http://localhost/comics/c1');
      expect((first['headers'] as Map)['X-Device-ID'], 'test');
    });

    test('journal never stores Authorization', () async {
      final seen = <String, String?>{};
      final client = MockClient((req) async {
        seen[req.url.path] = req.headers['Authorization'];
        if (req.url.path.endsWith('/info')) {
          return http.Response(jsonEncode({'page_count': 1}), 200);
        }
        return http.Response.bytes([1], 200);
      });
      final manager = DownloadManager(
        baseDir: tempDir.path,
        httpClient: client,
        authFor: (id) => id == 'src1' ? {'Authorization': 'Bearer k'} : {},
      );
      enqueueTestItem(manager, comicId: 'c1');

      await pumpUntil(() => seen.length >= 2);
      expect(seen['/comics/c1/info'], 'Bearer k');
      expect(seen['/comics/c1/pages/0'], 'Bearer k');
      expect(journal().readAsStringSync(), isNot(contains('Authorization')));
    });

    test('init restores pending items and processes them', () async {
      final managerA =
          DownloadManager(baseDir: tempDir.path, httpClient: hangingClient());
      enqueueTestItem(managerA, comicId: 'c1');
      enqueueTestItem(managerA, comicId: 'c2');

      // Same baseDir, working client — simulates app restart.
      final managerB =
          DownloadManager(baseDir: tempDir.path, httpClient: comicClient());
      await managerB.init();
      await pumpUntil(() =>
          managerB.isDownloaded('c1', 'src1') &&
          managerB.isDownloaded('c2', 'src1'));

      expect(Directory(p.join(comicDir('c1'), 'pages')).listSync(),
          hasLength(2));
      expect(jsonDecode(journal().readAsStringSync()) as List, isEmpty);
      managerB.dispose();
    });

    test('init survives a corrupt journal', () async {
      Directory(p.join(tempDir.path, 'downloads')).createSync(recursive: true);
      journal().writeAsStringSync('{not json[');

      final manager =
          DownloadManager(baseDir: tempDir.path, httpClient: comicClient());
      await manager.init(); // must not throw
      expect(manager.currentState.queue, isEmpty);
      manager.dispose();
    });

    test('a journal from the archive design restores and downloads pages',
        () async {
      Directory(p.join(tempDir.path, 'downloads')).createSync(recursive: true);
      journal().writeAsStringSync(jsonEncode([
        {
          'item': {
            'comic_id': 'c1',
            'source_id': 'src1',
            'status': 'extracting',
            'added_at': DateTime.now().toIso8601String(),
          },
          'url': 'http://localhost/comics/c1/download',
          'headers': {'X-Device-ID': 'test'},
        }
      ]));

      final manager =
          DownloadManager(baseDir: tempDir.path, httpClient: comicClient());
      await manager.init();
      await pumpUntil(() => manager.isDownloaded('c1', 'src1'));
      manager.dispose();
    });
  });

  group('sweep', () {
    test('init deletes incomplete dirs and keeps complete ones', () async {
      final root = p.join(tempDir.path, 'downloads', 'src1');
      // Half-downloaded (killed before metadata.json): not trusted.
      Directory(p.join(root, 'half', 'pages')).createSync(recursive: true);
      File(p.join(root, 'half', 'pages', '001')).writeAsStringSync('x');
      // Complete.
      Directory(p.join(root, 'done', 'pages')).createSync(recursive: true);
      File(p.join(root, 'done', 'pages', '001')).writeAsStringSync('x');
      File(p.join(root, 'done', 'metadata.json')).writeAsStringSync('{}');

      final manager =
          DownloadManager(baseDir: tempDir.path, httpClient: comicClient());
      await manager.init();

      expect(Directory(p.join(root, 'half')).existsSync(), isFalse);
      expect(File(p.join(root, 'done', 'pages', '001')).existsSync(), isTrue);
      manager.dispose();
    });

    test('init keeps partial dirs whose comic is in the restored queue',
        () async {
      final managerA =
          DownloadManager(baseDir: tempDir.path, httpClient: hangingClient());
      enqueueTestItem(managerA, comicId: 'c1');
      File(p.join(comicDir('c1'), 'pages', '001')).writeAsStringSync('done');

      final managerB =
          DownloadManager(baseDir: tempDir.path, httpClient: hangingClient());
      await managerB.init();

      // Not fresh: the page already fetched survives the relaunch.
      expect(File(p.join(comicDir('c1'), 'pages', '001')).existsSync(), isTrue);
      expect(managerB.currentState.queue.single.comicId, 'c1');
    });
  });

  group('enqueue disk check', () {
    test('enqueue skips a comic already downloaded on disk', () async {
      Directory(p.join(comicDir('c1'), 'pages')).createSync(recursive: true);
      File(p.join(comicDir('c1'), 'metadata.json')).writeAsStringSync('{}');

      final manager =
          DownloadManager(baseDir: tempDir.path, httpClient: comicClient());
      enqueueTestItem(manager, comicId: 'c1');
      expect(manager.currentState.queue, isEmpty);
      manager.dispose();
    });

    test('a half-downloaded comic is re-downloaded, not trusted', () async {
      Directory(p.join(comicDir('c1'), 'pages')).createSync(recursive: true);
      File(p.join(comicDir('c1'), 'pages', '001')).writeAsStringSync('stale');

      final manager =
          DownloadManager(baseDir: tempDir.path, httpClient: comicClient());
      enqueueTestItem(manager, comicId: 'c1');
      await pumpUntil(() => manager.isDownloaded('c1', 'src1'));
      expect(File(p.join(comicDir('c1'), 'pages', '001')).readAsBytesSync(),
          [0]);
      manager.dispose();
    });
  });

  test('page N on disk is server page N; metadata records count and size',
      () async {
    final manager = DownloadManager(
        baseDir: tempDir.path, httpClient: comicClient(pages: 3));
    enqueueTestItem(manager, comicId: 'c1');
    await pumpUntil(() => manager.isDownloaded('c1', 'src1'));

    for (var n = 0; n < 3; n++) {
      final name = (n + 1).toString().padLeft(3, '0');
      expect(File(p.join(comicDir('c1'), 'pages', name)).readAsBytesSync(),
          [n]);
    }
    final meta = jsonDecode(
        File(p.join(comicDir('c1'), 'metadata.json')).readAsStringSync());
    expect(meta['page_count'], 3);
    expect(meta['size_bytes'], 3);
    expect(manager.currentState.completed.single.totalBytes, 3);
    manager.dispose();
  });

  test('Komga layout: page count from the book, 1-based page URLs', () async {
    final requests = <String>[];
    final manager = DownloadManager(
      baseDir: tempDir.path,
      httpClient: MockClient((req) async {
        requests.add(req.url.path);
        if (req.url.path == '/api/v1/books/b1') {
          return http.Response(jsonEncode({'media': {'pagesCount': 3}}), 200);
        }
        final m = RegExp(r'/api/v1/books/b1/pages/(\d+)$').firstMatch(req.url.path);
        if (m == null) return http.Response('nope', 404);
        return http.Response.bytes([int.parse(m.group(1)!)], 200);
      }),
    );
    manager.enqueue(
      comicId: 'b1', sourceId: 'src1', seriesId: 's1', seriesName: 'S',
      comicName: 'B1', comicUrl: 'http://localhost/api/v1/books/b1',
      headers: const {'X-API-Key': 'k'},
    );
    await pumpUntil(() => manager.isDownloaded('b1', 'src1'));
    for (var n = 1; n <= 3; n++) {
      final name = n.toString().padLeft(3, '0');
      expect(File(p.join(comicDir('b1'), 'pages', name)).readAsBytesSync(), [n]);
    }
    expect(requests, isNot(contains('/api/v1/books/b1/pages/0')));
    manager.dispose();
  });

  test('Kavita layout: page count from the chapter, 0-based keyed page URLs', () async {
    final requests = <Uri>[];
    final manager = DownloadManager(
      baseDir: tempDir.path,
      httpClient: MockClient((req) async {
        requests.add(req.url);
        final q = req.url.queryParameters;
        if (req.url.path == '/api/Chapter' && q['chapterId'] == '3') {
          return http.Response(jsonEncode({'pages': 2}), 200);
        }
        if (req.url.path != '/api/Reader/image' || q['apiKey'] != 'k') {
          return http.Response('nope', 404);
        }
        return http.Response.bytes([int.parse(q['page']!)], 200);
      }),
    );
    manager.enqueue(
      comicId: '3', sourceId: 'src1', seriesId: '7', seriesName: 'S',
      comicName: 'C3', comicUrl: 'http://localhost/api/Chapter?chapterId=3',
      headers: const {'X-API-Key': 'k'},
    );
    await pumpUntil(() => manager.isDownloaded('3', 'src1'));
    for (var n = 0; n < 2; n++) {
      final name = (n + 1).toString().padLeft(3, '0');
      expect(File(p.join(comicDir('3'), 'pages', name)).readAsBytesSync(), [n]);
    }
    expect(requests.last.queryParameters['chapterId'], '3');
    manager.dispose();
  });

  test('a relaunch only fetches the pages still missing', () async {
    final managerA = DownloadManager(
        baseDir: tempDir.path,
        httpClient: comicClient(pages: 3, hangPages: true));
    enqueueTestItem(managerA, comicId: 'c1');
    // Page count journaled, then page 0 lands before the app dies.
    await pumpUntil(() => journal().readAsStringSync().contains('"page_count":3'));
    File(p.join(comicDir('c1'), 'pages', '001')).writeAsBytesSync([0]);

    final requests = <String>[];
    final managerB = DownloadManager(
        baseDir: tempDir.path,
        httpClient: comicClient(pages: 3, requests: requests));
    await managerB.init();
    await pumpUntil(() => managerB.isDownloaded('c1', 'src1'));
    expect(requests, ['/comics/c1/pages/1', '/comics/c1/pages/2']);
    managerB.dispose();
  });

  group('cancel', () {
    test('cancelling a queued item removes it from queue and journal',
        () async {
      final manager =
          DownloadManager(baseDir: tempDir.path, httpClient: hangingClient());
      enqueueTestItem(manager, comicId: 'c1'); // becomes active, hangs
      enqueueTestItem(manager, comicId: 'c2'); // stays queued

      manager.cancel('c2', 'src1');

      expect(manager.currentState.queue.map((i) => i.comicId), ['c1']);
      final entries = jsonDecode(journal().readAsStringSync()) as List;
      expect(((entries.single as Map)['item'] as Map)['comic_id'], 'c1');
      expect(Directory(comicDir('c2')).existsSync(), isFalse);
    });

    test('cancelling the active item aborts a hanging page and cleans up',
        () async {
      final manager = DownloadManager(
          baseDir: tempDir.path, httpClient: comicClient(hangPages: true));
      enqueueTestItem(manager, comicId: 'c1');
      await pumpUntil(() =>
          manager.currentState.active?.status == DownloadStatus.downloading);
      await Future.delayed(const Duration(milliseconds: 50));

      manager.cancel('c1', 'src1');
      await pumpUntil(() => manager.currentState.queue.isEmpty);

      expect(manager.currentState.completed, isEmpty);
      expect(Directory(comicDir('c1')).existsSync(), isFalse);
      manager.dispose();
    });

    test('cancel does not disturb the next queued item', () async {
      final hang = comicClient(hangPages: true);
      final ok = comicClient();
      final manager = DownloadManager(
        baseDir: tempDir.path,
        httpClient: MockClient((req) =>
            (req.url.path.contains('/c1/') ? hang : ok).get(req.url)),
      );
      enqueueTestItem(manager, comicId: 'c1');
      enqueueTestItem(manager, comicId: 'c2');
      await pumpUntil(() =>
          manager.currentState.active?.status == DownloadStatus.downloading);

      manager.cancel('c1', 'src1');
      await pumpUntil(() => manager.isDownloaded('c2', 'src1'));
      expect(manager.isDownloaded('c1', 'src1'), isFalse);
      manager.dispose();
    });
  });

  group('failures', () {
    Future<DownloadItem> failWith(http.Client client) async {
      final manager = DownloadManager(baseDir: tempDir.path, httpClient: client);
      enqueueTestItem(manager, comicId: 'c1');
      await pumpUntil(() => manager.currentState.completed.isNotEmpty);
      final item = manager.currentState.completed.single;
      expect(item.status, DownloadStatus.failed);
      // Partial files are gone, so nothing looks downloaded…
      expect(Directory(comicDir('c1')).existsSync(), isFalse);
      // …and a retry is actually queued, not silently skipped.
      enqueueTestItem(manager, comicId: 'c1');
      expect(manager.currentState.queue, hasLength(1));
      await pumpUntil(() => manager.currentState.queue.isEmpty);
      manager.dispose();
      return item;
    }

    test('a comic with no pages fails and cleans up', () async {
      final item = await failWith(comicClient(pages: 0));
      expect(item.error, contains('No pages'));
    });

    test('a failing page fails the comic and cleans up', () async {
      final item = await failWith(comicClient(pages: 3, failPage: 1));
      expect(item.error, contains('500'));
    });

    test('a failing info lookup fails the comic', () async {
      final item = await failWith(comicClient(infoStatus: 404));
      expect(item.error, contains('404'));
    });
  });

  test('delete removes files and forgets the completed item', () async {
    final manager =
        DownloadManager(baseDir: tempDir.path, httpClient: comicClient());
    enqueueTestItem(manager, comicId: 'c1');
    await pumpUntil(() => manager.isDownloaded('c1', 'src1'));

    await manager.delete('c1', 'src1');
    expect(manager.isDownloaded('c1', 'src1'), isFalse);
    expect(Directory(comicDir('c1')).existsSync(), isFalse);
    manager.dispose();
  });

  test('deleteSource drops completed + dir for that source only', () async {
    final manager =
        DownloadManager(baseDir: tempDir.path, httpClient: comicClient());
    enqueueTestItem(manager, comicId: 'c1');
    enqueueTestItem(manager, comicId: 'c2', sourceId: 'src2');
    await pumpUntil(() =>
        manager.isDownloaded('c1', 'src1') &&
        manager.isDownloaded('c2', 'src2'));

    await manager.deleteSource('src1');
    expect(manager.isDownloaded('c1', 'src1'), isFalse);
    expect(Directory(p.join(tempDir.path, 'downloads', 'src1')).existsSync(),
        isFalse);
    expect(manager.isDownloaded('c2', 'src2'), isTrue);
    expect(manager.currentState.completed.map((i) => i.sourceId), ['src2']);
    manager.dispose();
  });

  test('deleteSource cancels that source\'s queued items', () async {
    final manager =
        DownloadManager(
            baseDir: tempDir.path, httpClient: comicClient(hangPages: true));
    enqueueTestItem(manager, comicId: 'c1');
    enqueueTestItem(manager, comicId: 'c2');
    enqueueTestItem(manager, comicId: 'c3', sourceId: 'src2');
    await pumpUntil(() =>
        manager.currentState.active?.status == DownloadStatus.downloading);
    await Future.delayed(const Duration(milliseconds: 50));

    await manager.deleteSource('src1');
    await pumpUntil(() =>
        manager.currentState.queue.every((i) => i.sourceId == 'src2'));
    final entries = jsonDecode(journal().readAsStringSync()) as List;
    expect(entries.map((e) => ((e as Map)['item'] as Map)['source_id']),
        everyElement('src2'));
    manager.dispose();
  });

  test('init lists finished downloads from disk after a relaunch', () async {
    final first =
        DownloadManager(baseDir: tempDir.path, httpClient: comicClient());
    enqueueTestItem(first, comicId: 'c1');
    await pumpUntil(() => first.isDownloaded('c1', 'src1'));
    first.dispose();

    final relaunched =
        DownloadManager(baseDir: tempDir.path, httpClient: comicClient());
    await relaunched.init();
    final item = relaunched.currentState.completed.single;
    expect(item.status, DownloadStatus.completed);
    expect(item.comicName, 'Issue c1');
    expect(item.seriesName, 'Test Series');
    expect(item.totalBytes, 2);
    relaunched.dispose();
  });

  test('retry re-queues a failed download; clearFailed keeps finished ones',
      () async {
    var fail = true;
    final ok = comicClient();
    final manager = DownloadManager(
      baseDir: tempDir.path,
      httpClient: MockClient((req) => req.url.path.contains('/c2/') && fail
          ? Future.value(http.Response('nope', 500))
          : ok.get(req.url)),
    );
    enqueueTestItem(manager, comicId: 'c1');
    enqueueTestItem(manager, comicId: 'c2');
    await pumpUntil(() => manager.currentState.queue.isEmpty);
    expect(manager.isDownloaded('c1', 'src1'), isTrue);

    fail = false;
    manager.retry('c2', 'src1');
    await pumpUntil(() => manager.isDownloaded('c2', 'src1'));

    manager.clearFailed();
    expect(manager.currentState.completed, hasLength(2));
    manager.dispose();
  });

  group('background fetch', () {
    test('every queued comic is handed off at enqueue, not one at a time',
        () async {
      final fetcher = FakeFetcher();
      final manager = DownloadManager(
          baseDir: tempDir.path, httpClient: comicClient(), fetcher: fetcher);
      for (final id in ['c1', 'c2', 'c3']) {
        enqueueTestItem(manager, comicId: id);
      }
      await pumpUntil(() => fetcher.started.length == 3);
      final pages = fetcher.started.values.first;
      expect(pages.map((f) => f.url), [
        'http://localhost/comics/c1/pages/0',
        'http://localhost/comics/c1/pages/1',
      ]);
      expect(pages.map((f) => p.basename(f.dest)), ['001', '002']);
      manager.dispose();
    });

    test('pages that finished in the background complete on relaunch',
        () async {
      final before = FakeFetcher();
      final first = DownloadManager(
          baseDir: tempDir.path, httpClient: comicClient(), fetcher: before);
      enqueueTestItem(first, comicId: 'c1');
      await pumpUntil(() => before.started.isNotEmpty);
      final (taskId, files) =
          before.started.entries.map((e) => (e.key, e.value)).single;
      // App killed; the transfers finish natively meanwhile.
      for (final f in files) {
        File(f.dest).writeAsBytesSync([1]);
      }

      final after = FakeFetcher();
      final relaunched = DownloadManager(
          baseDir: tempDir.path, httpClient: hangingClient(), fetcher: after);
      await relaunched.init();
      // Same task, page count from the journal (no /info: client hangs).
      await pumpUntil(() => after.started.keys.contains(taskId));
      after.done(taskId).complete();
      await pumpUntil(() => relaunched.isDownloaded('c1', 'src1'));
      relaunched.dispose();
    });

    test('cancel reaches the fetcher for queued and active items', () async {
      final fetcher = FakeFetcher();
      final manager = DownloadManager(
          baseDir: tempDir.path, httpClient: comicClient(), fetcher: fetcher);
      enqueueTestItem(manager, comicId: 'c1');
      enqueueTestItem(manager, comicId: 'c2');
      await pumpUntil(() => fetcher.started.length == 2);

      manager.cancel('c2', 'src1');
      manager.cancel('c1', 'src1');
      await pumpUntil(() => manager.currentState.queue.isEmpty);
      expect(fetcher.cancelled, hasLength(2));
      expect(manager.currentState.completed, isEmpty);
      manager.dispose();
    });
  });

  group('local imports', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('dm_adopt'));
    tearDown(() => dir.deleteSync(recursive: true));

    void writeComic(String id, {bool complete = true}) {
      final comic = p.join(dir.path, 'downloads', 'local', id);
      File(p.join(comic, 'pages', '1.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      if (complete) {
        File(p.join(comic, 'metadata.json')).writeAsStringSync(jsonEncode(
            {'series_id': 's1', 'series_name': 'Saga', 'comic_name': 'Saga 001'}));
      }
    }

    test('adopt lists a finished directory as downloaded, once', () async {
      final manager = DownloadManager(baseDir: dir.path, httpClient: hangingClient());
      addTearDown(manager.dispose);
      await manager.init();
      writeComic('c1');
      writeComic('c2', complete: false);
      await manager.adopt('c1', 'local');
      await manager.adopt('c1', 'local');
      await manager.adopt('c2', 'local');
      final done = manager.currentState.completed;
      expect(done.map((i) => i.comicId), ['c1']);
      expect(done.single.status, DownloadStatus.completed);
      expect(done.single.seriesId, 's1');
      expect(done.single.totalBytes, 3);
      expect(manager.currentState.queue, isEmpty);
    });

    test('delete reports the source so a local library can re-list', () async {
      final deleted = <String>[];
      final manager = DownloadManager(
          baseDir: dir.path, httpClient: hangingClient(), onDeleted: deleted.add);
      addTearDown(manager.dispose);
      writeComic('c1');
      await manager.init();
      await manager.delete('c1', 'local');
      expect(deleted, ['local']);
      expect(manager.currentState.completed, isEmpty);
      expect(Directory(p.join(dir.path, 'downloads', 'local', 'c1')).existsSync(), false);
    });
  });
}
