import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:comic_reader_app/widgets/series_action_sheet.dart';
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
  @override
  Future<void> batchUpdateProgress(List<Map<String, dynamic>> items) async =>
      calls.add('read ${items.single['current_page']}/${items.single['total_pages']}');
  @override
  Future<void> batchDeleteProgress(List<String> comicIds) async =>
      calls.add('unread');
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
}
