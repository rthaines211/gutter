import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/cache_providers.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:comic_reader_app/services/sync_queue.dart';
import 'package:comic_reader_app/widgets/series_action_sheet.dart';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://localhost:0', deviceId: 'test');
  final calls = <String>[];
  bool offline = false;
  @override
  Future<void> batchUpdateProgress(List<Map<String, dynamic>> items) async =>
      offline ? throw const SocketException('offline') : calls.add('read ${items.single['current_page']}/${items.single['total_pages']}');
  @override
  Future<void> batchDeleteProgress(List<String> comicIds) async =>
      offline ? throw const SocketException('offline') : calls.add('unread');
}

Future<int?> _page(MirrorDatabase db, String id) async {
  final rows = await db.customSelect(
      'SELECT current_page FROM progress_rows WHERE comic_id = ?',
      variables: [Variable.withString(id)]).get();
  return rows.isEmpty ? null : rows.first.read<int>('current_page');
}

void main() {
  testWidgets('toggleIssueRead marks read at once; Undo restores the page',
      (t) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = MirrorDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _FakeApi();
    const issue = SeriesIssue(
      id: 'c19', name: 'Ultimates 19.cbz', number: '19', coverUrl: '',
      status: 'in_progress', currentPage: 8, totalPages: 22,
    );
    await t.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        syncEngineProvider.overrideWithValue(null),
        mirrorDbProvider.overrideWithValue(db),
        apiClientProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => toggleIssueRead(context, ref, issue),
              child: const Text('Mark read'),
            ),
          ),
        ),
      ),
    ));

    await t.tap(find.text('Mark read'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    expect(await t.runAsync(() => _page(db, 'c19')), 22);
    expect(api.calls, ['read 22/22']);
    expect(find.text('Marked #19 read'), findsOneWidget);

    await t.pump(const Duration(milliseconds: 500)); // snackbar slides in
    await t.tap(find.text('Undo'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    expect(await t.runAsync(() => _page(db, 'c19')), 8,
        reason: 'undo puts the reader back on page 9, not unread');
    expect(api.calls.last, 'read 8/22');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('offline, the toggle stays local and waits in the outbox',
      (t) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = MirrorDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _FakeApi()..offline = true;
    final dir = Directory.systemTemp.createTempSync('outbox');
    addTearDown(() => dir.deleteSync(recursive: true));
    final outbox = SyncQueue(queuePath: '${dir.path}/q.json');
    const issue = SeriesIssue(
      id: 'c19', name: 'Ultimates 19.cbz', number: '19', coverUrl: '',
      status: 'in_progress', currentPage: 8, totalPages: 22,
    );
    await t.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        syncEngineProvider.overrideWithValue(null),
        syncQueueProvider.overrideWithValue(outbox),
        mirrorDbProvider.overrideWithValue(db),
        apiClientProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => toggleIssueRead(context, ref, issue),
              child: const Text('Mark read'),
            ),
          ),
        ),
      ),
    ));

    await t.tap(find.text('Mark read'));
    // The push runs in the background: let its file I/O and microtasks
    // interleave until it lands.
    for (var k = 0; k < 10; k++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump();
    }
    expect(await t.runAsync(() => _page(db, 'c19')), 22);
    final queued = await t.runAsync(outbox.readAll);
    expect(queued!.single['type'], 'progress');
    expect(queued.single['payload'], {'comic_id': 'c19', 'current_page': 22, 'total_pages': 22});
    await t.pumpWidget(const SizedBox());
  });
}
