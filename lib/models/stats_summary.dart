class PeriodStats {
  final int pagesRead;
  final int issuesFinished;
  final int seriesCompleted;
  final int timeReadS;

  const PeriodStats({
    required this.pagesRead,
    required this.issuesFinished,
    required this.seriesCompleted,
    required this.timeReadS,
  });

  factory PeriodStats.fromJson(Map<String, dynamic> json) {
    return PeriodStats(
      pagesRead: json['pages_read'] as int? ?? 0,
      issuesFinished: json['issues_finished'] as int? ?? 0,
      seriesCompleted: json['series_completed'] as int? ?? 0,
      timeReadS: json['time_read_s'] as int? ?? 0,
    );
  }

  String get formattedTime {
    final hours = timeReadS ~/ 3600;
    final minutes = (timeReadS % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}

class DailyPages {
  final String date;
  final int pages;

  const DailyPages({required this.date, required this.pages});

  factory DailyPages.fromJson(Map<String, dynamic> json) {
    return DailyPages(
      date: json['date'] as String,
      pages: json['pages'] as int? ?? 0,
    );
  }
}

class NameCount {
  final String name;
  final int count;

  const NameCount({required this.name, required this.count});

  factory NameCount.fromJson(Map<String, dynamic> json) {
    return NameCount(
      name: json['name'] as String,
      count: json['count'] as int? ?? 0,
    );
  }
}

class SeriesPages {
  final String seriesId;
  final String name;
  final int pages;
  final int timeReadS;
  final String coverUrl;

  const SeriesPages({
    required this.seriesId,
    required this.name,
    required this.pages,
    required this.timeReadS,
    required this.coverUrl,
  });

  factory SeriesPages.fromJson(Map<String, dynamic> json) {
    return SeriesPages(
      seriesId: json['series_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      pages: json['pages'] as int? ?? 0,
      timeReadS: json['time_read_s'] as int? ?? 0,
      coverUrl: json['cover_url'] as String? ?? '',
    );
  }

  String get formattedTime {
    final hours = timeReadS ~/ 3600;
    final minutes = (timeReadS % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}

class HourPages {
  final int hour;
  final int pages;

  const HourPages({required this.hour, required this.pages});

  factory HourPages.fromJson(Map<String, dynamic> json) {
    return HourPages(
      hour: json['hour'] as int? ?? 0,
      pages: json['pages'] as int? ?? 0,
    );
  }
}

class StreakStats {
  final int current;
  final int longest;

  const StreakStats({required this.current, required this.longest});

  factory StreakStats.fromJson(Map<String, dynamic> json) {
    return StreakStats(
      current: json['current'] as int? ?? 0,
      longest: json['longest'] as int? ?? 0,
    );
  }
}

class CompletionRate {
  final int started;
  final int completed;
  final int ratePercent;

  const CompletionRate({
    required this.started,
    required this.completed,
    required this.ratePercent,
  });

  factory CompletionRate.fromJson(Map<String, dynamic> json) {
    return CompletionRate(
      started: json['started'] as int? ?? 0,
      completed: json['completed'] as int? ?? 0,
      ratePercent: json['rate_percent'] as int? ?? 0,
    );
  }
}

class StatsSummary {
  final PeriodStats allTime;
  final PeriodStats thisWeek;
  final PeriodStats thisMonth;
  final List<DailyPages> pagesPerDay;
  final List<NameCount> topGenres;
  final List<NameCount> topPublishers;
  final List<SeriesPages> topSeries;
  final List<NameCount> topWriters;
  final int avgSessionS;
  final CompletionRate completionRate;
  final StreakStats streak;
  final List<HourPages> hourHistogram;

  const StatsSummary({
    required this.allTime,
    required this.thisWeek,
    required this.thisMonth,
    required this.pagesPerDay,
    required this.topGenres,
    required this.topPublishers,
    required this.topSeries,
    required this.topWriters,
    required this.avgSessionS,
    required this.completionRate,
    required this.streak,
    required this.hourHistogram,
  });

  factory StatsSummary.fromJson(Map<String, dynamic> json) {
    return StatsSummary(
      allTime: PeriodStats.fromJson(json['all_time'] as Map<String, dynamic>),
      thisWeek: PeriodStats.fromJson(json['this_week'] as Map<String, dynamic>),
      thisMonth: PeriodStats.fromJson(json['this_month'] as Map<String, dynamic>),
      pagesPerDay: (json['pages_per_day'] as List<dynamic>? ?? [])
          .map((e) => DailyPages.fromJson(e as Map<String, dynamic>))
          .toList(),
      topGenres: (json['top_genres'] as List<dynamic>? ?? [])
          .map((e) => NameCount.fromJson(e as Map<String, dynamic>))
          .toList(),
      topPublishers: (json['top_publishers'] as List<dynamic>? ?? [])
          .map((e) => NameCount.fromJson(e as Map<String, dynamic>))
          .toList(),
      topSeries: (json['top_series'] as List<dynamic>? ?? [])
          .map((e) => SeriesPages.fromJson(e as Map<String, dynamic>))
          .toList(),
      topWriters: (json['top_writers'] as List<dynamic>? ?? [])
          .map((e) => NameCount.fromJson(e as Map<String, dynamic>))
          .toList(),
      avgSessionS: json['avg_session_s'] as int? ?? 0,
      completionRate: CompletionRate.fromJson(
          (json['completion_rate'] as Map<String, dynamic>?) ?? const {}),
      streak: StreakStats.fromJson(
          (json['streak'] as Map<String, dynamic>?) ?? const {}),
      hourHistogram: (json['hour_histogram'] as List<dynamic>? ?? [])
          .map((e) => HourPages.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
