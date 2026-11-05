import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/scheme.dart';
import '../models/reading_queue.dart';
import '../providers/mirror_provider.dart';
import '../providers/providers.dart';
import '../providers/queue_provider.dart';
import 'series_detail_screen.dart';

class QueueDetailScreen extends ConsumerWidget {
  final String queueId;
  const QueueDetailScreen({super.key, required this.queueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queuesAsync = ref.watch(queuesProvider);
    final library = ref.watch(mirrorLibraryProvider).value ?? [];
    final serverUrl = ref.watch(serverConfigProvider).serverUrl;

    final queue = queuesAsync.value
        ?.where((q) => q.id == queueId)
        .cast<ReadingQueue?>()
        .firstOrNull;

    return Scaffold(
      backgroundColor: context.scheme.bg,
      appBar: AppBar(
        backgroundColor: context.scheme.bg,
        title: Text(queue?.name ?? 'Queue'),
      ),
      body: queue == null
          ? const Center(child: CircularProgressIndicator())
          : queue.seriesIds.isEmpty
          ? Center(
              child: Text(
                'This queue is empty',
                style: TextStyle(color: context.scheme.t2),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: queue.seriesIds.length,
              onReorder: (oldIndex, newIndex) {
                HapticFeedback.mediumImpact();
                final ids = [...queue.seriesIds];
                if (newIndex > oldIndex) newIndex -= 1;
                final moved = ids.removeAt(oldIndex);
                ids.insert(newIndex, moved);
                ref.read(queueActionsProvider).reorder(queue, ids);
              },
              itemBuilder: (context, i) {
                final seriesId = queue.seriesIds[i];
                final series = library
                    .where((m) => m.series.id == seriesId)
                    .map((m) => m.series)
                    .firstOrNull;
                final name = series?.name ?? seriesId;
                final coverUrl =
                    '$serverUrl/library/${Uri.encodeComponent(seriesId)}/cover';
                return Dismissible(
                  key: ValueKey(seriesId),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: const Color(0xFFFF453A),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: Icon(
                      Icons.delete_outline,
                      color: Scheme.onAccent(const Color(0xFFFF453A)),
                    ),
                  ),
                  onDismissed: (_) {
                    HapticFeedback.mediumImpact();
                    ref
                        .read(queueActionsProvider)
                        .removeSeries(queue, seriesId);
                  },
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(httpHeaders: imageHeadersOf(context), 
                        imageUrl: coverUrl,
                        width: 36,
                        height: 52,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Container(
                          width: 36,
                          height: 52,
                          color: context.scheme.s1,
                        ),
                      ),
                    ),
                    title: Text(
                      name,
                      style: TextStyle(color: context.scheme.tx),
                    ),
                    trailing: Icon(
                      Icons.drag_handle_rounded,
                      color: context.scheme.t3,
                    ),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              SeriesDetailScreen(seriesId: seriesId),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
