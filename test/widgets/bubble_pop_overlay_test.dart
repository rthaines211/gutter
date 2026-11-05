import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/bubble_pop_overlay.dart';

void main() {
  const screen = Size(400, 800);

  test('small balloon grows by maxPopScale (1.6x)', () {
    final r = popoutRect(const Rect.fromLTWH(150, 300, 40, 20), screen);
    expect(r.width, closeTo(64, 0.01));
    expect(r.height, closeTo(32, 0.01));
  });

  test('a chain of joined balloons grows by chainPopScale (1.3x)', () {
    final r = popoutRect(
      const Rect.fromLTWH(150, 300, 40, 20),
      screen,
      maxScale: chainPopScale,
    );
    expect(r.width, closeTo(52, 0.01));
    expect(r.height, closeTo(26, 0.01));
  });

  test('centred balloon grows evenly', () {
    final r = popoutRect(const Rect.fromLTWH(180, 390, 40, 20), screen);
    expect(r.center.dx, closeTo(200, 0.01));
    expect(r.center.dy, closeTo(400, 0.01));
  });

  test('balloon grows away from the nearer edges', () {
    // Upper left: grows down and right, its top-left corner barely moves.
    final a = popoutRect(const Rect.fromLTWH(40, 60, 40, 20), screen);
    expect(a.left, lessThanOrEqualTo(40));
    expect(a.top, lessThanOrEqualTo(60));
    expect(a.left, greaterThan(40 - 10));
    expect(a.right, greaterThan(80 + 20));
    // Lower right: grows up and left.
    final b = popoutRect(const Rect.fromLTWH(320, 720, 40, 20), screen);
    expect(b.right, greaterThanOrEqualTo(360));
    expect(b.left, lessThan(320 - 20));
    expect(b.top, lessThan(720 - 10));
  });

  test('wide balloon is capped at 92 % of the screen width', () {
    final r = popoutRect(const Rect.fromLTWH(20, 300, 300, 40), screen);
    expect(r.width, closeTo(368, 0.01));
  });

  test('on a wide screen a tall balloon may reach 80 % of the height', () {
    final r = popoutRect(
      const Rect.fromLTWH(100, 50, 100, 250),
      const Size(844, 390),
    );
    expect(r.height, closeTo(312, 0.01));
  });

  test('tall balloon is capped at 45 % of the screen height', () {
    final r = popoutRect(const Rect.fromLTWH(100, 100, 50, 300), screen);
    expect(r.height, closeTo(360, 0.01));
  });

  test('clamped 8 px inside the screen', () {
    final r = popoutRect(const Rect.fromLTWH(0, 0, 40, 20), screen);
    expect(r.left, 8);
    expect(r.top, 8);
    final b = popoutRect(const Rect.fromLTWH(380, 790, 20, 10), screen);
    expect(b.right, 392);
    expect(b.bottom, 792);
  });

  test('balloon with a tail grows out of the tail, tip fixed', () {
    // Tail tip below-left of the balloon: it grows up and right from there.
    const tip = Offset(150, 340);
    final r = popoutRect(
      const Rect.fromLTWH(150, 300, 40, 40),
      screen,
      tail: tip,
    );
    expect(r.left, closeTo(150, 0.01));
    expect(r.bottom, closeTo(340, 0.01));
    expect(r.width, closeTo(64, 0.01));
  });

  test('tail growth is still kept on screen', () {
    final r = popoutRect(
      const Rect.fromLTWH(340, 20, 40, 20),
      screen,
      tail: const Offset(340, 20),
    );
    expect(r.right, lessThanOrEqualTo(392));
    expect(r.top, greaterThanOrEqualTo(8));
  });

  group('popoutSlide', () {
    test(
      'a tailed balloon at the right edge slides the page left by the overflow',
      () {
        // Tail on its left: it wants to grow right, past the screen edge.
        final ideal = popoutRect(
          const Rect.fromLTWH(340, 300, 40, 20),
          screen,
          tail: const Offset(340, 320),
          clamp: false,
        );
        expect(ideal.right, greaterThan(392));
        final slide = popoutSlide(ideal, screen);
        expect(slide.dx, closeTo(392 - ideal.right, 0.01));
        expect(slide.dy, 0);
        expect(ideal.shift(slide).right, closeTo(392, 0.01));
      },
    );

    test('a pop-out that fits needs no slide', () {
      final ideal = popoutRect(
        const Rect.fromLTWH(180, 390, 40, 20),
        screen,
        tail: const Offset(180, 410),
        clamp: false,
      );
      expect(popoutSlide(ideal, screen), Offset.zero);
    });

    test('top edge slides the page down', () {
      final ideal = popoutRect(
        const Rect.fromLTWH(180, 10, 40, 20),
        screen,
        tail: const Offset(200, 30),
        clamp: false,
      );
      final slide = popoutSlide(ideal, screen);
      expect(slide.dy, greaterThan(0));
      expect(ideal.shift(slide).top, closeTo(8, 0.01));
    });
  });

  group('art-aware placement', () {
    const on = Rect.fromLTWH(150, 300, 40, 20);
    test('moves off art that the tail placement would cover', () {
      // art everywhere right of x = 175: the tail spot (growing right) covers it
      double cost(Rect r) => (r.right - 175).clamp(0, 1000) * r.height;
      final tail = popoutRect(on, screen, tail: const Offset(150, 320));
      final placed = popoutRect(
        on,
        screen,
        tail: const Offset(150, 320),
        artCost: cost,
      );
      expect(cost(placed), lessThan(cost(tail)));
      expect(placed.left, lessThan(tail.left));
      expect(placed.size, tail.size, reason: 'same size, only moved');
      final o = placed.intersect(on);
      expect(
        o.width * o.height,
        greaterThanOrEqualTo(0.6 * 40 * 20),
        reason: 'still over its balloon',
      );
    });

    test('keeps the tail placement when nothing hides less', () {
      final tail = popoutRect(on, screen, tail: const Offset(150, 320));
      expect(
        popoutRect(on, screen, tail: const Offset(150, 320), artCost: (_) => 0),
        tail,
      );
    });
  });

  test('heightCap lets a panel grow past the 45 % balloon cap', () {
    // a 200 x 300 panel on a 400 x 800 screen: 45 % caps it at 360 tall (1.2x);
    // 85 % allows 680, so the 1.5x panel scale wins.
    const panel = Rect.fromLTWH(100, 200, 200, 300);
    expect(popoutRect(panel, screen, maxScale: 1.5).height, closeTo(360, 0.01));
    expect(popoutRect(panel, screen, maxScale: 1.5, heightCap: 0.85).height, closeTo(450, 0.01));
  });

  test('heightCap also replaces the 80 % landscape rule', () {
    const landscape = Size(800, 400);
    const panel = Rect.fromLTWH(300, 50, 200, 300);
    expect(popoutRect(panel, landscape, maxScale: 1.5).height, closeTo(320, 0.01)); // 0.8 * 400
    expect(popoutRect(panel, landscape, maxScale: 1.5, heightCap: 0.85).height, closeTo(340, 0.01));
  });

  test('minScale keeps a panel wider than the screen cap from shrinking', () {
    // a 380 x 200 panel on a 400 x 800 screen: the 92 % width cap would be 368 (0.97x)
    const panel = Rect.fromLTWH(10, 300, 380, 200);
    expect(popoutRect(panel, screen, maxScale: 1.5, heightCap: 0.85).width, closeTo(368, 0.01));
    final r = popoutRect(panel, screen, maxScale: 1.5, heightCap: 0.85, minScale: 1);
    expect(r.width, 380);
    expect(r.height, 200);
  });
}
