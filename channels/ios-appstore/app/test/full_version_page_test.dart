import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_service.dart';
import 'package:account_subscription_manager/core/entitlements/mock_store_gateway.dart';
import 'package:account_subscription_manager/core/entitlements/promo_activation_codec.dart';
import 'package:account_subscription_manager/core/entitlements/promo_activation_service.dart';
import 'package:account_subscription_manager/core/entitlements/promo_activation_store.dart';
import 'package:account_subscription_manager/features/product/presentation/full_version_page.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('免费购买页展示准确对比并可切换为已解锁态', (tester) async {
    final promoController = await _freePromoController();
    final controller = ProductEntitlementController(
      gateway: MockStoreGateway(simulationEnabled: true),
      promoEntitlementListenable: promoController,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(
      _testApp(controller, promoController: promoController),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('full-edition-card')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('七套高级固定主题与自定义主题'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('free-edition-card')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('最多 5 个订阅项'), findsOneWidget);
    expect(find.text('最多 15 个账户条目'), findsOneWidget);
    expect(find.text('橙墨旧刊主题（免费）'), findsOneWidget);
    final purchaseButton = find.byKey(
      const ValueKey<String>('purchase-full-version-button'),
    );
    await tester.scrollUntilVisible(
      purchaseButton,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('¥9.9 一次买断'), findsOneWidget);
    final privacyNote = find.byKey(
      const ValueKey<String>('purchase-local-privacy-note'),
    );
    await tester.scrollUntilVisible(
      privacyNote,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('购买记录由应用商店托管'), findsOneWidget);
    expect(find.text('登录账号'), findsNothing);
    expect(find.text('授权码'), findsNothing);
    expect(find.text('检查更新'), findsNothing);
    final promoDisclosure = find.byKey(
      const ValueKey<String>('promo-activation-disclosure'),
    );
    await tester.scrollUntilVisible(
      promoDisclosure,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('其他激活方式'), findsOneWidget);
    expect(find.text('已获得推广激活码'), findsOneWidget);

    await tester.ensureVisible(purchaseButton);
    await tester.tap(purchaseButton);
    await tester.pumpAndSettle();
    expect(controller.value, ProductEntitlement.purchased);
    expect(
      find.byKey(const ValueKey<String>('full-version-purchased-banner')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('purchase-full-version-button')),
      findsNothing,
    );
    final restoreButton = find.byKey(
      const ValueKey<String>('restore-purchase-button'),
    );
    await tester.scrollUntilVisible(
      restoreButton,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('恢复购买'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('promo-store-purchased-state')),
      findsOneWidget,
    );
    expect(find.text('已通过购买解锁完整版'), findsOneWidget);
  });

  testWidgets('免费态可展开其他激活方式并在本机验签激活', (tester) async {
    final keyPair = await Ed25519().newKeyPair();
    addTearDown(keyPair.destroy);
    final publicKey = await keyPair.extractPublicKey();
    final promoController = await _freePromoController(
      publicKeyBytes: publicKey.bytes,
      installationOffset: 24,
    );
    final controller = ProductEntitlementController(
      gateway: MockStoreGateway(simulationEnabled: false),
      promoEntitlementListenable: promoController,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final activationCode = await const PromoActivationIssuer().issue(
      requestCode: promoController.requestCode!,
      keyPair: keyPair,
    );

    await tester.pumpWidget(
      _testApp(controller, promoController: promoController),
    );
    final disclosure = find.byKey(
      const ValueKey<String>('promo-activation-disclosure'),
    );
    await tester.scrollUntilVisible(
      disclosure,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(disclosure);
    await tester.pumpAndSettle();
    expect(find.text('如果你已获得开发者签发的推广激活码，可在此使用本机申请码完成离线激活。'), findsOneWidget);
    expect(find.textContaining('赞赏'), findsNothing);

    expect(
      find.byKey(const ValueKey<String>('promo-request-code')),
      findsOneWidget,
    );
    final codeField = find.byKey(
      const ValueKey<String>('promo-activation-code-field'),
    );
    await tester.scrollUntilVisible(
      codeField,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(codeField, activationCode);
    final activateButton = find.byKey(
      const ValueKey<String>('activate-promo-code-button'),
    );
    await tester.scrollUntilVisible(
      activateButton,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(activateButton);
    await tester.pumpAndSettle();

    expect(promoController.isActivated, isTrue);
    expect(controller.hasFullVersion, isTrue);
    expect(find.text('已激活永久完整版。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('promo-activated-state')),
      findsOneWidget,
    );
    expect(find.text('已通过推广激活解锁完整版'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('purchase-full-version-button')),
      findsNothing,
    );
  });

  testWidgets('release模拟网关不会授予购买并显示即将上线', (tester) async {
    final promoController = await _freePromoController(installationOffset: 48);
    final controller = ProductEntitlementController(
      gateway: MockStoreGateway(simulationEnabled: false),
      promoEntitlementListenable: promoController,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(
      _testApp(controller, promoController: promoController),
    );
    final purchaseButton = find.byKey(
      const ValueKey<String>('purchase-full-version-button'),
    );
    await tester.scrollUntilVisible(
      purchaseButton,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('debug-entitlement-switch')),
      findsNothing,
    );
    await tester.tap(purchaseButton);
    await tester.pumpAndSettle();
    expect(find.text('正式版支付即将上线'), findsOneWidget);
    expect(controller.value, ProductEntitlement.free);
  });

  testWidgets('320x640与200%字体购买页可滚动且无溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final promoController = await _freePromoController(installationOffset: 72);
    final controller = ProductEntitlementController(
      gateway: MockStoreGateway(simulationEnabled: true),
      promoEntitlementListenable: promoController,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: _testApp(controller, promoController: promoController),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('full-version-page')),
      findsOneWidget,
    );
    final privacyNote = find.byKey(
      const ValueKey<String>('purchase-local-privacy-note'),
    );
    await tester.scrollUntilVisible(
      privacyNote,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final disclosure = find.byKey(
      const ValueKey<String>('promo-activation-disclosure'),
    );
    await tester.scrollUntilVisible(
      disclosure,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(disclosure);
    await tester.pumpAndSettle();
    final activateButton = find.byKey(
      const ValueKey<String>('activate-promo-code-button'),
    );
    await tester.scrollUntilVisible(
      activateButton,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('推广激活态显示独立来源并隐藏购买按钮但保留恢复', (tester) async {
    final keyPair = await Ed25519().newKeyPair();
    addTearDown(keyPair.destroy);
    final publicKey = await keyPair.extractPublicKey();
    final promoController = PromoActivationController(
      store: MemoryPromoActivationStore(
        PromoActivationRecord(
          installationId: List<int>.generate(16, (index) => index + 80),
        ),
      ),
      verifier: PromoActivationVerifier(publicKeyBytes: publicKey.bytes),
    );
    addTearDown(promoController.dispose);
    await promoController.initialize();
    final code = await const PromoActivationIssuer().issue(
      requestCode: promoController.requestCode!,
      keyPair: keyPair,
    );
    expect((await promoController.activate(code)).succeeded, isTrue);
    final controller = ProductEntitlementController(
      gateway: MockStoreGateway(simulationEnabled: false),
      promoEntitlementListenable: promoController,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(
      _testApp(controller, promoController: promoController),
    );
    expect(find.text('已通过推广激活解锁'), findsOneWidget);
    expect(find.textContaining('Ed25519 签名验证'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('purchase-full-version-button')),
      findsNothing,
    );
    final restoreButton = find.byKey(
      const ValueKey<String>('restore-purchase-button'),
    );
    await tester.scrollUntilVisible(
      restoreButton,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('恢复购买'), findsOneWidget);
    expect(find.textContaining('已通过推广激活解锁，所有数量限制'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('promo-activated-state')),
      findsOneWidget,
    );
  });
}

Future<PromoActivationController> _freePromoController({
  List<int>? publicKeyBytes,
  int installationOffset = 0,
}) async {
  final controller = PromoActivationController(
    store: MemoryPromoActivationStore(
      PromoActivationRecord(
        installationId: List<int>.generate(
          16,
          (index) => index + installationOffset + 1,
        ),
      ),
    ),
    verifier: PromoActivationVerifier(
      publicKeyBytes:
          publicKeyBytes ?? List<int>.generate(32, (index) => index + 1),
    ),
  );
  addTearDown(controller.dispose);
  await controller.initialize();
  return controller;
}

Widget _testApp(
  ProductEntitlementController controller, {
  PromoActivationController? promoController,
}) {
  Widget child = MaterialApp(home: FullVersionPage(controller: controller));
  if (promoController != null) {
    child = PromoActivationScope(controller: promoController, child: child);
  }
  return ProductEntitlementScope(controller: controller, child: child);
}
