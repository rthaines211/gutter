import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/cover_flight_route.dart';

/// The reveal handed to the last reader built.
CoverReveal? _reveal;

/// The tile's left edge; null takes it off the shelf.
final _tileLeft = ValueNotifier<double?>(100);

/// A shelf with one anchored cover at (100, 100) 60×90; tapping it opens
/// [comicId] via [readerRoute].
Future<void> _pumpShelf(WidgetTester t, {String comicId = 'c1', bool reduce = false}) async {
  t.view.physicalSize = const Size(800, 600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  _tileLeft.value = 100;
  await t.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
      child: child!,
    ),
    home: ValueListenableBuilder<double?>(
      valueListenable: _tileLeft,
      builder: (context, left, _) => Stack(children: [
        if (left != null) Positioned(
          left: left,
          top: 100,
          width: 60,
          height: 90,
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              readerRoute(context, comicId: comicId, builder: (_) => Builder(builder: (context) {
                _reveal = CoverReveal.of(context);
                return const Text('reader');
              })),
            ),
            child: const CoverAnchor(
              comicId: 'c1',
              imageUrl: 'http://test/cover',
              child: ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      ]),
    ),
  ));
}

Finder get _flyer => find.byType(ClipRRect);

void main() {
  testWidgets('the cover flies to the contain rect, holds, then hands over to the reader', (t) async {
    await _pumpShelf(t);
    await t.tap(find.byType(CoverAnchor));
    await t.pump(); // route pushed (its first frame is offstage)
    await t.pump(); // flight at its start

    expect(t.getRect(_flyer), const Rect.fromLTWH(100, 100, 60, 90));
    final reader = find.ancestor(of: find.text('reader'), matching: find.byType(Opacity)).first;
    expect(t.widget<Opacity>(reader).opacity, 0);

    await t.pump(const Duration(milliseconds: 380)); // flight done
    // 2:3 contained in 800×600: 400×600, centred.
    final landed = t.getRect(_flyer);
    expect(landed.left, closeTo(200, 0.5));
    expect(landed.width, closeTo(400, 0.5));
    expect(landed.height, closeTo(600, 0.5));

    // The cover holds while the reader loads.
    await t.pump(const Duration(seconds: 1));
    expect(t.widget<Opacity>(reader).opacity, 0);
    expect(t.widget<Visibility>(find.byType(Visibility)).visible, isTrue);

    var shown = false;
    _reveal!.shown.then((_) => shown = true);
    _reveal!.ready();
    await t.pump(); // ready lands, cross-fade starts
    await t.pump(); // its first tick
    await t.pump(const Duration(milliseconds: 170)); // cross-fade done
    await t.pump();
    expect(shown, isTrue);
    expect(t.widget<Opacity>(reader).opacity, 1);
    expect(t.widget<Visibility>(find.byType(Visibility)).visible, isFalse);

    // Closing flies the cover back and drops the reader.
    t.state<NavigatorState>(find.byType(Navigator)).pop();
    await t.pump();
    expect(t.widget<Visibility>(find.byType(Visibility)).visible, isTrue);
    await t.pump(const Duration(milliseconds: 600));
    await t.pump();
    expect(find.text('reader'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('closing flies to where the tile is now, and settles into it', (t) async {
    await _pumpShelf(t);
    await t.tap(find.byType(CoverAnchor));
    await t.pump();
    await t.pump(const Duration(milliseconds: 380));
    _reveal!.ready();
    await t.pump();
    await t.pump();
    await t.pump(const Duration(milliseconds: 170));

    _tileLeft.value = 500; // the shelf reordered while reading
    await t.pump();
    t.state<NavigatorState>(find.byType(Navigator)).pop();
    await t.pump(); // closing starts; home looked up after this frame
    await t.pump(const Duration(milliseconds: 210)); // halfway
    final mid = t.getRect(_flyer);
    expect(mid.left, greaterThan(300)); // heading right, toward the new spot
    await t.pump(const Duration(milliseconds: 205));
    expect(t.getRect(_flyer).left, closeTo(500, 6));
    await t.pump(const Duration(milliseconds: 20));
    expect(find.text('reader'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('closing with the tile gone fades the cover where it is', (t) async {
    await _pumpShelf(t);
    await t.tap(find.byType(CoverAnchor));
    await t.pump();
    await t.pump(const Duration(milliseconds: 380));
    _reveal!.ready();
    await t.pump();
    await t.pump();
    await t.pump(const Duration(milliseconds: 170));

    _tileLeft.value = null;
    await t.pump();
    t.state<NavigatorState>(find.byType(Navigator)).pop();
    await t.pump();
    await t.pump(const Duration(milliseconds: 210));
    expect(t.getRect(_flyer).left, closeTo(200, 0.5)); // stays put
    final fade = find.ancestor(of: _flyer, matching: find.byType(Opacity)).first;
    expect(t.widget<Opacity>(fade).opacity, lessThan(1));
    await t.pump(const Duration(milliseconds: 230));
    expect(find.text('reader'), findsNothing);
  });

  testWidgets('a reader that never reports is shown after the hold limit', (t) async {
    await _pumpShelf(t);
    await t.tap(find.byType(CoverAnchor));
    await t.pump();
    await t.pump(const Duration(milliseconds: 380));
    await t.pump(const Duration(seconds: 4));
    await t.pump(const Duration(milliseconds: 170));
    await t.pump();
    final reader = find.ancestor(of: find.text('reader'), matching: find.byType(Opacity)).first;
    expect(t.widget<Opacity>(reader).opacity, 1);
  });

  testWidgets('no anchor for the comic: a plain cross-fade, no flight', (t) async {
    await _pumpShelf(t, comicId: 'other');
    await t.tap(find.byType(CoverAnchor));
    await t.pump();
    await t.pump();
    expect(find.text('reader'), findsOneWidget);
    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.descendant(of: find.byType(Visibility), matching: find.byType(ClipRRect)), findsNothing);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('reader'), findsOneWidget);
  });

  testWidgets('Reduce Motion: no flight', (t) async {
    await _pumpShelf(t, reduce: true);
    await t.tap(find.byType(CoverAnchor));
    await t.pump();
    await t.pump();
    expect(find.text('reader'), findsOneWidget);
    expect(find.descendant(of: find.byType(Visibility), matching: find.byType(ClipRRect)), findsNothing);
  });
}
