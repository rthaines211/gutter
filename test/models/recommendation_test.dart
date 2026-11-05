import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/recommendation.dart';

void main() {
  group('Recommendation', () {
    test('round-trips through toJson/fromJson', () {
      const rec = Recommendation(
        seriesId: 'abc123',
        title: 'Saga, Vol 4',
        creator: 'Brian K. Vaughan',
        reasoning: 'You finished Y: The Last Man recently.',
        isInLibrary: true,
      );
      final hydrated = Recommendation.fromJson(rec.toJson());
      expect(hydrated.seriesId, 'abc123');
      expect(hydrated.title, 'Saga, Vol 4');
      expect(hydrated.creator, 'Brian K. Vaughan');
      expect(hydrated.reasoning, 'You finished Y: The Last Man recently.');
      expect(hydrated.isInLibrary, true);
    });

    test('handles unowned pick (null seriesId, isInLibrary false)', () {
      const rec = Recommendation(
        seriesId: null,
        title: 'Trees',
        creator: 'Warren Ellis',
        reasoning: 'Similar atmosphere to Black Monday Murders.',
        isInLibrary: false,
      );
      final hydrated = Recommendation.fromJson(rec.toJson());
      expect(hydrated.seriesId, null);
      expect(hydrated.isInLibrary, false);
    });

    test('fromJson defaults is_in_library to false when key is missing', () {
      final hydrated = Recommendation.fromJson({
        'series_id': 'x',
        'title': 'X',
        'creator': null,
        'reasoning': 'r',
        // is_in_library deliberately omitted
      });
      expect(hydrated.isInLibrary, false);
    });
  });
}
