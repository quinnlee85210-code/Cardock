import 'dart:io';

import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/data_import/data_import.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
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
const _password = 'TEST-ONLY-APP-BATCH-1234';

void main() {
  test('正式订阅导入公开纯校验与权威转换规则同源', () {
    expect(AppState.isFormalSubscriptionImportValid(_formalDraft()), isTrue);
    expect(
      AppState.isFormalSubscriptionImportValid(_unknownStartDraft()),
      isFalse,
    );
    expect(
      AppState.isFormalSubscriptionImportValid(_reversedDatesDraft()),
      isFalse,
    );
    expect(AppState.isFormalSubscriptionImportValid(_pendingDraft()), isFalse);
  });

  test('未知开始日期不会被续费日期替代且只能加密保存为待完善草稿', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-import-start-date-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final state = AppState(vaultStore: _store(directory));
    addTearDown(state.dispose);
    await state.initialize();
    expect(await state.createVault(_password), VaultActionResult.success);

    final unknown = _unknownStartDraft();
    final rejected = await state.commitBatchImport(
      _plan(state, formalSubscriptions: <SubscriptionImportDraft>[unknown]),
    );
    expect(rejected.success, isFalse);
    expect(rejected.failureCode, 'validation_failed');
    expect(state.subscriptions, isEmpty);
    expect(state.pendingSubscriptionDrafts, isEmpty);

    final saved = await state.commitBatchImport(
      _plan(
        state,
        pendingSubscriptionDrafts: <SubscriptionImportDraft>[unknown],
      ),
    );
    expect(saved.success, isTrue);
    expect(state.subscriptions, isEmpty);
    expect(state.pendingSubscriptionDrafts, hasLength(1));
    final draft = state.pendingSubscriptionDrafts.single;
    expect(draft.subscriptionStartDate, isNull);
    expect(draft.nextRenewalDate, DateTime(2026, 9, 30));
    expect(draft.missingFormalFields, contains('subscriptionStartDate'));
  });

  test('AppState权威提交一次写入正式订阅和草稿且草稿不进入提醒', () async {
    final directory = await Directory.systemTemp.createTemp('asm-app-batch-');
    addTearDown(() => _deleteDirectory(directory));
    final reminders = RecordingReminderScheduler();
    final state = AppState(
      vaultStore: _store(directory),
      reminderScheduler: reminders,
    );
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

    final plan = _plan(
      state,
      formalSubscriptions: <SubscriptionImportDraft>[_formalDraft()],
      pendingSubscriptionDrafts: <SubscriptionImportDraft>[_pendingDraft()],
    );
    final result = await state.commitBatchImport(plan);

    expect(result.success, isTrue);
    expect(result.resultingVaultRevision, state.localWebRevision);
    expect(result.rollbackAvailable, isTrue);
    expect(state.accounts, hasLength(1));
    expect(state.subscriptions, hasLength(1));
    expect(state.subscriptions.single.cycleCount, 3);
    expect(state.subscriptions.single.cycleUnit, SubscriptionCycleUnit.month);
    expect(state.subscriptions.single.autoRenew, isTrue);
    expect(state.subscriptions.single.notes, '正式直导备注');
    expect(state.subscriptions.single.firstSubscribedOn, DateTime(2026, 8, 15));
    expect(state.subscriptions.single.nextRenewalOn, DateTime(2026, 9, 30));
    expect(state.pendingSubscriptionDrafts, hasLength(1));
    expect(
      state.pendingSubscriptionDrafts.single.subscriptionStartDate,
      DateTime(2026, 8, 15),
    );
    expect(state.canUndoLastBatchImport, isTrue);
    expect(state.lastBatchRollbackImpact?.addedAccountCount, 1);
    expect(state.lastBatchRollbackImpact?.formalSubscriptionCount, 1);
    expect(state.lastBatchRollbackImpact?.pendingSubscriptionDraftCount, 1);
    expect(state.lastBatchRollbackImpact?.affectedRecordCount, 3);
    expect(reminders.rescheduleCalls, hasLength(1));
    expect(reminders.rescheduleCalls.single.subscriptionIds, <String>[
      state.subscriptions.single.id,
    ]);

    final incomplete = await state.completePendingSubscriptionDraft(
      draftId: state.pendingSubscriptionDrafts.single.draftId,
      details: SubscriptionDetailsDraft(
        serviceName: '缺少套餐与金额',
        currency: 'CNY',
        firstSubscribedOn: DateTime(2026, 8, 30),
        nextRenewalOn: DateTime(2026, 9, 30),
        cycleCount: 1,
        cycleUnit: SubscriptionCycleUnit.month,
        autoRenew: true,
        paymentMethod: '支付宝',
        reminderDaysBefore: 3,
      ),
    );
    expect(incomplete.status, RecordCreationStatus.failed);
    expect(state.pendingSubscriptionDrafts, hasLength(1));

    for (var index = 0; index < 4; index += 1) {
      expect(
        (await state.createSubscription(
          SubscriptionDraft(accountId: null, details: _details('补位$index')),
        )).saved,
        isTrue,
      );
    }
    expect(state.canUndoLastBatchImport, isFalse);
    expect(state.lastBatchRollbackImpact, isNull);
    final blocked = await state.completePendingSubscriptionDraft(
      draftId: state.pendingSubscriptionDrafts.single.draftId,
      details: _details('补全后正式订阅'),
    );
    expect(blocked.status, RecordCreationStatus.limitReached);
    expect(state.pendingSubscriptionDrafts, hasLength(1));

    expect(await state.deleteSubscription(state.subscriptions.last.id), isTrue);
    final completed = await state.completePendingSubscriptionDraft(
      draftId: state.pendingSubscriptionDrafts.single.draftId,
      details: SubscriptionDetailsDraft(
        serviceName: '补全后正式订阅',
        planName: '标准套餐',
        amount: '1.00',
        currency: 'CNY',
        firstSubscribedOn: DateTime(2026, 8, 30),
        nextRenewalOn: DateTime(2026, 10, 30),
        cycleCount: 2,
        cycleUnit: SubscriptionCycleUnit.week,
        autoRenew: false,
        paymentMethod: '支付宝',
        reminderDaysBefore: 19,
      ),
    );
    expect(completed.saved, isTrue);
    expect(state.pendingSubscriptionDrafts, isEmpty);
    expect(
      state.subscriptions.where((item) => item.serviceName == '补全后正式订阅'),
      hasLength(1),
    );
    final completedRecord = state.subscriptions.singleWhere(
      (item) => item.serviceName == '补全后正式订阅',
    );
    expect(completedRecord.notes, '金额待核实');
    expect(completedRecord.cycleCount, 2);
    expect(completedRecord.cycleUnit, SubscriptionCycleUnit.week);
    expect(completedRecord.autoRenew, isFalse);
    expect(completedRecord.reminderDaysBefore, 19);
  });

  test('过期revision及伪造完整订阅均零写入', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-app-batch-reject-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final state = AppState(vaultStore: _store(directory));
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_password);

    final stale = _plan(
      state,
      expectedRevision: state.localWebRevision + 1,
      formalSubscriptions: <SubscriptionImportDraft>[_formalDraft()],
    );
    final staleResult = await state.commitBatchImport(stale);
    expect(staleResult.success, isFalse);
    expect(staleResult.failureCode, 'stale_preview');
    expect(state.accounts, isEmpty);

    final invalidFormal = SubscriptionImportDraft(
      originalRowNumber: 2,
      sourceId: 'sub-invalid',
      accountKey: 'acc-1',
      accountKeyWasGenerated: false,
      planName: '伪造正式订阅',
      amount: '-1',
      currency: 'CNY',
      billingCycle: '1 month',
      nextRenewalDate: '2026-09-30',
      autoRenew: 'true',
      paymentMethod: '支付宝',
      reminderDays: '',
    );
    final invalid = _plan(
      state,
      formalSubscriptions: <SubscriptionImportDraft>[invalidFormal],
    );
    final invalidResult = await state.commitBatchImport(invalid);
    expect(invalidResult.success, isFalse);
    expect(invalidResult.failureCode, 'validation_failed');
    expect(state.accounts, isEmpty);
    expect(state.subscriptions, isEmpty);
    expect(state.pendingSubscriptionDrafts, isEmpty);

    final missingPlanName = SubscriptionImportDraft(
      originalRowNumber: 3,
      sourceId: 'sub-missing-plan-name',
      accountKey: 'acc-1',
      accountKeyWasGenerated: false,
      amount: '12.50',
      currency: 'CNY',
      billingCycle: 'monthly',
      nextRenewalDate: '2026-09-30',
      autoRenew: 'true',
      paymentMethod: '支付宝',
      reminderDays: '3',
    );
    final missingPlanResult = await state.commitBatchImport(
      _plan(
        state,
        formalSubscriptions: <SubscriptionImportDraft>[missingPlanName],
      ),
    );
    expect(missingPlanResult.success, isFalse);
    expect(missingPlanResult.failureCode, 'validation_failed');
    expect(state.accounts, isEmpty);
    expect(state.subscriptions, isEmpty);
    expect(state.pendingSubscriptionDrafts, isEmpty);
  });

  test('多账号多订阅按每行标识和账号键一次关联提交', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-app-batch-multi-row-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final state = AppState(vaultStore: _store(directory));
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_password);

    final accounts = <AccountImportDraft>[
      AccountImportDraft(
        originalRowNumber: 1,
        sourceId: 'account-row-1',
        accountKey: 'acc-a',
        platformName: '平台甲',
        loginAccount: 'a@example.test',
      ),
      AccountImportDraft(
        originalRowNumber: 2,
        sourceId: 'account-row-2',
        accountKey: 'acc-b',
        platformName: '平台乙',
        loginAccount: 'b@example.test',
      ),
    ];
    SubscriptionImportDraft subscription(
      int row,
      String sourceId,
      String accountKey,
      String planName,
    ) => SubscriptionImportDraft(
      originalRowNumber: row,
      sourceId: sourceId,
      accountKey: accountKey,
      accountKeyWasGenerated: false,
      planName: planName,
      amount: '10.00',
      currency: 'CNY',
      billingCycle: 'monthly',
      subscriptionStartDate: '2026-08-30',
      nextRenewalDate: '2026-09-30',
      autoRenew: 'true',
      paymentMethod: '银行卡',
      reminderDays: '3',
    );
    final subscriptions = <SubscriptionImportDraft>[
      subscription(3, 'subscription-row-1', 'acc-a', '套餐甲'),
      subscription(4, 'subscription-row-2', 'acc-b', '套餐乙'),
    ];
    final result = await state.commitBatchImport(
      ImportPlan(
        vaultScopeId: state.importVaultScopeId!,
        expectedVaultRevision: state.localWebRevision,
        newAccounts: accounts,
        accountUpdates: const <AccountUpdatePlan>[],
        skippedAccounts: const <AccountImportDraft>[],
        formalSubscriptions: subscriptions,
        pendingSubscriptionDrafts: const <SubscriptionImportDraft>[],
        unsupportedItemCount: 0,
        unresolvedDuplicateCount: 0,
        quota: const ImportQuotaValidationResult.unlimited(
          requestedAccounts: 2,
          requestedSubscriptions: 2,
        ),
      ),
    );

    expect(result.success, isTrue);
    expect(state.accounts, hasLength(2));
    expect(state.subscriptions, hasLength(2));
    final platformById = <String, String>{
      for (final account in state.accounts) account.id: account.platformName,
    };
    expect(
      state.subscriptions.map((item) => platformById[item.accountId]).toSet(),
      <String>{'平台甲', '平台乙'},
    );
  });

  test('AppState拒绝 skipped/unsupported 零写计划且不创建回滚', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-app-batch-zero-write-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final state = AppState(vaultStore: _store(directory));
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_password);
    final revision = state.localWebRevision;
    final skipped = AccountImportDraft(
      originalRowNumber: 2,
      sourceId: 'skipped-row-2',
      accountKey: 'skipped-key',
      platformName: '未选平台',
    );

    ImportPlan zeroWritePlan({
      List<AccountImportDraft> skippedAccounts = const <AccountImportDraft>[],
      int unsupportedItemCount = 0,
    }) => ImportPlan(
      vaultScopeId: state.importVaultScopeId!,
      expectedVaultRevision: revision,
      newAccounts: const <AccountImportDraft>[],
      accountUpdates: const <AccountUpdatePlan>[],
      skippedAccounts: skippedAccounts,
      formalSubscriptions: const <SubscriptionImportDraft>[],
      pendingSubscriptionDrafts: const <SubscriptionImportDraft>[],
      unsupportedItemCount: unsupportedItemCount,
      unresolvedDuplicateCount: 0,
      quota: const ImportQuotaValidationResult.unlimited(
        requestedAccounts: 0,
        requestedSubscriptions: 0,
      ),
    );

    for (final plan in <ImportPlan>[
      zeroWritePlan(skippedAccounts: <AccountImportDraft>[skipped]),
      zeroWritePlan(unsupportedItemCount: 2),
    ]) {
      final result = await state.commitBatchImport(plan);
      expect(result.success, isFalse);
      expect(result.failureCode, 'plan_not_committable');
      expect(state.localWebRevision, revision);
      expect(state.accounts, isEmpty);
      expect(state.subscriptions, isEmpty);
      expect(state.pendingSubscriptionDrafts, isEmpty);
      expect(state.canUndoLastBatchImport, isFalse);
      expect(state.lastBatchRollbackImpact, isNull);
    }
  });

  test('逐字段更新默认保留现有值，空字段和密码也只按显式 true 写入', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-app-batch-field-merge-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final state = AppState(vaultStore: _store(directory));
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_password);
    expect(
      (await state.createAccount(
        AccountDraft(
          platformName: '既有平台',
          loginAccount: 'existing-user',
          boundEmail: 'existing@example.test',
          notes: '既有备注',
        ),
      )).saved,
      isTrue,
    );
    final accountId = state.accounts.single.id;

    ImportPlan updatePlan(
      AccountImportDraft draft,
      Map<String, bool> choices,
    ) => ImportPlan(
      vaultScopeId: state.importVaultScopeId!,
      expectedVaultRevision: state.localWebRevision,
      newAccounts: const <AccountImportDraft>[],
      accountUpdates: <AccountUpdatePlan>[
        AccountUpdatePlan(
          draft: draft,
          resolution: ImportDuplicateResolution.fieldByField,
          existingAccountId: accountId,
          useImportedField: choices,
        ),
      ],
      skippedAccounts: const <AccountImportDraft>[],
      formalSubscriptions: const <SubscriptionImportDraft>[],
      pendingSubscriptionDrafts: const <SubscriptionImportDraft>[],
      unsupportedItemCount: 0,
      unresolvedDuplicateCount: 0,
      quota: const ImportQuotaValidationResult.unlimited(
        requestedAccounts: 0,
        requestedSubscriptions: 0,
      ),
    );

    final first = await state.commitBatchImport(
      updatePlan(
        AccountImportDraft(
          originalRowNumber: 1,
          sourceId: 'update-row-1',
          accountKey: 'existing-account',
          platformName: '既有平台',
          loginAccount: 'imported-user',
          phone: '13800000000',
          email: 'imported@example.test',
          password: 'imported-password',
          url: 'https://example.test',
          notes: '默认不得写入',
        ),
        const <String, bool>{},
      ),
    );
    expect(first.success, isTrue);
    expect(state.accounts.single.boundPhone, isNull);
    expect(state.accounts.single.website, isNull);
    expect(state.accounts.single.loginAccount, 'existing-user');
    expect(state.accounts.single.boundEmail, 'existing@example.test');
    expect(state.accounts.single.password, isNull);
    expect(state.accounts.single.notes, '既有备注');

    final second = await state.commitBatchImport(
      updatePlan(
        AccountImportDraft(
          originalRowNumber: 2,
          sourceId: 'update-row-2',
          accountKey: 'existing-account',
          platformName: '既有平台',
          loginAccount: 'still-not-selected',
          phone: '13800000000',
          email: 'still-not-selected@example.test',
          password: 'explicit-password',
          url: 'https://example.test',
          notes: '显式追加',
        ),
        const <String, bool>{
          'phone': true,
          'email': false,
          'password': true,
          'url': true,
          'notes': true,
        },
      ),
    );
    expect(second.success, isTrue);
    expect(state.accounts.single.loginAccount, 'existing-user');
    expect(state.accounts.single.boundPhone, '13800000000');
    expect(state.accounts.single.boundEmail, 'existing@example.test');
    expect(state.accounts.single.password, 'explicit-password');
    expect(state.accounts.single.website, 'https://example.test');
    expect(state.accounts.single.notes, '既有备注\n显式追加');
    expect(state.accounts.single.passwordChangeHistory, isEmpty);
    final third = await state.commitBatchImport(
      updatePlan(
        AccountImportDraft(
          originalRowNumber: 3,
          sourceId: 'update-row-3',
          accountKey: 'existing-account',
          platformName: '既有平台',
          password: 'TEST-ONLY-REPLACED',
        ),
        const {'password': true},
      ),
    );
    expect(third.success, isTrue);
    expect(state.accounts.single.passwordChangeHistory, hasLength(1));
    final changedAt =
        state.accounts.single.passwordChangeHistory.single.changedAtUtc;
    state.lock();
    expect(await state.unlock(_password), VaultActionResult.success);
    expect(
      state.accounts.single.passwordChangeHistory.single.changedAtUtc,
      changedAt,
    );
    expect(await state.undoLastBatchImport(), isTrue);
    expect(state.accounts.single.password, 'explicit-password');
    expect(state.accounts.single.passwordChangeHistory, isEmpty);
  });

  test('一个账号可有多个草稿且删除账号原子级联清理', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-app-batch-cascade-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final state = AppState(vaultStore: _store(directory));
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_password);
    final result = await state.commitBatchImport(
      _plan(
        state,
        pendingSubscriptionDrafts: <SubscriptionImportDraft>[
          _pendingDraft(),
          SubscriptionImportDraft(
            originalRowNumber: 4,
            sourceId: 'subscription-row-3',
            accountKey: 'acc-1',
            accountKeyWasGenerated: false,
            planName: '第二个待补套餐',
            missingOrInvalidFields: const <String>['currency'],
          ),
        ],
      ),
    );
    expect(result.success, isTrue);
    expect(state.pendingSubscriptionDrafts, hasLength(2));
    final accountId = state.accounts.single.id;
    expect(
      state.pendingSubscriptionDrafts.every(
        (draft) => draft.accountId == accountId,
      ),
      isTrue,
    );

    expect(await state.deleteAccount(accountId), isTrue);
    expect(state.accounts, isEmpty);
    expect(state.pendingSubscriptionDrafts, isEmpty);
  });

  test('系统提醒同步失败只产生warning且不把已提交数据误报为零写入', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-app-batch-reminder-warning-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final reminders = RecordingReminderScheduler();
    final state = AppState(
      vaultStore: _store(directory),
      reminderScheduler: reminders,
    );
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_password);
    await state.updatePreferences(
      state.preferences.copyWith(notificationsEnabled: true),
    );
    reminders.failOn = ReminderSchedulerOperation.rescheduleAll;

    final result = await state.commitBatchImport(
      _plan(
        state,
        formalSubscriptions: <SubscriptionImportDraft>[_formalDraft()],
      ),
    );
    expect(result.success, isTrue);
    expect(result.rollbackAvailable, isTrue);
    expect(state.accounts, hasLength(1));
    expect(state.subscriptions, hasLength(1));
    expect(state.warningMessage, isNotNull);

    state.dismissWarning();
    expect(state.warningMessage, isNull);
    expect(await state.undoLastBatchImport(), isTrue);
    expect(state.accounts, isEmpty);
    expect(state.subscriptions, isEmpty);
    expect(state.warningMessage, isNotNull);
  });

  test('显式 existing target 不被同名新账号 alias 覆盖且正式与草稿同源', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-app-batch-explicit-target-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final state = AppState(vaultStore: _store(directory));
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_password);
    expect(
      (await state.createAccount(
        AccountDraft(
          platformName: '既有目标平台',
          loginAccount: 'existing@example.invalid',
        ),
      )).saved,
      isTrue,
    );
    final existingId = state.accounts.single.id;
    final newAccount = AccountImportDraft(
      originalRowNumber: 10,
      sourceId: 'new-account-source',
      accountKey: existingId,
      platformName: '覆盖 alias 的新平台',
      loginAccount: 'new@example.invalid',
    );
    final formal = SubscriptionImportDraft(
      originalRowNumber: 11,
      sourceId: 'formal-explicit-target',
      accountKey: existingId,
      accountKeyWasGenerated: false,
      accountTargetConfirmed: true,
      targetExistingAccountId: existingId,
      planName: '显式正式套餐',
      amount: '8.00',
      currency: 'CNY',
      billingCycle: 'monthly',
      subscriptionStartDate: '2026-09-30',
      nextRenewalDate: '2026-10-30',
      autoRenew: 'true',
      paymentMethod: '测试卡',
      reminderDays: '2',
    );
    final pending = SubscriptionImportDraft(
      originalRowNumber: 12,
      sourceId: 'pending-explicit-target',
      accountKey: existingId,
      accountKeyWasGenerated: false,
      accountTargetConfirmed: true,
      targetExistingAccountId: existingId,
      planName: '显式待完善套餐',
      missingOrInvalidFields: const <String>['amount'],
    );

    final result = await state.commitBatchImport(
      ImportPlan(
        vaultScopeId: state.importVaultScopeId!,
        expectedVaultRevision: state.localWebRevision,
        newAccounts: <AccountImportDraft>[newAccount],
        accountUpdates: const <AccountUpdatePlan>[],
        skippedAccounts: const <AccountImportDraft>[],
        formalSubscriptions: <SubscriptionImportDraft>[formal],
        pendingSubscriptionDrafts: <SubscriptionImportDraft>[pending],
        unsupportedItemCount: 0,
        unresolvedDuplicateCount: 0,
        quota: const ImportQuotaValidationResult.unlimited(
          requestedAccounts: 1,
          requestedSubscriptions: 1,
        ),
      ),
    );

    expect(result.success, isTrue);
    expect(state.accounts, hasLength(2));
    expect(state.subscriptions.single.accountId, existingId);
    expect(state.pendingSubscriptionDrafts.single.accountId, existingId);
  });

  test('伪造不存在的显式 target 对正式与草稿均 validation_failed 且零写', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-app-batch-missing-target-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final state = AppState(vaultStore: _store(directory));
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_password);
    expect(
      (await state.createAccount(
        AccountDraft(
          platformName: '保留平台',
          loginAccount: 'preserved@example.invalid',
        ),
      )).saved,
      isTrue,
    );
    final existingId = state.accounts.single.id;
    final revision = state.localWebRevision;

    SubscriptionImportDraft draft({required bool pending}) =>
        SubscriptionImportDraft(
          originalRowNumber: pending ? 22 : 21,
          sourceId: pending
              ? 'pending-missing-target'
              : 'formal-missing-target',
          accountKey: existingId,
          accountKeyWasGenerated: false,
          accountTargetConfirmed: true,
          targetExistingAccountId: 'account-does-not-exist',
          planName: pending ? '伪造草稿目标' : '伪造正式目标',
          amount: pending ? '' : '6.00',
          currency: pending ? '' : 'CNY',
          billingCycle: pending ? '' : 'monthly',
          nextRenewalDate: pending ? '' : '2026-11-30',
          autoRenew: pending ? '' : 'false',
          paymentMethod: pending ? '' : '测试卡',
          reminderDays: pending ? '' : '1',
          missingOrInvalidFields: pending
              ? const <String>['amount']
              : const <String>[],
        );

    for (final isPending in <bool>[false, true]) {
      final candidate = draft(pending: isPending);
      final result = await state.commitBatchImport(
        ImportPlan(
          vaultScopeId: state.importVaultScopeId!,
          expectedVaultRevision: revision,
          newAccounts: const <AccountImportDraft>[],
          accountUpdates: const <AccountUpdatePlan>[],
          skippedAccounts: const <AccountImportDraft>[],
          formalSubscriptions: isPending
              ? const <SubscriptionImportDraft>[]
              : <SubscriptionImportDraft>[candidate],
          pendingSubscriptionDrafts: isPending
              ? <SubscriptionImportDraft>[candidate]
              : const <SubscriptionImportDraft>[],
          unsupportedItemCount: 0,
          unresolvedDuplicateCount: 0,
          quota: ImportQuotaValidationResult.unlimited(
            requestedAccounts: 0,
            requestedSubscriptions: isPending ? 0 : 1,
          ),
        ),
      );

      expect(result.success, isFalse);
      expect(result.failureCode, 'validation_failed');
      expect(state.localWebRevision, revision);
      expect(state.accounts.single.id, existingId);
      expect(state.subscriptions, isEmpty);
      expect(state.pendingSubscriptionDrafts, isEmpty);
      expect(state.canUndoLastBatchImport, isFalse);
    }
  });

  test('锁定与新 AppState 后重建回滚影响，撤销后重新协调提醒且不可重复', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-app-batch-persistent-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final firstReminders = RecordingReminderScheduler();
    final first = AppState(
      vaultStore: _store(directory),
      reminderScheduler: firstReminders,
    );
    addTearDown(first.dispose);
    await first.initialize();
    expect(await first.createVault(_password), VaultActionResult.success);
    expect(
      await first.updatePreferences(
        first.preferences.copyWith(notificationsEnabled: true),
      ),
      isTrue,
    );
    firstReminders.reset();
    final committed = await first.commitBatchImport(
      _plan(
        first,
        formalSubscriptions: <SubscriptionImportDraft>[_formalDraft()],
      ),
    );
    expect(committed.success, isTrue);
    expect(first.canUndoLastBatchImport, isTrue);
    expect(first.lastBatchRollbackImpact?.addedAccountCount, 1);
    expect(first.lastBatchRollbackImpact?.formalSubscriptionCount, 1);

    first.lock();
    expect(first.canUndoLastBatchImport, isFalse);
    expect(first.lastBatchRollbackAvailability, BatchRollbackAvailability.none);
    firstReminders.reset();
    expect(await first.unlock(_password), VaultActionResult.success);
    await _waitForReminderReschedule(firstReminders);
    expect(first.canUndoLastBatchImport, isTrue);
    expect(first.lastBatchRollbackImpact?.addedAccountCount, 1);
    first.lock();

    final restartedReminders = RecordingReminderScheduler();
    final restarted = AppState(
      vaultStore: _store(directory),
      reminderScheduler: restartedReminders,
    );
    addTearDown(restarted.dispose);
    await restarted.initialize();
    expect(await restarted.unlock(_password), VaultActionResult.success);
    expect(
      restarted.lastBatchRollbackAvailability,
      BatchRollbackAvailability.available,
    );
    expect(restarted.lastBatchRollbackImpact?.addedAccountCount, 1);
    expect(restarted.lastBatchRollbackImpact?.formalSubscriptionCount, 1);
    await _waitForReminderReschedule(restartedReminders);
    restartedReminders.reset();

    expect(await restarted.undoLastBatchImport(), isTrue);
    expect(restarted.accounts, isEmpty);
    expect(restarted.subscriptions, isEmpty);
    expect(restarted.canUndoLastBatchImport, isFalse);
    expect(restartedReminders.rescheduleCalls, hasLength(1));
    expect(restartedReminders.rescheduleCalls.single.subscriptionIds, isEmpty);

    restarted.lock();
    restartedReminders.reset();
    expect(await restarted.unlock(_password), VaultActionResult.success);
    await _waitForReminderReschedule(restartedReminders);
    expect(restarted.canUndoLastBatchImport, isFalse);
    expect(
      restarted.lastBatchRollbackAvailability,
      BatchRollbackAvailability.none,
    );
    expect(await restarted.undoLastBatchImport(), isFalse);
    restarted.lock();
  });
}

ImportPlan _plan(
  AppState state, {
  int? expectedRevision,
  List<SubscriptionImportDraft> formalSubscriptions =
      const <SubscriptionImportDraft>[],
  List<SubscriptionImportDraft> pendingSubscriptionDrafts =
      const <SubscriptionImportDraft>[],
}) {
  final account = AccountImportDraft(
    originalRowNumber: 1,
    sourceId: 'account-row-1',
    accountKey: 'acc-1',
    platformName: '批量平台',
    loginAccount: 'user@example.test',
  );
  return ImportPlan(
    vaultScopeId: state.importVaultScopeId!,
    expectedVaultRevision: expectedRevision ?? state.localWebRevision,
    newAccounts: <AccountImportDraft>[account],
    accountUpdates: const <AccountUpdatePlan>[],
    skippedAccounts: const <AccountImportDraft>[],
    formalSubscriptions: formalSubscriptions,
    pendingSubscriptionDrafts: pendingSubscriptionDrafts,
    unsupportedItemCount: 0,
    unresolvedDuplicateCount: 0,
    quota: ImportQuotaValidationResult.unlimited(
      requestedAccounts: 1,
      requestedSubscriptions: formalSubscriptions.length,
    ),
  );
}

SubscriptionImportDraft _formalDraft() => SubscriptionImportDraft(
  originalRowNumber: 2,
  sourceId: 'subscription-row-1',
  accountKey: 'acc-1',
  accountKeyWasGenerated: false,
  planName: '正式套餐',
  amount: '12.50',
  currency: 'CNY',
  billingCycle: '四半期',
  subscriptionStartDate: '2026-08-15',
  nextRenewalDate: '2026-09-30',
  autoRenew: 'はい',
  paymentMethod: '支付宝',
  reminderDays: '3',
  notes: '正式直导备注',
);

SubscriptionImportDraft _unknownStartDraft() => SubscriptionImportDraft(
  originalRowNumber: 4,
  sourceId: 'subscription-row-unknown-start',
  accountKey: 'acc-1',
  accountKeyWasGenerated: false,
  planName: '开始日期未知套餐',
  amount: '12.50',
  currency: 'CNY',
  billingCycle: 'monthly',
  nextRenewalDate: '2026-09-30',
  autoRenew: 'true',
  paymentMethod: '测试卡',
  reminderDays: '3',
  missingOrInvalidFields: const <String>['subscription_start_date'],
);

SubscriptionImportDraft _reversedDatesDraft() => SubscriptionImportDraft(
  originalRowNumber: 5,
  sourceId: 'subscription-row-reversed-dates',
  accountKey: 'acc-1',
  accountKeyWasGenerated: false,
  planName: '日期倒置套餐',
  amount: '12.50',
  currency: 'CNY',
  billingCycle: 'monthly',
  subscriptionStartDate: '2026-10-01',
  nextRenewalDate: '2026-09-30',
  autoRenew: 'true',
  paymentMethod: '测试卡',
  reminderDays: '3',
);

SubscriptionImportDraft _pendingDraft() => SubscriptionImportDraft(
  originalRowNumber: 3,
  sourceId: 'subscription-row-2',
  accountKey: 'acc-1',
  accountKeyWasGenerated: false,
  planName: '待补套餐',
  billingCycle: 'custom',
  subscriptionStartDate: '2026-08-15',
  notes: '金额待核实',
  missingOrInvalidFields: const <String>['amount'],
);

SubscriptionDetailsDraft _details(String serviceName) =>
    SubscriptionDetailsDraft(
      serviceName: serviceName,
      planName: '标准套餐',
      amount: '1.00',
      currency: 'CNY',
      firstSubscribedOn: DateTime(2026, 8, 30),
      nextRenewalOn: DateTime(2026, 9, 30),
      cycleCount: 1,
      cycleUnit: SubscriptionCycleUnit.month,
      autoRenew: true,
      paymentMethod: '支付宝',
      reminderDaysBefore: 3,
    );

EncryptedVaultStore _store(Directory directory) => EncryptedVaultStore(
  directoryProvider: () async => directory,
  creationKdf: _testKdf,
);

Future<void> _waitForReminderReschedule(
  RecordingReminderScheduler scheduler,
) async {
  for (var index = 0; index < 100; index += 1) {
    if (scheduler.rescheduleCalls.isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('解锁后的提醒重排未在测试等待窗口内完成');
}

Future<void> _deleteDirectory(Directory directory) async {
  if (await directory.exists()) await directory.delete(recursive: true);
}
