import 'dart:async';

import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/notifications/reminder_scheduler.dart';
import 'package:account_subscription_manager/core/platform/notification_reliability.dart';
import 'package:account_subscription_manager/core/security/unlock_throttle.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_recovery.dart';
import 'package:account_subscription_manager/core/storage/layered_vault_store.dart';
import 'package:account_subscription_manager/core/storage/vault_recovery_journal.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_expense_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_cost_summary.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';

import 'support/fake_vault_store.dart';
import 'support/recording_reminder_scheduler.dart';

const _testMasterPassword = 'TEST-ONLY-MASTER-1234';

void main() {
  test('免费态只拦新增且删除后释放额度，已购态无限制', () async {
    final entitlement = ValueNotifier<ProductEntitlement>(
      ProductEntitlement.free,
    );
    addTearDown(entitlement.dispose);
    final state = AppState(
      vaultStore: FakeVaultStore(),
      entitlementListenable: entitlement,
    );
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_testMasterPassword);

    for (var index = 0; index < 5; index += 1) {
      expect(
        (await state.createSubscription(
          SubscriptionDraft(
            accountId: null,
            details: _subscriptionDetails(serviceName: '订阅$index'),
          ),
        )).saved,
        isTrue,
      );
    }
    final sixth = await state.createSubscription(
      SubscriptionDraft(
        accountId: null,
        details: _subscriptionDetails(serviceName: '第六项'),
      ),
    );
    expect(sixth.status, RecordCreationStatus.limitReached);
    expect(state.subscriptions, hasLength(5));

    expect(
      await state.deleteSubscription(state.subscriptions.first.id),
      isTrue,
    );
    expect(
      (await state.createSubscription(
        SubscriptionDraft(
          accountId: null,
          details: _subscriptionDetails(serviceName: '补位项'),
        ),
      )).saved,
      isTrue,
    );

    for (var index = 0; index < 15; index += 1) {
      expect(
        (await state.createAccount(
          AccountDraft(platformName: '账户$index'),
        )).saved,
        isTrue,
      );
    }
    final sixteenth = await state.createAccount(
      AccountDraft(platformName: '第十六项'),
    );
    expect(sixteenth.status, RecordCreationStatus.limitReached);
    expect(state.accounts, hasLength(15));

    entitlement.value = ProductEntitlement.purchased;
    expect(
      (await state.createAccount(AccountDraft(platformName: '完整版账户'))).saved,
      isTrue,
    );
    expect(
      (await state.createSubscription(
        SubscriptionDraft(
          accountId: null,
          details: _subscriptionDetails(serviceName: '完整版订阅'),
        ),
      )).saved,
      isTrue,
    );
  });

  test('免费态完整恢复20个订阅后只限制继续新增', () async {
    final purchased = ValueNotifier<ProductEntitlement>(
      ProductEntitlement.purchased,
    );
    addTearDown(purchased.dispose);
    final source = AppState(
      vaultStore: FakeVaultStore(),
      entitlementListenable: purchased,
    );
    addTearDown(source.dispose);
    await source.initialize();
    await source.createVault(_testMasterPassword);
    for (var index = 0; index < 20; index += 1) {
      expect(
        await source.addSubscription(
          SubscriptionDraft(
            accountId: null,
            details: _subscriptionDetails(serviceName: '备份订阅$index'),
          ),
        ),
        isTrue,
      );
    }
    final backup = await source.exportEncryptedBackup(
      backupMasterPassword: _testMasterPassword,
    );
    expect(backup, isNotNull);

    final free = ValueNotifier<ProductEntitlement>(ProductEntitlement.free);
    addTearDown(free.dispose);
    final target = AppState(
      vaultStore: FakeVaultStore(),
      entitlementListenable: free,
    );
    addTearDown(target.dispose);
    await target.initialize();
    await target.createVault(_testMasterPassword);
    expect(
      await target.restoreEncryptedBackup(
        bytes: backup!,
        backupMasterPassword: _testMasterPassword,
        currentMasterPassword: _testMasterPassword,
      ),
      isTrue,
    );
    expect(target.subscriptions, hasLength(20));
    expect(
      (await target.createSubscription(
        SubscriptionDraft(
          accountId: null,
          details: _subscriptionDetails(serviceName: '额外订阅'),
        ),
      )).status,
      RecordCreationStatus.limitReached,
    );
    expect(target.subscriptions, hasLength(20));
  });

  test('账号草稿规范化普通字段但不改写密码内容', () {
    final draft = AccountDraft(
      platformName: '  测试平台  ',
      category: '  AI工具  ',
      loginAccount: '  TEST-ONLY-LOGIN  ',
      username: '  中文用户名🙂  ',
      boundPhone: '   ',
      password: '  TEST-ONLY-NONSECRET  ',
    );

    expect(draft.platformName, '测试平台');
    expect(draft.category, 'AI工具');
    expect(draft.loginAccount, 'TEST-ONLY-LOGIN');
    expect(draft.username, '中文用户名🙂');
    expect(draft.boundPhone, isNull);
    expect(draft.password, '  TEST-ONLY-NONSECRET  ');
  });

  test('空白平台名称被拒绝且错误不回显输入', () {
    expect(
      () => AccountDraft(platformName: '   '),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          '平台或应用名称不能为空',
        ),
      ),
    );
  });

  test('同一平台允许多条加密记录，锁定后清空并可重新载入', () async {
    final store = FakeVaultStore();
    final state = AppState(vaultStore: store);
    addTearDown(state.dispose);

    await state.initialize();
    expect(state.vaultPhase, VaultPhase.needsSetup);
    expect(
      await state.createVault(_testMasterPassword),
      VaultActionResult.success,
    );
    expect(await state.addAccount(AccountDraft(platformName: '测试平台')), isTrue);
    expect(await state.addAccount(AccountDraft(platformName: '测试平台')), isTrue);

    expect(state.accounts, hasLength(2));
    expect(state.accounts.first.id, isNot(state.accounts.last.id));
    expect(
      () => state.accounts.add(state.accounts.first),
      throwsUnsupportedError,
    );

    state.lock();
    expect(state.vaultPhase, VaultPhase.locked);
    expect(state.accounts, isEmpty);

    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
    expect(state.accounts, hasLength(2));
  });

  test('加密写入失败时不提交内存记录', () async {
    final store = FakeVaultStore();
    final state = AppState(vaultStore: store);
    addTearDown(state.dispose);

    await state.initialize();
    await state.createVault(_testMasterPassword);
    store.failSaves = true;

    expect(
      await state.addAccount(
        AccountDraft(platformName: 'TEST-ONLY-WRITE-FAILURE'),
        initialSubscription: _subscriptionDetails(
          serviceName: 'TEST-ONLY-FAILED-SUBSCRIPTION',
        ),
      ),
      isFalse,
    );
    expect(state.accounts, isEmpty);
    expect(state.subscriptions, isEmpty);
    expect(state.errorMessage, '账号及订阅记录未能写入本机加密库。');
  });

  test('新增账号时可原子保存首条订阅并在解锁后恢复', () async {
    final store = FakeVaultStore();
    final state = AppState(vaultStore: store);
    addTearDown(state.dispose);

    await state.initialize();
    await state.createVault(_testMasterPassword);
    expect(
      await state.addAccount(
        AccountDraft(
          platformName: '中文平台',
          loginAccount: '中文账号_甲🙂',
          notes: '中文备注：换行\n全角标点，。！',
        ),
        initialSubscription: _subscriptionDetails(serviceName: '专业版订阅'),
      ),
      isTrue,
    );

    expect(store.saveCalls, 1);
    expect(state.accounts.single.loginAccount, '中文账号_甲🙂');
    expect(state.subscriptions.single.accountId, state.accounts.single.id);
    expect(state.subscriptions.single.serviceName, '专业版订阅');

    state.lock();
    expect(state.accounts, isEmpty);
    expect(state.subscriptions, isEmpty);
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
    expect(state.accounts.single.notes, '中文备注：换行\n全角标点，。！');
    expect(state.subscriptions.single.serviceName, '专业版订阅');
  });

  test('已有账号可后补多条订阅并编辑日期周期', () async {
    final store = FakeVaultStore();
    final state = AppState(vaultStore: store);
    addTearDown(state.dispose);

    await state.initialize();
    await state.createVault(_testMasterPassword);
    await state.addAccount(AccountDraft(platformName: '后补订阅平台'));
    final accountId = state.accounts.single.id;

    expect(
      await state.addSubscription(
        SubscriptionDraft(
          accountId: accountId,
          details: _subscriptionDetails(serviceName: '云存储'),
        ),
      ),
      isTrue,
    );
    expect(
      await state.addSubscription(
        SubscriptionDraft(
          accountId: accountId,
          details: _subscriptionDetails(serviceName: '音乐会员'),
        ),
      ),
      isTrue,
    );
    expect(state.subscriptions, hasLength(2));

    final first = state.subscriptions.first;
    expect(
      await state.updateSubscription(
        subscriptionId: first.id,
        draft: SubscriptionDraft(
          accountId: accountId,
          details: SubscriptionDetailsDraft(
            serviceName: '云存储高级版',
            firstSubscribedOn: DateTime(2026, 8, 1),
            nextRenewalOn: DateTime(2026, 11, 1),
            cycleCount: 3,
            cycleUnit: SubscriptionCycleUnit.month,
            amount: '19.9',
            currency: 'CNY',
          ),
        ),
      ),
      isTrue,
    );

    state.lock();
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
    final updated = state.subscriptions.firstWhere(
      (subscription) => subscription.id == first.id,
    );
    expect(updated.serviceName, '云存储高级版');
    expect(updated.cycleLabel, '每3个月');
    expect(formatSubscriptionDate(updated.nextRenewalOn), '2026-11-01');
  });

  test('不存在的账号不能建立孤儿订阅', () async {
    final state = AppState(vaultStore: FakeVaultStore());
    addTearDown(state.dispose);

    await state.initialize();
    await state.createVault(_testMasterPassword);
    expect(
      await state.addSubscription(
        SubscriptionDraft(
          accountId: 'account-missing',
          details: _subscriptionDetails(serviceName: '孤儿订阅'),
        ),
      ),
      isFalse,
    );
    expect(state.subscriptions, isEmpty);
    expect(state.errorMessage, '关联账号不存在，订阅记录未保存。');
  });

  test('没有账号时可新增和恢复独立订阅', () async {
    final store = FakeVaultStore();
    final state = AppState(vaultStore: store);
    addTearDown(state.dispose);

    await state.initialize();
    await state.createVault(_testMasterPassword);
    expect(state.accounts, isEmpty);
    expect(
      await state.addSubscription(
        SubscriptionDraft(
          accountId: null,
          details: _subscriptionDetails(serviceName: '独立云服务'),
        ),
      ),
      isTrue,
    );
    expect(state.subscriptions.single.accountId, isNull);

    state.lock();
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
    expect(state.accounts, isEmpty);
    expect(state.subscriptions.single.accountId, isNull);
    expect(state.subscriptions.single.serviceName, '独立云服务');
  });

  test('删除账号只清理其关联订阅并保留独立订阅', () async {
    final state = AppState(vaultStore: FakeVaultStore());
    addTearDown(state.dispose);

    await state.initialize();
    await state.createVault(_testMasterPassword);
    await state.addAccount(AccountDraft(platformName: '待删除平台'));
    final accountId = state.accounts.single.id;
    await state.addSubscription(
      SubscriptionDraft(
        accountId: accountId,
        details: _subscriptionDetails(serviceName: '关联订阅'),
      ),
    );
    await state.addSubscription(
      SubscriptionDraft(
        accountId: null,
        details: _subscriptionDetails(serviceName: '独立订阅'),
      ),
    );

    expect(await state.deleteAccount(accountId), isTrue);
    expect(state.accounts, isEmpty);
    expect(state.subscriptions, hasLength(1));
    expect(state.subscriptions.single.serviceName, '独立订阅');
    expect(state.subscriptions.single.accountId, isNull);
  });

  test('创建过程中锁定会保持忙碌并阻止第二次创建', () async {
    final gate = Completer<void>();
    final store = FakeVaultStore()..createGate = gate;
    final state = AppState(vaultStore: store);
    addTearDown(state.dispose);

    await state.initialize();
    final firstCreate = state.createVault(_testMasterPassword);
    await Future<void>.delayed(Duration.zero);
    expect(store.createCalls, 1);
    expect(state.isBusy, isTrue);

    state.lock();
    expect(state.vaultPhase, VaultPhase.needsSetup);
    expect(state.isBusy, isTrue);
    expect(
      await state.createVault('TEST-ONLY-SECOND-MASTER'),
      VaultActionResult.rejected,
    );
    expect(store.createCalls, 1);

    gate.complete();
    expect(await firstCreate, VaultActionResult.rejected);
    expect(state.vaultPhase, VaultPhase.locked);
    expect(state.isBusy, isFalse);
    expect(store.configured, isTrue);
  });

  test('保存过程中锁定立即清内存且已完成写入仍准确返回成功', () async {
    final store = FakeVaultStore();
    final state = AppState(vaultStore: store);
    addTearDown(state.dispose);

    await state.initialize();
    await state.createVault(_testMasterPassword);
    final gate = Completer<void>();
    store.saveGate = gate;

    final save = state.addAccount(
      AccountDraft(platformName: 'TEST-ONLY-IN-FLIGHT-SAVE'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(store.saveCalls, 1);
    expect(state.isBusy, isTrue);

    state.lock();
    expect(state.vaultPhase, VaultPhase.locked);
    expect(state.accounts, isEmpty);
    expect(state.isBusy, isTrue);
    expect(await state.unlock(_testMasterPassword), VaultActionResult.rejected);
    expect(store.unlockCalls, 0);

    gate.complete();
    // 写入 Future 正常完成说明主快照已经持久化；锁定只阻止旧会话
    // 回填内存与提醒，不能把 durable success 误报成零写入。
    expect(await save, isTrue);
    expect(state.isBusy, isFalse);
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
    expect(state.accounts.single.platformName, 'TEST-ONLY-IN-FLIGHT-SAVE');
  });

  test('从旧一代恢复时提供明确警告且可确认关闭', () async {
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
      recoveredFromFallback: true,
    );
    final state = AppState(vaultStore: store);
    addTearDown(state.dispose);

    await state.initialize();
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
    expect(state.warningMessage, '已从上一份有效数据恢复，最近一次更改可能未保留。');

    state.dismissWarning();
    expect(state.warningMessage, isNull);
  });

  test('账号搜索包含可选字段但不会匹配密码', () {
    final record = AccountRecord.fromDraft(
      id: 'account-test',
      draft: AccountDraft(
        platformName: '测试平台',
        loginAccount: 'TEST-ONLY-LOGIN',
        username: '中文用户名-SENTINEL',
        password: 'TEST-ONLY-NONSECRET',
        notes: 'TEST-ONLY-NOTES',
      ),
    );

    expect(record.matches('test-only-login'), isTrue);
    expect(record.matches('中文用户名'), isTrue);
    expect(record.matches('test-only-notes'), isTrue);
    expect(record.matches('test-only-nonsecret'), isFalse);
  });

  test('账号编辑可分别保留、替换和明确清除密码', () async {
    final state = AppState(vaultStore: FakeVaultStore());
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_testMasterPassword);
    await state.addAccount(
      AccountDraft(
        platformName: '密码编辑平台',
        password: 'TEST-ONLY-ORIGINAL-PASSWORD',
      ),
    );
    final accountId = state.accounts.single.id;
    expect(
      state.accounts.single.passwordSyncState,
      PasswordSyncState.needsReview,
    );
    expect(state.accounts.single.passwordStoredAtUtc, isNotNull);
    expect(await state.confirmPasswordCurrent(accountId), isTrue);
    final storedAt = state.accounts.single.passwordStoredAtUtc;
    final verifiedAt = state.accounts.single.passwordVerifiedAtUtc;
    expect(state.accounts.single.passwordSyncState, PasswordSyncState.verified);
    expect(verifiedAt, isNotNull);

    expect(
      await state.updateAccount(
        accountId: accountId,
        draft: AccountDraft(
          platformName: '保留密码后的平台',
          password: 'TEST-ONLY-SHOULD-NOT-REPLACE',
        ),
        passwordMode: AccountPasswordUpdateMode.preserve,
      ),
      isTrue,
    );
    expect(state.accounts.single.password, 'TEST-ONLY-ORIGINAL-PASSWORD');
    expect(state.accounts.single.passwordStoredAtUtc, storedAt);
    expect(state.accounts.single.passwordVerifiedAtUtc, verifiedAt);
    expect(state.accounts.single.passwordSyncState, PasswordSyncState.verified);

    expect(
      await state.updateAccount(
        accountId: accountId,
        draft: AccountDraft(
          platformName: '替换密码后的平台',
          password: 'TEST-ONLY-REPLACED-PASSWORD',
        ),
        passwordMode: AccountPasswordUpdateMode.replace,
      ),
      isTrue,
    );
    expect(state.accounts.single.password, 'TEST-ONLY-REPLACED-PASSWORD');
    expect(
      state.accounts.single.passwordSyncState,
      PasswordSyncState.needsReview,
    );
    expect(state.accounts.single.passwordStoredAtUtc, isNot(storedAt));
    expect(state.accounts.single.passwordVerifiedAtUtc, verifiedAt);
    expect(await state.setPasswordReviewInterval(accountId, 180), isTrue);
    expect(state.accounts.single.passwordReviewIntervalDays, 180);
    expect(await state.markPlatformPasswordChanged(accountId), isTrue);
    expect(
      state.accounts.single.passwordSyncState,
      PasswordSyncState.externalChangePendingSync,
    );
    expect(state.accounts.single.platformPasswordChangedAtUtc, isNotNull);
    expect(await state.snoozePasswordReview(accountId, 7), isTrue);
    expect(state.accounts.single.passwordReviewSnoozedUntilUtc, isNotNull);
    expect(await state.markPasswordNeedsReview(accountId), isTrue);
    expect(
      state.accounts.single.passwordSyncState,
      PasswordSyncState.needsReview,
    );
    expect(state.accounts.single.passwordReviewSnoozedUntilUtc, isNull);
    expect(await state.confirmPasswordCurrent(accountId), isTrue);
    expect(state.accounts.single.passwordSyncState, PasswordSyncState.verified);

    expect(
      await state.updateAccount(
        accountId: accountId,
        draft: AccountDraft(platformName: '清除密码后的平台'),
        passwordMode: AccountPasswordUpdateMode.clear,
      ),
      isTrue,
    );
    expect(state.accounts.single.password, isNull);
    expect(state.accounts.single.passwordStoredAtUtc, isNull);
    expect(state.accounts.single.passwordSyncState, PasswordSyncState.unknown);
    expect(state.accounts.single.passwordVerifiedAtUtc, isNull);
    expect(state.accounts.single.passwordReviewIntervalDays, isNull);
  });

  test('续费可原子保存确认支出且软删除保留恢复所需的费用关联', () async {
    final store = FakeVaultStore();
    final state = AppState(vaultStore: store);
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_testMasterPassword);
    expect(
      await state.addSubscription(
        SubscriptionDraft(
          accountId: null,
          details: _subscriptionDetails(
            serviceName: '费用快照订阅',
          ).withExpenseCategory('影音娱乐'),
        ),
      ),
      isTrue,
    );
    final subscription = state.subscriptions.single;
    expect(
      await state.markSubscriptionRenewed(
        subscription,
        expense: SubscriptionExpenseDraft(
          subscriptionId: subscription.id,
          serviceName: subscription.serviceName,
          occurredOn: DateTime(2026, 9, 2),
          amount: '19.9',
          currency: 'CNY',
          kind: SubscriptionExpenseKind.payment,
          expenseCategory: '影音娱乐',
        ),
      ),
      isTrue,
    );

    expect(state.subscriptions.single.nextRenewalOn, DateTime(2026, 10, 1));
    expect(state.subscriptionExpenses, hasLength(2));
    final expense = state.subscriptionExpenses.last;
    expect(expense.subscriptionId, subscription.id);
    expect(expense.scheduledRenewalOn, DateTime(2026, 9, 1));
    expect(expense.serviceName, '费用快照订阅');
    expect(expense.amount, '19.9');
    expect(expense.expenseCategory, '影音娱乐');
    expect(store.snapshot.subscriptionExpenses.last.id, expense.id);

    expect(await state.deleteSubscription(subscription.id), isTrue);
    expect(state.subscriptions, isEmpty);
    final retainedExpense = state.subscriptionExpenses.singleWhere(
      (record) => record.id == expense.id,
    );
    expect(retainedExpense.subscriptionId, subscription.id);
    expect(retainedExpense.serviceName, '费用快照订阅');
    expect(retainedExpense.amount, '19.9');
    expect(
      store.snapshot.subscriptionExpenses
          .singleWhere((record) => record.id == expense.id)
          .subscriptionId,
      subscription.id,
    );
    expect(state.trashSubscriptions.single.record.id, subscription.id);
  });

  test('删除订阅保留逐月费用和退款，移除未来预计并持久保存', () async {
    final today = subscriptionDateOnly(DateTime.now());
    final firstMonth = DateTime(today.year, today.month - 3);
    final refundMonth = DateTime(today.year, today.month - 1, 15);
    final store = FakeVaultStore();
    final state = AppState(vaultStore: store);
    addTearDown(state.dispose);
    await state.initialize();
    expect(
      await state.createVault(_testMasterPassword),
      VaultActionResult.success,
    );
    expect(
      await state.addSubscription(
        SubscriptionDraft(
          accountId: null,
          details: SubscriptionDetailsDraft(
            serviceName: '删除后保留的月费',
            amount: '25.25',
            currency: 'CNY',
            firstSubscribedOn: firstMonth,
            nextRenewalOn: DateTime(today.year, today.month + 1),
          ),
        ),
      ),
      isTrue,
    );
    final subscriptionId = state.subscriptions.single.id;
    expect(
      await state.recordSubscriptionExpense(
        SubscriptionExpenseDraft(
          subscriptionId: subscriptionId,
          serviceName: '删除后保留的月费',
          occurredOn: refundMonth,
          amount: '5.25',
          currency: 'CNY',
          kind: SubscriptionExpenseKind.refund,
        ),
      ),
      isTrue,
    );
    final before = _previousThreeMonthCosts(state, today);
    expect(before, {
      _relativeMonthKey(today, -3): {'CNY': '25.25'},
      _relativeMonthKey(today, -2): {'CNY': '25.25'},
      _relativeMonthKey(today, -1): {'CNY': '20'},
    });
    expect(_nextThreeMonthForecast(state, today), isNotEmpty);
    final refundId = state.subscriptionExpenses
        .singleWhere(
          (expense) => expense.kind == SubscriptionExpenseKind.refund,
        )
        .id;

    expect(await state.deleteSubscription(subscriptionId), isTrue);
    expect(state.subscriptions, isEmpty);
    expect(_previousThreeMonthCosts(state, today), before);
    expect(_nextThreeMonthForecast(state, today), isEmpty);
    expect(
      state.subscriptionExpenses.every(
        (expense) => expense.subscriptionId == subscriptionId,
      ),
      isTrue,
    );
    final refund = state.subscriptionExpenses.singleWhere(
      (expense) => expense.id == refundId,
    );
    expect(refund.kind, SubscriptionExpenseKind.refund);
    expect(refund.amount, '5.25');
    expect(refund.occurredOn, refundMonth);
    expect(
      state.subscriptionExpenses.map((expense) => expense.id).toSet().length,
      state.subscriptionExpenses.length,
    );

    state.lock();
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
    expect(state.subscriptions, isEmpty);
    expect(_previousThreeMonthCosts(state, today), before);
    expect(_nextThreeMonthForecast(state, today), isEmpty);
  });

  test('删除账号归档其月季订阅费用，其他账号订阅和未来预计保留', () async {
    final today = subscriptionDateOnly(DateTime.now());
    final firstMonth = DateTime(today.year, today.month - 3);
    final store = FakeVaultStore();
    final state = AppState(vaultStore: store);
    addTearDown(state.dispose);
    await state.initialize();
    expect(
      await state.createVault(_testMasterPassword),
      VaultActionResult.success,
    );
    expect(
      await state.addAccount(
        AccountDraft(
          platformName: '历史费用账号',
          category: 'Work',
          loginAccount: 'archive-account@example.invalid',
        ),
      ),
      isTrue,
    );
    final removedAccountId = state.accounts.single.id;
    expect(await state.addAccount(AccountDraft(platformName: '保留账号')), isTrue);
    final retainedAccountId = state.accounts.last.id;
    for (final (accountId, service, currency, amount, cycleCount) in [
      (removedAccountId, '被删月费', 'CNY', '30', 1),
      (removedAccountId, '被删季费', 'USD', '90', 3),
      (retainedAccountId, '保留月费', 'CNY', '7', 1),
    ]) {
      expect(
        await state.addSubscription(
          SubscriptionDraft(
            accountId: accountId,
            details: SubscriptionDetailsDraft(
              serviceName: service,
              amount: amount,
              currency: currency,
              cycleCount: cycleCount,
              firstSubscribedOn: firstMonth,
              nextRenewalOn: cycleCount == 3
                  ? DateTime(today.year, today.month)
                  : DateTime(today.year, today.month + 1),
            ),
          ),
        ),
        isTrue,
      );
    }
    final removedIds = state.subscriptions
        .where((subscription) => subscription.accountId == removedAccountId)
        .map((subscription) => subscription.id)
        .toSet();
    final retainedSubscription = state.subscriptions.singleWhere(
      (subscription) => subscription.accountId == retainedAccountId,
    );
    final retainedPayload = retainedSubscription.toEncryptedPayloadJson();
    final before = _previousThreeMonthCosts(state, today);
    expect(before, {
      _relativeMonthKey(today, -3): {'CNY': '37', 'USD': '90'},
      _relativeMonthKey(today, -2): {'CNY': '37'},
      _relativeMonthKey(today, -1): {'CNY': '37'},
    });
    expect(
      _nextThreeMonthForecast(
        state,
        today,
      ).any((line) => removedIds.contains(line.subscriptionId)),
      isTrue,
    );

    expect(await state.deleteAccount(removedAccountId), isTrue);
    expect(state.accounts.map((account) => account.id), [retainedAccountId]);
    expect(
      state.subscriptions.single.toEncryptedPayloadJson(),
      retainedPayload,
    );
    expect(_previousThreeMonthCosts(state, today), before);
    final afterForecast = _nextThreeMonthForecast(state, today);
    expect(afterForecast, isNotEmpty);
    expect(
      afterForecast.every(
        (line) => line.subscriptionId == retainedSubscription.id,
      ),
      isTrue,
    );
    final archived = state.subscriptionExpenses
        .where(
          (expense) =>
              expense.serviceName == '被删月费' || expense.serviceName == '被删季费',
        )
        .toList();
    expect(archived.length, greaterThanOrEqualTo(4));
    expect(
      archived.every(
        (expense) =>
            state.trashSubscriptions.any(
              (t) => t.record.id == expense.subscriptionId,
            ) &&
            state.trashAccounts.any((t) => t.record.id == expense.accountId),
      ),
      isTrue,
    );
    expect(
      archived.every(
        (expense) =>
            expense.accountLabel?.contains('archive-account@example.invalid') ??
            false,
      ),
      isTrue,
    );

    state.lock();
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
    expect(state.accounts.map((account) => account.id), [retainedAccountId]);
    expect(
      state.subscriptions.single.toEncryptedPayloadJson(),
      retainedPayload,
    );
    expect(_previousThreeMonthCosts(state, today), before);
  });

  test('删除归档写盘失败时账号订阅费用和费用编号均保持原样', () async {
    for (final removeAccount in [false, true]) {
      final today = subscriptionDateOnly(DateTime.now());
      final store = FakeVaultStore();
      final state = AppState(vaultStore: store);
      addTearDown(state.dispose);
      await state.initialize();
      expect(
        await state.createVault(_testMasterPassword),
        VaultActionResult.success,
      );
      expect(
        await state.addAccount(AccountDraft(platformName: '删除失败保留账号')),
        isTrue,
      );
      final accountId = state.accounts.single.id;
      expect(
        await state.addSubscription(
          SubscriptionDraft(
            accountId: accountId,
            details: SubscriptionDetailsDraft(
              serviceName: '删除失败保留月费',
              amount: '18.5',
              currency: 'CNY',
              firstSubscribedOn: DateTime(today.year, today.month - 3),
              nextRenewalOn: DateTime(today.year, today.month + 1),
            ),
          ),
        ),
        isTrue,
      );
      final subscriptionId = state.subscriptions.single.id;
      final beforeSubscriptions = state.subscriptions
          .map((subscription) => subscription.toEncryptedPayloadJson())
          .toList();
      final beforeExpenses = state.subscriptionExpenses
          .map((expense) => expense.toEncryptedPayloadJson())
          .toList();
      final beforeNextExpenseId = store.snapshot.nextExpenseId;
      final beforeCosts = _previousThreeMonthCosts(state, today);
      final beforeFutureCount = _nextThreeMonthForecast(state, today).length;
      store.failSaves = true;

      expect(
        removeAccount
            ? await state.deleteAccount(accountId)
            : await state.deleteSubscription(subscriptionId),
        isFalse,
      );
      expect(state.accounts.map((account) => account.id), [accountId]);
      expect(
        state.subscriptions.map(
          (subscription) => subscription.toEncryptedPayloadJson(),
        ),
        beforeSubscriptions,
      );
      expect(
        state.subscriptionExpenses.map(
          (expense) => expense.toEncryptedPayloadJson(),
        ),
        beforeExpenses,
      );
      expect(
        store.snapshot.subscriptions.map(
          (subscription) => subscription.toEncryptedPayloadJson(),
        ),
        beforeSubscriptions,
      );
      expect(
        store.snapshot.subscriptionExpenses.map(
          (expense) => expense.toEncryptedPayloadJson(),
        ),
        beforeExpenses,
      );
      expect(store.snapshot.nextExpenseId, beforeNextExpenseId);
      expect(_previousThreeMonthCosts(state, today), beforeCosts);
      expect(
        _nextThreeMonthForecast(state, today),
        hasLength(beforeFutureCount),
      );

      store.failSaves = false;
      state.lock();
      expect(
        await state.unlock(_testMasterPassword),
        VaultActionResult.success,
      );
      expect(state.accounts.map((account) => account.id), [accountId]);
      expect(
        state.subscriptions.map(
          (subscription) => subscription.toEncryptedPayloadJson(),
        ),
        beforeSubscriptions,
      );
      expect(
        state.subscriptionExpenses.map(
          (expense) => expense.toEncryptedPayloadJson(),
        ),
        beforeExpenses,
      );
      expect(store.snapshot.nextExpenseId, beforeNextExpenseId);
    }
  });

  test('最近查看加密保存且删除账号会原子级联订阅和最近记录', () async {
    final state = AppState(vaultStore: FakeVaultStore());
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_testMasterPassword);
    await state.addAccount(AccountDraft(platformName: '账号甲'));
    await state.addAccount(AccountDraft(platformName: '账号乙'));
    final firstId = state.accounts.first.id;
    final secondId = state.accounts.last.id;
    await state.addSubscription(
      SubscriptionDraft(
        accountId: firstId,
        details: _subscriptionDetails(serviceName: '账号甲订阅'),
      ),
    );
    await state.markAccountViewed(secondId);
    await state.markAccountViewed(firstId);
    expect(state.recentAccounts.map((account) => account.id), <String>[
      firstId,
      secondId,
    ]);

    expect(await state.deleteAccount(firstId), isTrue);
    expect(state.accounts.single.id, secondId);
    expect(state.subscriptions, isEmpty);
    expect(state.recentAccounts.single.id, secondId);

    state.lock();
    await state.unlock(_testMasterPassword);
    expect(state.accounts.single.id, secondId);
    expect(state.recentAccounts.single.id, secondId);
  });

  test('账号删除写盘失败时账号订阅和最近查看均原子回滚', () async {
    final store = FakeVaultStore();
    final state = AppState(vaultStore: store);
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_testMasterPassword);
    await state.addAccount(AccountDraft(platformName: '待删账号'));
    await state.addAccount(AccountDraft(platformName: '保留账号'));
    final deletedId = state.accounts.first.id;
    final retainedId = state.accounts.last.id;
    await state.addSubscription(
      SubscriptionDraft(
        accountId: deletedId,
        details: _subscriptionDetails(serviceName: '不可半删订阅'),
      ),
    );
    await state.markAccountViewed(retainedId);
    await state.markAccountViewed(deletedId);

    final beforeAccountIds = state.accounts
        .map((account) => account.id)
        .toList(growable: false);
    final beforeSubscriptionIds = state.subscriptions
        .map((subscription) => subscription.id)
        .toList(growable: false);
    final beforeRecentIds = state.recentAccounts
        .map((account) => account.id)
        .toList(growable: false);
    store.failSaves = true;

    expect(await state.deleteAccount(deletedId), isFalse);
    expect(
      state.accounts.map((account) => account.id),
      orderedEquals(beforeAccountIds),
    );
    expect(
      state.subscriptions.map((subscription) => subscription.id),
      orderedEquals(beforeSubscriptionIds),
    );
    expect(
      state.recentAccounts.map((account) => account.id),
      orderedEquals(beforeRecentIds),
    );
    expect(state.subscriptions.single.accountId, deletedId);
    expect(state.errorMessage, '移入回收站失败，原记录保持不变。');

    store.failSaves = false;
    state.lock();
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
    expect(
      state.accounts.map((account) => account.id),
      orderedEquals(beforeAccountIds),
    );
    expect(
      state.subscriptions.map((subscription) => subscription.id),
      orderedEquals(beforeSubscriptionIds),
    );
    expect(
      state.recentAccounts.map((account) => account.id),
      orderedEquals(beforeRecentIds),
    );
  });

  test('最近查看重复账号会前置且超过十条只保留最新十条', () async {
    final state = AppState(vaultStore: FakeVaultStore());
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_testMasterPassword);
    for (var index = 1; index <= 12; index += 1) {
      expect(
        await state.addAccount(AccountDraft(platformName: '账号$index')),
        isTrue,
      );
    }
    final accountIds = state.accounts
        .map((account) => account.id)
        .toList(growable: false);
    for (final accountId in accountIds) {
      expect(await state.markAccountViewed(accountId), isTrue);
    }

    expect(state.recentAccounts, hasLength(10));
    expect(
      state.recentAccounts.map((account) => account.id),
      orderedEquals(accountIds.reversed.take(10)),
    );

    final repeatedId = accountIds[6];
    expect(await state.markAccountViewed(repeatedId), isTrue);
    final afterRepeat = state.recentAccounts
        .map((account) => account.id)
        .toList(growable: false);
    expect(afterRepeat, hasLength(10));
    expect(afterRepeat.first, repeatedId);
    expect(afterRepeat.where((id) => id == repeatedId), hasLength(1));

    state.lock();
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
    expect(
      state.recentAccounts.map((account) => account.id),
      orderedEquals(afterRepeat),
    );
  });

  test('加密偏好与备份可验证预览并原子恢复且保留当前主密码', () async {
    final state = AppState(vaultStore: FakeVaultStore());
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_testMasterPassword);
    await state.addAccount(AccountDraft(platformName: '备份内账号'));
    expect(
      await state.updatePreferences(
        const VaultPreferences(
          autoLockSeconds: 300,
          defaultReminderDaysBefore: 15,
          defaultCurrency: 'USD',
        ),
      ),
      isTrue,
    );
    final backup = await state.exportEncryptedBackup(
      backupMasterPassword: _testMasterPassword,
    );
    expect(backup, isNotNull);

    await state.addAccount(AccountDraft(platformName: '恢复前新增账号'));
    expect(state.accounts, hasLength(2));
    final preview = await state.inspectEncryptedBackup(
      bytes: backup!,
      backupMasterPassword: _testMasterPassword,
    );
    expect(preview?.accountCount, 1);
    expect(preview?.subscriptionCount, 0);
    expect(preview?.formatVersion, 2);
    expect(preview?.sourceSchemaVersion, VaultSnapshot.currentSchemaVersion);

    expect(
      await state.restoreEncryptedBackup(
        bytes: backup,
        backupMasterPassword: _testMasterPassword,
        currentMasterPassword: _testMasterPassword,
      ),
      isTrue,
    );
    expect(state.accounts.single.platformName, '备份内账号');
    expect(state.preferences.autoLockSeconds, 300);
    expect(state.preferences.defaultReminderDaysBefore, 15);
    expect(state.preferences.defaultCurrency, 'USD');

    state.lock();
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
    expect(state.accounts.single.platformName, '备份内账号');
  });

  test('快速解锁需先验证主密码，启用后可锁定并重新打开同一加密库', () async {
    final store = FakeVaultStore();
    final state = AppState(vaultStore: store);
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_testMasterPassword);
    await state.addAccount(AccountDraft(platformName: '快速解锁账号'));

    expect(await state.enableQuickUnlock('TEST-ONLY-WRONG-1234'), isFalse);
    expect(state.quickUnlockEnabled, isFalse);
    expect(await state.enableQuickUnlock(_testMasterPassword), isTrue);
    expect(state.quickUnlockEnabled, isTrue);

    state.lock();
    expect(state.accounts, isEmpty);
    expect(await state.unlockWithQuickUnlock(), VaultActionResult.success);
    expect(state.accounts.single.platformName, '快速解锁账号');
  });

  test('通知开启会按偏好重排，关闭及关闭状态重开都会清空提醒', () async {
    final store = FakeVaultStore();
    final scheduler = RecordingReminderScheduler();
    var state = AppState(vaultStore: store, reminderScheduler: scheduler);
    addTearDown(() => state.dispose());

    await state.initialize();
    await state.createVault(_testMasterPassword);
    await _drainEventQueue();
    scheduler.reset();
    await state.addAccount(
      AccountDraft(platformName: '通知开关平台'),
      initialSubscription: _subscriptionDetails(serviceName: '通知开关订阅'),
    );
    final subscriptionId = state.subscriptions.single.id;

    expect(await state.requestNotificationPermission(), isTrue);
    expect(scheduler.requestPermissionCalls, 1);
    expect(
      await state.updatePreferences(
        state.preferences.copyWith(
          notificationsEnabled: true,
          defaultReminderTimeMinutes: 10 * 60 + 15,
        ),
      ),
      isTrue,
    );
    expect(scheduler.rescheduleCalls, hasLength(1));
    expect(scheduler.rescheduleCalls.single.subscriptionIds, <String>[
      subscriptionId,
    ]);
    expect(scheduler.rescheduleCalls.single.reminderTimeMinutes, 10 * 60 + 15);
    expect(scheduler.rescheduleCalls.single.secondReminderTimeMinutes, 17 * 60);

    scheduler.reset();
    expect(
      await state.updatePreferences(
        state.preferences.copyWith(notificationsEnabled: false),
      ),
      isTrue,
    );
    expect(scheduler.cancelAllCalls, 1);
    expect(scheduler.rescheduleCalls, isEmpty);
    expect(store.snapshot.preferences.notificationsEnabled, isFalse);

    state.dispose();
    scheduler.reset();
    state = AppState(vaultStore: store, reminderScheduler: scheduler);
    await state.initialize();
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
    await _drainEventQueue();
    expect(state.preferences.notificationsEnabled, isFalse);
    expect(scheduler.cancelAllCalls, 1);
  });

  test('诱饵库会话不会清理或重排真实库设备提醒', () async {
    final store = _ScopedPasswordVaultStore(
      primarySnapshot: VaultSnapshot.empty().copyWith(
        preferences: const VaultPreferences(notificationsEnabled: true),
      ),
      decoySnapshot: VaultSnapshot.empty(),
    );
    final scheduler = RecordingReminderScheduler();
    final reliabilityService = MemoryNotificationReliabilityService(
      status: PlatformNotificationReliabilityStatus(
        applicationNotificationsEnabled: true,
        reminderChannelEnabled: true,
        batteryOptimizationExempt: true,
        exactAlarmsAllowed: true,
        manufacturer: 'Google',
        model: 'TEST-ONLY',
        androidApiLevel: 35,
        lastRecovery: ReminderRecoveryRecord(
          occurredAtUtc: DateTime.utc(2026, 8, 29, 15),
          trigger: 'android.intent.action.TIMEZONE_CHANGED',
          result: ReminderRecoveryResult.rescheduled,
        ),
      ),
    );
    final state = AppState(
      vaultStore: store,
      reminderScheduler: scheduler,
      notificationReliabilityService: reliabilityService,
      unlockThrottleController: UnlockThrottleController(
        MemoryUnlockThrottleStore(),
        MemoryUnlockThrottleClock(),
      ),
    );
    addTearDown(state.dispose);

    await state.initialize();
    expect(await state.unlock(store.decoyPassword), VaultActionResult.success);
    await _drainEventQueue();
    expect(state.canManageSecurity, isFalse);
    expect(scheduler.cancelAllCalls, 0);
    expect(scheduler.rescheduleCalls, isEmpty);

    expect(
      await state.updatePreferences(
        state.preferences.copyWith(notificationsEnabled: true),
      ),
      isTrue,
    );
    expect(scheduler.cancelAllCalls, 0);
    expect(scheduler.rescheduleCalls, isEmpty);

    expect(
      await state.setNotificationsEnabled(false),
      NotificationSettingResult.disabled,
    );
    expect(
      await state.setNotificationsEnabled(true),
      NotificationSettingResult.enabled,
    );
    expect(await state.refreshReminderScheduleForReliability(), isFalse);
    expect(await state.refreshReminderScheduleForSystemTimeRecovery(), isFalse);
    expect(reliabilityService.inspectCalls, 0);
    expect(scheduler.cancelAllCalls, 0);
    expect(scheduler.rescheduleCalls, isEmpty);

    state.lock();
    scheduler.reset();
    expect(
      await state.unlock(store.primaryPassword),
      VaultActionResult.success,
    );
    await _drainEventQueue();
    expect(state.canManageSecurity, isTrue);
    expect(scheduler.rescheduleCalls, hasLength(1));
    expect(scheduler.cancelAllCalls, 0);

    scheduler.reset();
    expect(await state.refreshReminderScheduleForSystemTimeRecovery(), isTrue);
    expect(scheduler.rescheduleCalls, hasLength(1));
    expect(await state.refreshReminderScheduleForSystemTimeRecovery(), isFalse);
    expect(scheduler.rescheduleCalls, hasLength(1));
  });

  test('业务写入忙碌时不消费系统时间恢复记录并在安全机会重试', () async {
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
      snapshot: VaultSnapshot.empty().copyWith(
        preferences: const VaultPreferences(notificationsEnabled: true),
      ),
    );
    final scheduler = RecordingReminderScheduler();
    final reliabilityService = MemoryNotificationReliabilityService(
      status: PlatformNotificationReliabilityStatus(
        applicationNotificationsEnabled: true,
        reminderChannelEnabled: true,
        batteryOptimizationExempt: true,
        exactAlarmsAllowed: true,
        manufacturer: 'Google',
        model: 'TEST-ONLY',
        androidApiLevel: 35,
        lastRecovery: ReminderRecoveryRecord(
          occurredAtUtc: DateTime.utc(2026, 8, 29, 16),
          trigger: 'android.intent.action.TIME_SET',
          result: ReminderRecoveryResult.rescheduled,
        ),
      ),
    );
    final state = AppState(
      vaultStore: store,
      reminderScheduler: scheduler,
      notificationReliabilityService: reliabilityService,
    );
    addTearDown(state.dispose);
    await state.initialize();
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
    await _drainEventQueue();
    scheduler.reset();

    final gate = Completer<void>();
    store.saveGate = gate;
    final save = state.addAccount(
      AccountDraft(platformName: 'TEST-ONLY-BUSY-RECOVERY'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(state.isBusy, isTrue);
    expect(await state.refreshReminderScheduleForSystemTimeRecovery(), isFalse);
    expect(reliabilityService.inspectCalls, 0);

    gate.complete();
    expect(await save, isTrue);
    await _drainEventQueue();
    scheduler.reset();
    expect(await state.refreshReminderScheduleForSystemTimeRecovery(), isTrue);
    expect(reliabilityService.inspectCalls, 1);
    expect(scheduler.rescheduleCalls, hasLength(1));
  });

  test('提醒调度失败不回滚已加密保存的订阅并显示降级警告', () async {
    final store = FakeVaultStore();
    final scheduler = RecordingReminderScheduler();
    var state = AppState(vaultStore: store, reminderScheduler: scheduler);
    addTearDown(() => state.dispose());

    await state.initialize();
    await state.createVault(_testMasterPassword);
    await _drainEventQueue();
    await state.addAccount(
      AccountDraft(platformName: '提醒失败平台'),
      initialSubscription: _subscriptionDetails(serviceName: '已有订阅'),
    );
    expect(
      await state.updatePreferences(
        state.preferences.copyWith(notificationsEnabled: true),
      ),
      isTrue,
    );

    scheduler.reset();
    scheduler.failOn = ReminderSchedulerOperation.rescheduleAll;
    expect(
      await state.addSubscription(
        SubscriptionDraft(
          accountId: state.accounts.single.id,
          details: _subscriptionDetails(serviceName: '调度失败仍保存的订阅'),
        ),
      ),
      isTrue,
    );
    expect(state.subscriptions, hasLength(2));
    expect(store.snapshot.subscriptions, hasLength(2));
    expect(scheduler.rescheduleCalls, hasLength(1));
    expect(state.warningMessage, '记录已安全保存，但系统提醒同步失败；应用内日期仍为准。');

    state.dispose();
    scheduler.reset();
    state = AppState(vaultStore: store, reminderScheduler: scheduler);
    await state.initialize();
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
    await _drainEventQueue();
    expect(
      state.subscriptions.map((subscription) => subscription.serviceName),
      contains('调度失败仍保存的订阅'),
    );
  });

  test('续费延期取消恢复四项快捷操作每次重开后均保持', () async {
    final store = FakeVaultStore();
    var state = AppState(
      vaultStore: store,
      reminderScheduler: const NoopReminderScheduler(),
    );
    addTearDown(() => state.dispose());

    Future<void> reopen() async {
      state.dispose();
      state = AppState(
        vaultStore: store,
        reminderScheduler: const NoopReminderScheduler(),
      );
      await state.initialize();
      expect(
        await state.unlock(_testMasterPassword),
        VaultActionResult.success,
      );
      await _drainEventQueue();
    }

    await state.initialize();
    await state.createVault(_testMasterPassword);
    await state.addAccount(
      AccountDraft(platformName: '四项操作平台'),
      initialSubscription: _subscriptionDetails(serviceName: '四项操作订阅'),
    );

    expect(
      await state.markSubscriptionRenewed(state.subscriptions.single),
      isTrue,
    );
    await reopen();
    expect(state.subscriptions.single.nextRenewalOn, DateTime(2026, 10, 1));
    expect(state.subscriptions.single.renewalHistory, hasLength(1));

    final snoozedUntil = DateTime(2026, 9, 15);
    expect(
      await state.snoozeSubscriptionReminder(
        state.subscriptions.single,
        SubscriptionSnoozeTarget.calendarDate(snoozedUntil),
      ),
      isTrue,
    );
    await reopen();
    expect(state.subscriptions.single.snoozedUntil, snoozedUntil);
    expect(state.subscriptions.single.snoozedUntilUtc, isNull);

    final exactSnooze = DateTime.utc(2026, 9, 15, 7, 45, 30);
    expect(
      await state.snoozeSubscriptionReminder(
        state.subscriptions.single,
        SubscriptionSnoozeTarget.exactInstant(exactSnooze),
      ),
      isTrue,
    );
    await reopen();
    expect(state.subscriptions.single.snoozedUntil, isNull);
    expect(state.subscriptions.single.snoozedUntilUtc, exactSnooze);

    final accessEndsOn = subscriptionDateOnly(
      DateTime.now().add(const Duration(days: 30)),
    );
    expect(
      await state.cancelSubscription(
        state.subscriptions.single,
        accessEndsOn: accessEndsOn,
      ),
      isTrue,
    );
    await reopen();
    expect(state.subscriptions.single.status, SubscriptionStatus.cancelled);
    expect(state.subscriptions.single.reminderEnabled, isFalse);
    expect(state.subscriptions.single.snoozedUntil, isNull);
    expect(state.subscriptions.single.snoozedUntilUtc, isNull);
    expect(state.subscriptions.single.cancelledOn, isNotNull);
    expect(state.subscriptions.single.accessEndsOn, accessEndsOn);
    expect(state.subscriptions.single.renewalHistory, hasLength(1));

    expect(await state.restoreSubscription(state.subscriptions.single), isTrue);
    await reopen();
    expect(state.subscriptions.single.status, SubscriptionStatus.active);
    expect(state.subscriptions.single.reminderEnabled, isTrue);
    expect(state.subscriptions.single.cancelledOn, isNull);
    expect(state.subscriptions.single.accessEndsOn, isNull);
    expect(state.subscriptions.single.renewalHistory, hasLength(1));
  });

  test('删除单条订阅会重排仅剩提醒且重开后删除状态保持', () async {
    final store = FakeVaultStore();
    final scheduler = RecordingReminderScheduler();
    var state = AppState(vaultStore: store, reminderScheduler: scheduler);
    addTearDown(() => state.dispose());

    await state.initialize();
    await state.createVault(_testMasterPassword);
    await _drainEventQueue();
    await state.addAccount(
      AccountDraft(platformName: '删除订阅平台'),
      initialSubscription: _subscriptionDetails(serviceName: '待删除订阅'),
    );
    await state.addSubscription(
      SubscriptionDraft(
        accountId: state.accounts.single.id,
        details: _subscriptionDetails(serviceName: '保留订阅'),
      ),
    );
    final deletedId = state.subscriptions.first.id;
    final retainedId = state.subscriptions.last.id;
    await state.updatePreferences(
      state.preferences.copyWith(notificationsEnabled: true),
    );

    scheduler.reset();
    expect(await state.deleteSubscription(deletedId), isTrue);
    expect(scheduler.rescheduleCalls, hasLength(1));
    expect(scheduler.rescheduleCalls.single.subscriptionIds, <String>[
      retainedId,
    ]);
    expect(store.snapshot.subscriptions.single.id, retainedId);

    state.dispose();
    scheduler.reset();
    state = AppState(vaultStore: store, reminderScheduler: scheduler);
    await state.initialize();
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
    await _drainEventQueue();
    expect(state.subscriptions.single.id, retainedId);
    expect(
      state.subscriptions.any((subscription) => subscription.id == deletedId),
      isFalse,
    );
    expect(scheduler.rescheduleCalls.single.subscriptionIds, <String>[
      retainedId,
    ]);
  });

  test('真实库与诱饵库可分别恢复且保持中性路由和失败计数边界', () async {
    final store = FakeVaultStore();
    final state = AppState(
      vaultStore: store,
      unlockThrottleController: UnlockThrottleController(
        MemoryUnlockThrottleStore(),
        MemoryUnlockThrottleClock(),
      ),
    );
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_testMasterPassword);
    await state.addAccount(AccountDraft(platformName: '恢复前平台'));

    final primaryQuestions = vaultRecoveryQuestionCatalog
        .take(3)
        .map((question) => question.id)
        .toList(growable: false);
    final decoyQuestions = vaultRecoveryQuestionCatalog
        .skip(3)
        .take(3)
        .map((question) => question.id)
        .toList(growable: false);
    const primaryAnswers = <String>['杭州', '实验小学', '王老师'];
    const decoyAnswers = <String>['红色', '小狗', '图书馆'];
    const decoyPassword = 'DECOY-TEST-PASSWORD-5678';
    const newDecoyPassword = 'Rotated-Decoy-85!Harbor';
    const newPrimaryPassword = 'Rotated-Master-85!Harbor';

    expect(
      await state.configurePasswordRecovery(
        currentMasterPassword: _testMasterPassword,
        questionIds: primaryQuestions,
        answers: primaryAnswers,
        entryMode: VaultRecoveryEntryMode.visible,
      ),
      isTrue,
    );
    expect(
      await state.createDecoyVault(
        currentMasterPassword: _testMasterPassword,
        decoyPassword: decoyPassword,
      ),
      isTrue,
    );
    expect(
      await state.configurePasswordRecovery(
        currentMasterPassword: _testMasterPassword,
        currentDecoyPassword: decoyPassword,
        questionIds: decoyQuestions,
        answers: decoyAnswers,
        entryMode: VaultRecoveryEntryMode.logoFiveTap,
        scope: VaultRecoveryScope.decoy,
      ),
      isTrue,
    );
    expect(state.primaryRecoveryConfigured, isTrue);
    expect(state.decoyRecoveryConfigured, isTrue);
    expect(state.recoveryConfigured, isTrue, reason: '兼容 getter 仍代表真实库');

    state.lock();
    expect(
      await state.unlock('WRONG-BUT-STRONG-PASSWORD'),
      VaultActionResult.rejected,
    );
    expect(state.failedUnlockAttempts, 1);
    expect(
      await state.recoverMasterPassword(
        questionIds: decoyQuestions,
        answers: decoyAnswers,
        newMasterPassword: newDecoyPassword,
        requestEntryMode: VaultRecoveryEntryMode.visible,
      ),
      isFalse,
      reason: 'visible 入口不能使用仅配置在 Logo 五击入口的材料',
    );
    expect(state.failedUnlockAttempts, 1);
    expect(
      await state.recoverMasterPassword(
        questionIds: decoyQuestions,
        answers: decoyAnswers,
        newMasterPassword: newDecoyPassword,
        requestEntryMode: VaultRecoveryEntryMode.logoFiveTap,
      ),
      isTrue,
    );
    expect(state.canManageSecurity, isFalse);
    expect(state.failedUnlockAttempts, 1, reason: '诱饵恢复不得清零真实主密码错误计数');
    expect(
      await state.exportEncryptedBackup(
        backupMasterPassword: 'TEST-ONLY-DECOY-BACKUP-5678',
      ),
      isNull,
      reason: '诱饵完整会话不得生成会被误认为真实库的便携备份',
    );

    state.lock();
    expect(
      await state.recoverMasterPassword(
        questionIds: primaryQuestions,
        answers: primaryAnswers,
        newMasterPassword: newPrimaryPassword,
        requestEntryMode: VaultRecoveryEntryMode.visible,
      ),
      isTrue,
    );
    expect(state.canManageSecurity, isTrue);
    expect(state.failedUnlockAttempts, 0, reason: '只有真实库恢复成功才清零');
    expect(state.accounts.single.platformName, '恢复前平台');
    expect(
      await state.exportEncryptedBackup(
        backupMasterPassword: 'TEST-ONLY-PRIMARY-BACKUP-5678',
      ),
      isNotNull,
      reason: '真实库恢复成功后仍可正常导出便携备份',
    );

    expect(
      await state.disablePasswordRecovery(
        currentMasterPassword: newPrimaryPassword,
        currentDecoyPassword: newDecoyPassword,
        scope: VaultRecoveryScope.decoy,
      ),
      isTrue,
    );
    expect(state.decoyRecoveryConfigured, isFalse);
    expect(state.primaryRecoveryConfigured, isTrue);
    expect(
      await state.disablePasswordRecovery(
        currentMasterPassword: newPrimaryPassword,
      ),
      isTrue,
    );
    expect(state.anyRecoveryConfigured, isFalse);
  });

  test('prepared 导入回滚日志阻断真实库恢复但不阻断诱饵库', () async {
    final store = FakeVaultStore();
    final recoveryJournal = _RecordingRecoveryJournal(
      VaultRecoveryState.prepared,
    );
    final state = AppState(vaultStore: store, recoveryJournal: recoveryJournal);
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_testMasterPassword);

    final primaryQuestions = vaultRecoveryQuestionCatalog
        .take(3)
        .map((question) => question.id)
        .toList(growable: false);
    final decoyQuestions = vaultRecoveryQuestionCatalog
        .skip(3)
        .take(3)
        .map((question) => question.id)
        .toList(growable: false);
    const primaryAnswers = <String>['杭州', '实验小学', '王老师'];
    const decoyAnswers = <String>['红色', '小狗', '图书馆'];
    const decoyPassword = 'DECOY-TEST-PASSWORD-5678';
    const blockedPrimaryPassword = 'Blocked-Master-34!Harbor';
    const recoveredDecoyPassword = 'Recovered-Decoy-34!Harbor';

    expect(
      await state.configurePasswordRecovery(
        currentMasterPassword: _testMasterPassword,
        questionIds: primaryQuestions,
        answers: primaryAnswers,
        entryMode: VaultRecoveryEntryMode.visible,
      ),
      isTrue,
    );
    expect(
      await state.createDecoyVault(
        currentMasterPassword: _testMasterPassword,
        decoyPassword: decoyPassword,
      ),
      isTrue,
    );
    expect(
      await state.configurePasswordRecovery(
        currentMasterPassword: _testMasterPassword,
        currentDecoyPassword: decoyPassword,
        questionIds: decoyQuestions,
        answers: decoyAnswers,
        entryMode: VaultRecoveryEntryMode.visible,
        scope: VaultRecoveryScope.decoy,
      ),
      isTrue,
    );

    state.lock();
    expect(
      await state.recoverMasterPassword(
        questionIds: primaryQuestions,
        answers: primaryAnswers,
        newMasterPassword: blockedPrimaryPassword,
        requestEntryMode: VaultRecoveryEntryMode.visible,
      ),
      isFalse,
    );
    expect(state.errorMessage, isNot(contains('真实库')));
    expect(
      await state.unlock(blockedPrimaryPassword),
      VaultActionResult.rejected,
      reason: '待处理的真实库回滚副本必须阻止真实库改密提交',
    );

    expect(
      await state.recoverMasterPassword(
        questionIds: decoyQuestions,
        answers: decoyAnswers,
        newMasterPassword: recoveredDecoyPassword,
        requestEntryMode: VaultRecoveryEntryMode.visible,
      ),
      isTrue,
      reason: '真实库的回滚副本不得阻断独立诱饵库恢复',
    );
    expect(state.canManageSecurity, isFalse);
    expect(recoveryJournal.clearCalls, 0);
    state.lock();
    expect(
      await state.unlock(recoveredDecoyPassword),
      VaultActionResult.success,
    );
    expect(state.canManageSecurity, isFalse);
  });

  test('committed 回滚凭据只在正确真实恢复认证后清除', () async {
    final store = FakeVaultStore();
    final recoveryJournal = _RecordingRecoveryJournal(
      VaultRecoveryState.committed,
    );
    final state = AppState(vaultStore: store, recoveryJournal: recoveryJournal);
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_testMasterPassword);
    final questions = vaultRecoveryQuestionCatalog
        .take(3)
        .map((question) => question.id)
        .toList(growable: false);
    const answers = <String>['杭州', '实验小学', '王老师'];
    expect(
      await state.configurePasswordRecovery(
        currentMasterPassword: _testMasterPassword,
        questionIds: questions,
        answers: answers,
        entryMode: VaultRecoveryEntryMode.visible,
      ),
      isTrue,
    );

    state.lock();
    expect(
      await state.recoverMasterPassword(
        questionIds: questions,
        answers: const <String>['错误', '实验小学', '王老师'],
        newMasterPassword: 'Rejected-Master-34!Harbor',
        requestEntryMode: VaultRecoveryEntryMode.visible,
      ),
      isFalse,
    );
    expect(recoveryJournal.clearCalls, 0, reason: '错误答案不得废弃回滚凭据');

    expect(
      await state.recoverMasterPassword(
        questionIds: questions,
        answers: answers,
        newMasterPassword: 'Recovered-Master-34!Harbor',
        requestEntryMode: VaultRecoveryEntryMode.visible,
      ),
      isTrue,
    );
    expect(recoveryJournal.clearCalls, 1);
    expect(recoveryJournal.cleared, isTrue);
    expect(state.hasRecoveryRollback, isFalse);
  });

  test('损坏的真实库回滚日志保守阻断真实恢复但不阻断诱饵恢复', () async {
    final store = FakeVaultStore();
    final state = AppState(
      vaultStore: store,
      recoveryJournal: const _ThrowingRecoveryJournal(),
    );
    addTearDown(state.dispose);
    await state.initialize();
    await state.createVault(_testMasterPassword);

    final primaryQuestions = vaultRecoveryQuestionCatalog
        .take(3)
        .map((question) => question.id)
        .toList(growable: false);
    final decoyQuestions = vaultRecoveryQuestionCatalog
        .skip(3)
        .take(3)
        .map((question) => question.id)
        .toList(growable: false);
    const primaryAnswers = <String>['杭州', '实验小学', '王老师'];
    const decoyAnswers = <String>['红色', '小狗', '图书馆'];
    const decoyPassword = 'DECOY-TEST-PASSWORD-5678';
    const blockedPrimaryPassword = 'Blocked-Master-92!Harbor';
    const recoveredDecoyPassword = 'Recovered-Decoy-92!Harbor';

    expect(
      await state.configurePasswordRecovery(
        currentMasterPassword: _testMasterPassword,
        questionIds: primaryQuestions,
        answers: primaryAnswers,
        entryMode: VaultRecoveryEntryMode.visible,
      ),
      isTrue,
    );
    expect(
      await state.createDecoyVault(
        currentMasterPassword: _testMasterPassword,
        decoyPassword: decoyPassword,
      ),
      isTrue,
    );
    expect(
      await state.configurePasswordRecovery(
        currentMasterPassword: _testMasterPassword,
        currentDecoyPassword: decoyPassword,
        questionIds: decoyQuestions,
        answers: decoyAnswers,
        entryMode: VaultRecoveryEntryMode.visible,
        scope: VaultRecoveryScope.decoy,
      ),
      isTrue,
    );

    state.lock();
    expect(
      await state.recoverMasterPassword(
        questionIds: primaryQuestions,
        answers: primaryAnswers,
        newMasterPassword: blockedPrimaryPassword,
        requestEntryMode: VaultRecoveryEntryMode.visible,
      ),
      isFalse,
    );
    expect(state.errorMessage, isNot(contains('真实库')));
    expect(
      await state.unlock(blockedPrimaryPassword),
      VaultActionResult.rejected,
    );
    expect(
      await state.recoverMasterPassword(
        questionIds: decoyQuestions,
        answers: decoyAnswers,
        newMasterPassword: recoveredDecoyPassword,
        requestEntryMode: VaultRecoveryEntryMode.visible,
      ),
      isTrue,
    );
    expect(state.canManageSecurity, isFalse);
  });

  test('第五次错误冷却跨AppState保留，真实主密码成功后持久清零', () async {
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
    );
    final clock = MemoryUnlockThrottleClock();
    final throttleStore = MemoryUnlockThrottleStore();
    var state = AppState(
      vaultStore: store,
      unlockThrottleController: UnlockThrottleController(throttleStore, clock),
    );
    await state.initialize();

    for (var attempt = 1; attempt <= 5; attempt += 1) {
      expect(
        await state.unlock('WRONG-PASSWORD-$attempt'),
        VaultActionResult.rejected,
      );
    }
    expect(store.unlockCalls, 5);
    expect(state.failedUnlockAttempts, 5);
    expect(state.unlockCooldownRemaining, const Duration(seconds: 30));
    expect(state.passwordUnlockBlocked, isTrue);
    expect(state.errorMessage, contains('不会清空、锁死或删除'));

    expect(await state.unlock(_testMasterPassword), VaultActionResult.rejected);
    expect(store.unlockCalls, 5, reason: '冷却期间不应继续执行 Argon2 或读取保险库');

    state.dispose();
    state = AppState(
      vaultStore: store,
      unlockThrottleController: UnlockThrottleController(throttleStore, clock),
    );
    addTearDown(state.dispose);
    await state.initialize();
    expect(state.failedUnlockAttempts, 5);
    expect(state.passwordUnlockBlocked, isTrue);
    expect(await state.unlock(_testMasterPassword), VaultActionResult.rejected);
    expect(store.unlockCalls, 5);

    clock.advance(const Duration(seconds: 30));
    await state.refreshUnlockThrottle();
    expect(state.failedUnlockAttempts, 5, reason: '中间层到期只清冷却，不清错误次数');
    expect(state.passwordUnlockBlocked, isFalse);
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
    expect(store.unlockCalls, 6);
    expect(state.unlockCooldownRemaining, Duration.zero);
    expect(state.failedUnlockAttempts, 0);
    expect(state.unlockAttemptsRemaining, 10);
    expect(throttleStore.value!.state, UnlockThrottleRecordState.cleared);
  });

  test('存储故障不计作主密码错误', () async {
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
    );
    final throttleStore = MemoryUnlockThrottleStore();
    final state = AppState(
      vaultStore: store,
      unlockThrottleController: UnlockThrottleController(
        throttleStore,
        MemoryUnlockThrottleClock(),
      ),
    );
    addTearDown(state.dispose);
    await state.initialize();
    store.failAccess = true;

    expect(
      await state.unlock('NOT-A-CREDENTIAL-RESULT'),
      VaultActionResult.failed,
    );
    expect(state.failedUnlockAttempts, 0);
    expect(throttleStore.writeCalls, 0);
  });

  test('诱饵密码与生物识别成功均不清零，真实主密码成功才清零', () async {
    final clock = MemoryUnlockThrottleClock();
    final throttleStore = MemoryUnlockThrottleStore();
    final store = _ScopedPasswordVaultStore();
    var state = AppState(
      vaultStore: store,
      unlockThrottleController: UnlockThrottleController(throttleStore, clock),
    );
    await state.initialize();
    for (var attempt = 1; attempt <= 4; attempt += 1) {
      expect(
        await state.unlock('WRONG-BEFORE-DECOY-$attempt'),
        VaultActionResult.rejected,
      );
    }
    expect(state.failedUnlockAttempts, 4);

    expect(await state.unlock(store.decoyPassword), VaultActionResult.success);
    expect(state.failedUnlockAttempts, 4);
    state.lock();
    expect(
      await state.unlock('FIFTH-WRONG-AFTER-DECOY'),
      VaultActionResult.rejected,
    );
    expect(state.failedUnlockAttempts, 5);
    expect(state.unlockCooldownRemaining, const Duration(seconds: 30));

    clock.advance(const Duration(seconds: 30));
    await state.refreshUnlockThrottle();
    expect(
      await state.unlock(store.primaryPassword),
      VaultActionResult.success,
    );
    expect(state.failedUnlockAttempts, 0);
    state.dispose();

    state = AppState(
      vaultStore: store,
      unlockThrottleController: UnlockThrottleController(throttleStore, clock),
    );
    addTearDown(state.dispose);
    await state.initialize();
    for (var attempt = 1; attempt <= 4; attempt += 1) {
      expect(
        await state.unlock('WRONG-BEFORE-BIOMETRIC-$attempt'),
        VaultActionResult.rejected,
      );
    }
    expect(await state.unlockWithQuickUnlock(), VaultActionResult.success);
    expect(state.failedUnlockAttempts, 4);
    state.lock();
    expect(
      await state.unlock('FIFTH-WRONG-AFTER-BIOMETRIC'),
      VaultActionResult.rejected,
    );
    expect(state.failedUnlockAttempts, 5);
    expect(state.passwordUnlockBlocked, isTrue);
  });
}

final class _RecordingRecoveryJournal implements VaultRecoveryJournal {
  _RecordingRecoveryJournal(this.state);

  final VaultRecoveryState state;
  int clearCalls = 0;
  bool cleared = false;

  @override
  Future<VaultRecoveryEntry?> read() async => cleared
      ? null
      : VaultRecoveryEntry(
          transactionId: 'test-recovery-transaction',
          createdAtUtc: DateTime.utc(2026, 9, 6),
          sourceGeneration: 1,
          revision: 1,
          state: state,
          encryptedVaultBytes: const <int>[1],
        );

  @override
  Future<void> clear() async {
    clearCalls += 1;
    cleared = true;
  }

  @override
  Future<String> stage({
    required List<int> encryptedVaultBytes,
    required int sourceGeneration,
  }) async => 'test-recovery-transaction';

  @override
  Future<void> markCommitted(String transactionId) async {}

  @override
  Future<void> markRolledBack(String transactionId) async {}
}

final class _ThrowingRecoveryJournal implements VaultRecoveryJournal {
  const _ThrowingRecoveryJournal();

  @override
  Future<VaultRecoveryEntry?> read() async =>
      throw const FormatException('test-only corrupt recovery journal');

  @override
  Future<void> clear() async {}

  @override
  Future<String> stage({
    required List<int> encryptedVaultBytes,
    required int sourceGeneration,
  }) async => 'test-only-corrupt-recovery-journal';

  @override
  Future<void> markCommitted(String transactionId) async {}

  @override
  Future<void> markRolledBack(String transactionId) async {}
}

final class _ScopedPasswordVaultStore implements VaultStore {
  _ScopedPasswordVaultStore({
    VaultSnapshot? primarySnapshot,
    VaultSnapshot? decoySnapshot,
  }) : _primarySnapshot = primarySnapshot ?? VaultSnapshot.empty(),
       _decoySnapshot = decoySnapshot ?? VaultSnapshot.empty();

  final String primaryPassword = 'PRIMARY-TEST-PASSWORD-1234';
  final String decoyPassword = 'DECOY-TEST-PASSWORD-1234';
  VaultSnapshot _primarySnapshot;
  VaultSnapshot _decoySnapshot;

  @override
  Future<bool> exists() async => true;

  @override
  Future<VaultOpenResult> create({required String masterPassword}) async =>
      throw const VaultAlreadyExistsException();

  @override
  Future<VaultOpenResult> unlock({required String masterPassword}) async {
    if (masterPassword == primaryPassword) {
      return _result(canManageSecurity: true, snapshot: _primarySnapshot);
    }
    if (masterPassword == decoyPassword) {
      return _result(canManageSecurity: false, snapshot: _decoySnapshot);
    }
    throw const VaultUnlockException();
  }

  @override
  Future<bool> isQuickUnlockEnabled() async => true;

  @override
  Future<VaultOpenResult> unlockWithQuickUnlock() async =>
      _result(canManageSecurity: true, snapshot: _primarySnapshot);

  @override
  Future<void> disableQuickUnlock() async {}

  @override
  Future<VaultSnapshot> readEncryptedBackup({
    required List<int> bytes,
    required String masterPassword,
  }) async => _primarySnapshot;

  VaultOpenResult _result({
    required bool canManageSecurity,
    required VaultSnapshot snapshot,
  }) => VaultOpenResult(
    session: _ScopedTestSession(
      canManageSecurity: canManageSecurity,
      onSave: (nextSnapshot) {
        if (canManageSecurity) {
          _primarySnapshot = nextSnapshot;
        } else {
          _decoySnapshot = nextSnapshot;
        }
      },
    ),
    snapshot: snapshot,
  );
}

final class _ScopedTestSession implements ScopedVaultSession {
  _ScopedTestSession({required this.canManageSecurity, required this.onSave});

  @override
  final bool canManageSecurity;
  final void Function(VaultSnapshot) onSave;

  @override
  VaultAccessLevel get accessLevel => VaultAccessLevel.full;

  @override
  int get generation => 1;

  @override
  Future<void> save(VaultSnapshot snapshot) async => onSave(snapshot);

  @override
  Future<Uint8List> exportEncryptedBackup() async => Uint8List(0);

  @override
  Future<void> enableQuickUnlock() async {}

  @override
  void close() {}
}

Future<void> _drainEventQueue() async {
  for (var index = 0; index < 3; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, Map<String, String>> _previousThreeMonthCosts(
  AppState state,
  DateTime today,
) => {
  for (var offset = -3; offset <= -1; offset += 1)
    _relativeMonthKey(today, offset): {
      for (final total in SubscriptionCostAnalysis.build(
        subscriptions: state.subscriptions,
        expenses: state.subscriptionExpenses,
        accounts: state.accounts,
        range: SubscriptionCostRange(
          startMonth: DateTime(today.year, today.month + offset),
          endMonth: DateTime(today.year, today.month + offset),
        ),
        today: today,
      ).currencyTotals(SubscriptionCostBasis.confirmed))
        total.currency: total.formattedAmount,
    },
};

String _relativeMonthKey(DateTime today, int offset) => formatSubscriptionDate(
  DateTime(today.year, today.month + offset),
).substring(0, 7);

List<SubscriptionCostLine> _nextThreeMonthForecast(
  AppState state,
  DateTime today,
) => SubscriptionCostAnalysis.build(
  subscriptions: state.subscriptions,
  expenses: state.subscriptionExpenses,
  accounts: state.accounts,
  range: SubscriptionCostRange(
    startMonth: DateTime(today.year, today.month),
    endMonth: DateTime(today.year, today.month + 3),
  ),
  today: today,
).forBasis(SubscriptionCostBasis.futureEstimate);

SubscriptionDetailsDraft _subscriptionDetails({required String serviceName}) =>
    SubscriptionDetailsDraft(
      serviceName: serviceName,
      planName: '月度版',
      amount: '19.9',
      currency: 'CNY',
      firstSubscribedOn: DateTime(2026, 8, 1),
      nextRenewalOn: DateTime(2026, 9, 1),
      cycleCount: 1,
      cycleUnit: SubscriptionCycleUnit.month,
      autoRenew: true,
      paymentMethod: '支付宝',
      reminderDaysBefore: 7,
    );
