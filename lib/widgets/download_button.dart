// lib/widgets/download_button.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/download_item.dart';
import '../providers/download_provider.dart';
import '../services/download_manager.dart';

class DownloadButton extends ConsumerWidget {
  final String comicId;
  final String sourceId;
  final VoidCallback onTap;

  final Color accent;

  const DownloadButton({
    super.key,
    required this.comicId,
    required this.sourceId,
    required this.onTap,
    this.accent = AppTheme.accent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(downloadStateProvider);
    final managerState = stateAsync.value ?? const DownloadManagerState();

    // Check if this comic is in the download state
    final item = managerState.all
        .where((i) => i.comicId == comicId && i.sourceId == sourceId)
        .firstOrNull;

    Widget icon;
    VoidCallback? tapHandler;

    if (item == null) {
      icon = Icon(Icons.download_rounded, size: 20, color: context.scheme.t2);
      tapHandler = () {
        HapticFeedback.mediumImpact();
        onTap();
      };
    } else {
      switch (item.status) {
        case DownloadStatus.queued:
          icon = Icon(Icons.hourglass_empty_rounded, size: 20, color: context.scheme.t3);
        case DownloadStatus.downloading:
          icon = SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              value: item.progress,
              strokeWidth: 2.5,
              color: accent,
              backgroundColor: context.scheme.s2,
            ),
          );
        case DownloadStatus.completed:
          icon = const Icon(Icons.check_circle_rounded, size: 20, color: AppTheme.green);
        case DownloadStatus.failed:
          icon = Icon(Icons.error_outline_rounded, size: 20, color: Colors.red[400]);
          tapHandler = () {
            HapticFeedback.mediumImpact();
            onTap();
          };
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: tapHandler,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(child: icon),
      ),
    );
  }
}
