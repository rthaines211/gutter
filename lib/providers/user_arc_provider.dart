import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/mirror/sync_engine.dart';
import '../services/sync_queue.dart';
import 'cache_providers.dart';
import 'mirror_provider.dart';

final userArcActionsProvider = Provider<UserArcActions>((ref) {
  return UserArcActions(
    outbox: ref.watch(syncQueueProvider),
    syncEngine: ref.watch(syncEngineProvider),
  );
});

/// Saves user-made arcs (source 'user') through the outbox; the next sync
/// pushes them and pulls them back into the mirror like any arc.
/// ponytail: no local mirror write, so an offline save shows up after the
/// next online sync; write arc_rows locally if that delay bothers anyone.
class UserArcActions {
  final SyncQueue? outbox;
  final SyncEngine? syncEngine;
  UserArcActions({required this.outbox, required this.syncEngine});

  static String newId() =>
      'u_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(0x7fffffff)}';

  Future<void> _push(Map<String, dynamic> entry) async {
    await outbox?.enqueue(entry);
    unawaited(syncEngine?.sync(force: true).catchError((_) {}));
  }

  Future<void> save(String id, String name, List<String> issueIds) => _push({
        'type': 'arc_upsert',
        'payload': {'id': id, 'name': name, 'issue_ids': issueIds},
      });

  Future<void> delete(String id) => _push({
        'type': 'arc_delete',
        'payload': {'id': id},
      });
}
