import 'package:account_subscription_manager/core/entitlements/entitlement_guard.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/theme/cardock_theme_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const guard = EntitlementGuard();

  group('free creation limits', () {
    test('exactly 5 subscriptions and 15 accounts are denied', () {
      expect(
        guard
            .subscriptionCreation(
              entitlement: ProductEntitlement.free,
              currentSubscriptions: EntitlementGuard.maxSubscriptions,
            )
            .allowed,
        isFalse,
      );
      expect(
        guard
            .accountCreation(
              entitlement: ProductEntitlement.free,
              currentAccounts: EntitlementGuard.maxAccounts,
            )
            .allowed,
        isFalse,
      );
    });

    test('one item below each boundary is allowed', () {
      expect(
        guard
            .subscriptionCreation(
              entitlement: ProductEntitlement.free,
              currentSubscriptions: 4,
            )
            .allowed,
        isTrue,
      );
      expect(
        guard
            .accountCreation(
              entitlement: ProductEntitlement.free,
              currentAccounts: 14,
            )
            .allowed,
        isTrue,
      );
    });

    test('purchased entitlement is unlimited', () {
      expect(
        guard
            .subscriptionCreation(
              entitlement: ProductEntitlement.purchased,
              currentSubscriptions: 5000,
            )
            .allowed,
        isTrue,
      );
      expect(
        guard
            .accountCreation(
              entitlement: ProductEntitlement.purchased,
              currentAccounts: 5000,
            )
            .allowed,
        isTrue,
      );
    });

    test('backup restore is never limited even far above free limits', () {
      expect(
        guard.canRestoreBackup(
          entitlement: ProductEntitlement.free,
          importedAccounts: 50,
          importedSubscriptions: 20,
        ),
        isTrue,
      );
    });
  });

  group('theme entitlement', () {
    test('free allows Paper Archive and rejects every premium family', () {
      expect(
        guard.canUseTheme(
          entitlement: ProductEntitlement.free,
          family: CardockThemeFamily.paperArchive,
        ),
        isTrue,
      );
      for (final family in CardockThemeFamily.values.where(
        (candidate) => candidate != CardockThemeFamily.paperArchive,
      )) {
        expect(
          guard.canUseTheme(
            entitlement: ProductEntitlement.free,
            family: family,
          ),
          isFalse,
          reason: family.name,
        );
      }
    });

    test('free persisted premium theme falls back to Paper Archive', () {
      expect(
        guard.allowedPersistedTheme(
          entitlement: ProductEntitlement.free,
          requested: CardockThemeFamily.neonZero,
        ),
        CardockThemeFamily.paperArchive,
      );
    });

    test('purchased allows every theme without fallback', () {
      for (final family in CardockThemeFamily.values) {
        expect(
          guard.canUseTheme(
            entitlement: ProductEntitlement.purchased,
            family: family,
          ),
          isTrue,
        );
        expect(
          guard.allowedPersistedTheme(
            entitlement: ProductEntitlement.purchased,
            requested: family,
          ),
          family,
        );
      }
    });
  });
}
