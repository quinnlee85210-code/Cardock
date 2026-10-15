import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:account_subscription_manager/core/entitlements/review_access_codec.dart';
import 'package:account_subscription_manager/core/entitlements/review_access_service.dart';
import 'package:account_subscription_manager/core/entitlements/promo_activation_codec.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_service.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_guard.dart';
import 'package:account_subscription_manager/core/entitlements/commercial_purchase_gateway.dart';
import 'package:account_subscription_manager/core/entitlements/commercial_license_config.dart';
import 'package:account_subscription_manager/core/entitlements/distribution_channel.dart';
import 'package:account_subscription_manager/core/theme/cardock_theme_types.dart';
import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/product/presentation/full_version_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:account_subscription_manager/l10n/translations_review_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_vault_store.dart';
import 'commercial_license_test.dart' show FakeLicensePlatform;

class ReviewMemoryStore implements ReviewAccessStore {
  String? credential;
  bool fail = false;
  @override
  Future<String?> read() async => credential;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('test storage failure');
    credential = value;
  }

  @override
  Future<void> remove() async {
    if (fail) throw StateError('test storage failure');
    credential = null;
  }
}

void main() {
  late SimpleKeyPair key;
  late List<int> publicKey;
  late ReviewAccessVerifier verifier;
  Future<String> issue({
    List<int>? header,
    String app = reviewAccessApplicationId,
    String domain = reviewAccessDomain,
    KeyPair? signingKey,
  }) async {
    final payload = <int>[
      ...header ?? [1, 1, 1, 1, 1],
      ...(await Sha256().hash(utf8.encode(app))).bytes,
      ...List.filled(16, 42),
    ];
    final signature = await Ed25519().sign([
      ...utf8.encode(domain),
      ...payload,
    ], keyPair: signingKey ?? key);
    return 'CR1${crockfordBase32Encode([...payload, ...signature.bytes])}';
  }

  setUp(() async {
    // Fresh test-only key, never import the production issuer or credential.
    key = await Ed25519().newKeyPair();
    publicKey = (await key.extractPublicKey()).bytes;
    verifier = ReviewAccessVerifier(publicKey: publicKey);
  });
  test(
    'strict signature, domain, audience, field versions and canonical encoding',
    () async {
      final code = await issue();
      expect(code.length, 191);
      expect(await verifier.verify(code), isTrue);
      for (var i = 0; i < 5; i++) {
        final header = [1, 1, 1, 1, 1];
        header[i] = 2;
        expect(await verifier.verify(await issue(header: header)), isFalse);
      }
      for (final bad in [
        '',
        'CR1',
        code.toLowerCase(),
        ' $code',
        '${code}0',
        code.substring(0, 190),
        '${code.substring(0, 100)}-${code.substring(100)}',
        'X' * 20000,
        await issue(app: 'other.app'),
        await issue(domain: 'website-license'),
        await issue(signingKey: await Ed25519().newKeyPair()),
      ]) {
        expect(await verifier.verify(bad), isFalse);
      }
      final bytes = crockfordBase32Decode(code.substring(3))!;
      bytes[70] ^= 1;
      expect(
        await verifier.verify('CR1${crockfordBase32Encode(bytes)}'),
        isFalse,
      );
      expect(
        await ReviewAccessVerifier(
          publicKey: publicKey,
          channel: 'website',
        ).verify(code),
        isFalse,
      );
      expect(
        await ReviewAccessVerifier(
          publicKey: publicKey,
          channel: 'app_store',
        ).verify(code),
        isFalse,
      );
    },
  );
  test(
    'source credential repeats across two fresh stores, restart and removal; bad input preserves good state',
    () async {
      final code = await issue();
      final a = ReviewMemoryStore();
      final b = ReviewMemoryStore();
      for (final store in [a, b]) {
        final c = ReviewAccessController(verifier: verifier, store: store);
        await c.initialize();
        expect(c.value, isFalse);
        expect(await c.activate('invalid'), ReviewAccessResult.invalid);
        expect(await c.activate(code), ReviewAccessResult.activated);
        expect(await c.activate(code), ReviewAccessResult.activated);
        expect(await c.activate('X' * 20000), ReviewAccessResult.invalid);
        expect(c.value, isTrue);
        store.fail = true;
        expect(await c.remove(), ReviewAccessResult.unavailable);
        expect(c.value, isTrue);
        store.fail = false;
        c.dispose();
        final cold = ReviewAccessController(verifier: verifier, store: store);
        await cold.initialize();
        expect(cold.value, isTrue);
        expect(await cold.remove(), ReviewAccessResult.removed);
        expect(cold.value, isFalse);
        cold.dispose();
      }
    },
  );
  test(
    'Google and review sources remain separate under restore, query and removal',
    () async {
      final platform = FakeLicensePlatform()..channel = 'google_play';
      final review = ReviewAccessController(
        verifier: verifier,
        store: ReviewMemoryStore(),
      );
      final controller = ProductEntitlementController(
        gateway: CommercialPurchaseGateway(
          config: const CommercialLicenseConfig(
            channel: CardockDistributionChannel.googlePlay,
          ),
          platform: platform,
        ),
        reviewAccessController: review,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await review.activate(await issue());
      expect(controller.value, ProductEntitlement.review);
      expect(controller.hasStorePurchase, isFalse);
      await controller.restore();
      expect(controller.isReviewAuthorized, isTrue);
      expect(controller.hasStorePurchase, isFalse);
      platform.store = true;
      await controller.initialize();
      expect(controller.hasStorePurchase, isTrue);
      expect(controller.isReviewAuthorized, isTrue);
      await review.remove();
      expect(controller.hasFullVersion, isTrue);
      expect(controller.isReviewAuthorized, isFalse);
      await review.activate(await issue());
      platform.store = false;
      await controller.restore();
      expect(controller.value, ProductEntitlement.review);
      platform.outcome = 'cancelled';
      await controller.purchase();
      expect(controller.hasStorePurchase, isFalse);
      expect(controller.isReviewAuthorized, isTrue);
      await review.remove();
      expect(controller.value, ProductEntitlement.free);
    },
  );
  test('only Play can receive review source', () async {
    for (final channel in [
      CardockDistributionChannel.website,
      CardockDistributionChannel.appStore,
      CardockDistributionChannel.development,
    ]) {
      final review = ReviewAccessController(
        verifier: verifier,
        store: ReviewMemoryStore(),
      );
      await review.activate(await issue());
      final platform = FakeLicensePlatform()..channel = channel.wireValue;
      final controller = ProductEntitlementController(
        gateway: CommercialPurchaseGateway(
          config: CommercialLicenseConfig(channel: channel),
          platform: platform,
        ),
        reviewAccessController: review,
      );
      await controller.initialize();
      expect(controller.reviewAccess, isNull);
      expect(controller.isReviewAuthorized, isFalse);
      expect(controller.hasFullVersion, isFalse);
      controller.dispose();
      review.dispose();
    }
  });
  test(
    'signed review unlocks real 16th account and 6th subscription, all themes; revoke preserves records and vault password',
    () async {
      final review = ReviewAccessController(
        verifier: verifier,
        store: ReviewMemoryStore(),
      );
      final platform = FakeLicensePlatform()..channel = 'google_play';
      final controller = ProductEntitlementController(
        gateway: CommercialPurchaseGateway(
          config: const CommercialLicenseConfig(
            channel: CardockDistributionChannel.googlePlay,
          ),
          platform: platform,
        ),
        reviewAccessController: review,
      );
      final vault = FakeVaultStore();
      final state = AppState(
        vaultStore: vault,
        entitlementListenable: controller,
      );
      addTearDown(state.dispose);
      addTearDown(controller.dispose);
      await controller.initialize();
      await state.initialize();
      expect(
        await state.createVault('TEST-ONLY-MASTER-1234'),
        VaultActionResult.success,
      );
      SubscriptionDraft draft(int i) => SubscriptionDraft(
        accountId: null,
        details: SubscriptionDetailsDraft(
          serviceName: 'Fictional $i',
          planName: 'Monthly',
          amount: '9.9',
          currency: 'CNY',
          firstSubscribedOn: DateTime(2026, 8, 1),
          nextRenewalOn: DateTime(2026, 9, 1),
          cycleCount: 1,
          cycleUnit: SubscriptionCycleUnit.month,
          autoRenew: true,
          paymentMethod: 'Fictional',
          reminderDaysBefore: 7,
        ),
      );
      for (var i = 0; i < 15; i++) {
        expect(
          (await state.createAccount(
            AccountDraft(platformName: 'Fictional $i'),
          )).saved,
          isTrue,
        );
      }
      for (var i = 0; i < 5; i++) {
        expect((await state.createSubscription(draft(i))).saved, isTrue);
      }
      expect(
        (await state.createAccount(AccountDraft(platformName: '16th'))).saved,
        isFalse,
      );
      expect((await state.createSubscription(draft(6))).saved, isFalse);
      final code = await issue();
      await review.activate(code);
      expect(
        (await state.createAccount(AccountDraft(platformName: '16th'))).saved,
        isTrue,
      );
      expect((await state.createSubscription(draft(6))).saved, isTrue);
      for (final family in CardockThemeFamily.values) {
        expect(
          const EntitlementGuard().canUseTheme(
            entitlement: controller.value,
            family: family,
          ),
          isTrue,
        );
      }
      final backup = await state.exportEncryptedBackup(
        backupMasterPassword: 'TEST-ONLY-MASTER-1234',
      );
      expect(backup, isNotNull);
      final count = vault.unlockCalls;
      state.lock();
      await review.activate(code);
      expect(vault.unlockCalls, count);
      expect(state.isUnlocked, isFalse);
      expect(await state.unlock(code), VaultActionResult.rejected);
      expect(
        await state.unlock('TEST-ONLY-MASTER-1234'),
        VaultActionResult.success,
      );
      expect(
        await state.restoreEncryptedBackup(
          bytes: backup!,
          backupMasterPassword: code,
          currentMasterPassword: 'TEST-ONLY-MASTER-1234',
        ),
        isFalse,
      );
      await review.remove();
      expect(state.accounts.length, 16);
      expect(state.subscriptions.length, 6);
      expect(vault.changeMasterPasswordCalls, 0);
      expect(
        (await state.createAccount(AccountDraft(platformName: '17th'))).saved,
        isFalse,
      );
      expect(await state.deleteAccount(state.accounts.last.id), isTrue);
      expect(state.accounts.length, 15);
    },
  );
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('en'),
    const Locale('ja'),
  ]) {
    testWidgets(
      'visible review entry and real store purchase remain available in $locale',
      (tester) async {
        final review = ReviewAccessController(
          verifier: verifier,
          store: ReviewMemoryStore(),
        );
        final platform = FakeLicensePlatform()
          ..channel = 'google_play'
          ..outcome = 'cancelled';
        final controller = ProductEntitlementController(
          gateway: CommercialPurchaseGateway(
            config: const CommercialLicenseConfig(
              channel: CardockDistributionChannel.googlePlay,
            ),
            platform: platform,
          ),
          reviewAccessController: review,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: FullVersionPage(controller: controller),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('review-access-entry')),
        );
        await tester.tap(find.byKey(const ValueKey('review-access-entry')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('review-access-input')),
          await issue(),
        );
        await tester.tap(find.byKey(const ValueKey('review-access-activate')));
        await tester.pumpAndSettle();
        expect(review.value, isTrue);
        expect(controller.hasStorePurchase, isFalse);
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('review-access-input')),
              )
              .controller!
              .text,
          isEmpty,
        );
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('purchase-full-version-button')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('purchase-full-version-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .byKey(const ValueKey('purchase-full-version-button'))
              .hitTestable(),
        );
        await tester.pumpAndSettle();
        expect(platform.purchaseCalls, 1);
        expect(controller.isReviewAuthorized, isTrue);
        expect(controller.hasStorePurchase, isFalse);
      },
    );
  }
  test('all review messages have English/Japanese translations', () {
    expect(
      reviewAccessEnglishTranslations.keys.toSet(),
      reviewAccessJapaneseTranslations.keys.toSet(),
    );
    for (final text in reviewAccessEnglishTranslations.keys) {
      expect(const AppLocalizations(Locale('en')).hasTranslation(text), isTrue);
      expect(const AppLocalizations(Locale('ja')).hasTranslation(text), isTrue);
    }
  });
}
