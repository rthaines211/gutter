import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:comic_reader_app/models/server_source.dart';
import 'package:comic_reader_app/providers/cache_providers.dart';
import 'package:comic_reader_app/providers/connectivity_provider.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/source_provider.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/connectivity_state_machine.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:comic_reader_app/services/sync_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SyncQueue queue;
  late List<bool> capturedOutcomes;

  setUp(() async {
    await AppLogger.init(logDirFactory: () async => null);
    tempDir = Directory.systemTemp.createTempSync('connectivity_test_');
    queue = SyncQueue(queuePath: '${tempDir.path}/sync_queue.json');
    capturedOutcomes = [];
  });

  tearDown(() {
    AppLogger.resetForTest();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ProviderContainer makeContainer({
    required Future<http.Response> Function(http.Request) httpHandler,
  }) {
    final client = ApiClient(
      baseUrl: 'http://localhost:8080',
      deviceId: 'test',
      httpClient: MockClient(httpHandler),
      onRequestOutcome: capturedOutcomes.add,
    );
    // _drain() now goes through SyncEngine, which needs the local mirror.
    final mirrorDb = MirrorDatabase(NativeDatabase.memory());
    addTearDown(mirrorDb.close);
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        syncQueueProvider.overrideWithValue(queue),
        mirrorDbProvider.overrideWithValue(mirrorDb),
        // build() now listens to activeSourceProvider and _drain() checks
        // isCustomSourceProvider; bypass the prefs/secure-storage chain.
        activeSourceProvider.overrideWithValue(
          ServerSource.createDefault(url: 'http://localhost:8080'),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Runs before container.dispose (addTearDown is LIFO): let the launch
    // microtask (check + drain) and any in-flight drain settle, otherwise
    // their failure logging fires after AppLogger.resetForTest().
    addTearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final drain = container
          .read(connectivityProvider.notifier)
          .drainInFlightForTesting;
      if (drain != null) await drain;
    });
    return container;
  }

  test('initial state is online', () {
    final container = makeContainer(
      httpHandler: (_) async => http.Response('[]', 200),
    );
    expect(container.read(connectivityProvider), isTrue);
    expect(
      container.read(connectivityProvider.notifier).internalStateForTesting,
      ConnectivityState.online,
    );
  });

  test('the pretend-offline switch overrides a working connection', () {
    final container = makeContainer(
      httpHandler: (_) async => http.Response('[]', 200),
    );
    final notifier = container.read(connectivityProvider.notifier);
    container.read(simulateOfflineProvider.notifier).set(true);
    expect(container.read(connectivityProvider), isFalse);
    // A successful request can't flip it back while the switch is on.
    notifier.reportOutcome(true);
    expect(container.read(connectivityProvider), isFalse);
    container.read(simulateOfflineProvider.notifier).set(false);
    expect(container.read(connectivityProvider), isTrue);
  });

  test('single failed report does not flip public bool', () {
    final container = makeContainer(
      httpHandler: (_) async => http.Response('[]', 200),
    );
    final notifier = container.read(connectivityProvider.notifier);
    notifier.reportOutcome(false);
    expect(container.read(connectivityProvider), isTrue);
    expect(notifier.internalStateForTesting, ConnectivityState.unsure);
  });

  test('three failures flip public bool to false', () {
    final container = makeContainer(
      httpHandler: (_) async => http.Response('[]', 200),
    );
    final notifier = container.read(connectivityProvider.notifier);
    notifier.reportOutcome(false);
    notifier.reportOutcome(false);
    notifier.reportOutcome(false);
    expect(container.read(connectivityProvider), isFalse);
  });

  test('returning online from offline triggers queue drain', () async {
    // Pre-populate queue.
    await queue.enqueue({
      'type': 'progress',
      'payload': {
        'comic_id': 'abc',
        'current_page': 5,
        'total_pages': 100,
      },
    });

    final container = makeContainer(
      httpHandler: (_) async => http.Response('{}', 200),
    );
    final notifier = container.read(connectivityProvider.notifier);

    // Force offline.
    notifier.reportOutcome(false);
    notifier.reportOutcome(false);
    notifier.reportOutcome(false);
    expect(container.read(connectivityProvider), isFalse);

    // Recovery.
    notifier.reportOutcome(true);
    // Drain is fire-and-forget; await it deterministically.
    final drain = notifier.drainInFlightForTesting;
    if (drain != null) await drain;

    expect(await queue.pendingCount, 0);
  });

  test('a new address on the same source id starts a sync at once', () async {
    // Onboarding fills in the blank default source and keeps its id. The
    // first sync then waited for the next health poll (up to 30 s) while the
    // first-sync card said "Couldn't reach <server>".
    final synced = <String>[];
    final mirrorDb = MirrorDatabase(NativeDatabase.memory());
    addTearDown(mirrorDb.close);
    final source = _SourceBox();
    final container = ProviderContainer(overrides: [
      // As in the app: the client is rebuilt from the active source.
      apiClientProvider.overrideWith((ref) => ApiClient(
            baseUrl: ref.watch(_sourceBoxProvider).baseUrl,
            deviceId: 'test',
            httpClient: MockClient((r) async {
              if (r.url.path == '/sync') synced.add(r.url.host);
              return http.Response('{}', 200);
            }),
          )),
      syncQueueProvider.overrideWithValue(queue),
      mirrorDbProvider.overrideWithValue(mirrorDb),
      _sourceBoxProvider.overrideWith(() => source),
      activeSourceProvider.overrideWith((ref) => ref.watch(_sourceBoxProvider)),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(connectivityProvider.notifier);
    Future<void> settle() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final drain = notifier.drainInFlightForTesting;
      if (drain != null) await drain;
    }
    addTearDown(settle);

    await settle();
    expect(synced, isNot(contains('other')));

    source.set(ServerSource.createDefault(url: 'http://other:8080'));
    // The UI watches the engine; a bare container needs a read to flush the
    // change to listeners.
    container.read(syncEngineProvider);
    await settle();

    expect(synced, contains('other'));
  });

  test('onAppResumed triggers an immediate check', () async {
    var callCount = 0;
    final container = makeContainer(
      httpHandler: (_) async {
        callCount++;
        return http.Response('[]', 200);
      },
    );
    final notifier = container.read(connectivityProvider.notifier);

    // Let the initial build-time check() run, then reset.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final before = callCount;

    notifier.onAppResumed();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(callCount, greaterThan(before));
  });

  test('onAppResumed drains pending queue if online', () async {
    await queue.enqueue({
      'type': 'progress',
      'payload': {
        'comic_id': 'abc',
        'current_page': 5,
        'total_pages': 100,
      },
    });

    final container = makeContainer(
      httpHandler: (_) async => http.Response('{}', 200),
    );
    final notifier = container.read(connectivityProvider.notifier);
    expect(container.read(connectivityProvider), isTrue);

    notifier.onAppResumed();
    // Drain is fire-and-forget but now starts synchronously (no pendingCount
    // pre-check — resume always syncs), so the in-flight future is set
    // immediately.
    final drain = notifier.drainInFlightForTesting;
    if (drain != null) await drain;

    expect(await queue.pendingCount, 0);
  });

  test('poll-tier gate: reschedules timer only when crossing online boundary', () async {
    final container = makeContainer(
      httpHandler: (_) async => http.Response('[]', 200),
    );
    final notifier = container.read(connectivityProvider.notifier);

    // build() calls _scheduleTimer() once.
    final initialCount = notifier.scheduleCountForTesting;
    expect(initialCount, 1);

    // First failure: online -> unsure crosses the tier; expect reschedule.
    notifier.reportOutcome(false);
    expect(notifier.scheduleCountForTesting, initialCount + 1);

    // Two more failures: unsure -> unsure (no transition.changed) then
    // unsure -> offline (changed but same poll tier). Neither should
    // reschedule the timer.
    notifier.reportOutcome(false);
    notifier.reportOutcome(false);
    expect(notifier.scheduleCountForTesting, initialCount + 1);

    // Recovery crosses tier; expect reschedule.
    notifier.reportOutcome(true);
    expect(notifier.scheduleCountForTesting, initialCount + 2);
  });

  test('concurrent _drain calls dedup via in-flight guard', () async {
    // Pre-populate a queue with one entry.
    await queue.enqueue({
      'type': 'progress',
      'payload': {
        'comic_id': 'abc',
        'current_page': 1,
        'total_pages': 100,
      },
    });

    // Count only PUT requests so health-check GETs don't skew the count.
    var drainCallCount = 0;
    final container = makeContainer(
      httpHandler: (req) async {
        if (req.method == 'PUT') drainCallCount++;
        return http.Response('{}', 200);
      },
    );
    final notifier = container.read(connectivityProvider.notifier);

    // Force offline then back online twice in quick succession.
    // First recovery starts a drain; second recovery should be guarded.
    notifier.reportOutcome(false);
    notifier.reportOutcome(false);
    notifier.reportOutcome(false);
    notifier.reportOutcome(true);  // offline -> online: drain 1 starts
    notifier.reportOutcome(false);
    notifier.reportOutcome(false);
    notifier.reportOutcome(false);
    notifier.reportOutcome(true);  // offline -> online: drain 2 should be guarded

    final drain = notifier.drainInFlightForTesting;
    if (drain != null) await drain;

    // Only one PUT for the single queue entry — not two.
    expect(drainCallCount, 1);
    expect(await queue.pendingCount, 0);
  });

  test('foreground sync timer starts on build', () {
    final container = makeContainer(
      httpHandler: (_) async => http.Response('[]', 200),
    );
    final notifier = container.read(connectivityProvider.notifier);
    expect(notifier.syncTimerActiveForTesting, isTrue);
  });

  test('hide cancels, resume restarts', () async {
    final container = makeContainer(
      httpHandler: (_) async => http.Response('[]', 200),
    );
    final notifier = container.read(connectivityProvider.notifier);

    notifier.onAppHidden();
    expect(notifier.syncTimerActiveForTesting, isFalse);

    notifier.onAppResumed();
    // Settle unawaited futures triggered by onAppResumed() (check() + _drain()).
    final drain = notifier.drainInFlightForTesting;
    if (drain != null) await drain;

    expect(notifier.syncTimerActiveForTesting, isTrue);
  });
}

final _sourceBoxProvider =
    NotifierProvider<_SourceBox, ServerSource>(_SourceBox.new);

class _SourceBox extends Notifier<ServerSource> {
  @override
  ServerSource build() =>
      ServerSource.createDefault(url: 'http://first:8080');

  void set(ServerSource s) => state = s;
}
