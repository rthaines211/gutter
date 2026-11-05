import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/bookmark.dart';
import '../models/chapter.dart';
import '../models/reading_queue.dart';
import 'api_client.dart';
import 'app_logger.dart';
import 'sync_queue.dart';

/// Drains a [SyncQueue] by replaying entries against an [ApiClient].
///
/// Failure handling:
/// - **Network-layer exception** (e.g. SocketException): break the loop.
///   The entry stays at the head and will be retried on the next drain.
/// - **5xx HTTP response**: break the loop. Server is reachable but
///   degraded; retry later.
/// - **401 / 403 / 408 / 429**: break like a 5xx; they're "try again later"
///   (wrong or missing credentials get fixed, then the entry replays), not
///   terminal.
/// - **Anything else thrown** (a bad cast on a malformed payload): drop, like
///   a 4xx. Breaking on it would stall every later entry behind it forever.
/// - **Other 4xx HTTP response**: drop the entry (it will never succeed) and
///   continue with the next. A 409 on a `progress` replay means the server
///   already holds a progress write at least as fresh (stale `read_at`);
///   dropping it is correct — the next `/sync` pull corrects the mirror.
class SyncQueueDrainer {
  final SyncQueue queue;
  final ApiClient client;

  SyncQueueDrainer({required this.queue, required this.client});

  Future<void> drain() async {
    while (true) {
      final entries = await queue.readAll();
      if (entries.isEmpty) break;

      final entry = entries.first;
      final type = entry['type'];
      final payload = entry['payload'];
      // These casts used to sit outside the try below, so a malformed entry
      // threw straight out of drain() and aborted the sync before its pull.
      // Malformed is terminal like a 4xx: drop it and keep draining.
      if (type is! String || payload is! Map<String, dynamic>) {
        AppLogger.instance.sync(
          level: LogLevel.warn,
          message: 'dropping malformed entry',
          context: {'entry': entry.toString()},
        );
        await queue.removeFirst();
        continue;
      }
      final queuedAtRaw = entry['queued_at'] as String?;
      final readAtMs = queuedAtRaw == null
          ? null
          : DateTime.tryParse(queuedAtRaw)?.millisecondsSinceEpoch;

      AppLogger.instance.sync(
        level: LogLevel.debug,
        message: 'flushing entry',
        context: {'type': type, 'comic_id': payload['comic_id'] ?? '<unknown>'},
      );

      try {
        await _replay(type, payload, readAtMs);
        await queue.removeFirst();
      } on ApiException catch (e) {
        if (e.statusCode >= 400 &&
            e.statusCode < 500 &&
            e.statusCode != 401 &&
            e.statusCode != 403 &&
            e.statusCode != 408 &&
            e.statusCode != 429) {
          AppLogger.instance.sync(
            level: LogLevel.warn,
            message: 'dropping entry (terminal ${e.statusCode})',
            context: {
              'type': type,
              'comic_id': payload['comic_id'] ?? '<unknown>',
              'status': e.statusCode,
            },
          );
          await queue.removeFirst();
          continue;
        }
        AppLogger.instance.sync(
          level: LogLevel.warn,
          message: 'flush paused (server ${e.statusCode})',
          context: {'type': type, 'status': e.statusCode},
        );
        break;
      } catch (e) {
        if (e is SocketException ||
            e is TimeoutException ||
            e is HandshakeException ||
            e is http.ClientException) {
          AppLogger.instance.sync(
            level: LogLevel.warn,
            message: 'flush paused (network)',
            context: {'type': type, 'error': e.toString()},
          );
          break;
        }
        // Anything else (a bad cast or parse on a malformed payload) means the
        // entry itself is bad; retrying can't fix it.
        AppLogger.instance.sync(
          level: LogLevel.warn,
          message: 'dropping entry (unreplayable)',
          context: {'type': type, 'error': e.toString()},
        );
        await queue.removeFirst();
      }
    }
  }

  Future<void> _replay(
    String type,
    Map<String, dynamic> payload,
    int? readAtMs,
  ) async {
    if (type == 'progress') {
      await client.updateProgress(
        comicId: payload['comic_id'] as String,
        currentPage: payload['current_page'] as int,
        totalPages: payload['total_pages'] as int,
        bookmarks: (payload['bookmarks'] as List<dynamic>?)
            ?.map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
            .toList(),
        // Absent stays absent: an empty list would make the server wipe the
        // comic's chapters on every replayed page turn.
        chapters: (payload['chapters'] as List<dynamic>?)
            ?.map((e) => Chapter.fromJson(e as Map<String, dynamic>))
            .toList(),
        readAtMs: readAtMs,
      );
    } else if (type == 'session') {
      await client.postReadingSession(
        comicId: payload['comic_id'] as String,
        seriesId: payload['series_id'] as String,
        startedAt: DateTime.parse(payload['started_at'] as String),
        pagesRead: payload['pages_read'] as int,
        durationS: payload['duration_s'] as int,
      );
    } else if (type == 'queue_upsert') {
      await client.putQueue(ReadingQueue.fromJson(payload));
    } else if (type == 'queue_delete') {
      await client.deleteQueue(payload['id'] as String);
    } else if (type == 'comic_metadata') {
      await client.patchComicMetadata(
        payload['comic_id'] as String,
        (payload['fields'] as Map).cast<String, dynamic>(),
      );
    } else if (type == 'series_metadata') {
      await client.patchSeriesMetadata(
        payload['series_id'] as String,
        (payload['fields'] as Map).cast<String, dynamic>(),
      );
    } else if (type == 'bubble_order') {
      await client.putBubbleOrder(
        payload['comic_id'] as String,
        payload['page'] as int,
        (payload['labels'] as List).cast<int>(),
      );
    } else {
      // Unknown type — drop it like a 4xx. Drainer logs it as terminal.
      throw ApiException(400, 'unknown queue entry type: $type');
    }
  }
}
