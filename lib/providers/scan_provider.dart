// lib/providers/scan_provider.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import 'providers.dart';
import 'scan_state.dart';

class ScanController extends Notifier<ScanState> {
  Timer? _timer;
  String? _jobId;
  int _ticks = 0;
  int _lastScanned = 0;
  int _stallTicks = 0;

  static const _interval = Duration(seconds: 5);
  // Hard backstop so a wedged poll can't run forever (1440 * 5s = 2 h).
  static const _maxTicks = 1440;
  // Progress watchdog: fail only if OCR stops advancing for 48 * 5s = 4 min.
  // This lets very large omnibuses (1000+ pages) finish however long OCR takes,
  // while still catching a genuinely stuck/dead job quickly.
  static const _maxStallTicks = 48;

  @override
  ScanState build() {
    ref.onDispose(() => _timer?.cancel());
    return const ScanState();
  }

  Future<void> start({
    required String comicId,
    required String title,
    int? exemplarPage,
  }) async {
    if (state.phase == ScanPhase.running) return; // client-side one-at-a-time guard
    _timer?.cancel();
    _jobId = null;
    _ticks = 0;
    _lastScanned = 0;
    _stallTicks = 0;
    state = ScanState(phase: ScanPhase.running, comicId: comicId, title: title);

    final client = ref.read(apiClientProvider);
    try {
      final res = await client.detectChapters(comicId, exemplarPage: exemplarPage);
      if (!res.ocrPending || res.jobId == null) {
        state = state.copyWith(phase: ScanPhase.done, candidates: res.candidates);
        return;
      }
      _jobId = res.jobId;
      state = state.copyWith(candidates: res.candidates); // interim structural
      _timer = Timer.periodic(_interval, (_) => pollOnce());
    } on ApiException catch (e) {
      state = state.copyWith(
        phase: ScanPhase.failed,
        error: e.statusCode == 409 ? 'A scan is already running' : 'Scan failed to start',
      );
    } catch (_) {
      state = state.copyWith(phase: ScanPhase.failed, error: 'Scan failed to start');
    }
  }

  /// One poll cycle. The periodic timer calls this; tests call it directly.
  Future<void> pollOnce() async {
    final comicId = state.comicId;
    final jobId = _jobId;
    if (comicId == null || jobId == null || state.phase != ScanPhase.running) {
      _timer?.cancel();
      return;
    }
    _ticks++;
    if (_ticks >= _maxTicks) {
      _timer?.cancel();
      state = state.copyWith(phase: ScanPhase.failed, error: 'Scan timed out');
      return;
    }
    try {
      final st = await ref.read(apiClientProvider).detectChaptersStatus(comicId, jobId);
      switch (st.state) {
        case 'done':
          _timer?.cancel();
          state = state.copyWith(
            phase: ScanPhase.done,
            scanned: st.scanned,
            total: st.total,
            candidates: st.candidates,
          );
        case 'failed':
        case 'unknown':
          _timer?.cancel();
          state = state.copyWith(
            phase: ScanPhase.failed,
            error: st.state == 'unknown' ? 'Scan interrupted' : 'Scan failed',
          );
        default: // running
          // Progress watchdog: reset the stall counter whenever OCR advances a
          // page; fail only after a sustained stall (dead/stuck job).
          if (st.scanned > _lastScanned) {
            _lastScanned = st.scanned;
            _stallTicks = 0;
          } else {
            _stallTicks++;
            if (_stallTicks >= _maxStallTicks) {
              _timer?.cancel();
              state = state.copyWith(phase: ScanPhase.failed, error: 'Scan stalled');
              return;
            }
          }
          state = state.copyWith(scanned: st.scanned, total: st.total);
      }
    } catch (_) {
      // Transient network error — keep polling; the stall watchdog still applies.
    }
  }

  void cancel() {
    _timer?.cancel();
    state = const ScanState();
  }

  void clear() {
    _timer?.cancel();
    state = const ScanState();
  }
}

final scanProvider = NotifierProvider<ScanController, ScanState>(ScanController.new);
