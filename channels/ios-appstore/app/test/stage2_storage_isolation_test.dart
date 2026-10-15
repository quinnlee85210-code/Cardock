import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/security/biometric_unlock.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_trash.dart';
import 'package:account_subscription_manager/core/security/subscription_metadata_migration.dart';
import 'package:account_subscription_manager/core/storage/layered_vault_store.dart';
import 'package:account_subscription_manager/core/storage/portable_backup_codec.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_management_actions.dart';
import 'support/fake_vault_store.dart';

const password = 'TEST-ONLY-Stage2-Store-2026!';
const decoyPassword = 'TEST-ONLY-Decoy-2026!';
const testKdf = VaultKdfParameters(
  memoryKiB: 64,
  iterations: 1,
  parallelism: 1,
);
VaultSnapshot fixture({bool extensions = true}) {
  final account = AccountRecord.fromDraft(
    id: 'account-1',
    draft: AccountDraft(
      platformName: 'Synthetic platform',
      loginAccount: 'SYNTHETIC-LOGIN',
      password: 'SYNTHETIC-PASSWORD',
    ),
  );
  final record = SubscriptionRecord.fromDraft(
    id: 'subscription-1',
    draft: SubscriptionDraft(
      accountId: account.id,
      details: SubscriptionDetailsDraft(
        serviceName: 'Synthetic subscription',
        amount: '1.2345',
        firstSubscribedOn: DateTime(2026, 9, 1),
        nextRenewalOn: DateTime(2026, 10, 1),
        paymentMethod: 'Synthetic payment',
        management: extensions
            ? SubscriptionManagement(
                trial: SubscriptionTrial(
                  startsOn: DateTime(2026, 9, 1),
                  endsOn: DateTime(2026, 9, 10),
                  formalAmount: '1.2345',
                ),
                cancellation: SubscriptionCancellationInfo(
                  steps: 'PRIVATE-CANCEL-STEPS',
                ),
                reminderRules: [
                  SubscriptionReminderRule(
                    event: SubscriptionReminderEvent.trialEnd,
                    daysBefore: [3, 1, 0],
                  ),
                ],
                priceHistory: [
                  SubscriptionPricePoint(
                    id: 'p1',
                    effectiveOn: DateTime(2026, 9, 1),
                    amount: '1.2345',
                    currency: 'CNY',
                    cycleCount: 1,
                    cycleUnit: SubscriptionCycleUnit.month,
                    kind: PriceChangeKind.backfill,
                    createdAt: DateTime.utc(2026, 9, 4),
                    note: 'PRIVATE-PRICE-NOTE',
                  ),
                ],
              )
            : null,
      ),
    ),
  );
  return VaultSnapshot(
    nextAccountId: 2,
    accounts: [account],
    nextSubscriptionId: 2,
    subscriptions: [record],
  );
}

class MemoryQuickUnlock implements QuickUnlockSecretStore {
  QuickUnlockSecret? value;
  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.available;
  @override
  Future<bool> containsSecret() async => value != null;
  @override
  Future<void> deleteSecret() async {
    value?.destroy();
    value = null;
  }

  @override
  Future<QuickUnlockSecret?> readSecret() async => value == null
      ? null
      : QuickUnlockSecret(vaultId: value!.vaultId, dataKey: value!.dataKey);
  @override
  Future<void> writeSecret(QuickUnlockSecret secret) async {
    value?.destroy();
    value = QuickUnlockSecret(vaultId: secret.vaultId, dataKey: secret.dataKey);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (var version = 1; version <= 11; version++) {
    test(
      'legacy schema $version preserves existing identifiers and upgrades once',
      () {
        final raw = fixture(extensions: false).toEncryptedPayloadJson()
          ..['schemaVersion'] = version;
        final restored = VaultSnapshot.fromEncryptedPayloadJson(raw);
        expect(restored.accounts.single.id, 'account-1');
        expect(restored.requiresSchemaUpgrade, isTrue);
        if (version > 1) {
          expect(restored.subscriptions.single.id, 'subscription-1');
          expect(restored.subscriptions.single.amount, '1.2345');
        }
        final reloaded = VaultSnapshot.fromEncryptedPayloadJson(
          jsonDecode(jsonEncode(restored.toEncryptedPayloadJson())),
        );
        expect(reloaded.requiresSchemaUpgrade, isFalse);
        expect(
          reloaded.toEncryptedPayloadJson(),
          restored.toEncryptedPayloadJson(),
        );
      },
    );
  }
  test(
    'first full unlock commits one atomic migration; next unlock does not',
    () async {
      final raw = fixture(extensions: false).toEncryptedPayloadJson()
        ..['schemaVersion'] = 11;
      final store = FakeVaultStore(
        configured: true,
        acceptedPassword: password,
        snapshot: VaultSnapshot.fromEncryptedPayloadJson(raw),
      );
      final state = AppState(vaultStore: store);
      addTearDown(state.dispose);
      await state.initialize();
      expect(await state.unlock(password), VaultActionResult.success);
      expect(store.saveCalls, 1);
      expect(store.snapshot.requiresSchemaUpgrade, isFalse);
      final amount = state.subscriptions.single.amount,
          methods = state.paymentMethods.length;
      state.lock();
      expect(state.paymentMethods, isEmpty);
      expect(await state.unlock(password), VaultActionResult.success);
      expect(store.saveCalls, 1);
      expect(state.subscriptions.single.amount, amount);
      expect(state.paymentMethods, hasLength(methods));
    },
  );
  test('failed migration leaves old snapshot intact and can retry', () async {
    final raw = fixture(extensions: false).toEncryptedPayloadJson()
      ..['schemaVersion'] = 11;
    final old = VaultSnapshot.fromEncryptedPayloadJson(raw),
        store = FakeVaultStore(
          configured: true,
          acceptedPassword: password,
          snapshot: VaultSnapshot.fromEncryptedPayloadJson(raw),
        )..failSaves = true;
    final state = AppState(vaultStore: store);
    addTearDown(state.dispose);
    await state.initialize();
    expect(await state.unlock(password), isNot(VaultActionResult.success));
    expect(state.isUnlocked, isFalse);
    expect(
      store.snapshot.toEncryptedPayloadJson(),
      old.toEncryptedPayloadJson(),
    );
    expect(store.snapshot.requiresSchemaUpgrade, isTrue);
    store.failSaves = false;
    expect(await state.unlock(password), VaultActionResult.success);
    expect(store.snapshot.requiresSchemaUpgrade, isFalse);
  });
  test(
    'trash and restore retain IDs, price history and trial without payment',
    () {
      final source = normalizeSubscriptionMetadata(fixture());
      final trash = VaultTrash.move(
        source,
        accountId: 'account-1',
        now: DateTime.utc(2026, 9, 4),
        batchId: 'stage2-batch',
      );
      final decoded = VaultSnapshot.fromEncryptedPayloadJson(
        jsonDecode(jsonEncode(trash.toEncryptedPayloadJson())),
      );
      expect(decoded.trashSubscriptions.single.batchId, 'stage2-batch');
      expect(decoded.subscriptionExpenses, isEmpty);
      final restored = VaultTrash.restore(
        decoded,
        accountId: 'account-1',
        wholeBatch: true,
      );
      expect(
        restored.subscriptions.single.toEncryptedPayloadJson(),
        source.subscriptions.single.toEncryptedPayloadJson(),
      );
      expect(
        restored.paymentMethods.single.id,
        source.paymentMethods.single.id,
      );
    },
  );
  test('payment merge updates trash but retains relationship and batch', () {
    var source = normalizeSubscriptionMetadata(fixture());
    source = savePaymentMethod(
      source,
      PaymentMethodRecord(id: 'target', name: 'Target'),
    );
    final trash = VaultTrash.move(
      source,
      subscriptionId: 'subscription-1',
      now: DateTime.utc(2026, 9, 4),
      batchId: 'kept-batch',
    );
    final merged = mergePaymentMethods(
      trash,
      fromId: source.paymentMethods.first.id,
      intoId: 'target',
    );
    expect(
      merged.trashSubscriptions.single.record.management!.paymentMethodId,
      'target',
    );
    expect(merged.trashSubscriptions.single.batchId, 'kept-batch');
    expect(merged.trashSubscriptions.single.record.accountId, 'account-1');
  });
  test(
    'portable V2 roundtrip retains extensions and rejects wrong password',
    () async {
      final source = normalizeSubscriptionMetadata(fixture()),
          codec = PortableBackupCodec();
      final bytes = await codec.encryptV2(
        snapshot: source,
        backupMasterPassword: password,
      );
      expect(utf8.decode(bytes), isNot(contains('PRIVATE-CANCEL-STEPS')));
      final result = await codec.read(
        bytes: bytes,
        backupMasterPassword: password,
      );
      expect(
        result.snapshot.toEncryptedPayloadJson(),
        source.toEncryptedPayloadJson(),
      );
      await expectLater(
        codec.read(
          bytes: bytes,
          backupMasterPassword: 'TEST-ONLY-Wrong-Password!',
        ),
        throwsA(isA<PortableBackupAuthenticationException>()),
      );
    },
  );
  test(
    'real subscription-only and decoy stores isolate stage2 metadata',
    () async {
      final parent = Directory('../backups/testdata/stage2-isolation');
      await parent.create(recursive: true);
      final directory = await parent.createTemp('synthetic-');
      final quick = MemoryQuickUnlock();
      addTearDown(quick.deleteSecret);
      final store = LayeredVaultStore.forDirectory(
        directory: directory,
        creationKdf: testKdf,
        quickUnlockSecretStore: quick,
      );
      final source = normalizeSubscriptionMetadata(fixture());
      final method = source.paymentMethods.single.copyWith(
        note: 'PRIVATE-PAYMENT-NOTE',
        shortLabel: 'PRIVATE-LABEL',
      );
      final full = source.copyWith(paymentMethods: [method]);
      final created = await store.create(masterPassword: password);
      await created.session.save(full);
      created.session.close();
      await store.configureQuickUnlock(
        currentMasterPassword: password,
        scope: QuickUnlockScope.subscriptionsOnly,
      );
      final readOnly = await store.unlockWithQuickUnlock();
      final projected = jsonEncode(readOnly.snapshot.toEncryptedPayloadJson());
      for (final secret in [
        'SYNTHETIC-LOGIN',
        'SYNTHETIC-PASSWORD',
        'PRIVATE-CANCEL-STEPS',
        'PRIVATE-PRICE-NOTE',
        'PRIVATE-PAYMENT-NOTE',
        'PRIVATE-LABEL',
      ]) {
        expect(projected, isNot(contains(secret)));
      }
      expect(
        readOnly.snapshot.subscriptions.single.management!.trial,
        isNotNull,
      );
      await expectLater(
        readOnly.session.save(full),
        throwsA(isA<VaultClosedException>()),
      );
      readOnly.session.close();
      await store.createDecoyVault(
        currentMasterPassword: password,
        decoyPassword: decoyPassword,
      );
      final decoy = await store.unlock(masterPassword: decoyPassword);
      expect(decoy.snapshot.paymentMethods, isEmpty);
      expect(decoy.snapshot.subscriptions, isEmpty);
      decoy.session.close();
      final real = await store.unlock(masterPassword: password);
      expect(
        real.snapshot.toEncryptedPayloadJson(),
        full.toEncryptedPayloadJson(),
      );
      real.session.close();
      // Synthetic encrypted fixtures are retained within the project for audit.
    },
  );
}
