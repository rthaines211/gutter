import 'package:flutter/material.dart';
import '../config/scheme.dart';
import '../services/chapter_merge.dart';

/// Modal sheet listing merged chapters. Callbacks delegate mutations and
/// navigation to the reader. Returns when dismissed.
Future<void> showChapterListSheet(
  BuildContext context, {
  required List<ReaderChapter> chapters,
  required int currentPage,
  required void Function(int page) onJump,
  required void Function(int pageNum, String title) onAdd,
  required void Function(String id, String title) onRename,
  required void Function(String id) onDelete,
  VoidCallback? onDetect,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.scheme.s1,
    isScrollControlled: true,
    builder: (ctx) => _ChapterListSheet(
      chapters: chapters,
      currentPage: currentPage,
      onJump: onJump,
      onAdd: onAdd,
      onRename: onRename,
      onDelete: onDelete,
      onDetect: onDetect,
    ),
  );
}

class _ChapterListSheet extends StatelessWidget {
  final List<ReaderChapter> chapters;
  final int currentPage;
  final void Function(int page) onJump;
  final void Function(int pageNum, String title) onAdd;
  final void Function(String id, String title) onRename;
  final void Function(String id) onDelete;
  final VoidCallback? onDetect;

  const _ChapterListSheet({
    required this.chapters,
    required this.currentPage,
    required this.onJump,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    this.onDetect,
  });

  Future<String?> _promptName(BuildContext context, {String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.scheme.s2,
        title: const Text('Chapter name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Chapter name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  const Text('Chapters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (onDetect != null)
                    TextButton.icon(
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Detect chapters'),
                      onPressed: () { Navigator.pop(context); onDetect!(); },
                    ),
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add here'),
                    onPressed: () async {
                      final name = await _promptName(context);
                      if (name == null) return;
                      onAdd(currentPage, name);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            if (chapters.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No chapters yet', style: TextStyle(color: context.scheme.t3)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: chapters.length,
                  itemBuilder: (ctx, i) {
                    final c = chapters[i];
                    return ListTile(
                      title: Text(c.title),
                      subtitle: Text('p. ${c.pageNum + 1}'),
                      onTap: () {
                        onJump(c.pageNum);
                        Navigator.pop(context);
                      },
                      trailing: c.editable
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Rename chapter',
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () async {
                                    final name = await _promptName(context, initial: c.title);
                                    if (name == null || name.trim().isEmpty) return;
                                    onRename(c.id!, name);
                                    if (context.mounted) Navigator.pop(context);
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Delete chapter',
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  onPressed: () {
                                    onDelete(c.id!);
                                    Navigator.pop(context);
                                  },
                                ),
                              ],
                            )
                          : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
