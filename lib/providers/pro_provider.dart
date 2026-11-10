import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/flavor.dart';
import '../config/platform.dart';
import '../services/pro_store.dart';
import 'providers.dart';

const _unlockedKey = 'pro_unlocked';

const zoomTrialKey = 'zoom_trial_comic';

/// Guided zoom without Pro: it works in one issue, the first it is turned on
/// in. True when [comicId] is that issue; claims it when there is none yet.
// ponytail: kept in prefs, so a reinstall gives another free issue.
bool zoomTrialCovers(SharedPreferences prefs, String comicId) {
  final trial = prefs.getString(zoomTrialKey);
  if (trial == null) {
    prefs.setString(zoomTrialKey, comicId);
    return true;
  }
  return trial == comicId;
}

const zoomTrialOver = 'Guided zoom was free for one issue. It is part of Pro.';

final proStoreProvider = Provider<ProStore>((ref) => InAppPurchaseProStore());

/// Whether Pro is unlocked. The personal build always is. The store build
/// starts from the cached flag (so Pro works offline) and listens to
/// StoreKit for purchases and restores.
// ponytail: refunds aren't detected; add receipt checks if they matter.
class ProNotifier extends Notifier<bool> {
  @override
  bool build() {
    if (!isStore) return true;
    final store = ref.read(proStoreProvider);
    final sub = store.purchases.listen(_onPurchases);
    ref.onDispose(sub.cancel);
    // Play Billing doesn't re-deliver at launch the way StoreKit does: ask for
    // owned purchases (no UI) so one finished while the app was closed unlocks,
    // and an unacknowledged one is acknowledged before Play refunds it (3 days).
    if (isAndroid) store.restore().catchError((_) {});
    return ref.read(sharedPrefsProvider).getBool(_unlockedKey) ?? false;
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    final store = ref.read(proStoreProvider);
    for (final p in purchases) {
      if (p.productID == proProductId &&
          (p.status == PurchaseStatus.purchased ||
              p.status == PurchaseStatus.restored)) {
        state = true;
        await ref.read(sharedPrefsProvider).setBool(_unlockedKey, true);
      }
      // StoreKit re-delivers every uncompleted transaction on launch; on
      // Play, completing acknowledges.
      if (p.pendingCompletePurchase) await store.complete(p);
    }
  }

  /// The Pro product (for its localized price), or null when the store
  /// can't be reached.
  Future<ProductDetails?> get product => ref.read(proStoreProvider).product();

  Future<void> buy() async {
    final store = ref.read(proStoreProvider);
    final p = await store.product();
    if (p != null) await store.buy(p);
  }

  Future<void> restore() => ref.read(proStoreProvider).restore();
}

final proProvider = NotifierProvider<ProNotifier, bool>(ProNotifier.new);
