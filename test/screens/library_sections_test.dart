import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/library_section_header.dart';

void main() {
  testWidgets('header shows its letter and count and stays pinned', (t) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: LibrarySectionHeaderDelegate(label: 'B', count: 12),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => SizedBox(height: 100, child: Text('row $i')),
                childCount: 20,
              ),
            ),
          ],
        ),
      ),
      ),
    ));

    expect(find.text('B'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);

    // Scroll well past the header's own extent; pinned means it survives.
    await t.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await t.pump();
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('delegate does not rebuild for identical config', (t) async {
    const a = LibrarySectionHeaderDelegate(label: 'B', count: 12);
    const b = LibrarySectionHeaderDelegate(label: 'B', count: 12);
    expect(a.shouldRebuild(b), isFalse);
  });

  testWidgets('delegate rebuilds when the count changes', (t) async {
    const a = LibrarySectionHeaderDelegate(label: 'B', count: 12);
    const b = LibrarySectionHeaderDelegate(label: 'B', count: 13);
    expect(a.shouldRebuild(b), isTrue);
  });
}
