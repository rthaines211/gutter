// lib/widgets/series_action_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/series.dart';
import '../providers/mirror_provider.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';
import 'metadata_edit_sheet.dart';
import 'rename_preview_sheet.dart';

/// Shows the long-press action sheet for an issue (mark read/unread, rename).
void showIssueActionSheet({
  required BuildContext context,
  required WidgetRef ref,
  required SeriesIssue issue,
  required String seriesId,
  required Color accent,
}) {
  HapticFeedback.mediumImpact();
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
          Text(issue.displayName,
              style: TextStyle(
                  color: ctx.scheme.tx,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          if (issue.status != 'completed')
            ListTile(
              leading: const Icon(Icons.check_circle, color: AppTheme.green),
              title: Text('Mark as Read',
                  style: TextStyle(color: ctx.scheme.tx)),
              onTap: () {
                Navigator.pop(ctx);
                markIssue(ref: ref, issue: issue, seriesId: seriesId, read: true);
              },
            ),
          if (issue.status != 'unread')
            ListTile(
              leading: Icon(Icons.remove_circle_outline,
                  color: ctx.scheme.t2),
              title: Text('Mark as Unread',
                  style: TextStyle(color: ctx.scheme.tx)),
              onTap: () {
                Navigator.pop(ctx);
                markIssue(ref: ref, issue: issue, seriesId: seriesId, read: false);
              },
            ),
          ListTile(
            leading: Icon(Icons.edit_outlined, color: ctx.scheme.tx),
            title: Text('Rename File',
                style: TextStyle(color: ctx.scheme.tx)),
            onTap: () {
              Navigator.pop(ctx);
              showRenameDialog(
                context: context,
                ref: ref,
                issue: issue,
                seriesId: seriesId,
                accent: accent,
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.edit_note, color: ctx.scheme.tx),
            title: Text('Edit Metadata',
                style: TextStyle(color: ctx.scheme.tx)),
            onTap: () {
              Navigator.pop(ctx);
              showMetadataEditSheet(
                context: context,
                ref: ref,
                issue: issue,
                seriesId: seriesId,
                accent: accent,
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Marks a single issue as read or unread.
Future<void> markIssue({
  required WidgetRef ref,
  required SeriesIssue issue,
  required String seriesId,
  required bool read,
}) async {
  final client = ref.read(apiClientProvider);
  try {
    if (read) {
      await client.batchUpdateProgress([
        {
          'comic_id': issue.id,
          'current_page': issue.totalPages ?? 1,
          'total_pages': issue.totalPages ?? 1,
        }
      ]);
    } else {
      await client.batchDeleteProgress([issue.id]);
    }
    HapticFeedback.mediumImpact();
    // Pull the server's view of the write into the local mirror; the
    // mirror-backed library/series streams update on their own.
    final engine = ref.read(syncEngineProvider);
    if (engine != null) await engine.sync();
  } catch (_) {}
}

/// Marks all issues in a series as read.
Future<void> markSeriesRead({
  required WidgetRef ref,
  required SeriesDetail detail,
}) async {
  HapticFeedback.mediumImpact();
  final client = ref.read(apiClientProvider);
  try {
    final updates = detail.issues
        .where((i) => i.status != 'completed')
        .map((i) => {
              'comic_id': i.id,
              'current_page': i.totalPages ?? 1,
              'total_pages': i.totalPages ?? 1,
            })
        .toList();
    if (updates.isNotEmpty) {
      await client.batchUpdateProgress(updates);
      final engine = ref.read(syncEngineProvider);
      if (engine != null) await engine.sync();
    }
  } catch (_) {}
}

/// Shows the rename dialog for a comic file.
void showRenameDialog({
  required BuildContext context,
  required WidgetRef ref,
  required SeriesIssue issue,
  required String seriesId,
  required Color accent,
}) {
  final ext = issue.name.contains('.')
      ? issue.name.substring(issue.name.lastIndexOf('.'))
      : '';
  final nameWithoutExt = ext.isNotEmpty
      ? issue.name.substring(0, issue.name.lastIndexOf('.'))
      : issue.name;

  final controller = TextEditingController(text: nameWithoutExt);
  String? errorText;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: ctx.scheme.s2,
        title: Text('Rename File',
            style: TextStyle(color: ctx.scheme.tx, fontSize: 17, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: ctx.scheme.tx),
              decoration: InputDecoration(
                suffixText: ext,
                suffixStyle: TextStyle(color: ctx.scheme.t2),
                errorText: errorText,
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: ctx.scheme.hairStrong),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: accent),
                ),
              ),
              onChanged: (value) {
                if (value.contains('/') || value.contains('\\')) {
                  setDialogState(() => errorText = 'Name cannot contain / or \\');
                } else if (errorText != null) {
                  setDialogState(() => errorText = null);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: ctx.scheme.t2)),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty || newName == nameWithoutExt) return;
              if (newName.contains('/') || newName.contains('\\')) return;

              Navigator.pop(ctx);

              try {
                final client = ref.read(apiClientProvider);
                final result = await client.renameComic(issue.id, newName);
                // Sync so the mirror picks up the renamed file. A sync
                // failure must not surface as a rename error.
                final engine = ref.read(syncEngineProvider);
                if (engine != null) {
                  await engine.sync().catchError((_) {});
                }

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Renamed to ${result['name']}',
                          style: TextStyle(color: context.scheme.tx)),
                      backgroundColor: context.scheme.s2,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } on ApiException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          e.statusCode == 409
                              ? 'A file with that name already exists'
                              : 'Rename failed: ${e.message}',
                          style: const TextStyle(color: Colors.white)),
                      backgroundColor: Colors.red.shade800,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Rename failed: $e',
                          style: const TextStyle(color: Colors.white)),
                      backgroundColor: Colors.red.shade800,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: Text('Save', style: TextStyle(color: accent)),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Series-level action sheet
// ---------------------------------------------------------------------------

/// Shows the overflow action sheet for a series (three tiles).
/// [onFolderRenamed] is called after a successful folder rename so the caller
/// can close any stale panel (e.g. iPad split-view SeriesDetailPanel).
void showSeriesActionSheet({
  required BuildContext context,
  required WidgetRef ref,
  required SeriesDetail detail,
  required String seriesId,
  required Color accent,
  VoidCallback? onFolderRenamed,
}) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet(
    context: context,
    backgroundColor: context.scheme.s2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    isScrollControlled: true,
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
          Text(detail.name,
              style: TextStyle(
                  color: ctx.scheme.tx,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          ListTile(
            leading: Icon(Icons.edit_note, color: ctx.scheme.tx),
            title: Text('Edit Metadata',
                style: TextStyle(color: ctx.scheme.tx)),
            onTap: () {
              Navigator.pop(ctx);
              showMetadataEditSheet(
                context: context,
                ref: ref,
                series: detail,
                seriesId: seriesId,
                accent: accent,
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.drive_file_rename_outline,
                color: ctx.scheme.tx),
            title: Text('Apply Naming Template…',
                style: TextStyle(color: ctx.scheme.tx)),
            onTap: () {
              Navigator.pop(ctx);
              showModalBottomSheet(
                context: context,
                backgroundColor: context.scheme.s2,
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(16)),
                ),
                isScrollControlled: true,
                builder: (_) => RenamePreviewSheet(
                  seriesId: seriesId,
                  accent: accent,
                ),
              );
            },
          ),
          ListTile(
            leading:
                Icon(Icons.folder_outlined, color: ctx.scheme.tx),
            title: Text('Rename Folder…',
                style: TextStyle(color: ctx.scheme.tx)),
            onTap: () {
              Navigator.pop(ctx);
              showRenameFolderDialog(
                context: context,
                ref: ref,
                seriesId: seriesId,
                seriesName: detail.name,
                accent: accent,
                onRenamed: onFolderRenamed,
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Folder rename dialog
// ---------------------------------------------------------------------------

/// Shows the rename-folder dialog for a series.
/// [onRenamed] is called after a successful rename so callers can close stale
/// panels (e.g. the iPad split-view SeriesDetailPanel). Guard with mounted
/// checks so that the full-screen route path doesn't break.
void showRenameFolderDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String seriesId,
  required String seriesName,
  required Color accent,
  VoidCallback? onRenamed,
}) {
  final controller = TextEditingController(text: seriesName);
  String? errorText;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: ctx.scheme.s2,
        title: Text('Rename Folder',
            style: TextStyle(
                color: ctx.scheme.tx,
                fontSize: 17,
                fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: ctx.scheme.tx),
              decoration: InputDecoration(
                errorText: errorText,
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: ctx.scheme.hairStrong),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: accent),
                ),
              ),
              onChanged: (value) {
                if (value.contains('/') || value.contains('\\')) {
                  setDialogState(
                      () => errorText = 'Name cannot contain / or \\');
                } else if (errorText != null) {
                  setDialogState(() => errorText = null);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: ctx.scheme.t2)),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty || newName == seriesName) return;
              if (newName.contains('/') || newName.contains('\\')) return;

              try {
                final client = ref.read(apiClientProvider);
                await client.renameSeriesFolder(seriesId, newName);

                // Sync so the mirror picks up the new folder. A sync failure
                // must not surface as a rename error.
                final engine = ref.read(syncEngineProvider);
                if (engine != null) {
                  await engine.sync().catchError((_) {});
                }

                // The series ID changed along with the folder name, so the
                // old detail panel/stream is now stale. Pop back to root.
                if (context.mounted) {
                  Navigator.pop(ctx);
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  // Clear stale iPad split-view panel if one is open.
                  try { onRenamed?.call(); } catch (_) {}
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Folder renamed',
                          style: TextStyle(color: context.scheme.tx)),
                      backgroundColor: context.scheme.s2,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } on ApiException catch (e) {
                if (e.statusCode == 409) {
                  // Keep dialog open, show inline error
                  setDialogState(() => errorText = 'A folder with that name already exists');
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Rename failed: ${e.message}',
                          style: const TextStyle(color: Colors.white)),
                      backgroundColor: Colors.red.shade800,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Rename failed: $e',
                          style: const TextStyle(color: Colors.white)),
                      backgroundColor: Colors.red.shade800,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: Text('Save', style: TextStyle(color: accent)),
          ),
        ],
      ),
    ),
  );
}
