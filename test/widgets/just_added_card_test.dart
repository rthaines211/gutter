import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/caption_box.dart';
import 'package:comic_reader_app/widgets/just_added_card.dart';

final _series = Series(
  id: 'series-1',
  name: 'A Very Long Series Title That Should Be Clamped To One Line',
  folderPath: '/comics/series-1',
  issueCount: 5,
  readCount: 0,
  coverUrl: '/library/series-1/cover',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

Future<void> _pump(WidgetTester t, {double width = 400}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      theme: AppTheme.themeData(Scheme.sepiaPaper),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Scaffold(
          body: JustAddedCard(
            series: _series,
            serverUrl: 'http://localhost:8080',
            onTap: () {},
          ),
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('is 100 wide on phone', (t) async {
    await _pump(t, width: 400);
    final size = t.getSize(find.byType(JustAddedCard));
    expect(size.width, 100);
  });

  testWidgets('is 120 wide on iPad', (t) async {
    await _pump(t, width: 900);
    final size = t.getSize(find.byType(JustAddedCard));
    expect(size.width, 120);
  });

  testWidgets('uses CaptionBox for the NEW tag', (t) async {
    await _pump(t);
    expect(
      find.descendant(
          of: find.byType(JustAddedCard), matching: find.byType(CaptionBox)),
      findsOneWidget,
    );
    expect(find.text('NEW'), findsOneWidget);
  });

  testWidgets('title clamps to a single line with ellipsis', (t) async {
    await _pump(t);
    final title = t.widget<Text>(find.text(_series.name));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
  });
}
