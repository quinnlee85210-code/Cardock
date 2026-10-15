import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_service.dart';
import 'package:account_subscription_manager/core/entitlements/mock_store_gateway.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('controller initializes from the replaceable gateway', () async {
    final controller = ProductEntitlementController(
      gateway: MockStoreGateway(
        initialEntitlement: ProductEntitlement.purchased,
      ),
    );
    await controller.initialize();
    expect(controller.value, ProductEntitlement.purchased);
    expect(controller.hasFullVersion, isTrue);
    controller.dispose();
  });

  test(
    'debug mock purchase and restore expose only free or purchased',
    () async {
      final controller = ProductEntitlementController(
        gateway: MockStoreGateway(simulationEnabled: true),
      );
      await controller.initialize();
      expect(controller.value, ProductEntitlement.free);
      expect(
        (await controller.restore()).status,
        PurchaseActionStatus.noPurchaseFound,
      );
      expect(
        (await controller.purchase()).status,
        PurchaseActionStatus.completed,
      );
      expect(controller.value, ProductEntitlement.purchased);
      expect(
        (await controller.restore()).status,
        PurchaseActionStatus.completed,
      );
      controller.dispose();
    },
  );

  test('release-mode mock never grants a simulated purchase', () async {
    final controller = ProductEntitlementController(
      gateway: MockStoreGateway(simulationEnabled: false),
    );
    await controller.initialize();
    expect(controller.debugOverrideAvailable, isFalse);
    final result = await controller.purchase();
    expect(result.status, PurchaseActionStatus.unavailable);
    expect(result.message, '正式版支付即将上线');
    expect(controller.value, ProductEntitlement.free);
    controller.dispose();
  });

  test('debug entitlement changes notify in-memory listeners', () async {
    final controller = ProductEntitlementController(
      gateway: MockStoreGateway(simulationEnabled: true),
    );
    await controller.initialize();
    var notifications = 0;
    controller.addListener(() => notifications += 1);
    await controller.debugSetEntitlement(ProductEntitlement.purchased);
    expect(controller.value, ProductEntitlement.purchased);
    expect(notifications, greaterThan(0));
    controller.dispose();
  });

  test('商店权益与推广激活任一成立即为完整版', () async {
    final promo = ValueNotifier<ProductEntitlement>(ProductEntitlement.free);
    final gateway = MockStoreGateway(simulationEnabled: true);
    final controller = ProductEntitlementController(
      gateway: gateway,
      promoEntitlementListenable: promo,
    );
    await controller.initialize();
    expect(controller.value, ProductEntitlement.free);

    promo.value = ProductEntitlement.purchased;
    expect(controller.value, ProductEntitlement.purchased);
    expect(controller.isPromoActivated, isTrue);
    expect(controller.hasStorePurchase, isFalse);

    await gateway.debugSetEntitlement(ProductEntitlement.purchased);
    expect(controller.hasStorePurchase, isTrue);
    promo.value = ProductEntitlement.free;
    expect(controller.value, ProductEntitlement.purchased);

    await gateway.debugSetEntitlement(ProductEntitlement.free);
    expect(controller.value, ProductEntitlement.free);
    controller.dispose();
    promo.dispose();
  });

  test('商店恢复失败不会清除已验证的推广权益', () async {
    final promo = ValueNotifier<ProductEntitlement>(
      ProductEntitlement.purchased,
    );
    final controller = ProductEntitlementController(
      gateway: MockStoreGateway(simulationEnabled: false),
      promoEntitlementListenable: promo,
    );
    await controller.initialize();
    expect(controller.value, ProductEntitlement.purchased);
    expect(
      (await controller.restore()).status,
      PurchaseActionStatus.unavailable,
    );
    expect(controller.value, ProductEntitlement.purchased);
    controller.dispose();
    promo.dispose();
  });
}
