import '../../accounts/domain/account_record.dart';
import 'subscription_expense_record.dart';
import 'subscription_record.dart';

String subscriptionExpenseAccountLabel(AccountRecord account) => <String?>[
  account.category,
  account.platformName,
  account.loginAccount ?? account.username,
].whereType<String>().where((value) => value.isNotEmpty).join(' · ');

/// Records entry/renewal actions only. Elapsed calendar cycles never pay.
({int nextExpenseId, List<SubscriptionExpenseRecord> expenses})
recordSubscriptionActions({
  required Iterable<SubscriptionRecord> previousSubscriptions,
  required Iterable<SubscriptionRecord> subscriptions,
  required Iterable<AccountRecord> accounts,
  required List<SubscriptionExpenseRecord> expenses,
  required int nextExpenseId,
  bool migrating = false,
}) {
  final previous = {for (final sub in previousSubscriptions) sub.id: sub};
  final accountById = {for (final account in accounts) account.id: account};
  final subscriptionById = {for (final sub in subscriptions) sub.id: sub};
  final result = expenses.map((expense) {
    if (!migrating || expense.accountLabel != null) return expense;
    final account =
        accountById[subscriptionById[expense.subscriptionId]?.accountId];
    return account == null
        ? expense
        : expense.withAccountContext(
            accountId: account.id,
            accountLabel: subscriptionExpenseAccountLabel(account),
          );
  }).toList();
  final payments = <String, List<SubscriptionExpenseRecord>>{};
  for (final expense in result) {
    if (expense.subscriptionId != null &&
        expense.kind == SubscriptionExpenseKind.payment) {
      (payments[expense.subscriptionId!] ??= []).add(expense);
    }
  }
  var nextId = nextExpenseId;
  void add(
    SubscriptionRecord sub,
    DateTime date,
    SubscriptionExpenseSource source, {
    DateTime? scheduled,
  }) {
    if (sub.amount == null) return;
    if (result.length >= maximumConfirmedSubscriptionExpenses ||
        nextId >= 1000000000) {
      throw const FormatException('费用记录已达到本机安全上限');
    }
    final account = accountById[sub.accountId];
    final expense = SubscriptionExpenseRecord.fromDraft(
      id: 'expense-${nextId++}',
      draft: SubscriptionExpenseDraft(
        subscriptionId: sub.id,
        paymentMethodId: sub.management?.paymentMethodId,
        paymentMethodName: sub.paymentMethod,
        accountId: sub.accountId,
        serviceName: sub.serviceName,
        occurredOn: date,
        amount: sub.amount!,
        currency: sub.currency,
        kind: SubscriptionExpenseKind.payment,
        expenseCategory: sub.expenseCategory ?? account?.category,
        scheduledRenewalOn: scheduled,
      ),
      accountLabel: account == null
          ? null
          : subscriptionExpenseAccountLabel(account),
      source: source,
    );
    result.add(expense);
    (payments[sub.id] ??= []).add(expense);
  }

  for (final sub in subscriptions) {
    // Trial cash flow always requires a separate explicit confirmation. Do not
    // infer an entry payment when the user creates or resolves a trial.
    if (sub.management?.trial != null) continue;
    final old = previous[sub.id];
    final paid = payments[sub.id] ?? [];
    if (migrating ||
        old == null ||
        (old.amount == null && sub.amount != null)) {
      // Old manual payments had no billing-date field; preserve them as the
      // entry payment instead of charging the same subscription twice.
      final hasEntry = paid.any(
        (expense) =>
            expense.source == SubscriptionExpenseSource.subscriptionEntry ||
            expense.scheduledRenewalOn == null ||
            expense.scheduledRenewalOn == sub.firstSubscribedOn,
      );
      if (!hasEntry) {
        add(
          sub,
          sub.firstSubscribedOn,
          SubscriptionExpenseSource.subscriptionEntry,
        );
      }
    }
    if (migrating || old == null) continue;
    final oldDates = old.renewalHistory
        .map((event) => event.previousRenewalOn)
        .toSet();
    for (final event in sub.renewalHistory) {
      if (oldDates.contains(event.previousRenewalOn)) continue;
      if ((payments[sub.id] ?? []).any(
        (expense) => expense.scheduledRenewalOn == event.previousRenewalOn,
      )) {
        continue;
      }
      add(
        sub,
        event.recordedOn,
        SubscriptionExpenseSource.renewal,
        scheduled: event.previousRenewalOn,
      );
    }
  }
  return (nextExpenseId: nextId, expenses: List.unmodifiable(result));
}
