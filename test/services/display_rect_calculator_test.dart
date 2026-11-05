import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/display_rect_calculator.dart';

void main() {
  group('calculateDisplayRect', () {
    group('fitScreen (BoxFit.contain)', () {
      test('tall image in landscape viewport → pillarboxed', () {
        final rect = calculateDisplayRect(
          imageWidth: 1200,
          imageHeight: 1800,
          viewportWidth: 1024,
          viewportHeight: 768,
          fit: BoxFit.contain,
        );
        expect(rect.left, closeTo(256, 1));
        expect(rect.top, closeTo(0, 1));
        expect(rect.width, closeTo(512, 1));
        expect(rect.height, closeTo(768, 1));
      });

      test('wide image in portrait viewport → letterboxed', () {
        final rect = calculateDisplayRect(
          imageWidth: 2400,
          imageHeight: 1800,
          viewportWidth: 390,
          viewportHeight: 844,
          fit: BoxFit.contain,
        );
        expect(rect.left, closeTo(0, 1));
        expect(rect.top, closeTo(275.75, 1));
        expect(rect.width, closeTo(390, 1));
        expect(rect.height, closeTo(292.5, 1));
      });

      test('image same aspect as viewport → exact fit', () {
        final rect = calculateDisplayRect(
          imageWidth: 1024,
          imageHeight: 768,
          viewportWidth: 1024,
          viewportHeight: 768,
          fit: BoxFit.contain,
        );
        expect(rect.left, closeTo(0, 1));
        expect(rect.top, closeTo(0, 1));
        expect(rect.width, closeTo(1024, 1));
        expect(rect.height, closeTo(768, 1));
      });
    });

    group('fitWidth (BoxFit.fitWidth)', () {
      test('tall image fills width, extends beyond viewport', () {
        final rect = calculateDisplayRect(
          imageWidth: 1200,
          imageHeight: 1800,
          viewportWidth: 1024,
          viewportHeight: 768,
          fit: BoxFit.fitWidth,
        );
        expect(rect.left, closeTo(0, 1));
        expect(rect.top, closeTo(-384, 1));
        expect(rect.width, closeTo(1024, 1));
        expect(rect.height, closeTo(1536, 1));
      });
    });

    group('fitHeight (BoxFit.fitHeight)', () {
      test('wide image fills height, extends beyond viewport', () {
        final rect = calculateDisplayRect(
          imageWidth: 2400,
          imageHeight: 1800,
          viewportWidth: 1024,
          viewportHeight: 768,
          fit: BoxFit.fitHeight,
        );
        expect(rect.left, closeTo(0, 1));
        expect(rect.top, closeTo(0, 1));
        expect(rect.width, closeTo(1024, 1));
        expect(rect.height, closeTo(768, 1));
      });

      test('tall image fills height, narrower than viewport', () {
        final rect = calculateDisplayRect(
          imageWidth: 600,
          imageHeight: 1800,
          viewportWidth: 1024,
          viewportHeight: 768,
          fit: BoxFit.fitHeight,
        );
        expect(rect.left, closeTo(384, 1));
        expect(rect.top, closeTo(0, 1));
        expect(rect.width, closeTo(256, 1));
        expect(rect.height, closeTo(768, 1));
      });
    });
  });
}
