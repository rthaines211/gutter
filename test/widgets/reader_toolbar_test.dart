import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/reader_toolbar.dart';

Future<void> _pump(
  WidgetTester t, {
  String? lead,
  int pagesLeft = 24,
  bool isSettingsOpen = false,
  Duration? Function()? sleepRemaining,
  VoidCallback? onSleepTimer,
  bool rail = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: AppTheme.themeData(Scheme.oledBlack),
        home: Scaffold(
          body: ReaderTopBar(
            title: 'Batman #80',
            subtitleLead: lead,
            pagesLeft: pagesLeft,
            isBookmarked: false,
            isSettingsOpen: isSettingsOpen,
            isMoreOpen: false,
            onClose: () {},
            onBookmark: () {},
            onSettings: () {},
            onMore: () {},
            sleepRemaining: sleepRemaining,
            onSleepTimer: onSleepTimer,
            rail: rail,
          ),
        ),
      ),
    ),
  );
}

BoxDecoration _aaFill(WidgetTester t) => t
    .widget<Container>(find.ancestor(
      of: find.text('Aa'),
      matching: find.byType(Container),
    ).first)
    .decoration as BoxDecoration;

void main() {
  testWidgets('sub-line is the uppercased lead then minutes left', (t) async {
    await _pump(t, lead: 'City of Bane Part 6');
    expect(find.text('Batman #80'), findsOneWidget);
    expect(find.text('CITY OF BANE PART 6 · 12 MIN LEFT'), findsOneWidget);
  });

  testWidgets('sub-line without a lead is just minutes left', (t) async {
    await _pump(t);
    expect(find.text('12 MIN LEFT'), findsOneWidget);
  });

  testWidgets('long reads use the shared hours format', (t) async {
    await _pump(t, pagesLeft: 288); // 144 min
    expect(find.text('2.4H'), findsOneWidget);
  });

  testWidgets('no pages left drops the minutes part', (t) async {
    await _pump(t, lead: 'City of Bane Part 6', pagesLeft: 0);
    expect(find.text('CITY OF BANE PART 6'), findsOneWidget);
    expect(find.textContaining('MIN LEFT'), findsNothing);
  });

  testWidgets('sub-line ellipsizes on a single line', (t) async {
    await _pump(t, lead: 'City of Bane Part 6');
    final subtitle = t.widget<Text>(
      find.text('CITY OF BANE PART 6 · 12 MIN LEFT'),
    );
    expect(subtitle.maxLines, 1);
    expect(subtitle.overflow, TextOverflow.ellipsis);
  });

  testWidgets('Aa pill fills accent only when settings open', (t) async {
    await _pump(t);
    expect(_aaFill(t).color, isNot(AppTheme.accent));
    await _pump(t, isSettingsOpen: true);
    expect(_aaFill(t).color, AppTheme.accent);
  });

  testWidgets('Aa and More carry semantic labels', (t) async {
    await _pump(t);
    expect(find.bySemanticsLabel('Reader settings'), findsOneWidget);
    expect(find.bySemanticsLabel('More'), findsOneWidget);
  });

  testWidgets('action buttons are 44pt touch targets', (t) async {
    await _pump(t);
    for (final k in ['reader.back', 'reader.bookmark', 'reader.aa', 'reader.more']) {
      final s = t.getSize(find.byKey(Key(k)));
      expect(s.width, greaterThanOrEqualTo(44), reason: k);
      expect(s.height, greaterThanOrEqualTo(44), reason: k);
    }
  });

  group('moon', () {
    testWidgets('moon is a 44pt target between title and bookmark', (t) async {
      await _pump(t, sleepRemaining: () => null, onSleepTimer: () {});
      final moon = find.byKey(const Key('reader.sleep'));
      final s = t.getSize(moon);
      expect(s.width, greaterThanOrEqualTo(44));
      expect(s.height, greaterThanOrEqualTo(44));
      expect(t.getTopLeft(moon).dx,
          greaterThan(t.getTopLeft(find.text('Batman #80')).dx));
      expect(t.getTopRight(moon).dx,
          lessThanOrEqualTo(t.getTopLeft(find.byKey(const Key('reader.bookmark'))).dx));
    });

    testWidgets('off: semantics \'Sleep timer off\', outline icon, no label',
        (t) async {
      await _pump(t, sleepRemaining: () => null, onSleepTimer: () {});
      expect(find.bySemanticsLabel('Sleep timer off'), findsOneWidget);
      expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
      expect(find.byIcon(Icons.bedtime), findsNothing);
      expect(find.textContaining(RegExp(r'^\d+m$')), findsNothing);
    });

    testWidgets('on: shows ceil minutes', (t) async {
      await _pump(t,
          sleepRemaining: () => const Duration(minutes: 26, seconds: 1),
          onSleepTimer: () {});
      expect(find.text('27m'), findsOneWidget);
      expect(find.byIcon(Icons.bedtime), findsOneWidget);
      expect(find.bySemanticsLabel('Sleep timer, 27 minutes left'),
          findsOneWidget);
    });

    testWidgets('label ticks', (t) async {
      final deadline = clock.now().add(const Duration(minutes: 26, seconds: 1));
      await _pump(t,
          sleepRemaining: () => deadline.difference(clock.now()),
          onSleepTimer: () {});
      expect(find.text('27m'), findsOneWidget);
      await t.pump(const Duration(minutes: 1));
      expect(find.text('26m'), findsOneWidget);
      await t.pumpWidget(const SizedBox()); // stop the tick timer
    });

    testWidgets('tap calls onSleepTimer', (t) async {
      var taps = 0;
      await _pump(t, sleepRemaining: () => null, onSleepTimer: () => taps++);
      await t.tap(find.byKey(const Key('reader.sleep')));
      expect(taps, 1);
    });

    testWidgets('hidden without handler', (t) async {
      await _pump(t);
      expect(find.byKey(const Key('reader.sleep')), findsNothing);
    });
  });

  testWidgets('rail: controls stack down the right edge, close beside the title top-left',
      (t) async {
    await _pump(
      t,
      rail: true,
      // A running timer: its pill is wider than the rail and must scale down.
      sleepRemaining: () => const Duration(minutes: 45),
      onSleepTimer: () {},
    );
    expect(t.takeException(), isNull);
    final back = t.getRect(find.byKey(const Key('reader.back')));
    final bookmark = t.getRect(find.byKey(const Key('reader.bookmark')));
    final more = t.getRect(find.byKey(const Key('reader.more')));
    final title = t.getRect(find.text('Batman #80'));
    expect(more.center.dx, moreOrLessEquals(bookmark.center.dx));
    expect(more.top, greaterThan(bookmark.bottom));
    expect(bookmark.left, greaterThan(title.right));
    // Close is in the title tag, just left of the title.
    expect(back.right, lessThanOrEqualTo(title.left));
    expect(back.center.dy, closeTo(title.center.dy, 20));
  });
}
