import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/sync_response.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';

/// Minimal series JSON suitable for SyncResponse seeding.
Map<String, dynamic> _seriesJson(String id, Map<String, dynamic> extras,
    {List<Map<String, dynamic>> issues = const []}) =>
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

/// Minimal issue JSON suitable for SyncResponse seeding.
Map<String, dynamic> _issueJson(String id, String seriesId,
    Map<String, dynamic> extras) =>
    {
      'id': id,
      'name': extras['name'] ?? '$id.cbz',
      'number': '1',
      'cover_url': '/comics/$id/cover',
      ...extras,
    };

void main() {
  late MirrorDatabase db;

  setUp(() {
    db = MirrorDatabase(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  test('updateSeriesPayloadLocal merges fields into payload', () async {
    // Seed via applySync — the canonical write path.
    await db.applySync(SyncResponse(
      serverTime: 1,
      series: [
        _seriesJson('s1', {'name': 'Old', 'publisher': 'OldPub'}),
      ],
      progress: [],
      seriesIds: ['s1'],
      progressIds: [],
      queues: [],
      queueIds: [],
    ));

    await db.updateSeriesPayloadLocal('s1', {'publisher': 'NewPub', 'year': 1999});

    final series = await db.watchLibrary().first;
    final s1 = series.singleWhere((s) => s.series.id == 's1');
    expect(s1.series.publisher, 'NewPub');
    expect(s1.series.year, 1999);
    expect(s1.series.name, 'Old'); // untouched fields preserved
  });

  test('updateIssuePayloadLocal merges fields into issue payload', () async {
    await db.applySync(SyncResponse(
      serverTime: 1,
      series: [
        _seriesJson('s1', {'name': 'S'}, issues: [
          _issueJson('i1', 's1', {'name': 'a.cbz', 'title': 'Old'}),
        ]),
      ],
      progress: [],
      seriesIds: ['s1'],
      progressIds: [],
      queues: [],
      queueIds: [],
    ));

    await db.updateIssuePayloadLocal('i1', {'title': 'New', 'format': 'tpb'});

    final detail = await db.watchSeriesDetail('s1').first;
    final issue = detail!.issues.singleWhere((i) => i.id == 'i1');
    expect(issue.title, 'New');
    expect(issue.format, 'tpb');
  });

  test('mutators are no-ops for missing rows', () async {
    await db.updateSeriesPayloadLocal('ghost', {'name': 'x'}); // must not throw
    await db.updateIssuePayloadLocal('ghost', {'title': 'x'});
  });

  // ---------------------------------------------------------------------------
  // I2 — applySync protection for comic_metadata / series_metadata outbox edits
  // ---------------------------------------------------------------------------

  test('I2: protectedComicIds prevents issue payload overwrite in applySync',
      () async {
    // Seed initial data
    await db.applySync(SyncResponse(
      serverTime: 1,
      series: [
        _seriesJson('s1', {'name': 'S'}, issues: [
          _issueJson('i1', 's1', {'name': 'a.cbz', 'title': 'Original'}),
        ]),
      ],
      progress: [],
      seriesIds: ['s1'],
      progressIds: [],
      queues: [],
      queueIds: [],
    ));

    // Simulate a local metadata edit (comic_metadata queued in outbox)
    await db.updateIssuePayloadLocal('i1', {'title': 'LocalEdit'});

    // Confirm local edit is present
    final before = await db.watchSeriesDetail('s1').first;
    expect(before!.issues.single.title, 'LocalEdit');

    // Server sends stale data for i1 — but i1 is protected
    await db.applySync(
      SyncResponse(
        serverTime: 2,
        series: [
          _seriesJson('s1', {'name': 'S'}, issues: [
            _issueJson('i1', 's1', {'name': 'a.cbz', 'title': 'ServerStale'}),
          ]),
        ],
        progress: [],
        seriesIds: ['s1'],
        progressIds: [],
        queues: [],
        queueIds: [],
      ),
      protectedComicIds: {'i1'},
    );

    // Local edit must survive
    final after = await db.watchSeriesDetail('s1').first;
    expect(after!.issues.single.title, 'LocalEdit',
        reason: 'protectedComicIds must prevent issue payload overwrite');
  });

  test('I2: protectedSeriesIds prevents series payload overwrite in applySync',
      () async {
    // Seed initial data
    await db.applySync(SyncResponse(
      serverTime: 1,
      series: [
        _seriesJson('s1', {'name': 'Original', 'publisher': 'OldPub'}),
      ],
      progress: [],
      seriesIds: ['s1'],
      progressIds: [],
      queues: [],
      queueIds: [],
    ));

    // Simulate a local series metadata edit (series_metadata queued in outbox)
    await db.updateSeriesPayloadLocal('s1', {'publisher': 'LocalPub'});

    final before = await db.watchLibrary().first;
    expect(before.single.series.publisher, 'LocalPub');

    // Server sends stale series payload — but s1 is protected
    await db.applySync(
      SyncResponse(
        serverTime: 2,
        series: [
          _seriesJson('s1', {'name': 'Original', 'publisher': 'ServerStale'}),
        ],
        progress: [],
        seriesIds: ['s1'],
        progressIds: [],
        queues: [],
        queueIds: [],
      ),
      protectedSeriesIds: {'s1'},
    );

    // Local edit must survive
    final after = await db.watchLibrary().first;
    expect(after.single.series.publisher, 'LocalPub',
        reason: 'protectedSeriesIds must prevent series payload overwrite');
  });
}
