import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/sync_response.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';

Map<String, dynamic> seriesJson(String id,
        {String name = 'Series',
        int issueCount = 1,
        String updatedAt = '2026-01-01T00:00:00Z',
        List<Map<String, dynamic>> issues = const []}) =>
    {
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

  setUp(() async {
    db = MirrorDatabase(NativeDatabase.memory());
    await db.applySync(SyncResponse(
      serverTime: 1,
      series: [
        seriesJson('s1',
            name: 'Batman',
            issueCount: 2,
            issues: [issueJson('c1'), issueJson('c2', number: '2')]),
        seriesJson('s2', name: 'X-Men', issueCount: 1, issues: [issueJson('c3')]),
      ],
      progress: [
        {
          'comic_id': 'c1',
          'current_page': 20,
          'total_pages': 20,
          'updated_at': '2026-01-05T00:00:00Z'
        },
        {
          'comic_id': 'c2',
          'current_page': 3,
          'total_pages': 22,
          'updated_at': '2026-01-06T00:00:00Z'
        },
      ],
      seriesIds: ['s1', 's2'],
      progressIds: ['c1', 'c2'],
    ));
  });
  tearDown(() => db.close());

  test('watchLibrary computes read_count and lastReadAt from progress', () async {
    final lib = await db.watchLibrary().first;
    expect(lib, hasLength(2));
    final batman = lib.firstWhere((m) => m.series.id == 's1');
    final xmen = lib.firstWhere((m) => m.series.id == 's2');
    expect(batman.series.readCount, 1); // c1 completed, c2 in progress
    expect(batman.lastReadAt, DateTime.parse('2026-01-06T00:00:00Z'));
    expect(batman.nextUnreadIssueId, 'c2'); // c1 completed, c2 is next
    expect(xmen.series.readCount, 0);
    expect(xmen.lastReadAt, null);
    expect(xmen.nextUnreadIssueId, 'c3'); // never opened -> unread
  });

  test('watchSeriesDetail derives issue statuses', () async {
    final detail = (await db.watchSeriesDetail('s1').first)!;
    expect(detail.name, 'Batman');
    expect(detail.readCount, 1);
    expect(detail.issues, hasLength(2));
    expect(detail.issues[0].status, 'completed');
    expect(detail.issues[1].status, 'in_progress');
    expect(detail.issues[1].currentPage, 3);
  });

  test('watchSeriesDetail emits null for unknown series', () async {
    expect(await db.watchSeriesDetail('nope').first, null);
  });

  test('watchReadingList returns in-progress newest-first with seriesId',
      () async {
    await db.saveProgressLocal(comicId: 'c3', currentPage: 1, totalPages: 30);
    final list = await db.watchReadingList().first;
    // c1 is completed -> excluded. c3 written "now" -> newest.
    expect(list.map((p) => p.comicId).toList(), ['c3', 'c2']);
    expect(list[0].seriesId, 's2');
    expect(list[1].seriesId, 's1');
  });

  test('watchArcs computes read count, coverUrl fallback, and lastReadAt across all members',
      () async {
    await db.applySync(SyncResponse(
      serverTime: 2,
      series: [
        seriesJson('s1', name: 'Batman', issueCount: 2,
            issues: [issueJson('c1'), issueJson('c2', number: '2')]),
        seriesJson('s2', name: 'X-Men', issueCount: 1, issues: [issueJson('c3')]),
        seriesJson('s3', name: 'Crisis Tie-ins', issueCount: 3,
            issues: [issueJson('i0'), issueJson('i1', number: '2'), issueJson('i2', number: '3')]),
      ],
      progress: [
        {'comic_id': 'c1', 'current_page': 20, 'total_pages': 20, 'updated_at': '2026-01-05T00:00:00Z'},
        {'comic_id': 'c2', 'current_page': 3, 'total_pages': 22, 'updated_at': '2026-01-06T00:00:00Z'},
        // i0 is completed but older; i1 is only in progress but newer -> lastReadAt
        // must track the newer timestamp across ALL members, not just completed ones.
        {'comic_id': 'i0', 'current_page': 10, 'total_pages': 10, 'updated_at': '2026-01-05T00:00:00Z'},
        {'comic_id': 'i1', 'current_page': 4, 'total_pages': 10, 'updated_at': '2026-01-10T00:00:00Z'},
        // i2 has no progress row at all -> still counted as present (unread).
      ],
      seriesIds: ['s1', 's2', 's3'],
      progressIds: ['c1', 'c2', 'i0', 'i1'],
      arcs: [
        {
          'id': 'arc1',
          'name': 'Crisis',
          'self_contained': true,
          'total': 3,
          'issue_ids': ['i0', 'i1', 'i2'],
        }
      ],
      arcIds: ['arc1'],
    ));

    final arc = (await db.watchArcs().first).single;
    expect(arc.present, 3);
    expect(arc.read, 1, reason: 'only i0 is completed');
    expect(arc.coverUrl, '/comics/i0/cover',
        reason: 'arc has no image_url, falls back to lowest-position present item');
    expect(arc.lastReadAt, DateTime.parse('2026-01-10T00:00:00Z'),
        reason: 'max across all members, not just completed ones');
  });

  test('watchArcs carries description; watchArcIssues carries series name/id',
      () async {
    await db.applySync(SyncResponse(
      serverTime: 2,
      series: [
        seriesJson('s1', name: 'Batman (2016)', issueCount: 2,
            issues: [issueJson('c1'), issueJson('c2', number: '2')]),
        seriesJson('s2', name: 'X-Men', issueCount: 1, issues: [issueJson('c3')]),
      ],
      progress: const [],
      seriesIds: ['s1', 's2'],
      progressIds: ['c1', 'c2'],
      arcs: [
        {
          'id': 'arc1',
          'name': 'Crossover',
          'description': 'Heroes meet.',
          'issue_ids': ['c3', 'c1'],
        },
        {'id': 'arc2', 'name': 'No desc', 'issue_ids': ['c2']},
      ],
      arcIds: ['arc1', 'arc2'],
    ));

    final arcs = await db.watchArcs().first;
    expect(arcs.firstWhere((a) => a.id == 'arc1').description, 'Heroes meet.');
    expect(arcs.firstWhere((a) => a.id == 'arc2').description, '');

    final issues = await db.watchArcIssues('arc1').first;
    expect(issues.map((i) => i.seriesName), ['X-Men', 'Batman (2016)']);
    expect(issues.map((i) => i.seriesId), ['s2', 's1']);
  });

  test('watch streams re-emit on progress writes', () async {
    final emissions = <int>[];
    final sub = db.watchLibrary().listen((lib) {
      emissions.add(lib.firstWhere((m) => m.series.id == 's1').series.readCount);
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await db.saveProgressLocal(comicId: 'c2', currentPage: 22, totalPages: 22);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await sub.cancel();
    expect(emissions.first, 1);
    expect(emissions.last, 2);
  });
}
