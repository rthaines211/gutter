import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/scrubber_geometry.dart';

void main() {
  group('bookmarkTickOffset', () {
    test('first page sits at the left inset', () {
      expect(
        bookmarkTickOffset(page: 0, totalPages: 100, trackWidth: 200),
        closeTo(9, 0.001),
      );
    });

    test('last page sits at the right inset', () {
      expect(
        bookmarkTickOffset(page: 99, totalPages: 100, trackWidth: 200),
        closeTo(191, 0.001), // 200 - 9
      );
    });

    test('middle page is centered between insets', () {
      // usable = 200 - 18 = 182; fraction 0.5 -> 9 + 91 = 100
      expect(
        bookmarkTickOffset(page: 50, totalPages: 101, trackWidth: 200),
        closeTo(100, 0.001),
      );
    });

    test('single page returns the left inset', () {
      expect(
        bookmarkTickOffset(page: 0, totalPages: 1, trackWidth: 200),
        closeTo(9, 0.001),
      );
    });

    test('out-of-range page is clamped into the track', () {
      final low = bookmarkTickOffset(page: -5, totalPages: 100, trackWidth: 200);
      final high = bookmarkTickOffset(page: 500, totalPages: 100, trackWidth: 200);
      expect(low, closeTo(9, 0.001));
      expect(high, closeTo(191, 0.001));
    });
  });

  group('pageGridColumns', () {
    test('phone width', () => expect(pageGridColumns(599), 4));
    test('small tablet boundary', () => expect(pageGridColumns(600), 6));
    test('mid tablet boundary', () => expect(pageGridColumns(900), 8));
    test('large tablet boundary', () => expect(pageGridColumns(1200), 10));
    test('very wide', () => expect(pageGridColumns(2000), 10));
  });
}
