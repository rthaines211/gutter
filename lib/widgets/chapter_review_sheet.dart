// lib/widgets/chapter_review_sheet.dart
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/chapter_candidate.dart';

Future<List<ChapterCandidate>?> showChapterReviewSheet(
  BuildContext context, {
  required List<ChapterCandidate> candidates,
}) {
  return showModalBottomSheet<List<ChapterCandidate>>(
    context: context,
    backgroundColor: context.scheme.s1,
    isScrollControlled: true,
    builder: (ctx) => _ReviewSheet(candidates: candidates),
  );
}

class _ReviewSheet extends StatefulWidget {
  final List<ChapterCandidate> candidates;
  const _ReviewSheet({required this.candidates});
  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late final Map<int, bool> _accepted;   // page -> accepted
  late final Map<int, String> _titles;   // page -> (edited) title

  @override
  void initState() {
    super.initState();
    _accepted = {for (final c in widget.candidates) c.page: true};
    _titles = {for (final c in widget.candidates) c.page: c.title};
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Review detected chapters',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
            ),
            if (widget.candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No chapters detected', style: TextStyle(color: context.scheme.t2)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: widget.candidates.map((c) {
                    final on = _accepted[c.page] ?? false;
                    return ListTile(
                      leading: Text('p.${c.page + 1}', style: context.monoCaption),
                      title: Text(_titles[c.page] ?? c.title,
                          style: TextStyle(color: on ? context.scheme.tx : context.scheme.t3)),
                      subtitle: Text('${c.source} · ${c.confidence}',
                          style: context.monoCaption.copyWith(fontSize: 10)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          key: Key('edit-${c.page}'),
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () async {
                            final t = await _editTitle(_titles[c.page] ?? c.title);
                            if (t != null) setState(() => _titles[c.page] = t);
                          },
                        ),
                        IconButton(
                          key: Key('dismiss-${c.page}'),
                          icon: Icon(on ? Icons.check_circle : Icons.remove_circle_outline,
                              size: 18, color: on ? AppTheme.accent : context.scheme.t3),
                          onPressed: () => setState(() => _accepted[c.page] = !on),
                        ),
                      ]),
                    );
                  }).toList(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const Spacer(),
                FilledButton(
                  key: const Key('review-confirm'),
                  onPressed: () {
                    final out = widget.candidates
                        .where((c) => _accepted[c.page] ?? false)
                        .map((c) => ChapterCandidate(
                            page: c.page,
                            title: _titles[c.page] ?? c.title,
                            source: c.source,
                            confidence: c.confidence))
                        .toList();
                    Navigator.pop(context, out);
                  },
                  child: const Text('Add chapters'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _editTitle(String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.scheme.s2,
        title: const Text('Chapter name'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
  }
}
