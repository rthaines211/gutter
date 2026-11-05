import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/widgets/filmstrip_scrubber.dart';
import 'package:comic_reader_app/widgets/page_jump_pill.dart';

Widget _wrap(Widget child, Size size, {ThemeData? theme}) {
  return ProviderScope(
    child: MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        theme: theme,
        home:
            Scaffold(body: Align(alignment: Alignment.topCenter, child: child)),
      ),
    ),
  );
}

void main() {
  Widget scrubber({
    List<int> chapterPages = const [],
    VoidCallback? onOpenGrid,
    Color accent = AppTheme.accent,
  }) {
    return FilmstripScrubber(
      onOpenGrid: onOpenGrid,
      accent: accent,
      currentPage: 10,
      totalPages: 30,
      pageUrlBuilder: (p) => 'https://example.com/$p.jpg',
      onPageSelected: (_) {},
      chapterPages: chapterPages,
    );
  }

  Widget big({int current = 500, ValueChanged<int>? onSelected}) =>
      FilmstripScrubber(
        currentPage: current,
        totalPages: 1000,
        pageUrlBuilder: (p) => 'https://example.com/$p.jpg',
        onPageSelected: onSelected ?? (_) {},
      );
  Finder thumb(int p) => find.byKey(ValueKey('filmstrip.thumb.$p'));
  double stripMid(WidgetTester t) => t.getCenter(find.byType(ListView)).dx;

  testWidgets('thumbs decode at thumbnail size, not full page resolution',
      (tester) async {
    tester.view.physicalSize = const Size(2048, 2732);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        ProviderScope(child: MaterialApp(home: Scaffold(body: big()))));
    await tester.pump();
    final images =
        tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(images, isNotEmpty);
    // One width for every thumb (the enlarged current one's 68pt), so a page
    // keeps one cache entry as it becomes current.
    for (final img in images) {
      expect(img.memCacheWidth, 136);
    }
  });

  testWidgets('strip builds lazily: a 1000-page issue builds only what shows',
      (tester) async {
    await tester.pumpWidget(_wrap(big(), const Size(1024, 1366)));
    await tester.pump();
    final built = find.byType(AnimatedContainer).evaluate().length;
    expect(built, greaterThan(9));
    expect(built, lessThan(60));
  });

  for (final size in const [Size(390, 844), Size(1024, 1366)]) {
    testWidgets('strip centres the current page (${size.width})',
        (tester) async {
      await tester.pumpWidget(_wrap(big(), size));
      await tester.pump();
      expect(tester.getCenter(thumb(500)).dx,
          moreOrLessEquals(stripMid(tester), epsilon: 1));
    });
  }

  testWidgets('strip re-centres when the page changes', (tester) async {
    const size = Size(1024, 1366);
    await tester.pumpWidget(_wrap(big(), size));
    await tester.pump();
    await tester.pumpWidget(_wrap(big(current: 700), size));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getCenter(thumb(700)).dx,
        moreOrLessEquals(stripMid(tester), epsilon: 1));
  });

  testWidgets('strip scrolls with a drag and stays where the finger left it',
      (tester) async {
    await tester.pumpWidget(_wrap(big(), const Size(1024, 1366)));
    await tester.pump();
    expect(thumb(530), findsNothing);
    await tester.drag(thumb(500), const Offset(-900, 0));
    await tester.pump(const Duration(seconds: 1));
    expect(thumb(510), findsOneWidget);
    expect(thumb(500).hitTestable(), findsNothing,
        reason: 'no snap back to the current page after a user scroll');
  });

  testWidgets('tapping a thumbnail jumps to that page', (tester) async {
    int? picked;
    await tester.pumpWidget(_wrap(
        big(onSelected: (p) => picked = p), const Size(1024, 1366)));
    await tester.pump();
    await tester.tap(thumb(502));
    expect(picked, 502);
  });

  testWidgets('renders an amber stripe on a chapter-start thumbnail',
      (tester) async {
    await tester.pumpWidget(
        _wrap(scrubber(chapterPages: const [10]), const Size(390, 844)));
    await tester.pump();

    // currentPage=10 is a chapter start; its thumb should carry the 3pt
    // amber stripe container (height 3, distinct from the 96/68 thumb size).
    final stripeFinder = find.byWidgetPredicate((w) =>
        w is Container &&
        w.constraints?.maxHeight == 3 &&
        (w.color == const Color(0xFFFFB800)));
    expect(stripeFinder, findsOneWidget);
  });

  testWidgets('no amber stripe when no page is a chapter start',
      (tester) async {
    await tester.pumpWidget(_wrap(scrubber(), const Size(390, 844)));
    await tester.pump();

    final stripeFinder = find.byWidgetPredicate((w) =>
        w is Container &&
        w.constraints?.maxHeight == 3 &&
        (w.color == const Color(0xFFFFB800)));
    expect(stripeFinder, findsNothing);
  });

  testWidgets('hosts a PageJumpPill instead of the old page-count texts',
      (tester) async {
    await tester.pumpWidget(_wrap(scrubber(), const Size(390, 844)));
    await tester.pump();

    expect(find.byType(PageJumpPill), findsOneWidget);
    expect(find.text('11 / 30'), findsOneWidget);
  });

  testWidgets('grid button is a 44x44 touch target', (tester) async {
    await tester.pumpWidget(
        _wrap(scrubber(onOpenGrid: () {}), const Size(390, 844)));
    final size =
        tester.getSize(find.byKey(const Key('filmstripScrubber.gridButton')));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('page pill follows the slider while dragging', (tester) async {
    await tester.pumpWidget(_wrap(scrubber(), const Size(390, 844)));
    final g = await tester.startGesture(tester.getCenter(find.byType(Slider)));
    await g.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(find.text('11 / 30'), findsNothing,
        reason: 'the pill shows the dragged-to page, not the committed one');
    await g.up();
  });

  testWidgets('slider uses scheme and accent colors, not white',
      (tester) async {
    const accent = Color(0xFFFF2D95);
    await tester.pumpWidget(_wrap(scrubber(accent: accent), const Size(390, 844),
        theme: AppTheme.themeData(Scheme.sepiaPaper)));
    final data = tester
        .widget<SliderTheme>(find
            .ancestor(of: find.byType(Slider), matching: find.byType(SliderTheme))
            .first)
        .data;
    expect(data.inactiveTrackColor, Scheme.sepiaPaper.hairStrong);
    expect(data.thumbColor, accent);
    expect(data.activeTrackColor, accent);
  });
}
