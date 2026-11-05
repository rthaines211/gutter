import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/floating_tab_bar.dart';
import 'package:comic_reader_app/widgets/offline_dot.dart';

Future<Widget> _wrap(Widget child) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('OfflineDot renders a dot', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OfflineDot())),
    );
    expect(find.byType(OfflineDot), findsOneWidget);
  });

  testWidgets('FloatingTabBar shows offline dot only when offline',
      (tester) async {
    Future<Widget> bar(bool offline) async => _wrap(Stack(
          children: [
            FloatingTabBar(
              currentIndex: 0,
              onTap: (_) {},
              offline: offline,
            ),
          ],
        ));

    await tester.pumpWidget(await bar(false));
    await tester.pump();
    expect(find.byType(OfflineDot), findsNothing);

    await tester.pumpWidget(await bar(true));
    await tester.pump();
    expect(find.byType(OfflineDot), findsOneWidget);
  });
}
