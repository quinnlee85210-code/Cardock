import 'dart:io';

import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/security/biometric_unlock.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/storage/layered_vault_store.dart';
import 'package:account_subscription_manager/core/storage/vault_recovery_journal.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:flutter_test/flutter_test.dart';

const _currentMasterPassword = 'Current-Master-74!Quartz';
const _newMasterPassword = 'Rotated-Master-85!Harbor';
const _backupPassword = 'Archive-Backup-62!River';
const _currentDecoyPassword = '故事1234';
const _newDecoyPassword = '新故事789';
const _testKdf = VaultKdfParameters(
  memoryKiB: 64,
  iterations: 1,
  parallelism: 1,
);

void main() {
  test('AppState 修改主密码后保留数据、停用快速解锁且旧密码失效', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final state = fixture.state;
    await state.addAccount(AccountDraft(platformName: '真实账号'));
    expect(
      await state.enableQuickUnlock(
        _currentMasterPassword,
        scope: QuickUnlockScope.fullVault,
      ),
      isTrue,
    );

    expect(
      await state.changeMasterPassword(
        currentMasterPassword: _currentMasterPassword,
        newMasterPassword: _newMasterPassword,
      ),
      isTrue,
    );
    expect(state.accounts.single.platformName, '真实账号');
    expect(state.quickUnlockEnabled, isFalse);
    expect(state.quickUnlockScope, isNull);

    state.lock();
    expect(
      await state.unlock(_currentMasterPassword),
      VaultActionResult.rejected,
    );
    expect(await state.unlock(_newMasterPassword), VaultActionResult.success);
    expect(state.accounts.single.platformName, '真实账号');
  });

  test('诱饵密码可重复修改，要求双授权并保持真实库和快速解锁不变', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final state = fixture.state;
    await state.addAccount(AccountDraft(platformName: '真实账号'));
    expect(
      await state.createDecoyVault(
        currentMasterPassword: _currentMasterPassword,
        decoyPassword: _currentDecoyPassword,
      ),
      isTrue,
    );
    state.lock();
    expect(
      await state.unlock(_currentDecoyPassword),
      VaultActionResult.success,
    );
    await state.addAccount(AccountDraft(platformName: '诱饵账号'));
    state.lock();
    expect(
      await state.unlock(_currentMasterPassword),
      VaultActionResult.success,
    );
    expect(
      await state.enableQuickUnlock(
        _currentMasterPassword,
        scope: QuickUnlockScope.fullVault,
      ),
      isTrue,
    );

    expect(
      await state.changeDecoyPassword(
        currentMasterPassword: 'Wrong-Real-Master-74!Quartz',
        currentDecoyPassword: _currentDecoyPassword,
        newDecoyPassword: _newDecoyPassword,
      ),
      isFalse,
    );
    expect(state.quickUnlockEnabled, isTrue);
    expect(
      await state.changeDecoyPassword(
        currentMasterPassword: _currentMasterPassword,
        currentDecoyPassword: _currentDecoyPassword,
        newDecoyPassword: _newDecoyPassword,
      ),
      isTrue,
    );
    expect(state.accounts.single.platformName, '真实账号');
    expect(state.quickUnlockEnabled, isTrue);

    state.lock();
    expect(
      await state.unlock(_currentDecoyPassword),
      VaultActionResult.rejected,
    );
    expect(await state.unlock(_newDecoyPassword), VaultActionResult.success);
    expect(state.accounts.single.platformName, '诱饵账号');
    state.lock();
    expect(
      await state.unlock(_currentMasterPassword),
      VaultActionResult.success,
    );
    expect(state.accounts.single.platformName, '真实账号');
  });

  test('有效恢复回滚副本默认阻止换密，明确放弃后才允许', () async {
    final fixture = await _Fixture.create(withRecoveryJournal: true);
    addTearDown(fixture.dispose);
    final state = fixture.state;
    await state.addAccount(AccountDraft(platformName: '备份账号'));
    final backup = await state.exportEncryptedBackup(
      backupMasterPassword: _backupPassword,
    );
    expect(backup, isNotNull);
    await state.addAccount(AccountDraft(platformName: '导入前账号'));
    expect(
      await state.restoreEncryptedBackup(
        bytes: backup!,
        backupMasterPassword: _backupPassword,
        currentMasterPassword: _currentMasterPassword,
      ),
      isTrue,
    );
    expect(state.hasRecoveryRollback, isTrue);

    expect(
      await state.changeMasterPassword(
        currentMasterPassword: _currentMasterPassword,
        newMasterPassword: _newMasterPassword,
      ),
      isFalse,
    );
    expect(state.errorMessage, contains('回滚副本'));
    expect(await fixture.journal!.read(), isNotNull);

    expect(
      await state.changeMasterPassword(
        currentMasterPassword: _currentMasterPassword,
        newMasterPassword: _newMasterPassword,
        discardRecoveryRollback: true,
      ),
      isTrue,
    );
    expect(await fixture.journal!.read(), isNull);
    expect(state.hasRecoveryRollback, isFalse);
    state.lock();
    expect(
      await state.unlock(_currentMasterPassword),
      VaultActionResult.rejected,
    );
    expect(await state.unlock(_newMasterPassword), VaultActionResult.success);
    expect(state.accounts.single.platformName, '备份账号');
  });

  test('prepared 恢复事务即使要求放弃也会失败关闭并保留旧主密码', () async {
    final fixture = await _Fixture.create(withRecoveryJournal: true);
    addTearDown(fixture.dispose);
    final state = fixture.state;
    await fixture.journal!.stage(
      encryptedVaultBytes: <int>[1, 2, 3, 4],
      sourceGeneration: 1,
    );

    expect(
      await state.changeMasterPassword(
        currentMasterPassword: _currentMasterPassword,
        newMasterPassword: _newMasterPassword,
        discardRecoveryRollback: true,
      ),
      isFalse,
    );
    expect(state.errorMessage, contains('尚未确认'));
    final recovery = await fixture.journal!.read();
    expect(recovery?.state, VaultRecoveryState.prepared);
    recovery?.destroy();
    state.lock();
    expect(
      await state.unlock(_currentMasterPassword),
      VaultActionResult.success,
    );
  });
}

final class _Fixture {
  const _Fixture({
    required this.directory,
    required this.quickUnlock,
    required this.state,
    this.journal,
  });

  final Directory directory;
  final _MemoryQuickUnlockStore quickUnlock;
  final AppState state;
  final FileVaultRecoveryJournal? journal;

  static Future<_Fixture> create({bool withRecoveryJournal = false}) async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-app-state-password-rotation-',
    );
    final quickUnlock = _MemoryQuickUnlockStore();
    final store = LayeredVaultStore.forDirectory(
      directory: directory,
      creationKdf: _testKdf,
      quickUnlockSecretStore: quickUnlock,
    );
    final journal = withRecoveryJournal
        ? FileVaultRecoveryJournal(
            fileProvider: () async =>
                File('${directory.path}${Platform.pathSeparator}rollback.json'),
          )
        : null;
    final state = AppState(
      vaultStore: store,
      recoveryJournal: journal ?? const NoopVaultRecoveryJournal(),
    );
    await state.initialize();
    expect(
      await state.createVault(_currentMasterPassword),
      VaultActionResult.success,
    );
    return _Fixture(
      directory: directory,
      quickUnlock: quickUnlock,
      state: state,
      journal: journal,
    );
  }

  Future<void> dispose() async {
    state.dispose();
    quickUnlock.destroy();
    for (var attempt = 0; attempt < 5; attempt += 1) {
      try {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
        return;
      } on FileSystemException {
        if (attempt == 4) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 50 * (attempt + 1)));
      }
    }
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
