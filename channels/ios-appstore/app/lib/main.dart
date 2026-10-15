import 'package:flutter/widgets.dart';
import 'core/platform/ios_core.dart';

import 'app/account_subscription_app.dart';
import 'core/entitlements/distribution_channel.dart';
import 'core/entitlements/mock_store_gateway.dart';
import 'core/entitlements/purchase_gateway.dart';
import 'core/entitlements/commercial_purchase_gateway.dart';
import 'core/entitlements/commercial_license_config.dart';
import 'core/entitlements/promo_activation_store.dart';
import 'core/notifications/reminder_scheduler.dart';
import 'core/platform/app_language_bridge.dart';
import 'core/platform/desktop_icon_controller.dart';
import 'core/platform/notification_reliability.dart';
import 'core/platform/screen_protection.dart';
import 'core/preferences/appearance_preferences.dart';
import 'core/preferences/language_preferences.dart';

PurchaseGateway _purchaseGatewayForDistribution() =>
    switch (CardockDistributionConfig.channel) {
      CardockDistributionChannel.development => MockStoreGateway(),
      _ => CommercialPurchaseGateway(
        config: CommercialLicenseConfig.environment(),
      ),
    };

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await prepareIOSPrivateStorage();
  } on Object {
    runApp(IOSStorageUnavailableApp(retry: main));
    acknowledgeIOSForegroundFrame();
    return;
  }
  final appearanceStore = await FileAppearancePreferencesStore.create();
  final languageStore = await FileLanguagePreferencesStore.create();
  final languageController = CardockLanguageController(store: languageStore);
  await languageController.load();
  try {
    await const CardockPlatformLanguageBridge().updateLanguage(
      languageController.language,
    );
  } on Object {
    // Keep startup available on hosts where the Android bridge is absent.
  }
  final promoActivationStore = await FilePromoActivationStore.create();
  runApp(
    AccountSubscriptionApp(
      reminderScheduler: LocalReminderScheduler(
        language: languageController.language,
      ),
      appearanceStore: appearanceStore,
      languageController: languageController,
      desktopIconBridge: MethodChannelDesktopIconBridge(),
      notificationReliabilityService:
          MethodChannelNotificationReliabilityService(),
      screenProtectionService: MethodChannelScreenProtectionService(),
      purchaseGateway: _purchaseGatewayForDistribution(),
      promoActivationStore: promoActivationStore,
    ),
  );
  acknowledgeIOSForegroundFrame();
}
