import 'package:comic_reader_app/models/download_item.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/cache_providers.dart';
import 'package:comic_reader_app/providers/connectivity_provider.dart';
import 'package:comic_reader_app/providers/download_provider.dart';
import 'package:comic_reader_app/providers/library_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/screens/downloads_screen.dart';
import 'package:comic_reader_app/services/download_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

DownloadItem _done(String comic) => DownloadItem(
    comicId: comic,
    sourceId: 'default',
    seriesId: 's1',
    seriesName: 'Ghost',
    comicName: 'Ghost #$comic',
    totalBytes: 100 << 20,
    downloadedBytes: 100 << 20,
    status: DownloadStatus.completed,
    addedAt: DateTime(2026));

SeriesIssue _issue(String id, String status) =>
    SeriesIssue(id: id, name: 'Ghost #$id', coverUrl: '', status: status,
        currentPage: 4, totalPages: 20);

final _detail = SeriesDetail(
  id: 's1',
  name: 'Ghost',
  folderPath: '',
  issueCount: 4,
  readCount: 1,
  coverUrl: '',
  issues: [
    _issue('1', 'completed'),
    _issue('2', 'in_progress'),
    _issue('3', 'unread'),
    _issue('4', 'unread'),
  ],
);

Future<void> _pump(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      connectivityProvider.overrideWith(_Online.new),
      docsDirProvider.overrideWith((_) async => '/nonexistent'),
      downloadStateProvider.overrideWith((_) => Stream.value(
          DownloadManagerState(completed: [_done('1'), _done('2')]))),
      seriesDetailProvider.overrideWith((ref, id) => Stream.value(_detail)),
    ],
    child: const MaterialApp(home: DownloadsScreen()),
  ));
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('tablet: the first series opens in the panel with its actions',
      (t) async {
    await _pump(t, const Size(1100, 800));
    expect(find.text('2 issues in 1 series'), findsOneWidget);
    // Panel: issues 3 and 4 are neither finished nor on the device.
    expect(find.text('Get next 2'), findsOneWidget);
    expect(find.text('Remove read'), findsOneWidget);
    expect(find.text('2 of 4 issues downloaded · 200 MB'), findsOneWidget);
    expect(find.text('Read · 100 MB'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
  });

  testWidgets('phone: tapping a series pushes its page', (t) async {
    await _pump(t, const Size(600, 900));
    expect(find.text('Get next 2'), findsNothing);
    await t.tap(find.text('Ghost'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Get next 2'), findsOneWidget);
  });
}
