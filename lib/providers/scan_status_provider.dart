import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/scan_status.dart';
import 'providers.dart';

enum ScanPhase { idle, scanning, done, error }

class ScanStatusState {
  final ScanPhase phase;
  final ScanStatus status;
  final String? errorMessage;

  const ScanStatusState({
    this.phase = ScanPhase.idle,
    this.status = const ScanStatus(),
    this.errorMessage,
  });

  ScanStatusState copyWith({
    ScanPhase? phase,
    ScanStatus? status,
    String? errorMessage,
  }) {
    return ScanStatusState(
      phase: phase ?? this.phase,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class ScanStatusNotifier extends Notifier<ScanStatusState> {
  Timer? _pollTimer;

  @override
  ScanStatusState build() {
    ref.onDispose(() => _pollTimer?.cancel());
    return const ScanStatusState();
  }

  Future<void> startScan() async {
    final client = ref.read(apiClientProvider);

    try {
      final started = await client.refreshLibrary();
      if (!started) {
        // Already running — start polling to pick up existing scan
        state = state.copyWith(phase: ScanPhase.scanning);
        _startPolling();
        return;
      }
      state = state.copyWith(phase: ScanPhase.scanning);
      _startPolling();
    } catch (e) {
      state = state.copyWith(
        phase: ScanPhase.error,
        errorMessage: e.toString(),
      );
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    _poll();
  }

  Future<void> _poll() async {
    try {
      final client = ref.read(apiClientProvider);
      final status = await client.getScanStatus();

      if (status.isBusy) {
        state = state.copyWith(
          phase: ScanPhase.scanning,
          status: status,
        );
      } else {
        _pollTimer?.cancel();
        state = state.copyWith(
          phase: ScanPhase.done,
          status: status,
        );
      }
    } catch (e) {
      _pollTimer?.cancel();
      state = state.copyWith(
        phase: ScanPhase.error,
        errorMessage: e.toString(),
      );
    }
  }

  void dismiss() {
    _pollTimer?.cancel();
    state = const ScanStatusState();
  }
}

final scanStatusProvider =
    NotifierProvider<ScanStatusNotifier, ScanStatusState>(
        ScanStatusNotifier.new);
