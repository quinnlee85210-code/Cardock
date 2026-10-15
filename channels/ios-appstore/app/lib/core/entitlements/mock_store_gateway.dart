import 'dart:async';

import 'package:flutter/foundation.dart';

import 'entitlement_model.dart';
import 'purchase_gateway.dart';

/// Deterministic store simulator. It performs no network access.
final class MockStoreGateway implements PurchaseGateway, DebugPurchaseGateway {
  MockStoreGateway({
    ProductEntitlement initialEntitlement = ProductEntitlement.free,
    bool? simulationEnabled,
  }) : _entitlement = initialEntitlement,
       _simulationEnabled = simulationEnabled ?? kDebugMode;

  final bool _simulationEnabled;
  final StreamController<ProductEntitlement> _controller =
      StreamController<ProductEntitlement>.broadcast(sync: true);
  ProductEntitlement _entitlement;
  bool _disposed = false;

  @override
  Stream<ProductEntitlement> get entitlementStream => _controller.stream;

  @override
  bool get debugOverrideAvailable => _simulationEnabled;

  @override
  Future<ProductEntitlement> query() async => _entitlement;

  @override
  Future<PurchaseActionResult> purchase() async {
    if (!_simulationEnabled) {
      return PurchaseActionResult.unavailable(entitlement: _entitlement);
    }
    await _setEntitlement(ProductEntitlement.purchased);
    return PurchaseActionResult.completed(
      entitlement: _entitlement,
      message: '模拟购买完成，已解锁完整版。',
    );
  }

  @override
  Future<PurchaseActionResult> restore() async {
    if (!_simulationEnabled) {
      return PurchaseActionResult.unavailable(entitlement: _entitlement);
    }
    if (!_entitlement.hasFullVersion) {
      return PurchaseActionResult.noPurchaseFound(entitlement: _entitlement);
    }
    _emit();
    return PurchaseActionResult.completed(
      entitlement: _entitlement,
      message: '已恢复模拟购买状态。',
    );
  }

  @override
  Future<void> debugSetEntitlement(ProductEntitlement entitlement) =>
      _setEntitlement(entitlement);

  Future<void> _setEntitlement(ProductEntitlement entitlement) async {
    if (_entitlement == entitlement) return;
    _entitlement = entitlement;
    _emit();
  }

  void _emit() {
    if (!_disposed) _controller.add(_entitlement);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_controller.close());
  }
}
