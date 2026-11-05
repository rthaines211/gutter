import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/models/comic_info.dart';
import 'package:comic_reader_app/models/reading_progress.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/resume_hero_card.dart';

// The title sits on the comic-yellow caption box in every scheme, so it must
// be a literal dark ink, never scheme.tx (white on OLED would vanish).

String _encodeComicId(String path) =>
    base64Url.encode(utf8.encode(path)).replaceAll('=', '');

final _progress = ReadingProgress(
  comicId: _encodeComicId(
      'The Amazing Spider-Man/The Amazing Spider-Man 042.cbz'),
  currentPage: 9,
  totalPages: 20,
  seriesId: 'series-1',
);

Future<void> _pump(WidgetTester t, Scheme scheme, {ComicInfo? info}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      heroComicInfoProvider.overrideWith((ref, id) async => info),
    ],
    child: MaterialApp(
      theme: AppTheme.themeData(scheme),
      home: Scaffold(
        body: ResumeHeroCard(
          progress: _progress,
          serverUrl: 'http://localhost:8080',
          onTap: () {},
        ),
      ),
    ),
  ));
}

double _luminance(Finder finder, WidgetTester t) {
  final text = t.widget<Text>(finder);
  final color = text.style?.color;
  expect(color, isNotNull, reason: 'title Text has no explicit color');
  return color!.computeLuminance();
}

void main() {
  for (final scheme in [Scheme.sepiaPaper, Scheme.oledBlack]) {
    testWidgets('title is dark on the yellow caption (${scheme.dark ? 'dark' : 'light'} scheme)',
        (t) async {
      await _pump(t, scheme);
      final titleFinder = find.text('The Amazing Spider-Man 042');
      expect(titleFinder, findsOneWidget);
      expect(_luminance(titleFinder, t), lessThan(0.1));
      expect(find.text('TURN THE PAGE'), findsOneWidget);
    });
  }

  testWidgets('phone layout lays out without overflow', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await _pump(t, Scheme.oledBlack);
    expect(t.takeException(), isNull);
    expect(find.text('MEANWHILE…'), findsOneWidget);
  });

  testWidgets('iPad layout fits long metadata', (t) async {
    t.view.physicalSize = const Size(820, 1180);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await _pump(t, Scheme.oledBlack,
        info: ComicInfo(
          title: 'A very long story title that keeps going and going for ages',
          series: 'Blackest Night Omnibus Deluxe Edition',
          number: '1',
          summary: 'The war between the Corps rages ' * 12,
          pageCount: 1536,
          chapters: [
            for (var i = 0; i < 93; i++)
              ComicInfoChapter(page: i * 16, title: '"Psycho Piracy" Blackest Night: Superman #$i'),
          ],
        ));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('Now in Blackest Night: Superman #0'), findsOneWidget);
  });

  testWidgets('iPad without summary shows credits + facts', (t) async {
    t.view.physicalSize = const Size(820, 1180);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await _pump(t, Scheme.oledBlack,
        info: const ComicInfo(
            title: '',
            writer: 'Paul Dini',
            penciller: 'Dustin Nguyen',
            publisher: 'DC Comics',
            pageCount: 20));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.textContaining('Paul Dini', findRichText: true), findsOneWidget);
    expect(find.text('20 PAGES'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('iPad with no summary or credits grows the title', (t) async {
    t.view.physicalSize = const Size(820, 1180);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // Test font glyphs are 1em squares, so keep the title short.
    await _pump(t, Scheme.oledBlack,
        info: const ComicInfo(title: '', series: 'Batman', number: '1', pageCount: 20));
    await t.pump();
    expect(t.takeException(), isNull);
    final title = t.widget<Text>(find.text('Batman #1'));
    expect(title.style!.fontSize, greaterThan(52));
    expect(find.text('20 PAGES'), findsOneWidget);
  });

  test('trustedChapters parses ComicInfo titles, rejects junk', () {
    final ok = trustedChapters(const [
      ComicInfoChapter(page: 40, title: '"Psycho Piracy" Blackest Night: Superman #2'),
      ComicInfoChapter(page: 0, title: '"Prologue" Green Lantern V4 #43 (2009)'),
    ]);
    expect(ok.map((c) => c.page), [0, 40]);
    expect(ok[1].story, 'Psycho Piracy');
    expect(ok[1].issue, 'Blackest Night: Superman #2');
    expect(ok[0].issue, 'Green Lantern V4 #43');

    expect(
        trustedChapters(const [
          ComicInfoChapter(page: 0, title: '"Prologue" Green Lantern #43'),
          ComicInfoChapter(page: 9, title: 'AVENGERS #24 oG : N'),
        ]),
        isEmpty);
  });

  test('publisherLogo', () {
    expect(publisherLogo('Marvel'), 'marvel');
    expect(publisherLogo('DC Comics'), 'dc');
    expect(publisherLogo('Image Comics'), 'image');
    expect(publisherLogo('Dark Horse Comics'), 'darkhorse');
    expect(publisherLogo('IDW Publishing'), 'idw');
    expect(publisherLogo('BOOM! Studios'), isNull);
    expect(publisherLogo('DCP Digital'), isNull);
  });

  test('progressCells', () {
    expect(progressCells(currentPage: 11, totalPages: 27), (27, 11));
    expect(progressCells(currentPage: 0, totalPages: 1536), (30, 0));
    expect(progressCells(currentPage: 1535, totalPages: 1536), (30, 29));
    expect(progressCells(currentPage: 448, totalPages: 1536, chapterIndex: 3, chapterCount: 12), (12, 3));
    // >40 chapters falls back to page buckets.
    expect(progressCells(currentPage: 448, totalPages: 1536, chapterIndex: 23, chapterCount: 93).$1, 30);
  });

  test('timeLeftLabel', () {
    expect(timeLeftLabel(30), '15 MIN');
    expect(timeLeftLabel(400), '3 HR');
  });
}
