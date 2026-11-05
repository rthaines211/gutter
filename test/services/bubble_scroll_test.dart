import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/bubble_scroll.dart';

void main() {
  // A sideways phone: a 1000 x 1500 page fits as 562.7 x 844 wide... use round
  // numbers: an 800 x 400 screen and a page laid out contain-fit at 200 x 400,
  // so fit width is 4x and the page is 1600 tall on screen (4 screens).
  const screen = Size(800, 400);
  const page = Rect.fromLTWH(300, 0, 200, 400);
  double ty(Matrix4 m) => m.entry(1, 3);
  double sx(Matrix4 m) => m.entry(0, 0);

  test(
    'every step keeps the fit-width scale; step 0 is the top of the page',
    () {
      final s = bubbleScrollSteps(
        scale: 4,
        page: page,
        screen: screen,
        steps: [(const Rect.fromLTWH(320, 10, 20, 10), null)],
      );
      expect(s.every((m) => sx(m) == 4), isTrue);
      expect(ty(s[0]), 0);
      expect(
        s[0].entry(0, 3),
        -1200,
        reason: 'page left edge at the screen edge',
      );
    },
  );

  test('a balloon already on screen does not move the page', () {
    final s = bubbleScrollSteps(
      scale: 4,
      page: page,
      screen: screen,
      steps: [
        (const Rect.fromLTWH(320, 10, 20, 10), null), // y 40..80 on screen
        (const Rect.fromLTWH(400, 50, 20, 10), null), // y 200..240
      ],
    );
    expect(ty(s[1]), 0);
    expect(ty(s[2]), 0);
  });

  test(
    'a balloon below the screen scrolls it near the top, at most most of a screen at a time',
    () {
      final s = bubbleScrollSteps(
        scale: 4,
        page: page,
        screen: screen,
        steps: [
          (
            const Rect.fromLTWH(320, 120, 20, 10),
            null,
          ), // y 480..520: just below
        ],
      );
      // near the top would be ty = 48 - 480 = -432, but the most it may jump is 340
      expect(ty(s[1]), -340);
      final m = s[1];
      expect(
        480 + ty(m) + 40 <= 400 - 8,
        isTrue,
        reason: 'balloon fully on screen',
      );
    },
  );

  test('scrolling stays within the page and a last step shows the bottom', () {
    final s = bubbleScrollSteps(
      scale: 4,
      page: page,
      screen: screen,
      steps: [
        (const Rect.fromLTWH(320, 395, 20, 5), null), // the very bottom
      ],
    );
    expect(ty(s[1]), -1200, reason: 'clamped: page bottom at screen bottom');
    expect(s.length, 2, reason: 'already at the bottom, no extra step');

    final t = bubbleScrollSteps(
      scale: 4,
      page: page,
      screen: screen,
      steps: [(const Rect.fromLTWH(320, 10, 20, 10), null)],
    );
    expect(t.length, 3);
    expect(ty(t.last), -1200);
  });

  test('a tailed balloon scrolls far enough for its pop-out too', () {
    // tail tip under the balloon: the pop-out grows upward from it
    final s = bubbleScrollSteps(
      scale: 4,
      page: page,
      screen: screen,
      steps: [(const Rect.fromLTWH(320, 4, 30, 20), const Offset(330, 24))],
    );
    // balloon 16..96 on screen at ty 0, pop-out grows up off the top: page scrolls down
    expect(ty(s[1]), greaterThan(0), reason: 'shows space above the page top');
  });
}
