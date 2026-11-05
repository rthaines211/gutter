import 'dart:io';

import 'package:comic_reader_app/providers/connectivity_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_comic_server.dart';
import 'harness.dart';

/// Wifi dropping or returning mid-read used to rebuild the reader at page 0
/// and save page 0 as progress.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory env;
  late FakeComicServer server;

  setUpAll(() async => env = await initReaderTestEnv());
  useComicServer(
    () => FakeComicServer()
      ..comics['c1'] = List.filled(10, portraitPage)
      ..settings = {'page_fit': 'fitHeight'},
    (s) => server = s,
    () => server,
  );

  testWidgets('a connectivity flip keeps the page and its progress',
      (tester) async {
    final h = await pumpReader(tester,
        server: server, tempDir: env, initialPage: 5);
    await settleImages(tester);
    expect(h.stateOf(tester).currentPage, 5);

    final connectivity = h.containerOf(tester).read(connectivityProvider.notifier);
    connectivity.state = false;
    await settleImages(tester);
    connectivity.state = true;
    await settleImages(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(h.stateOf(tester).currentPage, 5);
    final zeroSaves = server.requestsWhere((r) =>
        r.method == 'PUT' &&
        r.path == '/reading/c1' &&
        r.jsonBody?['current_page'] == 0);
    expect(zeroSaves, isEmpty);
    await disposeReader(tester);
  });
}
