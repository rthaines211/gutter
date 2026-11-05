import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/comic_style.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/halftone_overlay.dart';
import 'package:comic_reader_app/widgets/liquid_glass.dart';
import 'package:comic_reader_app/widgets/sleep_warning_overlay.dart';

const _accent = Color(0xFF0A84FF);

Future<void> _pump(
  WidgetTester t, {
  ComicStyle style = ComicStyle.fullPop,
  Scheme scheme = Scheme.oledBlack,
  Duration Function()? remaining,
  VoidCallback? onExtend,
  VoidCallback? onRestart,
  VoidCallback? onCancel,
  VoidCallback? onDismiss,
  VoidCallback? onPageTap,
}) async {
  SharedPreferences.setMockInitialValues({'comic_style': style.name});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: AppTheme.themeData(scheme),
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onPageTap,
                ),
              ),
              Positioned.fill(
                child: SleepWarningOverlay(
                  remaining:
                      remaining ?? () => const Duration(seconds: 47),
                  lead: const Duration(seconds: 60),
                  accent: _accent,
                  onExtend: onExtend ?? () {},
                  onRestart: onRestart ?? () {},
                  onCancel: onCancel ?? () {},
                  onDismiss: onDismiss ?? () {},
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  // Let the 450ms entrance finish so taps land where the buttons rest.
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> _unmount(WidgetTester t) => t.pumpWidget(const SizedBox());

void main() {
  testWidgets('countdown shows m:ss and ticks', (t) async {
    final deadline = clock.now().add(const Duration(seconds: 47));
    await _pump(t, remaining: () => deadline.difference(clock.now()));
    // Read at mount; the first 1s tick hasn't fired during the entrance.
    Text countdown() => t.widget<Text>(find.byKey(const Key('sleep.countdown')));
    expect(countdown().data, '0:47');
    await t.pump(const Duration(seconds: 1));
    expect(countdown().data, '0:46');
    await _unmount(t);
  });

  testWidgets('full pop: caption boxes and burst', (t) async {
    await _pump(t, style: ComicStyle.fullPop);
    expect(find.text('MEANWHILE…'), findsOneWidget);
    expect(find.text('SCREEN SLEEPS IN'), findsOneWidget);
    expect(find.byKey(const Key('sleep.burst')), findsOneWidget);
    expect(find.byType(HalftoneOverlay), findsOneWidget);
    await _unmount(t);
  });

  testWidgets('ink & halftone: caption layout and burst, no glass card',
      (t) async {
    await _pump(t, style: ComicStyle.inkHalftone);
    expect(find.text('MEANWHILE…'), findsOneWidget);
    expect(find.text('SCREEN SLEEPS IN'), findsOneWidget);
    expect(find.byKey(const Key('sleep.burst')), findsOneWidget);
    expect(find.byType(HalftoneOverlay), findsOneWidget);
    expect(find.byType(LiquidGlass), findsNothing);
    await _unmount(t);
  });

  testWidgets('comic style off: buttons do not breathe', (t) async {
    await _pump(t, style: ComicStyle.off);
    expect(find.ancestor(
            of: find.byKey(const Key('sleep.off')),
            matching: find.byType(ScaleTransition)),
        findsNothing);
    await _unmount(t);
  });

  testWidgets('comic style off: glass card, no burst, no halftone',
      (t) async {
    await _pump(t, style: ComicStyle.off);
    expect(find.byType(LiquidGlass), findsOneWidget);
    expect(find.text('Screen sleeping in'), findsOneWidget);
    expect(find.byKey(const Key('sleep.burst')), findsNothing);
    expect(find.byType(HalftoneOverlay), findsNothing);
    expect(find.byKey(const Key('sleep.extend')), findsOneWidget);
    await _unmount(t);
  });

  testWidgets('buttons are >= 52pt tall', (t) async {
    for (final style in ComicStyle.values) {
      await _pump(t, style: style);
      for (final k in ['sleep.restart', 'sleep.off', 'sleep.extend']) {
        expect(t.getSize(find.byKey(Key(k))).height,
            greaterThanOrEqualTo(52), reason: '$k in $style');
      }
      expect(t.getSize(find.byKey(const Key('sleep.restart'))),
          t.getSize(find.byKey(const Key('sleep.off'))),
          reason: 'Restart and Off match in $style');
    }
    await _unmount(t);
  });

  testWidgets('Off is solid and full-contrast', (t) async {
    for (final scheme in [Scheme.oledBlack, Scheme.sepiaPaper]) {
      for (final style in ComicStyle.values) {
        await _pump(t, scheme: scheme, style: style);
        final off = t.widget<Container>(find.byKey(const Key('sleep.off')));
        expect((off.decoration as BoxDecoration).color, scheme.s2);
        final label = t.widget<Text>(find.descendant(
            of: find.byKey(const Key('sleep.off')),
            matching: find.text('Off')));
        expect(label.style!.color, scheme.tx);
        expect(find.descendant(
                of: find.byKey(const Key('sleep.off')),
                matching: find.byIcon(Icons.bedtime_off_outlined)),
            findsOneWidget);
      }
    }
    await _unmount(t);
  });

  testWidgets('actions call their callbacks', (t) async {
    final calls = <String>[];
    await _pump(t,
        onExtend: () => calls.add('extend'),
        onRestart: () => calls.add('restart'),
        onCancel: () => calls.add('off'));
    await t.tap(find.byKey(const Key('sleep.extend')));
    await t.tap(find.byKey(const Key('sleep.restart')));
    await t.tap(find.byKey(const Key('sleep.off')));
    expect(calls, ['extend', 'restart', 'off']);
    await _unmount(t);
  });

  testWidgets('swipe calls onDismiss', (t) async {
    var dismissed = 0;
    await _pump(t, onDismiss: () => dismissed++);
    await t.fling(find.text('MEANWHILE…'), const Offset(-600, 0), 2000);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(dismissed, 1);
    await _unmount(t);
  });

  testWidgets('taps on the dim do not reach the page', (t) async {
    var pageTaps = 0;
    await _pump(t, onPageTap: () => pageTaps++);
    await t.tapAt(const Offset(780, 20)); // top-right corner, away from controls
    await t.tapAt(const Offset(400, 300));
    expect(pageTaps, 0);
    await _unmount(t);
  });

  testWidgets('+15, Restart, and Off carry button semantics', (t) async {
    for (final style in ComicStyle.values) {
      await _pump(t, style: style);
      for (final label in ['+15 min', 'Restart', 'Off']) {
        expect(find.bySemanticsLabel(label), findsOneWidget,
            reason: '$label in $style');
        final semantics = t.widgetList<Semantics>(find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == label));
        expect(semantics.single.properties.button, isTrue,
            reason: '$label in $style');
      }
    }
    await _unmount(t);
  });
}
