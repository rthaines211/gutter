// test/providers/reader_provider_dispose_flush_test.dart
//
// Verifies the reader dispose-flush: when the reader provider is disposed
// with a pending debounced save (swipe-back), the onDispose flush must still
// write progress to the mirror and, if the PUT fails, enqueue to the sync
// queue. In Riverpod 3 reading `state` throws after dispose, so the flush
// relies on the _pendingSave snapshot captured in _scheduleSave.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/cache_providers.dart';
import 'package:comic_reader_app/providers/connectivity_provider.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/reader_provider.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:comic_reader_app/services/sync_queue.dart';

class _AlwaysOnline extends ConnectivityNotifier {
  @override
  bool build() => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MirrorDatabase db;
  late Directory tempDir;
  late SyncQueue queue;
  late List<String> putCalls;

  MockClient mockServer({required bool failPuts}) => MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/comics/c1/info') {
          return http.Response(
            jsonEncode({'title': 'Comic 1', 'page_count': 10}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.method == 'PUT' && req.url.path.startsWith('/reading/')) {
          if (failPuts) return http.Response('boom', 500);
          putCalls.add(req.url.pathSegments.last);
          return http.Response('{"status":"ok"}', 200);
        }
        return http.Response('not found', 404);
      });

  setUp(() async {
    await AppLogger.init(logDirFactory: () async => null);
    db = MirrorDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('reader_flush_test_');
    queue = SyncQueue(queuePath: '${tempDir.path}/queue.json');
    putCalls = [];
  });

  tearDown(() async {
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  ReaderKey readerKey() => (
        comicId: 'c1',
        comicPath: 'Comic 1.cbz',
        seriesIssues: [
          SeriesIssue(
            id: 'c1',
            name: 'Comic 1.cbz',
            number: null,
            coverUrl: '',
            status: 'unread',
            currentPage: null,
            totalPages: null,
          ),
        ],
        currentIssueIndex: 0,
      );

  ProviderContainer makeContainer({required bool failPuts}) {
    return ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(ApiClient(
        baseUrl: 'http://test',
        deviceId: 'test-device',
        httpClient: mockServer(failPuts: failPuts),
      )),
      mirrorDbProvider.overrideWithValue(db),
      syncQueueProvider.overrideWithValue(queue),
      connectivityProvider.overrideWith(_AlwaysOnline.new),
    ]);
  }

  Future<void> scheduleSaveThenDispose(ProviderContainer container) async {
    final key = readerKey();
    final sub = container.listen(readerProvider(key), (_, _) {});
    await container.read(readerProvider(key).future);
    // Turn a page: schedules the 2s debounced save (and snapshots progress).
    container.read(readerProvider(key).notifier).goToPage(3);
    sub.close();
    // Dispose with the timer still pending — onDispose must flush.
    container.dispose();
    // The flush is fire-and-forget; let its async work complete.
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  test('dispose-flush writes progress to the mirror and PUTs to the server',
      () async {
    final container = makeContainer(failPuts: false);
    await scheduleSaveThenDispose(container);

    final rows = await db.select(db.progressRows).get();
    expect(rows, hasLength(1));
    expect(rows.single.comicId, 'c1');
    expect(rows.single.currentPage, 3);
    expect(rows.single.totalPages, 10);

    expect(putCalls, ['c1']);
    expect(await queue.readAll(), isEmpty);
  });

  test('dispose-flush writes the held page, not the jumped-to one', () async {
    final container = makeContainer(failPuts: false);
    final key = readerKey();
    final sub = container.listen(readerProvider(key), (_, _) {});
    await container.read(readerProvider(key).future);
    final notifier = container.read(readerProvider(key).notifier);
    notifier.goToPage(7); // an undoable jump from page 1
    notifier.holdProgressAt(1);
    sub.close();
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final rows = await db.select(db.progressRows).get();
    expect(rows.single.currentPage, 1);
  });

  test('dispose-flush enqueues to the sync queue when the PUT fails',
      () async {
    final container = makeContainer(failPuts: true);
    await scheduleSaveThenDispose(container);

    // Mirror still gets the local-first write.
    final rows = await db.select(db.progressRows).get();
    expect(rows, hasLength(1));
    expect(rows.single.currentPage, 3);

    // And the failed PUT lands in the outbox so the next sync pull
    // can't revert the local row.
    final entries = await queue.readAll();
    expect(entries, hasLength(1));
    expect(entries.single['type'], 'progress');
    final payload = entries.single['payload'] as Map<String, dynamic>;
    expect(payload['comic_id'], 'c1');
    expect(payload['current_page'], 3);
    expect(payload['total_pages'], 10);
  });
}
