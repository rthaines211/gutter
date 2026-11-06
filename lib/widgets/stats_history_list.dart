import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/reading_session.dart';
import '../providers/stats_provider.dart';
import '../providers/providers.dart';
import '../providers/source_provider.dart';
import '../screens/series_detail_screen.dart';
import 'shimmer_box.dart';

String _timeAgo(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inHours < 48) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final day = dt.day.toString().padLeft(2, '0');
  return '${months[dt.month - 1]} $day';
}

class StatsHistoryList extends ConsumerWidget {
  const StatsHistoryList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyState = ref.watch(statsHistoryProvider);
    final serverUrl = ref.watch(activeSourceProvider.select((s) => s.baseUrl));

    final sessions = historyState.sessions;
    final hasMore = historyState.hasMore;
    final loading = historyState.loading;
    final error = historyState.error;

    if (error != null && sessions.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            error,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: context.scheme.t3,
            ),
          ),
        ),
      );
    }

    if (sessions.isEmpty && !loading) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Text(
            'No reading history yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: context.scheme.t2,
            ),
          ),
        ),
      );
    }

    final itemCount = sessions.length + (hasMore ? 1 : 0);

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index >= sessions.length) {
            // Loading spinner / trigger for next page
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(statsHistoryProvider.notifier).loadMore();
            });
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(context.scheme.t3),
                  ),
                ),
              ),
            );
          }

          final session = sessions[index];
          return _HistoryRow(
            session: session,
            serverUrl: serverUrl,
            showDivider: index < sessions.length - 1,
          );
        },
        childCount: itemCount,
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final ReadingSession session;
  final String serverUrl;
  final bool showDivider;

  const _HistoryRow({
    required this.session,
    required this.serverUrl,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final coverUrl = session.coverUrl.isNotEmpty
        ? '$serverUrl${session.coverUrl}'
        : null;

    final detailText =
        '${session.pagesRead} ${session.pagesRead == 1 ? 'page' : 'pages'} · ${session.formattedDuration}';
    final timeText = _timeAgo(session.startedAt);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: session.seriesId.isNotEmpty
          ? () {
              Navigator.of(context).push(MaterialPageRoute(
                settings: const RouteSettings(name: '/series-detail'),
                builder: (_) =>
                    SeriesDetailScreen(seriesId: session.seriesId),
              ));
            }
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Cover thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.r8),
                  child: SizedBox(
                    width: 40,
                    height: 56,
                    child: coverUrl != null
                        ? CachedNetworkImage(
                            imageUrl: coverUrl,
                            httpHeaders: imageHeadersOf(context, coverUrl),
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const ShimmerBox(
                              width: 40,
                              height: 56,
                              radius: AppTheme.r8,
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: context.scheme.s2,
                              child: Icon(
                                Icons.auto_stories,
                                size: 20,
                                color: context.scheme.t4,
                              ),
                            ),
                          )
                        : Container(
                            color: context.scheme.s2,
                            child: Icon(
                              Icons.auto_stories,
                              size: 20,
                              color: context.scheme.t4,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                // Text content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.comicName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.scheme.tx,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detailText,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.scheme.t2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Timestamp
                Text(
                  timeText,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.scheme.t3,
                  ),
                ),
              ],
            ),
          ),
          if (showDivider)
            Divider(
              height: 1,
              thickness: 1,
              indent: 68,
              endIndent: 0,
              color: context.scheme.borderFaint,
            ),
        ],
      ),
    );
  }
}
