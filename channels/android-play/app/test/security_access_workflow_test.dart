import 'dart:async';
import 'dart:io';

import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/security/biometric_unlock.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/storage/layered_vault_store.dart';
import 'package:account_subscription_manager/core/storage/vault_recovery_journal.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter_test/flutter_test.dart';

const _realPassword = 'Cobalt-Real-Master-74!Quartz';
const _decoyPassword = 'Harbor-Decoy-Story-83!Maple';
const _backupPassword = 'Archive-Backup-Key-62!River';
const _testKdf = VaultKdfParameters(
  memoryKiB: 64,
  iterations: 1,
  parallelism: 1,
);

void main() {
  test('AppState 严格区分订阅只读、真实库和诱饵库', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-security-flow-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final quickUnlock = _MemoryQuickUnlockStore();
    addTearDown(quickUnlock.destroy);
    final store = LayeredVaultStore.forDirectory(
      directory: directory,
      creationKdf: _testKdf,
      quickUnlockSecretStore: quickUnlock,
    );
    final state = AppState(vaultStore: store);
    addTearDown(state.dispose);
    await state.initialize();
    expect(await state.createVault(_realPassword), VaultActionResult.success);
    await state.addAccount(
      AccountDraft(
        platformName: '真实平台',
        loginAccount: 'real@example.test',
        password: 'REAL-SECRET',
      ),
      initialSubscription: SubscriptionDetailsDraft(
        serviceName: '每周查看的订阅',
        firstSubscribedOn: DateTime(2026, 1, 1),
        nextRenewalOn: DateTime(2026, 10, 1),
      ),
    );
    expect(
      await state.enableQuickUnlock(
        _realPassword,
        scope: QuickUnlockScope.subscriptionsOnly,
      ),
      isTrue,
    );

    state.lock();
    expect(await state.unlockWithQuickUnlock(), VaultActionResult.success);
    expect(state.hasSubscriptionOnlyAccess, isTrue);
    expect(state.subscriptions.single.serviceName, '每周查看的订阅');
    expect(state.accounts.single.loginAccount, isNull);
    expect(state.accounts.single.password, isNull);
    expect(await state.addAccount(AccountDraft(platformName: '不得写入')), isFalse);

    state.lock();
    expect(await state.unlock(_realPassword), VaultActionResult.success);
    expect(state.hasFullVaultAccess, isTrue);
    expect(state.accounts.single.loginAccount, 'real@example.test');
    expect(state.accounts.single.password, 'REAL-SECRET');
    expect(
      await state.createDecoyVault(
        currentMasterPassword: _realPassword,
        decoyPassword: _decoyPassword,
      ),
      isTrue,
    );

    state.lock();
    expect(await state.unlock(_decoyPassword), VaultActionResult.success);
    expect(state.hasFullVaultAccess, isTrue);
    expect(state.canManageSecurity, isFalse);
    expect(state.accounts, isEmpty);
    expect(state.quickUnlockEnabled, isFalse);
    expect(await state.verifyMasterPassword(_decoyPassword), isFalse);
    expect(
      await state.enableQuickUnlock(
        _decoyPassword,
        scope: QuickUnlockScope.subscriptionsOnly,
      ),
      isFalse,
    );
    expect(await state.disableQuickUnlock(), isFalse);
    await state.addAccount(AccountDraft(platformName: '普通日历'));

    state.lock();
    expect(await state.unlock(_realPassword), VaultActionResult.success);
    expect(state.accounts.single.platformName, '真实平台');
    expect(state.quickUnlockEnabled, isFalse);
    expect(
      await state.enableQuickUnlock(
        _realPassword,
        scope: QuickUnlockScope.subscriptionsOnly,
      ),
      isTrue,
    );
  });

  test('v2 恢复保留设备安全设置且可回到导入前完整数据', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-restore-flow-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final quickUnlock = _MemoryQuickUnlockStore();
    addTearDown(quickUnlock.destroy);
    final store = LayeredVaultStore.forDirectory(
      directory: directory,
      creationKdf: _testKdf,
      quickUnlockSecretStore: quickUnlock,
    );
    final journal = FileVaultRecoveryJournal(
      fileProvider: () async =>
          File('${directory.path}${Platform.pathSeparator}rollback.json'),
    );
    final state = AppState(vaultStore: store, recoveryJournal: journal);
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_realPassword);
    await state.addAccount(AccountDraft(platformName: '备份中的账号'));
    final backup = await state.exportEncryptedBackup(
      backupMasterPassword: _backupPassword,
    );
    expect(backup, isNotNull);
    final backupBytes = backup!;
    expect(
      await state.createDecoyVault(
        currentMasterPassword: _realPassword,
        decoyPassword: _decoyPassword,
      ),
      isTrue,
    );
    expect(await state.verifyMasterPassword(_decoyPassword), isFalse);
    expect(await state.verifyMasterPassword(_realPassword), isTrue);

    await state.addAccount(AccountDraft(platformName: '导入前第二个账号'));
    await state.updatePreferences(
      state.preferences.copyWith(
        autoLockSeconds: 60,
        notificationsEnabled: false,
      ),
    );
    expect(state.accounts, hasLength(2));

    expect(
      await state.restoreEncryptedBackup(
        bytes: backupBytes,
        backupMasterPassword: _backupPassword,
        currentMasterPassword: _decoyPassword,
      ),
      isFalse,
    );
    expect(state.accounts, hasLength(2));
    expect(state.hasRecoveryRollback, isFalse);

    expect(
      await state.restoreEncryptedBackup(
        bytes: backupBytes,
        backupMasterPassword: _backupPassword,
        currentMasterPassword: _realPassword,
      ),
      isTrue,
    );
    expect(state.accounts.single.platformName, '备份中的账号');
    expect(state.preferences.autoLockSeconds, 60);
    expect(state.hasRecoveryRollback, isTrue);

    expect(
      await state.restoreLastRecoveryRollback(
        currentMasterPassword: _realPassword,
      ),
      isTrue,
    );
    expect(
      state.accounts.map((account) => account.platformName),
      containsAll(<String>['备份中的账号', '导入前第二个账号']),
    );
    expect(state.preferences.autoLockSeconds, 60);
  });

  test('回滚数据已写入后 journal 标记失败不留下可写的旧内存快照', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-rollback-journal-failure-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final quickUnlock = _MemoryQuickUnlockStore();
    addTearDown(quickUnlock.destroy);
    final store = LayeredVaultStore.forDirectory(
      directory: directory,
      creationKdf: _testKdf,
      quickUnlockSecretStore: quickUnlock,
    );
    final delegate = FileVaultRecoveryJournal(
      fileProvider: () async =>
          File('${directory.path}${Platform.pathSeparator}rollback.json'),
    );
    final state = AppState(
      vaultStore: store,
      recoveryJournal: _FailRolledBackJournal(delegate),
    );
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_realPassword);
    await state.addAccount(AccountDraft(platformName: '回滚目标-A'));
    final backup = await state.exportEncryptedBackup(
      backupMasterPassword: _backupPassword,
    );
    await state.addAccount(AccountDraft(platformName: '回滚目标-B'));

    expect(
      await state.restoreEncryptedBackup(
        bytes: backup!,
        backupMasterPassword: _backupPassword,
        currentMasterPassword: _realPassword,
      ),
      isTrue,
    );
    expect(state.accounts, hasLength(1));

    expect(
      await state.restoreLastRecoveryRollback(
        currentMasterPassword: _realPassword,
      ),
      isTrue,
    );
    expect(
      state.accounts.map((account) => account.platformName),
      containsAll(<String>['回滚目标-A', '回滚目标-B']),
    );
    expect(state.warningMessage, contains('回滚事务状态未能确认'));

    await state.addAccount(AccountDraft(platformName: '回滚后新增-C'));
    state.lock();
    final reopened = await store.unlock(masterPassword: _realPassword);
    expect(
      reopened.snapshot.accounts.map((account) => account.platformName),
      containsAll(<String>['回滚目标-A', '回滚目标-B', '回滚后新增-C']),
    );
    reopened.session.close();
  });

  test('真实库未完成的 journal 刷新不会串入后续诱饵会话', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-recovery-decoy-isolation-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final quickUnlock = _MemoryQuickUnlockStore();
    addTearDown(quickUnlock.destroy);
    final store = LayeredVaultStore.forDirectory(
      directory: directory,
      creationKdf: _testKdf,
      quickUnlockSecretStore: quickUnlock,
    );
    final journal = _BlockingRecoveryJournal();
    final state = AppState(vaultStore: store, recoveryJournal: journal);
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_realPassword);
    expect(journal.readCount, 1);
    expect(
      await state.createDecoyVault(
        currentMasterPassword: _realPassword,
        decoyPassword: _decoyPassword,
      ),
      isTrue,
    );

    state.lock();
    expect(await state.unlock(_decoyPassword), VaultActionResult.success);
    expect(state.canManageSecurity, isFalse);
    expect(journal.readCount, 1);

    journal.completePrepared();
    await Future<void>.delayed(Duration.zero);
    expect(state.warningMessage, isNull);
    expect(state.hasRecoveryRollback, isFalse);
    expect(journal.readCount, 1);
  });

  test('同一真实会话的慢 journal 读取不会覆盖随后恢复的新状态', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-recovery-refresh-token-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final quickUnlock = _MemoryQuickUnlockStore();
    addTearDown(quickUnlock.destroy);
    final store = LayeredVaultStore.forDirectory(
      directory: directory,
      creationKdf: _testKdf,
      quickUnlockSecretStore: quickUnlock,
    );
    final journal = _StaleReadRecoveryJournal();
    final state = AppState(vaultStore: store, recoveryJournal: journal);
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_realPassword);
    expect(journal.readCount, 1);
    await state.addAccount(AccountDraft(platformName: '慢读取前账号'));
    final backup = await state.exportEncryptedBackup(
      backupMasterPassword: _backupPassword,
    );
    await state.addAccount(AccountDraft(platformName: '待替换账号'));

    expect(
      await state.restoreEncryptedBackup(
        bytes: backup!,
        backupMasterPassword: _backupPassword,
        currentMasterPassword: _realPassword,
      ),
      isTrue,
    );
    expect(state.hasRecoveryRollback, isTrue);

    journal.completeInitialReadWithNull();
    await Future<void>.delayed(Duration.zero);
    expect(state.hasRecoveryRollback, isTrue);
    expect(state.accounts.single.platformName, '慢读取前账号');
  });
}

final class _FailRolledBackJournal implements VaultRecoveryJournal {
  const _FailRolledBackJournal(this._delegate);

  final VaultRecoveryJournal _delegate;

  @override
  Future<VaultRecoveryEntry?> read() => _delegate.read();

  @override
  Future<void> clear() => _delegate.clear();

  @override
  Future<String> stage({
    required List<int> encryptedVaultBytes,
    required int sourceGeneration,
  }) => _delegate.stage(
    encryptedVaultBytes: encryptedVaultBytes,
    sourceGeneration: sourceGeneration,
  );

  @override
  Future<void> markCommitted(String transactionId) =>
      _delegate.markCommitted(transactionId);

  @override
  Future<void> markRolledBack(String transactionId) async {
    throw const VaultStorageException();
  }
}

final class _BlockingRecoveryJournal implements VaultRecoveryJournal {
  final Completer<VaultRecoveryEntry?> _readCompleter =
      Completer<VaultRecoveryEntry?>();
  int readCount = 0;

  @override
  Future<VaultRecoveryEntry?> read() {
    readCount += 1;
    return _readCompleter.future;
  }

  @override
  Future<void> clear() async {
    throw const VaultStorageException();
  }

  void completePrepared() {
    _readCompleter.complete(
      VaultRecoveryEntry(
        transactionId: 'pending-real-restore',
        createdAtUtc: DateTime.utc(2026, 8, 1),
        sourceGeneration: 1,
        revision: 1,
        state: VaultRecoveryState.prepared,
        encryptedVaultBytes: <int>[1, 2, 3],
      ),
    );
  }

  @override
  Future<String> stage({
    required List<int> encryptedVaultBytes,
    required int sourceGeneration,
  }) async => throw const VaultStorageException();

  @override
  Future<void> markCommitted(String transactionId) async {
    throw const VaultStorageException();
  }

  @override
  Future<void> markRolledBack(String transactionId) async {
    throw const VaultStorageException();
  }
}

final class _StaleReadRecoveryJournal implements VaultRecoveryJournal {
  final Completer<VaultRecoveryEntry?> _initialRead =
      Completer<VaultRecoveryEntry?>();
  int readCount = 0;
  String? _transactionId;
  VaultRecoveryState? _state;

  @override
  Future<VaultRecoveryEntry?> read() {
    readCount += 1;
    if (readCount == 1) return _initialRead.future;
    final transactionId = _transactionId;
    final state = _state;
    if (transactionId == null || state == null) {
      return Future<VaultRecoveryEntry?>.value();
    }
    return Future<VaultRecoveryEntry?>.value(
      VaultRecoveryEntry(
        transactionId: transactionId,
        createdAtUtc: DateTime.utc(2026, 8, 1),
        sourceGeneration: 1,
        revision: state == VaultRecoveryState.prepared ? 1 : 2,
        state: state,
        encryptedVaultBytes: <int>[9, 8, 7],
      ),
    );
  }

  @override
  Future<void> clear() async {
    _transactionId = null;
    _state = null;
  }

  void completeInitialReadWithNull() => _initialRead.complete();

  @override
  Future<String> stage({
    required List<int> encryptedVaultBytes,
    required int sourceGeneration,
  }) async {
    _transactionId = 'new-restore-transaction';
    _state = VaultRecoveryState.prepared;
    return _transactionId!;
  }

  @override
  Future<void> markCommitted(String transactionId) async {
    if (transactionId != _transactionId) throw const VaultStorageException();
    _state = VaultRecoveryState.committed;
  }

  @override
  Future<void> markRolledBack(String transactionId) async {
    if (transactionId != _transactionId) throw const VaultStorageException();
    _state = VaultRecoveryState.rolledBack;
  }
}

final class _MemoryQuickUnlockStore implements QuickUnlockSecretStore {
  QuickUnlockSecret? _secret;

  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.available;

  @override
  Future<bool> containsSecret() async => _secret != null;

  @override
  Future<void> deleteSecret() async {
    _secret?.destroy();
    _secret = null;
  }

  @override
  Future<QuickUnlockSecret?> readSecret() async {
    final secret = _secret;
    if (secret == null) return null;
    return QuickUnlockSecret(vaultId: secret.vaultId, dataKey: secret.dataKey);
  }

  @override
  Future<void> writeSecret(QuickUnlockSecret secret) async {
    _secret?.destroy();
    _secret = QuickUnlockSecret(
      vaultId: secret.vaultId,
      dataKey: secret.dataKey,
    );
  }

  void destroy() {
    _secret?.destroy();
    _secret = null;
  }
}
