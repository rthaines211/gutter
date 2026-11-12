import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../config/server_url.dart';
import '../models/server_source.dart';
import '../services/app_logger.dart';
import '../services/local_session_store.dart';
import '../services/source_files.dart';
import '../services/sync_queue.dart';
import '../services/sync_queue_drainer.dart';
import 'cache_providers.dart';
import 'download_provider.dart';
import 'providers.dart';
import 'source_provider.dart';

/// Same type at the same address: a login-only change, which keeps the
/// source's id and everything on the device. The address is host (any case),
/// explicit non-default port and path; the scheme doesn't count, so adding
/// TLS to the same box keeps its downloads.
bool sameServer(ServerSource a, ServerSource b) {
  String key(String url) {
    final u = Uri.parse(normalizeServerUrl(url));
    return '${u.host.toLowerCase()}:${u.hasPort ? u.port : ''}${u.path}';
  }

  return a.type == b.type && key(a.address) == key(b.address);
}

typedef OutboxDrain = Future<void> Function(
    ServerSource source, SyncQueue queue);

final serverActionsProvider =
    Provider<ServerActions>((ref) => ServerActions(ref));

/// Edits, replaces, adds and signs out of servers. A replace (new type or
/// address) or a sign-out *forgets* the old source: keychain, prefs entry,
/// mirror, covers, cache (outbox included) and downloads. Callers flush the
/// outbox ([flushOutbox]) and ask the user before anything is forgotten.
class ServerActions {
  final Ref _ref;
  ServerActions(this._ref);

  /// Replays a source's outbox against that source's own server, so it works
  /// for a source that isn't active.
  @visibleForTesting
  late OutboxDrain drain = (source, queue) async {
    final docs = await _ref.read(docsDirProvider.future);
    final client = clientFor(source,
        deviceId: _ref.read(serverConfigProvider).deviceId,
        sessions:
            LocalSessionStore(p.join(docs, 'cache', source.id, 'sessions.json')));
    await SyncQueueDrainer(queue: queue, client: client).drain();
  };

  Future<SyncQueue> _queue(ServerSource s) async => SyncQueue(
      queuePath: p.join(await _ref.read(docsDirProvider.future), 'cache', s.id,
          'sync_queue.json'));

  Future<int> pendingCount(ServerSource s) async =>
      (await _queue(s)).pendingCount;

  /// Tries to send [s]'s queued changes; returns how many are still queued.
  Future<int> flushOutbox(ServerSource s) async {
    final queue = await _queue(s);
    try {
      await drain(s, queue);
    } catch (e) {
      AppLogger.instanceOrNull?.sync(
          level: LogLevel.warn,
          message: 'outbox flush failed',
          context: {'source': s.id, 'error': e.toString()});
    }
    return queue.pendingCount;
  }

  /// Saves a server that just answered a probe. [old] is the server being
  /// edited (null when adding).
  Future<void> save({ServerSource? old, required ServerSource found}) async {
    final list = _ref.read(sourceListProvider.notifier);
    if (old != null && sameServer(old, found)) {
      list.edit(old.id,
          _identity(found, id: old.id, name: old.name, isDefault: old.isDefault));
      return;
    }
    final fresh = _identity(found,
        id: generateSourceId(),
        name: found.name,
        isDefault: old?.isDefault ?? false);
    final wasActive = old != null && _ref.read(activeSourceProvider).id == old.id;
    list.add(fresh);
    if (old == null || wasActive) {
      _ref.read(activeSourceIdProvider.notifier).select(fresh.id);
    }
    if (old != null) await _forget(old.id);
  }

  /// Adds the "On this device" source next to any servers and switches to
  /// it. Free: not a server, so not behind the "more than one server" gate.
  void addLocal() {
    final local = ServerSource.local(id: generateSourceId());
    _ref.read(sourceListProvider.notifier).add(local);
    _ref.read(activeSourceIdProvider.notifier).select(local.id);
  }

  /// Makes the "On this device" source the active one and returns its id:
  /// the one there is, else the blank default (onboarding; same id), else a
  /// new one next to the servers.
  String useLocal() {
    final sources = _ref.read(sourceListProvider);
    for (final s in sources) {
      if (s.type == SourceType.local) {
        _ref.read(activeSourceIdProvider.notifier).select(s.id);
        return s.id;
      }
    }
    for (final s in sources) {
      if (s.isDefault && s.baseUrl.isEmpty) {
        _ref
            .read(sourceListProvider.notifier)
            .setDefaultServer(ServerSource.local(id: s.id));
        _ref.read(activeSourceIdProvider.notifier).select(s.id);
        return s.id;
      }
    }
    addLocal();
    return _ref.read(activeSourceProvider).id;
  }

  /// Signs out of [s] and forgets it. The last server leaves a blank default
  /// source (fresh id, no URL), so the app shows onboarding.
  Future<void> signOut(ServerSource s) async {
    final list = _ref.read(sourceListProvider.notifier);
    final active = _ref.read(activeSourceIdProvider.notifier);
    final others = _ref.read(sourceListProvider).where((x) => x.id != s.id);
    if (others.isEmpty) {
      final blank = ServerSource(
          id: generateSourceId(),
          name: 'My Server',
          type: SourceType.custom,
          baseUrl: '',
          authType: AuthType.none,
          isDefault: true);
      list.add(blank);
      active.select(blank.id);
    } else {
      if (_ref.read(activeSourceProvider).id == s.id) {
        active.select(others.first.id);
      }
      if (s.isDefault) {
        final heir = _ref.read(activeSourceProvider);
        list.edit(heir.id,
            _identity(heir, id: heir.id, name: heir.name, isDefault: true));
      }
    }
    await _forget(s.id);
  }

  /// The next active source is already selected, so nothing reopens this
  /// source's database. Its close (the mirror provider's dispose) may still be
  /// pending when the file is unlinked; on iOS the open handle keeps the
  /// inode alive until then, and the id is never reused.
  Future<void> _forget(String id) async {
    _ref.read(sourceListProvider.notifier).remove(id);
    try {
      await _ref.read(downloadManagerProvider)?.deleteSource(id);
    } catch (e) {
      debugPrint('forget $id downloads: $e');
    }
    try {
      await deleteSourceFiles(await _ref.read(docsDirProvider.future), id);
    } catch (e) {
      debugPrint('forget $id files: $e');
    }
  }

  static ServerSource _identity(ServerSource s,
          {required String id, required String name, required bool isDefault}) =>
      ServerSource(
        id: id,
        name: name,
        type: s.type,
        baseUrl: s.baseUrl,
        authType: s.authType,
        username: s.username,
        password: s.password,
        apiKey: s.apiKey,
        catalogPath: s.catalogPath,
        isDefault: isDefault,
      );
}
