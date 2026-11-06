import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/cache_providers.dart';
import 'package:comic_reader_app/providers/connectivity_provider.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/reader_provider.dart';
import 'package:comic_reader_app/providers/remote_provider.dart';
import 'package:comic_reader_app/screens/reader_screen.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:comic_reader_app/services/sync_queue.dart';

import 'fake_comic_server.dart';

class _RealHttpOverrides extends HttpOverrides {}

/// Every WakelockPlus toggle the reader sent, in order (true = enable).
/// Tests clear it themselves.
final wakelockCalls = <bool>[];

/// Pigeon wraps data classes as custom types (>= 128) holding their
/// encoded field list; read them back as that plain list.
class _PigeonCodec extends StandardMessageCodec {
  const _PigeonCodec();
  @override
  Object? readValueOfType(int type, ReadBuffer buffer) =>
      type >= 128 ? readValue(buffer) : super.readValueOfType(type, buffer);
}

class _AlwaysOnline extends ConnectivityNotifier {
  @override
  bool build() => true;
}

/// One-time per-file env setup: allow real HTTP to localhost, back
/// flutter_cache_manager's sqlite db with ffi, point path_provider at a
/// temp dir so the image disk cache has somewhere to live.
Future<Directory> initReaderTestEnv() async {
  HttpOverrides.global = _RealHttpOverrides();
  // Each pumpReader opens a fresh in-memory mirror DB; silence drift's
  // multiple-databases debug warning so test output stays pristine.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  // ponytail: init AppLogger in memory-only mode — required before ReaderNotifier.build() runs
  await AppLogger.init(logDirFactory: () async => null);
  final tmp = await Directory.systemTemp.createTemp('reader_test_');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => tmp.path,
  );
  // ponytail: stub secure storage — source_provider reads/deletes credentials on init/dispose
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async => switch (call.method) {
      'read' => null,
      'readAll' => <String, String>{},
      'write' || 'delete' || 'deleteAll' => null,
      _ => null,
    },
  );
  // ponytail: stub volume controller method + event channel — test env has no audio stack
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.yosemiteyss.flutter_volume_controller/method'),
    (call) async => null,
  );
  // EventChannel mock: reply to 'listen' with an empty stream (no volume events)
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockStreamHandler(
    const EventChannel('com.yosemiteyss.flutter_volume_controller/event'),
    MockStreamHandler.inline(onListen: (args, sink) {}, onCancel: (args) {}),
  );
  // ponytail: WakelockPlus uses BasicMessageChannel with StandardMessageCodec.
  // Return [null] — pigeon treats this as void success.
  const codec = StandardMessageCodec();
  const wakelockToggle =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  for (final ch in [
    wakelockToggle,
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.isEnabled',
  ]) {
    messenger.setMockMessageHandler(ch, (msg) async {
      if (ch == wakelockToggle && msg != null) {
        // [ToggleMessage] arrives as [[enable]].
        final args = const _PigeonCodec().decodeMessage(msg) as List;
        wakelockCalls.add((args.first as List).first as bool);
      }
      return codec.encodeMessage(<Object?>[null]);
    });
  }
  // ponytail: screen_brightness reset is called on reader dispose
  messenger.setMockMethodCallHandler(
    const MethodChannel('github.com/aaassseee/screen_brightness'),
    (call) async => null,
  );
  messenger.setMockStreamHandler(
    const EventChannel('github.com/aaassseee/screen_brightness/change'),
    MockStreamHandler.inline(onListen: (args, sink) {}, onCancel: (args) {}),
  );
  return tmp;
}

// ponytail: DefaultCacheManager is a true singleton; create a per-test
// CacheManager subclass with a unique store key so tests never share state.
int _cacheCounter = 0;

class _TestCacheManager extends CacheManager {
  _TestCacheManager(String key) : super(Config(key));
}

/// Assign a fresh per-test CacheManager and clear the painting image cache.
/// Call in each test file's setUp() before pumpReader().
void resetImageCaches() {
  // ponytail: unique key per test so completed downloads from prior tests
  // never pollute this test's image loads.
  CachedNetworkImageProvider.defaultCacheManager =
      _TestCacheManager('test_cache_${_cacheCounter++}');
  PaintingBinding.instance.imageCache.clear();
}

class ReaderHarness {
  final FakeComicServer server;
  final MirrorDatabase mirrorDb;
  final SyncQueue syncQueue;
  final ReaderKey readerKey;
  ReaderHarness(this.server, this.mirrorDb, this.syncQueue, this.readerKey);

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ReaderScreen)));

  ReaderState stateOf(WidgetTester tester) =>
      containerOf(tester).read(readerProvider(readerKey)).value!;

  ReaderNotifier notifierOf(WidgetTester tester) =>
      containerOf(tester).read(readerProvider(readerKey).notifier);
}

/// Standard per-test server lifecycle: start a FakeComicServer built by
/// [build], reset image caches, and drain+stop the server in tearDown.
/// Call inside a test file's main() after initReaderTestEnv is scheduled.
///
/// [onCreated] receives the new server instance so the caller can assign it
/// to their local `late FakeComicServer server` variable. The same reference
/// is captured in tearDown via [getter], which must read that same variable.
///
/// Example:
/// ```dart
/// late FakeComicServer server;
/// useComicServer(
///   () => FakeComicServer()..comics['c1'] = [...],
///   (s) => server = s,
///   () => server,
/// );
/// ```
// ponytail: one helper closes the four-file copy-paste of setUp/tearDown;
// fake_comic_server_test.dart is excluded — it doesn't pump widgets and
// needs no image cache reset, so converting adds noise with no benefit.
void useComicServer(
  FakeComicServer Function() build,
  void Function(FakeComicServer) onCreated,
  FakeComicServer Function() getter,
) {
  setUp(() async {
    wakelockCalls.clear();
    final s = build();
    onCreated(s);
    await s.start();
    resetImageCaches();
  });
  // ponytail: give the server 500ms real time to finish draining in-flight
  // PUT /reading requests before force-closing; prevents HttpException noise.
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await getter().stop();
  });
}

int _dbCounter = 0;

Future<ReaderHarness> pumpReader(
  WidgetTester tester, {
  required FakeComicServer server,
  required Directory tempDir,
  String comicId = 'c1',
  String comicPath = '/library/c1.cbz',
  int initialPage = 0,
  List<SeriesIssue>? seriesIssues,
  int? currentIssueIndex,
  // ponytail: riverpod 3.x public barrel doesn't export Override (verified riverpod-3.2.1
  // lib/riverpod.dart show-list); dynamic is required for the spread into ProviderScope.overrides
  List<dynamic> extraOverrides = const [],
  Stream<Map<String, dynamic>> Function()? remoteCommands,
}) async {
  // The first-run tap-zone hint is covered by its own widget test; mark it
  // already-shown here so it never overlays the reader in these tests. The
  // bedtime reminder is off so evening test runs see no snackbar.
  SharedPreferences.setMockInitialValues({
    'server_url': server.url,
    'tap_zone_onboarding_v2_shown': true,
    'bedtime_reminder_on': false,
  });
  final prefs = await SharedPreferences.getInstance();
  final db = MirrorDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final queue =
      SyncQueue(queuePath: '${tempDir.path}/sync_queue_${_dbCounter++}.json');

  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: server.url, deviceId: 'test-device')),
      mirrorDbProvider.overrideWithValue(db),
      syncQueueProvider.overrideWithValue(queue),
      connectivityProvider.overrideWith(_AlwaysOnline.new),
      // The fake comic server has no /remote/events, so without this every
      // reader test would open a real SSE connection, 404, and spin the
      // reconnect backoff on real timers. A named parameter rather than an
      // extraOverride because Riverpod 3 asserts on a doubly-overridden
      // provider — the remote tests pass their stream through here.
      remoteCommandsProvider.overrideWithValue(
          remoteCommands ?? () => const Stream<Map<String, dynamic>>.empty()),
      ...extraOverrides,
    ],
    child: MaterialApp(
      home: ReaderScreen(
        comicId: comicId,
        comicPath: comicPath,
        initialPage: initialPage,
        seriesIssues: seriesIssues,
        currentIssueIndex: currentIssueIndex,
      ),
    ),
  ));

  return ReaderHarness(server, db, queue, (
    comicId: comicId,
    comicPath: comicPath,
    seriesIssues: seriesIssues,
    currentIssueIndex: currentIssueIndex,
  ));
}

/// Widget tests run in FakeAsync; real HTTP + PNG decode need real async.
/// Alternate runAsync (real time) with pump (fake time) until images land.
Future<void> settleImages(WidgetTester tester, {int rounds = 20}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Under a loaded machine (the full suite runs files in parallel) a fixed
/// number of settle rounds isn't always enough: wait for the condition itself.
Future<void> settleUntil(
  WidgetTester tester,
  bool Function() done, {
  int maxRounds = 300,
}) async {
  for (var i = 0; i < maxRounds && !done(); i++) {
    await settleImages(tester, rounds: 1);
  }
}

/// The page on screen has loaded its image and computed its steps (the
/// reader keeps a page at opacity 0 until then).
bool pageReady(WidgetTester tester) => tester
    .widgetList<Opacity>(
      find.ancestor(of: find.byType(Image), matching: find.byType(Opacity)),
    )
    .any((o) => o.opacity == 1);

/// Tear the reader down and burn residual timers (
/// progress debounce, HTTP keepalive, _saveProgress timeout) so
/// flutter_test's pending-timer check passes.
///
/// pumpWidget(SizedBox) unmounts reader; runAsync drains real HTTP so the
/// PUT /reading round-trip completes before tearDown stops the server.
/// Interleaved pump() after runAsync processes any frame callbacks scheduled
/// by image decoders before they accumulate into subsequent tests.
/// The 31s covers: _saveProgress .timeout(30s) fake timer,
/// and HTTP keepalive timers.
Future<void> disposeReader(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
  await tester.pump(); // drain frame callbacks from image decoders
  await tester.pump(const Duration(seconds: 31));
}
