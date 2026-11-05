import 'package:comic_reader_app/providers/connectivity_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/screens/more_screen.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _FakeApi extends ApiClient {
  _FakeApi(this.status) : super(baseUrl: 'http://t', deviceId: 'd');
  final int? status;
  @override
  Future<int?> probeStatus() async => status;
}

Future<void> _pump(WidgetTester t, int? status) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      connectivityProvider.overrideWith(_Online.new),
      apiClientProvider.overrideWithValue(_FakeApi(status)),
    ],
    child: const MaterialApp(home: MoreScreen()),
  ));
  await t.pump();
}

void main() {
  testWidgets('401 shows signed out / wrong password, not offline', (t) async {
    await _pump(t, 401);
    expect(find.text('Signed out'), findsOneWidget);
    expect(find.text('Wrong password'), findsOneWidget);
    expect(find.text('Offline'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('unreachable shows offline', (t) async {
    await _pump(t, null);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Wrong password'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('200 shows online', (t) async {
    await _pump(t, 200);
    expect(find.text('Online'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
