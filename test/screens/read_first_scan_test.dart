import 'package:comic_reader_app/models/scan_status.dart';
import 'package:comic_reader_app/providers/connectivity_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/read_tab_provider.dart';
import 'package:comic_reader_app/providers/scan_status_provider.dart';
import 'package:comic_reader_app/screens/read_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _FixedScan extends ScanStatusNotifier {
  _FixedScan(this.fixed);
  final ScanStatusState fixed;
  @override
  ScanStatusState build() => fixed;
}

Future<void> _pump(WidgetTester t, ScanStatusState scan) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      connectivityProvider.overrideWith(_Online.new),
      isCustomSourceProvider.overrideWithValue(true),
      scanStatusProvider.overrideWith(() => _FixedScan(scan)),
      readTabProvider.overrideWith((ref) => Stream.value(
          const ReadTabData(continueReading: [], recentSeries: []))),
    ],
    child: const MaterialApp(home: ReadScreen()),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('empty Read tab during the first scan shows its progress',
      (t) async {
    await _pump(
        t,
        const ScanStatusState(
            phase: ScanPhase.scanning,
            status: ScanStatus(isScanning: true, scanned: 3, total: 10)));
    expect(find.text('Scanning your library…'), findsOneWidget);
    expect(find.text('3 of 10'), findsOneWidget);
    expect(find.textContaining('No comics in progress'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('done but not yet synced shows the neutral loading text',
      (t) async {
    await _pump(t, const ScanStatusState(phase: ScanPhase.done));
    expect(find.text('Loading your library…'), findsOneWidget);
    expect(find.textContaining('No comics in progress'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('idle shows the usual empty state', (t) async {
    await _pump(t, const ScanStatusState());
    expect(find.textContaining('No comics in progress'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
