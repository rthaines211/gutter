// lib/widgets/source_switcher.dart
import 'package:flutter/material.dart';
import 'pro_sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/server_source.dart';
import '../providers/source_provider.dart';
import 'source_config_sheet.dart';

class SourceSwitcher extends ConsumerWidget {
  /// If true, only shows the icon (for collapsed sidebar).
  final bool compact;
  final Color accent;

  const SourceSwitcher({super.key, this.compact = false, this.accent = AppTheme.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourceListProvider);
    final active = ref.watch(activeSourceProvider);

    // Don't show switcher if only one source
    if (sources.length <= 1 && compact) return const SizedBox.shrink();

    if (compact) {
      return GestureDetector(
        onTap: () => _showSourceMenu(context, ref, sources, active),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: context.scheme.s2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: context.scheme.borderFaint,
              width: 0.5,
            ),
          ),
          child: Center(
            child: Icon(
              active.type == SourceType.opds
                  ? Icons.rss_feed_rounded
                  : Icons.dns_rounded,
              size: 16,
              color: context.scheme.t2,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showSourceMenu(context, ref, sources, active),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: context.scheme.s2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: context.scheme.borderFaint,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active.type == SourceType.opds
                  ? Icons.rss_feed_rounded
                  : Icons.dns_rounded,
              size: 14,
              color: accent,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                active.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.scheme.t2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.unfold_more, size: 14, color: context.scheme.t3),
          ],
        ),
      ),
    );
  }

  void _showSourceMenu(
    BuildContext context,
    WidgetRef ref,
    List<ServerSource> sources,
    ServerSource active,
  ) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: context.scheme.s2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: ctx.scheme.hairStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Sources',
                style: TextStyle(
                    color: ctx.scheme.tx,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...sources.map((s) => ListTile(
                  leading: Icon(
                    s.type == SourceType.opds
                        ? Icons.rss_feed_rounded
                        : Icons.dns_rounded,
                    color: s.id == active.id
                        ? accent
                        : ctx.scheme.t2,
                  ),
                  title: Text(s.name,
                      style: TextStyle(
                        color: ctx.scheme.tx,
                        fontWeight: s.id == active.id
                            ? FontWeight.w700
                            : FontWeight.w500,
                      )),
                  trailing: s.id == active.id
                      ? Icon(Icons.check, size: 18, color: accent)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    HapticFeedback.selectionClick();
                    ref.read(activeSourceIdProvider.notifier).select(s.id);
                  },
                  onLongPress: s.isDefault
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _editSource(context, ref, s);
                        },
                )),
            Divider(color: ctx.scheme.s1),
            ListTile(
              leading: Icon(Icons.add, color: accent),
              title: Text('Add Server',
                  style: TextStyle(color: accent)),
              onTap: () {
                Navigator.pop(ctx);
                if (!requirePro(context, ref,
                    reason: 'More than one server is part of Pro.')) {
                  return;
                }
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const SourceConfigSheet(),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _editSource(BuildContext context, WidgetRef ref, ServerSource source) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SourceConfigSheet(existing: source),
    );
  }
}
