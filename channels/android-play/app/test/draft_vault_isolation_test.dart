import 'dart:io';
import 'package:account_subscription_manager/core/security/editor_draft.dart';

import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/security/biometric_unlock.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/storage/layered_vault_store.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/pending_subscription_draft.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter_test/flutter_test.dart';

const _testKdf = VaultKdfParameters(
  memoryKiB: 64,
  iterations: 1,
  parallelism: 1,
);
const _primaryPassword = 'TEST-ONLY-PRIMARY-1234';
const _decoyPassword = 'TEST-DECOY-1234';

void main() {
  test(
    'unfinished editors stay in originating vault and are inaccessible in subscription view',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'asm-editor-isolation-',
      );
      addTearDown(() => _deleteDirectory(directory));
      final quickStore = _MemoryQuickUnlockSecretStore();
      addTearDown(quickStore.dispose);
      final store = LayeredVaultStore.forDirectory(
        directory: directory,
        creationKdf: _testKdf,
        quickUnlockSecretStore: quickStore,
      );
      var primary = await store.create(masterPassword: _primaryPassword);
      primary.session.close();
      await store.configureQuickUnlock(
        currentMasterPassword: _primaryPassword,
        scope: QuickUnlockScope.subscriptionsOnly,
      );
      await store.createDecoyVault(
        currentMasterPassword: _primaryPassword,
        decoyPassword: _decoyPassword,
      );
      primary = await store.unlock(masterPassword: _primaryPassword);
      final original = {
        'kind': 'account',
        'fields': {'partial': 'TEST-ONLY-PRIMARY-EDITOR'},
      };
      await (primary.session as EditorDraftVaultSession).writeEditorDraft(
        original,
      );
      primary.session.close();
      final projection = await store.unlockWithQuickUnlock();
      // The full-access guard may reject synchronously before a Future exists.
      expect(
        () => (projection.session as EditorDraftVaultSession).readEditorDraft(),
        throwsA(isA<VaultClosedException>()),
      );
      expect(
        () => (projection.session as EditorDraftVaultSession).writeEditorDraft(
          null,
        ),
        throwsA(isA<VaultClosedException>()),
      );
      projection.session.close();
      final decoy = await store.unlock(masterPassword: _decoyPassword);
      expect(
        await (decoy.session as EditorDraftVaultSession).readEditorDraft(),
        isNull,
      );
      await (decoy.session as EditorDraftVaultSession).writeEditorDraft({
        'kind': 'subscription',
        'fields': {'partial': 'TEST-ONLY-DECOY-EDITOR'},
      });
      decoy.session.close();
      final restored = await store.unlock(masterPassword: _primaryPassword);
      expect(
        await (restored.session as EditorDraftVaultSession).readEditorDraft(),
        original,
      );
      restored.session.close();
    },
  );

  test('待完善草稿不进入订阅只读投影且真实库与诱饵库自然隔离', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-draft-isolation-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final quickStore = _MemoryQuickUnlockSecretStore();
    addTearDown(quickStore.dispose);
    final store = LayeredVaultStore.forDirectory(
      directory: directory,
      creationKdf: _testKdf,
      quickUnlockSecretStore: quickStore,
    );

    final created = await store.create(masterPassword: _primaryPassword);
    await created.session.save(_snapshot('primary'));
    created.session.close();
    await store.configureQuickUnlock(
      currentMasterPassword: _primaryPassword,
      scope: QuickUnlockScope.subscriptionsOnly,
    );

    final projection = await store.unlockWithQuickUnlock();
    expect(projection.snapshot.subscriptions, hasLength(1));
    expect(projection.snapshot.pendingSubscriptionDrafts, isEmpty);
    final scoped = projection.session as ScopedVaultSession;
    expect(scoped.accessLevel, VaultAccessLevel.subscriptionsOnly);
    await expectLater(
      scoped.save(projection.snapshot),
      throwsA(isA<VaultClosedException>()),
    );
    scoped.close();

    await store.createDecoyVault(
      currentMasterPassword: _primaryPassword,
      decoyPassword: _decoyPassword,
    );
    final decoy = await store.unlock(masterPassword: _decoyPassword);
    expect(decoy.snapshot.pendingSubscriptionDrafts, isEmpty);
    await decoy.session.save(_snapshot('decoy'));
    decoy.session.close();

    final primary = await store.unlock(masterPassword: _primaryPassword);
    expect(
      primary.snapshot.pendingSubscriptionDrafts.single.planName,
      'primary',
    );
    primary.session.close();
    final reopenedDecoy = await store.unlock(masterPassword: _decoyPassword);
    expect(
      reopenedDecoy.snapshot.pendingSubscriptionDrafts.single.planName,
      'decoy',
    );
    reopenedDecoy.session.close();
  });

  test('分享草稿经 AppState 只写当前诱饵库且原文不进入任一保险库', () async {
    const appDecoyPassword = 'TEST-DECOY-PASSWORD-1234';
    const rawMarker = 'RAW_SHARE_TEXT_MUST_NOT_PERSIST';
    final directory = await Directory.systemTemp.createTemp(
      'asm-share-draft-isolation-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final quickStore = _MemoryQuickUnlockSecretStore();
    addTearDown(quickStore.dispose);
    final store = LayeredVaultStore.forDirectory(
      directory: directory,
      creationKdf: _testKdf,
      quickUnlockSecretStore: quickStore,
    );
    final state = AppState(vaultStore: store);
    await state.initialize();
    expect(
      await state.createVault(_primaryPassword),
      VaultActionResult.success,
    );
    expect(
      (await state.createAccount(AccountDraft(platformName: 'Primary'))).saved,
      isTrue,
    );
    expect(
      await state.createDecoyVault(
        currentMasterPassword: _primaryPassword,
        decoyPassword: appDecoyPassword,
      ),
      isTrue,
    );

    state.lock();
    expect(await state.unlock(appDecoyPassword), VaultActionResult.success);
    expect(
      (await state.createAccount(
        AccountDraft(platformName: 'Decoy Example'),
      )).saved,
      isTrue,
    );
    expect(
      await state.saveSharedTextPendingSubscriptionDraft(
        accountId: state.accounts.single.id,
        planName: 'Decoy plan',
        amount: '8.88',
        currency: 'CNY',
      ),
      isTrue,
    );
    state.lock();
    state.dispose();

    final primary = await store.unlock(masterPassword: _primaryPassword);
    expect(primary.snapshot.pendingSubscriptionDrafts, isEmpty);
    expect(
      primary.snapshot.toEncryptedPayloadJson().toString(),
      isNot(contains(rawMarker)),
    );
    primary.session.close();

    final decoy = await store.unlock(masterPassword: appDecoyPassword);
    expect(decoy.snapshot.pendingSubscriptionDrafts, hasLength(1));
    expect(
      decoy.snapshot.pendingSubscriptionDrafts.single.planName,
      'Decoy plan',
    );
    expect(
      decoy.snapshot.toEncryptedPayloadJson().toString(),
      isNot(contains(rawMarker)),
    );
    decoy.session.close();
  });
}

VaultSnapshot _snapshot(String marker) {
  final account = AccountRecord.fromDraft(
    id: 'account-1',
    draft: AccountDraft(platformName: '$marker-platform'),
  );
  final subscription = SubscriptionRecord.fromDraft(
    id: 'subscription-1',
    draft: SubscriptionDraft(
      accountId: account.id,
      details: SubscriptionDetailsDraft(
        serviceName: '$marker-service',
        firstSubscribedOn: DateTime(2026, 8, 30),
        nextRenewalOn: DateTime(2026, 9, 30),
      ),
    ),
  );
  final draft = PendingSubscriptionDraft(
    draftId: 'pending-1',
    accountId: account.id,
    planName: marker,
    createdAt: DateTime.utc(2026, 8, 30),
    updatedAt: DateTime.utc(2026, 8, 30),
  );
  return VaultSnapshot(
    nextAccountId: 2,
    accounts: <AccountRecord>[account],
    nextSubscriptionId: 2,
    subscriptions: <SubscriptionRecord>[subscription],
    pendingSubscriptionDrafts: <PendingSubscriptionDraft>[draft],
  );
}

final class _MemoryQuickUnlockSecretStore implements QuickUnlockSecretStore {
  QuickUnlockSecret? _secret;

  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.available;

  @override
  Future<bool> containsSecret() async => _secret != null;

  @override
  Future<void> writeSecret(QuickUnlockSecret secret) async {
    _secret?.destroy();
    _secret = QuickUnlockSecret(
      vaultId: secret.vaultId,
      dataKey: secret.dataKey,
    );
  }

  @override
  Future<QuickUnlockSecret?> readSecret() async {
    final secret = _secret;
    return secret == null
        ? null
        : QuickUnlockSecret(vaultId: secret.vaultId, dataKey: secret.dataKey);
  }

  @override
  Future<void> deleteSecret() async {
    _secret?.destroy();
    _secret = null;
  }

  void dispose() {
    _secret?.destroy();
    _secret = null;
  }
}

Future<void> _deleteDirectory(Directory directory) async {
  if (await directory.exists()) await directory.delete(recursive: true);
}
