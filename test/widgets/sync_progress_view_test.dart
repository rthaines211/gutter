import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/models/server_source.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/source_provider.dart';
import 'package:comic_reader_app/services/mirror/sync_engine.dart';
import 'package:comic_reader_app/services/mirror/sync_progress.dart';
import 'package:comic_reader_app/widgets/sync_progress_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Fixed extends SyncProgressNotifier {
  _Fixed(this.initial);
  final SyncProgress initial;
  @override
  SyncProgress build() => initial;
}

class _FakeSync implements SyncEngine {
  final forces = <bool>[];
  @override
  Future<void> sync({bool force = false}) async => forces.add(force);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _source = ServerSource(
    id: 's',
    name: 'Home',
    type: SourceType.custom,
    baseUrl: 'http://t',
    authType: AuthType.none);

SyncProgress _running({
  SyncStage stage = SyncStage.fetching,
  bool initial = true,
  int done = 0,
  int? total,
  int covers = 0,
}) =>
    SyncProgress.start().next(
        stage: stage,
        initial: initial,
        seriesDone: done,
        seriesTotal: total,
        coversDone: covers);

Future<ProviderContainer> _pump(WidgetTester t, SyncProgress p, Widget child,
    {Scheme scheme = Scheme.oledBlack,
    _FakeSync? sync,
    bool reduceMotion = false}) async {
  SharedPreferences.setMockInitialValues({});
  await t.pumpWidget(ProviderScope(
    overrides: [
      syncProgressProvider.overrideWith(() => _Fixed(p)),
      activeSourceProvider.overrideWithValue(_source),
      syncEngineProvider.overrideWithValue(sync ?? _FakeSync()),
      coverSyncerProvider.overrideWithValue(null),
    ],
    child: MaterialApp(
      theme: AppTheme.themeData(scheme),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: child),
      ),
    ),
  ));
  await t.pump();
  return ProviderScope.containerOf(t.element(find.byType(Scaffold)));
}

double _opacity(WidgetTester t, Finder f) => t
    .widget<AnimatedOpacity>(
        find.ancestor(of: f, matching: find.byType(AnimatedOpacity)))
    .opacity;

void main() {
  for (final scheme in [Scheme.oledBlack, Scheme.sepiaPaper]) {
    final name = scheme.dark ? 'dark' : 'light';

    testWidgets('first sync card: before total, then counts ($name)',
        (t) async {
      final c = await _pump(
          t, _running(stage: SyncStage.pushing), const FirstSyncCard(),
          scheme: scheme);
      expect(find.text('Syncing with Home'), findsOneWidget);
      expect(find.text('Connecting…'), findsOneWidget);
      expect(find.text('Your comics appear as they arrive.'), findsOneWidget);
      expect(
          t.widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator)).value,
          isNull,
          reason: 'indeterminate before the total is known');

      c.read(syncProgressProvider.notifier)
          .apply((p) => p.next(stage: SyncStage.fetching));
      await t.pump();
      expect(find.text('Reading library…'), findsOneWidget);

      c.read(syncProgressProvider.notifier).apply(
          (p) => p.next(seriesDone: 12, seriesTotal: 40, coversDone: 31));
      await t.pump();
      expect(find.text('12 of 40 series · 31 covers'), findsOneWidget);
      expect(
          t.widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator)).value,
          closeTo(0.3, 1e-9));
      expect(find.bySemanticsLabel(RegExp('12 of 40 series')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('header pill and strip while the first sync fills in ($name)',
        (t) async {
      await _pump(
          t,
          _running(done: 12, total: 40),
          const Column(children: [SyncIndicator(), SyncIndicator.strip()]),
          scheme: scheme);
      expect(find.text('Syncing · 12/40'), findsOneWidget);
      expect(_opacity(t, find.text('Syncing · 12/40')), 1);
      expect(
          t.widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator)).value,
          closeTo(0.3, 1e-9));
      expect(find.bySemanticsLabel('Syncing, 12 of 40 series'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('failed: friendly text and Retry forces a sync ($name)',
        (t) async {
      final sync = _FakeSync();
      await _pump(
          t,
          _running().next(
              stage: SyncStage.failed, error: 'SocketException: boom'),
          const FirstSyncCard(),
          scheme: scheme,
          sync: sync);
      expect(find.text("Couldn't reach Home"), findsOneWidget);
      expect(find.text("Check that the server is running and you're online."),
          findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
      await t.tap(find.text('Retry'));
      await t.pump();
      expect(sync.forces, [true]);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('no progress for 10s switches to "Still working"', (t) async {
    final c = await _pump(
        t, _running(done: 12, total: 40), const FirstSyncCard());
    expect(find.text('Syncing with Home'), findsOneWidget);

    await t.pump(const Duration(seconds: 9));
    expect(find.text('Still working'), findsNothing);
    // Progress resets the clock.
    c.read(syncProgressProvider.notifier)
        .apply((p) => p.next(seriesDone: 13));
    await t.pump(const Duration(seconds: 9));
    expect(find.text('Still working'), findsNothing);

    await t.pump(const Duration(seconds: 2));
    expect(find.text('Still working'), findsOneWidget);
    expect(find.text('13 of 40 series. Big libraries take a minute.'),
        findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('background refresh: "Updating" after 1s, fades when done',
      (t) async {
    final c = await _pump(t, _running(initial: false, done: 3, total: 9),
        const Column(children: [SyncIndicator(), SyncIndicator.strip()]));
    expect(_opacity(t, find.text('Updating')), 0,
        reason: 'a quick periodic sync never shows');
    await t.pump(const Duration(seconds: 1));
    expect(_opacity(t, find.text('Updating')), 1);
    expect(find.textContaining('3/9'), findsNothing, reason: 'no count');
    expect(
        t.widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator)).value,
        isNull);

    c.read(syncProgressProvider.notifier)
        .apply((p) => p.next(stage: SyncStage.done));
    await t.pump();
    expect(_opacity(t, find.text('Updating')), 0);
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Reduce Motion: indeterminate bar is static', (t) async {
    await _pump(t, _running(), const FirstSyncCard(), reduceMotion: true);
    expect(
        t.widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator)).value,
        1);
    await t.pumpWidget(const SizedBox());
  });
}
