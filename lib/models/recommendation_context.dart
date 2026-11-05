class CompletedEntry {
  final String name;
  final String? writer;
  final String? publisher;
  final List<String> genres;
  const CompletedEntry({
    required this.name,
    this.writer,
    this.publisher,
    this.genres = const [],
  });
  Map<String, dynamic> toJson() => {
        'name': name,
        if (writer != null) 'writer': writer,
        if (publisher != null) 'publisher': publisher,
        'genres': genres,
      };
}

class InProgressEntry {
  final String name;
  final int progressPct;
  const InProgressEntry({required this.name, required this.progressPct});
  Map<String, dynamic> toJson() =>
      {'name': name, 'progress_pct': progressPct};
}

class SessionEntry {
  final String seriesName;
  final int daysAgo;
  const SessionEntry({required this.seriesName, required this.daysAgo});
  Map<String, dynamic> toJson() =>
      {'series_name': seriesName, 'days_ago': daysAgo};
}

class ShortlistEntry {
  final String seriesId;
  final String name;
  final String? writer;
  final List<String> genres;
  final int? year;
  const ShortlistEntry({
    required this.seriesId,
    required this.name,
    this.writer,
    this.genres = const [],
    this.year,
  });
  Map<String, dynamic> toJson() => {
        'series_id': seriesId,
        'name': name,
        if (writer != null) 'writer': writer,
        'genres': genres,
        if (year != null) 'year': year,
      };
}

class RecommendationContext {
  final List<String> topGenres;
  final List<String> topPublishers;
  final List<CompletedEntry> completed;
  final List<InProgressEntry> inProgress;
  final List<SessionEntry> sessions;
  final List<ShortlistEntry> shortlist;
  final List<String> avoidTitles;

  const RecommendationContext({
    required this.topGenres,
    required this.topPublishers,
    required this.completed,
    required this.inProgress,
    required this.sessions,
    required this.shortlist,
    this.avoidTitles = const [],
  });

  Map<String, dynamic> toJson() => {
        'top_genres': topGenres,
        'top_publishers': topPublishers,
        'completed': completed.map((e) => e.toJson()).toList(),
        'in_progress': inProgress.map((e) => e.toJson()).toList(),
        'sessions': sessions.map((e) => e.toJson()).toList(),
        'shortlist': shortlist.map((e) => e.toJson()).toList(),
        'avoid_titles': avoidTitles,
      };
}
