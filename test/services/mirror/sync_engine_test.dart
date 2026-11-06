import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:comic_reader_app/models/sync_response.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:comic_reader_app/services/mirror/sync_engine.dart';
import 'package:comic_reader_app/services/mirror/sync_progress.dart';
import 'package:comic_reader_app/services/sync_queue.dart';

void main() {
  late MirrorDatabase db;
  late Directory tempDir;
  late SyncQueue queue;
  final putCalls = <String>[];
  var syncCalls = 0;

  MockClient mockServer({bool failPuts = false}) => MockClient((req) async {
        if (req.method == 'PUT' && req.url.path.startsWith('/reading/')) {
          if (failPuts) return http.Response('boom', 500);
          putCalls.add(req.url.pathSegments.last);
          return http.Response('{"status":"ok"}', 200);
        }
        if (req.url.path == '/sync') {
          syncCalls++;
          return http.Response(
            jsonEncode({
              'server_time': 5000,
              'series': [],
              'progress': [
                {'comic_id': 'c1', 'current_page': 2, 'total_pages': 20, 'updated_at': '2020-01-01T00:00:00Z'}
              ],
              'series_ids': [],
              'progress_ids': ['c1'],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

  setUp(() async {
    await AppLogger.init(logDirFactory: () async => null);
    db = MirrorDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('sync_engine_test_');
    queue = SyncQueue(queuePath: '${tempDir.path}/queue.json');
    putCalls.clear();
    syncCalls = 0;
  });
  tearDown(() async {
    AppLogger.resetForTest();
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  test('flushes outbox before pull, then applies and stores watermark', () async {
    await queue.enqueue({
      'type': 'progress',
      'payload': {'comic_id': 'c1', 'current_page': 9, 'total_pages': 20},
    });
    final engine = SyncEngine(
      db: db,
      client: ApiClient(baseUrl: 'http://t', deviceId: 'd', httpClient: mockServer()),
      queue: queue,
    );

    await engine.sync();

    expect(putCalls, ['c1'], reason: 'outbox flushed first');
    expect(await queue.pendingCount, 0);
    // Queue flushed -> c1 was NOT protected -> server value applied.
    final row = (await db.select(db.progressRows).get()).single;
    expect(row.currentPage, 2);
    expect(await db.getSyncState('last_server_time'), '5000');
  });

  test('unflushed entries protect local progress from the pull', () async {
    await db.saveProgressLocal(comicId: 'c1', currentPage: 9, totalPages: 20);
    await queue.enqueue({
      'type': 'progress',
      'payload': {'comic_id': 'c1', 'current_page': 9, 'total_pages': 20},
    });
    final engine = SyncEngine(
      db: db,
      client: ApiClient(baseUrl: 'http://t', deviceId: 'd', httpClient: mockServer(failPuts: true)),
      queue: queue,
    );

    await engine.sync();

    expect(await queue.pendingCount, 1, reason: '5xx leaves entry queued');
    final row = (await db.select(db.progressRows).get()).single;
    expect(row.currentPage, 9, reason: 'queued write must not be clobbered');
  });

  test('minPullInterval: pushes every time, pulls once per interval unless forced', () async {
    final engine = SyncEngine(
      db: db,
      client: ApiClient(baseUrl: 'http://t', deviceId: 'd', httpClient: mockServer()),
      queue: queue,
      minPullInterval: const Duration(minutes: 10),
    );
    await engine.sync();
    await queue.enqueue({
      'type': 'progress',
      'payload': {'comic_id': 'c2', 'current_page': 3, 'total_pages': 20},
    });
    await engine.sync();
    expect(syncCalls, 1, reason: 'second pull inside the interval is skipped');
    expect(putCalls, ['c2'], reason: 'the outbox still drains');
    await engine.sync(force: true);
    expect(syncCalls, 2);
  });

  test('single uncontended sync does exactly one GET /sync', () async {
    final engine = SyncEngine(
      db: db,
      client: ApiClient(baseUrl: 'http://t', deviceId: 'd', httpClient: mockServer()),
      queue: queue,
    );
    await engine.sync();
    expect(syncCalls, 1, reason: 'no follow-up without a contended call');
    expect(engine.inFlightForTesting, isNull);
    expect(await db.getSyncState('last_server_time'), '5000');
  });

  // -------------------------------------------------------------------------
  // I2 — comic_metadata / series_metadata outbox entries protect local edits
  // -------------------------------------------------------------------------

  test('I2: comic_metadata in outbox protects issue payload from pull', () async {
    // Seed series + issue in mirror
    await db.applySync(SyncResponse(
      serverTime: 1,
      series: [
        {
          'id': 's1',
          'name': 'S',
          'folder_path': '/s1',
          'issue_count': 1,
          'cover_url': '/s1/cover',
          'updated_at': '2026-01-01T00:00:00Z',
          'issues': [
            {'id': 'i1', 'name': 'a.cbz', 'number': '1', 'cover_url': '/i1/cover', 'title': 'Original'},
          ],
        }
      ],
      progress: [],
      seriesIds: ['s1'],
      progressIds: [],
      queues: [],
      queueIds: [],
    ));

    // Simulate: local edit done, PATCH failed, entry queued in outbox
    await db.updateIssuePayloadLocal('i1', {'title': 'LocalEdit'});
    await queue.enqueue({
      'type': 'comic_metadata',
      'payload': {'comic_id': 'i1', 'fields': {'title': 'LocalEdit'}},
    });

    // Mock server: PATCH fails (still queued), GET /sync returns stale data
    final client = MockClient((req) async {
      if (req.method == 'PATCH') return http.Response('error', 500);
      if (req.url.path == '/sync') {
        return http.Response(
          jsonEncode({
            'server_time': 2000,
            'series': [
              {
                'id': 's1', 'name': 'S', 'folder_path': '/s1',
                'issue_count': 1, 'cover_url': '/s1/cover',
                'updated_at': '2026-01-02T00:00:00Z',
                'issues': [
                  {'id': 'i1', 'name': 'a.cbz', 'number': '1', 'cover_url': '/i1/cover', 'title': 'ServerStale'},
                ],
              }
            ],
            'progress': [],
            'series_ids': ['s1'],
            'progress_ids': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final engine = SyncEngine(
      db: db,
      client: ApiClient(baseUrl: 'http://t', deviceId: 'd', httpClient: client),
      queue: queue,
    );
    await engine.sync();

    // comic_metadata entry remains queued (PATCH failed)
    expect(await queue.pendingCount, 1, reason: 'PATCH failure keeps entry queued');

    // Local edit must survive despite stale pull
    final detail = await db.watchSeriesDetail('s1').first;
    expect(detail!.issues.single.title, 'LocalEdit',
        reason: 'comic_metadata in outbox must protect issue payload from overwrite');
  });

  test('I2: series_metadata in outbox protects series payload from pull', () async {
    // Seed series in mirror
    await db.applySync(SyncResponse(
      serverTime: 1,
      series: [
        {
          'id': 's1',
          'name': 'Original',
          'publisher': 'OldPub',
          'folder_path': '/s1',
          'issue_count': 0,
          'cover_url': '/s1/cover',
          'updated_at': '2026-01-01T00:00:00Z',
          'issues': [],
        }
      ],
      progress: [],
      seriesIds: ['s1'],
      progressIds: [],
      queues: [],
      queueIds: [],
    ));

    // Simulate: local edit done, PATCH failed, entry queued
    await db.updateSeriesPayloadLocal('s1', {'publisher': 'LocalPub'});
    await queue.enqueue({
      'type': 'series_metadata',
      'payload': {'series_id': 's1', 'fields': {'publisher': 'LocalPub'}},
    });

    final client = MockClient((req) async {
      if (req.method == 'PATCH') return http.Response('error', 500);
      if (req.url.path == '/sync') {
        return http.Response(
          jsonEncode({
            'server_time': 2000,
            'series': [
              {
                'id': 's1', 'name': 'Original', 'publisher': 'ServerStale',
                'folder_path': '/s1', 'issue_count': 0, 'cover_url': '/s1/cover',
                'updated_at': '2026-01-02T00:00:00Z', 'issues': [],
              }
            ],
            'progress': [],
            'series_ids': ['s1'],
            'progress_ids': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final engine = SyncEngine(
      db: db,
      client: ApiClient(baseUrl: 'http://t', deviceId: 'd', httpClient: client),
      queue: queue,
    );
    await engine.sync();

    expect(await queue.pendingCount, 1, reason: 'PATCH failure keeps entry queued');

    final library = await db.watchLibrary().first;
    final s1 = library.single.series;
    expect(s1.publisher, 'LocalPub',
        reason: 'series_metadata in outbox must protect series payload from overwrite');
  });

  // -------------------------------------------------------------------------
  // Self-heal — a series present in the server keep-list (series_ids) but
  // absent from the mirror must be backfilled. Delta sync only inserts the
  // *changed* set, so a series whose updated_at predates the watermark is
  // never re-inserted and never pruned; it stays invisible to mirror-backed
  // views and its detail page fails with "not in local mirror".
  // -------------------------------------------------------------------------

  test('self-heal: backfills a keep-list series missing from the mirror',
      () async {
    final client = MockClient((req) async {
      if (req.url.path == '/sync') {
        return http.Response(
          jsonEncode({
            'server_time': 7000,
            'series': [], // nothing "changed" this delta
            'progress': [],
            'series_ids': ['criminal-v01-v07'], // ...but keep-list references it
            'progress_ids': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/library/criminal-v01-v07') {
        return http.Response(
          jsonEncode({
            'id': 'criminal-v01-v07',
            'name': 'Criminal v01-v07',
            'folder_path': '/comics/Criminal v01-v07',
            'issue_count': 1,
            'cover_url': '/criminal/cover',
            'updated_at': '2020-01-01T00:00:00Z',
            'issues': [
              {'id': 'ci1', 'name': 'Criminal v01.cbz', 'number': '1', 'cover_url': '/ci1/cover'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final engine = SyncEngine(
      db: db,
      client: ApiClient(baseUrl: 'http://t', deviceId: 'd', httpClient: client),
      queue: queue,
    );
    await engine.sync();

    final detail = await db.watchSeriesDetail('criminal-v01-v07').first;
    expect(detail, isNotNull,
        reason: 'a keep-list series missing from the mirror must be backfilled');
    expect(detail!.issues.single.id, 'ci1');
  });

  test('self-heal: no backfill fetch when keep-list is already mirrored',
      () async {
    var libraryFetches = 0;
    final client = MockClient((req) async {
      if (req.url.path == '/sync') {
        return http.Response(
          jsonEncode({
            'server_time': 1,
            'series': [
              {
                'id': 's1', 'name': 'S', 'folder_path': '/s1',
                'issue_count': 0, 'cover_url': '/s1/cover',
                'updated_at': '2026-01-01T00:00:00Z', 'issues': [],
              }
            ],
            'progress': [],
            'series_ids': ['s1'],
            'progress_ids': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (req.url.path.startsWith('/library/')) {
        libraryFetches++;
        return http.Response('{}', 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('not found', 404);
    });
    final engine = SyncEngine(
      db: db,
      client: ApiClient(baseUrl: 'http://t', deviceId: 'd', httpClient: client),
      queue: queue,
    );
    await engine.sync();
    expect(libraryFetches, 0,
        reason: 's1 was in the changed set; nothing missing to backfill');
  });

  test('self-heal: one unreachable id does not abort the whole sync', () async {
    // Two missing ids; the first 404s. The batch must still heal the second
    // and the sync must complete (watermark stored).
    final client = MockClient((req) async {
      if (req.url.path == '/sync') {
        return http.Response(
          jsonEncode({
            'server_time': 9000,
            'series': [],
            'progress': [],
            'series_ids': ['gone', 'criminal-v01-v07'],
            'progress_ids': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/library/gone') {
        return http.Response('not found', 404);
      }
      if (req.url.path == '/library/criminal-v01-v07') {
        return http.Response(
          jsonEncode({
            'id': 'criminal-v01-v07', 'name': 'Criminal', 'folder_path': '/c',
            'issue_count': 0, 'cover_url': '/c/cover',
            'updated_at': '2020-01-01T00:00:00Z', 'issues': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });
    final engine = SyncEngine(
      db: db,
      client: ApiClient(baseUrl: 'http://t', deviceId: 'd', httpClient: client),
      queue: queue,
    );
    await engine.sync();

    expect(await db.getSyncState('last_server_time'), '9000',
        reason: 'sync completes despite one unreachable id');
    final healed = await db.watchSeriesDetail('criminal-v01-v07').first;
    expect(healed, isNotNull, reason: 'reachable missing id still backfilled');
  });

  test('sync requested while in flight triggers exactly one follow-up sync',
      () async {
    // Gate holds the first GET /sync open so the second sync() call is
    // deterministically "while in flight".
    final gate = Completer<void>();
    var calls = 0;
    final client = MockClient((req) async {
      if (req.url.path == '/sync') {
        calls++;
        if (calls == 1) await gate.future;
        return http.Response(
          jsonEncode({
            'server_time': 5000,
            'series': [],
            'progress': [],
            'series_ids': [],
            'progress_ids': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });
    final engine = SyncEngine(
      db: db,
      client: ApiClient(baseUrl: 'http://t', deviceId: 'd', httpClient: client),
      queue: queue,
    );

    final first = engine.sync();
    final second = engine.sync(); // in flight -> requests a follow-up
    expect(calls, lessThanOrEqualTo(1));

    gate.complete();
    await first;
    await second;

    // The follow-up was kicked fire-and-forget in whenComplete; it is the
    // current in-flight sync now. Await it to settle the counter.
    final followUp = engine.inFlightForTesting;
    expect(followUp, isNotNull,
        reason: 'a follow-up sync must start after the contended sync ends');
    await followUp;

    expect(calls, 2, reason: 'initial sync + exactly one follow-up');
    expect(engine.inFlightForTesting, isNull,
        reason: 'follow-up must not chain another follow-up');
  });

  group('progress reporting', () {
    SyncProgress state = const SyncProgress();
    final log = <SyncProgress>[];
    void sink(SyncProgress Function(SyncProgress) f) {
      state = f(state);
      log.add(state);
    }

    setUp(() {
      state = const SyncProgress();
      log.clear();
    });

    test('per-series pulls advance the series count, then done', () async {
      final engine = SyncEngine(
        db: db,
        client: _PerSeriesClient(),
        queue: queue,
        onProgress: sink,
      );
      await engine.sync();
      expect(log.first.stage, SyncStage.pushing);
      expect(
          log.where((p) => p.stage == SyncStage.fetching).map(
              (p) => (p.seriesDone, p.seriesTotal)),
          containsAllInOrder([(0, 3), (1, 3), (2, 3), (3, 3)]));
      expect(log.firstWhere((p) => p.stage == SyncStage.fetching).initial,
          isTrue, reason: 'no watermark yet');
      expect(state.stage, SyncStage.done);
      expect(state.running, isFalse);

      await engine.sync();
      expect(log.lastWhere((p) => p.stage == SyncStage.fetching).initial,
          isFalse, reason: 'watermark stored by the first pull');
    });

    test('a failed pull sets failed and still throws', () async {
      final engine = SyncEngine(
        db: db,
        client: ApiClient(
            baseUrl: 'http://t',
            deviceId: 'd',
            httpClient: MockClient((_) async => http.Response('{}', 500))),
        queue: queue,
        onProgress: sink,
      );
      await expectLater(engine.sync(), throwsA(anything));
      expect(state.stage, SyncStage.failed);
      expect(state.error, isNotNull);
    });
  });
}

class _PerSeriesClient extends ApiClient {
  _PerSeriesClient() : super(baseUrl: 'http://t', deviceId: 'd');

  @override
  Future<SyncResponse> fetchSync(
      {required int since, void Function(int done, int total)? onSeries}) async {
    for (var i = 0; i <= 3; i++) {
      onSeries?.call(i, 3);
    }
    return SyncResponse(
      serverTime: 9,
      series: const [],
      progress: const [],
      seriesIds: const [],
      progressIds: const [],
    );
  }
}
