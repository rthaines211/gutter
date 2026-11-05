import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/widgets/reader_more_menu.dart';

const _labels = [
  'Chapters',
  'All pages',
  'Recap so far',
  'Clip a panel',
  'Issue details',
  'Credits',
];

/// Opens the menu as a route, the way the reader does, so items can pop it.
Future<List<String>> _open(WidgetTester t,
    {bool recap = true,
    bool clip = true,
    bool details = true,
    bool credits = true,
    bool fixPanels = false,
    bool fixBalloons = false}) async {
  final calls = <String>[];
  await t.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: AppTheme.themeData(Scheme.oledBlack),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => ReaderMoreMenu(
              onChapters: () => calls.add('Chapters'),
              onAllPages: () => calls.add('All pages'),
              onRecap: recap ? () => calls.add('Recap so far') : null,
              onClipPanel: clip ? () => calls.add('Clip a panel') : null,
              onIssueDetails:
                  details ? () => calls.add('Issue details') : null,
              onCredits: credits ? () => calls.add('Credits') : null,
              onFixPanels:
                  fixPanels ? () => calls.add('Fix panels') : null,
              onFixBalloons:
                  fixBalloons ? () => calls.add('Fix balloons') : null,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return calls;
}

void main() {
  testWidgets('shows all six items', (t) async {
    await _open(t);
    for (final l in _labels) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
  });

  testWidgets('recap is absent without a callback', (t) async {
    await _open(t, recap: false);
    expect(find.text('Recap so far'), findsNothing);
    expect(find.text('Chapters'), findsOneWidget);
  });

  testWidgets('clip is absent without a callback (scroll mode)', (t) async {
    await _open(t, clip: false);
    expect(find.text('Clip a panel'), findsNothing);
    expect(find.text('Chapters'), findsOneWidget);
  });

  testWidgets('issue details is absent without a callback (no series)',
      (t) async {
    await _open(t, details: false);
    expect(find.text('Issue details'), findsNothing);
    expect(find.text('Chapters'), findsOneWidget);
  });

  testWidgets('credits is absent without a callback', (t) async {
    await _open(t, credits: false);
    expect(find.text('Credits'), findsNothing);
    expect(find.text('Chapters'), findsOneWidget);
  });

  testWidgets('fix items absent without callbacks', (t) async {
    await _open(t);
    expect(find.text('Fix panels'), findsNothing);
    expect(find.text('Fix balloons'), findsNothing);
  });

  testWidgets('fix items shown when callbacks given', (t) async {
    await _open(t, fixPanels: true, fixBalloons: true);
    expect(find.text('Fix panels'), findsOneWidget);
    expect(find.text('Fix balloons'), findsOneWidget);
  });

  for (final l in _labels) {
    testWidgets('$l pops the menu and calls its callback', (t) async {
      final calls = await _open(t);
      await t.tap(find.text(l));
      await t.pumpAndSettle();
      expect(calls, [l]);
      expect(find.byType(ReaderMoreMenu), findsNothing);
    });
  }
}
