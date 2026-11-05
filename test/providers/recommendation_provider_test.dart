import 'dart:async';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/models/stats_summary.dart';
import 'package:comic_reader_app/providers/library_provider.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/recommendation_provider.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:comic_reader_app/providers/stats_provider.dart';
import 'package:comic_reader_app/services/foundation_models_channel.dart';
import 'package:comic_reader_app/services/recommendation_service.dart';

class _FakeChannel implements FoundationModelsChannel {
  final List<Map<String, dynamic>> responses;
  int callCount = 0;
  bool available;

  _FakeChannel(this.responses, {this.available = true});

  @override
  Duration get timeout => const Duration(seconds: 10);
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<void> prewarm() async {}
  @override
  Future<Map<String, dynamic>> recommend(Map<String, dynamic> ctx) async {
    final r = responses[callCount.clamp(0, responses.length - 1)];
    callCount++;
    return r;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('recommendationProvider', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('exposes service result through AsyncValue', () async {
      final prefs = await SharedPreferences.getInstance();
      final channel = _FakeChannel([
        {
          'series_id': null,
          'title': 'Saga',
          'creator': 'BKV',
          'reasoning': 'why',
        }
      ]);
      final container = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        foundationModelsChannelProvider.overrideWithValue(channel),
        recommendationSignalsLoaderProvider
            .overrideWithValue(() async => SignalSnapshot.empty()),
        recommendationLibraryLookupProvider
            .overrideWithValue((id) => null),
      ]);
      addTearDown(container.dispose);
      final rec = await container.read(recommendationProvider.future);
      expect(rec?.title, 'Saga');
      expect(channel.callCount, 1);
    });

    test('returns null when channel reports unavailable', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        foundationModelsChannelProvider
            .overrideWithValue(_FakeChannel(const [], available: false)),
        recommendationSignalsLoaderProvider
            .overrideWithValue(() async => SignalSnapshot.empty()),
        recommendationLibraryLookupProvider
            .overrideWithValue((id) => null),
      ]);
      addTearDown(container.dispose);
      final rec = await container.read(recommendationProvider.future);
      expect(rec, isNull);
    });

    test('reroll fetches a new pick and updates state', () async {
      final prefs = await SharedPreferences.getInstance();
      final channel = _FakeChannel([
        {
          'series_id': null,
          'title': 'Saga',
          'creator': 'BKV',
          'reasoning': 'first',
        },
        {
          'series_id': null,
          'title': 'East of West',
          'creator': 'Hickman',
          'reasoning': 'second',
        },
      ]);
      final container = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        foundationModelsChannelProvider.overrideWithValue(channel),
        recommendationSignalsLoaderProvider
            .overrideWithValue(() async => SignalSnapshot.empty()),
        recommendationLibraryLookupProvider
            .overrideWithValue((id) => null),
      ]);
      addTearDown(container.dispose);

      final first = await container.read(recommendationProvider.future);
      expect(first?.title, 'Saga');

      await container.read(recommendationProvider.notifier).reroll();
      final second = container.read(recommendationProvider).value;
      expect(second?.title, 'East of West');
      expect(channel.callCount, 2);
    });
  });

  group('getDailyPick cache write behaviour', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('does NOT write daily pick cache when signals are a timeout fallback',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final channel = _FakeChannel([
        {
          'series_id': null,
          'title': 'Generic Pick',
          'creator': null,
          'reasoning': 'zero signal',
        }
      ]);
      final service = RecommendationService(
        cache: RecommendationCache(prefs),
        channel: channel,
        signalsLoader: () async => SignalSnapshot.timeoutFallback(),
        libraryLookup: (_) => null,
        now: () => DateTime(2026, 6, 10),
      );

      final rec = await service.getDailyPick();
      expect(rec?.title, 'Generic Pick');

      // Cache must NOT have been written — a subsequent cold-start (new
      // RecommendationCache over the same prefs) should still return null.
      final freshCache = RecommendationCache(prefs);
      expect(freshCache.readCachedPick(today: DateTime(2026, 6, 10)), isNull);
    });

    test('DOES write daily pick cache when signals are normal (non-timeout)',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final channel = _FakeChannel([
        {
          'series_id': null,
          'title': 'Real Pick',
          'creator': 'Author',
          'reasoning': 'has signals',
        }
      ]);
      final service = RecommendationService(
        cache: RecommendationCache(prefs),
        channel: channel,
        signalsLoader: () async => SignalSnapshot.empty(),
        libraryLookup: (_) => null,
        now: () => DateTime(2026, 6, 10),
      );

      final rec = await service.getDailyPick();
      expect(rec?.title, 'Real Pick');

      final freshCache = RecommendationCache(prefs);
      final cached = freshCache.readCachedPick(today: DateTime(2026, 6, 10));
      expect(cached?.title, 'Real Pick');
    });
  });

  group('recommendationSignalsLoaderProvider', () {
    test('falls back to empty library when libraryProvider never emits',
        () {
      // First-launch scenario: empty mirror means libraryProvider suppresses
      // emissions, so its .future never resolves. The loader must time out
      // and degrade to an empty library instead of hanging forever.
      fakeAsync((async) {
        // Empty in-memory mirror: watchReadingList emits [] promptly, so the
        // loader's reading signal degrades to empty just like first launch.
        final mirrorDb = MirrorDatabase(NativeDatabase.memory());
        addTearDown(() => mirrorDb.close());
        final container = ProviderContainer(overrides: [
          libraryProvider.overrideWith(
              (ref) => StreamController<List<Series>>().stream),
          mirrorDbProvider.overrideWithValue(mirrorDb),
          statsSummaryProvider.overrideWith((ref) async =>
              StatsSummary.fromJson(const {
                'all_time': <String, dynamic>{},
                'this_week': <String, dynamic>{},
                'this_month': <String, dynamic>{},
              })),
        ]);
        addTearDown(container.dispose);

        // Keep the autoDispose stream alive (in the app, LibraryScreen inside
        // the IndexedStack watches it permanently).
        container.listen(libraryProvider, (_, _) {});

        final loader = container.read(recommendationSignalsLoaderProvider);
        SignalSnapshot? snapshot;
        Object? error;
        loader().then((s) {
          snapshot = s;
        }, onError: (Object e) {
          error = e;
        });

        async.elapse(const Duration(seconds: 16));

        expect(error, isNull);
        expect(snapshot, isNotNull,
            reason: 'loader should resolve via the 15s timeout fallback');
        expect(snapshot!.completedSeries, isEmpty);
        expect(snapshot!.unreadLibrary, isEmpty);
        expect(snapshot!.inProgress, isEmpty);
      });
    });
  });
}
