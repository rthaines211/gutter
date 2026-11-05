import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/flavor.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/longbox_splash.dart';

void main() {
  testWidgets('store: the splash wordmark is the store name', (t) async {
    isStore = true;
    addTearDown(() => isStore = false);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: LongboxSplash(child: SizedBox())),
    ));
    await t.pump(const Duration(milliseconds: 1500));
    expect(find.text('GUTTER'), findsOneWidget);
    expect(find.text('LONGBOX'), findsNothing);
    await t.pump(LongboxSplash.duration);
  });
}
