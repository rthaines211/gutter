import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../config/string_utils.dart';
import '../models/recommendation.dart';
import '../providers/providers.dart';
import '../providers/recommendation_provider.dart';
import '../screens/series_detail_screen.dart';
import '../services/foundation_models_channel.dart';
import 'shimmer_box.dart';

class RecommendationCard extends ConsumerWidget {
  const RecommendationCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recommendationProvider);
    return async.when(
      loading: () => const _Shimmer(),
      error: (e, _) => _ErrorChip(
        error: e,
        onRetry: () => ref.read(recommendationProvider.notifier).reroll(),
      ),
      data: (rec) {
        if (rec == null) return const SizedBox.shrink();
        return _Loaded(rec: rec);
      },
    );
  }
}

class _Shimmer extends StatelessWidget {
  const _Shimmer();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('rec-card-shimmer'),
      padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: ShimmerBox(height: 140, radius: 16),
    );
  }
}

class _ErrorChip extends StatelessWidget {
  const _ErrorChip({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  String _detail() {
    final e = error;
    if (e is ModelGenerationError) return '${e.code}: ${e.message}';
    if (e is ModelUnavailable) return 'Model unavailable: ${e.message}';
    if (e is ModelDecodingError) return 'Decoding failure: ${e.message}';
    if (e is ModelTimeout) return 'Timed out';
    return '${e.runtimeType}: $e';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: context.scheme.s1,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Couldn't fetch a recommendation.",
                    style: TextStyle(color: context.scheme.t2),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _detail(),
                    style: TextStyle(
                      color: context.scheme.t3,
                      fontSize: 11,
                      fontFamily: 'Menlo',
                    ),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.rec});
  final Recommendation rec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(serverConfigProvider).serverUrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.scheme.s1,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Cover(rec: rec, serverUrl: serverUrl),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What should I read next?',
                      style: context.sectionHeader),
                  const SizedBox(height: 6),
                  Text(stripComicExtension(rec.title),
                      style: AppTheme.titleMedium),
                  if (rec.creator != null && rec.creator!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(rec.creator!,
                        style: TextStyle(
                            color: context.scheme.t2, fontSize: 13)),
                  ],
                  const SizedBox(height: 8),
                  Text(rec.reasoning,
                      style: TextStyle(
                          color: context.scheme.tx, fontSize: 13)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (rec.isInLibrary)
                        FilledButton(
                          onPressed: () => _open(context, rec),
                          child: const Text('Open'),
                        ),
                      if (rec.isInLibrary) const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => ref
                            .read(recommendationProvider.notifier)
                            .reroll(),
                        child: const Text('Re-roll'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, Recommendation rec) {
    if (rec.seriesId == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SeriesDetailScreen(seriesId: rec.seriesId!),
    ));
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.rec, required this.serverUrl});
  final Recommendation rec;
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    if (rec.isInLibrary && rec.seriesId != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: '$serverUrl/library/${rec.seriesId}/cover',
          httpHeaders: imageHeadersOf(context, '$serverUrl/library/${rec.seriesId}/cover'),
          width: 80, height: 120, fit: BoxFit.cover,
          errorWidget: (_, _, _) => const _GenericCover(),
        ),
      );
    }
    return const _GenericCover();
  }
}

class _GenericCover extends StatelessWidget {
  const _GenericCover();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80, height: 120,
      decoration: BoxDecoration(
        color: context.scheme.s2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.auto_awesome,
          color: context.scheme.t2, size: 32),
    );
  }
}
