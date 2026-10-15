import 'dart:io';

import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:account_subscription_manager/core/entitlements/distribution_channel.dart';
import 'package:account_subscription_manager/core/preferences/language_preferences.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final isPlay =
      CardockDistributionConfig.channel ==
      CardockDistributionChannel.googlePlay;

  test('supported system preference order and English fallback', () async {
    final cases = <List<Locale>, CardockLanguage>{
      [const Locale('en', 'US')]: CardockLanguage.english,
      [const Locale('en', 'GB')]: CardockLanguage.english,
      [const Locale('ja', 'JP')]: CardockLanguage.japanese,
      [const Locale('zh', 'CN')]: CardockLanguage.simplifiedChinese,
      [const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')]:
          CardockLanguage.simplifiedChinese,
      [const Locale('fr'), const Locale('ja')]: CardockLanguage.japanese,
      [const Locale('ja'), const Locale('en')]: CardockLanguage.japanese,
      [const Locale('de')]: CardockLanguage.english,
      [const Locale('zh', 'TW')]: CardockLanguage.english,
      <Locale>[]: CardockLanguage.english,
    };
    for (final entry in cases.entries) {
      final store = MemoryLanguagePreferencesStore();
      final controller = CardockLanguageController(
        store: store,
        systemLocales: () => entry.key,
      );
      await controller.load();
      expect(controller.language, entry.value, reason: entry.key.toString());
      expect(store.value, isNull);
      controller.dispose();
    }
  });

  test('every legacy v1 manual choice wins over system language', () async {
    for (final language in CardockLanguage.values) {
      var locales = [const Locale('en')];
      final saved = LanguagePreferences.tryParse({
        'version': 1,
        'language': language.storageCode,
      });
      final store = MemoryLanguagePreferencesStore(saved);
      final controller = CardockLanguageController(
        store: store,
        systemLocales: () => locales,
      );
      await controller.load();
      locales = [const Locale('ja')];
      controller.refreshSystemLanguage();
      expect(controller.language, language);
      expect(controller.followsSystem, isFalse);
      expect(store.value, saved);
      controller.dispose();
    }
  });

  test('choosing inferred current language persists across restart', () async {
    final store = MemoryLanguagePreferencesStore();
    final first = CardockLanguageController(
      store: store,
      systemLocales: () => [const Locale('en')],
    );
    addTearDown(first.dispose);
    await first.load();
    expect(store.value, isNull);
    await first.setLanguage(CardockLanguage.english);
    expect(first.followsSystem, isFalse);
    final restarted = CardockLanguageController(
      store: store,
      systemLocales: () => [const Locale('ja')],
    );
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(restarted.language, CardockLanguage.english);
  });

  test(
    'failed explicit save preserves inferred language and follow mode',
    () async {
      final controller = CardockLanguageController(
        store: _FailingStore(),
        systemLocales: () => [const Locale('en')],
      );
      addTearDown(controller.dispose);
      await controller.load();
      await expectLater(
        controller.setLanguage(CardockLanguage.japanese),
        throwsA(isA<FileSystemException>()),
      );
      expect(controller.language, CardockLanguage.english);
      expect(controller.followsSystem, isTrue);
    },
  );

  testWidgets(
    'automatic locale follows only Play on Android',
    (tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('ja', 'JP')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final controller = CardockLanguageController(
        store: MemoryLanguagePreferencesStore(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      final follows = isPlay && defaultTargetPlatform == TargetPlatform.android;
      expect(controller.followsSystem, follows);
      expect(
        controller.language,
        follows ? CardockLanguage.japanese : CardockLanguage.simplifiedChinese,
      );
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  for (final systemLanguage in CardockLanguage.values) {
    testWidgets(
      '${systemLanguage.name}: first password, home and manual choice',
      (tester) async {
        tester.platformDispatcher.localesTestValue = [systemLanguage.locale];
        addTearDown(tester.platformDispatcher.clearLocalesTestValue);
        tester.view.physicalSize = const Size(393, 873);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final expected = isPlay
            ? systemLanguage
            : CardockLanguage.simplifiedChinese;
        final store = MemoryLanguagePreferencesStore();
        final controller = CardockLanguageController(store: store);
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
        expect(find.byKey(const ValueKey('vault-setup-page')), findsOneWidget);
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
          expected.locale,
        );
        expect(
          find.text(AppLocalizations(expected.locale).translate('创建加密库')),
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
        final create = find.byKey(const ValueKey('create-vault-button'));
        await tester.ensureVisible(create);
        await tester.pumpAndSettle();
        await tester.tap(create);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
        expect(controller.language, expected);
        expect(store.value, isNull);
        await tester.tap(find.byKey(const ValueKey('nav-settings')));
        await tester.pumpAndSettle();
        final tile = find.byKey(const ValueKey('language-setting'));
        await tester.scrollUntilVisible(
          tile,
          280,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('language-${expected.storageCode}')),
        );
        await tester.pumpAndSettle();
        if (isPlay) {
          expect(store.value?.language, expected);
          expect(controller.followsSystem, isFalse);
          tester.platformDispatcher.localesTestValue = [
            expected == CardockLanguage.japanese
                ? const Locale('en')
                : const Locale('ja'),
          ];
          await tester.pumpAndSettle();
          expect(controller.language, expected);
          final restarted = CardockLanguageController(store: store);
          await restarted.load();
          expect(restarted.language, expected);
          restarted.dispose();
        }
        expect(vault.createCalls, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'system change refreshes setup without persisting a choice',
    (tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('en')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final store = MemoryLanguagePreferencesStore();
      final controller = CardockLanguageController(store: store);
      addTearDown(controller.dispose);
      await controller.load();
      await tester.pumpWidget(
        AccountSubscriptionApp(
          vaultStore: FakeVaultStore(),
          languageController: controller,
        ),
      );
      await tester.pumpAndSettle();
      tester.platformDispatcher.localesTestValue = [const Locale('ja')];
      await tester.pumpAndSettle();
      final expected = isPlay
          ? CardockLanguage.japanese
          : CardockLanguage.simplifiedChinese;
      expect(
        find.text(AppLocalizations(expected.locale).translate('创建加密库')),
        findsOneWidget,
      );
      expect(controller.language, expected);
      expect(store.value, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

class _FailingStore implements LanguagePreferencesStore {
  @override
  Future<LanguagePreferences?> read() async => null;

  @override
  Future<void> write(LanguagePreferences preferences) async {
    throw const FileSystemException('test save failure');
  }
}
