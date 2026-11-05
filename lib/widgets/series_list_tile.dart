import 'package:flutter/material.dart';
import '../providers/providers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/series.dart';

class SeriesListTile extends StatelessWidget {
  final Series series;
  final String serverUrl;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  final Color accent;

  const SeriesListTile({
    super.key,
    required this.series,
    required this.serverUrl,
    required this.onTap,
    this.onLongPress,
    this.accent = AppTheme.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Cover thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 40,
                height: 56,
                child: series.coverUrl.isNotEmpty
                    ? CachedNetworkImage(httpHeaders: imageHeadersOf(context), 
                        imageUrl: '$serverUrl${series.coverUrl}',
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Container(color: context.scheme.s1),
                        errorWidget: (context, url, error) =>
                            Container(color: context.scheme.s1),
                      )
                    : Container(
                        color: context.scheme.s1,
                        child: Icon(Icons.auto_stories,
                            size: 20, color: context.scheme.t4),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Title & metadata
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          series.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: context.scheme.tx,
                          ),
                        ),
                      ),
                      if (series.isRecentlyAdded) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.amber,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'ADDED',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              fontFamily: '.SF Mono',
                              fontFamilyFallback: ['JetBrains Mono', 'monospace'],
                              letterSpacing: 0.3,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${series.readCount}/${series.issueCount} issues',
                        style: context.monoCaption,
                      ),
                      if (series.isInProgress) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: series.progress,
                              backgroundColor: context.scheme.hair,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  accent),
                              minHeight: 3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Status icon
            _buildStatusIcon(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    if (series.isCompleted) {
      return Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: AppTheme.green,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, size: 12, color: Colors.black),
      );
    }
    return Icon(Icons.chevron_right,
        size: 20, color: context.scheme.t3);
  }
}
