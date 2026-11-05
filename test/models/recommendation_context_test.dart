import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/recommendation_context.dart';

void main() {
  group('RecommendationContext', () {
    test('toJson includes all sections', () {
      final ctx = RecommendationContext(
        topGenres: ['Sci-Fi', 'Horror'],
        topPublishers: ['Image'],
        completed: const [
          CompletedEntry(name: 'Saga', writer: 'BKV', publisher: 'Image',
              genres: ['Sci-Fi']),
        ],
        inProgress: const [
          InProgressEntry(name: 'Sandman', progressPct: 42),
        ],
        sessions: const [
          SessionEntry(seriesName: 'Saga', daysAgo: 1),
        ],
        shortlist: const [
          ShortlistEntry(seriesId: 's1', name: 'Paper Girls',
              writer: 'BKV', genres: ['Sci-Fi'], year: 2015),
        ],
        avoidTitles: const ['Locke & Key'],
      );
      final json = ctx.toJson();
      expect(json['top_genres'], ['Sci-Fi', 'Horror']);
      expect((json['shortlist'] as List).single['series_id'], 's1');
      expect(json['avoid_titles'], ['Locke & Key']);
    });

    test('omits null optional fields from JSON', () {
      final completed = const CompletedEntry(name: 'X').toJson();
      expect(completed.containsKey('writer'), isFalse);
      expect(completed.containsKey('publisher'), isFalse);

      final shortlist = const ShortlistEntry(seriesId: 'x', name: 'Y').toJson();
      expect(shortlist.containsKey('writer'), isFalse);
      expect(shortlist.containsKey('year'), isFalse);
    });
  });
}
