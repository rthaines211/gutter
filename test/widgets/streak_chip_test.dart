import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/comic_style.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/widgets/streak_chip.dart';

const _accent = Color(0xFF0A84FF);
final _comic = ComicTokens.of(ComicStyle.fullPop, Scheme.sepiaPaper, _accent);

Future<void> _pump(WidgetTester t, int days) => t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StreakChip(days: days, comic: _comic),
      ),
    ));

void main() {
  testWidgets('shows the day count and label', (t) async {
    await _pump(t, 6);
    expect(find.text('6'), findsOneWidget);
    expect(find.textContaining('DAY STREAK'), findsOneWidget);
  });

  testWidgets('renders nothing at zero', (t) async {
    await _pump(t, 0);
    expect(find.textContaining('STREAK'), findsNothing);
  });

  testWidgets('singular label at one day', (t) async {
    await _pump(t, 1);
    expect(find.textContaining('DAY STREAK'), findsOneWidget);
    expect(find.textContaining('DAYS'), findsNothing);
  });
}
