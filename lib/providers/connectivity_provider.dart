import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/app_logger.dart';
import '../services/connectivity_state_machine.dart';
import 'mirror_provider.dart';
import 'providers.dart';
import 'source_provider.dart';

final connectivityProvider =
    NotifierProvider<ConnectivityNotifier, bool>(ConnectivityNotifier.new);

/// Settings switch: make the app act offline while the network is fine, to
/// check what's readable before a trip. Not persisted — a relaunch clears it,
/// so it can't be forgotten on.
final simulateOfflineProvider =
    NotifierProvider<SimulateOfflineNotifier, bool>(SimulateOfflineNotifier.new);

class SimulateOfflineNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool on) => state = on;
}

class ConnectivityNotifier extends Notifier<bool> {
  final ConnectivityStateMachine _sm = ConnectivityStateMachine();
  Timer? _pollTimer;
  Timer? _syncTimer;
  static const _foregroundSyncInterval = Duration(seconds: 60);
  AppLifecycleListener? _lifecycleListener;
  Future<void>? _currentDrain;
  int _scheduleCountForTesting = 0;

  @override
  bool build() {
    _scheduleTimer();
    _startSyncTimer();
    _lifecycleListener =
        AppLifecycleListener(onResume: onAppResumed, onHide: onAppHidden);
    // At launch the engine may not exist yet (docsDir future unresolved), so
    // the first microtask drain can no-op. Kick a drain the moment the engine
    // becomes available so the initial sync is deterministic.
    ref.listen(syncEngineProvider, (prev, next) {
      if (prev == null && next != null) unawaited(_drain());
    });
    // Switching sources swaps the mirror database; the new source may never
    // have synced. Kick a drain so its mirror populates immediately.
    ref.listen(activeSourceProvider, (prev, next) {
      if (prev != null && prev.id != next.id) unawaited(_drain());
    });
    // A replaced engine means a new client or mirror: onboarding fills in the
    // blank default source in place (same id), and a login edit does too.
    // Without this the first sync waited for the next health poll under a
    // "Couldn't reach" card. Forced: a different server was never "pulled
    // recently". The client is built after the source changes, so the source
    // listener above is too early to see it.
    ref.listen(syncEngineProvider, (prev, next) {
      if (prev != null && next != null && !identical(prev, next)) {
        // Not inline: this can fire while the widget tree builds, and a
        // sync writes its progress to a provider at once.
        Future.microtask(() => _drain(force: true));
      }
    });
    // The test switch overrides the real state both ways.
    ref.listen(simulateOfflineProvider, (_, _) => state = _public);
    ref.onDispose(() {
      _pollTimer?.cancel();
      _syncTimer?.cancel();
      _lifecycleListener?.dispose();
    });
    Future.microtask(() async {
      await check();
      await _drain();
    });
    return _public;
  }

  /// What the app sees: the real state, unless the test switch says offline.
  bool get _public => !ref.read(simulateOfflineProvider) && _sm.isOnline;

  /// Public for tests only.
  ConnectivityState get internalStateForTesting => _sm.state;

  /// Public for tests only.
  Future<void>? get drainInFlightForTesting => _currentDrain;

  /// Public for tests only.
  int get scheduleCountForTesting => _scheduleCountForTesting;

  /// Called by [ApiClient] via the `onRequestOutcome` callback wired in
  /// [apiClientProvider]. Synchronous and fire-and-forget — never awaits.
  void reportOutcome(bool reachedServer) {
    final transition = _sm.reportOutcome(reachedServer);
    if (!transition.changed) return;

    if (transition.publicBoolChanged) {
      state = _public;
      AppLogger.instance.connectivity(
        level: LogLevel.info,
        message: _sm.isOnline ? 'online' : 'offline',
        context: {
          'from': transition.from.name,
          'to': transition.to.name,
        },
      );
    } else {
      AppLogger.instance.connectivity(
        level: LogLevel.debug,
        message: 'internal transition',
        context: {
          'from': transition.from.name,
          'to': transition.to.name,
        },
      );
    }

    if (_pollTierChanged(transition)) {
      _scheduleTimer();
    }

    if (transition.from == ConnectivityState.offline &&
        transition.to == ConnectivityState.online) {
      unawaited(_drain());
    }
  }

  bool _pollTierChanged(ConnectivityTransition t) =>
      (t.from == ConnectivityState.online) !=
      (t.to == ConnectivityState.online);

  /// Trigger an explicit health-check. Result flows back through
  /// [reportOutcome] via the [ApiClient] callback.
  Future<void> check() async {
    try {
      await ref.read(apiClientProvider).checkConnection();
    } catch (_) {
      // checkConnection swallows its own errors; this catch is paranoia.
    }
  }

  /// Called by [AppLifecycleListener] on resume. Public for testing.
  /// Always syncs — we now pull server deltas on resume, not just push.
  void onAppResumed() {
    unawaited(check());
    unawaited(_drain());
    _startSyncTimer();
  }

  /// Called by [AppLifecycleListener] when the app is no longer visible.
  /// Public for testing.
  void onAppHidden() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Public for tests only.
  bool get syncTimerActiveForTesting => _syncTimer != null;

  void _scheduleTimer() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_sm.pollInterval, (_) => check());
    _scheduleCountForTesting++;
  }

  /// Foreground periodic sync (study rec 3): another device's progress
  /// appears within a minute while browsing. _drain() already guards
  /// OPDS sources, missing engine, and drains in flight.
  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer =
        Timer.periodic(_foregroundSyncInterval, (_) => unawaited(_drain()));
  }

  Future<void> _drain({bool force = false}) async {
    // Guard: the launch microtask / resume listener can fire after the
    // container is disposed (tests, source switches); ref.read would throw.
    if (!ref.mounted) return;
    // OPDS sources have no /sync endpoint — only custom backends mirror.
    if (!ref.read(hasMirrorProvider)) return;
    if (_currentDrain != null) {
      if (!force) return;
      // A drain on the replaced engine is in flight; run after it.
      await _currentDrain;
      if (!ref.mounted || _currentDrain != null) return;
    }
    final engine = ref.read(syncEngineProvider);
    if (engine == null) return;
    final f = engine.sync(force: force).catchError((Object e) {
      AppLogger.instance.sync(
        level: LogLevel.warn,
        message: 'sync failed',
        context: {'error': e.toString()},
      );
    }).whenComplete(() {
      _currentDrain = null;
      if (!ref.mounted) return;
      final covers = ref.read(coverSyncerProvider);
      if (covers != null) unawaited(covers.syncCovers());
    });
    _currentDrain = f;
    await f;
  }
}
