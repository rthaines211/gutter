import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/models/recommendation.dart';
import 'package:comic_reader_app/services/recommendation_service.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/services/foundation_models_channel.dart';

class _FakeChannel implements FoundationModelsChannel {
  Map<String, dynamic>? lastContext;
  Map<String, dynamic> nextResponse;
  int callCount = 0;

  _FakeChannel(this.nextResponse);

  @override
  Duration get timeout => const Duration(seconds: 10);

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> prewarm() async {}

  @override
  Future<Map<String, dynamic>> recommend(
      Map<String, dynamic> context) async {
    callCount++;
    lastContext = context;
    return nextResponse;
  }
}

class _UnavailableChannel implements FoundationModelsChannel {
  @override
  Duration get timeout => const Duration(seconds: 10);
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<void> prewarm() async {}
  @override
  Future<Map<String, dynamic>> recommend(Map<String, dynamic> ctx) async =>
      throw UnimplementedError();
}

Series _s(String id, String name, {List<String> genres = const []}) =>
    Series(
      id: id, name: name, folderPath: '', issueCount: 5, readCount: 0,
      coverUrl: '', genres: genres, createdAt: DateTime.now(), updatedAt: DateTime.now(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecommendationCache', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns null when no cached pick exists', () async {
      final cache = RecommendationCache(
          await SharedPreferences.getInstance());
      expect(cache.readCachedPick(today: DateTime(2026, 6, 4)), null);
    });

    test('returns cached pick when date matches', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = RecommendationCache(prefs);
      const rec = Recommendation(
        seriesId: 's1', title: 'Saga', creator: 'BKV',
        reasoning: 'why', isInLibrary: true,
      );
      await cache.writeDailyPick(rec, today: DateTime(2026, 6, 4));
      final read = cache.readCachedPick(today: DateTime(2026, 6, 4));
      expect(read?.title, 'Saga');
    });

    test('a pick cached for one source is not read by another', () async {
      final prefs = await SharedPreferences.getInstance();
      const rec = Recommendation(
        seriesId: 'fantastic-four', title: 'FF', creator: 'Hickman',
        reasoning: 'why', isInLibrary: true,
      );
      await RecommendationCache(prefs, sourceId: 'gutter')
          .writeDailyPick(rec, today: DateTime(2026, 6, 4));
      expect(
          RecommendationCache(prefs, sourceId: 'kavita')
              .readCachedPick(today: DateTime(2026, 6, 4)),
          isNull);
      expect(
          RecommendationCache(prefs, sourceId: 'gutter')
              .readCachedPick(today: DateTime(2026, 6, 4))
              ?.seriesId,
          'fantastic-four');
    });

    test('returns null when date does not match', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = RecommendationCache(prefs);
      const rec = Recommendation(
        seriesId: 's1', title: 'Saga', creator: 'BKV',
        reasoning: 'why', isInLibrary: true,
      );
      await cache.writeDailyPick(rec, today: DateTime(2026, 6, 3));
      expect(cache.readCachedPick(today: DateTime(2026, 6, 4)), null);
    });

    test('returns null when cached JSON is malformed', () async {
      SharedPreferences.setMockInitialValues({
        'ai_rec_daily_date': '2026-06-04',
        'ai_rec_daily_pick_json': 'not json',
      });
      final cache = RecommendationCache(
          await SharedPreferences.getInstance());
      expect(cache.readCachedPick(today: DateTime(2026, 6, 4)), null);
    });

    test('session exclusions and titles accumulate and clear together', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = RecommendationCache(prefs);
      cache.addSessionExclusion('s1');
      cache.addSessionExclusion('s2');
      cache.addSessionTitle('Saga, Vol 4');
      expect(cache.sessionExclusions(), {'s1', 's2'});
      expect(cache.sessionTitles(), {'Saga, Vol 4'});
      cache.clearSessionExclusions();
      expect(cache.sessionExclusions(), isEmpty);
      expect(cache.sessionTitles(), isEmpty);
    });
  });

  group('RecommendationService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns cached pick when present and not forced', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = RecommendationCache(prefs);
      const cached = Recommendation(
        seriesId: 's1', title: 'Saga', creator: 'BKV',
        reasoning: 'why', isInLibrary: true,
      );
      await cache.writeDailyPick(cached, today: DateTime(2026, 6, 4));
      final channel = _FakeChannel(const {});
      final svc = RecommendationService(
        cache: cache,
        channel: channel,
        signalsLoader: () async => SignalSnapshot.empty(),
        libraryLookup: (id) => null,
        now: () => DateTime(2026, 6, 4),
      );
      final rec = await svc.getDailyPick();
      expect(rec?.title, 'Saga');
      expect(channel.callCount, 0);
    });

    test('forces fresh call when force=true and marks isInLibrary', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = RecommendationCache(prefs);
      final library = {'s9': _s('s9', 'Paper Girls')};
      final channel = _FakeChannel({
        'series_id': 's9',
        'title': 'Paper Girls',
        'creator': 'BKV',
        'reasoning': 'because BKV',
      });
      final svc = RecommendationService(
        cache: cache,
        channel: channel,
        signalsLoader: () async => SignalSnapshot.empty(),
        libraryLookup: (id) => library[id],
        now: () => DateTime(2026, 6, 4),
      );
      final rec = await svc.getDailyPick(force: true);
      expect(rec?.title, 'Paper Girls');
      expect(rec?.isInLibrary, true);
      expect(channel.callCount, 1);
    });

    test('treats unknown series_id as unowned (isInLibrary false)', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = RecommendationCache(prefs);
      final channel = _FakeChannel({
        'series_id': 'phantom',
        'title': 'Trees',
        'creator': 'Ellis',
        'reasoning': 'vibes',
      });
      final svc = RecommendationService(
        cache: cache,
        channel: channel,
        signalsLoader: () async => SignalSnapshot.empty(),
        libraryLookup: (_) => null,
        now: () => DateTime(2026, 6, 4),
      );
      final rec = await svc.getDailyPick(force: true);
      expect(rec?.isInLibrary, false);
      expect(rec?.seriesId, isNull);
    });

    test('reroll adds previous pick id and title to exclusions', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = RecommendationCache(prefs);
      await cache.writeDailyPick(
        const Recommendation(
          seriesId: 's1', title: 'Saga', creator: 'BKV',
          reasoning: 'why', isInLibrary: true,
        ),
        today: DateTime(2026, 6, 4),
      );
      final channel = _FakeChannel({
        'series_id': 's2',
        'title': 'East of West',
        'creator': 'Hickman',
        'reasoning': 'because',
      });
      final svc = RecommendationService(
        cache: cache,
        channel: channel,
        signalsLoader: () async => SignalSnapshot.empty(),
        libraryLookup: (_) => null,
        now: () => DateTime(2026, 6, 4),
      );
      await svc.reroll();
      expect(cache.sessionExclusions().contains('s1'), true);
      expect(cache.sessionTitles().contains('Saga'), true);
      expect(channel.callCount, 1);
    });

    test('returns null when channel reports unavailable', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = RecommendationCache(prefs);
      final svc = RecommendationService(
        cache: cache,
        channel: _UnavailableChannel(),
        signalsLoader: () async => SignalSnapshot.empty(),
        libraryLookup: (_) => null,
        now: () => DateTime(2026, 6, 4),
      );
      final rec = await svc.getDailyPick(force: true);
      expect(rec, isNull);
    });
  });
}
