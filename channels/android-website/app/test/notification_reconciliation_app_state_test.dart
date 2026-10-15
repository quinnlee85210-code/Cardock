import 'dart:io';
import 'dart:async';
import 'support/fake_vault_store.dart';

import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/data_import/data_import.dart';
import 'package:account_subscription_manager/core/platform/notification_reliability.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/storage/encrypted_vault_store.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_reminder_scheduler.dart';

const _testKdf = VaultKdfParameters(
  memoryKiB: 64,
  iterations: 1,
  parallelism: 1,
);
const _password = 'TEST-ONLY-NOTIFICATION-APPSTATE-1234';

void main() {
  test(
    'unlock queues saved reminders before delayed storage read and immediate background lock',
    () async {
      final store = FakeVaultStore();
      final scheduler = RecordingReminderScheduler();
      final state = AppState(vaultStore: store, reminderScheduler: scheduler);
      addTearDown(state.dispose);
      await state.initialize();
      await state.createVault(_password);
      await state.setNotificationsEnabled(true);
      await state.createSubscription(
        SubscriptionDraft(accountId: null, details: _details()),
      );
      state.lock();
      scheduler.reset();
      final gate = Completer<void>();
      store.notificationReadGate = gate;
      expect(await state.unlock(_password), VaultActionResult.success);
      state.lock();
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(scheduler.rescheduleCalls, hasLength(1));
      expect(scheduler.rescheduleCalls.single.subscriptionIds, hasLength(1));
      expect(state.isUnlocked, isFalse);
    },
  );

  test('失败 outbox 跨锁定、应用重启和模拟设备重启保留并在解锁自动重试', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-notification-appstate-restart-',
    );
    addTearDown(() => _deleteDirectory(directory));

    final firstScheduler = RecordingReminderScheduler();
    var state = AppState(
      vaultStore: _store(directory),
      reminderScheduler: firstScheduler,
    );
    addTearDown(() => state.dispose());
    await state.initialize();
    expect(await state.createVault(_password), VaultActionResult.success);
    await _drainEventQueue();
    expect(
      await state.setNotificationsEnabled(true),
      NotificationSettingResult.enabled,
    );
    firstScheduler.reset();
    firstScheduler.failOn = ReminderSchedulerOperation.rescheduleAll;

    expect(
      (await state.createAccount(
        AccountDraft(platformName: 'TEST-ONLY-REMINDER-OUTBOX'),
        initialSubscription: _details(),
      )).saved,
      isTrue,
    );
    var report = await state.inspectNotificationReliability();
    expect(
      report.reconciliation.health,
      NotificationReconciliationHealth.pending,
    );
    expect(report.reconciliation.attemptCount, 1);

    state.lock();
    firstScheduler.reset(clearFailure: false);
    expect(await state.unlock(_password), VaultActionResult.success);
    await _waitUntil(() => firstScheduler.rescheduleCalls.isNotEmpty);
    report = await _waitForReconciliation(
      state,
      NotificationReconciliationHealth.pending,
      attemptCount: 2,
    );
    expect(
      report.reconciliation.health,
      NotificationReconciliationHealth.pending,
    );
    expect(report.reconciliation.attemptCount, 2);

    // New AppState + new store object models process termination/app restart.
    state.dispose();
    final secondScheduler = RecordingReminderScheduler()
      ..failOn = ReminderSchedulerOperation.rescheduleAll;
    state = AppState(
      vaultStore: _store(directory),
      reminderScheduler: secondScheduler,
    );
    await state.initialize();
    expect(await state.unlock(_password), VaultActionResult.success);
    await _waitUntil(() => secondScheduler.rescheduleCalls.isNotEmpty);
    report = await _waitForReconciliation(
      state,
      NotificationReconciliationHealth.pending,
      attemptCount: 3,
    );
    expect(
      report.reconciliation.health,
      NotificationReconciliationHealth.pending,
    );
    expect(report.reconciliation.attemptCount, 3);

    // A second complete reconstruction models the same private files after a
    // device reboot. The authoritative retry occurs at the next primary-vault
    // unlock because business data cannot be decrypted while the vault is locked.
    state.dispose();
    final thirdScheduler = RecordingReminderScheduler();
    state = AppState(
      vaultStore: _store(directory),
      reminderScheduler: thirdScheduler,
    );
    await state.initialize();
    expect(await state.unlock(_password), VaultActionResult.success);
    await _waitUntil(() => thirdScheduler.rescheduleCalls.isNotEmpty);
    report = await _waitForReconciliation(
      state,
      NotificationReconciliationHealth.upToDate,
    );
    expect(
      report.reconciliation.health,
      NotificationReconciliationHealth.upToDate,
    );
    expect(thirdScheduler.rescheduleCalls, hasLength(1));
    expect(
      thirdScheduler.rescheduleCalls.single.subscriptionIds,
      state.subscriptions.map((item) => item.id).toList(growable: false),
    );
  });

  test('关闭提醒清理失败也持久化，重启解锁后自动 cancel 并清账', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-notification-appstate-cancel-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final scheduler = RecordingReminderScheduler();
    var state = AppState(
      vaultStore: _store(directory),
      reminderScheduler: scheduler,
    );
    addTearDown(() => state.dispose());
    await state.initialize();
    expect(await state.createVault(_password), VaultActionResult.success);
    await _drainEventQueue();
    expect(
      await state.setNotificationsEnabled(true),
      NotificationSettingResult.enabled,
    );
    scheduler.reset();
    scheduler.failOn = ReminderSchedulerOperation.cancelAll;

    expect(
      await state.setNotificationsEnabled(false),
      NotificationSettingResult.cancelFailed,
    );
    expect(state.preferences.notificationsEnabled, isFalse);
    var report = await state.inspectNotificationReliability();
    expect(
      report.reconciliation.health,
      NotificationReconciliationHealth.pending,
    );
    expect(report.reconciliation.attemptCount, 1);

    state.dispose();
    final retryScheduler = RecordingReminderScheduler();
    state = AppState(
      vaultStore: _store(directory),
      reminderScheduler: retryScheduler,
    );
    await state.initialize();
    expect(await state.unlock(_password), VaultActionResult.success);
    await _waitUntil(() => retryScheduler.cancelAllCalls > 0);
    expect(retryScheduler.cancelAllCalls, 1);
    report = await _waitForReconciliation(
      state,
      NotificationReconciliationHealth.upToDate,
    );
    expect(
      report.reconciliation.health,
      NotificationReconciliationHealth.upToDate,
    );
  });

  test('账号-only 批量导入回滚不创建虚假提醒 outbox', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-notification-account-only-rollback-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final scheduler = RecordingReminderScheduler();
    final state = AppState(
      vaultStore: _store(directory),
      reminderScheduler: scheduler,
    );
    addTearDown(state.dispose);
    await state.initialize();
    expect(await state.createVault(_password), VaultActionResult.success);
    await _drainEventQueue();
    expect(
      await state.setNotificationsEnabled(true),
      NotificationSettingResult.enabled,
    );
    scheduler.reset();

    final result = await state.commitBatchImport(
      _importPlan(
        state,
        accounts: <AccountImportDraft>[
          AccountImportDraft(
            originalRowNumber: 2,
            sourceId: 'account-only-row-2',
            accountKey: 'account-only-key',
            platformName: 'TEST-ONLY-ACCOUNT-ONLY',
          ),
        ],
      ),
    );
    expect(result.success, isTrue);
    expect(scheduler.rescheduleCalls, isEmpty);
    expect(await state.undoLastBatchImport(), isTrue);
    expect(scheduler.rescheduleCalls, isEmpty);

    final report = await state.inspectNotificationReliability();
    expect(
      report.reconciliation.health,
      NotificationReconciliationHealth.upToDate,
    );
  });

  test('含正式订阅的批量导入回滚仍重排提醒并完整清账', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-notification-subscription-rollback-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final scheduler = RecordingReminderScheduler();
    final state = AppState(
      vaultStore: _store(directory),
      reminderScheduler: scheduler,
    );
    addTearDown(state.dispose);
    await state.initialize();
    expect(await state.createVault(_password), VaultActionResult.success);
    await _drainEventQueue();
    expect(
      await state.setNotificationsEnabled(true),
      NotificationSettingResult.enabled,
    );
    scheduler.reset();

    final result = await state.commitBatchImport(
      _importPlan(
        state,
        accounts: <AccountImportDraft>[
          AccountImportDraft(
            originalRowNumber: 2,
            sourceId: 'subscription-account-row-2',
            accountKey: 'subscription-account-key',
            platformName: 'TEST-ONLY-SUBSCRIPTION-ACCOUNT',
          ),
        ],
        subscriptions: <SubscriptionImportDraft>[
          SubscriptionImportDraft(
            originalRowNumber: 2,
            sourceId: 'subscription-row-2',
            accountKey: 'subscription-account-key',
            accountKeyWasGenerated: false,
            planName: 'TEST-ONLY-PLAN',
            amount: '1.00',
            currency: 'CNY',
            billingCycle: 'monthly',
            subscriptionStartDate: '2026-08-01',
            nextRenewalDate: '2026-09-01',
            autoRenew: 'true',
            paymentMethod: 'TEST-ONLY',
            reminderDays: '3',
          ),
        ],
      ),
    );
    expect(result.success, isTrue);
    expect(scheduler.rescheduleCalls, hasLength(1));
    scheduler.reset();

    expect(await state.undoLastBatchImport(), isTrue);
    expect(scheduler.rescheduleCalls, hasLength(1));
    expect(scheduler.rescheduleCalls.single.subscriptionIds, isEmpty);
    final report = await state.inspectNotificationReliability();
    expect(
      report.reconciliation.health,
      NotificationReconciliationHealth.upToDate,
    );
  });
}

EncryptedVaultStore _store(Directory directory) => EncryptedVaultStore(
  directoryProvider: () async => directory,
  creationKdf: _testKdf,
);

SubscriptionDetailsDraft _details() => SubscriptionDetailsDraft(
  serviceName: 'TEST-ONLY-OUTBOX-SERVICE',
  planName: 'TEST-ONLY-PLAN',
  amount: '1.00',
  currency: 'CNY',
  firstSubscribedOn: DateTime(2026, 8, 1),
  nextRenewalOn: DateTime(2026, 9, 1),
  cycleCount: 1,
  cycleUnit: SubscriptionCycleUnit.month,
  autoRenew: true,
  paymentMethod: 'TEST-ONLY',
  reminderDaysBefore: 3,
);

ImportPlan _importPlan(
  AppState state, {
  required List<AccountImportDraft> accounts,
  List<SubscriptionImportDraft> subscriptions =
      const <SubscriptionImportDraft>[],
}) => ImportPlan(
  vaultScopeId: state.importVaultScopeId!,
  expectedVaultRevision: state.localWebRevision,
  newAccounts: accounts,
  accountUpdates: const <AccountUpdatePlan>[],
  skippedAccounts: const <AccountImportDraft>[],
  formalSubscriptions: subscriptions,
  pendingSubscriptionDrafts: const <SubscriptionImportDraft>[],
  unsupportedItemCount: 0,
  unresolvedDuplicateCount: 0,
  quota: ImportQuotaValidationResult.unlimited(
    requestedAccounts: accounts.length,
    requestedSubscriptions: subscriptions.length,
  ),
);

Future<void> _drainEventQueue() async {
  for (var index = 0; index < 8; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var index = 0; index < 100; index += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('TEST-ONLY asynchronous notification reconciliation did not finish');
}

Future<NotificationReliabilityReport> _waitForReconciliation(
  AppState state,
  NotificationReconciliationHealth health, {
  int? attemptCount,
}) async {
  NotificationReliabilityReport? latest;
  for (var index = 0; index < 100; index += 1) {
    latest = await state.inspectNotificationReliability();
    if (latest.reconciliation.health == health &&
        (attemptCount == null ||
            latest.reconciliation.attemptCount == attemptCount)) {
      return latest;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail(
    'TEST-ONLY reconciliation state did not become $health/$attemptCount: '
    '${latest?.reconciliation.health}/${latest?.reconciliation.attemptCount}',
  );
}

Future<void> _deleteDirectory(Directory directory) async {
  if (await directory.exists()) await directory.delete(recursive: true);
}
