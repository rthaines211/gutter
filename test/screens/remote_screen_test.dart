import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/providers/remote_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/screens/remote_screen.dart';
import 'package:comic_reader_app/services/remote_session.dart';

/// Records commands instead of hitting the network, so tests can assert how
/// many times (and with what payload) the screen calls sendCommand.
class _FakeRemoteSession extends RemoteSession {
  _FakeRemoteSession() : super(baseUrl: 'http://test');

  final List<({String type, int? page})> calls = [];

  /// Flip to false to simulate the relay's 409 "no reader connected".
  bool accepts = true;

  @override
  Future<bool> sendCommand(String type, {int? page}) async {
    calls.add((type: type, page: page));
    return accepts;
  }
}

void main() {
  late StreamController<RemoteSnapshot?> snapshots;
  late StreamController<bool> connected;
  late _FakeRemoteSession session;

  Widget build() => ProviderScope(
        overrides: [
          imageHeadersProvider.overrideWithValue(const {}),
          remoteSnapshotProvider.overrideWith((ref) => snapshots.stream),
          remoteConnectedProvider.overrideWith((ref) => connected.stream),
          remoteSessionProvider.overrideWithValue(session),
          // Only for pageUrl on the thumbnail; the real one needs prefs and
          // an active source, neither of which this screen cares about.
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test', deviceId: 'test'),
          ),
        ],
        child: const MaterialApp(home: RemoteScreen()),
      );

  setUp(() {
    snapshots = StreamController<RemoteSnapshot?>.broadcast();
    connected = StreamController<bool>.broadcast();
    session = _FakeRemoteSession();
  });
  tearDown(() {
    snapshots.close();
    connected.close();
  });

  RemoteSnapshot snap({
    int page = 4,
    int total = 20,
    String mode = 'page',
    bool bookmarked = false,
  }) =>
      RemoteSnapshot(
        comicId: 'abc',
        series: 'Saga',
        page: page,
        totalPages: total,
        bookmarked: bookmarked,
        hasNextIssue: true,
        readingMode: mode,
      );

  testWidgets('shows the empty state before any snapshot', (tester) async {
    await tester.pumpWidget(build());
    await tester.pump();
    expect(find.text('No iPad reading'), findsOneWidget);
  });

  testWidgets('shows series and page position', (tester) async {
    await tester.pumpWidget(build());
    snapshots.add(snap());
    await tester.pump();
    expect(find.text('Saga'), findsOneWidget);
    expect(find.text('5 / 20'), findsOneWidget);
  });

  testWidgets('explains that scroll mode is unsupported', (tester) async {
    await tester.pumpWidget(build());
    snapshots.add(snap(mode: 'scroll'));
    await tester.pump();
    expect(find.textContaining('Scroll mode'), findsOneWidget);
    // The whole point of the scroll-mode branch is hiding these controls —
    // a regression that dropped the wrapping `if (!scrollMode)` but kept
    // the explanatory text would still pass the assertion above.
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });

  // The bool sendCommand returns was discarded at every call site, so a 409
  // looked exactly like success: the button clicked and nothing happened.
  testWidgets('a rejected command surfaces to the user', (tester) async {
    session.accepts = false;
    await tester.pumpWidget(build());
    snapshots.add(snap());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(SnackBar, 'No iPad reading'), findsOneWidget);
  });

  testWidgets('an accepted command stays silent', (tester) async {
    await tester.pumpWidget(build());
    snapshots.add(snap());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('dragging the slider sends exactly one goto command',
      (tester) async {
    await tester.pumpWidget(build());
    snapshots.add(snap());
    await tester.pump();

    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await tester.pump();

    final gotoCalls = session.calls.where((c) => c.type == 'goto').toList();
    expect(gotoCalls, hasLength(1));
  });

  // The hub clears its snapshot when the last reader leaves, which only helps
  // a phone that connects afterwards. One already streaming got no bytes at
  // all and kept rendering a frozen page count from a closed reader.
  testWidgets('reader_gone returns the screen to the empty state',
      (tester) async {
    await tester.pumpWidget(build());
    snapshots.add(snap());
    await tester.pump();
    expect(find.text('Saga'), findsOneWidget);

    snapshots.add(null);
    await tester.pump();
    expect(find.text('No iPad reading'), findsOneWidget);
    expect(find.text('Saga'), findsNothing);
  });

  // A lost connection and a closed reader are different failures: one means
  // what is on screen may be stale, the other that there is nothing to show.
  testWidgets('a lost connection shows a banner over the last snapshot',
      (tester) async {
    await tester.pumpWidget(build());
    connected.add(true);
    snapshots.add(snap());
    await tester.pump();
    expect(find.textContaining('Reconnecting'), findsNothing);

    connected.add(false);
    await tester.pump();
    expect(find.textContaining('Reconnecting'), findsOneWidget);
    // The snapshot stays visible — stale under a banner is honest.
    expect(find.text('Saga'), findsOneWidget);
  });

  // The reader's end card sits at page == pageCount, one past the last page.
  // Rendering it naively read "21 / 20" and asked the backend for a page that
  // does not exist.
  testWidgets('the end card reads total / total, not one past it',
      (tester) async {
    await tester.pumpWidget(build());
    connected.add(true);
    snapshots.add(snap(page: 20, total: 20));
    await tester.pump();
    expect(find.text('20 / 20'), findsOneWidget);
    expect(find.text('21 / 20'), findsNothing);
    expect(find.textContaining('End of issue'), findsOneWidget);
  });

  // Mid-drag the preview is debounced, so a fast scrub across the issue
  // fetches where the thumb settles rather than every division it crossed.
  // Release is immediate, which is why this drives the gesture by hand.
  testWidgets('a mid-drag scrub previews only after the debounce',
      (tester) async {
    await tester.pumpWidget(build());
    connected.add(true);
    snapshots.add(snap(page: 4, total: 20));
    await tester.pump();
    expect(find.text('5 / 20'), findsOneWidget);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Slider)));
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();
    // Thumb has moved, but the thumbnail and counter still show the iPad.
    expect(find.text('5 / 20'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('5 / 20'), findsNothing);

    await gesture.up();
    await tester.pump();
  });

  // A goto the relay rejects means the iPad will never reach that page, so
  // leaving the preview up would strand the phone on a page nobody is showing.
  testWidgets('a rejected goto abandons the preview', (tester) async {
    session.accepts = false;
    await tester.pumpWidget(build());
    connected.add(true);
    snapshots.add(snap(page: 4, total: 20));
    await tester.pump();

    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await tester.pump();
    await tester.pump();
    expect(find.text('5 / 20'), findsOneWidget);
  });
}
