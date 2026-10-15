import 'dart:async';
import 'dart:io';

import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/data_import/data_import.dart';
import 'package:account_subscription_manager/core/platform/notification_reliability.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/storage/encrypted_vault_store.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_reminder_scheduler.dart';

const _testKdf = VaultKdfParameters(
  memoryKiB: 64,
  iterations: 1,
  parallelism: 1,
);
const _password = 'TEST-ONLY-BATCH-LOCK-RACE-1234';

void main() {
  test('close 在线性化保存开始前生效时拒绝批量写入且重开仍为空', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-batch-close-before-save-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final store = _store(directory);
    final opened = await store.create(masterPassword: _password);
    final session = opened.session as BatchRollbackVaultSession;
    final generation = session.generation;
    session.close();

    await expectLater(
      session.saveBatchWithRollback(
        before: opened.snapshot,
        after: _snapshotWithAccount(),
      ),
      throwsA(isA<VaultClosedException>()),
    );

    final reopened = await store.unlock(masterPassword: _password);
    expect(reopened.session.generation, generation);
    expect(reopened.snapshot.accounts, isEmpty);
    expect(
      (reopened.session as BatchRollbackVaultSession).canUndoLastBatch,
      isFalse,
    );
    reopened.session.close();
  });

  test('主槽 rename 后锁定仍按已提交返回且锁定态不回填敏感内存', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-batch-close-after-rename-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final renameCommitted = Completer<void>();
    final releaseCommit = Completer<void>();
    var gateEnabled = false;
    final store = _store(
      directory,
      afterEnvelopeCommitRenameForTesting: (generation) async {
        if (!gateEnabled) return;
        gateEnabled = false;
        renameCommitted.complete();
        await releaseCommit.future;
      },
    );
    final reminders = RecordingReminderScheduler();
    final state = AppState(vaultStore: store, reminderScheduler: reminders);
    addTearDown(state.dispose);
    await state.initialize();
    expect(await state.createVault(_password), VaultActionResult.success);
    expect(
      await state.updatePreferences(
        state.preferences.copyWith(notificationsEnabled: true),
      ),
      isTrue,
    );
    reminders.reset();
    final plan = _plan(state);
    final originalRevision = state.localWebRevision;

    gateEnabled = true;
    final commitFuture = state.commitBatchImport(plan);
    await renameCommitted.future;
    state.lock();

    expect(state.vaultPhase, VaultPhase.locked);
    expect(state.accounts, isEmpty);
    expect(state.subscriptions, isEmpty);
    expect(state.pendingSubscriptionDrafts, isEmpty);
    expect(state.importVaultScopeId, isNull);
    expect(state.canUndoLastBatchImport, isFalse);
    expect(state.lastBatchRollbackImpact, isNull);

    releaseCommit.complete();
    final result = await commitFuture;

    expect(result.success, isTrue);
    expect(result.failureCode, isNull);
    expect(result.addedAccountCount, 1);
    expect(result.formalSubscriptionCount, 1);
    expect(result.resultingVaultRevision, originalRevision + 1);
    expect(result.rollbackAvailable, isFalse);
    expect(state.vaultPhase, VaultPhase.locked);
    expect(state.isBusy, isFalse);
    expect(state.accounts, isEmpty);
    expect(state.subscriptions, isEmpty);
    expect(state.pendingSubscriptionDrafts, isEmpty);
    expect(state.canUndoLastBatchImport, isFalse);
    expect(state.lastBatchRollbackImpact, isNull);
    expect(reminders.rescheduleCalls, isEmpty);

    expect(await state.unlock(_password), VaultActionResult.success);
    expect(state.accounts.single.platformName, '锁定竞态平台');
    expect(state.subscriptions.single.planName, '锁定竞态套餐');
    expect(state.canUndoLastBatchImport, isTrue);
    expect(state.lastBatchRollbackImpact?.addedAccountCount, 1);
    expect(state.lastBatchRollbackImpact?.formalSubscriptionCount, 1);
    await _waitForReminderReschedule(reminders);
    await _waitForNotificationReconciliation(state);
    state.lock();
  });

  test('主提交后的 superseded 清理失败不反转 AppState 成功且新会话清残留', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-batch-post-commit-cleanup-',
    );
    addTearDown(() => _deleteDirectory(directory));
    var injectedFailures = 0;
    final store = _store(
      directory,
      beforeCommittedBatchCleanupForTesting: (artifactPath) async {
        if (artifactPath.endsWith('.superseded')) {
          injectedFailures += 1;
          throw FileSystemException('test-only cleanup failure', artifactPath);
        }
      },
    );
    final state = AppState(vaultStore: store);
    addTearDown(state.dispose);
    await state.initialize();
    expect(await state.createVault(_password), VaultActionResult.success);

    final first = await state.commitBatchImport(
      _accountOnlyPlan(
        state,
        sourceId: 'cleanup-account-1',
        accountKey: 'cleanup-key-1',
        platformName: '清理故障平台甲',
      ),
    );
    expect(first.success, isTrue);
    expect(first.rollbackAvailable, isTrue);

    final second = await state.commitBatchImport(
      _accountOnlyPlan(
        state,
        sourceId: 'cleanup-account-2',
        accountKey: 'cleanup-key-2',
        platformName: '清理故障平台乙',
      ),
    );
    expect(injectedFailures, 1);
    expect(second.success, isTrue);
    expect(second.addedAccountCount, 1);
    expect(second.rollbackAvailable, isTrue);
    expect(state.accounts, hasLength(2));

    final superseded = File(
      '${directory.path}${Platform.pathSeparator}'
      'batch_import_rollback_v1.envelope.superseded',
    );
    expect(await superseded.exists(), isTrue);

    state.lock();
    expect(state.accounts, isEmpty);
    expect(state.canUndoLastBatchImport, isFalse);
    expect(await state.unlock(_password), VaultActionResult.success);
    expect(
      state.accounts.map((account) => account.platformName).toSet(),
      <String>{'清理故障平台甲', '清理故障平台乙'},
    );
    expect(state.canUndoLastBatchImport, isTrue);
    expect(await state.undoLastBatchImport(), isTrue);
    expect(
      state.accounts.map((account) => account.platformName).toSet(),
      <String>{'清理故障平台甲'},
    );
    expect(state.canUndoLastBatchImport, isFalse);
    expect(await superseded.exists(), isFalse);
  });
}

EncryptedVaultStore _store(
  Directory directory, {
  Future<void> Function(int committedGeneration)?
  afterEnvelopeCommitRenameForTesting,
  Future<void> Function(String artifactPath)?
  beforeCommittedBatchCleanupForTesting,
}) => EncryptedVaultStore(
  directoryProvider: () async => directory,
  creationKdf: _testKdf,
  afterEnvelopeCommitRenameForTesting: afterEnvelopeCommitRenameForTesting,
  beforeCommittedBatchCleanupForTesting: beforeCommittedBatchCleanupForTesting,
);

VaultSnapshot _snapshotWithAccount() => VaultSnapshot(
  nextAccountId: 2,
  accounts: <AccountRecord>[
    AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: '不得写入平台'),
    ),
  ],
);

ImportPlan _plan(AppState state) {
  final account = AccountImportDraft(
    originalRowNumber: 1,
    sourceId: 'account-row-1',
    accountKey: 'account-key-1',
    platformName: '锁定竞态平台',
    loginAccount: 'race-user@example.invalid',
  );
  final subscription = SubscriptionImportDraft(
    originalRowNumber: 2,
    sourceId: 'subscription-row-2',
    accountKey: 'account-key-1',
    accountKeyWasGenerated: false,
    planName: '锁定竞态套餐',
    amount: '12.50',
    currency: 'CNY',
    billingCycle: 'monthly',
    subscriptionStartDate: '2026-08-30',
    nextRenewalDate: '2026-09-30',
    autoRenew: 'true',
    paymentMethod: '测试卡',
    reminderDays: '3',
  );
  return ImportPlan(
    vaultScopeId: state.importVaultScopeId!,
    expectedVaultRevision: state.localWebRevision,
    newAccounts: <AccountImportDraft>[account],
    accountUpdates: const <AccountUpdatePlan>[],
    skippedAccounts: const <AccountImportDraft>[],
    formalSubscriptions: <SubscriptionImportDraft>[subscription],
    pendingSubscriptionDrafts: const <SubscriptionImportDraft>[],
    unsupportedItemCount: 0,
    unresolvedDuplicateCount: 0,
    quota: const ImportQuotaValidationResult.unlimited(
      requestedAccounts: 1,
      requestedSubscriptions: 1,
    ),
  );
}

ImportPlan _accountOnlyPlan(
  AppState state, {
  required String sourceId,
  required String accountKey,
  required String platformName,
}) => ImportPlan(
  vaultScopeId: state.importVaultScopeId!,
  expectedVaultRevision: state.localWebRevision,
  newAccounts: <AccountImportDraft>[
    AccountImportDraft(
      originalRowNumber: 1,
      sourceId: sourceId,
      accountKey: accountKey,
      platformName: platformName,
      loginAccount: '$sourceId@example.invalid',
    ),
  ],
  accountUpdates: const <AccountUpdatePlan>[],
  skippedAccounts: const <AccountImportDraft>[],
  formalSubscriptions: const <SubscriptionImportDraft>[],
  pendingSubscriptionDrafts: const <SubscriptionImportDraft>[],
  unsupportedItemCount: 0,
  unresolvedDuplicateCount: 0,
  quota: const ImportQuotaValidationResult.unlimited(
    requestedAccounts: 1,
    requestedSubscriptions: 0,
  ),
);

Future<void> _deleteDirectory(Directory directory) async {
  if (await directory.exists()) await directory.delete(recursive: true);
}

Future<void> _waitForReminderReschedule(
  RecordingReminderScheduler scheduler,
) async {
  for (var index = 0; index < 100; index += 1) {
    if (scheduler.rescheduleCalls.isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('解锁后的提醒重排未在测试等待窗口内完成');
}

Future<void> _waitForNotificationReconciliation(AppState state) async {
  for (var index = 0; index < 100; index += 1) {
    final report = await state.inspectNotificationReliability();
    if (report.reconciliation.health ==
        NotificationReconciliationHealth.upToDate) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('解锁后的提醒协调未在测试等待窗口内完成');
}
