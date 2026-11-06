import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/flavor.dart';
import 'package:comic_reader_app/providers/pro_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/stats_provider.dart';
import 'package:comic_reader_app/screens/stats_screen.dart';

import '../providers/pro_provider_test.dart' show FakeProStore;

void main() {
  testWidgets('store without Pro: Stats offers Pro and loads nothing', (t) async {
    isStore = true;
    addTearDown(() => isStore = false);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var loaded = false;
    await t.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        proStoreProvider.overrideWithValue(FakeProStore()),
        statsSummaryProvider.overrideWith((ref) {
          loaded = true;
          return Completer<Never>().future;
        }),
      ],
      child: const MaterialApp(home: StatsScreen()),
    ));
    await t.pump();
    expect(find.text('Reading stats are part of Pro.'), findsOneWidget);
    expect(loaded, isFalse);
    await t.tap(find.text('See Gutter Pro'));
    await t.pumpAndSettle();
    expect(find.text('Restore Purchases'), findsOneWidget);
  });
}
