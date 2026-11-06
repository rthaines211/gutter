// lib/widgets/issue_grid_view.dart
import '../providers/mirror_provider.dart';
import '../providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/series.dart';
import 'issue_list_view.dart'; // WritebackBadge
import 'read_mark.dart';
import 'cover_flight_route.dart';

class IssueGridTile extends ConsumerWidget {
  final SeriesIssue issue;
  final String serverUrl;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const IssueGridTile({
    super.key,
    required this.issue,
    required this.serverUrl,
    required this.accent,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isInProgress = issue.status == 'in_progress';
    final isCompleted = issue.status == 'completed';
    final coverUrl = ref.watch(issueCoverUrlProvider(issue.id));
    final progress = (issue.currentPage != null && issue.totalPages != null && issue.totalPages! > 0)
        ? issue.currentPage! / issue.totalPages!
        : 0.0;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.r12),
                border: isInProgress
                    ? Border.all(color: accent.withValues(alpha: 0.5), width: 1.5)
                    : Border.all(color: context.scheme.borderFaint, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    offset: const Offset(0, 4),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.r12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CoverAnchor(
                      comicId: issue.id,
                      imageUrl: coverUrl,
                      radius: AppTheme.r12,
                      child: CachedNetworkImage(
                        imageUrl: coverUrl,
                        httpHeaders: imageHeadersOf(context, coverUrl),
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: context.scheme.s1),
                        errorWidget: (_, _, _) => Container(
                          color: context.scheme.s1,
                          child: Center(
                            child: Text(
                              issue.number ?? '?',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: context.scheme.t3,
                                fontFamily: '.SF Mono',
                                fontFamilyFallback: const ['JetBrains Mono', 'monospace'],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Issue number badge — top left
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#${issue.number ?? '?'}',
                          // On the black badge fill, not a scheme surface —
                          // stays light in every theme.
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            fontFamily: '.SF Mono',
                            fontFamilyFallback: ['JetBrains Mono', 'monospace'],
                            letterSpacing: 0.3,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // Read check — top right. Animates a stamp when the
                    // issue flips to read while on screen.
                    Positioned.fill(
                      child: ReadMark(
                        issueId: issue.id,
                        isRead: isCompleted,
                        accent: accent,
                      ),
                    ),
                    // Writeback error badge — bottom left corner
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: WritebackBadge(issue: issue),
                    ),
                    // In-progress bar — bottom
                    if (isInProgress && progress > 0)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 3,
                          color: Colors.black.withValues(alpha: 0.5),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(
                              decoration: BoxDecoration(
                                color: accent,
                                boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: 4)],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            issue.enrichedDisplayTitle ?? issue.displayName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isCompleted ? context.scheme.t3 : context.scheme.tx,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
