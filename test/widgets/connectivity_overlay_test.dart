import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/providers/connectivity_provider.dart';
import 'package:comic_reader_app/providers/source_provider.dart';
import 'package:comic_reader_app/widgets/connectivity_overlay.dart';

/// No prefs in these tests: the on-device count reads the active source id.
class _Active extends ActiveSourceNotifier {
  @override
  String build() => 'default';
}

/// Test double: bypasses the real notifier's timers/lifecycle setup and lets
/// the test drive the bool directly.
class FakeConnectivity extends ConnectivityNotifier {
  FakeConnectivity(this._initial);
  final bool _initial;

  @override
  bool build() => _initial;

  @override
  Future<void> check() async {}

  void emit(bool online) => state = online;
}

Future<void> _pumpOverlay(WidgetTester tester, FakeConnectivity fake) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        connectivityProvider.overrideWith(() => fake),
        activeSourceIdProvider.overrideWith(_Active.new),
      ],
      child: const MaterialApp(
        home: ConnectivityOverlay(child: SizedBox.expand()),
      ),
    ),
  );
  await tester.pump(); // flush the post-frame _initialized callback
}

void main() {
  group('ConnectivityOverlay', () {
    testWidgets('strip slid offscreen when online', (tester) async {
      await _pumpOverlay(tester, FakeConnectivity(true));
      final slide = tester.widget<AnimatedSlide>(find.byType(AnimatedSlide));
      expect(slide.offset, const Offset(0, -1));
    });

    testWidgets('strip slid into view when offline', (tester) async {
      final fake = FakeConnectivity(true);
      await _pumpOverlay(tester, fake);
      fake.emit(false);
      await tester.pump();
      final slide = tester.widget<AnimatedSlide>(find.byType(AnimatedSlide));
      expect(slide.offset, Offset.zero);
      // No downloads in this test, so the strip says so.
      expect(find.text('Offline · nothing downloaded'), findsOneWidget);
    });

    testWidgets('strip steps aside over a pushed page (the reader)', (tester) async {
      atRootRoute.value = true;
      final fake = FakeConnectivity(true);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(ProviderScope(
        overrides: [
        connectivityProvider.overrideWith(() => fake),
        activeSourceIdProvider.overrideWith(_Active.new),
      ],
        child: MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [RootRouteObserver()],
          builder: (_, child) => ConnectivityOverlay(child: child!),
          home: const SizedBox.expand(),
        ),
      ));
      await tester.pump();
      fake.emit(false);
      await tester.pump();
      Offset slide() =>
          tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset;
      expect(slide(), Offset.zero);

      nav.currentState!.push(MaterialPageRoute(builder: (_) => const SizedBox()));
      await tester.pump();
      await tester.pump();
      expect(slide(), const Offset(0, -1));

      nav.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(slide(), Offset.zero);
    });

    testWidgets('shows "Connection lost" toast on going offline', (tester) async {
      final fake = FakeConnectivity(true);
      await _pumpOverlay(tester, fake);
      fake.emit(false);
      await tester.pump();
      expect(find.text('Connection lost'), findsOneWidget);
    });

    testWidgets('shows "Back online" toast on reconnect', (tester) async {
      final fake = FakeConnectivity(false);
      await _pumpOverlay(tester, fake);
      fake.emit(true);
      await tester.pump();
      expect(find.text('Back online'), findsOneWidget);
    });

    testWidgets('no toast on initial render (first-frame suppression)',
        (tester) async {
      await _pumpOverlay(tester, FakeConnectivity(true));
      expect(find.text('Connection lost'), findsNothing);
      expect(find.text('Back online'), findsNothing);
    });

    testWidgets('toast auto-dismisses after 3s', (tester) async {
      final fake = FakeConnectivity(true);
      await _pumpOverlay(tester, fake);
      fake.emit(false);
      await tester.pump();
      expect(find.text('Connection lost'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(); // settle the setState
      expect(find.text('Connection lost'), findsNothing);
    });
  });
}
