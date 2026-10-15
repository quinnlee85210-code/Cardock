import 'dart:convert';
import 'dart:io';

import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/storage/encrypted_vault_store.dart';
import 'package:account_subscription_manager/core/storage/vault_recovery_journal.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/pending_subscription_draft.dart';
import 'package:flutter_test/flutter_test.dart';

const _testKdf = VaultKdfParameters(
  memoryKiB: 64,
  iterations: 1,
  parallelism: 1,
);
const _password = 'TEST-ONLY-BATCH-ROLLBACK-1234';

void main() {
  test('批量提交把提交前快照持久为独立认证密文且只能撤销一次', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-batch-rollback-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final store = _store(directory);
    final opened = await store.create(masterPassword: _password);
    final session = opened.session as BatchRollbackVaultSession;
    final before = opened.snapshot;
    final after = _snapshot('批量导入密文哨兵-SENTINEL');

    await session.saveBatchWithRollback(before: before, after: after);
    final rollbackFile = File(
      '${directory.path}${Platform.pathSeparator}batch_import_rollback_v1.envelope',
    );
    expect(await rollbackFile.exists(), isTrue);
    final raw = utf8.decode(await rollbackFile.readAsBytes());
    expect(jsonDecode(raw), isA<Map<String, Object?>>());
    expect(raw, isNot(contains('批量导入密文哨兵-SENTINEL')));
    expect(session.canUndoLastBatch, isTrue);
    expect(
      session.batchRollbackAvailability,
      BatchRollbackAvailability.available,
    );
    expect(session.lastBatchRollbackSummary?.addedAccountCount, 1);

    final restored = await session.undoLastBatch();
    expect(restored.accounts, isEmpty);
    expect(session.canUndoLastBatch, isFalse);
    expect(await rollbackFile.exists(), isFalse);
    await expectLater(
      session.undoLastBatch(),
      throwsA(isA<VaultBatchRollbackUnavailableException>()),
    );
    session.close();
  });

  test('过期提交前快照失败时主 generation 与数据均不变', () async {
    final directory = await Directory.systemTemp.createTemp('asm-batch-stale-');
    addTearDown(() => _deleteDirectory(directory));
    final store = _store(directory);
    final opened = await store.create(masterPassword: _password);
    final session = opened.session as BatchRollbackVaultSession;
    final generation = session.generation;

    await expectLater(
      session.saveBatchWithRollback(
        before: _snapshot('并非当前快照'),
        after: _snapshot('不得写入'),
      ),
      throwsA(isA<VaultStorageException>()),
    );
    expect(session.generation, generation);
    expect(session.canUndoLastBatch, isFalse);
    session.close();

    final reopened = await store.unlock(masterPassword: _password);
    expect(reopened.snapshot.accounts, isEmpty);
    reopened.session.close();
  });

  test('业务 revision 改变后跨重启保留原因并安全拒绝，显式丢弃才清除', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-batch-invalidate-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final store = _store(directory);
    final opened = await store.create(masterPassword: _password);
    final session = opened.session as BatchRollbackVaultSession;
    await session.saveBatchWithRollback(
      before: opened.snapshot,
      after: _snapshot('第一次批量'),
    );
    expect(session.canUndoLastBatch, isTrue);

    await session.save(_snapshot('批量后的普通修改'));
    expect(session.canUndoLastBatch, isFalse);
    expect(
      session.batchRollbackAvailability,
      BatchRollbackAvailability.revisionChanged,
    );
    final rollbackFile = File(
      '${directory.path}${Platform.pathSeparator}'
      'batch_import_rollback_v1.envelope',
    );
    expect(await rollbackFile.exists(), isTrue);
    session.close();

    final reopened = await _store(directory).unlock(masterPassword: _password);
    final reopenedSession = reopened.session as BatchRollbackVaultSession;
    expect(reopenedSession.canUndoLastBatch, isFalse);
    expect(
      reopenedSession.batchRollbackAvailability,
      BatchRollbackAvailability.revisionChanged,
    );
    await expectLater(
      reopenedSession.undoLastBatch(),
      throwsA(isA<VaultBatchRollbackUnavailableException>()),
    );
    expect(reopened.snapshot.accounts.single.platformName, '批量后的普通修改');
    await reopenedSession.discardLastBatchRollback();
    expect(
      reopenedSession.batchRollbackAvailability,
      BatchRollbackAvailability.none,
    );
    expect(await rollbackFile.exists(), isFalse);
    reopenedSession.close();
  });

  test('锁定、应用重启和模拟设备重启后仍可发现，回滚成功后永不重复', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-batch-persistent-',
    );
    addTearDown(() => _deleteDirectory(directory));

    final created = await _store(directory).create(masterPassword: _password);
    final firstSession = created.session as BatchRollbackVaultSession;
    await firstSession.saveBatchWithRollback(
      before: created.snapshot,
      after: _snapshot('跨会话批量'),
    );
    firstSession.close();

    final appRestart = await _store(
      directory,
    ).unlock(masterPassword: _password);
    final appRestartSession = appRestart.session as BatchRollbackVaultSession;
    expect(appRestart.snapshot.accounts.single.platformName, '跨会话批量');
    expect(appRestartSession.canUndoLastBatch, isTrue);
    expect(appRestartSession.lastBatchRollbackSummary?.addedAccountCount, 1);
    appRestartSession.close();

    final deviceRestart = await _store(
      directory,
    ).unlock(masterPassword: _password);
    final deviceRestartSession =
        deviceRestart.session as BatchRollbackVaultSession;
    expect(
      deviceRestartSession.batchRollbackAvailability,
      BatchRollbackAvailability.available,
    );
    final restored = await deviceRestartSession.undoLastBatch();
    expect(restored.accounts, isEmpty);
    expect(deviceRestartSession.canUndoLastBatch, isFalse);
    deviceRestartSession.close();

    final afterRollbackRestart = await _store(
      directory,
    ).unlock(masterPassword: _password);
    final afterRollbackSession =
        afterRollbackRestart.session as BatchRollbackVaultSession;
    expect(afterRollbackRestart.snapshot.accounts, isEmpty);
    expect(afterRollbackSession.canUndoLastBatch, isFalse);
    expect(
      afterRollbackSession.batchRollbackAvailability,
      BatchRollbackAvailability.none,
    );
    await expectLater(
      afterRollbackSession.undoLastBatch(),
      throwsA(isA<VaultBatchRollbackUnavailableException>()),
    );
    afterRollbackSession.close();
  });

  test('下一次成功批量导入替换旧回滚点且只恢复到第二次导入之前', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-batch-replace-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final opened = await _store(directory).create(masterPassword: _password);
    final session = opened.session as BatchRollbackVaultSession;
    final afterFirst = _snapshot('第一次成功批量');
    await session.saveBatchWithRollback(
      before: opened.snapshot,
      after: afterFirst,
    );
    await session.saveBatchWithRollback(
      before: afterFirst,
      after: _snapshot('第二次成功批量'),
    );

    final restored = await session.undoLastBatch();
    expect(restored.accounts.single.platformName, '第一次成功批量');
    expect(session.canUndoLastBatch, isFalse);
    session.close();
  });

  test('另一会话推进主 revision 后旧会话也必须安全拒绝回滚', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-batch-cross-session-revision-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final firstStore = _store(directory);
    final opened = await firstStore.create(masterPassword: _password);
    final staleSession = opened.session as BatchRollbackVaultSession;
    await staleSession.saveBatchWithRollback(
      before: opened.snapshot,
      after: _snapshot('待撤销批量'),
    );

    final concurrent = await _store(
      directory,
    ).unlock(masterPassword: _password);
    await concurrent.session.save(_snapshot('另一会话业务修改'));
    concurrent.session.close();

    await expectLater(
      staleSession.undoLastBatch(),
      throwsA(isA<VaultBatchRollbackUnavailableException>()),
    );
    expect(staleSession.canUndoLastBatch, isFalse);
    expect(
      staleSession.batchRollbackAvailability,
      BatchRollbackAvailability.revisionChanged,
    );
    staleSession.close();

    final verified = await _store(directory).unlock(masterPassword: _password);
    expect(verified.snapshot.accounts.single.platformName, '另一会话业务修改');
    expect(
      (verified.session as BatchRollbackVaultSession).batchRollbackAvailability,
      BatchRollbackAvailability.revisionChanged,
    );
    verified.session.close();
  });

  test('提交交换与回滚消费中断均按原子边界恢复且已提交回滚不复活', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-batch-atomic-recovery-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final created = await _store(directory).create(masterPassword: _password);
    final createdSession = created.session as BatchRollbackVaultSession;
    await createdSession.saveBatchWithRollback(
      before: created.snapshot,
      after: _snapshot('原子恢复批量'),
    );
    createdSession.close();

    final active = File(
      '${directory.path}${Platform.pathSeparator}'
      'batch_import_rollback_v1.envelope',
    );
    final superseded = File('${active.path}.superseded');
    final consuming = File('${active.path}.consuming');

    // 模拟下一次批量提交在旧 active 已移到 superseded 后进程终止。
    await active.rename(superseded.path);
    final recoveredSwap = await _store(
      directory,
    ).unlock(masterPassword: _password);
    final recoveredSwapSession =
        recoveredSwap.session as BatchRollbackVaultSession;
    expect(recoveredSwapSession.canUndoLastBatch, isTrue);
    expect(await active.exists(), isTrue);
    expect(await superseded.exists(), isFalse);
    recoveredSwapSession.close();

    // 模拟 undo 在 active 已消费但主 generation 尚未提交时进程终止。
    await active.rename(consuming.path);
    final recoveredConsume = await _store(
      directory,
    ).unlock(masterPassword: _password);
    final recoveredConsumeSession =
        recoveredConsume.session as BatchRollbackVaultSession;
    expect(recoveredConsumeSession.canUndoLastBatch, isTrue);
    expect(await active.exists(), isTrue);
    expect(await consuming.exists(), isFalse);
    final retiredRollbackBytes = await active.readAsBytes();
    final restored = await recoveredConsumeSession.undoLastBatch();
    expect(restored.accounts, isEmpty);
    recoveredConsumeSession.close();

    // 模拟主快照已提交但 consuming 物理清理失败；旧密文不得再次授权。
    await consuming.writeAsBytes(retiredRollbackBytes, flush: true);
    retiredRollbackBytes.fillRange(0, retiredRollbackBytes.length, 0);
    final afterCommittedUndo = await _store(
      directory,
    ).unlock(masterPassword: _password);
    final afterCommittedUndoSession =
        afterCommittedUndo.session as BatchRollbackVaultSession;
    expect(afterCommittedUndo.snapshot.accounts, isEmpty);
    expect(afterCommittedUndoSession.canUndoLastBatch, isFalse);
    expect(
      afterCommittedUndoSession.batchRollbackAvailability,
      BatchRollbackAvailability.none,
    );
    expect(await consuming.exists(), isFalse);
    afterCommittedUndoSession.close();
  });

  test('批量回滚快照包含草稿且文件类型独立于恢复 journal', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-batch-draft-rollback-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final store = _store(directory);
    final opened = await store.create(masterPassword: _password);
    final session = opened.session as BatchRollbackVaultSession;
    final before = _snapshotWithDraft();
    await session.save(before);
    await session.saveBatchWithRollback(
      before: before,
      after: _snapshot('导入后正式数据'),
    );

    final names = (await directory.list().toList())
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .toList(growable: false);
    expect(names, contains('batch_import_rollback_v1.envelope'));
    expect(names.where((name) => name.contains('recovery_journal')), isEmpty);
    final restored = await session.undoLastBatch();
    expect(restored.pendingSubscriptionDrafts.single.planName, '回滚草稿');
    session.close();
  });

  test('批量回滚与备份恢复前回滚使用独立类型和状态并可同时存在', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-batch-restore-coexist-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final opened = await _store(directory).create(masterPassword: _password);
    final session = opened.session as BatchRollbackVaultSession;
    final recoveryBase = File(
      '${directory.path}${Platform.pathSeparator}recovery'
      '${Platform.pathSeparator}last_restore_rollback_v1.json',
    );
    final journal = FileVaultRecoveryJournal(
      fileProvider: () async => recoveryBase,
    );
    final exported = await session.exportEncryptedBackup();
    final transactionId = await journal.stage(
      encryptedVaultBytes: exported,
      sourceGeneration: session.generation,
    );
    exported.fillRange(0, exported.length, 0);
    await journal.markCommitted(transactionId);
    final committedBefore = await journal.read();
    expect(committedBefore?.state, VaultRecoveryState.committed);
    final recoveryRevision = committedBefore?.revision;
    committedBefore?.destroy();

    await session.saveBatchWithRollback(
      before: opened.snapshot,
      after: _snapshot('与恢复 journal 并存'),
    );
    expect(session.canUndoLastBatch, isTrue);
    var recovery = await journal.read();
    expect(recovery?.transactionId, transactionId);
    expect(recovery?.state, VaultRecoveryState.committed);
    expect(recovery?.revision, recoveryRevision);
    recovery?.destroy();

    await session.undoLastBatch();
    recovery = await journal.read();
    expect(recovery?.transactionId, transactionId);
    expect(recovery?.state, VaultRecoveryState.committed);
    expect(recovery?.revision, recoveryRevision);
    recovery?.destroy();
    session.close();
  });
}

EncryptedVaultStore _store(Directory directory) => EncryptedVaultStore(
  directoryProvider: () async => directory,
  creationKdf: _testKdf,
);

VaultSnapshot _snapshot(String platformName) => VaultSnapshot(
  nextAccountId: 2,
  accounts: <AccountRecord>[
    AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: platformName),
    ),
  ],
);

VaultSnapshot _snapshotWithDraft() {
  final account = AccountRecord.fromDraft(
    id: 'account-1',
    draft: AccountDraft(platformName: '草稿账号'),
  );
  return VaultSnapshot(
    nextAccountId: 2,
    accounts: <AccountRecord>[account],
    pendingSubscriptionDrafts: <PendingSubscriptionDraft>[
      PendingSubscriptionDraft(
        draftId: 'pending-rollback',
        accountId: account.id,
        planName: '回滚草稿',
        createdAt: DateTime.utc(2026, 8, 30),
        updatedAt: DateTime.utc(2026, 8, 30),
      ),
    ],
  );
}

Future<void> _deleteDirectory(Directory directory) async {
  if (await directory.exists()) await directory.delete(recursive: true);
}
