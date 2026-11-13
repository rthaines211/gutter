import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/stats_summary.dart';
import 'longbox_mark.dart';

/// The image a reader shares from Stats: numbers only. No covers and no
/// series names, so it never shows what the person reads.
///
/// Always dark and always [size], whatever the app's scheme or text size.
class StatsShareCard extends StatelessWidget {
  /// Logical size. Captured at [pixelRatio] it gives a 1080x1350 PNG.
  static const size = Size(360, 450);
  static const pixelRatio = 3.0;

  final StatsSummary summary;
  final Color accent;
  const StatsShareCard({super.key, required this.summary, this.accent = AppTheme.accent});

  /// Nothing to show yet: the Stats screen hides the Share button.
  static bool isEmpty(StatsSummary s) => s.allTime.pagesRead == 0;

  @override
  Widget build(BuildContext context) {
    const s = Scheme.oledBlack;
    final streak = summary.streak.current;
    return MediaQuery.withNoTextScaling(
      child: SizedBox.fromSize(
        size: size,
        child: Material(
          color: s.bgRaised,
          textStyle: TextStyle(color: s.tx),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MY WEEK IN COMICS',
                    style: AppTheme.sectionHeader.copyWith(color: accent)),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('${summary.thisWeek.pagesRead}',
                      style: const TextStyle(
                          fontSize: 104, fontWeight: FontWeight.w800, letterSpacing: -4, height: 1)),
                ),
                Text('pages this week',
                    style: AppTheme.titleMedium.copyWith(color: s.t2)),
                const Spacer(),
                Row(
                  children: [
                    _tile(s, '$streak', 'day streak'),
                    const SizedBox(width: 10),
                    _tile(s, '${summary.allTime.issuesFinished}', 'issues finished'),
                    const SizedBox(width: 10),
                    _tile(s, '${summary.allTime.pagesRead}', 'pages all time'),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    LongboxMark(size: 26, accent: accent, background: const Color(0xFF1B1720), radius: 6),
                    const SizedBox(width: 8),
                    const Text('Gutter',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text('getgutter.app', style: AppTheme.monoLabel.copyWith(color: s.t3)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(Scheme s, String value, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: s.s1,
            borderRadius: BorderRadius.circular(AppTheme.r12),
            border: Border.all(color: s.hair),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, style: TextStyle(fontSize: 10, color: s.t3)),
              ),
            ],
          ),
        ),
      );
}

/// Paints [StatsShareCard] for one frame and returns it as PNG bytes.
Future<Uint8List> renderStatsCardPng(BuildContext context, StatsSummary summary, Color accent) async {
  final key = GlobalKey();
  // ponytail: painted off the left edge of the overlay for one frame, not in a
  // separate render tree. An overlay child paints wherever it is placed.
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -2 * StatsShareCard.size.width,
      top: 0,
      width: StatsShareCard.size.width,
      height: StatsShareCard.size.height,
      child: RepaintBoundary(key: key, child: StatsShareCard(summary: summary, accent: accent)),
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: StatsShareCard.pixelRatio);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    entry.remove();
  }
}

/// Shares the stats card as an image. [context] is the Share button's: the
/// iPad anchors the share sheet to its rect, and throws without one.
Future<void> shareStatsCard(BuildContext context, StatsSummary summary, Color accent) async {
  final box = context.findRenderObject()! as RenderBox;
  final origin = box.localToGlobal(Offset.zero) & box.size;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final png = await renderStatsCardPng(context, summary, accent);
    final file = File(p.join((await getTemporaryDirectory()).path, 'gutter-stats.png'));
    await file.writeAsBytes(png);
    await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')],
        text: 'Read with Gutter: https://apps.apple.com/us/app/gutter-comic-reader/id6831270255',
        sharePositionOrigin: origin);
  } catch (e) {
    debugPrint('share stats: $e');
    messenger?.showSnackBar(const SnackBar(content: Text("Couldn't share your stats.")));
  }
}
