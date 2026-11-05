import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/stats_summary.dart';

void main() {
  group('StatsSummary new fields', () {
    test('parses all new fields when present', () {
      final json = {
        'all_time': {'pages_read': 0, 'issues_finished': 0, 'series_completed': 0, 'time_read_s': 0},
        'this_week': {'pages_read': 0, 'time_read_s': 0},
        'this_month': {'pages_read': 0, 'time_read_s': 0},
        'pages_per_day': [],
        'top_genres': [],
        'top_publishers': [],
        'top_series': [
          {'series_id': 'abc', 'name': 'A', 'pages': 100, 'time_read_s': 600, 'cover_url': '/library/abc/cover'},
        ],
        'top_writers': [
          {'name': 'Tom King', 'count': 5},
        ],
        'avg_session_s': 95,
        'completion_rate': {'started': 7, 'completed': 3, 'rate_percent': 42},
        'streak': {'current': 4, 'longest': 12},
        'hour_histogram': [
          {'hour': 0, 'pages': 0},
          {'hour': 22, 'pages': 30},
        ],
      };

      final s = StatsSummary.fromJson(json);
      expect(s.topSeries, hasLength(1));
      expect(s.topSeries.single.seriesId, 'abc');
      expect(s.topSeries.single.name, 'A');
      expect(s.topSeries.single.pages, 100);
      expect(s.topSeries.single.coverUrl, '/library/abc/cover');

      expect(s.topWriters.single.name, 'Tom King');
      expect(s.avgSessionS, 95);
      expect(s.completionRate.started, 7);
      expect(s.completionRate.ratePercent, 42);
      expect(s.streak.current, 4);
      expect(s.streak.longest, 12);
      expect(s.hourHistogram, hasLength(2));
      expect(s.hourHistogram[1].hour, 22);
      expect(s.hourHistogram[1].pages, 30);
    });

    test('defaults safely when new fields missing', () {
      final json = {
        'all_time': {'pages_read': 0, 'issues_finished': 0, 'series_completed': 0, 'time_read_s': 0},
        'this_week': {'pages_read': 0, 'time_read_s': 0},
        'this_month': {'pages_read': 0, 'time_read_s': 0},
        'pages_per_day': [],
        'top_genres': [],
        'top_publishers': [],
      };

      final s = StatsSummary.fromJson(json);
      expect(s.topSeries, isEmpty);
      expect(s.topWriters, isEmpty);
      expect(s.avgSessionS, 0);
      expect(s.completionRate.started, 0);
      expect(s.completionRate.completed, 0);
      expect(s.completionRate.ratePercent, 0);
      expect(s.streak.current, 0);
      expect(s.streak.longest, 0);
      expect(s.hourHistogram, isEmpty);
    });
  });

  group('StatsSummary existing fields', () {
    test('fromJson parses all sections', () {
      final summary = StatsSummary.fromJson({
        'all_time': {'pages_read': 12450, 'issues_finished': 234, 'series_completed': 18, 'time_read_s': 432000},
        'this_week': {'pages_read': 180, 'issues_finished': 6, 'time_read_s': 7200},
        'this_month': {'pages_read': 650, 'issues_finished': 22, 'time_read_s': 28800},
        'pages_per_day': [{'date': '2026-04-15', 'pages': 45}, {'date': '2026-04-16', 'pages': 0}],
        'top_genres': [{'name': 'Superhero', 'count': 95}],
        'top_publishers': [{'name': 'Marvel', 'count': 80}],
      });
      expect(summary.allTime.pagesRead, 12450);
      expect(summary.thisWeek.pagesRead, 180);
      expect(summary.pagesPerDay.length, 2);
      expect(summary.topPublishers.first.name, 'Marvel');
    });

    test('fromJson handles empty data', () {
      final summary = StatsSummary.fromJson({
        'all_time': {'pages_read': 0, 'issues_finished': 0, 'series_completed': 0, 'time_read_s': 0},
        'this_week': {'pages_read': 0, 'time_read_s': 0},
        'this_month': {'pages_read': 0, 'time_read_s': 0},
        'pages_per_day': [], 'top_genres': [], 'top_publishers': [],
      });
      expect(summary.allTime.pagesRead, 0);
      expect(summary.pagesPerDay, isEmpty);
    });

    test('PeriodStats.formattedTime formats correctly', () {
      expect(PeriodStats(pagesRead: 0, issuesFinished: 0, seriesCompleted: 0, timeReadS: 7380).formattedTime, '2h 3m');
      expect(PeriodStats(pagesRead: 0, issuesFinished: 0, seriesCompleted: 0, timeReadS: 300).formattedTime, '5m');
    });
  });
}
