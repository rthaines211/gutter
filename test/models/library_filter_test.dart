import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/library_filter.dart';

void main() {
  group('LibraryFilter metadata fields', () {
    test('default has no metadata filters', () {
      const filter = LibraryFilter();
      expect(filter.publisher, isNull);
      expect(filter.genre, isNull);
      expect(filter.writer, isNull);
      expect(filter.yearMin, isNull);
      expect(filter.yearMax, isNull);
      expect(filter.activeFilterCount, 0);
      expect(filter.isDefault, isTrue);
    });

    test('copyWith sets metadata fields', () {
      const filter = LibraryFilter();
      final updated = filter.copyWith(publisher: 'DC Comics', genre: 'Action');
      expect(updated.publisher, 'DC Comics');
      expect(updated.genre, 'Action');
      expect(updated.activeFilterCount, 2);
      expect(updated.isDefault, isFalse);
    });

    test('copyWith clears metadata fields with clear flags', () {
      final filter = const LibraryFilter().copyWith(publisher: 'DC Comics');
      final cleared = filter.copyWith(clearPublisher: true);
      expect(cleared.publisher, isNull);
      expect(cleared.activeFilterCount, 0);
    });

    test('activeFilterCount counts only metadata filters', () {
      final filter = const LibraryFilter().copyWith(
        status: 'unread',
        publisher: 'Image',
        genre: 'Sci-Fi',
        yearMin: 2010,
      );
      expect(filter.activeFilterCount, 3);
    });

    test('sortLabel includes new sort options', () {
      expect(const LibraryFilter(sort: 'publisher').sortLabel, 'Publisher');
      expect(const LibraryFilter(sort: 'year').sortLabel, 'Year');
      expect(const LibraryFilter(sort: 'issue_count').sortLabel, 'Issue Count');
      expect(const LibraryFilter(sort: 'unread_count').sortLabel, 'Unread Count');
      expect(const LibraryFilter(sort: 'progress').sortLabel, 'Progress');
    });
  });
}
