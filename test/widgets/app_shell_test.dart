import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/providers/navigation_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/widgets/app_shell.dart';
import 'package:comic_reader_app/widgets/floating_tab_bar.dart';

void main() {
  test('tablet screens line up with NavDestination', () {
    // The iPad shell uses an IndexedStack keyed on NavDestination.index, so a
    // missing or reordered entry silently shows the WRONG screen rather than
    // failing to compile. Adding a destination must add a screen here.
    expect(AppShell.tabletScreens.length, NavDestination.values.length,
        reason: 'one screen per destination, in enum order');
  });

  testWidgets('phone shell rebuilds when the navigation destination changes',
      (tester) async {
    // tabIndex is derived from navigationProvider's state, so the phone shell
    // must WATCH the provider. Reading it off the notifier subscribes to
    // nothing: taps fired, state changed, and the shell never rebuilt — the
    // tab bar and IndexedStack stayed frozen on Read. The iPad path watches,
    // which is why only the phone was affected.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await AppLogger.init(logDirFactory: () async => null);
    // The shell reaches flutter_secure_storage via the source/config chain;
    // there is no plugin implementation under flutter_test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            null));
    tester.view.physicalSize = const Size(760 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pump();

    expect(tester.widget<FloatingTabBar>(find.byType(FloatingTabBar)).currentIndex,
        0, reason: 'starts on Read');

    ProviderScope.containerOf(tester.element(find.byType(AppShell)))
        .read(navigationProvider.notifier)
        .setTabIndex(1);
    await tester.pump();

    expect(tester.widget<FloatingTabBar>(find.byType(FloatingTabBar)).currentIndex,
        1, reason: 'phone shell must follow navigation state');

    // Unmount and drain: the shell's screens schedule connection-check and
    // shimmer timers that flutter_test's pending-timer check would otherwise
    // flag. Same pattern as test/reader/harness.dart's disposeReader.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
  });
}
