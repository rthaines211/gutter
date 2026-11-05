import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/tap_zone_overlay.dart';

const _centre = Offset(150, 150);

Future<void> _pumpOverlay(
  WidgetTester tester,
  String layout, {
  required void Function(String) log,
  bool Function()? chromeVisible,
  bool scrollMode = false,
  bool offStep = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 300,
        height: 300,
        child: TapZoneOverlay(
          layout: layout,
          onLeft: () => log('left'),
          onRight: () => log('right'),
          chromeVisible: chromeVisible ?? () => false,
          scrollMode: () => scrollMode,
          offStep: () => offStep,
          onShowChrome: () => log('show'),
          onHideChrome: () => log('hide'),
          onDoubleTap: (_) => log('double'),
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('standard: left third taps fire onLeft', (tester) async {
    final events = <String>[];
    await _pumpOverlay(tester, 'standard', log: events.add);
    await tester.tapAt(const Offset(30, 150)); // x≈0.1
    await tester.pump(const Duration(milliseconds: 300)); // past double-tap window
    expect(events, ['left']);
  });

  testWidgets('disabled: tap does nothing when chrome hidden', (tester) async {
    final events = <String>[];
    await _pumpOverlay(tester, 'disabled', log: events.add);
    await tester.tapAt(const Offset(30, 150));
    await tester.pump(const Duration(milliseconds: 300));
    expect(events, isEmpty);
  });

  testWidgets('standard: centre tap is a no-op', (tester) async {
    final events = <String>[];
    await _pumpOverlay(tester, 'standard', log: events.add);
    await tester.tapAt(_centre);
    await tester.pump(const Duration(milliseconds: 300));
    expect(events, isEmpty);
  });

  testWidgets('centre tap toggles chrome when offStep', (tester) async {
    final events = <String>[];
    await _pumpOverlay(tester, 'standard', log: events.add, offStep: true);
    await tester.tapAt(_centre);
    await tester.pump(const Duration(milliseconds: 300));
    expect(events, ['show']);
  });

  testWidgets('tap while chrome visible only hides', (tester) async {
    final events = <String>[];
    var visible = true;
    await _pumpOverlay(tester, 'standard',
        log: events.add, chromeVisible: () => visible);
    await tester.tapAt(const Offset(270, 150)); // right third
    await tester.pump(const Duration(milliseconds: 300));
    expect(events, ['hide']);
    // Getter is read at gesture time, not build time.
    visible = false;
    await tester.tapAt(const Offset(270, 150));
    await tester.pump(const Duration(milliseconds: 300));
    expect(events, ['hide', 'right']);
  });

  testWidgets('swipe up shows chrome', (tester) async {
    final events = <String>[];
    await _pumpOverlay(tester, 'standard', log: events.add);
    await tester.dragFrom(_centre, const Offset(0, -80));
    await tester.pump(const Duration(milliseconds: 300));
    expect(events, ['show']);
  });

  testWidgets('swipe up ignored when offStep', (tester) async {
    final events = <String>[];
    await _pumpOverlay(tester, 'standard', log: events.add, offStep: true);
    await tester.dragFrom(_centre, const Offset(0, -80));
    await tester.pump(const Duration(milliseconds: 300));
    expect(events, isEmpty);
  });

  testWidgets('horizontal drag never shows chrome', (tester) async {
    final events = <String>[];
    await _pumpOverlay(tester, 'standard', log: events.add);
    await tester.dragFrom(_centre, const Offset(-120, -30));
    await tester.pump(const Duration(milliseconds: 300));
    expect(events, isEmpty);
  });

  testWidgets('swipe down hides when visible', (tester) async {
    final events = <String>[];
    await _pumpOverlay(tester, 'standard',
        log: events.add, chromeVisible: () => true);
    await tester.dragFrom(_centre, const Offset(0, 80));
    await tester.pump(const Duration(milliseconds: 300));
    expect(events, ['hide']);
  });

  testWidgets('swipe down does nothing when hidden', (tester) async {
    final events = <String>[];
    await _pumpOverlay(tester, 'standard', log: events.add);
    await tester.dragFrom(_centre, const Offset(0, 80));
    await tester.pump(const Duration(milliseconds: 300));
    expect(events, isEmpty);
  });

  testWidgets('swipe up ignored in scroll mode', (tester) async {
    final events = <String>[];
    await _pumpOverlay(tester, 'standard', log: events.add, scrollMode: true);
    await tester.dragFrom(_centre, const Offset(0, -80));
    await tester.pump(const Duration(milliseconds: 300));
    expect(events, isEmpty);
  });

  testWidgets('two-finger gesture fires no tap and no swipe', (tester) async {
    final events = <String>[];
    await _pumpOverlay(tester, 'standard', log: events.add);
    final f1 = await tester.startGesture(const Offset(270, 100), pointer: 1);
    final f2 = await tester.startGesture(const Offset(270, 200), pointer: 2);
    await f1.moveBy(const Offset(0, -50)); // pinch-ish: finger 1 moves up
    await f2.moveBy(const Offset(0, 10));
    await f1.up();
    await tester.pump(const Duration(milliseconds: 300));
    await f2.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(events, isEmpty);
  });

  testWidgets('a page-turn tap draws nothing', (tester) async {
    final events = <String>[];
    await _pumpOverlay(tester, 'standard', log: events.add);
    await tester.tapAt(const Offset(270, 150)); // right third
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(events, ['right']);
    expect(
        find.descendant(
            of: find.byType(TapZoneOverlay), matching: find.byType(ColoredBox)),
        findsNothing);
  });
}
