import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/services/local_session_store.dart';
import 'package:comic_reader_app/services/local_stats.dart';

Series series(String id, {int issues = 2, int read = 0}) => Series(
      id: id, name: 'Series $id', folderPath: '', issueCount: issues,
      readCount: read, coverUrl: '/api/v1/series/$id/thumbnail',
      writer: 'Writer $id', publisher: 'Image', genres: const ['Sci-Fi'],
      createdAt: DateTime(2026), updatedAt: DateTime(2026));

LocalSession s(String series, DateTime at, {int pages = 10, int secs = 600}) =>
    LocalSession(comicId: 'c-$series', seriesId: series, startedAt: at,
        pagesRead: pages, durationS: secs);

void main() {
  // Thursday 2026-11-05 21:00 local.
  final now = DateTime(2026, 11, 5, 21);

  test('empty input gives zeroes', () {
    final st = computeLocalStats(const [], const {}, now);
    expect(st.allTime.pagesRead, 0);
    expect(st.streak.current, 0);
    expect(st.pagesPerDay, hasLength(30));
    expect(st.hourHistogram, hasLength(24));
  });

  test('periods, top series, streaks, hours and average', () {
    final lib = {'a': series('a', read: 2), 'b': series('b')};
    final st = computeLocalStats([
      s('a', DateTime(2026, 11, 5, 20)), // today
      s('a', DateTime(2026, 11, 4, 20)), // yesterday
      s('b', DateTime(2026, 11, 3, 9), pages: 30, secs: 1200), // this week (Mon 2nd)
      s('a', DateTime(2026, 10, 28, 20)), // last month
      s('b', DateTime(2026, 10, 27, 20)),
      s('b', DateTime(2026, 10, 26, 20)),
      s('b', DateTime(2026, 10, 25, 20)), // 4-day run, Oct 25–28
    ], lib, now);
    expect(st.allTime.pagesRead, 90);
    expect(st.allTime.timeReadS, 7 * 600 + 600);
    expect(st.thisWeek.pagesRead, 50);
    expect(st.thisMonth.pagesRead, 50);
    expect(st.topSeries.first.seriesId, 'b');
    expect(st.topSeries.first.name, 'Series b');
    expect(st.topSeries.first.coverUrl, '/api/v1/series/b/thumbnail');
    expect(st.topGenres.single.name, 'Sci-Fi');
    expect(st.topPublishers.single.count, 90);
    expect(st.streak.current, 3, reason: 'Nov 3, 4, 5');
    expect(st.streak.longest, 4, reason: 'Oct 25–28');
    expect(st.hourHistogram[20].pages, 60);
    expect(st.avgSessionS, (7 * 600 + 600) ~/ 7);
    expect(st.pagesPerDay.last.date, '2026-11-05');
    expect(st.pagesPerDay.last.pages, 10);
    expect(st.completionRate.completed, 1, reason: 'series a is fully read');
  });

  test('store appends and reads back per file', () async {
    final dir = await Directory.systemTemp.createTemp('sessions_');
    addTearDown(() => dir.delete(recursive: true));
    final store = LocalSessionStore('${dir.path}/src1/sessions.json');
    await store.append(s('a', DateTime(2026, 11, 5, 20)));
    await store.append(s('b', DateTime(2026, 11, 5, 21)));
    final back = await LocalSessionStore('${dir.path}/src1/sessions.json').all();
    expect(back.map((e) => e.seriesId), ['a', 'b']);
    expect(back.first.startedAt, DateTime(2026, 11, 5, 20));
  });

  test('history is newest first, paged, with names from the library', () {
    final sessions = [
      for (var d = 1; d <= 25; d++) s('a', DateTime(2026, 10, d, 20)),
    ];
    final page1 = localHistory(sessions, {'a': series('a')}, page: 1, limit: 20);
    expect(page1.total, 25);
    expect(page1.sessions, hasLength(20));
    expect(page1.sessions.first.startedAt, DateTime(2026, 10, 25, 20));
    expect(page1.sessions.first.seriesName, 'Series a');
    expect(localHistory(sessions, const {}, page: 2, limit: 20).sessions, hasLength(5));
  });

  test('concurrent appends keep every session', () async {
    final dir = await Directory.systemTemp.createTemp('sessions_');
    addTearDown(() => dir.delete(recursive: true));
    final store = LocalSessionStore('${dir.path}/sessions.json');
    await Future.wait([
      for (var i = 0; i < 10; i++) store.append(s('s$i', DateTime(2026, 11, 1, i))),
    ]);
    expect(await store.all(), hasLength(10));
  });

  test('a corrupt file is not overwritten by the next append', () async {
    final dir = await Directory.systemTemp.createTemp('sessions_');
    addTearDown(() => dir.delete(recursive: true));
    final f = File('${dir.path}/sessions.json')..writeAsStringSync('[{"comic_id": ');
    final store = LocalSessionStore(f.path);
    await expectLater(store.append(s('a', DateTime(2026))), throwsFormatException);
    expect(f.readAsStringSync(), '[{"comic_id": ');
  });
}
