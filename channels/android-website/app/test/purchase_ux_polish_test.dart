import 'dart:convert';
import 'package:account_subscription_manager/core/entitlements/commercial_license_config.dart';
import 'package:account_subscription_manager/core/entitlements/commercial_purchase_gateway.dart';
import 'package:account_subscription_manager/core/entitlements/distribution_channel.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_service.dart';
import 'package:account_subscription_manager/core/entitlements/purchase_credential_model.dart';
import 'package:account_subscription_manager/features/product/presentation/full_version_page.dart';
import 'package:account_subscription_manager/features/product/presentation/purchase_credential_page.dart';
import 'package:account_subscription_manager/features/product/presentation/website_purchase_access.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'commercial_license_test.dart' show FakeLicensePlatform;
import 'website_purchase_gateway_test.dart' show FakeOfflineBrowser;

void main() {
  late ProductEntitlementController controller;
  late WebsitePurchaseAccess access;
  late FakeOfflineBrowser reader;
  setUp(() async {
    reader = FakeOfflineBrowser();
    access = WebsitePurchaseAccess()..update(true);
    controller = ProductEntitlementController(
      gateway: CommercialPurchaseGateway(
        config: CommercialLicenseConfig(
          channel: CardockDistributionChannel.website,
          checkoutUrl: 'https://maskden.com/cardock/buy',
          websitePublicKeys: jsonEncode({
            'test': base64Url.encode(List.filled(32, 1)),
          }),
        ),
        platform: FakeLicensePlatform(),
        offlineBrowser: reader.bridge,
        openCheckout: reader.open,
      ),
    );
    await controller.initialize();
  });
  tearDown(() {
    controller.dispose();
    access.dispose();
  });
  Widget host(Widget child, String lang) => MaterialApp(
    locale: Locale(lang),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.3)),
      child: child!,
    ),
    home: WebsitePurchaseScope(access: access, child: child),
  );
  for (final (lang, manual, label) in [
    ('zh', '手动粘贴网站授权码', '网站授权码'),
    ('en', 'Paste a website license code manually', 'Website license code'),
    ('ja', '公式サイトのライセンスコードを貼り付ける', '公式サイトのライセンスコード'),
  ]) {
    testWidgets(
      '$lang narrow large-text purchase help stays below orders and manual dialog agrees',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          host(FullVersionPage(controller: controller), lang),
        );
        await tester.pumpAndSettle();
        final help = find.byKey(const ValueKey('website-orders-help'));
        await tester.scrollUntilVisible(help, 160);
        expect(help, findsOneWidget);
        expect(
          tester.getTopLeft(help).dy,
          greaterThanOrEqualTo(
            tester
                .getBottomLeft(
                  find.byKey(const ValueKey('website-orders-entry')),
                )
                .dy,
          ),
        );
        await tester.scrollUntilVisible(find.text(manual), 160);
        await tester.tap(find.text(manual));
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(manual),
          ),
          findsOneWidget,
        );
        expect(find.text(label), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(reader.beginCalls, 0);
        expect(reader.openCalls, 0);
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      },
    );
    for (final state in InstallationAuthorizationState.values) {
      testWidgets(
        '$lang website $state hides order metadata without requests',
        (tester) async {
          final snapshot = PurchaseCredentialSnapshot(
            source: PurchaseCredentialSource.website,
            authorizationState: state,
            purchasedOn: DateTime.utc(2026, 9, 10),
            authorizationId: 'synthetic-license-retained',
          );
          await tester.pumpWidget(
            host(
              PurchaseCredentialPage(
                controller: controller,
                managementAllowed: true,
                snapshotOverride: snapshot,
              ),
              lang,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('SYNTHETIC-ORDER-PRESERVED'), findsNothing);
          expect(find.textContaining('2026-09-10'), findsNothing);
          expect(find.text('synthetic-license-retained'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('credential-website-orders')),
            findsOneWidget,
          );
          expect(reader.beginCalls, 0);
          expect(reader.openCalls, 0);
          expect(snapshot.orderReference, isNull);
          expect(snapshot.purchasedOn, DateTime.utc(2026, 9, 10));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final source in [
    PurchaseCredentialSource.googlePlay,
    PurchaseCredentialSource.appStore,
  ]) {
    testWidgets('$source retains valid order and purchase date', (
      tester,
    ) async {
      // Source-specific store fixture exercises the same details component.
      await tester.pumpWidget(
        host(
          PurchaseCredentialPage(
            controller: controller,
            managementAllowed: true,
            snapshotOverride: PurchaseCredentialSnapshot(
              source: source,
              authorizationState: InstallationAuthorizationState.active,
              orderReference: 'SYNTHETIC-STORE-ORDER',
              purchasedOn: DateTime(2026, 9, 10),
            ),
          ),
          'zh',
        ),
      );
      expect(find.text('订单参考'), findsOneWidget);
      expect(find.text('购买日期'), findsOneWidget);
      expect(find.text('SYNTHETIC-STORE-ORDER'), findsOneWidget);
      expect(find.text('2026-09-10'), findsOneWidget);
    });
  }
}
