import 'package:flutter/material.dart';
import '../providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/layout_breakpoint.dart';
import '../config/scheme.dart';
import '../config/string_utils.dart';
import '../models/reading_progress.dart';
import '../widgets/progress_bar.dart';
import 'caption_box.dart';
import 'cover_flight_route.dart';

/// "Up next" shelf card: 2:3 cover with a NEXT [CaptionBox] tag and a
/// progress bar over the art, title + mono page sub-line below on the page
/// background.
///
/// The tag and progress bar sit on the cover image, so their colours stay
/// literal light values (matches [CaptionBox]'s own rule and the progress
/// bar's default accent fill) — see docs/superpowers/DEFERRED.md "The scrim
/// bug class". The title and sub-line sit on `context.scheme.s1` (the card
/// body, not artwork), so they follow the scheme.
class UpNextCard extends ConsumerWidget {
  final ReadingProgress progress;
  final String serverUrl;
  final VoidCallback onTap;

  const UpNextCard({
    super.key,
    required this.progress,
    required this.serverUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comic = ComicTokens.watch(ref, context, AppTheme.accent);
    final path = comicIdToPath(progress.comicId);
    final name = stripComicExtension(
        path.contains('/') ? path.split('/').last : path);
    final pageLabel = 'P.${progress.currentPage + 1}/${progress.totalPages}';
    final width = LayoutBreakpoint.isTablet(context) ? 150.0 : 130.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: context.scheme.s1,
          borderRadius: BorderRadius.circular(AppTheme.r18),
          border: Border.all(
            color: context.scheme.borderFaint,
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppTheme.r18)),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CoverAnchor(
                      comicId: progress.comicId,
                      imageUrl: '$serverUrl/comics/${progress.comicId}/cover',
                      radius: AppTheme.r18,
                      child: CachedNetworkImage(httpHeaders: imageHeadersOf(context), 
                        imageUrl: '$serverUrl/comics/${progress.comicId}/cover',
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: context.scheme.s2),
                        errorWidget: (_, _, _) => Container(color: context.scheme.s2),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: CaptionBox(text: 'NEXT', comic: comic),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ProgressBar(value: progress.progress, height: 3),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: context.scheme.tx,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(pageLabel,
                      style: context.monoCaption.copyWith(fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
