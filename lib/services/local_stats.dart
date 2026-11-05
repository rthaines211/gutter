import '../models/reading_session.dart';
import '../models/series.dart';
import '../models/stats_summary.dart';
import 'local_session_store.dart';

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _date(DateTime d) => DateTime(d.year, d.month, d.day);

/// The stats dashboard from on-device sessions, with names, covers and
/// metadata from the mirrored [library] (by series id). Weeks start Monday.
/// Issues/series finished per period aren't tracked locally and stay 0.
StatsSummary computeLocalStats(
    List<LocalSession> sessions, Map<String, Series> library, DateTime now) {
  final today = _date(now);
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  final monthStart = DateTime(today.year, today.month);

  PeriodStats period(bool Function(LocalSession) keep) {
    final picked = sessions.where(keep);
    return PeriodStats(
      pagesRead: picked.fold(0, (n, s) => n + s.pagesRead),
      issuesFinished: 0,
      seriesCompleted: 0,
      timeReadS: picked.fold(0, (n, s) => n + s.durationS),
    );
  }

  final pagesByDay = <String, int>{};
  final hours = List.filled(24, 0);
  final bySeries = <String, (int pages, int secs)>{};
  final genres = <String, int>{}, publishers = <String, int>{}, writers = <String, int>{};
  for (final s in sessions) {
    final d = _day(s.startedAt);
    pagesByDay[d] = (pagesByDay[d] ?? 0) + s.pagesRead;
    hours[s.startedAt.hour] += s.pagesRead;
    final (p, t) = bySeries[s.seriesId] ?? (0, 0);
    bySeries[s.seriesId] = (p + s.pagesRead, t + s.durationS);
    final meta = library[s.seriesId];
    if (meta == null) continue;
    for (final g in meta.genres) {
      genres[g] = (genres[g] ?? 0) + s.pagesRead;
    }
    if (meta.publisher case final pub? when pub.isNotEmpty) {
      publishers[pub] = (publishers[pub] ?? 0) + s.pagesRead;
    }
    if (meta.writer case final w? when w.isNotEmpty) {
      writers[w] = (writers[w] ?? 0) + s.pagesRead;
    }
  }

  List<NameCount> top(Map<String, int> m) => (m.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
      .take(5)
      .map((e) => NameCount(name: e.key, count: e.value))
      .toList();

  // Streaks over days with any pages; current counts back from today (or
  // yesterday, so an unread morning doesn't zero it).
  final readDays = {
    for (final e in pagesByDay.entries)
      if (e.value > 0) e.key,
  };
  var longest = 0, run = 0;
  DateTime? prev;
  for (final d in readDays.map(DateTime.parse).toList()..sort()) {
    run = prev != null && d.difference(prev).inDays == 1 ? run + 1 : 1;
    if (run > longest) longest = run;
    prev = d;
  }
  var current = 0;
  var cursor = readDays.contains(_day(today))
      ? today
      : today.subtract(const Duration(days: 1));
  while (readDays.contains(_day(cursor))) {
    current++;
    cursor = cursor.subtract(const Duration(days: 1));
  }

  final started = library.values.where((s) => s.readCount > 0).length;
  final completed = library.values
      .where((s) => s.issueCount > 0 && s.readCount >= s.issueCount)
      .length;
  final allTime = period((_) => true);

  return StatsSummary(
    allTime: allTime,
    thisWeek: period((s) => !s.startedAt.isBefore(weekStart)),
    thisMonth: period((s) => !s.startedAt.isBefore(monthStart)),
    pagesPerDay: [
      for (var i = 29; i >= 0; i--)
        DailyPages(
          date: _day(today.subtract(Duration(days: i))),
          pages: pagesByDay[_day(today.subtract(Duration(days: i)))] ?? 0,
        ),
    ],
    topGenres: top(genres),
    topPublishers: top(publishers),
    topWriters: top(writers),
    topSeries: (bySeries.entries.toList()
          ..sort((a, b) => b.value.$1.compareTo(a.value.$1)))
        .take(5)
        .map((e) => SeriesPages(
              seriesId: e.key,
              name: library[e.key]?.name ?? '',
              pages: e.value.$1,
              timeReadS: e.value.$2,
              coverUrl: library[e.key]?.coverUrl ?? '',
            ))
        .toList(),
    avgSessionS: sessions.isEmpty ? 0 : allTime.timeReadS ~/ sessions.length,
    completionRate: CompletionRate(
      started: started,
      completed: completed,
      ratePercent: started == 0 ? 0 : completed * 100 ~/ started,
    ),
    streak: StreakStats(current: current, longest: longest),
    hourHistogram: [
      for (var h = 0; h < 24; h++) HourPages(hour: h, pages: hours[h]),
    ],
  );
}

/// One page of on-device sessions, newest first, named from [library].
({List<ReadingSession> sessions, int total}) localHistory(
    List<LocalSession> sessions, Map<String, Series> library,
    {int page = 1, int limit = 20}) {
  final sorted = [...sessions]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  var i = 0;
  return (
    total: sorted.length,
    sessions: [
      for (final s in sorted.skip((page - 1) * limit).take(limit))
        ReadingSession(
          id: i++,
          comicId: s.comicId,
          seriesId: s.seriesId,
          seriesName: library[s.seriesId]?.name ?? '',
          comicName: '',
          coverUrl: library[s.seriesId]?.coverUrl ?? '',
          startedAt: s.startedAt,
          pagesRead: s.pagesRead,
          durationS: s.durationS,
        ),
    ],
  );
}
