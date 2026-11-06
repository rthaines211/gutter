import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/review_item.dart';
import '../services/api_client.dart';
import 'providers.dart';

class ReviewQueueState {
  final List<ReviewItem> items;
  final int cursor;
  final bool busy;

  const ReviewQueueState({
    this.items = const [],
    this.cursor = 0,
    this.busy = false,
  });

  ReviewItem? get current => items.isEmpty ? null : items[cursor];

  ReviewQueueState copyWith({
    List<ReviewItem>? items,
    int? cursor,
    bool? busy,
  }) => ReviewQueueState(
    items: items ?? this.items,
    cursor: cursor ?? this.cursor,
    busy: busy ?? this.busy,
  );
}

class ReviewQueueNotifier extends AsyncNotifier<ReviewQueueState> {
  @override
  Future<ReviewQueueState> build() async {
    final r = await ref.watch(apiClientProvider).fetchReviewQueue();
    return ReviewQueueState(items: r.items);
  }

  /// Refetch the queue. No-op while an action is in flight (it would reset
  /// busy and the action's own result handling would act on a stale queue).
  Future<void> reload() async {
    if (state.value?.busy == true) return;
    await _load();
  }

  Future<void> _load() async {
    final r = await ref.read(apiClientProvider).fetchReviewQueue();
    if (!ref.mounted) return;
    final cursor = state.value?.cursor ?? 0;
    state = AsyncData(
      ReviewQueueState(
        items: r.items,
        cursor: r.items.isEmpty ? 0 : cursor.clamp(0, r.items.length - 1),
      ),
    );
  }

  Future<void> confirm() => _act((api, id) => api.confirmReview(id));
  Future<void> pin(VolumeHit hit) =>
      _act((api, id) => api.pinReviewVolume(id, hit));
  Future<void> dontMatch() => _act((api, id) => api.dontMatchReview(id));

  void skip() {
    final s = state.value;
    if (s == null || s.items.isEmpty || s.busy) return;
    state = AsyncData(s.copyWith(cursor: (s.cursor + 1) % s.items.length));
  }

  Future<void> _act(
    Future<void> Function(ApiClient api, String id) call,
  ) async {
    final s = state.value;
    final cur = s?.current;
    if (s == null || cur == null || s.busy) return;
    state = AsyncData(s.copyWith(busy: true));
    try {
      await call(ref.read(apiClientProvider), cur.seriesId);
      if (!ref.mounted) return;
      // Remove by id from the *current* state, not the pre-await snapshot.
      final latest = state.value ?? s;
      final items = latest.items.where((i) => i.seriesId != cur.seriesId).toList();
      state = AsyncData(
        ReviewQueueState(
          items: items,
          cursor: items.isEmpty ? 0 : latest.cursor.clamp(0, items.length - 1),
        ),
      );
    } catch (_) {
      if (ref.mounted) {
        try {
          await _load();
        } catch (_) {
          if (ref.mounted) state = AsyncData(s.copyWith(busy: false));
        }
      }
      rethrow;
    }
  }
}

final reviewQueueProvider =
    AsyncNotifierProvider<ReviewQueueNotifier, ReviewQueueState>(
      ReviewQueueNotifier.new,
      // Surface load errors (Retry button) instead of silent auto-retry.
      retry: (_, _) => null,
    );

/// 0 without fetching where Review is hidden (store app, not a Gutter server).
final reviewCountProvider = Provider<int>(
  (ref) => !ref.watch(gutterFeaturesProvider)
      ? 0
      : ref.watch(reviewQueueProvider).value?.items.length ?? 0,
);
