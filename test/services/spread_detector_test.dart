// test/services/spread_detector_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/spread_detector.dart';

void main() {
  group('isSpread', () {
    test('standard portrait page is not a spread', () {
      // Typical comic page: ~2:3 ratio (0.67)
      expect(isSpread(1200, 1800), false);
    });

    test('2-page spread is detected', () {
      // Typical spread: ~4:3 ratio (1.33)
      expect(isSpread(2400, 1800), true);
    });

    test('exactly square is not a spread', () {
      expect(isSpread(1000, 1000), false);
    });

    test('just wider than tall is a spread', () {
      expect(isSpread(1001, 1000), true);
    });

    test('tall single page well below the cut is not a spread', () {
      // Even a generously tall single page stays portrait.
      expect(isSpread(900, 1000), false);
    });

    // Regression: Green Arrow (Lemire) deluxe edition spreads are 4237x3262
    // (aspect 1.299), which the old > 1.3 threshold silently missed. Singles
    // in the same book are 2119x3263 (aspect 0.649).
    test('Green Arrow deluxe spread (aspect ~1.299) is detected', () {
      expect(isSpread(4237, 3262), true);
    });

    test('Green Arrow deluxe single page (aspect ~0.649) is not a spread', () {
      expect(isSpread(2119, 3263), false);
    });

    test('very wide panoramic is a spread', () {
      expect(isSpread(3000, 1000), true);
    });

    test('handles zero height gracefully', () {
      expect(isSpread(1000, 0), false);
    });
  });
}
