import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/scheme.dart';
import '../models/series.dart';
import '../providers/mirror_provider.dart';
import '../providers/user_arc_provider.dart';
import '../services/arc_list_matcher.dart';

String _label(SeriesIssue i) =>
    '${i.seriesName ?? i.name}${i.number == null ? '' : ' #${i.number}'}';

/// Make or edit a user arc: paste a reading order, add issues by search,
/// drag to reorder. [arcId] null = new arc.
class ArcEditorScreen extends ConsumerStatefulWidget {
  final String? arcId;
  final String initialName;
  final List<SeriesIssue> initialIssues;
  const ArcEditorScreen({
    super.key,
    this.arcId,
    this.initialName = '',
    this.initialIssues = const [],
  });

  @override
  ConsumerState<ArcEditorScreen> createState() => _ArcEditorScreenState();
}

class _ArcEditorScreenState extends ConsumerState<ArcEditorScreen> {
  late final _name = TextEditingController(text: widget.initialName);
  late final List<SeriesIssue> _issues = [...widget.initialIssues];
  final List<String> _unmatched = [];
  List<SeriesIssue>? _library;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<List<SeriesIssue>> _loadLibrary() async =>
      _library ??= await ref.read(mirrorDbProvider).allIssuesWithSeries();

  void _add(SeriesIssue i) {
    if (_issues.any((e) => e.id == i.id)) return;
    setState(() => _issues.add(i));
  }

  Future<void> _paste() async {
    final ctl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste a reading order'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: ctl,
            autofocus: true,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: 'One issue per line, like\nUltimates #19',
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctl.text),
              child: const Text('Add')),
        ],
      ),
    );
    ctl.dispose();
    if (text == null || text.trim().isEmpty) return;
    final matches = matchArcList(text, await _loadLibrary());
    if (!mounted) return;
    setState(() {
      _unmatched
        ..clear()
        ..addAll(matches.where((m) => m.issue == null).map((m) => m.line));
    });
    for (final m in matches) {
      if (m.issue != null) _add(m.issue!);
    }
  }

  Future<void> _pick() async {
    final library = await _loadLibrary();
    if (!mounted) return;
    final picked = await showModalBottomSheet<SeriesIssue>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _IssuePicker(library: library),
    );
    if (picked != null) _add(picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _issues.isEmpty) return;
    await ref.read(userArcActionsProvider).save(
          widget.arcId ?? UserArcActions.newId(),
          name,
          _issues.map((i) => i.id).toList(),
        );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _name.text.trim().isNotEmpty && _issues.isNotEmpty;
    return Scaffold(
      backgroundColor: context.scheme.bg,
      appBar: AppBar(
        backgroundColor: context.scheme.bg,
        title: Text(widget.arcId == null ? 'New reading order' : 'Edit reading order'),
        actions: [
          TextButton(
              onPressed: canSave ? _save : null, child: const Text('Save')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste_rounded),
                  label: const Text('Paste list'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add issue'),
                ),
              ],
            ),
          ),
          if (_unmatched.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Not in your library: ${_unmatched.join(' · ')}',
                style: TextStyle(color: context.scheme.t2),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 120),
              itemCount: _issues.length,
              onReorder: (from, to) => setState(() {
                if (to > from) to--;
                _issues.insert(to, _issues.removeAt(from));
              }),
              itemBuilder: (context, i) {
                final issue = _issues[i];
                return ListTile(
                  key: ValueKey(issue.id),
                  leading: Text('${i + 1}', style: TextStyle(color: context.scheme.t2)),
                  title: Text(_label(issue)),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _issues.removeAt(i)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Search the library by "series number" and tap an issue to add it.
class _IssuePicker extends StatefulWidget {
  final List<SeriesIssue> library;
  const _IssuePicker({required this.library});

  @override
  State<_IssuePicker> createState() => _IssuePickerState();
}

class _IssuePickerState extends State<_IssuePicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final words =
        _q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final hits = words.isEmpty
        ? const <SeriesIssue>[]
        : widget.library
            .where((i) {
              final l = _label(i).toLowerCase();
              return words.every(l.contains);
            })
            .take(100)
            .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search, like "ultimates 19"',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final i in hits)
                    ListTile(
                      title: Text(_label(i)),
                      onTap: () => Navigator.pop(context, i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
