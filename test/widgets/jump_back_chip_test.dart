import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/jump_back_chip.dart';

void main() {
  Future<({List<String> calls})> pump(WidgetTester tester,
      {required bool forward}) async {
    final calls = <String>[];
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: JumpBackChip(
              page: forward ? 20 : 4,
              forward: forward,
              onTap: () => calls.add('tap'),
              onDismiss: () => calls.add('dismiss'),
            ),
          ),
        ),
      ),
    ));
    return (calls: calls);
  }

  testWidgets('back chip reads "Back to page N" with an undo icon',
      (tester) async {
    final r = await pump(tester, forward: false);
    expect(find.text('Back to page 4'), findsOneWidget);
    expect(find.byIcon(Icons.undo), findsOneWidget);
    await tester.tap(find.text('Back to page 4'));
    expect(r.calls, ['tap']);
  });

  testWidgets('forward chip reads "Forward to page M" with a redo icon',
      (tester) async {
    await pump(tester, forward: true);
    expect(find.text('Forward to page 20'), findsOneWidget);
    expect(find.byIcon(Icons.redo), findsOneWidget);
  });

  testWidgets('× dismisses and is at least 44pt', (tester) async {
    final r = await pump(tester, forward: false);
    final close = find.byKey(const Key('jumpchip.dismiss'));
    final size = tester.getSize(close);
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
    await tester.tap(close);
    expect(r.calls, ['dismiss']);
  });
}
