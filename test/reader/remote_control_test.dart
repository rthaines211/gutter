import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/reader_settings.dart';
import 'package:comic_reader_app/providers/settings_provider.dart';
import 'package:comic_reader_app/screens/reader_screen.dart';

import 'fake_comic_server.dart';
import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory env;
  late FakeComicServer server;
  late StreamController<Map<String, dynamic>> commands;

  setUpAll(() async => env = await initReaderTestEnv());
  useComicServer(
    () => FakeComicServer()..comics['c1'] = List.filled(10, portraitPage),
    (s) => server = s,
    () => server,
  );

  setUp(() => commands = StreamController<Map<String, dynamic>>.broadcast());
  tearDown(() => commands.close());

  // fitScreen auto-zooms a portrait page on a landscape viewport, giving a
  // multi-step PanSequence where the first advance pans instead of turning.
  // fitHeight is identity scale, so one 'next' turns one page.
  void useSingleStepFit() => server.settings = {'page_fit': 'fitHeight'};

  testWidgets('remote next advances the page', (tester) async {
    useSingleStepFit();
    final h = await pumpReader(
      tester,
      server: server,
      tempDir: env,
      remoteCommands: () => commands.stream,
    );
    await settleImages(tester);
    expect(h.stateOf(tester).currentPage, 0);

    commands.add({'type': 'next'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await settleImages(tester);
    expect(h.stateOf(tester).currentPage, 1);

    await disposeReader(tester);
  });

  testWidgets('remote prev retreats a page', (tester) async {
    useSingleStepFit();
    final h = await pumpReader(
      tester,
      server: server,
      tempDir: env,
      initialPage: 3,
      remoteCommands: () => commands.stream,
    );
    await settleImages(tester);

    commands.add({'type': 'prev'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await settleImages(tester);
    expect(h.stateOf(tester).currentPage, 2);

    await disposeReader(tester);
  });

  testWidgets('remote goto jumps to the requested page', (tester) async {
    useSingleStepFit();
    final h = await pumpReader(
      tester,
      server: server,
      tempDir: env,
      remoteCommands: () => commands.stream,
    );
    await settleImages(tester);

    commands.add({'type': 'goto', 'page': 6});
    await tester.pump();
    await settleImages(tester);
    expect(h.stateOf(tester).currentPage, 6);

    await disposeReader(tester);
  });

  // Nothing between the tailnet and PageController.jumpToPage validated this
  // number: the provider clamped it, the PageView did not, and the two
  // silently desynced. The clamp now lives in _jumpToPage, so the state and
  // the view agree whatever arrives.
  testWidgets('remote goto with an out-of-range page is clamped',
      (tester) async {
    useSingleStepFit();
    final h = await pumpReader(
      tester,
      server: server,
      tempDir: env,
      remoteCommands: () => commands.stream,
    );
    await settleImages(tester);

    ScrollPosition pos() =>
        tester.widget<PageView>(find.byType(PageView)).controller!.position;

    // Asserted on the very next frame and on raw pixels: jumpToPage()
    // forcePixels() straight to the requested offset and only corrects
    // itself on the following ballistic, and PageController.page hides that
    // by clamping its getter. Raw pixels are where the desync is visible —
    // a viewport scrolled past every child, i.e. a blank flash.
    commands.add({'type': 'goto', 'page': 9999});
    await tester.pump();
    expect(pos().pixels, lessThanOrEqualTo(pos().maxScrollExtent));
    await settleImages(tester);
    expect(h.stateOf(tester).currentPage, 9);

    commands.add({'type': 'goto', 'page': -5});
    await tester.pump();
    expect(pos().pixels, greaterThanOrEqualTo(pos().minScrollExtent));
    await settleImages(tester);
    expect(h.stateOf(tester).currentPage, 0);

    await disposeReader(tester);
  });

  // The harness default is Stream.empty(), which is broadcast and so cannot
  // catch this class of bug — hence the explicit single-subscription
  // controller. RemoteControlListener re-subscribes in initState, and its
  // element is re-inflated whenever the widget type at its slot changes.
  // It used to sit *under* a conditional VolumeKeyListener, so toggling
  // volumeKeys or readingMode from inside the reader re-listened to an
  // already-listened stream: "Bad state: Stream has already been listened
  // to", i.e. an ErrorWidget where the reader should be.
  testWidgets('toggling reader settings does not re-listen the command stream',
      (tester) async {
    useSingleStepFit();
    final single = StreamController<Map<String, dynamic>>();
    addTearDown(single.close);
    final h = await pumpReader(
      tester,
      server: server,
      tempDir: env,
      remoteCommands: () => single.stream,
    );
    await settleImages(tester);

    final container = h.containerOf(tester);
    final base = container.read(settingsProvider).value!;
    Future<void> save(ReaderSettings s) async {
      await tester
          .runAsync(() => container.read(settingsProvider.notifier).save(s));
      await settleImages(tester, rounds: 5);
    }

    // Both directions, and both settings that gate the VolumeKeyListener.
    await save(base.copyWith(volumeKeys: false));
    await save(base.copyWith(volumeKeys: true));
    await save(base.copyWith(readingMode: 'scroll'));
    await save(base.copyWith(readingMode: 'page'));
    expect(tester.takeException(), isNull);

    // And the remote still works afterwards.
    single.add({'type': 'next'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await settleImages(tester);
    expect(h.stateOf(tester).currentPage, 1);

    await disposeReader(tester);
  });

  testWidgets('remote bookmark toggles the current page', (tester) async {
    useSingleStepFit();
    final h = await pumpReader(
      tester,
      server: server,
      tempDir: env,
      remoteCommands: () => commands.stream,
    );
    await settleImages(tester);
    expect(h.stateOf(tester).bookmarks, isEmpty);

    commands.add({'type': 'bookmark'});
    await tester.pump();
    await settleImages(tester);
    expect(
      h.stateOf(tester).bookmarks.map((b) => b.pageNum),
      contains(0),
    );

    // The snapshot the phone would render must reflect the new bookmark —
    // this is what the next task's iPhone UI reads to draw the bookmark icon.
    final lastState =
        server.requestsWhere((r) => r.path == '/remote/state').last;
    expect(lastState.jsonBody?['bookmarked'], isTrue);

    await disposeReader(tester);
  });

  testWidgets('the iPad publishes a state snapshot on open', (tester) async {
    useSingleStepFit();
    await pumpReader(
      tester,
      server: server,
      tempDir: env,
      remoteCommands: () => commands.stream,
    );
    await settleImages(tester);

    final stateRequests =
        server.requestsWhere((r) => r.path == '/remote/state');
    expect(stateRequests, isNotEmpty);

    // The next task builds the iPhone UI entirely off this payload, so its
    // fields must be right, not just present.
    final body = stateRequests.last.jsonBody!;
    expect(body['comicId'], 'c1');
    expect(body['page'], 0);
    expect(body['totalPages'], 10);
    expect(body['readingMode'], 'page');

    await disposeReader(tester);
  });

  testWidgets('remote state publish is deduped across rebuilds with no change',
      (tester) async {
    useSingleStepFit();
    await pumpReader(
      tester,
      server: server,
      tempDir: env,
      remoteCommands: () => commands.stream,
    );
    await settleImages(tester);

    int stateCount() =>
        server.requestsWhere((r) => r.path == '/remote/state').length;
    final afterOpen = stateCount();
    expect(afterOpen, greaterThan(0));

    // Showing the chrome rebuilds the reader (toolbar visibility flips via
    // setState) without touching page, bookmarks, or comic — the dedupe
    // guard (_lastSnapshotJson) is the only thing that can stop this from
    // re-publishing on every such rebuild.
    tester.state<ReaderScreenState>(find.byType(ReaderScreen)).showChrome();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      stateCount(),
      afterOpen,
      reason: 'unchanged snapshot content must not re-publish',
    );

    await disposeReader(tester);
  });
}
