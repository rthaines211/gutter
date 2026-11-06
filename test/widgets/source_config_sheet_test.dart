import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/models/server_source.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/source_provider.dart';
import 'package:comic_reader_app/widgets/source_config_sheet.dart';

const _secureStorage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  testWidgets('adds a Komga server with a login', (t) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage,
            (call) async => call.method == 'readAll' ? <String, String>{} : null);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null));
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    t.view.physicalSize = const Size(800, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: SourceConfigSheet())),
    ));
    await t.tap(find.text('Komga'));
    await t.pump();
    await t.enterText(find.widgetWithText(TextField, 'https://komga.local:25600'),
        'https://komga.example.com');
    await t.tap(find.text('Basic'));
    await t.pump();
    await t.enterText(find.widgetWithText(TextField, 'admin'), 'reader');
    await t.enterText(find.byType(TextField).last, 'pw');
    await t.tap(find.text('Add Source'));
    await t.pump();
    final added = c.read(sourceListProvider).last;
    expect(added.type, SourceType.komga);
    expect(added.baseUrl, 'https://komga.example.com');
    expect(added.authHeaders['Authorization'], startsWith('Basic '));
  });
}
