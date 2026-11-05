import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/page_prefetcher.dart';

void main() {
  group('PagePrefetcher', () {
    test('calculates forward prefetch range in LTR mode', () {
      final prefetcher = PagePrefetcher(
        totalPages: 20,
        pageUrlBuilder: (p) => 'http://test.com/page/$p',
      );

      final range = prefetcher.prefetchRange(currentPage: 5, rtl: false);
      expect(range, [6, 7, 8, 9, 10]); // default prefetchCount = 5
    });

    test('calculates backward prefetch range in RTL mode', () {
      final prefetcher = PagePrefetcher(
        totalPages: 20,
        pageUrlBuilder: (p) => 'http://test.com/page/$p',
      );

      final range = prefetcher.prefetchRange(currentPage: 10, rtl: true);
      expect(range, [9, 8, 7, 6, 5]); // prefetches lower pages
    });

    test('clamps range to valid page bounds', () {
      final prefetcher = PagePrefetcher(
        totalPages: 5,
        pageUrlBuilder: (p) => 'http://test.com/page/$p',
      );

      final range = prefetcher.prefetchRange(currentPage: 3, rtl: false);
      expect(range, [4]); // only 1 page left, not 3
    });

    test('returns empty range on last page in LTR', () {
      final prefetcher = PagePrefetcher(
        totalPages: 5,
        pageUrlBuilder: (p) => 'http://test.com/page/$p',
      );

      final range = prefetcher.prefetchRange(currentPage: 4, rtl: false);
      expect(range, isEmpty);
    });

    test('returns empty range on first page in RTL', () {
      final prefetcher = PagePrefetcher(
        totalPages: 5,
        pageUrlBuilder: (p) => 'http://test.com/page/$p',
      );

      final range = prefetcher.prefetchRange(currentPage: 0, rtl: true);
      expect(range, isEmpty);
    });

    test('increases prefetch count after rapid page turns', () {
      final prefetcher = PagePrefetcher(
        totalPages: 20,
        pageUrlBuilder: (p) => 'http://test.com/page/$p',
      );
      addTearDown(prefetcher.dispose);

      prefetcher.onPageChangedForTest();
      prefetcher.onPageChangedForTest();
      prefetcher.onPageChangedForTest();

      final range = prefetcher.prefetchRange(currentPage: 5, rtl: false);
      expect(range.length, 8);
    });

    test('resets prefetch count after cooldown', () async {
      final prefetcher = PagePrefetcher(
        totalPages: 20,
        pageUrlBuilder: (p) => 'http://test.com/page/$p',
      );

      prefetcher.onPageChangedForTest();
      prefetcher.onPageChangedForTest();
      prefetcher.onPageChangedForTest();

      expect(prefetcher.prefetchRange(currentPage: 5, rtl: false).length, 8);

      await Future.delayed(const Duration(seconds: 5));

      expect(prefetcher.prefetchRange(currentPage: 5, rtl: false).length, 5);

      prefetcher.dispose();
    });

    test('onPageJump resets speed tracking', () {
      final prefetcher = PagePrefetcher(
        totalPages: 20,
        pageUrlBuilder: (p) => 'http://test.com/page/$p',
      );
      addTearDown(prefetcher.dispose);

      // Trigger speed boost
      prefetcher.onPageChangedForTest();
      prefetcher.onPageChangedForTest();
      prefetcher.onPageChangedForTest();
      expect(prefetcher.prefetchRange(currentPage: 5, rtl: false).length, 8);

      // onPageJump should reset — we can't call it without BuildContext,
      // but we can test onPageJumpForTest
      prefetcher.onPageJumpForTest();
      expect(prefetcher.prefetchRange(currentPage: 5, rtl: false).length, 5);
    });
  });
}
