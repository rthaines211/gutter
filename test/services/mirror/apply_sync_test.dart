import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/reading_queue.dart';
import 'package:comic_reader_app/models/sync_response.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';

Map<String, dynamic> seriesJson(String id, {String name = 'Series', int issueCount = 1, String updatedAt = '2026-01-01T00:00:00Z', List<Map<String, dynamic>> issues = const []}) => {
      'id': id,
      'name': name,
      'folder_path': '/comics/$id',
      'issue_count': issueCount,
      'cover_url': '/library/$id/cover',
      'writer': 'Tom King',
      'penciller': '',
      'publisher': 'DC',
      'genres': ['Action'],
      'year': 2020,
      'updated_at': updatedAt,
      'issues': issues,
    };

Map<String, dynamic> issueJson(String id, {String number = '1'}) => {
      'id': id,
      'name': 'Issue $number.cbz',
      'number': number,
      'cover_url': '/comics/$id/cover',
    };

void main() {
  late MirrorDatabase db;

  setUp(() => db = MirrorDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('upserts series, issues, and progress', () async {
    await db.applySync(SyncResponse(
      serverTime: 1,
      series: [
        seriesJson('s1', issues: [issueJson('c1'), issueJson('c2', number: '2')])
      ],
      progress: [
        {'comic_id': 'c1', 'current_page': 20, 'total_pages': 20, 'updated_at': '2026-01-02T00:00:00Z'}
      ],
      seriesIds: ['s1'],
      progressIds: ['c1'],
    ));

    expect((await db.select(db.seriesRows).get()).length, 1);
    expect((await db.select(db.issueRows).get()).length, 2);
    expect((await db.select(db.progressRows).get()).single.currentPage, 20);
  });

  test('second sync replaces issues and prunes deleted series/progress', () async {
    await db.applySync(SyncResponse(
      serverTime: 1,
      series: [
        seriesJson('s1', issues: [issueJson('c1')]),
        seriesJson('s2', issues: [issueJson('c9')]),
      ],
      progress: [
        {'comic_id': 'c1', 'current_page': 5, 'total_pages': 20, 'updated_at': '2026-01-02T00:00:00Z'}
      ],
      seriesIds: ['s1', 's2'],
      progressIds: ['c1'],
    ));

    // s2 deleted server-side; c1 progress deleted (marked unread); s1 unchanged (not in delta).
    await db.applySync(SyncResponse(
      serverTime: 2,
      series: [],
      progress: [],
      seriesIds: ['s1'],
      progressIds: [],
    ));

    final series = await db.select(db.seriesRows).get();
    expect(series.single.id, 's1');
    expect((await db.select(db.issueRows).get()).single.id, 'c1');
    expect(await db.select(db.progressRows).get(), isEmpty);
  });

  test('protected (queued) progress is not overwritten or pruned', () async {
    await db.saveProgressLocal(comicId: 'c1', currentPage: 9, totalPages: 20);

    await db.applySync(
      SyncResponse(
        serverTime: 1,
        series: [],
        progress: [
          {'comic_id': 'c1', 'current_page': 2, 'total_pages': 20, 'updated_at': '2020-01-01T00:00:00Z'}
        ],
        seriesIds: [],
        progressIds: [],
      ),
      protectedComicIds: {'c1'},
    );

    final row = (await db.select(db.progressRows).get()).single;
    expect(row.currentPage, 9, reason: 'queued local write must win until flushed');
  });

  test('series upsert preserves coverSyncedAt', () async {
    await db.applySync(SyncResponse(
      serverTime: 1,
      series: [seriesJson('s1')],
      progress: [],
      seriesIds: ['s1'],
      progressIds: [],
    ));
    await db.markCoverSynced('s1', '2026-01-01T00:00:00Z');

    await db.applySync(SyncResponse(
      serverTime: 2,
      series: [seriesJson('s1', updatedAt: '2026-02-01T00:00:00Z')],
      progress: [],
      seriesIds: ['s1'],
      progressIds: [],
    ));

    final row = (await db.select(db.seriesRows).get()).single;
    expect(row.updatedAt, '2026-02-01T00:00:00Z');
    expect(row.coverSyncedAt, '2026-01-01T00:00:00Z');
  });

  test('applySync stores arc source, publisher, and years', () async {
    await db.applySync(SyncResponse(
      serverTime: 1,
      series: [],
      progress: [],
      seriesIds: [],
      progressIds: [],
      arcs: [
        {
          'id': 'arc1',
          'name': 'Crisis',
          'source': 'comicvine',
          'publisher': 'DC',
          'start_year': 1985,
          'end_year': 1986,
          'total': 12,
          'issue_ids': <String>[],
        }
      ],
      arcIds: ['arc1'],
    ));

    final row = (await db.select(db.arcRows).get()).single;
    expect(row.source, 'comicvine');
    expect(row.publisher, 'DC');
    expect(row.startYear, 1985);
    expect(row.endYear, 1986);
  });

  test('applySync defaults arc source/publisher/years when absent', () async {
    await db.applySync(SyncResponse(
      serverTime: 1,
      series: [],
      progress: [],
      seriesIds: [],
      progressIds: [],
      arcs: [
        {'id': 'arc2', 'name': 'No Metadata', 'total': 1, 'issue_ids': <String>[]}
      ],
      arcIds: ['arc2'],
    ));

    final row = (await db.select(db.arcRows).get()).single;
    expect(row.source, 'mylar');
    expect(row.publisher, '');
    expect(row.startYear, 0);
    expect(row.endYear, 0);
  });

  test('sync state round-trips', () async {
    expect(await db.getSyncState('last_server_time'), null);
    await db.setSyncState('last_server_time', '123');
    await db.setSyncState('last_server_time', '456');
    expect(await db.getSyncState('last_server_time'), '456');
  });

  test('servers without queues (Komga) keep local queues', () async {
    await db.upsertQueueLocal(ReadingQueue(
        id: 'q1', name: 'Next', seriesIds: const [],
        createdAt: DateTime(2026), updatedAt: DateTime(2026)));
    await db.applySync(const SyncResponse(
        serverTime: 1, series: [], progress: [], seriesIds: [], progressIds: [],
        serverHasQueues: false));
    expect((await db.watchQueues().first).map((q) => q.id), ['q1']);

    await db.applySync(const SyncResponse(
        serverTime: 2, series: [], progress: [], seriesIds: [], progressIds: []));
    expect(await db.watchQueues().first, isEmpty);
  });

  test('seriesIdForComic finds the issue\'s series', () async {
    await db.applySync(SyncResponse(
        serverTime: 1, series: [seriesJson('s1', issues: [issueJson('c1')])],
        progress: const [], seriesIds: const ['s1'], progressIds: const []));
    expect(await db.seriesIdForComic('c1'), 's1');
    expect(await db.seriesIdForComic('nope'), isNull);
  });
}
