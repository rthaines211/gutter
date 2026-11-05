import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/layout_breakpoint.dart';
import '../config/reading_estimate.dart';
import '../config/scheme.dart';
import '../config/string_utils.dart';
import '../models/comic_info.dart';
import '../models/reading_progress.dart';
import '../providers/providers.dart';
import 'halftone_overlay.dart';
import 'cover_flight_route.dart';

/// ComicInfo for the hero's issue: display name, summary and chapters.
/// Null when the server can't be reached; the hero falls back to the filename
/// and page progress.
final heroComicInfoProvider = FutureProvider.family<ComicInfo?, String>((
  ref,
  comicId,
) async {
  try {
    return await ref.read(apiClientProvider).getComicInfo(comicId);
  } catch (_) {
    return null;
  }
});

/// A chapter we trust enough to name: ComicInfo-sourced (the only kind /info
/// returns) and titled `"<Story>" <Series> #<n> …`.
class TrustedChapter {
  final int page;
  final String story;
  final String issue;
  const TrustedChapter(this.page, this.story, this.issue);
}

final _chapterTitle = RegExp(r'^"([^"]+)"\s+(.+?#\s*\d+[\w.]*)');

/// Chapters that parse cleanly, sorted by page. Empty when any chapter fails
/// to parse: a half-trusted list would mislabel the gaps.
@visibleForTesting
List<TrustedChapter> trustedChapters(List<ComicInfoChapter> chapters) {
  final out = <TrustedChapter>[];
  for (final c in chapters) {
    final m = _chapterTitle.firstMatch(c.title.trim());
    if (m == null) return const [];
    out.add(TrustedChapter(c.page, m.group(1)!.trim(), m.group(2)!.trim()));
  }
  return out..sort((a, b) => a.page.compareTo(b.page));
}

/// Progress strip cells: (count, 0-based current index).
@visibleForTesting
(int, int) progressCells({
  required int currentPage,
  required int totalPages,
  int? chapterIndex,
  int? chapterCount,
}) {
  if (chapterIndex != null && chapterCount != null && chapterCount <= 40) {
    return (chapterCount, chapterIndex);
  }
  if (totalPages <= 40) {
    return (totalPages, currentPage.clamp(0, totalPages - 1));
  }
  const buckets = 30;
  final cur = ((currentPage + 1) / totalPages * buckets).ceil().clamp(
    1,
    buckets,
  );
  return (buckets, cur - 1);
}

@visibleForTesting
String timeLeftLabel(int pagesLeft) {
  final minutes = (pagesLeft * kMinutesPerPage).ceil();
  return minutes < 90 ? '$minutes MIN' : '${(minutes / 60).round()} HR';
}

String _thousands(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// Bundled logo for a ComicInfo publisher name, or null (text stamp).
@visibleForTesting
String? publisherLogo(String publisher) {
  final s = publisher.toLowerCase();
  if (s.contains('marvel')) return 'marvel';
  if (s == 'dc' || s.startsWith('dc ')) return 'dc';
  if (s.startsWith('image')) return 'image';
  if (s.contains('dark horse')) return 'darkhorse';
  if (s.startsWith('idw')) return 'idw';
  return null;
}

const _months = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];
const _captionYellow = Color(0xFFFFD23F);
const _captionInk = Color(0xFF111111);
const _border = 2.0;
const _gutter = 8.0;

/// "Continue reading" hero for the Read tab, laid out as a comic page: the
/// whole cover in a tall panel, a yellow caption box for the title, a strip
/// of tiny pages for progress and an accent button panel. The whole card is
/// the tap target. Spec: docs/superpowers/specs/2026-10-21-read-hero-panel-page-design.md
class ResumeHeroCard extends ConsumerWidget {
  final ReadingProgress progress;
  final String serverUrl;
  final VoidCallback onTap;

  const ResumeHeroCard({
    super.key,
    required this.progress,
    required this.serverUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comic = ComicTokens.watch(ref, context, AppTheme.accent);
    final scheme = context.scheme;
    final tablet = LayoutBreakpoint.isTablet(context);
    final info = ref.watch(heroComicInfoProvider(progress.comicId)).value;

    final path = comicIdToPath(progress.comicId);
    final fileName = stripComicExtension(
      path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? path,
    );
    final series = info?.series?.trim() ?? '';
    final number = info?.number?.trim() ?? '';
    final title = series.isNotEmpty && number.isNotEmpty
        ? '$series #$number'
        : fileName;

    final page = progress.currentPage;
    final total = math.max(progress.totalPages, 1);
    final chapters = trustedChapters(info?.chapters ?? const []);
    final chIdx = chapters.isEmpty
        ? null
        : math.max(0, chapters.lastIndexWhere((c) => c.page <= page));
    final chapter = chIdx == null ? null : chapters[chIdx];

    final story = info?.title.trim() ?? '';
    final subtitle = chapter != null
        ? 'Now in ${chapter.issue}'
        : (story.isNotEmpty && story != title ? story : null);
    final summary = tablet ? info?.summary?.trim() : null;
    final writer = info?.writer?.trim() ?? '';
    final artist = info?.penciller?.trim() ?? '';
    final sparse =
        tablet &&
        (summary == null || summary.isEmpty) &&
        writer.isEmpty &&
        artist.isEmpty;
    final read = progress.updatedAt?.toLocal();
    final facts = [
      '${_thousands(total)} PAGES',
      if (read != null) 'LAST READ ${_months[read.month - 1]} ${read.day}',
    ].join(' · ');

    final String lead;
    if (page == 0) {
      lead = tablet ? 'OUR STORY BEGINS…' : 'IT BEGINS…';
    } else if (!tablet) {
      lead = 'MEANWHILE…';
    } else if (chapter != null) {
      lead = 'MEANWHILE, IN “${chapter.story.toUpperCase()}”…';
    } else {
      lead = 'MEANWHILE, ON PAGE ${page + 1}…';
    }

    final left = timeLeftLabel((total - page - 1).clamp(0, total));
    final (String lblMain, String lblSide) = chapter != null
        ? (tablet
              ? (
                  'CH ${chIdx! + 1} OF ${chapters.length}',
                  'P.${page + 1} · $left LEFT',
                )
              : ('CH ${chIdx! + 1}/${chapters.length}', left))
        : (tablet
              ? ('PAGE ${page + 1} OF ${_thousands(total)}', '$left LEFT')
              : ('${page + 1}/${_thousands(total)}', left));

    final (cellCount, cellCur) = progressCells(
      currentPage: page,
      totalPages: total,
      chapterIndex: chIdx,
      chapterCount: chapters.isEmpty ? null : chapters.length,
    );

    final ink = scheme.ink;
    final panelFill = scheme.dark ? scheme.bg : Colors.white;
    final accent = AppTheme.accent;
    final onAccent = Scheme.onAccent(accent);

    Widget panel(Widget child, {Color? fill}) => Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: fill ?? panelFill,
        border: Border.all(color: ink, width: _border),
      ),
      child: child,
    );

    final cover = panel(
      CoverAnchor(
        comicId: progress.comicId,
        imageUrl: '$serverUrl/comics/${progress.comicId}/pages/0',
        radius: 0,
        child: CachedNetworkImage(
          // Full-res page 0: /cover is a 300px thumbnail.
          imageUrl: '$serverUrl/comics/${progress.comicId}/pages/0',
          httpHeaders: imageHeadersOf(context, '$serverUrl/comics/${progress.comicId}/pages/0'),
          memCacheWidth: 1200,
          fit: BoxFit.contain,
          placeholder: (_, _) => const SizedBox.expand(),
          errorWidget: (_, _, _) => const SizedBox.expand(),
        ),
      ),
      fill: scheme.dark ? Colors.black : _captionInk,
    );

    final publisher = info?.publisher?.trim() ?? '';
    final logoKey = publisherLogo(publisher);
    final Widget? logo = !tablet || publisher.isEmpty
        ? null
        : logoKey != null
        ? ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96, maxHeight: 40),
            child: Image.asset(
              'assets/publishers/$logoKey.png',
              fit: BoxFit.contain,
              // Dark Horse's wordmark is white-on-transparent.
              color: logoKey == 'darkhorse' ? _captionInk : null,
              colorBlendMode: BlendMode.srcIn,
              semanticLabel: publisher,
            ),
          )
        : Container(
            constraints: const BoxConstraints(maxWidth: 140),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: _captionInk, width: _border),
            ),
            child: Text(
              publisher.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.displayTextStyle(
                comic,
                fontSize: 13,
              ).copyWith(color: _captionInk),
            ),
          );
    final logoGap = logo == null ? 0.0 : (logoKey != null ? 108.0 : 152.0);

    final titleSize = tablet
        ? (title.length <= 18
              ? 52.0
              : title.length <= 24
              ? 42.0
              : 36.0)
        : (title.length <= 14
              ? 26.0
              : title.length <= 22
              ? 21.0
              : 18.0);

    final caption = panel(
      Padding(
        padding: tablet
            ? const EdgeInsets.fromLTRB(18, 14, 18, 14)
            : const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lead,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.displayTextStyle(
                    comic,
                    fontSize: tablet ? 20 : 15,
                  ).copyWith(color: _captionInk),
                ),
                const SizedBox(height: 4),
                if (sparse)
                  // Nothing but the pages line to show: the title grows to fill
                  // the box instead of leaving dead yellow.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final avail = c.maxHeight - (subtitle != null ? 48 : 0);
                        var size = titleSize;
                        for (final s in [96.0, 84.0, 72.0, 64.0, 56.0]) {
                          if (s <= titleSize) break;
                          final tp = TextPainter(
                            text: TextSpan(
                              text: title,
                              style: AppTheme.displayTextStyle(
                                comic,
                                fontSize: s,
                              ).copyWith(height: 0.95),
                            ),
                            maxLines: 3,
                            textDirection: TextDirection.ltr,
                            textScaler: MediaQuery.textScalerOf(context),
                          )..layout(maxWidth: c.maxWidth);
                          final fits =
                              !tp.didExceedMaxLines && tp.height <= avail;
                          tp.dispose();
                          if (fits) {
                            size = s;
                            break;
                          }
                        }
                        return Text(
                          title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.displayTextStyle(
                            comic,
                            fontSize: size,
                          ).copyWith(color: _captionInk, height: 0.95),
                        );
                      },
                    ),
                  )
                else
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.displayTextStyle(
                      comic,
                      fontSize: titleSize,
                    ).copyWith(color: _captionInk, height: 0.95),
                  ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      subtitle,
                      maxLines: tablet ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: tablet ? 14 : 12,
                        fontWeight: FontWeight.w600,
                        color: _captionInk,
                      ),
                    ),
                  ),
                if (summary != null && summary.isNotEmpty) ...[
                  // Pinned to the bottom; drops lines (max 4) when a long title
                  // leaves less room.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final lines = math.min(
                          4,
                          ((c.maxHeight - 14) / (14 * 1.45)).floor(),
                        );
                        if (lines < 1) return const SizedBox.shrink();
                        return Padding(
                          padding: EdgeInsets.only(right: logoGap),
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              summary,
                              maxLines: lines,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                                fontStyle: FontStyle.italic,
                                color: _captionInk,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ] else if (sparse) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.only(right: logoGap),
                    child: Text(
                      facts,
                      maxLines: 1,
                      style: AppTheme.monoCaption.copyWith(
                        color: _captionInk,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ] else if (tablet) ...[
                  // No summary: credits + facts pinned to the bottom instead of
                  // dead yellow.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        if (c.maxHeight < 64) return const SizedBox.shrink();
                        final credits = <Widget>[
                          for (final (role, name) in [
                            ('WRITER', writer),
                            ('ART', artist),
                          ])
                            if (name.isNotEmpty)
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '$role  ',
                                      style: AppTheme.displayTextStyle(
                                        comic,
                                        fontSize: 15,
                                      ).copyWith(color: _captionInk),
                                    ),
                                    TextSpan(
                                      text: name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: _captionInk,
                                      ),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        ];
                        return Padding(
                          padding: EdgeInsets.only(right: logoGap),
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ...credits,
                                if (credits.isNotEmpty)
                                  const SizedBox(height: 6),
                                Text(
                                  facts,
                                  maxLines: 1,
                                  style: AppTheme.monoCaption.copyWith(
                                    color: _captionInk,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
            if (logo != null) Positioned(right: 0, bottom: 0, child: logo),
          ],
        ),
      ),
      fill: _captionYellow,
    );

    // ponytail: phone uses ≥10 columns (spec says 4 rows); 4 rows of fat
    // cells overflowed the half-width column at 390pt.
    final cols = tablet ? cellCount : math.max((cellCount / 4).ceil(), 10);
    const cellGap = 3.0;
    Widget cell(int i) {
      final isNow = i == cellCur;
      final box = AspectRatio(
        aspectRatio: 2 / 3,
        child: Container(
          decoration: BoxDecoration(
            color: isNow ? accent : (i < cellCur ? ink : panelFill),
            border: Border.all(color: ink, width: 1.5),
            boxShadow: isNow && comic.hardShadow
                ? [BoxShadow(color: ink, offset: const Offset(2, 2))]
                : null,
          ),
        ),
      );
      if (!isNow) return box;
      return Transform.rotate(
        angle: -4 * math.pi / 180,
        child: Transform.scale(scale: 1.3, child: box),
      );
    }

    final rows = <Widget>[];
    for (var start = 0; start < cellCount; start += cols) {
      rows.add(
        Row(
          children: [
            for (var c = 0; c < cols; c++) ...[
              if (c > 0) SizedBox(width: cellGap),
              Expanded(
                child: start + c < cellCount
                    ? cell(start + c)
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }

    final strip = panel(
      Stack(
        children: [
          if (comic.benDay)
            HalftoneOverlay(
              color: accent,
              opacity: scheme.dark ? 0.38 : 0.18,
              dotSpacing: 7,
              dotRadius: 1.2,
            ),
          Padding(
            padding: tablet
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        lblMain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.displayTextStyle(
                          comic,
                          fontSize: tablet ? 18 : 16,
                        ).copyWith(color: scheme.tx),
                      ),
                    ),
                    Text(
                      lblSide,
                      style: AppTheme.displayTextStyle(
                        comic,
                        fontSize: tablet ? 18 : 16,
                      ).copyWith(color: scheme.tx.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (var r = 0; r < rows.length; r++) ...[
                  if (r > 0) SizedBox(height: cellGap),
                  rows[r],
                ],
              ],
            ),
          ),
        ],
      ),
    );

    final button = panel(
      Padding(
        padding: tablet
            ? const EdgeInsets.symmetric(horizontal: 18, vertical: 10)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                page == 0 ? 'START READING' : 'TURN THE PAGE',
                style: AppTheme.displayTextStyle(
                  comic,
                  fontSize: tablet ? 34 : 26,
                ).copyWith(color: onAccent),
              ),
            ),
            Text(
              '→',
              style: TextStyle(
                fontSize: tablet ? 40 : 30,
                height: 1,
                color: onAccent,
              ),
            ),
          ],
        ),
      ),
      fill: accent,
    );

    final Widget body;
    if (tablet) {
      // Cover column is 280 wide; ~2:3 cover → ~430 tall.
      body = SizedBox(
        height: 430,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 280, child: cover),
            const SizedBox(width: _gutter),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: caption),
                  const SizedBox(height: _gutter),
                  strip,
                  const SizedBox(height: _gutter),
                  button,
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      body = LayoutBuilder(
        builder: (context, c) {
          final colW = (c.maxWidth - _gutter) / 2;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: colW * 1.5,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: cover),
                    const SizedBox(width: _gutter),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: caption),
                          const SizedBox(height: _gutter),
                          strip,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: _gutter),
              button,
            ],
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Semantics(
        button: true,
        label:
            '${page == 0 ? 'Start' : 'Resume'} $title, page ${page + 1} of $total',
        excludeSemantics: true,
        child: GestureDetector(onTap: onTap, child: body),
      ),
    );
  }
}
