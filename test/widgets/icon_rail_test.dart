import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/flavor.dart';
import 'package:comic_reader_app/providers/connectivity_provider.dart';
import 'package:comic_reader_app/providers/navigation_provider.dart';
import 'package:comic_reader_app/widgets/icon_rail.dart';

const _accent = Color(0xFF0A84FF);

Widget _host({NavDestination initial = NavDestination.read, bool online = true}) =>
    ProviderScope(
      overrides: [
        navigationProvider.overrideWith(() => _FakeNavigationNotifier(initial)),
        connectivityProvider.overrideWith(() => _FixedConnectivity(online)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: IconRail(accent: _accent)),
      ),
    );

class _FakeNavigationNotifier extends NavigationNotifier {
  final NavDestination initial;
  _FakeNavigationNotifier(this.initial);
  @override
  NavDestination build() => initial;
}

class _FixedConnectivity extends ConnectivityNotifier {
  final bool online;
  _FixedConnectivity(this.online);
  @override
  bool build() => online;
}

void main() {
  testWidgets('offline hides the destinations that need the server',
      (t) async {
    await t.pumpWidget(_host(online: false));
    for (final label in ['Creators', 'Review', 'Stats']) {
      expect(find.text(label), findsNothing, reason: '$label needs the server');
    }
    for (final label in ['Read', 'Library', 'Downloads', 'Queues', 'Arcs']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('renders every nav destination the sidebar and tab bar use',
      (t) async {
    await t.pumpWidget(_host());
    for (final label in [
      'Read',
      'Library',
      'Creators',
      'Downloads',
      'Queues',
      'Arcs',
      'Stats',
      'Settings',
    ]) {
      expect(find.text(label), findsOneWidget,
          reason: '$label should render in the rail');
    }
  });

  testWidgets('Creators sits right after Library', (t) async {
    await t.pumpWidget(_host());
    final libraryY = t.getRect(find.text('Library')).top;
    final creatorsY = t.getRect(find.text('Creators')).top;
    expect(creatorsY, greaterThan(libraryY));
  });

  testWidgets('settings sits last in the rail', (t) async {
    await t.pumpWidget(_host());
    final settingsY = t.getRect(find.text('Settings')).top;
    for (final label in [
      'Read',
      'Library',
      'Creators',
      'Downloads',
      'Queues',
      'Arcs',
      'Stats',
    ]) {
      expect(t.getRect(find.text(label)).top, lessThan(settingsY),
          reason: '$label should sit above Settings');
    }
  });

  testWidgets('the active destination is visually distinguished from inactive ones',
      (t) async {
    await t.pumpWidget(_host(initial: NavDestination.library));
    final activeText = t.widget<Text>(find.text('Library'));
    final inactiveText = t.widget<Text>(find.text('Read'));
    expect(activeText.style!.color, _accent);
    expect(inactiveText.style!.color, isNot(_accent));
  });

  testWidgets('tapping a tile calls the navigation notifier', (t) async {
    late final BuildContext context;
    await t.pumpWidget(ProviderScope(
      overrides: [
        navigationProvider.overrideWith(
            () => _FakeNavigationNotifier(NavDestination.read)),
        connectivityProvider.overrideWith(() => _FixedConnectivity(true)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(builder: (c) {
            context = c;
            return const IconRail(accent: _accent);
          }),
        ),
      ),
    ));

    await t.tap(find.text('Library'));
    await t.pump();

    final container = ProviderScope.containerOf(context);
    expect(container.read(navigationProvider), NavDestination.library);
  });

  testWidgets('tapping settings navigates to the settings destination',
      (t) async {
    late final BuildContext context;
    await t.pumpWidget(ProviderScope(
      overrides: [
        navigationProvider.overrideWith(
            () => _FakeNavigationNotifier(NavDestination.read)),
        connectivityProvider.overrideWith(() => _FixedConnectivity(true)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(builder: (c) {
            context = c;
            return const IconRail(accent: _accent);
          }),
        ),
      ),
    ));

    await t.tap(find.text('Settings'));
    await t.pump();

    final container = ProviderScope.containerOf(context);
    expect(container.read(navigationProvider), NavDestination.settings);
  });

  testWidgets('rail is 76pt wide', (t) async {
    await t.pumpWidget(_host());
    expect(t.getSize(find.byType(IconRail)).width, 76);
  });

  testWidgets('store: no Creators, Review or Arcs in the rail', (t) async {
    isStore = true;
    addTearDown(() => isStore = false);
    await t.pumpWidget(_host());
    expect(find.text('Creators'), findsNothing);
    expect(find.text('Review'), findsNothing);
    // Arcs come from Mylar via the personal backend: empty for strangers.
    expect(find.text('Arcs'), findsNothing);
    expect(find.text('Library'), findsOneWidget);
  });
}
