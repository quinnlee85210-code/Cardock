import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/entitlements/mock_store_gateway.dart';
import 'package:account_subscription_manager/core/platform/desktop_icon_controller.dart';
import 'package:account_subscription_manager/core/preferences/appearance_preferences.dart';
import 'package:account_subscription_manager/core/theme/cardock_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

void main() {
  for (final saved in <CardockThemeFamily?>[
    null,
    CardockThemeFamily.ceramicBlue,
    CardockThemeFamily.paperArchive,
  ]) {
    for (final paid in [false, true]) {
      testWidgets('startup theme for saved $saved and paid=$paid', (
        tester,
      ) async {
        final original = saved == null
            ? null
            : AppearancePreferences(
                family: saved,
                brightnessMode: CardockBrightnessMode.dark,
                desktopIconMode: CardockDesktopIconMode.mistCoral,
              );
        final store = MemoryAppearancePreferencesStore(original);
        await tester.pumpWidget(
          AccountSubscriptionApp(
            vaultStore: FakeVaultStore(),
            appearanceStore: store,
            desktopIconBridge: const _NoopDesktopIconBridge(),
            purchaseGateway: MockStoreGateway(
              initialEntitlement: paid
                  ? ProductEntitlement.purchased
                  : ProductEntitlement.free,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final expected = paid && saved != null
            ? saved
            : CardockThemeFamily.paperArchive;
        final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
        expect(app.theme!.extension<CardockThemeExtension>()!.family, expected);
        expect(
          app.darkTheme!.extension<CardockThemeExtension>()!.family,
          expected,
        );
        expect(find.byType(AlertDialog), findsNothing);
        if (original != null) {
          expect(
            store.value,
            original.copyWith(
              family: expected,
              desktopIconMode: paid
                  ? original.desktopIconMode
                  : CardockDesktopIconMode.followTheme,
            ),
          );
        }
      });
    }
  }

  testWidgets('权益从已购切回免费时正在使用的付费主题静默回退', (tester) async {
    final appearanceStore = MemoryAppearancePreferencesStore(
      const AppearancePreferences(family: CardockThemeFamily.neonZero),
    );
    final gateway = MockStoreGateway(
      initialEntitlement: ProductEntitlement.purchased,
      simulationEnabled: true,
    );

    await tester.pumpWidget(
      AccountSubscriptionApp(
        vaultStore: FakeVaultStore(),
        appearanceStore: appearanceStore,
        desktopIconBridge: const _NoopDesktopIconBridge(),
        purchaseGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();
    expect(appearanceStore.value?.family, CardockThemeFamily.neonZero);

    await gateway.debugSetEntitlement(ProductEntitlement.free);
    await tester.pumpAndSettle();

    expect(appearanceStore.value?.family, CardockThemeFamily.paperArchive);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  });
}

final class _NoopDesktopIconBridge implements DesktopIconBridge {
  const _NoopDesktopIconBridge();

  @override
  Future<CardockLauncherFamily?> getActiveIcon() async =>
      CardockLauncherFamily.ceramicBlue;

  @override
  Future<void> setIcon(CardockLauncherFamily family) async {}
}
