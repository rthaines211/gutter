import 'dart:convert';

import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/models/reading_progress.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/caption_box.dart';
import 'package:comic_reader_app/widgets/up_next_card.dart';

String _encodeComicId(String path) =>
    base64Url.encode(utf8.encode(path)).replaceAll('=', '');

final _progress = ReadingProgress(
  comicId: _encodeComicId(
      'The Amazing Spider-Man/The Amazing Spider-Man 042 Some Very Long Issue Title Here.cbz'),
  currentPage: 9,
  totalPages: 20,
  seriesId: 'series-1',
);

Future<void> _pump(WidgetTester t, {double width = 400}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      issueCoverPathsProvider.overrideWith((ref) => Stream.value(const {})),
    ],
    child: MaterialApp(
      theme: AppTheme.themeData(Scheme.sepiaPaper),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Scaffold(
          body: UpNextCard(
            progress: _progress,
            serverUrl: 'http://localhost:8080',
            onTap: () {},
          ),
        ),
      ),
    ),
  ));
}

void main() {
  // The Read tab's shelf was a fixed 230 tall; the card is taller (cover at
  // 2:3 plus two text lines), so the title and page line were cut off.
  for (final width in [400.0, 900.0]) {
    testWidgets('fits its shelf at $width wide', (t) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await t.pumpWidget(ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          issueCoverPathsProvider.overrideWith((ref) => Stream.value(const {})),
        ],
        child: MaterialApp(
          theme: AppTheme.themeData(Scheme.sepiaPaper),
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 800)),
            child: Scaffold(
              body: Builder(
                builder: (context) => Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    height: UpNextCard.shelfHeight(context),
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        UpNextCard(
                          progress: _progress,
                          serverUrl: 'http://localhost:8080',
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('is 130 wide on phone', (t) async {
    await _pump(t, width: 400);
    final size = t.getSize(find.byType(UpNextCard));
    expect(size.width, 130);
  });

  testWidgets('is 150 wide on iPad', (t) async {
    await _pump(t, width: 900);
    final size = t.getSize(find.byType(UpNextCard));
    expect(size.width, 150);
  });

  testWidgets('uses CaptionBox for the NEXT tag', (t) async {
    await _pump(t);
    expect(
      find.descendant(of: find.byType(UpNextCard), matching: find.byType(CaptionBox)),
      findsOneWidget,
    );
    expect(find.text('NEXT'), findsOneWidget);
  });

  testWidgets('title clamps to a single line with ellipsis', (t) async {
    await _pump(t);
    final title = t.widget<Text>(find.text(
        'The Amazing Spider-Man 042 Some Very Long Issue Title Here'));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  testWidgets('shows a mono page sub-line', (t) async {
    await _pump(t);
    expect(find.text('P.10/20'), findsOneWidget);
  });
}
