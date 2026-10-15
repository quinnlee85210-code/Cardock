import 'package:account_subscription_manager/core/entitlements/commercial_license_config.dart';
import 'package:account_subscription_manager/core/entitlements/commercial_purchase_gateway.dart';
import 'package:account_subscription_manager/core/entitlements/distribution_channel.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_service.dart';
import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/features/product/presentation/full_version_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'commercial_license_test.dart' show FakeLicensePlatform;

void main() {
  for (final channel in [
    CardockDistributionChannel.website,
    CardockDistributionChannel.googlePlay,
    CardockDistributionChannel.appStore,
  ]) {
    for (final entry in {
      'zh': '橙墨旧刊主题（免费）',
      'en': 'Paper Archive theme (free)',
      'ja': 'ペーパーアーカイブテーマ（無料）',
    }.entries) {
      testWidgets(
        '${channel.wireValue}/${entry.key} shows the free Paper Archive theme',
        (tester) async {
          final platform = FakeLicensePlatform()..channel = channel.wireValue;
          final controller = ProductEntitlementController(
            gateway: CommercialPurchaseGateway(
              config: CommercialLicenseConfig(channel: channel),
              platform: platform,
            ),
          );
          addTearDown(controller.dispose);
          await controller.initialize();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              locale: Locale(entry.key),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: FullVersionPage(controller: controller),
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey<String>('free-edition-card')),
            220,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(find.text(entry.value), findsOneWidget);
          expect(controller.hasFullVersion, isFalse);
          expect(platform.purchaseCalls, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
