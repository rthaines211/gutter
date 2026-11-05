// lib/widgets/rename_preview_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../config/string_utils.dart';
import '../models/template_rename_result.dart';
import '../providers/mirror_provider.dart';
import '../providers/providers.dart';
import 'shimmer_box.dart';

/// Displays a dry-run preview of the naming-template renames for a series,
/// with an Apply button that fires the real rename.
class RenamePreviewSheet extends ConsumerStatefulWidget {
  final String seriesId;
  final Color accent;

  const RenamePreviewSheet({
    super.key,
    required this.seriesId,
    required this.accent,
  });

  @override
  ConsumerState<RenamePreviewSheet> createState() => _RenamePreviewSheetState();
}

class _RenamePreviewSheetState extends ConsumerState<RenamePreviewSheet> {
  late Future<List<TemplateRenameResult>> _previewFuture;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _previewFuture = ref
        .read(apiClientProvider)
        .applyTemplate(widget.seriesId, dryRun: true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<TemplateRenameResult>>(
        future: _previewFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildShimmer();
          }
          if (snapshot.hasError) {
            return _buildError(snapshot.error.toString());
          }
          final results = snapshot.data ?? [];
          return _buildLoaded(context, results);
        },
      ),
    );
  }

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShimmerBox(width: 180, height: 18),
          const SizedBox(height: 16),
          for (int i = 0; i < 4; i++) ...[
            const ShimmerBox(width: double.infinity, height: 44),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: context.scheme.t2, size: 36),
          const SizedBox(height: 12),
          Text('Failed to load preview: $message',
              style: TextStyle(color: context.scheme.t2),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Dismiss',
                style: TextStyle(color: context.scheme.t2)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoaded(BuildContext context, List<TemplateRenameResult> results) {
    // A "changed" row is one where newName differs from oldName and is non-empty.
    // An "applicable" row is changed AND not a conflict.
    final changedCount = results.where((r) =>
        r.newName.isNotEmpty && r.newName != r.oldName && !r.conflict).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 16),
          decoration: BoxDecoration(
            color: context.scheme.hairStrong,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // Title
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Template Preview',
              style: TextStyle(
                color: context.scheme.tx,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),

        // List of rows
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.45,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: results.length,
            itemBuilder: (context, index) =>
                _buildRow(context, results[index]),
          ),
        ),

        const SizedBox(height: 8),

        // Footer actions
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: _applying
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: changedCount > 0
                              ? widget.accent
                              : context.scheme.s2,
                          foregroundColor: Scheme.onAccent(widget.accent),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.r14)),
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        onPressed: changedCount > 0
                            ? () => _applyRenames(context)
                            : null,
                        child: Text(
                          'Apply $changedCount ${changedCount == 1 ? 'rename' : 'renames'}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel',
                    style: TextStyle(color: context.scheme.t2)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, TemplateRenameResult r) {
    final unchanged =
        r.newName.isEmpty || r.newName == r.oldName;
    final errorColor = Theme.of(context).colorScheme.error;

    Color rowColor;
    if (r.conflict) {
      rowColor = errorColor.withValues(alpha: 0.12);
    } else if (unchanged) {
      rowColor = Colors.transparent;
    } else {
      rowColor = Colors.transparent;
    }

    final textOpacity = unchanged ? 0.4 : 1.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: rowColor,
        borderRadius: BorderRadius.circular(10),
        border: r.conflict
            ? Border.all(color: errorColor.withValues(alpha: 0.4), width: 0.5)
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(
                  opacity: textOpacity,
                  child: Text(
                    stripComicExtension(r.oldName),
                    style: TextStyle(
                        color: context.scheme.t2, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!unchanged) ...[
                  const SizedBox(height: 2),
                  Text(
                    stripComicExtension(r.newName),
                    style: TextStyle(
                        color: r.conflict ? errorColor : context.scheme.tx,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (r.conflict) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: errorColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppTheme.pill),
              ),
              child: Text(
                'conflict',
                style: TextStyle(
                    color: errorColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _applyRenames(BuildContext context) async {
    // Capture messenger and navigator before any async gap.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _applying = true);
    try {
      final client = ref.read(apiClientProvider);
      final results =
          await client.applyTemplate(widget.seriesId, dryRun: false);

      final appliedCount = results.where((r) => r.applied).length;
      final skipped = results.where((r) => r.conflict).length;

      if (mounted) {
        final engine = ref.read(syncEngineProvider);
        if (engine != null) {
          await engine.sync().catchError((_) {});
        }
      }

      if (!context.mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            skipped > 0
                ? 'Renamed $appliedCount files, skipped $skipped'
                : 'Renamed $appliedCount files',
            style: TextStyle(color: context.scheme.tx),
          ),
          backgroundColor: context.scheme.s2,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _applying = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Apply failed: $e',
                style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
