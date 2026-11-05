import 'package:comic_reader_app/models/scan_status.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/connectivity_provider.dart';
import 'package:comic_reader_app/providers/library_provider.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/screens/library_screen.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/mirror/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://t', deviceId: 'd');
  ScanStatus status = const ScanStatus();
  @override
  Future<ScanStatus> getScanStatus() async => status;
}

class _FakeSync implements SyncEngine {
  int calls = 0;
  @override
  Future<void> sync() async => calls++;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> pump(WidgetTester t, _FakeApi api, _FakeSync sync) async {
  t.view.physicalSize = const Size(1366, 1024);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      connectivityProvider.overrideWith(_Online.new),
      isCustomSourceProvider.overrideWithValue(true),
      apiClientProvider.overrideWithValue(api),
      syncEngineProvider.overrideWithValue(sync),
      libraryProvider.overrideWith((ref) => Stream.value(<Series>[])),
    ],
    child: const MaterialApp(home: LibraryScreen()),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('empty library while scanning shows progress', (t) async {
    final api = _FakeApi()
      ..status = const ScanStatus(isScanning: true, scanned: 120, total: 583);
    await pump(t, api, _FakeSync());
    expect(find.text('Scanning your library…'), findsOneWidget);
    expect(find.text('120 of 583'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('scan finishing triggers a mirror sync', (t) async {
    final api = _FakeApi()
      ..status = const ScanStatus(isScanning: true, scanned: 1, total: 5);
    final sync = _FakeSync();
    await pump(t, api, sync);
    expect(sync.calls, 0);
    api.status = const ScanStatus();
    await t.pump(const Duration(seconds: 2));
    await t.pump(const Duration(milliseconds: 100));
    expect(sync.calls, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('scan finished with zero series shows empty state', (t) async {
    final api = _FakeApi()
      ..status = const ScanStatus(isScanning: true, scanned: 0, total: 0);
    await pump(t, api, _FakeSync());
    expect(find.text('Scanning your library…'), findsOneWidget);
    expect(find.textContaining(' of '), findsNothing);
    api.status = const ScanStatus();
    await t.pump(const Duration(seconds: 2));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('No comics found'), findsOneWidget);
    expect(find.text('Scanning your library…'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
