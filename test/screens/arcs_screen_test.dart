import 'package:comic_reader_app/models/arc.dart';
import 'package:comic_reader_app/providers/arc_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/screens/arcs_screen.dart';
import 'package:comic_reader_app/widgets/glass_button.dart';
import 'package:comic_reader_app/widgets/liquid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Arc _arc(String id, String name, String publisher, int present,
        {int read = 0}) =>
    Arc(
  id: id,
  name: name,
  imageUrl: '',
  selfContained: null,
  total: 0,
  present: present,
  source: 'derived',
  publisher: publisher,
  startYear: 2025,
  endYear: 2026,
  read: read,
  coverUrl: '',
  lastReadAt: null,
);

void main() {
  for (final size in const [Size(1366, 1024), Size(390, 844)]) {
    testWidgets('shows featured, publisher shelves, and filters by search '
        'at $size', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final arcs = [
        _arc('a', '"Avengers" One World Under Doom', 'Marvel', 20),
        _arc('b', 'Absolute Power', 'DC', 18),
        _arc('c', 'Blood Hunt', 'Marvel', 5),
        _arc('d', 'Gang War', 'Marvel', 4),
        _arc('e', 'Energon Universe', 'Image', 3),
      ];
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            arcsProvider.overrideWith((ref) => Stream.value(arcs)),
          ],
          child: const MaterialApp(home: ArcsScreen()),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));

      expect(find.text('Biggest in your library'), findsOneWidget);
      expect(find.text('AVENGERS'), findsOneWidget);
      expect(find.text('One World Under Doom'), findsOneWidget);
      expect(find.text('Marvel'), findsOneWidget);
      // Phone width pushes the later shelves below the lazy list's build extent.
      await t.scrollUntilVisible(
        find.text('More events'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('More events'), findsOneWidget);
      expect(find.text('In progress'), findsNothing);

      await t.scrollUntilVisible(
        find.byIcon(Icons.search_rounded),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byIcon(Icons.search_rounded));
      await t.pump();
      await t.enterText(find.byType(TextField), 'blood');
      await t.pump();
      expect(find.text('Blood Hunt'), findsOneWidget);
      expect(find.text('Biggest in your library'), findsNothing);

      await t.enterText(find.byType(TextField), 'zzz');
      await t.pump();
      expect(find.text('No arcs match'), findsOneWidget);
    });
  }

  for (final size in const [Size(1366, 1024), Size(390, 844)]) {
    testWidgets('biggest leads, in progress follows; search sits top-right '
        'at $size', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final arcs = [
        _arc('a', 'Absolute Power', 'DC', 18),
        _arc('b', 'Blood Hunt', 'Marvel', 12),
        _arc('c', 'Gang War', 'Marvel', 5, read: 2),
      ];
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            arcsProvider.overrideWith((ref) => Stream.value(arcs)),
          ],
          child: const MaterialApp(home: ArcsScreen()),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));

      // Content's right padding is 20 (measured on the glass, not its 44pt hit box).
      expect(t.getRect(find.descendant(of: find.byType(GlassButton), matching: find.byType(LiquidGlass))).right,
          moreOrLessEquals(size.width - 20, epsilon: 1));

      expect(find.text('Biggest in your library'), findsOneWidget,
          reason: 'leads the page');
      await t.scrollUntilVisible(
        find.text('In progress'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(t.getTopLeft(find.text('In progress')).dy,
          greaterThan(t.getTopLeft(find.text('Biggest in your library',
              skipOffstage: false)).dy));
    });
  }
}
