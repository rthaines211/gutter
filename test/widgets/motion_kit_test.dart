import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/comic_style.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/longbox_splash.dart';
import 'package:comic_reader_app/widgets/missing_issue_slot.dart';
import 'package:comic_reader_app/widgets/read_mark.dart';
import 'package:comic_reader_app/widgets/riffle_entry.dart';
import 'package:comic_reader_app/widgets/series_progress_bar.dart';

const _accent = Color(0xFF0A84FF);

Future<void> _pump(
  WidgetTester t,
  Widget child, {
  ComicStyle style = ComicStyle.fullPop,
  bool reducedMotion = false,
}) async {
  SharedPreferences.setMockInitialValues({'comic_style': style.name});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      theme: AppTheme.themeData(Scheme.oledBlack),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Scaffold(body: child),
      ),
    ),
  ));
}

/// A ReadMark on a sized cover, so its badge and stamp have room.
Widget _cover({required bool read, String id = 'a'}) => SizedBox(
      width: 150,
      height: 225,
      child: Stack(children: [
        Positioned.fill(child: ReadMark(issueId: id, isRead: read, accent: _accent)),
      ]),
    );

void main() {
  group('ReadMark', () {
    for (final style in ComicStyle.values) {
      testWidgets('marking read under $style animates and settles on the badge',
          (t) async {
        await _pump(t, _cover(read: false), style: style);
        expect(find.byIcon(Icons.check_rounded), findsNothing);

        await _pump(t, _cover(read: true), style: style);
        await t.pump(const Duration(milliseconds: 150));
        if (style == ComicStyle.off) {
          expect(find.textContaining('READ'), findsNothing);
        } else {
          expect(find.textContaining('READ'), findsOneWidget);
        }

        await t.pumpAndSettle();
        expect(find.textContaining('READ'), findsNothing);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('an issue already read shows the badge with no stamp', (t) async {
      await _pump(t, _cover(read: true));
      await t.pump(const Duration(milliseconds: 150));
      expect(find.textContaining('READ'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('a different issue landing in the slot does not stamp', (t) async {
      await _pump(t, _cover(read: false, id: 'a'));
      await _pump(t, _cover(read: true, id: 'b'));
      await t.pump(const Duration(milliseconds: 150));
      expect(find.textContaining('READ'), findsNothing);
    });

    testWidgets('reduced motion skips the stamp', (t) async {
      await _pump(t, _cover(read: false), reducedMotion: true);
      await _pump(t, _cover(read: true), reducedMotion: true);
      await t.pump(const Duration(milliseconds: 150));
      expect(find.textContaining('READ'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });

  group('SeriesProgressBar motion', () {
    testWidgets('finishing an issue animates, then rests on final colours', (t) async {
      await _pump(t, SeriesProgressBar(total: 6, read: 2, currentIndex: 2, accent: _accent));
      await _pump(t, SeriesProgressBar(total: 6, read: 3, currentIndex: 3, accent: _accent));
      await t.pump(const Duration(milliseconds: 100));
      // Mid-animation the fresh segment is wrapped in a Transform.
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('progress-segment-2')),
          matching: find.byType(Transform),
        ),
        findsWidgets,
      );
      await t.pumpAndSettle();
      Color seg(int i) => ((t.widget<Container>(find.byKey(ValueKey('progress-segment-$i'))))
              .decoration as BoxDecoration)
          .color!;
      expect(seg(2), AppTheme.green);
      expect(seg(3), _accent);
      expect(t.takeException(), isNull);
    });
  });

  group('MissingIssueSlot', () {
    for (final style in ComicStyle.values) {
      testWidgets('renders under $style', (t) async {
        await _pump(
          t,
          const SizedBox(width: 120, height: 220, child: MissingIssueSlot(number: 4, accent: _accent)),
          style: style,
        );
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('#4'), findsOneWidget);
        expect(find.text('#4 · Missing'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('RiffleEntry', () {
    testWidgets('keeps the child fully visible and settles with no transform', (t) async {
      await _pump(t, const RiffleEntry(index: 1, play: true, child: Text('cover')));
      expect(find.text('cover'), findsOneWidget);
      // No Opacity/FadeTransition: the tile is never hidden.
      expect(
        find.descendant(of: find.byType(RiffleEntry), matching: find.byType(FadeTransition)),
        findsNothing,
      );
      await t.pump(const Duration(milliseconds: 250));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('LongboxSplash', () {
    testWidgets('overlays the app, then gets out of the way', (t) async {
      await _pump(t, const LongboxSplash(child: Text('home')));
      await t.pump(const Duration(milliseconds: 1500));
      expect(find.text('LONGBOX'), findsOneWidget);
      expect(find.text('home'), findsOneWidget);
      await t.pump(LongboxSplash.duration);
      await t.pump();
      expect(find.text('LONGBOX'), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('keeps the child element across the hand-off', (t) async {
      await _pump(t, const LongboxSplash(child: _Counter()));
      final before = t.state(find.byType(_Counter));
      await t.pump(LongboxSplash.duration);
      await t.pump();
      expect(identical(t.state(find.byType(_Counter)), before), isTrue);
    });

    testWidgets('a tap skips to the fade and never reaches the app', (t) async {
      var taps = 0;
      await _pump(
        t,
        LongboxSplash(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 500));
      await t.tapAt(const Offset(400, 300));
      expect(taps, 0);
      // Only the fade is left: 15% of the run, well short of the full run.
      // (The first pump starts its ticker; +16ms covers float rounding.)
      await t.pump();
      await t.pump(LongboxSplash.duration * 0.15 + const Duration(milliseconds: 16));
      await t.pump();
      expect(find.text('LONGBOX'), findsNothing);
      await t.tapAt(const Offset(400, 300));
      expect(taps, 1);
    });

    testWidgets('reduced motion shows no splash at all', (t) async {
      await _pump(t, const LongboxSplash(child: Text('home')), reducedMotion: true);
      await t.pump();
      expect(find.text('LONGBOX'), findsNothing);
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
