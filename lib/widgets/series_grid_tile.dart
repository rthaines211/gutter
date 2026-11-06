// lib/widgets/series_grid_tile.dart
import '../services/mirror/cover_syncer.dart';
import '../providers/providers.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/scheme.dart';
import '../models/series.dart';
import 'caption_box.dart';
import 'panel_frame.dart';
import '../config/layout_breakpoint.dart';

class SeriesGridTile extends ConsumerWidget {
  final Series series;
  final String serverUrl;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final int density; // 2, 3, or 4 columns

  final Color accent;
  final String? localCoverPath;

  /// Offline only: issues of this series on the device. 0 dims the tile;
  /// more shows an "N on iPad" badge. Null (online) changes nothing.
  final int? onDevice;

  const SeriesGridTile({
    super.key,
    required this.series,
    required this.serverUrl,
    required this.onTap,
    this.onLongPress,
    this.density = 3,
    this.accent = AppTheme.accent,
    this.localCoverPath,
    this.onDevice,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comic = ComicTokens.watch(ref, context, accent);
    final tile = GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildCover(context, comic)),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              series.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: density == 2 ? 14 : (density == 3 ? 12.5 : 11),
                fontWeight: FontWeight.w600,
                color: context.scheme.tx,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${series.readCount}/${series.issueCount}',
                style: context.monoCaption,
              ),
            ],
          ),
        ],
      ),
    );
    return onDevice == 0 ? Opacity(opacity: 0.4, child: tile) : tile;
  }

  Widget _buildCover(BuildContext context, ComicTokens comic) {
    return Hero(
      tag: 'cover-series-${series.id}',
      child: Material(
        type: MaterialType.transparency,
        child: PanelFrame(
        radius: density == 2 ? AppTheme.r16 : (density == 3 ? AppTheme.r12 : AppTheme.r8),
        accent: accent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _coverImage(context),
          // Completed badge
          if (series.isCompleted)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: AppTheme.green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 12, color: Colors.black),
              ),
            ),
          // NEW badge: only for series that are both recently added AND unread.
          if (series.isUnread && series.isRecentlyAdded && !series.isCompleted)
            Positioned(
              top: 6,
              right: 6,
              child: CaptionBox(text: 'NEW', comic: comic, rightSide: true),
            ),
          if (onDevice == 0)
            const Positioned(
              bottom: 8,
              right: 8,
              child: Icon(Icons.cloud_outlined, size: 18, color: Colors.white70),
            ),
          if ((onDevice ?? 0) > 0)
            Positioned(
              bottom: 8,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '$onDevice on ${LayoutBreakpoint.deviceNoun}',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ),
            ),
          // In-progress bar
          if (series.isInProgress)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 3,
                color: Colors.black.withValues(alpha: 0.5),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: series.progress,
                  child: Container(color: accent),
                ),
              ),
            ),
        ],
      ),
      ),
      ),
    );
  }

  // Decode covers at roughly tile size instead of full thumbnail size; halves
  // memory and removes decode jank while scrolling.
  static const int _decodeWidth = coverDecodeWidth;

  Widget _coverImage(BuildContext context) {
    final Widget network = series.coverUrl.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: '$serverUrl${series.coverUrl}',
            httpHeaders: imageHeadersOf(context, '$serverUrl${series.coverUrl}'),
            fit: BoxFit.cover,
            memCacheWidth: _decodeWidth,
            placeholder: (_, _) => Container(color: context.scheme.s1),
            errorWidget: (_, _, _) => _fallback(context),
          )
        : _fallback(context);
    if (localCoverPath == null) return network;
    return Image.file(
      File(localCoverPath!),
      fit: BoxFit.cover,
      cacheWidth: _decodeWidth,
      // Cover not downloaded yet (or deleted) — fall back to network.
      errorBuilder: (_, _, _) => network,
    );
  }

  Widget _fallback(BuildContext context) {
    return Container(
      color: context.scheme.s1,
      child: Icon(Icons.auto_stories, size: 48, color: context.scheme.t4),
    );
  }
}
