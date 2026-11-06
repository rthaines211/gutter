import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/sync_response.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:drift/native.dart';

void main() {
  late MirrorDatabase db;

  setUp(() => db = MirrorDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('saveProgressLocal persists chapters and chaptersForComic reads them', () async {
    await db.saveProgressLocal(
      comicId: 'c1',
      currentPage: 2,
      totalPages: 10,
      chapters: [
        {'comic_id': 'c1', 'page_num': 0, 'title': 'One'},
        {'comic_id': 'c1', 'page_num': 5, 'title': 'Two'},
      ],
    );
    final got = await db.chaptersForComic('c1');
    expect(got.length, 2);
    expect(got[0]['title'], 'One');
    expect(got[1]['page_num'], 5);
  });

  test('chaptersForComic empty when none', () async {
    await db.saveProgressLocal(comicId: 'c2', currentPage: 0, totalPages: 3);
    expect(await db.chaptersForComic('c2'), isEmpty);
  });

  test('a sync whose progress has no chapters (Komga) keeps local chapters', () async {
    await db.saveProgressLocal(comicId: 'c1', currentPage: 2, totalPages: 10, chapters: [
      {'comic_id': 'c1', 'page_num': 5, 'title': 'Two'},
    ]);
    await db.applySync(const SyncResponse(
      serverTime: 1, series: [], seriesIds: [], progressIds: ['c1'],
      progress: [
        {'comic_id': 'c1', 'current_page': 4, 'total_pages': 10, 'updated_at': 'x'},
      ],
    ));
    expect((await db.chaptersForComic('c1')).single['title'], 'Two');
  });

  test('a sync that sends chapters still replaces them', () async {
    await db.saveProgressLocal(comicId: 'c1', currentPage: 2, totalPages: 10, chapters: [
      {'comic_id': 'c1', 'page_num': 5, 'title': 'Two'},
    ]);
    await db.applySync(const SyncResponse(
      serverTime: 1, series: [], seriesIds: [], progressIds: ['c1'],
      progress: [
        {'comic_id': 'c1', 'current_page': 4, 'total_pages': 10, 'updated_at': 'x', 'chapters': []},
      ],
    ));
    expect(await db.chaptersForComic('c1'), isEmpty);
  });
}
