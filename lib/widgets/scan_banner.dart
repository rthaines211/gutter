import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/scheme.dart';
import '../providers/mirror_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/review_provider.dart';
import '../providers/scan_status_provider.dart';

class ScanBanner extends ConsumerStatefulWidget {
  const ScanBanner({super.key});

  @override
  ConsumerState<ScanBanner> createState() => _ScanBannerState();
}

class _ScanBannerState extends ConsumerState<ScanBanner> {
  Timer? _autoDismiss;
  int _reviewCount = 0;

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  /// The scan/pipeline may have queued matches for review: reload, and keep
  /// the banner up with a link when there are any; else auto-dismiss.
  Future<void> _onDone() async {
    _autoDismiss?.cancel();
    _reviewCount = 0; // never carry a stale count over from a previous scan
    var n = 0;
    try {
      ref.invalidate(reviewQueueProvider);
      n = (await ref.read(reviewQueueProvider.future)).items.length;
    } catch (e) {
      debugPrint('ScanBanner: review load failed: $e'); // plain auto-dismiss
    }
    if (!mounted) return;
    if (n > 0) {
      setState(() => _reviewCount = n);
      return;
    }
    setState(() {});
    _autoDismiss = Timer(const Duration(seconds: 3), () {
      ref.read(scanStatusProvider.notifier).dismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(scanStatusProvider);

    ref.listen(scanStatusProvider, (prev, next) {
      if (prev?.phase != ScanPhase.done && next.phase == ScanPhase.done) {
        HapticFeedback.mediumImpact();
        // Pull the rescan results into the local mirror; the mirror-backed
        // library stream updates on its own.
        unawaited(
          ref.read(syncEngineProvider)?.sync().catchError((_) {}),
        );
        unawaited(_onDone());
      }
    });

    if (scanState.phase == ScanPhase.idle) {
      return const SizedBox.shrink();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _buildBanner(context, scanState),
    );
  }

  Widget _buildBanner(BuildContext context, ScanStatusState scanState) {
    final Color bg;
    final Widget content;

    switch (scanState.phase) {
      case ScanPhase.scanning:
        bg = context.scheme.s2;
        final status = scanState.status;
        final label = !status.isScanning && status.pipelineRunning
            ? 'Matching new comics...'
            : status.total > 0
                ? 'Scanning library... ${status.scanned} / ${status.total}'
                : 'Scanning library...';
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.scheme.t2,
                  ),
                ),
                const SizedBox(width: 12),
                Text(label, style: TextStyle(color: context.scheme.tx, fontSize: 13)),
              ],
            ),
            if (status.total > 0) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: status.progress,
                  backgroundColor: context.scheme.hair,
                  color: context.scheme.t3,
                  minHeight: 3,
                ),
              ),
            ],
          ],
        );

      case ScanPhase.done:
        bg = context.scheme.s2;
        final status = scanState.status;
        final parts = <String>[];
        if (status.newCount > 0) parts.add('${status.newCount} new series');
        if (status.removedCount > 0) parts.add('${status.removedCount} removed');
        final detail = parts.isEmpty ? 'no changes found' : parts.join(', ');
        content = Row(
          children: [
            Icon(Icons.check_circle_outline, color: context.scheme.t2, size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Scan complete — $detail',
                style: TextStyle(color: context.scheme.tx, fontSize: 13),
              ),
            ),
            if (_reviewCount > 0) ...[
              Text('$_reviewCount need review',
                  style: TextStyle(color: context.scheme.t2, fontSize: 13)),
              TextButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  ref
                      .read(navigationProvider.notifier)
                      .go(NavDestination.review);
                  ref.read(scanStatusProvider.notifier).dismiss();
                },
                child: const Text('Review'),
              ),
            ],
          ],
        );

      case ScanPhase.error:
        bg = Colors.red.shade800;
        content = GestureDetector(
          onTap: () => ref.read(scanStatusProvider.notifier).dismiss(),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white70, size: 16),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  scanState.errorMessage ?? 'Scan failed',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );

      case ScanPhase.idle:
        return const SizedBox.shrink();
    }

    return Container(
      key: ValueKey(scanState.phase),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: content,
    );
  }
}
