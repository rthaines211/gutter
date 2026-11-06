import 'package:in_app_purchase/in_app_purchase.dart';

/// The one-time Pro unlock (non-consumable, $12.99 in App Store Connect).
const proProductId = 'com.ryanhaines.gutter.pro';

/// StoreKit, narrowed to what Pro needs, so tests can fake it.
abstract class ProStore {
  Stream<List<PurchaseDetails>> get purchases;
  Future<ProductDetails?> product();
  Future<void> buy(ProductDetails product);
  Future<void> restore();
  Future<void> complete(PurchaseDetails purchase);
}

class InAppPurchaseProStore implements ProStore {
  InAppPurchase get _iap => InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchases => _iap.purchaseStream;

  @override
  Future<ProductDetails?> product() async {
    if (!await _iap.isAvailable()) return null;
    final res = await _iap.queryProductDetails({proProductId});
    return res.productDetails.firstOrNull;
  }

  @override
  Future<void> buy(ProductDetails product) =>
      _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Future<void> complete(PurchaseDetails purchase) => _iap.completePurchase(purchase);
}
