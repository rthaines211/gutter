import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/reading_queue.dart';
import '../providers/queue_provider.dart';
import 'queue_detail_screen.dart';

class QueuesScreen extends ConsumerWidget {
  const QueuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queuesAsync = ref.watch(queuesProvider);
    return Scaffold(
      backgroundColor: context.scheme.bg,
      appBar: AppBar(
        backgroundColor: context.scheme.bg,
        title: const Text('Queues'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showCreate(context, ref),
          ),
        ],
      ),
      body: queuesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load queues: $e')),
        data: (queues) {
          if (queues.isEmpty) {
            return _EmptyState(onCreate: () => _showCreate(context, ref));
          }
          return ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: queues.length,
            onReorder: (oldIndex, newIndex) {
              HapticFeedback.mediumImpact();
              _reorderQueues(ref, queues, oldIndex, newIndex);
            },
            itemBuilder: (context, i) {
              final q = queues[i];
              return ListTile(
                key: ValueKey(q.id),
                leading: Icon(
                  Icons.playlist_play_rounded,
                  color: _parseColor(q.color),
                ),
                title: Text(
                  q.name,
                  style: TextStyle(color: context.scheme.tx),
                ),
                subtitle: Text(
                  '${q.seriesIds.length} series',
                  style: TextStyle(color: context.scheme.t3),
                ),
                trailing: Icon(
                  Icons.drag_handle_rounded,
                  color: context.scheme.t3,
                ),
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => QueueDetailScreen(queueId: q.id),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _reorderQueues(
    WidgetRef ref,
    List<ReadingQueue> queues,
    int oldIndex,
    int newIndex,
  ) {
    final list = [...queues];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    final actions = ref.read(queueActionsProvider);
    for (var i = 0; i < list.length; i++) {
      if (list[i].position != i) {
        actions.rename(list[i].copyWith(position: i), list[i].name);
      }
    }
  }

  void _showCreate(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: context.scheme.s2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'New Queue',
              style: TextStyle(
                color: ctx.scheme.tx,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: ctx.scheme.tx),
              decoration: InputDecoration(
                hintText: 'Queue name',
                hintStyle: TextStyle(color: ctx.scheme.t3),
                filled: true,
                fillColor: ctx.scheme.s1,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (name) async {
                if (name.trim().isNotEmpty) {
                  await ref.read(queueActionsProvider).create(name.trim());
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  static Color _parseColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length == 6) {
      final value = int.tryParse(cleaned, radix: 16);
      if (value != null) return Color(0xFF000000 | value);
    }
    return AppTheme.accent;
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.playlist_add_rounded,
            size: 56,
            color: context.scheme.t3,
          ),
          const SizedBox(height: 12),
          Text(
            'No queues yet',
            style: TextStyle(color: context.scheme.t2, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'Make a queue to plan your next reads',
            style: TextStyle(color: context.scheme.t3, fontSize: 12),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New Queue'),
          ),
        ],
      ),
    );
  }
}
