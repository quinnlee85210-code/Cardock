import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_expense_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('schema 9费用与密码复核迁移', () {
    test('schema 8升级后录入费用计入一次、密码历史为空且密码提醒关闭', () {
      final current = _schema9Snapshot();
      final legacy = Map<String, Object?>.from(current.toEncryptedPayloadJson())
        ..['schemaVersion'] = 8;
      legacy
        ..remove('nextExpenseId')
        ..remove('subscriptionExpenses');
      legacy['accounts'] = <Object?>[
        for (final raw in legacy['accounts']! as List<Object?>)
          Map<String, Object?>.from(raw! as Map<String, Object?>)
            ..remove('passwordStoredAtUtc')
            ..remove('passwordSyncState')
            ..remove('passwordVerifiedAtUtc')
            ..remove('platformPasswordChangedAtUtc')
            ..remove('passwordReviewIntervalDays')
            ..remove('passwordReviewSnoozedUntilUtc'),
      ];
      legacy['subscriptions'] = <Object?>[
        for (final raw in legacy['subscriptions']! as List<Object?>)
          Map<String, Object?>.from(raw! as Map<String, Object?>)
            ..remove('expenseCategory'),
      ];
      legacy['preferences'] = Map<String, Object?>.from(
        legacy['preferences']! as Map<String, Object?>,
      )..remove('passwordReviewNotificationsEnabled');

      final migrated = VaultSnapshot.fromEncryptedPayloadJson(legacy);

      expect(migrated.nextExpenseId, 2);
      expect(migrated.subscriptionExpenses.single.amount, '20');
      expect(
        migrated.subscriptionExpenses.single.source,
        SubscriptionExpenseSource.subscriptionEntry,
      );
      expect(
        migrated.accounts.every(
          (account) => account.passwordChangeHistory.isEmpty,
        ),
        isTrue,
      );
      expect(
        migrated.accounts.map((account) => account.passwordSyncState),
        everyElement(PasswordSyncState.unknown),
      );
      for (final account in migrated.accounts) {
        expect(account.passwordStoredAtUtc, isNull);
        expect(account.passwordVerifiedAtUtc, isNull);
        expect(account.platformPasswordChangedAtUtc, isNull);
        expect(account.passwordReviewIntervalDays, isNull);
        expect(account.passwordReviewSnoozedUntilUtc, isNull);
      }
      expect(migrated.preferences.passwordReviewNotificationsEnabled, isFalse);
      expect(migrated.subscriptions.single.expenseCategory, isNull);
      expect(
        migrated.toEncryptedPayloadJson()['schemaVersion'],
        VaultSnapshot.currentSchemaVersion,
      );
    });

    test('schema 9往返费用、分类、四态密码元数据与提醒偏好', () {
      final source = _schema9Snapshot();
      final payload = source.toEncryptedPayloadJson();

      final restored = VaultSnapshot.fromEncryptedPayloadJson(payload);

      expect(payload['schemaVersion'], VaultSnapshot.currentSchemaVersion);
      expect(restored.nextExpenseId, 2);
      expect(restored.subscriptionExpenses, hasLength(1));
      final expense = restored.subscriptionExpenses.single;
      expect(expense.id, 'expense-1');
      expect(expense.subscriptionId, 'subscription-1');
      expect(expense.serviceName, '订阅名称快照');
      expect(expense.amount, '19.9001');
      expect(expense.expenseCategory, '支出分类快照');
      expect(expense.kind, SubscriptionExpenseKind.payment);
      expect(expense.scheduledRenewalOn, DateTime(2026, 9, 1));
      expect(restored.subscriptions.single.expenseCategory, '当前订阅分类');
      expect(restored.preferences.passwordReviewNotificationsEnabled, isTrue);

      final accountsById = <String, AccountRecord>{
        for (final account in restored.accounts) account.id: account,
      };
      expect(
        accountsById['account-unknown']!.passwordSyncState,
        PasswordSyncState.unknown,
      );
      expect(
        accountsById['account-review']!.passwordSyncState,
        PasswordSyncState.needsReview,
      );
      expect(
        accountsById['account-verified']!.passwordSyncState,
        PasswordSyncState.verified,
      );
      expect(
        accountsById['account-external']!.passwordSyncState,
        PasswordSyncState.externalChangePendingSync,
      );
      expect(
        accountsById['account-unknown']!.passwordStoredAtUtc,
        DateTime.utc(2026, 1, 1),
      );
      expect(
        accountsById['account-review']!.passwordReviewSnoozedUntilUtc,
        DateTime.utc(2026, 10, 1),
      );
      expect(
        accountsById['account-verified']!.passwordVerifiedAtUtc,
        DateTime.utc(2026, 8, 1, 2),
      );
      expect(
        accountsById['account-external']!.platformPasswordChangedAtUtc,
        DateTime.utc(2026, 8, 20, 3),
      );
      expect(restored.toEncryptedPayloadJson(), payload);
    });

    test('未知未来版本安全拒绝', () {
      final future = Map<String, Object?>.from(
        _schema9Snapshot().toEncryptedPayloadJson(),
      )..['schemaVersion'] = VaultSnapshot.currentSchemaVersion + 1;

      expect(
        () => VaultSnapshot.fromEncryptedPayloadJson(future),
        throwsA(isA<VaultUnsupportedSchemaVersionException>()),
      );
    });

    test('删除订阅后解除关联但保留费用事实和全部快照', () {
      final linked = _expense();
      final unlinked = linked.unlinkSubscription();

      expect(unlinked.subscriptionId, isNull);
      expect(unlinked.id, linked.id);
      expect(unlinked.serviceName, linked.serviceName);
      expect(unlinked.occurredOn, linked.occurredOn);
      expect(unlinked.amount, linked.amount);
      expect(unlinked.currency, linked.currency);
      expect(unlinked.kind, linked.kind);
      expect(unlinked.expenseCategory, linked.expenseCategory);
      expect(unlinked.scheduledRenewalOn, linked.scheduledRenewalOn);
      expect(unlinked.recordedAtUtc, linked.recordedAtUtc);

      final afterDeletion = VaultSnapshot(
        nextAccountId: 1,
        accounts: const <AccountRecord>[],
        nextExpenseId: 2,
        subscriptionExpenses: <SubscriptionExpenseRecord>[unlinked],
      );
      expect(afterDeletion.subscriptionExpenses.single.subscriptionId, isNull);

      expect(
        () => VaultSnapshot(
          nextAccountId: 1,
          accounts: const <AccountRecord>[],
          nextExpenseId: 2,
          subscriptionExpenses: <SubscriptionExpenseRecord>[linked],
        ),
        throwsA(isA<VaultFormatException>()),
      );
    });

    test('无密码元数据、无周期稍后提醒和无时间平台改密均拒绝', () {
      expect(
        () => AccountRecord.fromDraft(
          id: 'account-no-password',
          draft: AccountDraft(platformName: '无密码账号'),
          passwordStoredAtUtc: DateTime.utc(2026, 1, 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => AccountRecord.fromDraft(
          id: 'account-snooze-no-cycle',
          draft: AccountDraft(platformName: '无周期账号', password: 'secret'),
          passwordReviewSnoozedUntilUtc: DateTime.utc(2026, 10, 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => AccountRecord.fromDraft(
          id: 'account-external-no-time',
          draft: AccountDraft(platformName: '平台改密账号', password: 'secret'),
          passwordSyncState: PasswordSyncState.externalChangePendingSync,
        ),
        throwsArgumentError,
      );
    });

    test('nextExpenseId不得与已生成费用编号碰撞', () {
      final unlinked = _expense().unlinkSubscription();

      expect(
        () => VaultSnapshot(
          nextAccountId: 1,
          accounts: const <AccountRecord>[],
          nextExpenseId: 1,
          subscriptionExpenses: <SubscriptionExpenseRecord>[unlinked],
        ),
        throwsA(isA<VaultFormatException>()),
      );
    });

    test('密码复核到期以用户确认、待核对和稍后提醒状态计算', () {
      final verified = AccountRecord.fromDraft(
        id: 'account-due-verified',
        draft: AccountDraft(platformName: '已核对', password: 'secret'),
        passwordSyncState: PasswordSyncState.verified,
        passwordVerifiedAtUtc: DateTime.utc(2026, 1, 1),
        passwordReviewIntervalDays: 180,
      );
      final needsReview = AccountRecord.fromDraft(
        id: 'account-due-review',
        draft: AccountDraft(platformName: '待核对', password: 'secret'),
        passwordSyncState: PasswordSyncState.needsReview,
        passwordReviewIntervalDays: 180,
      );
      final snoozed = AccountRecord.fromDraft(
        id: 'account-due-snoozed',
        draft: AccountDraft(platformName: '稍后提醒', password: 'secret'),
        passwordSyncState: PasswordSyncState.needsReview,
        passwordReviewIntervalDays: 90,
        passwordReviewSnoozedUntilUtc: DateTime.utc(2026, 9, 20),
      );
      final now = DateTime.utc(2026, 9, 1);

      expect(
        verified.passwordReviewDueAtUtc(nowUtc: now),
        DateTime.utc(2026, 6, 30),
      );
      expect(needsReview.passwordReviewDueAtUtc(nowUtc: now), now);
      expect(
        snoozed.passwordReviewDueAtUtc(nowUtc: now),
        DateTime.utc(2026, 9, 20),
      );
    });
  });
}

VaultSnapshot _schema9Snapshot() {
  final accounts = <AccountRecord>[
    AccountRecord.fromDraft(
      id: 'account-unknown',
      draft: AccountDraft(platformName: '未知状态', password: 'unknown-secret'),
      passwordStoredAtUtc: DateTime.utc(2026, 1, 1),
      passwordSyncState: PasswordSyncState.unknown,
      passwordReviewIntervalDays: 365,
    ),
    AccountRecord.fromDraft(
      id: 'account-review',
      draft: AccountDraft(platformName: '待核对状态', password: 'review-secret'),
      passwordStoredAtUtc: DateTime.utc(2026, 2, 1),
      passwordSyncState: PasswordSyncState.needsReview,
      passwordReviewIntervalDays: 90,
      passwordReviewSnoozedUntilUtc: DateTime.utc(2026, 10, 1),
    ),
    AccountRecord.fromDraft(
      id: 'account-verified',
      draft: AccountDraft(platformName: '已核对状态', password: 'verified-secret'),
      passwordStoredAtUtc: DateTime.utc(2026, 3, 1),
      passwordSyncState: PasswordSyncState.verified,
      passwordVerifiedAtUtc: DateTime.utc(2026, 8, 1, 2),
      passwordReviewIntervalDays: 180,
    ),
    AccountRecord.fromDraft(
      id: 'account-external',
      draft: AccountDraft(platformName: '平台已改密状态', password: 'external-secret'),
      passwordStoredAtUtc: DateTime.utc(2026, 4, 1),
      passwordSyncState: PasswordSyncState.externalChangePendingSync,
      platformPasswordChangedAtUtc: DateTime.utc(2026, 8, 20, 3),
      passwordReviewIntervalDays: 365,
    ),
  ];
  final subscription = SubscriptionRecord.fromDraft(
    id: 'subscription-1',
    draft: SubscriptionDraft(
      accountId: 'account-unknown',
      details: SubscriptionDetailsDraft(
        serviceName: '当前订阅名称',
        firstSubscribedOn: DateTime(2026, 1, 1),
        nextRenewalOn: DateTime(2026, 9, 1),
        amount: '20',
        expenseCategory: '当前订阅分类',
      ),
    ),
  );

  return VaultSnapshot(
    nextAccountId: 5,
    accounts: accounts,
    nextSubscriptionId: 2,
    subscriptions: <SubscriptionRecord>[subscription],
    nextExpenseId: 2,
    subscriptionExpenses: <SubscriptionExpenseRecord>[_expense()],
    preferences: const VaultPreferences(
      notificationsEnabled: true,
      passwordReviewNotificationsEnabled: true,
    ),
  );
}

SubscriptionExpenseRecord _expense() => SubscriptionExpenseRecord.fromDraft(
  id: 'expense-1',
  draft: SubscriptionExpenseDraft(
    subscriptionId: 'subscription-1',
    serviceName: '订阅名称快照',
    occurredOn: DateTime(2026, 9, 2),
    amount: '19.9001',
    currency: 'CNY',
    kind: SubscriptionExpenseKind.payment,
    expenseCategory: '支出分类快照',
    scheduledRenewalOn: DateTime(2026, 9, 1),
  ),
  recordedAtUtc: DateTime.utc(2026, 9, 2, 12, 30),
);
