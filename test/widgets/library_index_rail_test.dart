import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/library_index_rail.dart';

const _accent = Color(0xFF0A84FF);
const _allKeys = ['#', 'A', 'B', 'C'];

Widget _host({required Set<String> present, void Function(String)? onTap}) =>
    MaterialApp(
      home: Scaffold(
        body: LibraryIndexRail(
          allKeys: _allKeys,
          presentKeys: present,
          accent: _accent,
          onTap: onTap ?? (_) {},
        ),
      ),
    );

void main() {
  testWidgets('renders every key', (t) async {
    await t.pumpWidget(_host(present: {'A'}));
    for (final k in _allKeys) {
      expect(find.text(k), findsOneWidget);
    }
  });

  testWidgets('present letters use the accent, absent ones do not', (t) async {
    await t.pumpWidget(_host(present: {'A'}));
    expect(t.widget<Text>(find.text('A')).style!.color, _accent);
    expect(t.widget<Text>(find.text('B')).style!.color, isNot(_accent));
  });

  testWidgets('tapping a present letter reports it', (t) async {
    String? tapped;
    await t.pumpWidget(_host(present: {'A'}, onTap: (k) => tapped = k));
    await t.tap(find.text('A'));
    expect(tapped, 'A');
  });

  testWidgets('tapping an absent letter reports nothing', (t) async {
    String? tapped;
    await t.pumpWidget(_host(present: {'A'}, onTap: (k) => tapped = k));
    await t.tap(find.text('B'), warnIfMissed: false);
    expect(tapped, isNull);
  });

  testWidgets('dragging along the rail scrubs through present sections',
      (t) async {
    // The rail is a Stack sibling over the scroll view, so it wins the hit
    // test for its whole box. Before it handled drags, a drag here was
    // swallowed and the list simply did not scroll — a ~405pt dead band down
    // the right edge with the full 27-key set. Scrubbing is both the fix and
    // the gesture iOS users expect from an A–Z rail.
    final keys = ['#', ...List.generate(26, (i) => String.fromCharCode(65 + i))];
    final fired = <String>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibraryIndexRail(
          allKeys: keys,
          presentKeys: const {'A', 'B', 'C', 'M', 'W'},
          accent: _accent,
          onTap: fired.add,
        ),
      ),
    ));

    final r = t.getRect(find.byType(LibraryIndexRail));
    final g = await t.startGesture(Offset(r.center.dx, r.top + 5));
    for (var y = r.top + 5; y < r.bottom - 5; y += 6) {
      await g.moveTo(Offset(r.center.dx, y));
      await t.pump();
    }
    await g.up();
    await t.pumpAndSettle();

    expect(fired, ['A', 'B', 'C', 'M', 'W'],
        reason: 'scrub should hit each present section once, in order, '
            'and skip absent letters');
  });

  testWidgets('a scrub does not re-fire while inside one letter', (t) async {
    final fired = <String>[];
    await t.pumpWidget(_host(present: {'A', 'B'}, onTap: fired.add));
    final r = t.getRect(find.byType(LibraryIndexRail));
    final aY = t.getRect(find.text('A')).center.dy;

    final g = await t.startGesture(Offset(r.center.dx, aY - 3));
    await g.moveTo(Offset(r.center.dx, aY));
    await t.pump();
    await g.moveTo(Offset(r.center.dx, aY + 3));
    await t.pump();
    await g.up();
    await t.pumpAndSettle();

    expect(fired, ['A'], reason: 'one letter should fire once per crossing');
  });
}
