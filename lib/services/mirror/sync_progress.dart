import 'package:clock/clock.dart';

enum SyncStage { idle, pushing, fetching, applying, covers, done, failed }

/// What the current (or last) mirror sync is doing, for the sync UI.
/// [SyncEngine] and [CoverSyncer] write it through a [SyncProgressUpdate].
class SyncProgress {
  final SyncStage stage;

  /// The first pull for this source (no watermark yet).
  final bool initial;
  final int seriesDone;

  /// Null until the pull knows how many series it will read.
  final int? seriesTotal;
  final int coversDone;
  final int? coversTotal;
  final DateTime? startedAt;
  final DateTime? lastProgressAt;
  final Object? error;

  const SyncProgress({
    this.stage = SyncStage.idle,
    this.initial = false,
    this.seriesDone = 0,
    this.seriesTotal,
    this.coversDone = 0,
    this.coversTotal,
    this.startedAt,
    this.lastProgressAt,
    this.error,
  });

  factory SyncProgress.start() {
    final now = clock.now();
    return SyncProgress(
        stage: SyncStage.pushing, startedAt: now, lastProgressAt: now);
  }

  bool get running =>
      stage.index >= SyncStage.pushing.index &&
      stage.index <= SyncStage.covers.index;

  /// A copy with [lastProgressAt] stamped now.
  SyncProgress next({
    SyncStage? stage,
    bool? initial,
    int? seriesDone,
    int? seriesTotal,
    int? coversDone,
    int? coversTotal,
    Object? error,
  }) =>
      SyncProgress(
        stage: stage ?? this.stage,
        initial: initial ?? this.initial,
        seriesDone: seriesDone ?? this.seriesDone,
        seriesTotal: seriesTotal ?? this.seriesTotal,
        coversDone: coversDone ?? this.coversDone,
        coversTotal: coversTotal ?? this.coversTotal,
        startedAt: startedAt ?? clock.now(),
        lastProgressAt: clock.now(),
        error: error ?? this.error,
      );
}

typedef SyncProgressUpdate = void Function(
    SyncProgress Function(SyncProgress) update);
