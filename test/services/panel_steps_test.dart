import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/panel_steps.dart';

void main() {
  // A 400 x 800 phone; a 1000 x 1500 page contain-fits at 400 x 600, top at y = 100.
  const screen = Size(400, 800);
  const page = Rect.fromLTWH(0, 100, 400, 600);
  const pagePx = Size(1000, 1500);
  const grid = [
    Rect.fromLTRB(0, 0, 500, 750),
    Rect.fromLTRB(500, 0, 1000, 750),
    Rect.fromLTRB(0, 750, 1000, 1500),
  ];
  double sx(Matrix4 m) => m.entry(0, 0);
  Rect on(Matrix4 m, Rect panel) => MatrixUtils.transformRect(m, panelOnScreen(page, pagePx, panel));

  test('panelOnScreen maps page pixels onto the contain rect and clamps overshoot', () {
    expect(panelOnScreen(page, pagePx, grid[0]), const Rect.fromLTRB(0, 100, 200, 400));
    expect(panelOnScreen(page, pagePx, const Rect.fromLTRB(-50, 1400, 1100, 1600)),
        const Rect.fromLTRB(0, 660, 400, 700));
  });

  test('step 0 is the whole page and there is one step per panel', () {
    final s = panelSteps(page: page, pagePx: pagePx, screen: screen, panels: grid, popout: false);
    expect(s, hasLength(4));
    expect(s[0], Matrix4.identity());
  });

  test('a fit step scales the panel to the screen inside an 8 px margin', () {
    final s = panelSteps(page: page, pagePx: pagePx, screen: screen, panels: grid, popout: false);
    expect(sx(s[1]), closeTo(1.92, 0.001)); // (400 - 16) / 200
    final r = on(s[1], grid[0]);
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.right, lessThanOrEqualTo(400));
    expect(r.top, greaterThanOrEqualTo(0));
    expect(r.bottom, lessThanOrEqualTo(800));
    // the page still covers the screen horizontally: no blank strip past its edge
    final pageOn = MatrixUtils.transformRect(s[1], page);
    expect(pageOn.left, lessThanOrEqualTo(0));
    expect(pageOn.right, greaterThanOrEqualTo(400));
  });

  test('a wide panel letterboxes: scale never drops below the contain fit', () {
    const wide = [Rect.fromLTRB(0, 0, 1000, 300), Rect.fromLTRB(0, 300, 1000, 1500)];
    final s = panelSteps(page: page, pagePx: pagePx, screen: screen, panels: wide, popout: false);
    expect(sx(s[1]), 1.0);
    expect(on(s[1], wide[0]).width, 400);
  });

  test('a step is centred on its panel when the page has room to move', () {
    // a mid-page panel, 200 x 200 on screen: at 1.92x the page still covers the screen
    const mid = Rect.fromLTRB(250, 500, 750, 1000);
    final s = panelSteps(page: page, pagePx: pagePx, screen: screen, panels: [mid, grid[2]], popout: false);
    final r = on(s[1], mid);
    expect(sx(s[1]), closeTo(1.92, 0.001));
    expect(r.center.dx, closeTo(200, 0.5));
    expect(r.center.dy, closeTo(400, 0.5));
  });

  test('a panel as wide as the page stays at page scale with the page centred', () {
    final s = panelSteps(page: page, pagePx: pagePx, screen: screen, panels: grid, popout: false);
    expect(sx(s[3]), 1.0); // the bottom half is already 400 wide on screen
    final pageOn = MatrixUtils.transformRect(s[3], page);
    expect(pageOn.top, 100); // 600 tall on an 800 screen: centred, not pulled up
  });

  test('pop-out mode leaves the page where it is', () {
    final s = panelSteps(page: page, pagePx: pagePx, screen: screen, panels: grid, popout: true);
    expect(s, hasLength(4));
    expect(s.every((m) => m == Matrix4.identity()), isTrue);
  });
}
