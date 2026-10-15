import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:account_subscription_manager/core/entitlements/commercial_license_config.dart';
import 'package:account_subscription_manager/core/entitlements/commercial_purchase_gateway.dart';
import 'package:account_subscription_manager/core/entitlements/distribution_channel.dart';
import 'package:account_subscription_manager/core/platform/store_diagnostics.dart';
import 'package:account_subscription_manager/core/preferences/language_preferences.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscription_form_fields.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'commercial_license_test.dart' show FakeLicensePlatform;
import 'support/fake_vault_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cases = <List<Locale>, CardockLanguage>{
    [const Locale('en', 'US')]: CardockLanguage.english,
    [const Locale('en', 'GB')]: CardockLanguage.english,
    [const Locale('ja', 'JP')]: CardockLanguage.japanese,
    [const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')]:
        CardockLanguage.simplifiedChinese,
    [const Locale('zh', 'CN')]: CardockLanguage.simplifiedChinese,
    [const Locale('fr'), const Locale('en', 'GB')]: CardockLanguage.english,
    [const Locale('de')]: CardockLanguage.english,
    [
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      const Locale('ja'),
    ]: CardockLanguage.japanese,
    [const Locale('zh', 'TW')]: CardockLanguage.english,
    <Locale>[]: CardockLanguage.english,
  };
  for (final entry in cases.entries) {
    test('fresh iOS preferences ${entry.key} resolve without saving', () async {
      final store = MemoryLanguagePreferencesStore();
      final controller = CardockLanguageController(
        store: store,
        systemLocales: () => entry.key,
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.language, entry.value);
      expect(controller.followsSystem, isTrue);
      expect(store.value, isNull);
    });
  }
  test(
    'follow changes; choosing the current language is explicit and survives restart',
    () async {
      var locales = [const Locale('en')];
      final store = MemoryLanguagePreferencesStore();
      final first = CardockLanguageController(
        store: store,
        systemLocales: () => locales,
      );
      addTearDown(first.dispose);
      await first.load();
      locales = [const Locale('ja')];
      first.refreshSystemLanguage();
      expect(first.language, CardockLanguage.japanese);
      expect(store.value, isNull);
      await first.setLanguage(CardockLanguage.japanese);
      expect(first.followsSystem, isFalse);
      locales = [const Locale('en')];
      first.refreshSystemLanguage();
      final restarted = CardockLanguageController(
        store: store,
        systemLocales: () => locales,
      );
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(restarted.language, CardockLanguage.japanese);
      expect(first.language, CardockLanguage.japanese);
    },
  );
  test('legacy v1 saved Chinese remains authoritative on upgrade', () async {
    final store = MemoryLanguagePreferencesStore(
      LanguagePreferences.tryParse({'version': 1, 'language': 'zh_CN'}),
    );
    final controller = CardockLanguageController(
      store: store,
      systemLocales: () => [const Locale('en')],
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.language, CardockLanguage.simplifiedChinese);
    expect(controller.followsSystem, isFalse);
  });

  for (final language in CardockLanguage.values) {
    testWidgets(
      '${language.name}: first setup and unlocked home share locale, iPad layout',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 1366);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final preferences = MemoryLanguagePreferencesStore();
        final controller = CardockLanguageController(
          store: preferences,
          systemLocales: () => [language.locale],
        );
        addTearDown(controller.dispose);
        await controller.load();
        final vault = FakeVaultStore(configured: false);
        await tester.pumpWidget(
          AccountSubscriptionApp(
            vaultStore: vault,
            languageController: controller,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
          language.locale,
        );
        expect(
          find.text(AppLocalizations(language.locale).translate('创建加密库')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const ValueKey('master-password-field')),
          'TEST-ONLY-MASTER-1234',
        );
        await tester.enterText(
          find.byKey(const ValueKey('master-password-confirmation-field')),
          'TEST-ONLY-MASTER-1234',
        );
        final button = find.byKey(const ValueKey('create-vault-button'));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
          language.locale,
        );
        expect(preferences.value, isNull);
        await tester.tap(find.byKey(const ValueKey('nav-settings')));
        await tester.pumpAndSettle();
        final languageEntry = find.byKey(const ValueKey('language-setting'));
        await tester.ensureVisible(languageEntry);
        await tester.pumpAndSettle();
        await tester.tap(languageEntry);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('language-${language.storageCode}')),
        );
        await tester.pumpAndSettle();
        expect(preferences.value?.language, language);
        expect(controller.followsSystem, isFalse);

        expect(tester.takeException(), isNull);
      },
    );
    for (final edit in [false, true]) {
      testWidgets(
        '${language.name}: ${edit ? 'edit' : 'new'} payment label and saved data',
        (tester) async {
          final controller = SubscriptionFormController(
            initial: edit
                ? SubscriptionDetailsDraft(
                    serviceName: 'Fictional',
                    firstSubscribedOn: DateTime(2026, 9, 1),
                    nextRenewalOn: DateTime(2026, 10, 1),
                    paymentMethod: '我的自填方式',
                  )
                : null,
          );
          controller.serviceNameController.text = 'Fictional';
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            MaterialApp(
              locale: language.locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: SubscriptionFormFields(
                    controller: controller,
                    keyPrefix: "test",
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final label = switch (language) {
            CardockLanguage.simplifiedChinese => '选择支付方式',
            CardockLanguage.english => 'Select payment method',
            CardockLanguage.japanese => '支払い方法を選択',
          };
          final picker = find.widgetWithText(
            DropdownButtonFormField<String>,
            label,
          );
          await tester.ensureVisible(picker);
          await tester.pumpAndSettle();
          expect(picker, findsOneWidget);
          if (edit) expect(controller.paymentMethodController.text, '我的自填方式');
          await tester.tap(picker);
          await tester.pumpAndSettle();
          final alipay = AppLocalizations(language.locale).translate('支付宝');
          await tester.tap(find.text(alipay).last);
          await tester.pumpAndSettle();
          expect(controller.paymentMethodController.text, alipay);
          expect(controller.toDraft().paymentMethod, '支付宝');
          controller.paymentMethodController.text = 'User custom';
          expect(controller.toDraft().paymentMethod, 'User custom');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  test(
    'Apple unavailable then cancelled then verified purchase/restore remains retryable',
    () async {
      final platform = FakeLicensePlatform()
        ..channel = 'app_store'
        ..outcome = 'unavailable';
      final gateway = CommercialPurchaseGateway(
        config: const CommercialLicenseConfig(
          channel: CardockDistributionChannel.appStore,
        ),
        platform: platform,
      );
      addTearDown(gateway.dispose);
      expect((await gateway.purchase()).entitlement.hasFullVersion, isFalse);
      platform.outcome = 'cancelled';
      expect((await gateway.purchase()).entitlement.hasFullVersion, isFalse);
      platform.outcome = 'purchased';
      expect((await gateway.purchase()).succeeded, isFalse);
      platform.store = true;
      expect((await gateway.purchase()).succeeded, isTrue);
      expect((await gateway.restore()).succeeded, isTrue);
      final restarted = CommercialPurchaseGateway(
        config: const CommercialLicenseConfig(
          channel: CardockDistributionChannel.appStore,
        ),
        platform: platform,
      );
      addTearDown(restarted.dispose);
      expect((await restarted.query()).hasFullVersion, isTrue);
      expect(platform.purchaseCalls, 4);
    },
  );
  test(
    'diagnostic bridge failures omit exception messages and details',
    () async {
      const channel = MethodChannel('cardock/commercial_license');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(
          code: 'test_error',
          message: 'PRIVATE',
          details: {'receipt': 'PRIVATE'},
        ),
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      expect(await readStoreDiagnostics(), {
        'stage': 'bridge_error',
        'code': 'test_error',
      });
    },
  );
}
