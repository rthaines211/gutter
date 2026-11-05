import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/widgets/liquid_glass.dart';
import 'package:comic_reader_app/widgets/tap_zone_onboarding.dart';

Future<void> _pump(
  WidgetTester tester, {
  required VoidCallback onDismiss,
  String layout = 'standard',
  bool rtl = false,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: theme,
      home: Scaffold(
        body: TapZoneOnboarding(onDismiss: onDismiss, layout: layout, rtl: rtl),
      ),
    ),
  ));
}

void main() {
  test('shouldShowTapZoneOnboarding is true when the v2 key is unset', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await shouldShowTapZoneOnboarding(), isTrue);
  });

  test('shouldShowTapZoneOnboarding is true for the legacy (v1) key', () async {
    SharedPreferences.setMockInitialValues({'tap_zone_onboarding_shown': true});
    expect(await shouldShowTapZoneOnboarding(), isTrue);
  });

  test('shouldShowTapZoneOnboarding is false after markTapZoneOnboardingShown', () async {
    SharedPreferences.setMockInitialValues({});
    await markTapZoneOnboardingShown();
    expect(await shouldShowTapZoneOnboarding(), isFalse);
  });

  testWidgets('shows the swipe-up hint text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, onDismiss: () {});
    expect(find.text('Swipe up for controls'), findsOneWidget);
  });

  testWidgets('disabled layout shows only the swipe-up line, no zones', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, onDismiss: () {}, layout: 'disabled');
    expect(find.text('Swipe up for controls'), findsOneWidget);
    expect(find.text('Previous Page'), findsNothing);
    expect(find.text('Next Page'), findsNothing);
  });

  testWidgets('standard layout shows back/next regions', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, onDismiss: () {});
    expect(find.text('Previous Page'), findsOneWidget);
    expect(find.text('Next Page'), findsOneWidget);
  });

  testWidgets('RTL swaps the left/right labels', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, onDismiss: () {}, rtl: true);
    final mid = tester.getSize(find.byType(Scaffold)).width / 2;
    expect(tester.getCenter(find.text('Next Page')).dx, lessThan(mid));
    expect(tester.getCenter(find.text('Previous Page')).dx, greaterThan(mid));
  });

  testWidgets('RTL leaves the thumb strip (back/forward) alone', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, onDismiss: () {}, layout: 'thumb', rtl: true);
    expect(tester.getCenter(find.text('Previous Page')).dy,
        lessThan(tester.getCenter(find.text('Next Page')).dy));
  });

  testWidgets('labels sit on glass chips in scheme colors (Sepia)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester,
        onDismiss: () {}, theme: AppTheme.themeData(Scheme.sepiaPaper));
    for (final label in ['Previous Page', 'Next Page', 'Swipe up for controls']) {
      expect(tester.widget<Text>(find.text(label)).style?.color,
          Scheme.sepiaPaper.tx, reason: label);
      expect(
          find.ancestor(of: find.text(label), matching: find.byType(LiquidGlass)),
          findsOneWidget,
          reason: label);
    }
  });

  testWidgets('tap dismisses via onDismiss and marks shown', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var dismissed = false;
    await _pump(tester, onDismiss: () => dismissed = true);
    await tester.tapAt(const Offset(10, 10));
    expect(dismissed, isTrue);
    await tester.pump();
    expect(await shouldShowTapZoneOnboarding(), isFalse);
  });

  testWidgets('peek: no swipe hint, fades itself out and dismisses', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var dismissed = false;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: TapZoneOnboarding(
            peek: true,
            layout: 'thumb',
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    ));
    expect(find.text('Swipe up for controls'), findsNothing);
    expect(find.text('Next Page'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(dismissed, isFalse);
    await tester.pump(const Duration(milliseconds: 1000)); // 1500 hold + 360 fade
    await tester.pump(const Duration(milliseconds: 400));
    expect(dismissed, isTrue);
    // Peek never counts as the one-time onboarding.
    expect(await shouldShowTapZoneOnboarding(), isTrue);
  });
}
