import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/flavor.dart';
import 'package:comic_reader_app/providers/pro_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/services/pro_store.dart';

class FakeProStore implements ProStore {
  final controller = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <PurchaseDetails>[];
  int restores = 0, buys = 0;

  @override
  Stream<List<PurchaseDetails>> get purchases => controller.stream;
  @override
  Future<ProductDetails?> product() async => ProductDetails(
      id: proProductId, title: 'Gutter Pro', description: 'Pro',
      price: r'$12.99', rawPrice: 12.99, currencyCode: 'USD');
  @override
  Future<void> buy(ProductDetails p) async => buys++;
  @override
  Future<void> restore() async => restores++;
  @override
  Future<void> complete(PurchaseDetails p) async => completed.add(p);
}

PurchaseDetails purchase(PurchaseStatus status, {bool pending = false}) =>
    PurchaseDetails(
      productID: proProductId,
      verificationData: PurchaseVerificationData(
          localVerificationData: '', serverVerificationData: '', source: 'app_store'),
      transactionDate: null,
      status: status,
    )..pendingCompletePurchase = pending;

Future<(ProviderContainer, FakeProStore)> container([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final store = FakeProStore();
  final c = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(p),
    proStoreProvider.overrideWithValue(store),
  ]);
  addTearDown(c.dispose);
  return (c, store);
}

void main() {
  tearDown(() => isStore = false);

  test('personal build is always Pro', () async {
    final (c, _) = await container();
    expect(c.read(proProvider), isTrue);
  });

  group('store', () {
    setUp(() => isStore = true);

    test('starts locked, unlocks on purchase and remembers it', () async {
      final (c, store) = await container();
      expect(c.read(proProvider), isFalse);
      store.controller.add([purchase(PurchaseStatus.purchased, pending: true)]);
      await pumpEventQueue();
      expect(c.read(proProvider), isTrue);
      expect(store.completed, hasLength(1), reason: 'StoreKit re-delivers uncompleted purchases');
      expect(c.read(sharedPrefsProvider).getBool('pro_unlocked'), isTrue);
    });

    test('a restored purchase unlocks', () async {
      final (c, store) = await container();
      c.read(proProvider);
      await c.read(proProvider.notifier).restore();
      expect(store.restores, 1);
      store.controller.add([purchase(PurchaseStatus.restored)]);
      await pumpEventQueue();
      expect(c.read(proProvider), isTrue);
    });

    test('errors and cancels are completed but do not unlock', () async {
      final (c, store) = await container();
      c.read(proProvider);
      store.controller.add([purchase(PurchaseStatus.canceled, pending: true)]);
      await pumpEventQueue();
      expect(c.read(proProvider), isFalse);
      expect(store.completed, hasLength(1));
    });

    test('a cached unlock survives a relaunch with no store events', () async {
      final (c, _) = await container({'pro_unlocked': true});
      expect(c.read(proProvider), isTrue);
    });

    test('buy asks the store for the Pro product', () async {
      final (c, store) = await container();
      await c.read(proProvider.notifier).buy();
      expect(store.buys, 1);
    });
  });
}
