import 'package:account_subscription_manager/core/entitlements/commercial_license_config.dart';
import 'package:account_subscription_manager/core/entitlements/commercial_purchase_gateway.dart';
import 'package:account_subscription_manager/core/entitlements/distribution_channel.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_service.dart';
import 'package:account_subscription_manager/features/product/presentation/full_version_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:account_subscription_manager/l10n/translations_commercial.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'commercial_license_test.dart' show FakeLicensePlatform;

void main() {
  for (final channel in [
    CardockDistributionChannel.googlePlay,
    CardockDistributionChannel.appStore,
  ]) {
    testWidgets(
      '${channel.wireValue} remains free and displays the store price before in-app purchase',
      (tester) async {
        final platform = FakeLicensePlatform()
          ..channel = channel.wireValue
          ..outcome = 'cancelled';
        final controller = ProductEntitlementController(
          gateway: CommercialPurchaseGateway(
            config: CommercialLicenseConfig(channel: channel),
            platform: platform,
          ),
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await tester.pumpWidget(
          MaterialApp(home: FullVersionPage(controller: controller)),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey<String>('free-edition-card')),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('最多 5 个订阅项'), findsOneWidget);
        expect(find.text('最多 15 个账户条目'), findsOneWidget);
        expect(find.text('橙墨旧刊主题（免费）'), findsOneWidget);
        final button = find.byKey(
          const ValueKey<String>('purchase-full-version-button'),
        );
        await tester.scrollUntilVisible(
          button,
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('¥9.90 一次买断'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('promo-activation-disclosure')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('debug-entitlement-switch')),
          findsNothing,
        );
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(platform.purchaseCalls, 1);
        expect(controller.hasFullVersion, isFalse);
        expect(find.text('已取消付款。'), findsOneWidget);
      },
    );
  }
  test(
    'every new commercial message has explicit English and Japanese translations',
    () {
      const english = AppLocalizations(Locale('en'));
      const japanese = AppLocalizations(Locale('ja'));
      expect(
        commercialEnglishTranslations.keys.toSet(),
        commercialJapaneseTranslations.keys.toSet(),
      );
      for (final source in commercialEnglishTranslations.keys) {
        expect(english.hasTranslation(source), isTrue);
        expect(japanese.hasTranslation(source), isTrue);
        expect(
          RegExp(r'[\u3400-\u9FFF]').hasMatch(english.translate(source)),
          isFalse,
          reason: source,
        );
      }
    },
  );
}
