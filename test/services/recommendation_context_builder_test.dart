import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/recommendation_context.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/services/recommendation_context_builder.dart';

Series series({
  required String id,
  required String name,
  String? writer,
  String? publisher,
  List<String> genres = const [],
  int? year,
  int issueCount = 5,
  int readCount = 0,
}) {
  return Series(
    id: id,
    name: name,
    folderPath: '',
    issueCount: issueCount,
    readCount: readCount,
    coverUrl: '',
    writer: writer,
    publisher: publisher,
    genres: genres,
    year: year,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

void main() {
  group('RecommendationContextBuilder', () {
    test('ranks unread series by Jaccard overlap with taste', () {
      final completed = [
        series(id: 'c1', name: 'Saga', writer: 'BKV',
            genres: ['Sci-Fi', 'Drama']),
      ];
      final unread = [
        series(id: 'u1', name: 'Paper Girls', writer: 'BKV',
            genres: ['Sci-Fi']),
        series(id: 'u2', name: 'Bone', writer: 'Jeff Smith',
            genres: ['Fantasy']),
        series(id: 'u3', name: 'East of West', writer: 'Jonathan Hickman',
            genres: ['Sci-Fi', 'Drama']),
      ];
      final ctx = RecommendationContextBuilder.build(
        completedSeries: completed,
        inProgress: const [],
        topGenres: const ['Sci-Fi', 'Drama'],
        topPublishers: const [],
        sessions: const [],
        unreadLibrary: unread,
        excludedIds: const {},
        shortlistLimit: 10,
      );
      final ids = ctx.shortlist.map((e) => e.seriesId).toList();
      expect(ids.first, anyOf('u1', 'u3'));
      expect(ids.last, 'u2');
    });

    test('respects shortlist limit and excludes IDs', () {
      final unread = List.generate(
        20,
        (i) => series(id: 'u$i', name: 'Series $i', genres: const ['Sci-Fi']),
      );
      final ctx = RecommendationContextBuilder.build(
        completedSeries: const [],
        inProgress: const [],
        topGenres: const ['Sci-Fi'],
        topPublishers: const [],
        sessions: const [],
        unreadLibrary: unread,
        excludedIds: const {'u0', 'u1', 'u2'},
        shortlistLimit: 5,
      );
      expect(ctx.shortlist.length, 5);
      expect(ctx.shortlist.any((e) => e.seriesId == 'u0'), isFalse);
      expect(ctx.shortlist.any((e) => e.seriesId == 'u1'), isFalse);
    });

    test('passes through pre-built in-progress and session entries', () {
      final ctx = RecommendationContextBuilder.build(
        completedSeries: const [],
        inProgress: const [InProgressEntry(name: 'Sandman', progressPct: 50)],
        topGenres: const [],
        topPublishers: const [],
        sessions: const [SessionEntry(seriesName: 'Saga', daysAgo: 2)],
        unreadLibrary: const [],
        excludedIds: const {},
        shortlistLimit: 10,
      );
      expect(ctx.inProgress.single.name, 'Sandman');
      expect(ctx.inProgress.single.progressPct, 50);
      expect(ctx.sessions.single.seriesName, 'Saga');
      expect(ctx.sessions.single.daysAgo, 2);
    });

    test('passes avoidTitles through', () {
      final ctx = RecommendationContextBuilder.build(
        completedSeries: const [],
        inProgress: const [],
        topGenres: const [],
        topPublishers: const [],
        sessions: const [],
        unreadLibrary: const [],
        excludedIds: const {},
        avoidTitles: const ['Locke & Key'],
        shortlistLimit: 10,
      );
      expect(ctx.avoidTitles, ['Locke & Key']);
    });
  });
}
