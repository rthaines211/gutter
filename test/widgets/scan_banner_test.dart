import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/models/review_item.dart';
import 'package:comic_reader_app/providers/navigation_provider.dart';
import 'package:comic_reader_app/providers/review_provider.dart';
import 'package:comic_reader_app/providers/scan_status_provider.dart';
import 'package:comic_reader_app/widgets/scan_banner.dart';

class _FakeScan extends ScanStatusNotifier {
  @override
  ScanStatusState build() => const ScanStatusState();
  void finish() => state = const ScanStatusState(phase: ScanPhase.done);
  @override
  void dismiss() => state = const ScanStatusState();
}

int _queueSize = 0;

class _FakeQueue extends ReviewQueueNotifier {
  @override
  Future<ReviewQueueState> build() async => ReviewQueueState(
        items: [
          for (var i = 0; i < _queueSize; i++)
            ReviewItem(
              seriesId: '$i', name: 'n$i', state: '', localCoverUrl: '',
              guessVolumeId: '', guessSource: '', guessName: '',
              guessPublisher: '', guessYear: '', guessIssueCount: 0,
              guessCoverUrl: '',
            ),
        ],
      );
}

Future<ProviderContainer> _pump(WidgetTester t, int n) async {
  _queueSize = n;
  await t.pumpWidget(ProviderScope(
    overrides: [
        gutterFeaturesProvider.overrideWithValue(true),
      scanStatusProvider.overrideWith(_FakeScan.new),
      reviewQueueProvider.overrideWith(_FakeQueue.new),
    ],
    child: const MaterialApp(home: Scaffold(body: ScanBanner())),
  ));
  final c = ProviderScope.containerOf(t.element(find.byType(ScanBanner)));
  (c.read(scanStatusProvider.notifier) as _FakeScan).finish();
  await t.pump();
  await t.pump();
  await t.pump();
  return c;
}

void main() {
  testWidgets('done with reviews shows link and does not auto-dismiss',
      (t) async {
    final c = await _pump(t, 2);
    expect(find.text('2 need review'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
    expect(find.text('2 need review'), findsOneWidget);
    await t.tap(find.text('Review'));
    expect(c.read(navigationProvider), NavDestination.review);
  });

  testWidgets('done with zero reviews auto-dismisses', (t) async {
    await _pump(t, 0);
    expect(find.textContaining('Scan complete'), findsOneWidget);
    expect(find.textContaining('need review'), findsNothing);
    await t.pump(const Duration(seconds: 4));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Scan complete'), findsNothing);
  });

  testWidgets('second scan with zero reviews does not show stale count',
      (t) async {
    final c = await _pump(t, 2);
    expect(find.text('2 need review'), findsOneWidget);
    await t.tap(find.text('Review')); // navigates + dismisses
    await t.pump();
    _queueSize = 0;
    (c.read(scanStatusProvider.notifier) as _FakeScan).finish();
    await t.pump();
    await t.pump();
    await t.pump();
    expect(find.textContaining('Scan complete'), findsOneWidget);
    expect(find.textContaining('need review'), findsNothing);
    await t.pump(const Duration(seconds: 4));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Scan complete'), findsNothing);
  });
}
