// lib/providers/scan_state.dart
import '../models/chapter_candidate.dart';

enum ScanPhase { idle, running, done, failed }

class ScanState {
  final ScanPhase phase;
  final String? comicId;
  final String? title;
  final int scanned;
  final int total;
  final List<ChapterCandidate> candidates;
  final String? error;

  const ScanState({
    this.phase = ScanPhase.idle,
    this.comicId,
    this.title,
    this.scanned = 0,
    this.total = 0,
    this.candidates = const [],
    this.error,
  });

  double get progress => total > 0 ? scanned / total : 0;
  bool get isRunning => phase == ScanPhase.running;

  ScanState copyWith({
    ScanPhase? phase,
    String? comicId,
    String? title,
    int? scanned,
    int? total,
    List<ChapterCandidate>? candidates,
    String? error,
  }) =>
      ScanState(
        phase: phase ?? this.phase,
        comicId: comicId ?? this.comicId,
        title: title ?? this.title,
        scanned: scanned ?? this.scanned,
        total: total ?? this.total,
        candidates: candidates ?? this.candidates,
        error: error ?? this.error,
      );
}
