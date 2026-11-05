import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/flavor.dart';
import 'package:comic_reader_app/providers/pro_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/pro_sheet.dart';

import '../providers/pro_provider_test.dart' show FakeProStore, purchase;

Future<FakeProStore> pumpHost(WidgetTester t, void Function(BuildContext, WidgetRef) onTap) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = FakeProStore();
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      proStoreProvider.overrideWithValue(store),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
              onPressed: () => onTap(context, ref), child: const Text('go')),
        ),
      ),
    ),
  ));
  return store;
}

void main() {
  tearDown(() => isStore = false);

  testWidgets('store: sheet shows the price, Restore works, and it closes on unlock',
      (t) async {
    isStore = true;
    final store = await pumpHost(t, (c, _) => showProSheet(c, reason: 'Downloads are part of Pro.'));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('Downloads are part of Pro.'), findsOneWidget);
    expect(find.textContaining(r'$12.99'), findsOneWidget);
    await t.tap(find.text('Restore Purchases'));
    await t.pump();
    expect(store.restores, 1);
    store.controller.add([purchase(PurchaseStatus.restored)]);
    await t.pumpAndSettle();
    expect(find.text('Restore Purchases'), findsNothing);
  });

  testWidgets('requirePro: personal build passes without a sheet', (t) async {
    bool? result;
    await pumpHost(t, (c, ref) => result = requirePro(c, ref, reason: 'x'));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(result, isTrue);
    expect(find.text('Restore Purchases'), findsNothing);
  });

  testWidgets('requirePro: locked store build opens the sheet', (t) async {
    isStore = true;
    bool? result;
    await pumpHost(t, (c, ref) => result = requirePro(c, ref, reason: 'x'));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(result, isFalse);
    expect(find.text('Restore Purchases'), findsOneWidget);
  });

  testWidgets('already unlocked: the sheet says so instead of selling', (t) async {
    await pumpHost(t, (c, _) => showProSheet(c));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('Unlocked'), findsOneWidget);
    expect(find.textContaining('Unlock for'), findsNothing);
  });
}
