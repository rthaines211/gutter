import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/page_reader.dart';

import 'fake_comic_server.dart';
import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory env;
  late FakeComicServer server;

  setUpAll(() async => env = await initReaderTestEnv());
  useComicServer(
    () => FakeComicServer()..comics['c1'] = List.filled(10, portraitPage),
    (s) => server = s,
    () => server,
  );

  testWidgets('reader opens against fake server and loads pages',
      (tester) async {
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);

    expect(find.byType(PageReader), findsOneWidget);
    expect(server.requestsWhere((r) => r.path == '/settings'), isNotEmpty);
    expect(
      server.requestsWhere((r) => r.path.startsWith('/comics/c1/pages/')),
      isNotEmpty,
      reason: 'real image pipeline should have fetched page bytes',
    );

    await disposeReader(tester);
  });
}
