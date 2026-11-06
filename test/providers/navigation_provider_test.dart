import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/flavor.dart';
import 'package:comic_reader_app/providers/navigation_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/screens/creators_screen.dart';
import 'package:comic_reader_app/screens/review_screen.dart';
import 'package:comic_reader_app/widgets/app_shell.dart';

void main() {
  test('on a source that is not a Gutter server, Creators/Review/Arcs land on Read', () {
    final c = ProviderContainer(overrides: [
      gutterFeaturesProvider.overrideWithValue(false),
    ]);
    addTearDown(c.dispose);
    final n = c.read(navigationProvider.notifier);
    for (final d in storeHiddenDestinations) {
      n.go(d);
      expect(c.read(navigationProvider), NavDestination.read, reason: '$d');
    }
    n.go(NavDestination.stats);
    expect(c.read(navigationProvider), NavDestination.stats);
  });

  test('phone tab 3 is review, downloads maps to More (4)', () {
    final c = ProviderContainer(overrides: [
      gutterFeaturesProvider.overrideWithValue(true),
    ]);
    addTearDown(c.dispose);
    final n = c.read(navigationProvider.notifier);
    n.setTabIndex(3);
    expect(c.read(navigationProvider), NavDestination.review);
    expect(n.tabIndex, 3);
    n.go(NavDestination.downloads);
    expect(n.tabIndex, 4);
    n.setTabIndex(4); // already under More: stay put
    expect(c.read(navigationProvider), NavDestination.downloads);
    n.setTabIndex(0);
    n.setTabIndex(4);
    expect(c.read(navigationProvider), NavDestination.downloads);
  });

  test('tab 2 is creators', () {
    final c = ProviderContainer(overrides: [
      gutterFeaturesProvider.overrideWithValue(true),
    ]);
    addTearDown(c.dispose);
    final n = c.read(navigationProvider.notifier);
    n.setTabIndex(2);
    expect(c.read(navigationProvider), NavDestination.creators);
    expect(n.tabIndex, 2);
  });

  test('creators is appended last and has a tablet screen', () {
    expect(NavDestination.values.last, NavDestination.creators);
    expect(AppShell.tabletScreens.length, NavDestination.values.length);
    expect(AppShell.tabletScreens[NavDestination.review.index],
        isA<ReviewScreen>());
    expect(AppShell.tabletScreens[NavDestination.creators.index],
        isA<CreatorsScreen>());
  });

  test('store: going to a hidden destination lands on Read', () {
    isStore = true;
    addTearDown(() => isStore = false);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(navigationProvider.notifier);
    n.go(NavDestination.library);
    n.go(NavDestination.review);
    expect(c.read(navigationProvider), NavDestination.read);
    n.go(NavDestination.library);
    n.setTabIndex(2);
    expect(c.read(navigationProvider), NavDestination.read);
    n.go(NavDestination.arcs);
    expect(c.read(navigationProvider), NavDestination.read);
  });
}
