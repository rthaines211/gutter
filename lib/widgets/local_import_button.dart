import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/scheme.dart';
import '../providers/accent_provider.dart';
import '../config/app_theme.dart';
import '../providers/local_import_provider.dart';

/// "Import comics" for the local source: picks files, imports them, and says
/// what happened to each. [compact] is the Library header's icon button.
class LocalImportButton extends ConsumerWidget {
  final bool compact;
  const LocalImportButton({super.key, this.compact = false});

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.of(context);
    final List<ImportOutcome> outcomes;
    try {
      outcomes = await ref.read(localImportProvider.notifier).pickAndImport();
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not open the file picker.')));
      return;
    }
    if (outcomes.isEmpty) return;
    final failed = outcomes.where((o) => o.problem != null).toList();
    final ok = outcomes.length - failed.length;
    if (failed.isEmpty) {
      messenger.showSnackBar(SnackBar(
          content: Text('Imported $ok ${ok == 1 ? 'comic' : 'comics'}')));
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.scheme.s1,
        title: Text('Imported $ok of ${outcomes.length}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final f in failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${f.fileName}: ${f.problem}'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(localImportProvider);
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    final busy = progress != null;
    final label = busy
        ? 'Importing ${progress.done + 1 > progress.total ? progress.total : progress.done + 1} of ${progress.total}'
        : 'Import comics';
    final onPressed = busy ? null : () => _import(context, ref);
    if (compact) {
      return IconButton(
        tooltip: label,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: busy
            ? const SizedBox.square(
                dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.add, color: accent),
      );
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: accent),
      onPressed: onPressed,
      icon: const Icon(Icons.add),
      label: Text(label),
    );
  }
}
