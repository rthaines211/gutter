import '../models/recommendation_context.dart';
import '../models/series.dart';

class RecommendationContextBuilder {
  static RecommendationContext build({
    required List<Series> completedSeries,
    required List<InProgressEntry> inProgress,
    required List<String> topGenres,
    required List<String> topPublishers,
    required List<SessionEntry> sessions,
    required List<Series> unreadLibrary,
    required Set<String> excludedIds,
    List<String> avoidTitles = const [],
    int shortlistLimit = 30,
    int completedLimit = 5,
  }) {
    final tasteGenres = topGenres.map((g) => g.toLowerCase()).toSet();
    final tasteWriters = completedSeries
        .where((s) => s.writer != null && s.writer!.isNotEmpty)
        .map((s) => s.writer!.toLowerCase())
        .toSet();

    final ranked = unreadLibrary
        .where((s) => !excludedIds.contains(s.id))
        .map((s) {
      final genreSet = s.genres.map((g) => g.toLowerCase()).toSet();
      final overlap = genreSet.intersection(tasteGenres).length;
      final union = genreSet.union(tasteGenres).length;
      final genreScore = union == 0 ? 0.0 : overlap / union;
      final writerScore = (s.writer != null &&
              tasteWriters.contains(s.writer!.toLowerCase()))
          ? 1.0
          : 0.0;
      return _Ranked(s, genreScore + writerScore);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final shortlist = ranked
        .take(shortlistLimit)
        .map((r) => ShortlistEntry(
              seriesId: r.series.id,
              name: r.series.name,
              writer: r.series.writer,
              genres: r.series.genres,
              year: r.series.year,
            ))
        .toList();

    final completed = completedSeries
        .take(completedLimit)
        .map((s) => CompletedEntry(
              name: s.name,
              writer: s.writer,
              publisher: s.publisher,
              genres: s.genres,
            ))
        .toList();

    return RecommendationContext(
      topGenres: topGenres,
      topPublishers: topPublishers,
      completed: completed,
      inProgress: inProgress,
      sessions: sessions,
      shortlist: shortlist,
      avoidTitles: avoidTitles,
    );
  }
}

class _Ranked {
  final Series series;
  final double score;
  _Ranked(this.series, this.score);
}
