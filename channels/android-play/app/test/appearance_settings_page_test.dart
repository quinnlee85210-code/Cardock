import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_service.dart';
import 'package:account_subscription_manager/core/entitlements/mock_store_gateway.dart';
import 'package:account_subscription_manager/core/notifications/reminder_scheduler.dart';
import 'package:account_subscription_manager/core/platform/desktop_icon_controller.dart';
import 'package:account_subscription_manager/core/preferences/appearance_preferences.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/core/theme/cardock_tokens.dart';
import 'package:account_subscription_manager/core/theme/custom_theme.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/settings/presentation/settings_page.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

const _testMasterPassword = 'TEST-ONLY-MASTER-1234';

void main() {
  testWidgets('Paper Archive预览后开启跟随会同时应用主题和橙墨旧刊图标', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final state = AppState(
      vaultStore: FakeVaultStore(
        configured: true,
        acceptedPassword: _testMasterPassword,
      ),
    );
    addTearDown(state.dispose);
    await state.initialize();
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);

    final appearanceStore = MemoryAppearancePreferencesStore(
      const AppearancePreferences(
        desktopIconMode: CardockDesktopIconMode.ceramicBlue,
      ),
    );
    final desktopIconBridge = _RecordingDesktopIconBridge();
    final appearanceController = CardockAppearanceController(
      store: appearanceStore,
      desktopIconBridge: desktopIconBridge,
    );
    addTearDown(appearanceController.dispose);
    await appearanceController.load();
    final entitlementController = ProductEntitlementController(
      gateway: MockStoreGateway(simulationEnabled: true),
    );
    addTearDown(entitlementController.dispose);
    await entitlementController.initialize();

    await tester.pumpWidget(
      ProductEntitlementScope(
        controller: entitlementController,
        child: CardockAppearanceScope(
          controller: appearanceController,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SettingsPage(appState: state, onLock: () {}),
            ),
          ),
        ),
      ),
    );
    final entry = find.byKey(
      const ValueKey<String>('appearance-settings-entry'),
    );
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    for (final family in CardockThemeFamily.values.where(
      (candidate) => candidate.isPremium,
    )) {
      expect(
        find.byKey(ValueKey<String>('appearance-theme-lock-${family.name}')),
        findsOneWidget,
      );
    }
    await tester.tap(
      find.byKey(const ValueKey<String>('appearance-theme-obsidianGold')),
    );
    await tester.pumpAndSettle();
    expect(appearanceController.family, CardockThemeFamily.paperArchive);
    expect(
      appearanceStore.value?.family ?? CardockThemeFamily.paperArchive,
      CardockThemeFamily.paperArchive,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('appearance-apply-theme')),
    );
    await tester.pumpAndSettle();
    expect(find.text('该主题为完整版专属'), findsOneWidget);
    expect(appearanceController.family, CardockThemeFamily.paperArchive);
    await tester.tap(
      find.byKey(const ValueKey<String>('full-version-upsell-dismiss')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('appearance-theme-lock-paperArchive')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('appearance-theme-lock-ceramicBlue')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('appearance-theme-paperArchive')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('appearance-apply-theme')),
    );
    await tester.pumpAndSettle();
    expect(find.text('该主题为完整版专属'), findsNothing);
    expect(appearanceController.family, CardockThemeFamily.paperArchive);
    await tester.tap(
      find.byKey(const ValueKey<String>('appearance-theme-obsidianGold')),
    );
    await tester.pumpAndSettle();

    await entitlementController.debugSetEntitlement(
      ProductEntitlement.purchased,
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('appearance-apply-theme')),
    );
    await tester.pumpAndSettle();
    expect(appearanceController.family, CardockThemeFamily.obsidianGold);
    expect(appearanceStore.value?.family, CardockThemeFamily.obsidianGold);

    await tester.tap(
      find.byKey(const ValueKey<String>('appearance-theme-paperArchive')),
    );
    await tester.pumpAndSettle();
    expect(appearanceController.family, CardockThemeFamily.obsidianGold);

    final followTheme = find.byKey(
      const ValueKey<String>('appearance-desktop-icon-follow-theme'),
    );
    final appearanceScroll = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      followTheme,
      240,
      scrollable: appearanceScroll,
    );
    await tester.drag(appearanceScroll, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(followTheme);
    await tester.pumpAndSettle();

    expect(appearanceController.family, CardockThemeFamily.paperArchive);
    expect(
      appearanceController.desktopIconMode,
      CardockDesktopIconMode.followTheme,
    );
    expect(
      appearanceController.desktopIconFamily,
      CardockLauncherFamily.paperArchive,
    );
    expect(desktopIconBridge.active, CardockLauncherFamily.paperArchive);
    expect(appearanceStore.value?.family, CardockThemeFamily.paperArchive);
    expect(
      appearanceStore.value?.desktopIconMode,
      CardockDesktopIconMode.followTheme,
    );
  });

  testWidgets('外观页有九个应用主题、八套对应桌面图标且名称只显示中文', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final account = _account();
    final subscriptions = <SubscriptionRecord>[
      _subscription(id: 'subscription-1', daysUntilRenewal: 5),
      _subscription(id: 'subscription-2', daysUntilRenewal: 65),
    ];
    final state = AppState(
      vaultStore: FakeVaultStore(
        configured: true,
        acceptedPassword: _testMasterPassword,
        snapshot: VaultSnapshot(
          nextAccountId: 2,
          accounts: <AccountRecord>[account],
          nextSubscriptionId: 3,
          subscriptions: subscriptions,
          recentAccountIds: <String>[account.id],
        ),
      ),
      reminderScheduler: const NoopReminderScheduler(),
    );
    addTearDown(state.dispose);
    await state.initialize();
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);

    final customWithVividFallback = CardockCustomTheme.defaults.copyWith(
      launcherFallback: CardockLauncherFamily.mistCoral,
    );
    final appearanceStore = MemoryAppearancePreferencesStore(
      AppearancePreferences(
        customTheme: customWithVividFallback,
        desktopIconMode: CardockDesktopIconMode.ceramicBlue,
      ),
    );
    final desktopIconBridge = _RecordingDesktopIconBridge();
    final appearanceController = CardockAppearanceController(
      store: appearanceStore,
      desktopIconBridge: desktopIconBridge,
    );
    addTearDown(appearanceController.dispose);
    await appearanceController.load();
    final entitlementController = ProductEntitlementController(
      gateway: MockStoreGateway(
        initialEntitlement: ProductEntitlement.purchased,
        simulationEnabled: true,
      ),
    );
    addTearDown(entitlementController.dispose);
    await entitlementController.initialize();

    await tester.pumpWidget(
      ProductEntitlementScope(
        controller: entitlementController,
        child: ListenableBuilder(
          listenable: appearanceController,
          builder: (context, child) => CardockAppearanceScope(
            controller: appearanceController,
            child: MaterialApp(
              theme: AppTheme.light(
                family: appearanceController.family,
                customTheme: appearanceController.customTheme,
              ),
              home: Scaffold(
                body: SettingsPage(appState: state, onLock: () {}),
              ),
            ),
          ),
        ),
      ),
    );

    final entry = find.byKey(
      const ValueKey<String>('appearance-settings-entry'),
    );
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('appearance-settings-page')),
      findsOneWidget,
    );
    expect(find.text('卡坞 · Cardock'), findsOneWidget);
    expect(find.textContaining('应用内品牌标志自动跟随主题'), findsOneWidget);
    expect(find.textContaining('应用内 LOGO 颜色'), findsNothing);
    expect(find.textContaining('应用内 LOGO 选择'), findsNothing);
    expect(find.text('橙墨旧刊'), findsWidgets);
    expect(find.text('Paper Archive'), findsNothing);
    expect(find.text('Standard'), findsNothing);
    expect(find.text('Prime'), findsNothing);
    expect(find.text('Vivid'), findsNothing);

    final appearanceScroll = find.byType(Scrollable).last;
    for (final family in cardockSelectableThemeFamilies) {
      final themeCard = find.byKey(
        ValueKey<String>('appearance-theme-${family.name}'),
      );
      await tester.scrollUntilVisible(
        themeCard,
        240,
        scrollable: appearanceScroll,
      );
      expect(themeCard, findsOneWidget, reason: '九个应用内主题都必须可见：${family.name}');
    }
    for (final family in cardockLauncherFamilies) {
      final launcherCard = find.byKey(
        ValueKey<String>('appearance-desktop-icon-${family.name}'),
      );
      await tester.scrollUntilVisible(
        launcherCard,
        240,
        scrollable: appearanceScroll,
      );
      expect(
        launcherCard,
        findsOneWidget,
        reason: '八套打包桌面图标都必须可见：${family.name}',
      );
    }
    expect(
      find.byKey(const ValueKey<String>('appearance-desktop-icon-custom')),
      findsNothing,
    );
    expect(find.textContaining('launcher_custom'), findsNothing);
    expect(find.textContaining('系统桌面可能需要几秒刷新'), findsOneWidget);
    final launcherAssets = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<AssetImage>()
        .map((provider) => provider.assetName)
        .where((asset) => asset.contains('launcher'))
        .toList(growable: false);
    expect(launcherAssets, hasLength(8));
    expect(
      launcherAssets.any(
        (asset) =>
            asset.contains('custom') || asset.contains('launcher_custom'),
      ),
      isFalse,
    );

    final monoTheme = find.byKey(
      const ValueKey<String>('appearance-theme-neonZero'),
    );
    await tester.scrollUntilVisible(
      monoTheme,
      -240,
      scrollable: appearanceScroll,
    );
    await tester.tap(monoTheme);
    await tester.pumpAndSettle();

    expect(appearanceController.family, CardockThemeFamily.paperArchive);
    expect(appearanceStore.value?.family, CardockThemeFamily.paperArchive);
    await tester.tap(
      find.byKey(const ValueKey<String>('appearance-apply-theme')),
    );
    await tester.pumpAndSettle();

    expect(appearanceController.family, CardockThemeFamily.neonZero);
    expect(appearanceStore.value?.family, CardockThemeFamily.neonZero);
    final monoContext = tester.element(
      find.byKey(const ValueKey<String>('appearance-settings-page')),
    );
    expect(
      Theme.of(monoContext).colorScheme.primary,
      CardockTokens.palette(
        CardockThemeFamily.neonZero,
        Brightness.light,
      ).primary,
    );

    final restoredController = CardockAppearanceController(
      store: appearanceStore,
      desktopIconBridge: _RecordingDesktopIconBridge(),
    );
    addTearDown(restoredController.dispose);
    await restoredController.load();
    expect(restoredController.family, CardockThemeFamily.neonZero);

    final customTheme = find.byKey(
      const ValueKey<String>('appearance-theme-custom'),
    );
    await tester.ensureVisible(customTheme);
    await tester.tap(customTheme);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('appearance-apply-theme')),
    );
    await tester.pumpAndSettle();

    expect(appearanceController.family, CardockThemeFamily.custom);
    expect(
      appearanceController.desktopIconMode,
      CardockDesktopIconMode.ceramicBlue,
    );
    expect(
      appearanceController.desktopIconFamily,
      CardockLauncherFamily.ceramicBlue,
    );
    expect(desktopIconBridge.setCalls, isEmpty);

    final followTheme = find.byKey(
      const ValueKey<String>('appearance-desktop-icon-follow-theme'),
    );
    await tester.ensureVisible(followTheme);
    await tester.tap(followTheme);
    await tester.pumpAndSettle();

    expect(
      appearanceController.desktopIconMode,
      CardockDesktopIconMode.followTheme,
    );
    expect(
      appearanceController.desktopIconFamily,
      CardockLauncherFamily.mistCoral,
    );
    expect(desktopIconBridge.active, CardockLauncherFamily.mistCoral);
    expect(desktopIconBridge.setCalls, <CardockLauncherFamily>[
      CardockLauncherFamily.mistCoral,
    ]);
    expect(
      appearanceStore.value?.desktopIconMode,
      CardockDesktopIconMode.followTheme,
    );
    expect(
      appearanceStore.value?.desktopIconFamily,
      CardockLauncherFamily.mistCoral,
    );
    expect(find.textContaining('自定义主题使用已选的固定图标回退'), findsOneWidget);
    expect(find.text('桌面图标将在几秒内更新'), findsOneWidget);

    final editCustom = find.byKey(
      const ValueKey<String>('appearance-edit-custom-theme'),
    );
    await tester.ensureVisible(editCustom);
    await tester.tap(editCustom);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('custom-theme-editor-page')),
      findsOneWidget,
    );
    expect(find.text('1 个账号 · 2 项订阅'), findsNothing);
    expect(find.text('1 项待续'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('custom-preview-home')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('custom-theme-quick-controls')),
      findsOneWidget,
    );
  });
  testWidgets('9 主题选择器在 320/360/390/411 与 1.0/1.3/1.5/2.0 字号无溢出', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final state = AppState(
      vaultStore: FakeVaultStore(
        configured: true,
        acceptedPassword: _testMasterPassword,
      ),
    );
    addTearDown(state.dispose);
    await state.initialize();
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);

    final appearanceController = CardockAppearanceController(
      store: MemoryAppearancePreferencesStore(),
      desktopIconBridge: _RecordingDesktopIconBridge(),
    );
    addTearDown(appearanceController.dispose);
    await appearanceController.load();
    final entitlementController = ProductEntitlementController(
      gateway: MockStoreGateway(
        initialEntitlement: ProductEntitlement.purchased,
        simulationEnabled: true,
      ),
    );
    addTearDown(entitlementController.dispose);
    await entitlementController.initialize();

    for (final width in <double>[320, 360, 390, 411]) {
      for (final scale in <double>[1, 1.3, 1.5, 2]) {
        // Height is deliberately generous: this matrix validates narrow-width
        // and text-scale layout, not the Settings root page's scroll position.
        tester.view.physicalSize = Size(width, 1400);
        await tester.pumpWidget(
          ProductEntitlementScope(
            controller: entitlementController,
            child: CardockAppearanceScope(
              controller: appearanceController,
              child: MaterialApp(
                theme: AppTheme.light(),
                builder: (context, child) {
                  final media = MediaQuery.of(context);
                  return MediaQuery(
                    data: media.copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  );
                },
                home: Scaffold(
                  body: SettingsPage(appState: state, onLock: () {}),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final entry = find.byKey(
          const ValueKey<String>('appearance-settings-entry'),
        );
        final rootScroll = find
            .descendant(
              of: find.byKey(const ValueKey<String>('settings-page')),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(entry, 260, scrollable: rootScroll);
        await tester.ensureVisible(entry);
        await tester.pumpAndSettle();
        expect(entry.hitTestable(), findsOneWidget, reason: '$width/$scale');
        await tester.tap(entry.hitTestable());
        await tester.pumpAndSettle();

        final appearanceScroll = find.byType(Scrollable).last;
        for (final family in cardockSelectableThemeFamilies) {
          final themeCard = find.byKey(
            ValueKey<String>('appearance-theme-${family.name}'),
          );
          await tester.scrollUntilVisible(
            themeCard,
            220,
            scrollable: appearanceScroll,
          );
          expect(themeCard, findsOneWidget, reason: '$width/$scale');
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$width/$scale');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    }
  });
}

final class _RecordingDesktopIconBridge implements DesktopIconBridge {
  CardockLauncherFamily active = CardockLauncherFamily.ceramicBlue;
  final List<CardockLauncherFamily> setCalls = <CardockLauncherFamily>[];

  @override
  Future<CardockLauncherFamily?> getActiveIcon() async => active;

  @override
  Future<void> setIcon(CardockLauncherFamily family) async {
    setCalls.add(family);
    active = family;
  }
}

AccountRecord _account() => AccountRecord.fromDraft(
  id: 'account-1',
  draft: AccountDraft(
    platformName: '测试平台',
    category: '测试分类',
    loginAccount: 'test@example.invalid',
  ),
);

SubscriptionRecord _subscription({
  required String id,
  required int daysUntilRenewal,
}) => SubscriptionRecord.fromDraft(
  id: id,
  draft: SubscriptionDraft(
    accountId: 'account-1',
    details: SubscriptionDetailsDraft(
      serviceName: '本机订阅 $id',
      planName: '测试方案',
      amount: '18.00',
      currency: 'CNY',
      firstSubscribedOn: DateTime(2026, 1, 1),
      nextRenewalOn: subscriptionDateOnly(
        DateTime.now(),
      ).add(Duration(days: daysUntilRenewal)),
    ),
  ),
);
