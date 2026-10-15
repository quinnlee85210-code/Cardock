import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_trash.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_expense_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_cost_summary.dart';

final _now = DateTime(2026, 9, 4);
AccountRecord _account(int index) => AccountRecord.fromDraft(
  id: 'account-$index',
  draft: AccountDraft(
    platformName: 'Synthetic $index',
    category: 'Synthetic category $index',
  ),
);
SubscriptionRecord _subscription(int index) => SubscriptionRecord.fromDraft(
  id: 'subscription-$index',
  draft: SubscriptionDraft(
    accountId: 'account-$index',
    details: SubscriptionDetailsDraft(
      serviceName: 'Synthetic $index',
      amount: '$index.2345',
      currency: index.isOdd ? 'CNY' : 'USD',
      firstSubscribedOn: DateTime(2026, 7, 1),
      nextRenewalOn: DateTime(2026, 10, 1),
    ),
  ),
);
SubscriptionCostAnalysis _analysis(VaultSnapshot source) =>
    SubscriptionCostAnalysis.build(
      subscriptions: source.subscriptions,
      accounts: source.accounts,
      expenses: source.subscriptionExpenses,
      today: _now,
      range: SubscriptionCostRange(
        startMonth: DateTime(2026),
        endMonth: DateTime(2026, 12),
      ),
    );
List<String> _confirmed(VaultSnapshot source) =>
    _analysis(source)
        .forBasis(SubscriptionCostBasis.confirmed)
        .map(
          (line) => jsonEncode([
            line.date.toIso8601String(),
            line.serviceName,
            line.currency,
            line.amount,
            line.refund,
            line.expenseCategory,
            line.accountLabel,
            line.subscriptionId,
            line.scheduledOn?.toIso8601String(),
          ]),
        )
        .toList()
      ..sort();

void main() {
  test(
    'batch archive preserves exact paid/history/refund/manual amounts and account labels',
    () {
      final source = VaultSnapshot(
        nextAccountId: 4,
        accounts: [for (var i = 1; i <= 3; i++) _account(i)],
        nextSubscriptionId: 4,
        subscriptions: [for (var i = 1; i <= 3; i++) _subscription(i)],
        nextExpenseId: 4,
        subscriptionExpenses: [
          SubscriptionExpenseRecord.fromDraft(
            id: 'expense-1',
            source: SubscriptionExpenseSource.subscriptionEntry,
            draft: SubscriptionExpenseDraft(
              subscriptionId: 'subscription-1',
              accountId: 'account-1',
              serviceName: 'Synthetic 1',
              occurredOn: DateTime(2026, 7, 1),
              amount: '1.2345',
              currency: 'CNY',
              scheduledRenewalOn: DateTime(2026, 7, 1),
              kind: SubscriptionExpenseKind.payment,
            ),
          ),
          SubscriptionExpenseRecord.fromDraft(
            id: 'expense-2',
            draft: SubscriptionExpenseDraft(
              subscriptionId: 'subscription-2',
              accountId: 'account-2',
              serviceName: 'Synthetic 2',
              occurredOn: DateTime(2026, 8, 15),
              amount: '0.0123',
              currency: 'USD',
              kind: SubscriptionExpenseKind.refund,
            ),
          ),
          SubscriptionExpenseRecord.fromDraft(
            id: 'expense-3',
            draft: SubscriptionExpenseDraft(
              subscriptionId: null,
              serviceName: 'Unlinked synthetic',
              occurredOn: DateTime(2026, 9, 1),
              amount: '999.0001',
              currency: 'JPY',
              kind: SubscriptionExpenseKind.payment,
            ),
          ),
        ],
      );
      final before = _confirmed(source);
      final moved = VaultTrash.moveAccounts(
        source,
        accountIds: {'account-1', 'account-2'},
        now: _now,
        batchId: 'batch-archive',
      );
      expect(_confirmed(moved), before);
      expect(
        moved.subscriptionExpenses
            .take(3)
            .map((e) => e.toEncryptedPayloadJson())
            .toList(),
        source.subscriptionExpenses
            .map((e) => e.toEncryptedPayloadJson())
            .toList(),
      );
      expect(moved.trashSubscriptions, hasLength(2));
      expect(
        _analysis(moved)
            .forBasis(SubscriptionCostBasis.futureEstimate)
            .every((line) => line.subscriptionId == 'subscription-3'),
        isTrue,
      );
    },
  );
  test(
    'bulk archive with 5000 accounts and subscriptions keeps all associations',
    () {
      final source = VaultSnapshot(
        nextAccountId: 5001,
        nextSubscriptionId: 5001,
        accounts: [for (var i = 1; i <= 5000; i++) _account(i)],
        subscriptions: [for (var i = 1; i <= 5000; i++) _subscription(i)],
      );
      final moved = VaultTrash.moveAccounts(
        source,
        accountIds: source.accounts.map((a) => a.id).toSet(),
        now: _now,
        batchId: 'batch-5000-full',
      );
      expect(moved.trashAccounts, hasLength(5000));
      expect(moved.trashSubscriptions, hasLength(5000));
      expect(moved.accounts, isEmpty);
      expect(moved.subscriptions, isEmpty);
      expect(
        moved.subscriptionExpenses.map((e) => e.subscriptionId).toSet(),
        source.subscriptions.map((s) => s.id).toSet(),
      );
      expect(
        moved.subscriptionExpenses.every((e) => e.amount.endsWith('.2345')),
        isTrue,
      );
    },
  );
}
