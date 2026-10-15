import 'dart:async';

import 'entitlement_model.dart';

/// Replaceable application-store boundary.
///
/// Task seven can inject HuaweiIapGateway without changing feature code.
abstract interface class PurchaseGateway {
  Stream<ProductEntitlement> get entitlementStream;

  Future<ProductEntitlement> query();

  Future<PurchaseActionResult> purchase();

  Future<PurchaseActionResult> restore();

  void dispose();
}

/// Debug-only seam exposed by the local deterministic store simulator.
abstract interface class DebugPurchaseGateway {
  bool get debugOverrideAvailable;

  Future<void> debugSetEntitlement(ProductEntitlement entitlement);
}
