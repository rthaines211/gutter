import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/floating_tab_bar.dart';

Widget _host(int count) => MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          FloatingTabBar(currentIndex: 0, onTap: (_) {}, reviewCount: count),
        ]),
      ),
    );

void main() {
  testWidgets('review badge only when count > 0', (t) async {
    await t.pumpWidget(_host(2));
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await t.pumpWidget(_host(0));
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('Creators tab sits between Library and Review', (t) async {
    await t.pumpWidget(_host(0));
    expect(find.text('Creators'), findsOneWidget);
    final libraryX = t.getCenter(find.text('Library')).dx;
    final creatorsX = t.getCenter(find.text('Creators')).dx;
    final reviewX = t.getCenter(find.text('Review')).dx;
    expect(creatorsX, greaterThan(libraryX));
    expect(creatorsX, lessThan(reviewX));
  });
}
