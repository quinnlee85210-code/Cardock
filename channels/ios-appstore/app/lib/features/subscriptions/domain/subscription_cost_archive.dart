import '../../accounts/domain/account_record.dart';
import 'subscription_cost_summary.dart';
import 'subscription_expense_record.dart';
import 'subscription_record.dart';

/// Keep already displayed historical charges when a user deletes a card.
/// Only the selected cards are archived; future forecasts are never saved.
({int nextExpenseId, List<SubscriptionExpenseRecord> expenses})
archiveRemovedSubscriptionCosts({
  required Iterable<SubscriptionRecord> removedSubscriptions,
  required Iterable<AccountRecord> accounts,
  required Set<String> retainedAccountIds,
  required List<SubscriptionExpenseRecord> previousExpenses,
  required List<SubscriptionExpenseRecord> expenses,
  required int nextExpenseId,
  DateTime? today,
  bool preserveSubscriptionId = false,
}) {
  final now = subscriptionDateOnly(today ?? DateTime.now());
  final result = [...expenses];
  final accountsById = {for (final account in accounts) account.id: account};
  final expensesBySubscription = <String, List<SubscriptionExpenseRecord>>{};
  for (final expense in previousExpenses) {
    final id = expense.subscriptionId;
    if (id != null) (expensesBySubscription[id] ??= []).add(expense);
  }
  var nextId = nextExpenseId;
  for (final sub in removedSubscriptions) {
    // Bound each analysis window without silently truncating older daily
    // subscriptions. The persisted ledger has its existing global limit.
    var firstYear = sub.firstSubscribedOn.year;
    for (final event in sub.renewalHistory) {
      if (event.recordedOn.year < firstYear) firstYear = event.recordedOn.year;
    }
    for (var year = firstYear; year <= now.year; year += 1) {
      final analysis = SubscriptionCostAnalysis.build(
        subscriptions: [sub],
        accounts: [?accountsById[sub.accountId]],
        // Scheduled-entry suppression is scoped to the current subscription ID.
        // Unrelated/manual/refund ledger entries remain unchanged in result.
        expenses: expensesBySubscription[sub.id] ?? const [],
        range: SubscriptionCostRange(
          startMonth: DateTime(year),
          endMonth: DateTime(year, 12),
        ),
        today: now,
      );
      for (final line in analysis.forBasis(SubscriptionCostBasis.confirmed)) {
        if (!line.fromSchedule ||
            line.amount == null ||
            line.date.isAfter(now)) {
          continue;
        }
        if (result.length >= maximumConfirmedSubscriptionExpenses ||
            nextId >= 1000000000) {
          throw const FormatException('费用记录已达到本机安全上限');
        }
        result.add(
          SubscriptionExpenseRecord.fromDraft(
            id: 'expense-${nextId++}',
            draft: SubscriptionExpenseDraft(
              subscriptionId: preserveSubscriptionId ? sub.id : null,
              accountId: retainedAccountIds.contains(sub.accountId)
                  ? sub.accountId
                  : null,
              serviceName: line.serviceName,
              occurredOn: line.date,
              amount: line.amount!,
              currency: line.currency,
              kind: SubscriptionExpenseKind.payment,
              expenseCategory: line.expenseCategory,
              scheduledRenewalOn: line.scheduledOn,
            ),
            accountLabel: line.accountLabel,
            source: line.scheduledOn == sub.firstSubscribedOn
                ? SubscriptionExpenseSource.subscriptionEntry
                : SubscriptionExpenseSource.renewal,
          ),
        );
      }
    }
  }
  return (nextExpenseId: nextId, expenses: List.unmodifiable(result));
}
