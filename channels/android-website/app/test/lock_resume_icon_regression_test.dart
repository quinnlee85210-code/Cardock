import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_guard.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/platform/desktop_icon_controller.dart';
import 'package:account_subscription_manager/core/preferences/appearance_preferences.dart';
import 'package:account_subscription_manager/core/theme/cardock_theme_types.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/vault/presentation/vault_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_vault_store.dart';

const password = 'TEST-ONLY-Lock-Resume-1234';
Future<void> unlock(WidgetTester tester, [String value = password]) async {
  await tester.enterText(
    find.byKey(const ValueKey('unlock-master-password-field')),
    value,
  );
  await tester.tap(find.byKey(const ValueKey('unlock-vault-button')));
  await tester.pumpAndSettle();
}

Future<void> autoLock(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('privacy-shield')), findsOneWidget);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('vault-unlock-page')), findsOneWidget);
}

Future<FakeVaultStore> start(WidgetTester tester) async {
  final store = FakeVaultStore(configured: true, acceptedPassword: password);
  await tester.pumpWidget(AccountSubscriptionApp(vaultStore: store));
  await tester.pumpAndSettle();
  await unlock(tester);
  addTearDown(() {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  return store;
}

void main() {
  for (final page in ['accounts', 'subscriptions', 'settings']) {
    testWidgets(
      'automatic lock resumes $page without bypassing authentication',
      (tester) async {
        await start(tester);
        await tester.tap(find.byKey(ValueKey('nav-$page')));
        await tester.pumpAndSettle();
        await autoLock(tester);
        expect(find.byKey(ValueKey('$page-page')), findsNothing);
        await unlock(tester, 'TEST-ONLY-WRONG');
        expect(find.byKey(const ValueKey('vault-unlock-page')), findsOneWidget);
        await unlock(tester);
        expect(find.byKey(ValueKey('$page-page')), findsOneWidget);
        expect(find.byKey(const ValueKey('home-page')), findsNothing);
      },
    );
  }
  testWidgets(
    'automatic lock restores nested appearance page; free icons are locked',
    (tester) async {
      await start(tester);
      await tester.tap(find.byKey(const ValueKey('nav-settings')));
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('appearance-settings-entry'));
      await tester.scrollUntilVisible(
        entry,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(tester.element(entry), alignment: 0.3);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('appearance-settings-page')),
        findsOneWidget,
      );
      await autoLock(tester);
      expect(
        find.byKey(const ValueKey('appearance-settings-page')),
        findsNothing,
      );
      await unlock(tester);
      expect(
        find.byKey(const ValueKey('appearance-settings-page')),
        findsOneWidget,
      );
      final blue = find.byKey(
        const ValueKey('appearance-desktop-icon-ceramicBlue'),
      );
      await tester.scrollUntilVisible(
        blue,
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(tester.element(blue), alignment: 0.4);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('appearance-icon-lock-ceramicBlue')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('appearance-icon-lock-paperArchive')),
        findsNothing,
      );
      await tester.tap(blue);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('full-version-upsell-dismiss')),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'automatic lock reconstructs account details from the reopened vault',
    (tester) async {
      await start(tester);
      final state = tester.widget<VaultGate>(find.byType(VaultGate)).appState;
      await state.createAccount(
        AccountDraft(platformName: 'TEST-ONLY-Resume-Account'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-accounts')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TEST-ONLY-Resume-Account').first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('account-details-page')),
        findsOneWidget,
      );
      await autoLock(tester);
      expect(state.accounts, isEmpty);
      expect(find.text('TEST-ONLY-Resume-Account'), findsNothing);
      await unlock(tester);
      expect(
        find.byKey(const ValueKey('account-details-page')),
        findsOneWidget,
      );
      expect(find.text('TEST-ONLY-Resume-Account'), findsWidgets);
    },
  );
  testWidgets('decoy unlock never restores the real-vault navigation', (
    tester,
  ) async {
    final store = await start(tester);
    await store.createDecoyVault(
      currentMasterPassword: password,
      decoyPassword: 'TEST-ONLY-Decoy-1234',
    );
    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pumpAndSettle();
    await autoLock(tester);
    await unlock(tester, 'TEST-ONLY-Decoy-1234');
    expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-page')), findsNothing);
  });
  test(
    'fresh install synchronizes orange and unchanged native state is rejected',
    () async {
      final bridge = IconBridge();
      final controller = CardockAppearanceController(
        store: MemoryAppearancePreferencesStore(),
        desktopIconBridge: bridge,
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(bridge.active, CardockLauncherFamily.paperArchive);
      bridge.ignoreChanges = true;
      await expectLater(
        controller.setDesktopIconFamily(CardockLauncherFamily.sakuraMist),
        throwsA(isA<DesktopIconProtocolException>()),
      );
      expect(controller.desktopIconMode, CardockDesktopIconMode.followTheme);
      bridge.ignoreChanges = false;
      await controller.setDesktopIconFamily(CardockLauncherFamily.sakuraMist);
      expect(bridge.active, CardockLauncherFamily.sakuraMist);
    },
  );
  test(
    'free saved blue icon is repaired; purchased choices are retained',
    () async {
      for (final entitlement in [
        ProductEntitlement.free,
        ProductEntitlement.purchased,
      ]) {
        final bridge = IconBridge();
        final store = MemoryAppearancePreferencesStore(
          const AppearancePreferences(
            desktopIconMode: CardockDesktopIconMode.ceramicBlue,
          ),
        );
        final controller = CardockAppearanceController(
          store: store,
          desktopIconBridge: bridge,
        );
        addTearDown(controller.dispose);
        await controller.load(
          sanitizeIconMode: (mode) =>
              const EntitlementGuard().allowedDesktopIconMode(
                entitlement: entitlement,
                requested: mode,
              ),
        );
        expect(
          bridge.active,
          entitlement.hasFullVersion
              ? CardockLauncherFamily.ceramicBlue
              : CardockLauncherFamily.paperArchive,
        );
      }
    },
  );
}

class IconBridge implements DesktopIconBridge {
  CardockLauncherFamily active = CardockLauncherFamily.ceramicBlue;
  bool ignoreChanges = false;
  @override
  Future<CardockLauncherFamily?> getActiveIcon() async => active;
  @override
  Future<void> setIcon(CardockLauncherFamily family) async {
    if (!ignoreChanges) active = family;
  }
}
