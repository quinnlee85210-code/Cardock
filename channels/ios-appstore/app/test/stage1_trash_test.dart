import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_trash.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_cost_summary.dart';
import 'support/fake_vault_store.dart';
import 'support/recording_reminder_scheduler.dart';

final now = DateTime.utc(2026, 9, 3);
const master = 'STAGE1-TEST-ONLY-1234';
VaultSnapshot fixture() => VaultSnapshot(
  nextAccountId: 2,
  accounts: [
    AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(
        platformName: '测试',
        password: 'TEST-CURRENT',
        notes: '备注',
      ),
    ),
  ],
  nextSubscriptionId: 3,
  subscriptions: [
    for (final id in [1, 2])
      SubscriptionRecord.fromDraft(
        id: 'subscription-$id',
        draft: SubscriptionDraft(
          accountId: id == 1 ? 'account-1' : null,
          details: SubscriptionDetailsDraft(
            serviceName: '订阅$id',
            amount: '12.3456',
            firstSubscribedOn: DateTime(2026, 6, 1),
            nextRenewalOn: DateTime(2026, 10, 1),
            status: SubscriptionStatus.paused,
          ),
        ),
      ),
  ],
  recentAccountIds: ['account-1'],
);
VaultSnapshot deleted() => VaultTrash.move(
  fixture(),
  accountId: 'account-1',
  now: now,
  batchId: 'batch-1',
);

void main() {
  test('账号与直接订阅同批次移入，独立订阅保留，账号正文和日期不变', () {
    final source = fixture();
    final result = deleted();
    expect(result.accounts, isEmpty);
    expect(result.subscriptions.single.id, 'subscription-2');
    expect(result.recentAccountIds, isEmpty);
    expect(
      result.trashAccounts.single.record.toEncryptedPayloadJson(),
      source.accounts.single.toEncryptedPayloadJson(),
    );
    expect(
      result.trashSubscriptions.single.record.toEncryptedPayloadJson(),
      source.subscriptions.first.toEncryptedPayloadJson(),
    );
    expect(
      result.trashAccounts.single.batchId,
      result.trashSubscriptions.single.batchId,
    );
    expect(result.trashAccounts.single.deletedAtUtc.isUtc, isTrue);
  });
  test('单独订阅删除只移动该项', () {
    final result = VaultTrash.move(
      fixture(),
      subscriptionId: 'subscription-1',
      now: now,
      batchId: 'single',
    );
    expect(result.accounts, hasLength(1));
    expect(result.trashAccounts, isEmpty);
    expect(result.subscriptions, hasLength(1));
  });
  test('组合恢复保持ID、关系、状态、日期及费用，不重复', () {
    final source = fixture();
    final trash = deleted();
    final result = VaultTrash.restore(
      trash,
      accountId: 'account-1',
      wholeBatch: true,
    );
    expect(result.trashAccounts, isEmpty);
    expect(result.trashSubscriptions, isEmpty);
    expect(
      result.accounts.single.toEncryptedPayloadJson(),
      source.accounts.single.toEncryptedPayloadJson(),
    );
    expect(
      result.subscriptions.last.toEncryptedPayloadJson(),
      source.subscriptions.first.toEncryptedPayloadJson(),
    );
    expect(result.subscriptionExpenses, trash.subscriptionExpenses);
    expect(
      () =>
          VaultTrash.restore(result, accountId: 'account-1', wholeBatch: true),
      throwsA(isA<VaultFormatException>()),
    );
  });
  test('单条账号恢复不恢复订阅，子订阅不能产生孤儿关系', () {
    final trash = deleted();
    expect(
      () => VaultTrash.restore(trash, subscriptionId: 'subscription-1'),
      throwsA(isA<VaultFormatException>()),
    );
    final account = VaultTrash.restore(trash, accountId: 'account-1');
    expect(account.trashSubscriptions, hasLength(1));
    expect(
      VaultTrash.restore(
        account,
        subscriptionId: 'subscription-1',
      ).subscriptions,
      hasLength(2),
    );
  });
  test('30天到期包含等于边界且重复清理幂等', () {
    final trash = deleted();
    final deadline = now.add(const Duration(days: 30));
    expect(
      VaultTrash.purgeExpired(
        trash,
        deadline.subtract(const Duration(microseconds: 1)),
      ).trashAccounts,
      hasLength(1),
    );
    final purged = VaultTrash.purgeExpired(trash, deadline);
    expect(purged.trashAccounts, isEmpty);
    expect(purged.trashSubscriptions, isEmpty);
    expect(
      jsonEncode(
        VaultTrash.purgeExpired(purged, deadline).toEncryptedPayloadJson(),
      ),
      jsonEncode(purged.toEncryptedPayloadJson()),
    );
    expect(
      () => VaultTrash.restore(purged, accountId: 'account-1'),
      throwsA(isA<VaultFormatException>()),
    );
  });
  test('永久移除保留费用且无损坏引用', () {
    final trash = deleted();
    final purged = VaultTrash.remove(trash, accountIds: {'account-1'});
    expect(
      purged.subscriptionExpenses.length,
      trash.subscriptionExpenses.length,
    );
    expect(
      purged.subscriptionExpenses.every(
        (e) => e.subscriptionId == null && e.accountId == null,
      ),
      isTrue,
    );
    expect(
      VaultSnapshot.fromEncryptedPayloadJson(
        purged.toEncryptedPayloadJson(),
      ).trashAccounts,
      isEmpty,
    );
  });
  test('schema11往返保留回收站及现有业务结构', () {
    final source = deleted();
    final result = VaultSnapshot.fromEncryptedPayloadJson(
      jsonDecode(jsonEncode(source.toEncryptedPayloadJson())),
    );
    expect(result.toEncryptedPayloadJson(), source.toEncryptedPayloadJson());
  });
  test('schema10安全默认活动记录，迁移可重入，未来schema拒绝', () {
    final old = fixture().toEncryptedPayloadJson()
      ..['schemaVersion'] = 10
      ..remove('trashAccounts')
      ..remove('trashSubscriptions');
    final result = VaultSnapshot.fromEncryptedPayloadJson(old);
    expect(result.trashAccounts, isEmpty);
    expect(result.accounts.single.id, 'account-1');
    expect(
      VaultSnapshot.fromEncryptedPayloadJson(
        result.toEncryptedPayloadJson(),
      ).toEncryptedPayloadJson(),
      result.toEncryptedPayloadJson(),
    );
    expect(
      () => VaultSnapshot.fromEncryptedPayloadJson({
        ...old,
        'schemaVersion': VaultSnapshot.currentSchemaVersion + 1,
      }),
      throwsA(isA<VaultUnsupportedSchemaVersionException>()),
    );
  });
  test('禁止活动与回收站复用ID、非法时间和缺失父账号', () {
    final trash = deleted();
    expect(
      () => trash.copyWith(accounts: fixture().accounts),
      throwsA(isA<VaultFormatException>()),
    );
    expect(
      () => TrashAccount.fromJson({
        ...trash.trashAccounts.single.toJson(),
        'deletedAtUtc': '2026-09-03T00:00:00',
      }),
      throwsFormatException,
    );
    expect(
      () => trash.copyWith(trashAccounts: []),
      throwsA(isA<VaultFormatException>()),
    );
  });
  test('AppState活动列表及提醒排除回收站，恢复保留账期和费用', () async {
    final scheduler = RecordingReminderScheduler();
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: master,
      snapshot: fixture().copyWith(
        preferences: const VaultPreferences(notificationsEnabled: true),
      ),
    );
    final app = AppState(
      vaultStore: store,
      reminderScheduler: scheduler,
      now: () => now,
    );
    addTearDown(app.dispose);
    await app.initialize();
    await app.unlock(master);
    await pumpEventQueue();
    expect(await app.deleteAccount('account-1'), isTrue);
    expect(app.accounts, isEmpty);
    expect(app.subscriptions.single.id, 'subscription-2');
    final expenses = app.subscriptionExpenses
        .map((e) => e.toEncryptedPayloadJson())
        .toList();
    expect(
      await app.restoreTrash(accountId: 'account-1', wholeBatch: true),
      isTrue,
    );
    expect(
      app.subscriptionExpenses.map((e) => e.toEncryptedPayloadJson()).toList(),
      expenses,
    );
    expect(app.subscriptions.last.nextRenewalOn, DateTime(2026, 10, 1));
  });
  test('失败零写且永久删除要求当前凭据与清空文字', () async {
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: master,
      snapshot: fixture(),
    );
    final app = AppState(vaultStore: store, now: () => now);
    addTearDown(app.dispose);
    await app.initialize();
    await app.unlock(master);
    store.failSaves = true;
    expect(await app.deleteAccount('account-1'), isFalse);
    expect(app.accounts, hasLength(1));
    expect(app.trashAccounts, isEmpty);
    store.failSaves = false;
    await app.deleteAccount('account-1');
    expect(
      await app.permanentlyDeleteTrash(
        currentPassword: 'wrong',
        accountIds: {'account-1'},
      ),
      isFalse,
    );
    expect(
      await app.permanentlyDeleteTrash(
        currentPassword: master,
        emptyAll: true,
        confirmation: 'wrong',
      ),
      isFalse,
    );
    expect(app.trashAccounts, hasLength(1));
    expect(
      await app.permanentlyDeleteTrash(
        currentPassword: master,
        emptyAll: true,
        confirmation: '清空回收站',
      ),
      isTrue,
    );
    expect(app.trashAccounts, isEmpty);
    app.lock();
    expect(await app.purgeExpiredTrash(), isFalse);
  });
  test('过期自动清理失败不影响解锁并保留记录', () async {
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: master,
      snapshot: deleted(),
    )..failSaves = true;
    final app = AppState(
      vaultStore: store,
      now: () => now.add(const Duration(days: 31)),
    );
    addTearDown(app.dispose);
    await app.initialize();
    expect(await app.unlock(master), VaultActionResult.success);
    await pumpEventQueue();
    expect(app.isUnlocked, isTrue);
    expect(app.trashAccounts, hasLength(1));
    expect(store.snapshot.trashAccounts, hasLength(1));
  });
  test('费用历史删除和恢复后一致', () {
    SubscriptionCostAnalysis analysis(VaultSnapshot s) =>
        SubscriptionCostAnalysis.build(
          subscriptions: s.subscriptions,
          accounts: s.accounts,
          expenses: s.subscriptionExpenses,
          range: SubscriptionCostRange(
            startMonth: DateTime(2026),
            endMonth: DateTime(2026, 12),
          ),
          today: now,
        );
    final trash = deleted();
    final restored = VaultTrash.restore(
      trash,
      accountId: 'account-1',
      wholeBatch: true,
    );
    final before = analysis(
      fixture(),
    ).forBasis(SubscriptionCostBasis.confirmed);
    expect(
      analysis(trash).forBasis(SubscriptionCostBasis.confirmed).length,
      before.length,
    );
    expect(
      analysis(restored).forBasis(SubscriptionCostBasis.confirmed).length,
      before.length,
    );
  });
}
