import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/flavor.dart';
import 'package:comic_reader_app/providers/connectivity_provider.dart';
import 'package:comic_reader_app/providers/pro_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/screens/more_screen.dart';
import 'package:comic_reader_app/screens/onboarding_screen.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/widgets/pro_sheet.dart';

import '../providers/pro_provider_test.dart' show FakeProStore;

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://t', deviceId: 'd');
  @override
  Future<int?> probeStatus() async => 200;
}

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// First-run screens at large Dynamic Type on the smallest iPhone (SE,
/// 375x667). An overflow here throws, and the test fails.
Future<void> _pump(WidgetTester t, Widget home, {double scale = 2.0}) async {
  t.view.physicalSize = const Size(750, 1334);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorage,
          (call) async => call.method == 'readAll' ? <String, String>{} : null);
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorage, null));
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      proStoreProvider.overrideWithValue(FakeProStore()),
      connectivityProvider.overrideWith(_Online.new),
      apiClientProvider.overrideWithValue(_FakeApi()),
    ],
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  tearDown(() => isStore = false);

  for (final scale in [1.35, 2.0]) {
    testWidgets('More fits an iPhone SE at ${scale}x text', (t) async {
      isStore = true;
      await _pump(t, const MoreScreen(), scale: scale);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('onboarding fits an iPhone SE at ${scale}x text', (t) async {
      isStore = true;
      await _pump(t, OnboardingScreen(probe: (_) async => null), scale: scale);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Gutter server'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('Pro sheet fits an iPhone SE at ${scale}x text', (t) async {
      isStore = true;
      await _pump(
          t,
          Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                  onPressed: () =>
                      showProSheet(c, reason: 'Downloads are part of Pro.'),
                  child: const Text('go')),
            ),
          ),
          scale: scale);
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.text('Restore Purchases'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
