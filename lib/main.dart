import 'dart:io';
import 'providers/pro_provider.dart';
import 'services/source_auth_client.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'providers/app_breadcrumbs.dart';
import 'providers/connectivity_provider.dart';
import 'providers/providers.dart';
import 'providers/source_provider.dart';
import 'services/app_logger.dart';
import 'services/crash_detector.dart';
import 'services/error_capture.dart';
import 'services/heartbeat_writer.dart';
import 'services/memory_pressure_watcher.dart';
import 'config/flavor.dart';
import 'config/platform.dart';
import 'services/push_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android 15 forces edge-to-edge; draw under transparent bars everywhere
  // and let SafeArea/MediaQuery padding keep content clear (as on iOS).
  if (isAndroid) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ));
  }

  // Tuned for iPad memory budget. Prefetcher only holds ~5-8 pages ahead;
  // the rest is LRU-cached recently-viewed pages which can be evicted safely.
  PaintingBinding.instance.imageCache.maximumSize = 100;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 * 1024 * 1024; // 256 MB
  // Every CachedNetworkImage fetches through the source's credentials.
  CachedNetworkImageProvider.defaultCacheManager = SourceImageCacheManager();

  await AppLogger.init(
    logDirFactory: () async => getApplicationDocumentsDirectory(),
  );

  final docsDir = await getApplicationDocumentsDirectory();
  final heartbeatFile = File('${docsDir.path}/heartbeat.json');

  await CrashDetector.runOnce(heartbeatFile: heartbeatFile);

  installErrorCapture();

  MemoryPressureWatcher().init();

  final prefs = await SharedPreferences.getInstance();
  final credentials = await readSourceCredentials(prefs);
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      sourceCredentialsProvider.overrideWithValue(credentials),
    ],
  );
  // Listen to StoreKit from launch: purchases approved while the app was
  // closed (Ask to Buy, a kill mid-purchase) arrive now, not at a paywall.
  container.read(proProvider);

  HeartbeatWriter(
    heartbeatFile: heartbeatFile,
    snapshot: () {
      final s = container.read(appBreadcrumbsProvider);
      final c = PaintingBinding.instance.imageCache;
      return (
        route: s.route,
        comicId: s.comicId,
        page: s.page,
        totalPages: s.totalPages,
        lastAction: s.lastAction,
        cacheCount: c.currentSize,
        cacheBytes: c.currentSizeBytes,
      );
    },
  ).init();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ComicReaderApp(),
    ),
  );

  // Instantiate connectivity so launch sync + queue draining run even before
  // any screen watches it.
  container.read(connectivityProvider);

  // After the first frame so a cold-start tap can push onto a live navigator.
  // Push is personal-only: the store app has no aps-environment entitlement.
  // APNs only: no Android push.
  if (!isStore && !isAndroid) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final push = PushService(
      channel: const MethodChannel('app.comic_reader/push'),
      client: http.Client(),
      source: () => container.read(activeSourceProvider),
      onTap: (screen) => routePushTap(container, screen),
    );
    container.listen(activeSourceProvider, (prev, next) {
      if (prev?.baseUrl != next.baseUrl || prev?.apiKey != next.apiKey) {
        push.sourceChanged();
      }
    });
    push.start();
  });
  }
}
