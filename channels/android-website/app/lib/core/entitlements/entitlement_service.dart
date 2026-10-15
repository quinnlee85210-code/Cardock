import 'review_access_service.dart';
import 'review_access_codec.dart';
import 'review_access_public_key.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'distribution_channel.dart';
import 'commercial_purchase_gateway.dart';
import 'entitlement_model.dart';
import 'purchase_gateway.dart';
import 'website_offline_codec.dart';

/// Keeps the queried store entitlement in memory for cheap reactive reads.
final class ProductEntitlementController extends ChangeNotifier
    implements ValueListenable<ProductEntitlement> {
  factory ProductEntitlementController({
    required PurchaseGateway gateway,
    ValueListenable<ProductEntitlement>? promoEntitlementListenable,
    ReviewAccessController? reviewAccessController,
  }) => ProductEntitlementController._(
    gateway,
    promoEntitlementListenable,
    gateway is DistributionAwarePurchaseGateway &&
            (gateway as DistributionAwarePurchaseGateway).distributionChannel ==
                CardockDistributionChannel.googlePlay
        ? reviewAccessController ??
              ReviewAccessController(
                verifier: ReviewAccessVerifier(
                  publicKey: reviewAccessPublicKey,
                ),
                store: const MethodChannelReviewAccessStore(),
              )
        : null,
  );

  ProductEntitlementController._(
    this._gateway,
    this._promoEntitlementListenable,
    this.reviewAccess,
  ) {
    reviewAccess?.addListener(_onReviewChanged);
    _promoEntitlementListenable?.addListener(_onPromoEntitlementChanged);
    _promoEntitlement =
        _promoEntitlementListenable?.value ?? ProductEntitlement.free;
    _recomputeValue();
  }

  final PurchaseGateway _gateway;
  final ReviewAccessController? reviewAccess;
  bool get isReviewAuthorized => reviewAccess?.value == true;
  final ValueListenable<ProductEntitlement>? _promoEntitlementListenable;
  ProductEntitlement _storeEntitlement = ProductEntitlement.free;
  ProductEntitlement _promoEntitlement = ProductEntitlement.free;
  ProductEntitlement _value = ProductEntitlement.free;
  StreamSubscription<ProductEntitlement>? _subscription;
  Future<void> _operationTail = Future<void>.value();
  bool _initialized = false;
  bool _busy = false;
  bool _disposed = false;

  @override
  ProductEntitlement get value => _value;

  String? storePrice;
  Future<void> loadStorePrice() async {
    final gateway = _gateway;
    if (gateway is CommercialPurchaseGateway) {
      storePrice = await gateway.loadPrice();
      _notifyIfActive();
    }
  }

  bool get isInitialized => _initialized;
  bool get isBusy => _busy;
  bool get hasFullVersion => _value.hasFullVersion;
  bool get hasStorePurchase => _storeEntitlement.hasFullVersion;
  CardockDistributionChannel get distributionChannel {
    final gateway = _gateway;
    return gateway is DistributionAwarePurchaseGateway
        ? (gateway as DistributionAwarePurchaseGateway).distributionChannel
        : CardockDistributionChannel.development;
  }

  bool get isPromoActivated =>
      distributionChannel == CardockDistributionChannel.development &&
      _promoEntitlement.hasFullVersion;
  bool get debugOverrideAvailable {
    final gateway = _gateway;
    return gateway is DebugPurchaseGateway &&
        (gateway as DebugPurchaseGateway).debugOverrideAvailable;
  }

  Future<void> initialize() => _runExclusive(() async {
    await reviewAccess?.initialize();
    _subscription ??= _gateway.entitlementStream.listen(
      _setStoreEntitlement,
      onError: (_, _) {},
    );
    try {
      _setStoreEntitlement(await _gateway.query());
    } on Object {
      _setStoreEntitlement(ProductEntitlement.free);
    } finally {
      _initialized = true;
      _notifyIfActive();
    }
  });

  Future<PurchaseActionResult> purchase() => _perform(_gateway.purchase);

  Future<PurchaseActionResult> restore() => _perform(_gateway.restore);

  VerifiedWebsiteReceipt? get websiteReceipt {
    final gateway = _gateway;
    return hasStorePurchase && gateway is CommercialPurchaseGateway
        ? gateway.websiteReceipt
        : null;
  }

  Future<PurchaseActionResult> removeWebsiteAuthorization(
    bool Function() authorized,
  ) => _perform(() {
    final gateway = _gateway;
    return gateway is CommercialPurchaseGateway
        ? gateway.removeWebsiteAuthorization(authorized)
        : Future.value(PurchaseActionResult.unavailable(entitlement: _value));
  });

  Future<PurchaseActionResult> openWebsiteRequest(
    String purpose,
    String reference,
    bool Function() authorized,
  ) => _perform(() {
    final gateway = _gateway;
    return gateway is CommercialPurchaseGateway
        ? gateway.openWebsiteRequest(purpose, reference, authorized)
        : Future.value(PurchaseActionResult.unavailable(entitlement: _value));
  });

  Future<PurchaseActionResult> handleWebsiteChallenge(
    String challenge,
    bool Function() authorized,
  ) => _perform(() {
    final gateway = _gateway;
    return gateway is CommercialPurchaseGateway
        ? gateway.handleWebsiteChallenge(challenge, authorized)
        : Future.value(PurchaseActionResult.unavailable(entitlement: _value));
  });

  Future<PurchaseActionResult> openWebsiteOrders(bool Function() authorized) =>
      _perform(() {
        final gateway = _gateway;
        return gateway is CommercialPurchaseGateway
            ? gateway.openWebsiteOrders(authorized)
            : Future.value(
                PurchaseActionResult.unavailable(entitlement: _value),
              );
      });

  Future<PurchaseActionResult> openWebsiteRecovery({
    bool Function()? authorized,
  }) => _perform(() {
    final gateway = _gateway;
    return gateway is CommercialPurchaseGateway
        ? gateway.openWebsiteRecovery(authorized: authorized)
        : Future.value(const PurchaseActionResult.unavailable());
  });

  Future<PurchaseActionResult> importWebsiteAuthorization(
    String credential, {
    bool Function()? authorized,
  }) => _perform(() {
    final gateway = _gateway;
    if (gateway is CommercialPurchaseGateway) {
      return gateway.importAuthorization(credential, authorized: authorized);
    }
    if (authorized != null && !authorized()) {
      return Future.value(
        PurchaseActionResult.unavailable(entitlement: _value),
      );
    }
    if (gateway is WebsiteAuthorizationGateway) {
      return (gateway as WebsiteAuthorizationGateway).importAuthorization(
        credential,
      );
    }
    return Future.value(const PurchaseActionResult.unavailable());
  });

  Future<void> debugSetEntitlement(ProductEntitlement entitlement) async {
    final gateway = _gateway;
    if (gateway is! DebugPurchaseGateway) {
      return;
    }
    final debugGateway = gateway as DebugPurchaseGateway;
    if (!debugGateway.debugOverrideAvailable) return;
    await debugGateway.debugSetEntitlement(entitlement);
    _setStoreEntitlement(entitlement);
  }

  Future<PurchaseActionResult> _perform(
    Future<PurchaseActionResult> Function() action,
  ) => _runExclusive(() async {
    _busy = true;
    _notifyIfActive();
    try {
      final result = await action();
      _setStoreEntitlement(result.entitlement);
      return result;
    } on Object {
      return PurchaseActionResult.failed(entitlement: _value);
    } finally {
      _busy = false;
      _notifyIfActive();
    }
  });

  Future<T> _runExclusive<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _setStoreEntitlement(ProductEntitlement next) {
    if (_storeEntitlement == next) return;
    _storeEntitlement = next;
    _recomputeValue();
  }

  void _onPromoEntitlementChanged() {
    final next = _promoEntitlementListenable?.value ?? ProductEntitlement.free;
    if (_promoEntitlement == next) return;
    _promoEntitlement = next;
    _recomputeValue();
  }

  void _onReviewChanged() {
    _recomputeValue();
    _notifyIfActive();
  }

  void _recomputeValue() {
    final next = _storeEntitlement.hasFullVersion || isPromoActivated
        ? ProductEntitlement.purchased
        : isReviewAuthorized
        ? ProductEntitlement.review
        : ProductEntitlement.free;
    if (_value == next) return;
    _value = next;
    _notifyIfActive();
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _promoEntitlementListenable?.removeListener(_onPromoEntitlementChanged);
    unawaited(_subscription?.cancel());
    _gateway.dispose();
    reviewAccess?.removeListener(_onReviewChanged);
    reviewAccess?.dispose();
    super.dispose();
  }
}

class ProductEntitlementScope
    extends InheritedNotifier<ProductEntitlementController> {
  const ProductEntitlementScope({
    required ProductEntitlementController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ProductEntitlementController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'ProductEntitlementScope is missing.');
    return controller!;
  }

  static ProductEntitlementController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ProductEntitlementScope>()
      ?.notifier;
}
