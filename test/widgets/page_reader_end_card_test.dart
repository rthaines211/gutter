import 'package:flutter/material.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/page_reader.dart';

void main() {
  group('PageReader end-card support', () {
    testWidgets('itemCount is pageCount when endCardBuilder is null', (tester) async {
      final controller = PageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        noImgAuth(MaterialApp(
          home: Scaffold(
            body: PageReader(
              controller: controller,
              pageCount: 3,
              pageUrlBuilder: (i) => 'about:blank',
              rtl: false,
              onPageChanged: (_) {},
            ),
          ),
        )),
      );

      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.childrenDelegate.estimatedChildCount, 3);
    });

    testWidgets('itemCount becomes pageCount + 1 when endCardBuilder is provided', (tester) async {
      final controller = PageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        noImgAuth(MaterialApp(
          home: Scaffold(
            body: PageReader(
              controller: controller,
              pageCount: 3,
              pageUrlBuilder: (i) => 'about:blank',
              rtl: false,
              onPageChanged: (_) {},
              endCardBuilder: (_) => const SizedBox(
                key: Key('test.endcard'),
                width: 10,
                height: 10,
              ),
            ),
          ),
        )),
      );

      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.childrenDelegate.estimatedChildCount, 4);
    });

    testWidgets('renders endCardBuilder result at the trailing index', (tester) async {
      final controller = PageController(initialPage: 1);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        noImgAuth(MaterialApp(
          home: Scaffold(
            body: PageReader(
              controller: controller,
              pageCount: 1,
              pageUrlBuilder: (i) => 'about:blank',
              rtl: false,
              onPageChanged: (_) {},
              endCardBuilder: (_) => const Text(
                'END',
                key: Key('test.endcard'),
              ),
            ),
          ),
        )),
      );

      await tester.pumpAndSettle();
      expect(find.byKey(const Key('test.endcard')), findsOneWidget);
    });
  });
}


/// Cover images ask for auth headers; these tests have no source.
Widget noImgAuth(Widget child) => ProviderScope(
      overrides: [imageHeadersProvider.overrideWithValue(const {})],
      child: child,
    );
