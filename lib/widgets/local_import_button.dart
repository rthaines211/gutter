import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/scheme.dart';
import '../providers/accent_provider.dart';
import '../config/app_theme.dart';
import '../providers/local_import_provider.dart';
import '../services/local_import.dart' show LocalImportError;

/// "Import comics" for the local source: picks files, imports them, and says
/// what happened to each. [compact] is the Library header's icon button.
class LocalImportButton extends ConsumerWidget {
  final bool compact;

  /// The one-step entry from onboarding and Servers: see
  /// [LocalImportNotifier.pickAndImport].
  final bool intoLocal;
  const LocalImportButton(
      {super.key, this.compact = false, this.intoLocal = false});

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.of(context);
    final List<ImportOutcome> outcomes;
    try {
      final navigator = Navigator.of(context);
      outcomes = await ref
          .read(localImportProvider.notifier)
          .pickAndImport(intoLocal: intoLocal);
      // From Servers (a pushed screen): back to the shell, on the Library.
      if (intoLocal && outcomes.isNotEmpty && navigator.mounted) {
        navigator.popUntil((r) => r.isFirst);
      }
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
        : intoLocal
            ? 'Import comics from Files'
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
    if (intoLocal) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(Icons.folder_open, color: accent),
        label: Text(label, style: TextStyle(color: accent)),
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

/// "Try a sample comic": imports the bundled Pepper&Carrot #1 into the local
/// source and opens the Library on it (see
/// [LocalImportNotifier.importSample]). Secondary to [LocalImportButton],
/// with the CC BY credit under it. Free, no Pro gate.
class SampleComicButton extends ConsumerWidget {
  const SampleComicButton({super.key});

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final outcomes =
        await ref.read(localImportProvider.notifier).importSample();
    if (outcomes.isNotEmpty && navigator.mounted) {
      navigator.popUntil((r) => r.isFirst);
    }
    final problem = outcomes.firstOrNull?.problem;
    if (problem != null && problem != importProblem(LocalImportError.alreadyImported)) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not add the sample comic.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(localImportProvider) != null;
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: busy ? null : () => _import(context, ref),
          child: Text('Try a sample comic', style: TextStyle(color: accent)),
        ),
        Text(sampleComicCredit,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: context.scheme.t2)),
      ],
    );
  }
}
