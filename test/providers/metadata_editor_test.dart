import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comic_reader_app/models/sync_response.dart';
import 'package:comic_reader_app/providers/metadata_editor.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:comic_reader_app/services/sync_queue.dart';

// ---------------------------------------------------------------------------
// Seed helpers (mirror mirror_metadata_test.dart pattern)
// ---------------------------------------------------------------------------

Map<String, dynamic> _seriesJson(
  String id,
  Map<String, dynamic> extras, {
  List<Map<String, dynamic>> issues = const [],
}) =>
    {
      'id': id,
      'name': extras['name'] ?? id,
      'folder_path': '/comics/$id',
      'issue_count': issues.length,
      'cover_url': '/library/$id/cover',
      'updated_at': '2026-01-01T00:00:00Z',
      'issues': issues,
      ...extras,
    };

Map<String, dynamic> _issueJson(
  String id,
  String seriesId,
  Map<String, dynamic> extras,
) =>
    {
      'id': id,
      'name': extras['name'] ?? '$id.cbz',
      'number': '1',
      'cover_url': '/comics/$id/cover',
      ...extras,
    };

// ---------------------------------------------------------------------------
// Client helpers (mirror sync_queue_drainer_metadata_test.dart pattern)
// ---------------------------------------------------------------------------

void main() {
  late Directory tmp;
  late MirrorDatabase db;
  late SyncQueue queue;
  late List<http.Request> requests;

  setUp(() async {
    await AppLogger.init(logDirFactory: () async => null);
    tmp = Directory.systemTemp.createTempSync('metadata_editor_test');
    db = MirrorDatabase(NativeDatabase.memory());
    queue = SyncQueue(queuePath: '${tmp.path}/sync_queue.json');
    requests = [];

    // Seed: series s1 + issue i1
    await db.applySync(SyncResponse(
      serverTime: 1,
      series: [
        _seriesJson(
          's1',
          {'name': 'Old Series', 'publisher': 'OldPub'},
          issues: [
            _issueJson('i1', 's1', {'name': 'a.cbz', 'title': 'Old'}),
          ],
        ),
      ],
      progress: [],
      seriesIds: ['s1'],
      progressIds: [],
      queues: [],
      queueIds: [],
    ));
  });

  tearDown(() async {
    AppLogger.resetForTest();
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  ApiClient okClient() => ApiClient(
        baseUrl: 'http://x',
        deviceId: 't',
        httpClient: MockClient((req) async {
          requests.add(req);
          return http.Response('', 204);
        }),
      );

  ApiClient failingClient() => ApiClient(
        baseUrl: 'http://x',
        deviceId: 't',
        httpClient: MockClient((req) async {
          requests.add(req);
          throw const SocketException('network error');
        }),
      );

  // -------------------------------------------------------------------------

  test('saveIssue writes mirror first, then PATCHes', () async {
    final editor = MetadataEditor(db: db, client: okClient(), queue: queue);
    await editor.saveIssue('i1', {'title': 'New', 'format': 'tpb'});

    // Mirror updated (regardless of network):
    final detail = await db.watchSeriesDetail('s1').first;
    expect(detail!.issues.single.title, 'New');
    expect(detail.issues.single.format, 'tpb');

    // Server was called at the correct path:
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/comics/i1/metadata');

    // Nothing queued (PATCH succeeded):
    expect(await queue.pendingCount, 0);
  });

  test('saveIssue enqueues to outbox when PATCH fails', () async {
    final editor =
        MetadataEditor(db: db, client: failingClient(), queue: queue);
    await editor.saveIssue('i1', {'title': 'New'});

    // Mirror still updated:
    final detail = await db.watchSeriesDetail('s1').first;
    expect(detail!.issues.single.title, 'New');

    // One outbox entry:
    expect(await queue.pendingCount, 1);
    final entry = (await queue.readAll()).single;
    expect(entry['type'], 'comic_metadata');
    expect(entry['payload']['comic_id'], 'i1');
    expect(entry['payload']['fields']['title'], 'New');
  });

  test('saveSeries mirrors then PATCHes with series payload keys', () async {
    final editor = MetadataEditor(db: db, client: okClient(), queue: queue);
    await editor.saveSeries('s1', {'publisher': 'P', 'year': 2000});

    final series = await db.watchLibrary().first;
    expect(series.single.series.publisher, 'P');
    expect(series.single.series.year, 2000);

    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/series/s1/metadata');

    expect(await queue.pendingCount, 0);
  });
}
