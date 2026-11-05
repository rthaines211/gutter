import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

typedef HeartbeatSnapshot = ({
  String route,
  String? comicId,
  int? page,
  int? totalPages,
  String? lastAction,
  int cacheCount,
  int cacheBytes,
});

class HeartbeatWriter with WidgetsBindingObserver {
  HeartbeatWriter({
    required this.heartbeatFile,
    required HeartbeatSnapshot Function() snapshot,
    Duration interval = const Duration(seconds: 5),
  })  : _snapshot = snapshot,
        _interval = interval;

  final File heartbeatFile;
  final HeartbeatSnapshot Function() _snapshot;
  final Duration _interval;

  Timer? _timer;
  String? _stateOverride;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  void init() {
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    // Write one immediately so heartbeat is fresh from launch.
    unawaited(_write());
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    unawaited(_write());
    if (state == AppLifecycleState.resumed) {
      _startTimer();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => unawaited(_write()));
  }

  Future<void> _write() async {
    final s = _snapshot();
    final state = _stateOverride ?? _lifecycleToState();
    final payload = <String, Object?>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'state': state,
      'route': s.route,
      if (s.comicId != null) 'comicId': s.comicId,
      if (s.page != null) 'page': s.page,
      if (s.totalPages != null) 'totalPages': s.totalPages,
      if (s.lastAction != null) 'lastAction': s.lastAction,
      'imageCache': {'count': s.cacheCount, 'bytes': s.cacheBytes},
    };
    final tmp = File('${heartbeatFile.path}.tmp');
    try {
      await tmp.writeAsString(jsonEncode(payload), flush: true);
      await tmp.rename(heartbeatFile.path);
    } catch (_) {
      // Best-effort; never throw out of diagnostic plumbing.
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  String _lifecycleToState() {
    switch (_lifecycle) {
      case AppLifecycleState.resumed:
        return 'resumed';
      case AppLifecycleState.inactive:
        return 'inactive';
      case AppLifecycleState.paused:
        return 'paused';
      case AppLifecycleState.detached:
        return 'detached';
      case AppLifecycleState.hidden:
        return 'hidden';
    }
  }

  @visibleForTesting
  Future<void> tickForTest() => _write();

  @visibleForTesting
  void overrideStateForTest(String state) {
    _stateOverride = state;
  }
}
