import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/models/reader_settings.dart';
import 'package:comic_reader_app/providers/providers.dart' show sharedPrefsProvider;
import 'package:comic_reader_app/widgets/reader_aa_panel.dart';

void main() {
  late ReaderSettings? changed;
  late List<double> brightnessSet;

  Future<void> pump(
    WidgetTester t, {
    Size size = const Size(360, 700),
    ReaderSettings settings = const ReaderSettings(),
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    changed = null;
    brightnessSet = [];
    await t.pumpWidget(
      ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 360,
                child: ReaderAaPanel(
                  settings: settings,
                  onChanged: (s) => changed = s,
                  setBrightness: (v) async => brightnessSet.add(v),
                  readBrightness: () async => 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
  }

  testWidgets('Width sets pageFit to fitWidth', (t) async {
    await pump(t);
    await t.tap(find.text('Width'));
    expect(changed?.pageFit, 'fitWidth');
  });

  testWidgets('Panels sets zoomMode to panels', (t) async {
    await pump(t);
    await t.tap(find.text('Panels'));
    expect(changed?.zoomMode, 'panels');
  });

  testWidgets('Paper sets theme to white', (t) async {
    await pump(t);
    await t.tap(find.text('Paper'));
    expect(changed?.theme, 'white');
  });

  testWidgets('dragging brightness calls setBrightness', (t) async {
    await pump(t);
    await t.drag(find.byType(Slider), const Offset(60, 0));
    expect(brightnessSet, isNotEmpty);
  });

  testWidgets('Scroll sets readingMode to scroll', (t) async {
    await pump(t);
    await t.tap(find.text('Scroll'));
    expect(changed?.readingMode, 'scroll');
  });

  testWidgets('RTL sets readingDirection to rtl', (t) async {
    await pump(t);
    await t.tap(find.text('RTL'));
    expect(changed?.readingDirection, 'rtl');
  });

  testWidgets('More reader settings reveals tap zones; sleep lives in Settings', (
    t,
  ) async {
    await pump(t);
    expect(find.text('Tap zones'), findsNothing);
    await t.ensureVisible(find.text('More reader settings'));
    await t.tap(find.text('More reader settings'));
    await t.pump();
    await t.scrollUntilVisible(find.text('Page turn'), 200);
    expect(find.text('Tap zones'), findsOneWidget);
    expect(find.text('Keep screen on'), findsOneWidget);
    expect(find.text('Starting time'), findsNothing);
    expect(find.text('Bedtime reminder'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('rebuild with the same settings object keeps earlier edits', (
    t,
  ) async {
    const opening = ReaderSettings();
    await pump(t, settings: opening);
    await t.tap(find.text('Width'));
    await pump(t, settings: opening); // route rebuild re-passes the snapshot
    await t.tap(find.text('RTL'));
    expect(changed?.readingDirection, 'rtl');
    expect(changed?.pageFit, 'fitWidth');
  });

  testWidgets('legacy paper theme selects the Paper swatch', (t) async {
    await pump(t, settings: const ReaderSettings(theme: 'paper'));
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  for (final size in const [Size(360, 700), Size(360, 520)]) {
    testWidgets('no overflow at ${size.width}x${size.height}, expanded', (
      t,
    ) async {
      await pump(
        t,
        size: size,
        settings: const ReaderSettings(zoomMode: 'panels'),
      );
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('More reader settings'));
      await t.tap(find.text('More reader settings'));
      await t.pump();
      expect(t.takeException(), isNull);
    });
  }
}
