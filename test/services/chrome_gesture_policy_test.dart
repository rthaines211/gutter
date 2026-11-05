import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/chrome_gesture_policy.dart';

void main() {
  group('resolveReaderTap: chrome visible', () {
    const points = [
      Offset(0.1, 0.5),
      Offset(0.5, 0.5),
      Offset(0.9, 0.5),
      Offset(0.8, 0.2),
      Offset(0.8, 0.8),
    ];
    const layouts = ['standard', 'edge', 'thumb', 'disabled'];

    test('hides chrome everywhere, regardless of layout or offStep', () {
      for (final layout in layouts) {
        for (final point in points) {
          for (final offStep in [true, false]) {
            expect(
              resolveReaderTap(
                layout: layout,
                normalized: point,
                chromeVisible: true,
                scrollMode: false,
                offStep: offStep,
              ),
              ChromeTapResult.hideChrome,
              reason: 'layout=$layout point=$point offStep=$offStep',
            );
          }
        }
      }
    });
  });

  group('resolveReaderTap: scroll mode, chrome hidden', () {
    test('any tap toggles chrome', () {
      for (final point in [Offset(0.1, 0.5), Offset(0.5, 0.5), Offset(0.9, 0.5)]) {
        expect(
          resolveReaderTap(
            layout: 'standard',
            normalized: point,
            chromeVisible: false,
            scrollMode: true,
            offStep: false,
          ),
          ChromeTapResult.toggleChrome,
          reason: 'point=$point',
        );
      }
    });
  });

  group('resolveReaderTap: paged, offStep false', () {
    test('standard center is a no-op', () {
      expect(
        resolveReaderTap(
          layout: 'standard',
          normalized: const Offset(0.5, 0.5),
          chromeVisible: false,
          scrollMode: false,
          offStep: false,
        ),
        ChromeTapResult.none,
      );
    });

    test('standard left/right page', () {
      expect(
        resolveReaderTap(
          layout: 'standard',
          normalized: const Offset(0.1, 0.5),
          chromeVisible: false,
          scrollMode: false,
          offStep: false,
        ),
        ChromeTapResult.left,
      );
      expect(
        resolveReaderTap(
          layout: 'standard',
          normalized: const Offset(0.9, 0.5),
          chromeVisible: false,
          scrollMode: false,
          offStep: false,
        ),
        ChromeTapResult.right,
      );
    });

    test('thumb no-op region, back, forward', () {
      expect(
        resolveReaderTap(
          layout: 'thumb',
          normalized: const Offset(0.3, 0.5),
          chromeVisible: false,
          scrollMode: false,
          offStep: false,
        ),
        ChromeTapResult.none,
      );
      expect(
        resolveReaderTap(
          layout: 'thumb',
          normalized: const Offset(0.8, 0.2),
          chromeVisible: false,
          scrollMode: false,
          offStep: false,
        ),
        ChromeTapResult.back,
      );
      expect(
        resolveReaderTap(
          layout: 'thumb',
          normalized: const Offset(0.8, 0.8),
          chromeVisible: false,
          scrollMode: false,
          offStep: false,
        ),
        ChromeTapResult.forward,
      );
    });

    test('disabled is a no-op', () {
      expect(
        resolveReaderTap(
          layout: 'disabled',
          normalized: const Offset(0.1, 0.5),
          chromeVisible: false,
          scrollMode: false,
          offStep: false,
        ),
        ChromeTapResult.none,
      );
    });
  });

  group('resolveReaderTap: paged, offStep true', () {
    test('standard center toggles chrome', () {
      expect(
        resolveReaderTap(
          layout: 'standard',
          normalized: const Offset(0.5, 0.5),
          chromeVisible: false,
          scrollMode: false,
          offStep: true,
        ),
        ChromeTapResult.toggleChrome,
      );
    });

    test('thumb no-op region toggles chrome', () {
      expect(
        resolveReaderTap(
          layout: 'thumb',
          normalized: const Offset(0.3, 0.5),
          chromeVisible: false,
          scrollMode: false,
          offStep: true,
        ),
        ChromeTapResult.toggleChrome,
      );
    });

    test('disabled toggles chrome', () {
      expect(
        resolveReaderTap(
          layout: 'disabled',
          normalized: const Offset(0.9, 0.5),
          chromeVisible: false,
          scrollMode: false,
          offStep: true,
        ),
        ChromeTapResult.toggleChrome,
      );
    });

    test('standard left zone still pages, unaffected by offStep', () {
      expect(
        resolveReaderTap(
          layout: 'standard',
          normalized: const Offset(0.1, 0.5),
          chromeVisible: false,
          scrollMode: false,
          offStep: true,
        ),
        ChromeTapResult.left,
      );
    });
  });

  group('isSwipeUp', () {
    test('40px upward travel at zero velocity is a swipe', () {
      expect(isSwipeUp(const Offset(0, -40), 0), isTrue);
    });

    test('39px upward travel at zero velocity is not', () {
      expect(isSwipeUp(const Offset(0, -39), 0), isFalse);
    });

    test('short travel with fast upward velocity is a swipe', () {
      expect(isSwipeUp(const Offset(0, -10), -600), isTrue);
    });

    test('horizontal-dominant motion is never a swipe up', () {
      expect(isSwipeUp(const Offset(60, -45), 0), isFalse);
    });

    test('diagonal motion without 2:1 vertical dominance is not a swipe up', () {
      expect(isSwipeUp(const Offset(30, -45), 0), isFalse);
    });

    test('downward travel is not a swipe up', () {
      expect(isSwipeUp(const Offset(0, 40), 0), isFalse);
    });
  });

  group('isSwipeDown', () {
    test('40px downward travel at zero velocity is a swipe', () {
      expect(isSwipeDown(const Offset(0, 40), 0), isTrue);
    });

    test('39px downward travel at zero velocity is not', () {
      expect(isSwipeDown(const Offset(0, 39), 0), isFalse);
    });

    test('short travel with fast downward velocity is a swipe', () {
      expect(isSwipeDown(const Offset(0, 10), 600), isTrue);
    });

    test('horizontal-dominant motion is never a swipe down', () {
      expect(isSwipeDown(const Offset(60, 45), 0), isFalse);
    });

    test('diagonal motion without 2:1 vertical dominance is not a swipe down',
        () {
      expect(isSwipeDown(const Offset(30, 45), 0), isFalse);
    });

    test('upward travel is not a swipe down', () {
      expect(isSwipeDown(const Offset(0, -40), 0), isFalse);
    });
  });

  group('swipeShowsChrome', () {
    test('paged mode, on step: swipe shows chrome', () {
      expect(swipeShowsChrome(scrollMode: false, offStep: false), isTrue);
    });

    test('scroll mode suppresses it', () {
      expect(swipeShowsChrome(scrollMode: true, offStep: false), isFalse);
    });

    test('off-step suppresses it', () {
      expect(swipeShowsChrome(scrollMode: false, offStep: true), isFalse);
    });

    test('both flags suppress it', () {
      expect(swipeShowsChrome(scrollMode: true, offStep: true), isFalse);
    });
  });
}
