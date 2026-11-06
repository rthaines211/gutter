// lib/widgets/issue_list_view.dart
import 'package:flutter/material.dart';
import '../config/source_urls.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/scheme.dart';
import '../models/series.dart';
import '../providers/download_provider.dart';
import '../providers/source_provider.dart';
import '../providers/providers.dart';
import 'caption_box.dart';
import 'download_button.dart';
import 'cover_flight_route.dart';

/// Lays out [IssueListRow]s in one column, or two once the available width
/// (the PANEL's width, learned via [LayoutBuilder] — not [MediaQuery], since
/// this widget is shared by the iPad split panel and the full-screen series
/// detail view, and only the panel's own constraints tell it which one it's
/// in) reaches [wideBreakpoint].
///
/// Deliberately does not group rows by story arc — `SeriesIssue` carries no
/// arc field, and joining through `arcItemRows` for an issue->arc lookup is
/// its own follow-up task, not part of this restyle.
class WritebackBadge extends StatelessWidget {
  final SeriesIssue issue;

  const WritebackBadge({super.key, required this.issue});

  static const _errorColor = Color(0xFFFF3B30); // matches comic-red accent

  @override
  Widget build(BuildContext context) {
    if (issue.writebackStatus != 'error') return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            issue.writebackError ?? 'Metadata could not be written to the file',
          ),
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.only(left: 4),
        child: Icon(Icons.sync_problem, size: 16, color: _errorColor),
      ),
    );
  }
}

class IssueListRow extends ConsumerWidget {
  final SeriesIssue issue;
  final String serverUrl;
  final String seriesId;
  final String seriesName;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const IssueListRow({
    super.key,
    required this.issue,
    required this.serverUrl,
    required this.seriesId,
    required this.seriesName,
    required this.accent,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isInProgress = issue.status == 'in_progress';
    final isCompleted = issue.status == 'completed';
    final comic = ComicTokens.watch(ref, context, accent);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          // "acs" fill: accent at 16% for the in-progress row. Distinct from
          // AppTheme.accentSoft (14%, used elsewhere) — the design calls for
          // 16% specifically here.
          color: isInProgress
              ? accent.withValues(alpha: 0.16)
              : context.scheme.s1,
          borderRadius: BorderRadius.circular(AppTheme.r16),
          border: isInProgress
              ? Border.all(
                  color: accent.withValues(alpha: 0.35),
                  width: 0.5,
                )
              : null,
        ),
        child: Row(
          children: [
            // Cover thumbnail — small (36x52) and nothing overlays it, so no
            // pinned-light text sits on top; scheme colours are fine.
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 36,
                height: 52,
                child: Opacity(
                  opacity: isCompleted ? 0.55 : 1.0,
                  child: CoverAnchor(
                    comicId: issue.id,
                    imageUrl: ref.watch(activeSourceProvider).comicCover(issue.id),
                    child: CachedNetworkImage(
                      imageUrl: ref.watch(activeSourceProvider).comicCover(issue.id),
                      httpHeaders: imageHeadersOf(context, ref.watch(activeSourceProvider).comicCover(issue.id)),
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(color: context.scheme.s2),
                      errorWidget: (_, _, _) => Container(color: context.scheme.s2),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Status circle (30px)
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCompleted
                    ? AppTheme.green.withValues(alpha: 0.18)
                    : isInProgress
                        ? accent.withValues(alpha: 0.15)
                        : context.scheme.s2,
                border: Border.all(
                  color: isCompleted
                      ? AppTheme.green.withValues(alpha: 0.3)
                      : isInProgress
                          ? accent.withValues(alpha: 0.3)
                          : context.scheme.hair,
                  width: 0.5,
                ),
              ),
              child: Center(
                child: isCompleted
                    ? const Icon(Icons.check_rounded, size: 15, color: AppTheme.green)
                    : isInProgress
                        ? Icon(Icons.play_arrow_rounded, size: 15, color: accent)
                        : Text(
                            issue.number ?? '?',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: context.scheme.t2,
                              fontFamily: '.SF Mono',
                              fontFamilyFallback: const ['JetBrains Mono', 'monospace'],
                            ),
                          ),
              ),
            ),
            const SizedBox(width: 12),

            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    issue.enrichedDisplayTitle ?? issue.name,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: isCompleted ? context.scheme.t2 : context.scheme.tx,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  if (isInProgress && issue.currentPage != null && issue.totalPages != null)
                    Text(
                      'Page ${issue.currentPage! + 1} of ${issue.totalPages}',
                      style: context.monoCaption.copyWith(fontSize: 10),
                    )
                  else if (isCompleted)
                    Text('Read', style: context.monoCaption.copyWith(fontSize: 10, color: AppTheme.green))
                  else
                    Text(
                      issue.totalPages != null ? '${issue.totalPages} pages' : '',
                      style: context.monoCaption.copyWith(fontSize: 10),
                    ),
                ],
              ),
            ),

            // Writeback error badge
            WritebackBadge(issue: issue),

            // "READING" tag for current issue
            if (isInProgress) ...[
              const SizedBox(width: 8),
              CaptionBox(text: 'READING', comic: comic),
            ],

            // Download button
            DownloadButton(
              comicId: issue.id,
              sourceId: ref.read(activeSourceProvider).id,
              onTap: () {
                final source = ref.read(activeSourceProvider);
                ref.read(downloadManagerProvider)?.enqueue(
                  comicId: issue.id,
                  sourceId: source.id,
                  seriesId: seriesId,
                  seriesName: seriesName,
                  comicName: issue.name,
                  comicUrl: source.comicDownload(issue.id),
                  headers: {
                    'Content-Type': 'application/json',
                    'X-Device-ID': ref.read(serverConfigProvider).deviceId,
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
