// lib/widgets/series_action_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/series.dart';
import '../providers/cache_providers.dart';
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
          // Files and metadata live on the Gutter server; Komga edits its own.
          if (ref.read(isCustomSourceProvider)) ...[
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
          ],
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Reads a provider; both `ref.read` and `ProviderContainer.read` fit.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// One-tap read toggle for issue rows: writes the mirror first so the row
/// flips at once, shows Undo straight away (it restores an in-progress
/// page, not just "unread"), then pushes to the server in the background.
Future<void> toggleIssueRead(
    BuildContext context, WidgetRef ref, SeriesIssue issue) async {
  HapticFeedback.selectionClick();
  // The container outlives this row (lazy lists recycle it; the reader's
  // series panel may close), so Undo reads through it, not through [ref].
  final read = ProviderScope.containerOf(context, listen: false).read;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final wasRead = issue.status == 'completed';
  final label = issue.number == null ? issue.displayName : '#${issue.number}';
  // Unread drops the progress row, bookmarks with it, and Undo can't bring
  // those back: keep that behind the long-press sheet.
  if (wasRead &&
      (await read(mirrorDbProvider).bookmarksFor(issue.id)).isNotEmpty) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('$label has bookmarks. Long-press to mark it unread.')));
    return;
  }
  final prevPage = issue.status == 'in_progress' ? issue.currentPage : null;
  await setIssueReadState(read, issue, read: !wasRead, awaitServer: false);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('Marked $label ${wasRead ? 'unread' : 'read'}'),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => setIssueReadState(read, issue,
            read: wasRead, page: wasRead ? null : prevPage),
      ),
    ));
}

/// Sets an issue to read, unread, or (with [page]) in progress at [page].
/// Writes the mirror, then pushes to the server (awaited unless
/// [awaitServer] is false). A failed push goes to the outbox, so an offline
/// toggle reaches the server on the next sync, as reader progress does.
Future<void> setIssueReadState(ProviderReader reader, SeriesIssue issue,
    {required bool read, int? page, bool awaitServer = true}) async {
  final db = reader(mirrorDbProvider);
  final total = issue.totalPages ?? 1;
  final current = read ? total : page;
  if (current == null) {
    await db.deleteProgressLocal(issue.id);
  } else {
    await db.saveProgressLocal(
        comicId: issue.id, currentPage: current, totalPages: total);
  }
  Future<void> pushToServer() async {
    final client = reader(apiClientProvider);
    try {
      if (current == null) {
        await client.batchDeleteProgress([issue.id]);
      } else {
        await client.batchUpdateProgress([
          {'comic_id': issue.id, 'current_page': current, 'total_pages': total}
        ]);
      }
    } catch (_) {
      await reader(syncQueueProvider)?.enqueue(current == null
          ? {'type': 'progress_delete', 'payload': {'comic_id': issue.id}}
          : {
              'type': 'progress',
              'payload': {
                'comic_id': issue.id,
                'current_page': current,
                'total_pages': total,
              },
            });
    }
    try {
      await reader(syncEngineProvider)?.sync();
    } catch (_) {}
  }
  final push = pushToServer();
  if (awaitServer) await push;
}

/// Marks a single issue as read or unread (long-press sheet).
Future<void> markIssue({
  required WidgetRef ref,
  required SeriesIssue issue,
  required String seriesId,
  required bool read,
}) async {
  HapticFeedback.mediumImpact();
  await setIssueReadState(ref.read, issue, read: read);
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
