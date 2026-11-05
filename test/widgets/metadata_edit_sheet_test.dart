import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/metadata_editor.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:comic_reader_app/services/sync_queue.dart';
import 'package:comic_reader_app/widgets/metadata_edit_sheet.dart';

// ---------------------------------------------------------------------------
// Recording fake — overrides save methods; real deps are never called.
// ---------------------------------------------------------------------------

class _RecordingEditor extends MetadataEditor {
  _RecordingEditor({
    required super.db,
    required super.queue,
  }) : super(
          client: ApiClient(baseUrl: 'http://stub', deviceId: 'stub'),
        );

  String? lastIssueSaveId;
  Map<String, dynamic>? lastIssueSaveFields;
  String? lastSeriesSaveId;
  Map<String, dynamic>? lastSeriesSaveFields;

  @override
  Future<void> saveIssue(String comicId, Map<String, dynamic> fields) async {
    lastIssueSaveId = comicId;
    lastIssueSaveFields = fields;
  }

  @override
  Future<void> saveSeries(String seriesId, Map<String, dynamic> fields) async {
    lastSeriesSaveId = seriesId;
    lastSeriesSaveFields = fields;
  }
}

// ---------------------------------------------------------------------------
// Model helpers
// ---------------------------------------------------------------------------

SeriesIssue _issue({
  String id = 'i1',
  String name = 'a.cbz',
  String? title = 'Old Title',
  String? format = 'tpb',
  String? number = '1',
  String? writer = 'Writer A',
  String? summary = 'Summary text',
}) =>
    SeriesIssue(
      id: id,
      name: name,
      number: number,
      coverUrl: '/comics/$id/cover',
      status: 'unread',
      currentPage: null,
      totalPages: null,
      title: title,
      format: format,
      writer: writer,
      summary: summary,
    );

SeriesDetail _series({
  String id = 's1',
  String name = 'Old Name',
  String? publisher = 'Old Publisher',
  String? writer = 'Old Writer',
  int? year = 2000,
  List<String> genres = const ['Action'],
  String? description = 'Old Desc',
}) =>
    SeriesDetail(
      id: id,
      name: name,
      folderPath: '/comics/$id',
      issueCount: 1,
      readCount: 0,
      coverUrl: '/library/$id/cover',
      publisher: publisher,
      writer: writer,
      year: year,
      genres: genres,
      description: description,
      issues: const [],
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tmp;
  late MirrorDatabase db;
  late SyncQueue queue;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('metadata_edit_sheet_test');
    db = MirrorDatabase(NativeDatabase.memory());
    queue = SyncQueue(queuePath: '${tmp.path}/queue.json');
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Pumps the sheet directly (bypasses showModalBottomSheet) so we can test
  /// the form widget in isolation with a recording editor override.
  Future<void> pumpSheet(
    WidgetTester tester,
    _RecordingEditor recording, {
    SeriesDetail? series,
    SeriesIssue? issue,
    String seriesId = 's1',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          metadataEditorProvider.overrideWithValue(recording),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MetadataEditSheet(
              series: series,
              issue: issue,
              seriesId: seriesId,
              accent: Colors.blue,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('issue mode: fields prefilled and only changed fields saved',
      (tester) async {
    final recording = _RecordingEditor(db: db, queue: queue);
    final iss = _issue();
    await pumpSheet(tester, recording, issue: iss, seriesId: 's1');

    // Title field prefilled
    expect(find.widgetWithText(TextFormField, 'Old Title'), findsOneWidget);
    // Format shows TPB label
    expect(find.text('Trade Paperback'), findsOneWidget);
    // Writer prefilled
    expect(find.widgetWithText(TextFormField, 'Writer A'), findsOneWidget);

    // Edit only the title
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Old Title'), 'New Title');
    await tester.pump();

    // Tap Save
    await tester.tap(find.text('Save'));
    await tester.pump();

    // Only the changed field is sent
    expect(recording.lastIssueSaveId, 'i1');
    expect(recording.lastIssueSaveFields, {'title': 'New Title'});
    // format/writer/number/summary were untouched — not included
    expect(recording.lastIssueSaveFields!.containsKey('format'), isFalse);
    expect(recording.lastIssueSaveFields!.containsKey('writer'), isFalse);
  });

  testWidgets('series mode: series fields render', (tester) async {
    final recording = _RecordingEditor(db: db, queue: queue);
    final s = _series();
    await pumpSheet(tester, recording, series: s, seriesId: 's1');

    // Name, publisher, writer, year, genres, description fields render
    expect(find.widgetWithText(TextFormField, 'Old Name'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Old Publisher'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Old Writer'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '2000'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Action'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Old Desc'), findsOneWidget);
  });

  testWidgets('PDF caption shown for .pdf issue', (tester) async {
    final recording = _RecordingEditor(db: db, queue: queue);
    final iss = _issue(name: 'comic.PDF');
    await pumpSheet(tester, recording, issue: iss, seriesId: 's1');

    expect(
      find.textContaining('PDF: metadata is stored in the library database'),
      findsOneWidget,
    );
  });

  testWidgets('PDF caption not shown for .cbz issue', (tester) async {
    final recording = _RecordingEditor(db: db, queue: queue);
    await pumpSheet(tester, recording, issue: _issue(), seriesId: 's1');

    expect(
      find.textContaining('PDF: metadata is stored'),
      findsNothing,
    );
  });

  testWidgets('no-op save: no SnackBar when no fields changed', (tester) async {
    final recording = _RecordingEditor(db: db, queue: queue);
    final iss = _issue();
    await pumpSheet(tester, recording, issue: iss, seriesId: 's1');

    // Tap Save without editing any fields
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // No saveIssue call should have been made
    expect(recording.lastIssueSaveId, isNull);
    expect(recording.lastIssueSaveFields, isNull);

    // No 'Metadata saved' SnackBar should appear
    expect(find.text('Metadata saved'), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // I1 — format/year null-safety contract
  // ---------------------------------------------------------------------------

  testWidgets('I1: clearing format sends empty string, not null', (tester) async {
    final recording = _RecordingEditor(db: db, queue: queue);
    // Issue starts with format = 'tpb'
    final iss = _issue(format: 'tpb');
    await pumpSheet(tester, recording, issue: iss, seriesId: 's1');

    // Open the format dropdown and pick "Not set" (empty string sentinel)
    await tester.tap(find.text('Trade Paperback'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not set'));
    await tester.pumpAndSettle();

    // Save
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(recording.lastIssueSaveId, 'i1');
    // format must be '' (empty string), never null
    expect(recording.lastIssueSaveFields!['format'], '');
    expect(recording.lastIssueSaveFields!.containsKey('format'), isTrue);
  });

  testWidgets('I1: clearing year omits key from save map', (tester) async {
    final recording = _RecordingEditor(db: db, queue: queue);
    // Series starts with year = 2000, publisher = 'Old Publisher'
    final s = _series(year: 2000);
    await pumpSheet(tester, recording, series: s, seriesId: 's1');

    // Clear the year field AND change publisher so fields is non-empty
    await tester.enterText(find.widgetWithText(TextFormField, '2000'), '');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Old Publisher'), 'New Publisher');
    await tester.pump();

    // Save
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(recording.lastSeriesSaveId, 's1');
    // year key must be absent when cleared (omit entirely — no clear semantics)
    expect(recording.lastSeriesSaveFields!.containsKey('year'), isFalse);
    // publisher change is included
    expect(recording.lastSeriesSaveFields!['publisher'], 'New Publisher');
  });

  testWidgets('I1: non-numeric year input omits year key from save map',
      (tester) async {
    final recording = _RecordingEditor(db: db, queue: queue);
    // Series starts with year = 2000, publisher = 'Old Publisher'
    final s = _series(year: 2000);
    await pumpSheet(tester, recording, series: s, seriesId: 's1');

    // Enter non-numeric text into year field AND change publisher so fields is non-empty
    await tester.enterText(find.widgetWithText(TextFormField, '2000'), 'abc');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Old Publisher'), 'New Publisher');
    await tester.pump();

    // Save
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(recording.lastSeriesSaveId, 's1');
    // year key must be absent when parse fails (int.tryParse returns null)
    expect(recording.lastSeriesSaveFields!.containsKey('year'), isFalse);
    // publisher change is included
    expect(recording.lastSeriesSaveFields!['publisher'], 'New Publisher');
  });
}
