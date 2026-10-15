import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_expense_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_cost_summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_vault_store.dart';
import 'support/recording_reminder_scheduler.dart';

const _master = 'TEST-ONLY-CHANGE-1234';
SubscriptionDraft _subscription(String? accountId, {String? amount = '20'}) =>
    SubscriptionDraft(
      accountId: accountId,
      details: SubscriptionDetailsDraft(
        serviceName: '同名服务',
        planName: '月度版',
        amount: amount,
        currency: 'CNY',
        firstSubscribedOn: DateTime(2026, 9, 1),
        nextRenewalOn: DateTime(2026, 10, 1),
      ),
    );
Future<AppState> _state(
  FakeVaultStore store, {
  RecordingReminderScheduler? scheduler,
}) async {
  final state = AppState(vaultStore: store, reminderScheduler: scheduler);
  addTearDown(state.dispose);
  await state.initialize();
  expect(await state.createVault(_master), VaultActionResult.success);
  return state;
}

SubscriptionCostAnalysis _analysis(AppState state, {DateTime? today}) =>
    SubscriptionCostAnalysis.build(
      subscriptions: state.subscriptions,
      expenses: state.subscriptionExpenses,
      range: SubscriptionCostRange(
        startMonth: DateTime(2026),
        endMonth: DateTime(2026, 12),
      ),
      today: today ?? DateTime(2026, 12, 31),
    );

Map<String, String> _confirmedMonthlyAmounts(
  SubscriptionCostAnalysis analysis,
) => {
  for (final month in analysis.byMonth(SubscriptionCostBasis.confirmed).entries)
    month.key: formatScaledSubscriptionAmount(
      month.value.fold<BigInt>(BigInt.zero, (total, line) {
        expect(line.currency, 'CNY');
        expect(line.amount, isNotNull);
        final amount = parseScaledSubscriptionAmount(line.amount!);
        return total + (line.refund ? -amount : amount);
      }),
    ),
};
void main() {
  test('旧复核设置保留兼容数据，但不再安排复核通知', () async {
    final scheduler = RecordingReminderScheduler();
    final state = await _state(FakeVaultStore(), scheduler: scheduler);
    await state.addAccount(
      AccountDraft(platformName: 'Test', password: 'TEST-ONLY-REVIEW'),
    );
    await state.setPasswordReviewInterval(state.accounts.single.id, 1);
    expect(await state.setPasswordReviewNotificationsEnabled(true), isTrue);
    expect(
      await state.setNotificationsEnabled(true),
      NotificationSettingResult.enabled,
    );
    scheduler.reset();
    state.lock();
    expect(await state.unlock(_master), VaultActionResult.success);
    await pumpEventQueue();
    expect(scheduler.rescheduleCalls, isNotEmpty);
    expect(
      scheduler.rescheduleCalls.every(
        (call) => call.passwordReviewAtUtc == null,
      ),
      isTrue,
    );
  });

  test('首次录入不计次，相同值与普通编辑不计次；保存失败不留下历史，重开保留日期', () async {
    final store = FakeVaultStore();
    final state = await _state(store);
    await state.addAccount(
      AccountDraft(
        platformName: '测试平台',
        category: '工作',
        loginAccount: 'tester@example.invalid',
        password: 'TEST-INITIAL',
      ),
    );
    final id = state.accounts.single.id;
    expect(state.accounts.single.passwordChangeHistory, isEmpty);
    Future<bool> save(String? password, AccountPasswordUpdateMode mode) =>
        state.updateAccount(
          accountId: id,
          draft: AccountDraft(
            platformName: '测试平台',
            category: '工作',
            loginAccount: 'tester@example.invalid',
            password: password,
          ),
          passwordMode: mode,
        );
    expect(
      await save('TEST-INITIAL', AccountPasswordUpdateMode.replace),
      isTrue,
    );
    expect(
      await save('TEST-IGNORED', AccountPasswordUpdateMode.preserve),
      isTrue,
    );
    expect(state.accounts.single.passwordChangeHistory, isEmpty);
    final firstStored = state.accounts.single.passwordStoredAtUtc;
    expect(
      await save('TEST-CHANGED', AccountPasswordUpdateMode.replace),
      isTrue,
    );
    final event = state.accounts.single.passwordChangeHistory.single;
    expect(event.previousStoredAtUtc, firstStored);
    expect(event.changedAtUtc.isUtc, isTrue);
    store.failSaves = true;
    expect(
      await save('TEST-FAILED', AccountPasswordUpdateMode.replace),
      isFalse,
    );
    expect(state.accounts.single.passwordChangeHistory, hasLength(1));
    expect(state.accounts.single.password, 'TEST-CHANGED');
    store.failSaves = false;
    state.lock();
    expect(state.accounts, isEmpty);
    expect(await state.unlock(_master), VaultActionResult.success);
    expect(
      state.accounts.single.passwordChangeHistory.single.toJson(),
      event.toJson(),
    );
    expect(await save(null, AccountPasswordUpdateMode.clear), isTrue);
    expect(state.accounts.single.password, isNull);
    expect(state.accounts.single.passwordChangeHistory, hasLength(1));
    // No old value is retained to compare after an explicit clear.
    expect(
      await save('TEST-NEW-BASELINE', AccountPasswordUpdateMode.replace),
      isTrue,
    );
    expect(state.accounts.single.passwordChangeHistory, hasLength(1));
    final payload = state.accounts.single.toEncryptedPayloadJson();
    expect(
      payload['passwordChangeHistory'].toString(),
      isNot(contains('TEST-CHANGED')),
    );
  });

  test('首次入账与过去每月续费完整统计，退款扣减且账号删除保留已有费用快照', () async {
    final store = FakeVaultStore();
    final state = await _state(store);
    await state.addAccount(
      AccountDraft(
        platformName: '平台',
        category: '工作',
        loginAccount: 'owner@example.invalid',
      ),
    );
    final id = state.accounts.single.id;
    await state.addSubscription(_subscription(id));
    final sub = state.subscriptions.single;
    expect(state.subscriptionExpenses, hasLength(1));
    expect(state.subscriptionExpenses.single.accountId, id);
    expect(
      state.subscriptionExpenses.single.accountLabel,
      contains('owner@example.invalid'),
    );
    final entryLedger = [
      for (final expense in state.subscriptionExpenses)
        expense.toEncryptedPayloadJson(),
    ];
    final initialAnalysis = _analysis(state);
    expect(_confirmedMonthlyAmounts(initialAnalysis), {
      '2026-09': '20',
      '2026-10': '20',
      '2026-11': '20',
      '2026-12': '20',
    });
    expect(
      initialAnalysis
          .currencyTotals(SubscriptionCostBasis.confirmed)
          .single
          .formattedAmount,
      '80',
    );
    expect(
      [
        for (final expense in state.subscriptionExpenses)
          expense.toEncryptedPayloadJson(),
      ],
      entryLedger,
      reason: '按月统计不会把日历推演直接写成新的付款流水',
    );
    await state.updateSubscription(
      subscriptionId: sub.id,
      draft: _subscription(id, amount: '30'),
    );
    expect(state.subscriptionExpenses, hasLength(1));
    expect(state.subscriptionExpenses.single.amount, '20');
    expect(
      await state.markSubscriptionRenewed(
        state.subscriptions.single,
        expense: SubscriptionExpenseDraft(
          subscriptionId: sub.id,
          accountId: id,
          serviceName: sub.serviceName,
          occurredOn: DateTime(2026, 10, 1),
          scheduledRenewalOn: DateTime(2026, 10, 1),
          amount: '30',
          currency: 'CNY',
          kind: SubscriptionExpenseKind.payment,
        ),
      ),
      isTrue,
    );
    expect(state.subscriptionExpenses, hasLength(2));
    expect(state.subscriptionExpenses.last.amount, '30');
    final recorded = await state.recordSubscriptionExpense(
      SubscriptionExpenseDraft(
        subscriptionId: sub.id,
        accountId: id,
        serviceName: sub.serviceName,
        occurredOn: DateTime(2026, 9, 3),
        amount: '5',
        currency: 'CNY',
        kind: SubscriptionExpenseKind.refund,
      ),
    );
    expect(recorded, isTrue);
    final afterRefund = _analysis(state);
    expect(_confirmedMonthlyAmounts(afterRefund), {
      '2026-09': '15',
      '2026-10': '30',
      '2026-11': '30',
      '2026-12': '30',
    });
    expect(
      afterRefund
          .currencyTotals(SubscriptionCostBasis.confirmed)
          .single
          .formattedAmount,
      '105',
    );
    expect(state.subscriptionExpenses, hasLength(3));

    // Deletion uses the real current date, so compare the same date before and
    // after deletion instead of treating the simulated year end as today.
    final deletionDate = subscriptionDateOnly(DateTime.now());
    final beforeDeletion = _analysis(state, today: deletionDate);
    final confirmedBeforeDeletion = _confirmedMonthlyAmounts(beforeDeletion);
    final archivedCycleCount = beforeDeletion
        .forBasis(SubscriptionCostBasis.confirmed)
        .where((line) => line.fromSchedule)
        .length;
    final retainedLedger = [
      for (final expense in state.subscriptionExpenses)
        <String, Object?>{
          ...expense.toEncryptedPayloadJson(),
          'accountId': expense.accountId,
          'subscriptionId': expense.subscriptionId,
        },
    ];
    expect(await state.deleteAccount(id), isTrue);
    expect(state.subscriptions, isEmpty);
    expect(state.subscriptionExpenses, hasLength(3 + archivedCycleCount));
    expect(
      state.subscriptionExpenses.every(
        (entry) =>
            entry.accountId == id &&
            state.trashSubscriptions.any(
              (t) => t.record.id == entry.subscriptionId,
            ),
      ),
      isTrue,
    );
    expect(
      state.subscriptionExpenses.every(
        (entry) => entry.accountLabel!.contains('owner@example.invalid'),
      ),
      isTrue,
    );
    expect([
      for (final expense in state.subscriptionExpenses)
        expense.toEncryptedPayloadJson(),
    ], containsAll(retainedLedger));
    expect(
      _confirmedMonthlyAmounts(_analysis(state, today: deletionDate)),
      confirmedBeforeDeletion,
    );
    expect(
      _analysis(
        state,
        today: deletionDate,
      ).forBasis(SubscriptionCostBasis.futureEstimate),
      isEmpty,
    );
  });

  test('无金额保留缺失，首次补金额入账；过去账期参与统计且只读查询不新增流水', () async {
    final state = await _state(FakeVaultStore());
    await state.addSubscription(_subscription(null, amount: null));
    expect(state.subscriptionExpenses, isEmpty);
    final missingAmountAnalysis = _analysis(state);
    expect(
      missingAmountAnalysis.forBasis(SubscriptionCostBasis.confirmed),
      hasLength(4),
    );
    expect(
      missingAmountAnalysis
          .cnyEstimate(SubscriptionCostBasis.confirmed)
          .missingAmountCount,
      4,
    );
    expect(
      missingAmountAnalysis.currencyTotals(SubscriptionCostBasis.confirmed),
      isEmpty,
    );
    expect(state.subscriptionExpenses, isEmpty);
    await state.updateSubscription(
      subscriptionId: state.subscriptions.single.id,
      draft: _subscription(null, amount: '12.0001'),
    );
    expect(state.subscriptionExpenses, hasLength(1));
    expect(state.subscriptionExpenses.single.amount, '12.0001');
    final ledger = state.subscriptionExpenses.single.toEncryptedPayloadJson();
    final analysis = _analysis(state);
    expect(analysis.forBasis(SubscriptionCostBasis.confirmed), hasLength(4));
    expect(_confirmedMonthlyAmounts(analysis), {
      '2026-09': '12.0001',
      '2026-10': '12.0001',
      '2026-11': '12.0001',
      '2026-12': '12.0001',
    });
    expect(
      analysis
          .currencyTotals(SubscriptionCostBasis.confirmed)
          .single
          .formattedAmount,
      '48.0004',
    );
    expect(state.subscriptionExpenses, hasLength(1));
    expect(state.subscriptionExpenses.single.toEncryptedPayloadJson(), ledger);
  });

  test('支付账号与订阅不匹配则零写；指定同一续费日期的付款不会在续费时重复', () async {
    final store = FakeVaultStore();
    final state = await _state(store);
    await state.addAccount(AccountDraft(platformName: '甲'));
    await state.addAccount(AccountDraft(platformName: '乙'));
    await state.addSubscription(_subscription(state.accounts.first.id));
    final sub = state.subscriptions.single;
    SubscriptionExpenseDraft payment(String id) => SubscriptionExpenseDraft(
      subscriptionId: sub.id,
      accountId: id,
      serviceName: sub.serviceName,
      occurredOn: DateTime(2026, 9, 3),
      amount: '20',
      currency: 'CNY',
      kind: SubscriptionExpenseKind.payment,
      scheduledRenewalOn: sub.nextRenewalOn,
    );
    expect(
      await state.recordSubscriptionExpense(payment(state.accounts.last.id)),
      isFalse,
    );
    expect(state.subscriptionExpenses, hasLength(1));
    expect(
      await state.recordSubscriptionExpense(payment(state.accounts.first.id)),
      isTrue,
    );
    expect(await state.markSubscriptionRenewed(sub), isTrue);
    expect(state.subscriptionExpenses, hasLength(2));
    expect(state.subscriptions.single.renewalHistory, hasLength(1));
  });

  test('schema 9只迁移录入费用，保留退款和明确付款；不伪造密码历史，重复打开不重复', () {
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(
        platformName: '平台',
        category: '工作',
        loginAccount: 'user@example.invalid',
        password: 'TEST',
      ),
      passwordStoredAtUtc: DateTime.utc(2026, 9, 1),
    );
    final subscription = SubscriptionRecord.fromDraft(
      id: 'subscription-1',
      draft: _subscription(account.id),
    );
    final old = VaultSnapshot(
      nextAccountId: 2,
      accounts: [account],
      nextSubscriptionId: 2,
      subscriptions: [subscription],
    );
    final payload = old.toEncryptedPayloadJson()..['schemaVersion'] = 9;
    final migrated = VaultSnapshot.fromEncryptedPayloadJson(payload);
    expect(migrated.subscriptionExpenses.single.amount, '20');
    expect(migrated.accounts.single.passwordChangeHistory, isEmpty);
    expect(
      migrated.accounts.single.passwordStoredAtUtc,
      account.passwordStoredAtUtc,
    );
    final roundTrip = VaultSnapshot.fromEncryptedPayloadJson(
      migrated.toEncryptedPayloadJson(),
    );
    expect(
      roundTrip.toEncryptedPayloadJson(),
      migrated.toEncryptedPayloadJson(),
    );
    final paid = SubscriptionExpenseRecord.fromDraft(
      id: 'expense-1',
      draft: SubscriptionExpenseDraft(
        subscriptionId: subscription.id,
        serviceName: '原支付',
        occurredOn: DateTime(2026, 9, 2),
        amount: '19',
        currency: 'CNY',
        kind: SubscriptionExpenseKind.payment,
      ),
    );
    final refunded = SubscriptionExpenseRecord.fromDraft(
      id: 'expense-2',
      draft: SubscriptionExpenseDraft(
        subscriptionId: subscription.id,
        serviceName: '原退款',
        occurredOn: DateTime(2026, 9, 3),
        amount: '2',
        currency: 'CNY',
        kind: SubscriptionExpenseKind.refund,
      ),
    );
    final existing =
        old
            .copyWith(nextExpenseId: 3, subscriptionExpenses: [paid, refunded])
            .toEncryptedPayloadJson()
          ..['schemaVersion'] = 9;
    final kept = VaultSnapshot.fromEncryptedPayloadJson(existing);
    expect(kept.subscriptionExpenses, hasLength(2));
    expect(kept.subscriptionExpenses.map((entry) => entry.amount), ['19', '2']);
    expect(
      kept.subscriptionExpenses.first.accountLabel,
      contains('user@example.invalid'),
    );
    expect(
      () => VaultSnapshot.fromEncryptedPayloadJson({
        ...payload,
        'schemaVersion': VaultSnapshot.currentSchemaVersion + 1,
      }),
      throwsA(isA<VaultUnsupportedSchemaVersionException>()),
    );
  });

  test('schema 10变更历史往返且无效UTC和未知账号引用安全拒绝', () {
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: '平台'),
      passwordChangeHistory: [
        PasswordChangeRecord(
          changedAtUtc: DateTime.utc(2026, 9, 3),
          previousStoredAtUtc: DateTime.utc(2026, 9, 1),
        ),
      ],
    );
    final snapshot = VaultSnapshot(nextAccountId: 2, accounts: [account]);
    expect(
      VaultSnapshot.fromEncryptedPayloadJson(
        snapshot.toEncryptedPayloadJson(),
      ).accounts.single.passwordChangeHistory.single.toJson(),
      account.passwordChangeHistory.single.toJson(),
    );
    final malformed = account.toEncryptedPayloadJson()
      ..['passwordChangeHistory'] = [
        {'changedAtUtc': '2026-09-03T00:00:00', 'previousStoredAtUtc': null},
      ];
    expect(
      () => VaultSnapshot.fromEncryptedPayloadJson({
        ...snapshot.toEncryptedPayloadJson(),
        'accounts': [malformed],
      }),
      throwsA(isA<VaultFormatException>()),
    );
    final orphan = SubscriptionExpenseRecord.fromDraft(
      id: 'expense-1',
      draft: SubscriptionExpenseDraft(
        subscriptionId: null,
        accountId: 'missing',
        serviceName: '孤立',
        occurredOn: DateTime(2026, 9, 3),
        amount: '1',
        currency: 'CNY',
        kind: SubscriptionExpenseKind.refund,
      ),
    );
    expect(
      () => snapshot.copyWith(nextExpenseId: 2, subscriptionExpenses: [orphan]),
      throwsA(isA<VaultFormatException>()),
    );
  });

  test('订阅新增与自动费用保存失败时均不提交', () async {
    final store = FakeVaultStore();
    final state = await _state(store);
    store.failSaves = true;
    expect(await state.addSubscription(_subscription(null)), isFalse);
    expect(state.subscriptions, isEmpty);
    expect(state.subscriptionExpenses, isEmpty);
    expect(store.snapshot.subscriptionExpenses, isEmpty);
  });
}
