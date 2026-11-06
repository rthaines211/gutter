import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:comic_reader_app/models/sync_response.dart';
import 'package:comic_reader_app/services/mirror/cover_syncer.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';

void main() {
  late MirrorDatabase db;
  late Directory tempDir;
  final fetched = <String>[];

  MockClient mockCovers({int status = 200}) => MockClient((req) async {
        fetched.add(req.url.path);
        return http.Response.bytes([0xFF, 0xD8, 0xFF], status); // jpeg magic
      });

  Future<void> seed(String id, {String updatedAt = '2026-01-01T00:00:00Z'}) =>
      db.applySync(SyncResponse(
        serverTime: 1,
        series: [
          {
            'id': id,
            'name': id,
            'cover_url': '/library/$id/cover',
            'updated_at': updatedAt,
            'issues': [],
          }
        ],
        progress: [],
        seriesIds: [id],
        progressIds: [],
      ));

  setUp(() {
    db = MirrorDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('cover_test_');
    fetched.clear();
  });
  tearDown(() async {
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  test('overlapping sweeps share one run instead of re-downloading', () async {
    await seed('s1');
    final syncer = CoverSyncer(
        db: db, baseUrl: 'http://t', coversDir: tempDir.path, httpClient: mockCovers());

    await Future.wait([syncer.syncCovers(), syncer.syncCovers()]);

    expect(fetched, ['/library/s1/cover']);
  });

  test('cover syncer sends headers', () async {
    await seed('s1');
    String? auth;
    final syncer = CoverSyncer(
      db: db,
      baseUrl: 'http://t',
      coversDir: tempDir.path,
      headers: const {'Authorization': 'Bearer k'},
      httpClient: MockClient((req) async {
        auth = req.headers['Authorization'];
        return http.Response.bytes([0xFF, 0xD8, 0xFF], 200);
      }),
    );
    await syncer.syncCovers();
    expect(auth, 'Bearer k');
  });

  test('downloads missing covers and marks them synced', () async {
    await seed('s1');
    final syncer = CoverSyncer(
        db: db, baseUrl: 'http://t', coversDir: tempDir.path, httpClient: mockCovers());

    await syncer.syncCovers();

    expect(fetched, ['/library/s1/cover']);
    expect(File('${tempDir.path}/s1.jpg').existsSync(), true);

    // Second run: nothing to do.
    fetched.clear();
    await syncer.syncCovers();
    expect(fetched, isEmpty);
  });

  test('re-downloads when series updated_at changes', () async {
    await seed('s1');
    final syncer = CoverSyncer(
        db: db, baseUrl: 'http://t', coversDir: tempDir.path, httpClient: mockCovers());
    await syncer.syncCovers();

    await seed('s1', updatedAt: '2026-02-01T00:00:00Z');
    fetched.clear();
    await syncer.syncCovers();
    expect(fetched, ['/library/s1/cover']);
  });

  test('non-200 leaves cover unsynced for retry', () async {
    await seed('s1');
    final syncer = CoverSyncer(
        db: db, baseUrl: 'http://t', coversDir: tempDir.path,
        httpClient: mockCovers(status: 503));
    await syncer.syncCovers();
    expect(File('${tempDir.path}/s1.jpg').existsSync(), false);

    final rows = await db.listSeriesNeedingCovers();
    expect(rows.single.id, 's1');
  });

  test('malformed payload row is skipped; healthy row still downloads', () async {
    // Seed the healthy series via the normal helper (seriesIds prunes nothing
    // else yet because the bad row isn't in the DB yet).
    await seed('good');

    // Insert a corrupt row directly — applySync always writes valid JSON so
    // we bypass it here.
    await db.into(db.seriesRows).insert(
      SeriesRowsCompanion.insert(
        id: 'bad',
        updatedAt: '2026-01-01T00:00:00Z',
        payload: 'not json',
      ),
    );

    final syncer = CoverSyncer(
        db: db, baseUrl: 'http://t', coversDir: tempDir.path,
        httpClient: mockCovers());

    // Must not throw — the corrupt row is skipped.
    await syncer.syncCovers();

    // The healthy series' cover file was written.
    expect(File('${tempDir.path}/good.jpg').existsSync(), true);
  });
}
