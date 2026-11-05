import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:comic_reader_app/services/mirror/mirror_database.dart';

void main() {
  late MirrorDatabase db;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() => db = MirrorDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('inserts and reads a series row', () async {
    await db.into(db.seriesRows).insert(SeriesRowsCompanion.insert(
          id: 's1',
          updatedAt: '2026-01-01T00:00:00Z',
          payload: '{"id":"s1","name":"Batman"}',
        ));
    final rows = await db.select(db.seriesRows).get();
    expect(rows.single.id, 's1');
    expect(rows.single.coverSyncedAt, null);
  });

  test('serverTimestamp formats RFC3339 UTC', () {
    expect(serverTimestamp(DateTime.utc(2026, 6, 9, 8, 5, 3)),
        '2026-06-09T08:05:03Z');
  });

  test('watchArcs tolerates a malformed issue payload', () async {
    await db.into(db.seriesRows).insert(SeriesRowsCompanion.insert(
          id: 's1',
          updatedAt: '2026-01-01T00:00:00Z',
          payload: '{"id":"s1","name":"Batman"}',
        ));
    await db.into(db.issueRows).insert(IssueRowsCompanion.insert(
          id: 'i1',
          seriesId: 's1',
          position: 0,
          payload: 'not valid json{',
        ));
    await db.into(db.arcRows).insert(ArcRowsCompanion.insert(
          id: 'a1',
          name: 'Arc',
        ));
    await db.into(db.arcItemRows).insert(ArcItemRowsCompanion.insert(
          arcId: 'a1',
          issueId: 'i1',
          position: 0,
        ));

    final arcs = await db.watchArcs().first;

    expect(arcs.single.coverUrl, '');
  });

  _migrationTests();
}

/// Reproduces a device upgrading straight from schema v1-3 to v6: arc_rows
/// doesn't exist yet, so the `from < 4` step creates it from the *current*
/// table definition (which already has source/publisher/start_year/end_year).
/// The `from < 6` step must not then try to add those columns again.
void _seedPreV4Schema(sqlite3.Database raw) {
  raw.execute('''
    CREATE TABLE series_rows (
      id TEXT NOT NULL PRIMARY KEY,
      updated_at TEXT NOT NULL,
      cover_synced_at TEXT,
      payload TEXT NOT NULL
    );
    CREATE TABLE issue_rows (
      id TEXT NOT NULL PRIMARY KEY,
      series_id TEXT NOT NULL,
      position INTEGER NOT NULL,
      payload TEXT NOT NULL
    );
    CREATE INDEX idx_issue_series ON issue_rows (series_id);
    CREATE TABLE progress_rows (
      comic_id TEXT NOT NULL PRIMARY KEY,
      current_page INTEGER NOT NULL,
      total_pages INTEGER NOT NULL,
      updated_at TEXT NOT NULL,
      chapters TEXT
    );
    CREATE TABLE sync_state (
      key TEXT NOT NULL PRIMARY KEY,
      value TEXT NOT NULL
    );
    CREATE TABLE queue_rows (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      icon TEXT NOT NULL DEFAULT 'bookmark',
      color TEXT NOT NULL DEFAULT '#FFB74D',
      position INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE queue_item_rows (
      queue_id TEXT NOT NULL,
      series_id TEXT NOT NULL,
      position INTEGER NOT NULL,
      PRIMARY KEY (queue_id, series_id)
    );
    CREATE INDEX idx_queue_item_queue ON queue_item_rows (queue_id);
    PRAGMA user_version = 3;
  ''');
}

void _migrationTests() {
  group('migration from schema v1-3', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('mirror_migration_test');
      dbPath = '${tempDir.path}/mirror.sqlite';
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('upgrading from v6 adds arc description and resets the watermark',
        () async {
      final seed = sqlite3.sqlite3.open(dbPath);
      _seedPreV4Schema(seed);
      seed.execute('''
        CREATE TABLE arc_rows (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          image_url TEXT NOT NULL DEFAULT '',
          self_contained INTEGER,
          total INTEGER NOT NULL DEFAULT 0,
          source TEXT NOT NULL DEFAULT 'mylar',
          publisher TEXT NOT NULL DEFAULT '',
          start_year INTEGER NOT NULL DEFAULT 0,
          end_year INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE arc_item_rows (
          arc_id TEXT NOT NULL,
          issue_id TEXT NOT NULL,
          position INTEGER NOT NULL,
          PRIMARY KEY (arc_id, issue_id)
        );
        CREATE INDEX idx_arc_item_arc ON arc_item_rows (arc_id);
        INSERT INTO arc_rows (id, name) VALUES ('a1', 'Arc');
        INSERT INTO sync_state (key, value) VALUES ('last_server_time', '99');
        PRAGMA user_version = 6;
      ''');
      seed.close();

      final upgraded = MirrorDatabase(NativeDatabase(File(dbPath)));
      addTearDown(upgraded.close);

      final arcs = await upgraded.watchArcs().first;
      expect(arcs.single.description, '');
      expect(await upgraded.select(upgraded.syncState).get(), isEmpty);
    });

    test('upgrading straight to v6 does not fail on duplicate columns',
        () async {
      final seed = sqlite3.sqlite3.open(dbPath);
      _seedPreV4Schema(seed);
      seed.close();

      final upgraded = MirrorDatabase(NativeDatabase(File(dbPath)));
      addTearDown(upgraded.close);

      // Any query forces drift to run the pending migration.
      await upgraded.select(upgraded.syncState).get();

      final cols = await upgraded
          .customSelect("SELECT name FROM pragma_table_info('arc_rows')")
          .get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      expect(
        names,
        {
          'id',
          'name',
          'image_url',
          'self_contained',
          'total',
          'source',
          'publisher',
          'start_year',
          'end_year',
          'description',
        },
      );
    });
  });
}
