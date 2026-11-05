import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/widgets/page_jump_pill.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

Widget _wrapWithTheme(Widget child, ThemeData theme) {
  return MaterialApp(theme: theme, home: Scaffold(body: child));
}

void main() {
  testWidgets('shows "7 / 24" for currentPage=6, totalPages=24',
      (tester) async {
    await tester.pumpWidget(_wrap(PageJumpPill(
      currentPage: 6,
      totalPages: 24,
      onJump: (_) {},
    )));
    await tester.pump();

    expect(find.text('7 / 24'), findsOneWidget);
  });

  testWidgets('tap, enter 18, Go calls onJump(17)', (tester) async {
    int? jumped;
    await tester.pumpWidget(_wrap(PageJumpPill(
      currentPage: 6,
      totalPages: 24,
      onJump: (p) => jumped = p,
    )));

    await tester.tap(find.byKey(const Key('pageJumpPill.pill')));
    await tester.pump();
    await tester.pump(); // autofocus lands: Go must not count as a tap outside

    await tester.enterText(find.byKey(const Key('pageJumpPill.field')), '18');
    // A frame between down and up, as on a device.
    final g = await tester
        .startGesture(tester.getCenter(find.byKey(const Key('pageJumpPill.go'))));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(jumped, 17);
    // Reverts to the pill after Go.
    expect(find.byKey(const Key('pageJumpPill.field')), findsNothing);
  });

  testWidgets('"0" clamps to onJump(0)', (tester) async {
    int? jumped;
    await tester.pumpWidget(_wrap(PageJumpPill(
      currentPage: 6,
      totalPages: 24,
      onJump: (p) => jumped = p,
    )));

    await tester.tap(find.byKey(const Key('pageJumpPill.pill')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('pageJumpPill.field')), '0');
    await tester.tap(find.byKey(const Key('pageJumpPill.go')));
    await tester.pump();

    expect(jumped, 0);
  });

  testWidgets('"999" clamps to onJump(totalPages - 1)', (tester) async {
    int? jumped;
    await tester.pumpWidget(_wrap(PageJumpPill(
      currentPage: 6,
      totalPages: 24,
      onJump: (p) => jumped = p,
    )));

    await tester.tap(find.byKey(const Key('pageJumpPill.pill')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('pageJumpPill.field')), '999');
    await tester.tap(find.byKey(const Key('pageJumpPill.go')));
    await tester.pump();

    expect(jumped, 23);
  });

  testWidgets('empty input + Go calls nothing', (tester) async {
    int? jumped;
    await tester.pumpWidget(_wrap(PageJumpPill(
      currentPage: 6,
      totalPages: 24,
      onJump: (p) => jumped = p,
    )));

    await tester.tap(find.byKey(const Key('pageJumpPill.pill')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('pageJumpPill.go')));
    await tester.pump();

    expect(jumped, isNull);
  });

  testWidgets('field rejects letters (digits-only formatter)', (tester) async {
    await tester.pumpWidget(_wrap(PageJumpPill(
      currentPage: 6,
      totalPages: 24,
      onJump: (_) {},
    )));

    await tester.tap(find.byKey(const Key('pageJumpPill.pill')));
    await tester.pump();

    final field =
        tester.widget<TextField>(find.byKey(const Key('pageJumpPill.field')));
    final formatters = field.inputFormatters ?? const [];
    expect(
      formatters.any((f) => f is FilteringTextInputFormatter),
      isTrue,
    );

    await tester.enterText(find.byKey(const Key('pageJumpPill.field')), 'ab12cd');
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('losing focus reverts to the pill without jumping',
      (tester) async {
    int? jumped;
    await tester.pumpWidget(_wrap(Column(children: [
      PageJumpPill(
        currentPage: 6,
        totalPages: 24,
        onJump: (p) => jumped = p,
      ),
      const TextField(key: Key('other.field')),
    ])));

    await tester.tap(find.byKey(const Key('pageJumpPill.pill')));
    await tester.pump();
    expect(find.byKey(const Key('pageJumpPill.field')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('pageJumpPill.field')), '18');
    // Move focus elsewhere without submitting.
    await tester.tap(find.byKey(const Key('other.field')));
    await tester.pump();

    expect(find.byKey(const Key('pageJumpPill.field')), findsNothing);
    expect(jumped, isNull);
  });

  testWidgets('pill and Go button are at least 44pt tall', (tester) async {
    await tester.pumpWidget(_wrap(const Center(
      child: PageJumpPill(currentPage: 6, totalPages: 24, onJump: _noop),
    )));
    expect(tester.getSize(find.byKey(const Key('pageJumpPill.pill'))).height,
        greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const Key('pageJumpPill.pill')));
    await tester.pump();
    expect(tester.getSize(find.byKey(const Key('pageJumpPill.go'))).height,
        greaterThanOrEqualTo(44));
  });

  testWidgets('tapping outside the field reverts to the pill', (tester) async {
    await tester.pumpWidget(_wrap(const Column(children: [
      PageJumpPill(currentPage: 6, totalPages: 24, onJump: _noop),
      SizedBox(
        key: Key('outside'),
        width: 300,
        height: 300,
        child: ColoredBox(color: Colors.transparent),
      ),
    ])));
    await tester.tap(find.byKey(const Key('pageJumpPill.pill')));
    await tester.pump();
    await tester.pump(); // autofocus lands
    expect(find.byKey(const Key('pageJumpPill.field')), findsOneWidget);

    await tester.tap(find.byKey(const Key('outside')));
    await tester.pump();
    expect(find.byKey(const Key('pageJumpPill.field')), findsNothing);
  });

  testWidgets('pill text uses the Sepia Paper scheme color, not white',
      (tester) async {
    await tester.pumpWidget(_wrapWithTheme(
      const PageJumpPill(currentPage: 6, totalPages: 24, onJump: _noop),
      AppTheme.themeData(Scheme.sepiaPaper),
    ));
    await tester.pump();

    final text = tester.widget<Text>(find.text('7 / 24'));
    expect(text.style?.color, Scheme.sepiaPaper.tx);
    expect(text.style?.color, isNot(Colors.white));
  });
}

void _noop(int _) {}
