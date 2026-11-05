import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/tap_zone_overlay.dart';

void main() {
  late int taps, longs, doubles, chrome;

  Future<void> pump(WidgetTester tester, {bool withDoubleTap = false}) async {
    taps = 0;
    longs = 0;
    doubles = 0;
    chrome = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TapZoneOverlay(
          layout: 'standard',
          onRight: () => taps++,
          chromeVisible: () => false,
          scrollMode: () => false,
          offStep: () => false,
          onShowChrome: () => chrome++,
          onHideChrome: () => chrome++,
          onLongPress: (_) => longs++,
          onDoubleTap: withDoubleTap ? (_) => doubles++ : null,
        ),
      ),
    );
  }

  testWidgets('a still press fires once and is not a tap', (tester) async {
    await pump(tester);
    final g = await tester.startGesture(const Offset(760, 300));
    await tester.pump(const Duration(milliseconds: 600));
    await g.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(longs, 1);
    expect(taps, 0);
  });

  testWidgets('a quick tap is not a long-press', (tester) async {
    await pump(tester);
    await tester.tapAt(const Offset(760, 300));
    await tester.pump(const Duration(milliseconds: 600));
    expect(taps, 1);
    expect(longs, 0);
  });

  testWidgets('moving the finger cancels it', (tester) async {
    await pump(tester);
    final g = await tester.startGesture(const Offset(760, 300));
    await g.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 600));
    await g.up();
    expect(longs, 0);
  });

  testWidgets('long press then release fires no tap and no swipe',
      (tester) async {
    await pump(tester);
    final g = await tester.startGesture(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(const Offset(0, -80)); // would be a swipe up
    await g.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(longs, 1);
    expect(taps, 0);
    expect(chrome, 0);
  });

  testWidgets('double tap fires onDoubleTap, not chrome', (tester) async {
    await pump(tester, withDoubleTap: true);
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(doubles, 1);
    expect(chrome, 0);
    expect(taps, 0);
  });
}
