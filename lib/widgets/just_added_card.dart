import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/layout_breakpoint.dart';
import '../config/scheme.dart';
import '../models/series.dart';
import '../widgets/panel_frame.dart';
import 'caption_box.dart';

/// "Just added" shelf card: 2:3 cover with a NEW [CaptionBox] tag, title and
/// issue-count sub-line below on the page background.
///
/// The tag sits on the cover art, so it stays literal (handled by
/// [CaptionBox] itself) — see docs/superpowers/DEFERRED.md "The scrim bug
/// class". The title and sub-line sit on the page background, so they
/// follow the scheme.
class JustAddedCard extends ConsumerWidget {
  final Series series;
  final String serverUrl;
  final VoidCallback onTap;

  const JustAddedCard({
    super.key,
    required this.series,
    required this.serverUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comic = ComicTokens.watch(ref, context, AppTheme.accent);
    final coverUrl = series.coverUrl.isNotEmpty
        ? '$serverUrl${series.coverUrl}'
        : null;
    final width = LayoutBreakpoint.isTablet(context) ? 120.0 : 100.0;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                PanelFrame(
                  radius: AppTheme.r14,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: coverUrl != null
                        ? CachedNetworkImage(
                            imageUrl: coverUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                Container(color: context.scheme.s1),
                            errorWidget: (_, _, _) =>
                                Container(color: context.scheme.s1),
                          )
                        : Container(color: context.scheme.s1),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: CaptionBox(text: 'NEW', comic: comic),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(series.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: context.scheme.tx,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text('${series.issueCount} issue${series.issueCount == 1 ? '' : 's'}',
                style: context.monoCaption.copyWith(fontSize: 9)),
          ],
        ),
      ),
    );
  }
}
