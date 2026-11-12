import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/connectivity_provider.dart';
import 'package:comic_reader_app/providers/library_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/screens/library_screen.dart';
import 'package:comic_reader_app/widgets/library_mode_pill.dart';
import 'package:comic_reader_app/widgets/library_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

Series _series(int i) => Series(
      id: 's$i',
      name: 'Series ${i.toString().padLeft(3, '0')}',
      folderPath: '',
      issueCount: 1,
      readCount: 0,
      coverUrl: '',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Future<void> pumpLibrary(WidgetTester t) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      connectivityProvider.overrideWith(_Online.new),
      isCustomSourceProvider.overrideWithValue(false),
      libraryProvider.overrideWith(
          (ref) => Stream.value([for (var i = 0; i < 120; i++) _series(i)])),
    ],
    child: const MaterialApp(home: LibraryScreen()),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('mode pill and sort button sit at the right edge with a library',
      (t) async {
    t.view.physicalSize = const Size(1024, 1366); // iPad portrait
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await pumpLibrary(t);
    final sort = find.ancestor(of: find.byIcon(Icons.sort), matching: find.byType(Container)).first;
    expect(find.byType(LibraryModePill), findsOneWidget);
    // Header padding is 20 on the right.
    expect(t.getTopRight(sort).dx, moreOrLessEquals(1024 - 20, epsilon: 1));
    expect(t.getTopRight(find.byType(LibraryModePill)).dx,
        moreOrLessEquals(t.getTopLeft(sort).dx - 8, epsilon: 1));
  });

  // Phone layout (<768). At 390 the title row overflows 129px under the
  // Ahem test font (true on main too; real fonts fit), so 600 stands in.
  for (final size in const [Size(1366, 1024), Size(600, 900)]) {
    testWidgets('header stays pinned while the grid scrolls at $size',
        (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await pumpLibrary(t);

      final search = find.byType(LibrarySearchBar);
      expect(search, findsOneWidget);
      final before = t.getTopLeft(search);
      // Pull-to-refresh spinner starts below the pinned header.
      await t.pump();
      expect(t.widget<RefreshIndicator>(find.byType(RefreshIndicator)).edgeOffset,
          greaterThan(t.getBottomLeft(search).dy));
      expect(find.text('Series 000'), findsOneWidget);

      await t.drag(find.byType(CustomScrollView), const Offset(0, -1500));
      await t.pump(const Duration(milliseconds: 500));

      expect(find.text('Series 000'), findsNothing, reason: 'grid scrolled');
      expect(search, findsOneWidget);
      expect(t.getTopLeft(search), before);
      expect(find.text('Library'), findsOneWidget);
    });
  }

  // Too short to pin (phone landscape, or the keyboard up): the header
  // scrolls away with the grid instead of squeezing it to nothing.
  for (final (size, keyboard) in const [
    (Size(844, 390), 0.0),
    (Size(600, 700), 350.0),
  ]) {
    testWidgets('short body ($size, keyboard $keyboard): header scrolls, '
        'no overflow', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      t.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(t.view.reset);
      await pumpLibrary(t);

      final search = find.byType(LibrarySearchBar);
      expect(search, findsOneWidget);
      expect(t.takeException(), isNull, reason: 'no overflow');
      await t.pump();
      expect(t.widget<RefreshIndicator>(find.byType(RefreshIndicator)).edgeOffset,
          0, reason: 'header scrolls with the list, so does the spinner');

      await t.drag(find.byType(CustomScrollView), const Offset(0, -150));
      await t.pump(const Duration(milliseconds: 500));
      expect(t.takeException(), isNull);
      final title = find.text('Library');
      expect(title.evaluate().isEmpty || t.getTopLeft(title).dy < 0, isTrue,
          reason: 'the header scrolled away with the grid');
    });
  }
}
