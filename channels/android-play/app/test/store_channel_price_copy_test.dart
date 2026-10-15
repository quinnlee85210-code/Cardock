import 'package:account_subscription_manager/core/entitlements/commercial_license_config.dart';
import 'package:account_subscription_manager/core/entitlements/commercial_purchase_gateway.dart';
import 'package:account_subscription_manager/core/entitlements/distribution_channel.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_service.dart';
import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/features/about/presentation/developer_note_page.dart';
import 'package:account_subscription_manager/features/product/presentation/full_version_page.dart';
import 'package:account_subscription_manager/features/product/presentation/full_version_upsell_sheet.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'commercial_license_test.dart' show FakeLicensePlatform;

class EuroPlatform extends FakeLicensePlatform {
  @override
  Future<String?> storePrice() async => '€3.49';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('cardock/commercial_license');
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (call) async => null),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null),
  );
  for (final channel in [
    CardockDistributionChannel.googlePlay,
    CardockDistributionChannel.appStore,
  ]) {
    for (final language in ['zh', 'en', 'ja']) {
      testWidgets(
        '${channel.wireValue}/$language does not fabricate prices or currency prefixes',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(800, 1400);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final platform = EuroPlatform()..channel = channel.wireValue;
          final controller = ProductEntitlementController(
            gateway: CommercialPurchaseGateway(
              config: CommercialLicenseConfig(channel: channel),
              platform: platform,
            ),
          );
          addTearDown(controller.dispose);
          await controller.initialize();
          Widget wrap(Widget child) => ProductEntitlementScope(
            controller: controller,
            child: MaterialApp(
              theme: AppTheme.light(),
              locale: Locale(language),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: child,
            ),
          );
          await tester.pumpWidget(
            wrap(
              Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showFullVersionUpsell(
                      context,
                      scene: FullVersionUpsellScene.accountLimit,
                      usageLabel: '15/15',
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          expect(find.textContaining('9.9'), findsNothing);
          expect(find.textContaining('CN€'), findsNothing);
          await tester.tap(
            find.byKey(const ValueKey<String>('full-version-upsell-unlock')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(FullVersionPage), findsOneWidget);
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey<String>('purchase-full-version-button')),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('€3.49'), findsWidgets);
          expect(find.textContaining('CN€'), findsNothing);
          expect(find.textContaining('9.9'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(wrap(const DeveloperNotePage()));
          await tester.pumpAndSettle();
          expect(find.textContaining('9.9'), findsNothing);
          for (final key in [
            'developer-note-principles',
            'developer-note-purchase',
          ]) {
            await tester.scrollUntilVisible(
              find.byKey(ValueKey<String>(key)),
              300,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expect(find.textContaining('9.9'), findsNothing);
          }
          String? copied;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, (call) async {
                if (call.method == 'Clipboard.setData') {
                  copied = (call.arguments as Map)['text'] as String?;
                }
                return null;
              });
          addTearDown(
            () => TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          await tester.ensureVisible(
            find.byKey(
              const ValueKey<String>('developer-note-copy-recommendation'),
            ),
          );
          await tester.tap(
            find.byKey(
              const ValueKey<String>('developer-note-copy-recommendation'),
            ),
          );
          await tester.pumpAndSettle();
          expect(copied, isNotNull);
          expect(copied, isNot(contains('9.9')));
          if (language == 'en') {
            expect(copied, contains('store price'));
          }
          if (language == 'ja') {
            expect(copied, contains('ストア価格'));
          }
          expect(platform.purchaseCalls, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
