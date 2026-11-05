import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/sync_response.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';

MirrorDatabase _memDb() => MirrorDatabase(NativeDatabase.memory());

void main() {
  test('applySync stores arcs, computes present, and prunes', () async {
    final db = _memDb();
    addTearDown(db.close);

    // One series with one issue so present-count has something to join to.
    final resp = SyncResponse(
      serverTime: 0,
      series: [
        {'id': 's', 'name': 'S', 'folder_path': '/p/s', 'updated_at': '',
         'issues': [
           {'id': 'iss', 'name': 'iss', 'number': '1', 'status': 'unread'}
         ]}
      ],
      progress: const [],
      seriesIds: const ['s'],
      progressIds: const [],
      arcs: [
        {'id': 'arc1', 'name': 'Arc One', 'image_url': 'img',
         'self_contained': true, 'total': 3, 'issue_ids': ['iss']}
      ],
      arcIds: const ['arc1'],
    );
    await db.applySync(resp);

    var arcs = await db.watchArcs().first;
    expect(arcs.length, 1);
    expect(arcs[0].present, 1);
    expect(arcs[0].total, 3);
    expect(arcs[0].selfContained, true);

    final issues = await db.watchArcIssues('arc1').first;
    expect(issues.map((e) => e.id).toList(), ['iss']);

    // Prune: arc absent from next sync → removed.
    await db.applySync(SyncResponse(
      serverTime: 0, series: const [], progress: const [],
      seriesIds: const ['s'], progressIds: const [],
      arcs: const [], arcIds: const [],
    ));
    arcs = await db.watchArcs().first;
    expect(arcs, isEmpty);
  });

  test('watchArcs orders self-contained first, then name, null last', () async {
    final db = _memDb();
    addTearDown(db.close);

    await db.applySync(SyncResponse(
      serverTime: 0,
      series: const [],
      progress: const [],
      seriesIds: const [],
      progressIds: const [],
      arcs: [
        // deliberately inserted out of final order
        {'id': 'c', 'name': 'Charlie', 'self_contained': false, 'total': 1, 'issue_ids': const []},
        {'id': 'n', 'name': 'Delta', 'self_contained': null, 'total': 1, 'issue_ids': const []},
        {'id': 'b', 'name': 'Bravo', 'self_contained': true, 'total': 1, 'issue_ids': const []},
        {'id': 'a', 'name': 'Alpha', 'self_contained': true, 'total': 1, 'issue_ids': const []},
      ],
      arcIds: const ['a', 'b', 'c', 'n'],
    ));

    final arcs = await db.watchArcs().first;
    // self-contained (Alpha, Bravo by name) first, then false (Charlie), then null (Delta).
    expect(arcs.map((e) => e.id).toList(), ['a', 'b', 'c', 'n']);
  });

  test('watchArcIssues: current_page 0 with a progress row is unread, not in_progress',
      () async {
    final db = _memDb();
    addTearDown(db.close);

    await db.applySync(SyncResponse(
      serverTime: 0,
      series: [
        {'id': 's', 'name': 'S', 'folder_path': '/p/s', 'updated_at': '',
         'issues': [
           {'id': 'i0', 'name': 'i0', 'number': '1', 'status': 'unread'},
           {'id': 'i1', 'name': 'i1', 'number': '2', 'status': 'unread'},
           {'id': 'i2', 'name': 'i2', 'number': '3', 'status': 'unread'},
         ]}
      ],
      progress: const [
        {'comic_id': 'i0', 'current_page': 0, 'total_pages': 10, 'updated_at': ''}, // opened, not read
        {'comic_id': 'i1', 'current_page': 4, 'total_pages': 10, 'updated_at': ''}, // in progress
        {'comic_id': 'i2', 'current_page': 10, 'total_pages': 10, 'updated_at': ''}, // done
      ],
      seriesIds: const ['s'],
      progressIds: const ['i0', 'i1', 'i2'],
      arcs: [
        {'id': 'arc1', 'name': 'Arc', 'total': 3, 'issue_ids': const ['i0', 'i1', 'i2']}
      ],
      arcIds: const ['arc1'],
    ));

    final issues = await db.watchArcIssues('arc1').first;
    expect(issues.map((e) => e.status).toList(),
        ['unread', 'in_progress', 'completed']);
  });
}
