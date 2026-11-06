import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../providers/accent_provider.dart';
import '../providers/mirror_provider.dart';
import '../providers/source_provider.dart';
import '../services/mirror/sync_progress.dart';
import 'shimmer_box.dart';

/// No series progress for this long: the card says "Still working".
const syncSlowAfter = Duration(seconds: 10);

/// A background sync shorter than this never shows "Updating", so the 60s
/// periodic sync doesn't blink the pill every minute.
const _updatingDelay = Duration(seconds: 1);

/// Rounded accent bar; indeterminate when [value] is null, static under
/// Reduce Motion.
class SyncBar extends ConsumerWidget {
  final double? value;
  final double height;
  const SyncBar({super.key, this.value, this.height = 4});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    final still =
        value == null && (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LinearProgressIndicator(
        value: still ? 1 : value,
        minHeight: height,
        backgroundColor: context.scheme.s3,
        color: still ? accent.withValues(alpha: 0.4) : accent,
      ),
    );
  }
}

/// The centered sync/scan card over dimmed placeholders.
class SyncCard extends StatelessWidget {
  final String title;
  final String line;
  final String? footer;

  /// Hidden when [showBar] is false; indeterminate when null.
  final double? value;
  final bool showBar;
  final VoidCallback? onRetry;

  const SyncCard({
    super.key,
    required this.title,
    required this.line,
    this.footer,
    this.value,
    this.showBar = true,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Stack(
      children: [
        Positioned.fill(
          child: ExcludeSemantics(
            child: Opacity(opacity: 0.35, child: _Placeholders()),
          ),
        ),
        Center(
          child: Semantics(
            container: true,
            label: '$title. $line',
            child: Container(
              width: 300,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: s.s1,
                borderRadius: BorderRadius.circular(AppTheme.r16),
                border: Border.all(color: s.borderFaint, width: 0.5),
              ),
              child: ExcludeSemantics(
                excluding: onRetry == null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: s.tx,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(line, style: TextStyle(color: s.t2, fontSize: 13)),
                    if (showBar) ...[
                      const SizedBox(height: 14),
                      SyncBar(value: value),
                    ],
                    if (footer != null) ...[
                      const SizedBox(height: 12),
                      Text(footer!,
                          style: TextStyle(color: s.t3, fontSize: 12)),
                    ],
                    if (onRetry != null) ...[
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                            onPressed: onRetry, child: const Text('Retry')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Placeholders extends StatelessWidget {
  @override
  Widget build(BuildContext context) => GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        crossAxisCount: MediaQuery.sizeOf(context).width >= 768 ? 5 : 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        children: [
          for (var i = 0; i < 15; i++) const ShimmerBox(radius: AppTheme.r12),
        ],
      );
}

/// The empty Library's / Read tab's stand-in while the first sync of a source
/// runs, or after it failed.
class FirstSyncCard extends ConsumerStatefulWidget {
  const FirstSyncCard({super.key});

  static bool shows(SyncProgress p) =>
      p.running || p.stage == SyncStage.failed;

  @override
  ConsumerState<FirstSyncCard> createState() => _FirstSyncCardState();
}

class _FirstSyncCardState extends ConsumerState<FirstSyncCard> {
  Timer? _slowTimer;

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  Future<void> _retry() async {
    try {
      await ref.read(syncEngineProvider)?.sync(force: true);
    } catch (_) {
      // The card shows the failure; never raw error text.
    }
    if (mounted) unawaited(ref.read(coverSyncerProvider)?.syncCovers());
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(syncProgressProvider);
    final name = ref.watch(activeSourceProvider.select((s) => s.name));
    final total = p.seriesTotal;

    if (p.stage == SyncStage.failed) {
      return SyncCard(
        title: "Couldn't reach $name",
        line: "Check that the server is running and you're online.",
        showBar: false,
        onRetry: _retry,
      );
    }

    final since = clock.now().difference(p.lastProgressAt ?? clock.now());
    final slow = since >= syncSlowAfter;
    _slowTimer?.cancel();
    if (!slow && p.running) {
      _slowTimer = Timer(syncSlowAfter - since, () {
        if (mounted) setState(() {});
      });
    }
    final count = total == null ? null : '${p.seriesDone} of $total series';
    final value = total == null || total == 0 ? null : p.seriesDone / total;
    if (slow) {
      return SyncCard(
        title: 'Still working',
        line: count == null
            ? 'Big libraries take a minute.'
            : '$count. Big libraries take a minute.',
        value: value,
      );
    }
    return SyncCard(
      title: 'Syncing with $name',
      line: count == null
          ? (p.stage == SyncStage.pushing ? 'Connecting…' : 'Reading library…')
          : p.coversDone > 0
              ? '$count · ${p.coversDone} covers'
              : count,
      footer: 'Your comics appear as they arrive.',
      value: value,
    );
  }
}

/// Header sync status for a screen with content: [strip] false is the pill
/// beside the title, true the 2px bar under it. First sync: "Syncing · 12/40"
/// and a determinate strip; later syncs: "Updating" and an indeterminate bar.
/// Both fade out when the sync ends.
class SyncIndicator extends ConsumerStatefulWidget {
  final bool strip;
  const SyncIndicator({super.key}) : strip = false;
  const SyncIndicator.strip({super.key}) : strip = true;

  @override
  ConsumerState<SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState extends ConsumerState<SyncIndicator> {
  Timer? _delay;

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(syncProgressProvider);
    final s = context.scheme;
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    var show = p.running;
    if (show && !p.initial) {
      final age = clock.now().difference(p.startedAt ?? clock.now());
      show = age >= _updatingDelay;
      _delay?.cancel();
      if (!show) {
        _delay = Timer(_updatingDelay - age, () {
          if (mounted) setState(() {});
        });
      }
    }
    // Never synced: take no room in the header.
    if (p.stage == SyncStage.idle) {
      return SizedBox(height: widget.strip ? 2 : 0);
    }
    final total = p.stage == SyncStage.covers ? p.coversTotal : p.seriesTotal;
    final done = p.stage == SyncStage.covers ? p.coversDone : p.seriesDone;

    final Widget child;
    if (widget.strip) {
      child = SyncBar(
        height: 2,
        // Static once hidden: no ticker running behind opacity 0.
        value: !show
            ? 1
            : p.initial && total != null && total > 0
                ? done / total
                : null,
      );
    } else {
      final label = p.initial
          ? (p.seriesTotal == null
              ? 'Syncing'
              : 'Syncing · ${p.seriesDone}/${p.seriesTotal}')
          : 'Updating';
      child = Semantics(
        label: p.initial && p.seriesTotal != null
            ? 'Syncing, ${p.seriesDone} of ${p.seriesTotal} series'
            : label,
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: s.s2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: s.borderFaint, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!p.initial) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: TextStyle(color: s.t2, fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return IgnorePointer(
      ignoring: !show,
      child: ExcludeSemantics(
        excluding: !show,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: child,
        ),
      ),
    );
  }
}
