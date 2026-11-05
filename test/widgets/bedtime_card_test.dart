import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/bedtime_card.dart';

Future<void> _pump(WidgetTester t,
    {VoidCallback? onStart, VoidCallback? onDismiss, VoidCallback? onSnooze, VoidCallback? onPageTap}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await withClock(Clock.fixed(DateTime(2026, 10, 31, 21, 42)), () async {
    await t.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: AppTheme.themeData(Scheme.oledBlack),
        home: Scaffold(
          body: Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                  behavior: HitTestBehavior.opaque, onTap: onPageTap),
            ),
            Positioned.fill(
              child: BedtimeCard(
                minutes: 15,
                accent: const Color(0xFF0A84FF),
                onStart: onStart ?? () {},
                onDismiss: onDismiss ?? () {},
                onSnooze: onSnooze ?? () {},
              ),
            ),
          ]),
        ),
      ),
    ));
  });
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('shows the time; Start runs onStart', (t) async {
    var started = 0;
    await _pump(t, onStart: () => started++);
    expect(find.text("It's 9:42 PM"), findsOneWidget);
    await t.tap(find.text('Start 15m'));
    // First frame starts the close animation's clock; the second finishes it.
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(started, 1);
  });

  testWidgets('Later runs onSnooze', (t) async {
    var snoozed = 0;
    await _pump(t, onSnooze: () => snoozed++);
    await t.tap(find.text('Later 30m'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(snoozed, 1);
  });

  testWidgets('dismisses itself after 8s', (t) async {
    var dismissed = 0;
    await _pump(t, onDismiss: () => dismissed++);
    await t.pump(const Duration(seconds: 8));
    await t.pump(const Duration(milliseconds: 400));
    expect(dismissed, 1);
  });

  testWidgets('taps beside the card reach the page', (t) async {
    var pageTaps = 0;
    await _pump(t, onPageTap: () => pageTaps++);
    await t.tapAt(const Offset(20, 20));
    expect(pageTaps, 1);
    await t.pump(const Duration(seconds: 9)); // let the timeout finish
  });
}
