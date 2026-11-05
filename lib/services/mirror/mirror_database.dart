import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../models/arc.dart';
import '../../models/reading_progress.dart';
import '../../models/reading_queue.dart';
import '../../models/series.dart';
import '../../models/sync_response.dart';

part 'mirror_database.g.dart';

/// One mirrored series row. `payload` is the full server JSON object
/// (minus `issues`), so `Series.fromJson` keeps working unchanged.
class SeriesRows extends Table {
  TextColumn get id => text()();
  TextColumn get updatedAt => text()(); // RFC3339 UTC, from the server
  TextColumn get coverSyncedAt => text().nullable()(); // updatedAt at last cover download
  TextColumn get payload => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_issue_series', columns: {#seriesId})
class IssueRows extends Table {
  TextColumn get id => text()();
  TextColumn get seriesId => text()();
  IntColumn get position => integer()();
  TextColumn get payload => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class ProgressRows extends Table {
  TextColumn get comicId => text()();
  IntColumn get currentPage => integer()();
  IntColumn get totalPages => integer()();
  TextColumn get updatedAt => text()(); // RFC3339 UTC
  TextColumn get chapters => text().nullable()(); // JSON-encoded List<Chapter>

  @override
  Set<Column> get primaryKey => {comicId};
}

class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class QueueRows extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get icon => text().withDefault(const Constant('bookmark'))();
  TextColumn get color => text().withDefault(const Constant('#FFB74D'))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text()(); // RFC3339 UTC
  TextColumn get updatedAt => text()(); // RFC3339 UTC

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_queue_item_queue', columns: {#queueId})
class QueueItemRows extends Table {
  TextColumn get queueId => text()();
  TextColumn get seriesId => text()();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {queueId, seriesId};
}

class ArcRows extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get imageUrl => text().withDefault(const Constant(''))();
  IntColumn get selfContained => integer().nullable()(); // 0/1/null
  IntColumn get total => integer().withDefault(const Constant(0))();
  TextColumn get source => text().withDefault(const Constant('mylar'))();
  TextColumn get publisher => text().withDefault(const Constant(''))();
  IntColumn get startYear => integer().withDefault(const Constant(0))();
  IntColumn get endYear => integer().withDefault(const Constant(0))();
  TextColumn get description => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_arc_item_arc', columns: {#arcId})
class ArcItemRows extends Table {
  TextColumn get arcId => text()();
  TextColumn get issueId => text()();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {arcId, issueId};
}

/// A series plus progress-derived aggregates the Series payload can't carry.
class MirrorSeries {
  final Series series;
  final DateTime? lastReadAt;

  /// First issue (by position) that isn't completed, or null when every
  /// issue is read. Used by the creator page's "read next" action.
  final String? nextUnreadIssueId;

  const MirrorSeries({
    required this.series,
    this.lastReadAt,
    this.nextUnreadIssueId,
  });
}

/// RFC3339 UTC, second resolution — matches the server's timestamp format so
/// local and pulled timestamps sort consistently as text.
String serverTimestamp(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}

@DriftDatabase(tables: [
  SeriesRows, IssueRows, ProgressRows, SyncState, QueueRows, QueueItemRows,
  ArcRows, ArcItemRows,
])
class MirrorDatabase extends _$MirrorDatabase {
  MirrorDatabase(super.e);

  factory MirrorDatabase.open(String sourceId) =>
      MirrorDatabase(driftDatabase(name: 'mirror_$sourceId'));

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(queueRows);
            await m.createTable(queueItemRows);
          }
          if (from < 3) {
            await m.addColumn(progressRows, progressRows.chapters);
          }
          if (from < 4) {
            await m.createTable(arcRows);
            await m.createTable(arcItemRows);
          }
          if (from < 5) {
            // created_at now rides in the series payload. Reset the watermark so
            // the next sync re-pulls every series (since=0) and backfills it;
            // otherwise untouched series keep the updatedAt fallback forever.
            await (delete(syncState)
                  ..where((t) => t.key.equals('last_server_time')))
                .go();
          }
          if (from < 6) {
            // Arc rows gain source/publisher/years. Reset the watermark (same
            // reasoning as the from < 5 step) so every arc re-pulls and
            // backfills the new columns instead of sitting at their defaults.
            // Skip the addColumns for from < 4: the from < 4 step above just
            // created arc_rows from the *current* table definition, which
            // already has these columns — adding them again would fail with
            // "duplicate column".
            if (from >= 4) {
              await m.addColumn(arcRows, arcRows.source);
              await m.addColumn(arcRows, arcRows.publisher);
              await m.addColumn(arcRows, arcRows.startYear);
              await m.addColumn(arcRows, arcRows.endYear);
            }
            await (delete(syncState)
                  ..where((t) => t.key.equals('last_server_time')))
                .go();
          }
          if (from < 7) {
            // Arc rows gain description. Same from >= 4 guard and watermark
            // reset as the from < 6 step.
            if (from >= 4) {
              await m.addColumn(arcRows, arcRows.description);
            }
            await (delete(syncState)
                  ..where((t) => t.key.equals('last_server_time')))
                .go();
          }
        },
      );

  /// Applies a /sync delta inside one transaction: upsert changed series
  /// (replacing their issue lists), upsert pulled progress, then prune
  /// anything absent from the full ID lists. Progress rows whose comic_id is
  /// in [protectedComicIds] (= still queued in the outbox) are never touched.
  /// Issue payload rows whose comic_id is in [protectedComicIds] are also
  /// skipped (covers queued comic_metadata edits). Series payload upserts for
  /// series IDs in [protectedSeriesIds] are skipped entirely, though their
  /// issues and progress rows are still processed normally.
  Future<void> applySync(SyncResponse resp,
      {Set<String> protectedComicIds = const {},
      Set<String> protectedQueueIds = const {},
      Set<String> protectedSeriesIds = const {}}) async {
    await transaction(() async {
      for (final s in resp.series) {
        await _upsertSeriesFromMap(s,
            protectedComicIds: protectedComicIds,
            protectedSeriesIds: protectedSeriesIds);
      }

      for (final p in resp.progress) {
        final comicId = p['comic_id'] as String;
        if (protectedComicIds.contains(comicId)) continue;
        await into(progressRows).insertOnConflictUpdate(
          ProgressRowsCompanion.insert(
            comicId: comicId,
            currentPage: p['current_page'] as int? ?? 0,
            totalPages: p['total_pages'] as int? ?? 0,
            updatedAt: p['updated_at'] as String? ?? '',
            chapters: Value(jsonEncode(p['chapters'] ?? [])),
          ),
        );
      }

      for (final q in resp.queues) {
        final id = q['id'] as String;
        final seriesIds =
            (q['series_ids'] as List<dynamic>? ?? []).cast<String>();
        await into(queueRows).insert(
          QueueRowsCompanion.insert(
            id: id,
            name: q['name'] as String? ?? '',
            icon: Value(q['icon'] as String? ?? 'bookmark'),
            color: Value(q['color'] as String? ?? '#FFB74D'),
            position: Value(q['position'] as int? ?? 0),
            createdAt: q['created_at'] as String? ?? '',
            updatedAt: q['updated_at'] as String? ?? '',
          ),
          onConflict: DoUpdate(
            (old) => QueueRowsCompanion(
              name: Value(q['name'] as String? ?? ''),
              icon: Value(q['icon'] as String? ?? 'bookmark'),
              color: Value(q['color'] as String? ?? '#FFB74D'),
              position: Value(q['position'] as int? ?? 0),
              updatedAt: Value(q['updated_at'] as String? ?? ''),
            ),
          ),
        );
        await (delete(queueItemRows)..where((t) => t.queueId.equals(id))).go();
        var pos = 0;
        for (final sid in seriesIds) {
          await into(queueItemRows).insert(QueueItemRowsCompanion.insert(
            queueId: id,
            seriesId: sid,
            position: pos++,
          ));
        }
      }

      for (final a in resp.arcs) {
        final id = a['id'] as String;
        final issueIds =
            (a['issue_ids'] as List<dynamic>? ?? []).cast<String>();
        await into(arcRows).insert(
          ArcRowsCompanion.insert(
            id: id,
            name: a['name'] as String? ?? '',
            imageUrl: Value(a['image_url'] as String? ?? ''),
            selfContained: Value(a['self_contained'] == null
                ? null
                : ((a['self_contained'] as bool) ? 1 : 0)),
            total: Value(a['total'] as int? ?? 0),
            source: Value(a['source'] as String? ?? 'mylar'),
            publisher: Value(a['publisher'] as String? ?? ''),
            startYear: Value(a['start_year'] as int? ?? 0),
            endYear: Value(a['end_year'] as int? ?? 0),
            description: Value(a['description'] as String? ?? ''),
          ),
          onConflict: DoUpdate(
            (old) => ArcRowsCompanion(
              name: Value(a['name'] as String? ?? ''),
              imageUrl: Value(a['image_url'] as String? ?? ''),
              selfContained: Value(a['self_contained'] == null
                  ? null
                  : ((a['self_contained'] as bool) ? 1 : 0)),
              total: Value(a['total'] as int? ?? 0),
              source: Value(a['source'] as String? ?? 'mylar'),
              publisher: Value(a['publisher'] as String? ?? ''),
              startYear: Value(a['start_year'] as int? ?? 0),
              endYear: Value(a['end_year'] as int? ?? 0),
              description: Value(a['description'] as String? ?? ''),
            ),
          ),
        );
        await (delete(arcItemRows)..where((t) => t.arcId.equals(id))).go();
        var pos = 0;
        for (final iid in issueIds) {
          await into(arcItemRows).insert(ArcItemRowsCompanion.insert(
            arcId: id,
            issueId: iid,
            position: pos++,
          ));
        }
      }

      await (delete(seriesRows)..where((t) => t.id.isNotIn(resp.seriesIds)))
          .go();
      await (delete(issueRows)
            ..where((t) => t.seriesId.isNotIn(resp.seriesIds)))
          .go();
      await (delete(progressRows)
            ..where((t) =>
                t.comicId.isNotIn(resp.progressIds) &
                t.comicId.isNotIn(protectedComicIds.toList())))
          .go();

      // Komga has no queues or arcs: its empty id lists mean "none of
      // mine", not "delete yours".
      if (!resp.serverHasQueues) return;
      final keepQueueIds = [...resp.queueIds, ...protectedQueueIds];
      await (delete(queueRows)..where((t) => t.id.isNotIn(keepQueueIds))).go();
      await (delete(queueItemRows)
            ..where((t) => t.queueId.isNotIn(keepQueueIds)))
          .go();

      await (delete(arcRows)..where((t) => t.id.isNotIn(resp.arcIds))).go();
      await (delete(arcItemRows)..where((t) => t.arcId.isNotIn(resp.arcIds)))
          .go();
    });
  }

  /// Inserts/updates one series row (+ its issue rows) from a raw server map
  /// (issues inline). Shared by [applySync]'s changed-set loop and
  /// [healMissingSeries]'s backfill. Must run inside a transaction.
  Future<void> _upsertSeriesFromMap(
    Map<String, dynamic> s, {
    required Set<String> protectedComicIds,
    required Set<String> protectedSeriesIds,
  }) async {
    final id = s['id'] as String;
    final issues =
        (s['issues'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final payload = Map<String, dynamic>.of(s)..remove('issues');
    final updatedAt = s['updated_at'] as String? ?? '';

    // Skip series payload upsert if a series_metadata edit is still
    // queued — the local edit must not be overwritten by a stale pull.
    if (!protectedSeriesIds.contains(id)) {
      await into(seriesRows).insert(
        SeriesRowsCompanion.insert(
          id: id,
          updatedAt: updatedAt,
          payload: jsonEncode(payload),
        ),
        onConflict: DoUpdate(
          (old) => SeriesRowsCompanion(
            updatedAt: Value(updatedAt),
            payload: Value(jsonEncode(payload)),
          ),
        ),
      );
    }

    // Snapshot local payloads for protected issues BEFORE deleting rows.
    final Map<String, String> savedPayloads = {};
    if (protectedComicIds.isNotEmpty) {
      final protectedInSeries = issues
          .map((i) => i['id'] as String)
          .where(protectedComicIds.contains)
          .toList();
      if (protectedInSeries.isNotEmpty) {
        final rows = await (select(issueRows)
              ..where((t) => t.id.isIn(protectedInSeries)))
            .get();
        for (final r in rows) {
          savedPayloads[r.id] = r.payload;
        }
      }
    }

    await (delete(issueRows)..where((t) => t.seriesId.equals(id))).go();
    var position = 0;
    for (final issue in issues) {
      final issueId = issue['id'] as String;
      // If a comic_metadata edit is queued, re-insert with the locally
      // edited payload (not the stale server payload).
      final localPayload = savedPayloads[issueId];
      await into(issueRows).insert(
        IssueRowsCompanion.insert(
          id: issueId,
          seriesId: id,
          position: position++,
          payload: localPayload ?? jsonEncode(issue),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }

  /// All series-row primary keys currently in the mirror.
  Future<Set<String>> allSeriesIds() async {
    final rows =
        await (selectOnly(seriesRows)..addColumns([seriesRows.id])).get();
    return rows.map((r) => r.read(seriesRows.id)!).toSet();
  }

  /// Backfills series that exist on the server (present in the sync keep-list)
  /// but are absent from the mirror. Delta sync only inserts the *changed*
  /// set, so a series whose `updated_at` predates the watermark is never
  /// re-inserted and never pruned — it goes permanently missing until a full
  /// re-pull. This inserts the fetched rows without pruning. Caller supplies
  /// raw server maps (issues inline), e.g. from [ApiClient.fetchSeriesRaw].
  Future<void> healMissingSeries(List<Map<String, dynamic>> series) async {
    if (series.isEmpty) return;
    await transaction(() async {
      for (final s in series) {
        await _upsertSeriesFromMap(s,
            protectedComicIds: const {}, protectedSeriesIds: const {});
      }
    });
  }

  /// Local-first progress write (reader). Timestamp is client-now in server
  /// format; the authoritative server timestamp replaces it on the next pull.
  /// Pass [chapters] only to (re)write the chapter set. When omitted (null) the
  /// chapters column is left untouched, so a routine progress save can't wipe
  /// chapters written by a chapter mutation or the out-of-band accept path.
  Future<void> saveProgressLocal({
    required String comicId,
    required int currentPage,
    required int totalPages,
    List<Map<String, dynamic>>? chapters,
  }) =>
      into(progressRows).insertOnConflictUpdate(ProgressRowsCompanion.insert(
        comicId: comicId,
        currentPage: currentPage,
        totalPages: totalPages,
        updatedAt: serverTimestamp(DateTime.now()),
        chapters: chapters == null
            ? const Value.absent()
            : Value(jsonEncode(chapters)),
      ));

  /// Merges [changes] into the stored series payload JSON. Local-first
  /// metadata edits call this before the server PATCH so streams update
  /// immediately; the next sync pull overwrites with server truth.
  Future<void> updateSeriesPayloadLocal(
      String seriesId, Map<String, dynamic> changes) async {
    final row = await (select(seriesRows)
          ..where((t) => t.id.equals(seriesId)))
        .getSingleOrNull();
    if (row == null) return;
    final payload = jsonDecode(row.payload) as Map<String, dynamic>;
    payload.addAll(changes);
    await (update(seriesRows)..where((t) => t.id.equals(seriesId))).write(
      SeriesRowsCompanion(
        payload: Value(jsonEncode(payload)),
        updatedAt: Value(serverTimestamp(DateTime.now())),
      ),
    );
  }

  /// Same as [updateSeriesPayloadLocal] for a single issue row.
  Future<void> updateIssuePayloadLocal(
      String comicId, Map<String, dynamic> changes) async {
    final row = await (select(issueRows)
          ..where((t) => t.id.equals(comicId)))
        .getSingleOrNull();
    if (row == null) return;
    final payload = jsonDecode(row.payload) as Map<String, dynamic>;
    payload.addAll(changes);
    await (update(issueRows)..where((t) => t.id.equals(comicId))).write(
      IssueRowsCompanion(payload: Value(jsonEncode(payload))),
    );
  }

  /// Current progress + decoded chapters for [comicId], or null if no row.
  Future<({int currentPage, int totalPages, List<Map<String, dynamic>> chapters})?>
      progressForComic(String comicId) async {
    final row = await (select(progressRows)
          ..where((t) => t.comicId.equals(comicId)))
        .getSingleOrNull();
    if (row == null) return null;
    final raw = row.chapters;
    final chapters = (raw == null || raw.isEmpty)
        ? const <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    return (
      currentPage: row.currentPage,
      totalPages: row.totalPages,
      chapters: chapters,
    );
  }

  /// Decodes the stored chapters JSON for [comicId]; empty list if none.
  Future<List<Map<String, dynamic>>> chaptersForComic(String comicId) async {
    final row = await (select(progressRows)
          ..where((t) => t.comicId.equals(comicId)))
        .getSingleOrNull();
    final raw = row?.chapters;
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  /// Series whose cover was never downloaded or is stale relative to the
  /// series' server updated_at.
  Future<List<SeriesRow>> listSeriesNeedingCovers() =>
      (select(seriesRows)
            ..where((t) =>
                t.coverSyncedAt.isNull() |
                t.coverSyncedAt.equalsExp(t.updatedAt).not()))
          .get();

  Future<void> markCoverSynced(String seriesId, String updatedAt) =>
      (update(seriesRows)..where((t) => t.id.equals(seriesId)))
          .write(SeriesRowsCompanion(coverSyncedAt: Value(updatedAt)));

  Future<String?> getSyncState(String key) async {
    final row = await (select(syncState)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setSyncState(String key, String value) =>
      into(syncState).insertOnConflictUpdate(
          SyncStateCompanion.insert(key: key, value: value));

  /// All mirrored series with progress-derived read counts and last-read
  /// timestamps. Single SQL statement so drift re-emits on any change to
  /// series, issues, or progress.
  Stream<List<MirrorSeries>> watchLibrary() {
    final query = customSelect('''
      SELECT s.payload AS payload,
        (SELECT COUNT(*) FROM issue_rows i
           JOIN progress_rows p ON p.comic_id = i.id
          WHERE i.series_id = s.id
            AND p.total_pages > 0
            AND p.current_page >= p.total_pages) AS read_count,
        (SELECT MAX(p.updated_at) FROM issue_rows i
           JOIN progress_rows p ON p.comic_id = i.id
          WHERE i.series_id = s.id) AS last_read_at,
        (SELECT i.id FROM issue_rows i
           LEFT JOIN progress_rows p ON p.comic_id = i.id
          WHERE i.series_id = s.id
            AND (p.comic_id IS NULL
                 OR p.total_pages = 0
                 OR p.current_page < p.total_pages)
          ORDER BY i.position LIMIT 1) AS next_unread_issue_id
      FROM series_rows s
    ''', readsFrom: {seriesRows, issueRows, progressRows});
    return query.watch().map((rows) => rows.map((r) {
          final map =
              jsonDecode(r.read<String>('payload')) as Map<String, dynamic>;
          map['read_count'] = r.read<int>('read_count');
          final lastRead = r.read<String?>('last_read_at');
          return MirrorSeries(
            series: Series.fromJson(map),
            lastReadAt: lastRead == null ? null : DateTime.tryParse(lastRead),
            nextUnreadIssueId: r.read<String?>('next_unread_issue_id'),
          );
        }).toList());
  }

  /// Series detail with issue statuses derived from mirrored progress.
  /// Emits null when the series isn't in the mirror.
  Stream<SeriesDetail?> watchSeriesDetail(String seriesId) {
    final query = customSelect('''
      SELECT s.payload AS series_payload,
             i.payload AS issue_payload,
             p.current_page AS current_page,
             p.total_pages AS total_pages
      FROM series_rows s
      LEFT JOIN issue_rows i ON i.series_id = s.id
      LEFT JOIN progress_rows p ON p.comic_id = i.id
      WHERE s.id = ?
      ORDER BY i.position
    ''', variables: [
      Variable.withString(seriesId)
    ], readsFrom: {
      seriesRows,
      issueRows,
      progressRows
    });
    return query.watch().map((rows) {
      if (rows.isEmpty) return null;
      final seriesMap =
          jsonDecode(rows.first.read<String>('series_payload'))
              as Map<String, dynamic>;
      final issues = <Map<String, dynamic>>[];
      var readCount = 0;
      for (final r in rows) {
        final issuePayload = r.read<String?>('issue_payload');
        if (issuePayload == null) continue;
        final m = jsonDecode(issuePayload) as Map<String, dynamic>;
        final cp = r.read<int?>('current_page');
        final tp = r.read<int?>('total_pages');
        if (cp != null && tp != null) {
          m['current_page'] = cp;
          m['total_pages'] = tp;
          m['status'] = (tp > 0 && cp >= tp) ? 'completed' : 'in_progress';
          if (m['status'] == 'completed') readCount++;
        } else {
          m['status'] = 'unread';
          m.remove('current_page');
          m.remove('total_pages');
        }
        issues.add(m);
      }
      seriesMap['issues'] = issues;
      seriesMap['read_count'] = readCount;
      return SeriesDetail.fromJson(seriesMap);
    });
  }

  /// In-progress comics, newest first — the "Continue Reading" shelf.
  Stream<List<ReadingProgress>> watchReadingList() {
    final query = customSelect('''
      SELECT p.comic_id AS comic_id, p.current_page AS current_page,
             p.total_pages AS total_pages, p.updated_at AS updated_at,
             i.series_id AS series_id
      FROM progress_rows p
      LEFT JOIN issue_rows i ON i.id = p.comic_id
      WHERE p.current_page < p.total_pages
      ORDER BY p.updated_at DESC
    ''', readsFrom: {progressRows, issueRows});
    return query.watch().map((rows) => rows
        .map((r) => ReadingProgress(
              comicId: r.read<String>('comic_id'),
              currentPage: r.read<int>('current_page'),
              totalPages: r.read<int>('total_pages'),
              updatedAt: DateTime.tryParse(r.read<String>('updated_at')),
              seriesId: r.read<String?>('series_id'),
            ))
        .toList());
  }

  /// All queues, ordered by queue position, each with ordered series ids.
  Stream<List<ReadingQueue>> watchQueues() {
    final query = customSelect('''
      SELECT q.id AS id, q.name AS name, q.icon AS icon, q.color AS color,
             q.position AS q_pos, q.created_at AS created_at, q.updated_at AS updated_at,
             qi.series_id AS series_id
      FROM queue_rows q
      LEFT JOIN queue_item_rows qi ON qi.queue_id = q.id
      ORDER BY q.position ASC, qi.position ASC
    ''', readsFrom: {queueRows, queueItemRows});
    return query.watch().map((rows) {
      final byId = <String, ReadingQueue>{};
      final order = <String>[];
      for (final r in rows) {
        final id = r.read<String>('id');
        if (!byId.containsKey(id)) {
          order.add(id);
          byId[id] = ReadingQueue(
            id: id,
            name: r.read<String>('name'),
            icon: r.read<String>('icon'),
            color: r.read<String>('color'),
            position: r.read<int>('q_pos'),
            seriesIds: const [],
            createdAt: DateTime.tryParse(r.read<String>('created_at')) ??
                DateTime.now(),
            updatedAt: DateTime.tryParse(r.read<String>('updated_at')) ??
                DateTime.now(),
          );
        }
        final sid = r.read<String?>('series_id');
        if (sid != null) {
          byId[id] = byId[id]!
              .copyWith(seriesIds: [...byId[id]!.seriesIds, sid]);
        }
      }
      return order.map((id) => byId[id]!).toList();
    });
  }

  /// All arcs with their present/total issue counts, read-derived progress,
  /// and a display cover. present = arc items whose issue is mirrored
  /// locally; total = the arc's issue count reported by Mylar; read =
  /// present items whose progress is completed; lastReadAt = the newest
  /// progress.updatedAt among the arc's members (null if none have
  /// progress); coverUrl = the arc's own image_url if set, else the
  /// cover_url from the lowest-position present item's issue payload, else
  /// ''.
  Stream<List<Arc>> watchArcs() {
    final query = customSelect('''
      SELECT a.id AS id, a.name AS name, a.image_url AS image_url,
             a.self_contained AS self_contained, a.total AS total,
             a.source AS source, a.publisher AS publisher,
             a.start_year AS start_year, a.end_year AS end_year,
             a.description AS description,
             COUNT(i.id) AS present,
             SUM(CASE WHEN p.total_pages > 0 AND p.current_page >= p.total_pages
                      THEN 1 ELSE 0 END) AS read_count,
             MAX(p.updated_at) AS last_read_at,
             (SELECT i2.payload FROM arc_item_rows ai2
                JOIN issue_rows i2 ON i2.id = ai2.issue_id
               WHERE ai2.arc_id = a.id
               ORDER BY ai2.position ASC LIMIT 1) AS first_issue_payload
      FROM arc_rows a
      LEFT JOIN arc_item_rows ai ON ai.arc_id = a.id
      LEFT JOIN issue_rows i ON i.id = ai.issue_id
      LEFT JOIN progress_rows p ON p.comic_id = i.id
      GROUP BY a.id
      ORDER BY (a.self_contained = 1) DESC, a.name ASC
    ''', readsFrom: {arcRows, arcItemRows, issueRows, progressRows});
    return query.watch().map((rows) => rows.map((r) {
          final sc = r.read<int?>('self_contained');
          final imageUrl = r.read<String>('image_url');
          final lastRead = r.read<String?>('last_read_at');
          String coverUrl = imageUrl;
          if (coverUrl.isEmpty) {
            final firstPayload = r.read<String?>('first_issue_payload');
            if (firstPayload != null) {
              try {
                final m = jsonDecode(firstPayload) as Map<String, dynamic>;
                coverUrl = m['cover_url'] as String? ?? '';
              } catch (_) {
                // Malformed issue payload: leave coverUrl at '' rather than
                // erroring the whole arcs stream.
              }
            }
          }
          return Arc(
            id: r.read<String>('id'),
            name: r.read<String>('name'),
            imageUrl: imageUrl,
            selfContained: sc == null ? null : sc != 0,
            total: r.read<int>('total'),
            present: r.read<int>('present'),
            source: r.read<String>('source'),
            publisher: r.read<String>('publisher'),
            startYear: r.read<int>('start_year'),
            endYear: r.read<int>('end_year'),
            read: r.read<int>('read_count'),
            coverUrl: coverUrl,
            lastReadAt: lastRead == null ? null : DateTime.tryParse(lastRead),
            description: r.read<String>('description'),
          );
        }).toList());
  }

  /// An arc's issues in reading order, as SeriesIssue (joined to progress so the
  /// reader opens at the right page). Only issues present in the mirror appear.
  ///
  /// NOTE: unlike the brief's assumed schema, `issue_rows` has no discrete
  /// `name`/`number`/`cover_url` columns — issue data lives in a JSON
  /// `payload` column (see [_upsertSeriesFromMap]), the same shape
  /// [watchSeriesDetail] decodes. This mirrors that pattern instead of
  /// selecting columns that don't exist. Status also uses 'completed' (not
  /// 'read') to match [SeriesIssue.status]'s convention used app-wide
  /// (issue_list_view.dart, issue_grid_view.dart, series_action_sheet.dart).
  Stream<List<SeriesIssue>> watchArcIssues(String arcId) {
    final query = customSelect('''
      SELECT i.payload AS issue_payload, i.series_id AS series_id,
             json_extract(s.payload, '\$.name') AS series_name,
             p.current_page AS current_page, p.total_pages AS total_pages
      FROM arc_item_rows ai
      JOIN issue_rows i ON i.id = ai.issue_id
      LEFT JOIN series_rows s ON s.id = i.series_id
      LEFT JOIN progress_rows p ON p.comic_id = i.id
      WHERE ai.arc_id = ?
      ORDER BY ai.position ASC
    ''', variables: [
      Variable.withString(arcId)
    ], readsFrom: {
      arcItemRows,
      issueRows,
      seriesRows,
      progressRows
    });
    return query.watch().map((rows) => rows.map((r) {
          final m = jsonDecode(r.read<String>('issue_payload'))
              as Map<String, dynamic>;
          m['series_id'] = r.read<String>('series_id');
          m['series_name'] = r.read<String?>('series_name');
          final cp = r.read<int?>('current_page');
          final tp = r.read<int?>('total_pages');
          if (cp != null && tp != null) {
            m['current_page'] = cp;
            m['total_pages'] = tp;
            // cp==0 with a progress row (e.g. total_pages recorded on open,
            // before any page turn) is still unread, not in_progress.
            m['status'] = (tp > 0 && cp >= tp)
                ? 'completed'
                : (cp > 0 ? 'in_progress' : 'unread');
          } else {
            m['status'] = 'unread';
            m.remove('current_page');
            m.remove('total_pages');
          }
          return SeriesIssue.fromJson(m);
        }).toList());
  }

  /// Local-first queue write: replace the queue row and its ordered membership.
  Future<void> upsertQueueLocal(ReadingQueue q) async {
    await transaction(() async {
      await into(queueRows).insertOnConflictUpdate(QueueRowsCompanion.insert(
        id: q.id,
        name: q.name,
        icon: Value(q.icon),
        color: Value(q.color),
        position: Value(q.position),
        createdAt: serverTimestamp(q.createdAt),
        updatedAt: serverTimestamp(q.updatedAt),
      ));
      await (delete(queueItemRows)..where((t) => t.queueId.equals(q.id))).go();
      var pos = 0;
      for (final sid in q.seriesIds) {
        await into(queueItemRows).insert(QueueItemRowsCompanion.insert(
          queueId: q.id,
          seriesId: sid,
          position: pos++,
        ));
      }
    });
  }

  Future<void> deleteQueueLocal(String id) async {
    await transaction(() async {
      await (delete(queueItemRows)..where((t) => t.queueId.equals(id))).go();
      await (delete(queueRows)..where((t) => t.id.equals(id))).go();
    });
  }

  /// If [comicId]'s series is now fully read, remove that series from every
  /// queue containing it. Returns the updated queues (empty when nothing
  /// changed) so the caller can enqueue outbox snapshots.
  Future<List<ReadingQueue>> autoRemoveOnComplete(String comicId) async {
    final issue = await (select(issueRows)
          ..where((t) => t.id.equals(comicId)))
        .getSingleOrNull();
    final seriesId = issue?.seriesId;
    if (seriesId == null) return [];

    final counts = await customSelect('''
      SELECT
        (SELECT COUNT(*) FROM issue_rows WHERE series_id = ?1) AS total,
        (SELECT COUNT(*) FROM issue_rows i
           JOIN progress_rows p ON p.comic_id = i.id
          WHERE i.series_id = ?1
            AND p.total_pages > 0
            AND p.current_page >= p.total_pages) AS read
    ''', variables: [Variable.withString(seriesId)], readsFrom: {
      issueRows,
      progressRows
    }).getSingle();

    final total = counts.read<int>('total');
    final read = counts.read<int>('read');
    if (total == 0 || read < total) return [];

    final queues = await watchQueues().first;
    final affected =
        queues.where((q) => q.seriesIds.contains(seriesId)).toList();
    final updated = <ReadingQueue>[];
    for (final q in affected) {
      final next = q.copyWith(
        seriesIds: q.seriesIds.where((s) => s != seriesId).toList(),
        updatedAt: DateTime.now(),
      );
      await upsertQueueLocal(next);
      updated.add(next);
    }
    return updated;
  }
}
