import 'package:account_subscription_manager/core/entitlements/distribution_channel.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_service.dart';
import 'package:account_subscription_manager/core/entitlements/mock_store_gateway.dart';
import 'package:account_subscription_manager/core/entitlements/purchase_credential_model.dart';
import 'package:account_subscription_manager/core/entitlements/unavailable_purchase_gateway.dart';
import 'package:account_subscription_manager/features/product/presentation/purchase_credential_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProductEntitlementController> createController({
    ValueNotifier<ProductEntitlement>? promo,
  }) async {
    final controller = ProductEntitlementController(
      gateway: MockStoreGateway(simulationEnabled: false),
      promoEntitlementListenable: promo,
    );
    await controller.initialize();
    return controller;
  }

  Widget host(Widget child, {Locale locale = const Locale('zh', 'CN')}) =>
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: child,
      );

  testWidgets('purchase secrets stay hidden outside the real managed vault', (
    tester,
  ) async {
    final controller = await createController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        PurchaseCredentialPage(
          controller: controller,
          managementAllowed: false,
          snapshotOverride: const PurchaseCredentialSnapshot(
            source: PurchaseCredentialSource.website,
            authorizationState: InstallationAuthorizationState.active,
            orderReference: 'CARD-DEMO-SECRET',
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('purchase-credential-access-denied')),
      findsOneWidget,
    );
    expect(find.text('CARD-DEMO-SECRET'), findsNothing);
  });

  testWidgets('runtime promotional entitlement is not mislabeled as purchase', (
    tester,
  ) async {
    final promo = ValueNotifier<ProductEntitlement>(
      ProductEntitlement.purchased,
    );
    final controller = await createController(promo: promo);
    addTearDown(() {
      controller.dispose();
      promo.dispose();
    });

    await tester.pumpWidget(
      host(
        PurchaseCredentialPage(controller: controller, managementAllowed: true),
      ),
    );

    expect(find.text('既有推广激活'), findsWidgets);
    expect(find.text('官网购买'), findsNothing);
    expect(find.text('Google Play'), findsNothing);
  });

  testWidgets('website credential shows historical quota and scoped actions', (
    tester,
  ) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    var exportCalls = 0;
    var importCalls = 0;

    await tester.pumpWidget(
      host(
        PurchaseCredentialPage(
          controller: controller,
          managementAllowed: true,
          snapshotOverride: PurchaseCredentialSnapshot(
            source: PurchaseCredentialSource.website,
            authorizationState: InstallationAuthorizationState.active,
            orderReference: 'CARD-DEMO-0001',
            purchasedOn: DateTime.utc(2026, 9, 5),
            authorizationId: 'lic-demo-1',
            remainingSlotsAtIssue: 9,
          ),
          onExportWebsiteRecovery: () => exportCalls++,
          onImportWebsiteAuthorization: () => importCalls++,
        ),
      ),
    );

    expect(find.text('官网购买'), findsWidgets);
    expect(find.text('CARD-DEMO-0001'), findsOneWidget);
    expect(find.text('这里只是最近一次签发时的记录，实时名额以官网为准。'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('export-website-recovery-proof')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('import-website-installation-license')),
    );
    expect(exportCalls, 1);
    expect(importCalls, 1);
  });

  testWidgets('Google Play source exposes only store restore action', (
    tester,
  ) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    var restoreCalls = 0;

    await tester.pumpWidget(
      host(
        PurchaseCredentialPage(
          controller: controller,
          managementAllowed: true,
          snapshotOverride: const PurchaseCredentialSnapshot(
            source: PurchaseCredentialSource.googlePlay,
            authorizationState: InstallationAuthorizationState.active,
          ),
          onRestoreStorePurchase: () async {
            restoreCalls++;
          },
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('restore-google-play-purchase')),
    );
    expect(restoreCalls, 1);
    expect(
      find.byKey(const ValueKey<String>('export-website-recovery-proof')),
      findsNothing,
    );
  });

  testWidgets('unavailable Google Play channel still exposes restore safely', (
    tester,
  ) async {
    final controller = ProductEntitlementController(
      gateway: const UnavailablePurchaseGateway(
        CardockDistributionChannel.googlePlay,
      ),
    );
    await controller.initialize();
    addTearDown(controller.dispose);
    var restoreCalls = 0;

    await tester.pumpWidget(
      host(
        PurchaseCredentialPage(
          controller: controller,
          managementAllowed: true,
          onRestoreStorePurchase: () async {
            restoreCalls++;
          },
        ),
      ),
    );

    expect(find.text('Google Play（当前未购买）'), findsWidgets);
    expect(find.text('未配置'), findsWidgets);
    await tester.tap(
      find.byKey(const ValueKey<String>('restore-google-play-purchase')),
    );
    expect(restoreCalls, 1);
    expect(find.text('当前安装有效'), findsNothing);
  });
  testWidgets('new page has English and Japanese translations', (tester) async {
    final controller = await createController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        PurchaseCredentialPage(controller: controller, managementAllowed: true),
        locale: const Locale('en'),
      ),
    );
    expect(find.text('Purchase credentials'), findsOneWidget);
    expect(find.text('Not purchased'), findsWidgets);

    await tester.pumpWidget(
      host(
        PurchaseCredentialPage(controller: controller, managementAllowed: true),
        locale: const Locale('ja'),
      ),
    );
    await tester.pump();
    expect(find.text('購入証明'), findsOneWidget);
    expect(find.text('未購入'), findsWidgets);
  });
}
