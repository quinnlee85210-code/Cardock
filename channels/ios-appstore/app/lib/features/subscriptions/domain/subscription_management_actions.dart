import 'subscription_cost_summary.dart';
import '../../../core/security/vault_contract.dart';
import 'subscription_expense_record.dart';
import 'subscription_record.dart';

VaultSnapshot resolveSubscriptionTrial(
  VaultSnapshot source, {
  required String subscriptionId,
  required TrialOutcome outcome,
  required DateTime now,
  DateTime? actualPaidOn,
  String? actualAmount,
  String? actualCurrency,
  bool paymentConfirmed = false,
}) {
  final sub = source.subscriptions.firstWhere((s) => s.id == subscriptionId);
  final trial = sub.management?.trial;
  if (trial == null) throw StateError('此订阅没有试用记录');
  if (!trial.unresolved) throw StateError('试用结果已经处理，不会重复记账');
  if (actualPaidOn != null &&
      subscriptionDateOnly(actualPaidOn).isAfter(subscriptionDateOnly(now))) {
    throw ArgumentError('实际付款日期不能晚于今天');
  }
  final resolved = trial.resolve(
    outcome,
    now: now,
    actualPaidOn: actualPaidOn,
    actualAmount: actualAmount,
    actualCurrency: actualCurrency,
    paid: paymentConfirmed,
  );
  var management = sub.management!.copyWith(trial: resolved);
  var updated = sub.withManagement(management);
  var nextExpenseId = source.nextExpenseId;
  final expenses = [...source.subscriptionExpenses];
  if (outcome == TrialOutcome.converted) {
    management = management.putPrice(
      SubscriptionPricePoint(
        id: 'conversion-${now.toUtc().microsecondsSinceEpoch}',
        effectiveOn: actualPaidOn!,
        amount: actualAmount!,
        currency: actualCurrency!,
        cycleCount: trial.formalCycleCount,
        cycleUnit: trial.formalCycleUnit,
        kind: PriceChangeKind.change,
        createdAt: now,
      ),
      replaceSameDay: true,
    );
    final nextDate = advanceSubscriptionDate(
      actualPaidOn,
      count: trial.formalCycleCount,
      unit: trial.formalCycleUnit,
      preserveMonthEnd: true,
    );
    updated = sub.applyDraft(
      SubscriptionDraft(
        accountId: sub.accountId,
        details: sub.details.copyWith(
          management: management,
          amount: actualAmount,
          currency: actualCurrency,
          cycleCount: trial.formalCycleCount,
          cycleUnit: trial.formalCycleUnit,
          nextRenewalOn: nextDate,
          reminderEnabled: true,
          status: SubscriptionStatus.active,
        ),
      ),
    );
    if (paymentConfirmed) {
      expenses.add(
        SubscriptionExpenseRecord.fromDraft(
          id: 'expense-${nextExpenseId++}',
          source: SubscriptionExpenseSource.trialConversion,
          recordedAtUtc: now,
          draft: SubscriptionExpenseDraft(
            subscriptionId: sub.id,
            accountId: sub.accountId,
            serviceName: sub.serviceName,
            occurredOn: actualPaidOn,
            scheduledRenewalOn: actualPaidOn,
            amount: actualAmount,
            currency: actualCurrency,
            kind: SubscriptionExpenseKind.payment,
            expenseCategory: sub.expenseCategory,
            paymentMethodId: management.paymentMethodId,
            paymentMethodName: sub.paymentMethod,
          ),
        ),
      );
    }
  } else {
    updated = updated.applyDraft(
      SubscriptionDraft(
        accountId: updated.accountId,
        details: updated.details.copyWith(
          status: outcome == TrialOutcome.cancelled
              ? SubscriptionStatus.cancelled
              : SubscriptionStatus.expired,
          reminderEnabled: false,
        ),
      ),
    );
  }
  return source.copyWith(
    subscriptions: [
      for (final s in source.subscriptions)
        if (s.id == sub.id) updated else s,
    ],
    nextExpenseId: nextExpenseId,
    subscriptionExpenses: expenses,
  );
}

VaultSnapshot confirmTrialCharge(
  VaultSnapshot source, {
  required String subscriptionId,
  required DateTime paidOn,
  required DateTime now,
}) {
  final sub = source.subscriptions.firstWhere((s) => s.id == subscriptionId),
      trial = sub.management?.trial;
  if (trial == null ||
      !trial.unresolved ||
      parseScaledSubscriptionAmount(trial.amount) == BigInt.zero ||
      source.subscriptionExpenses.any(
        (e) =>
            e.subscriptionId == sub.id &&
            e.source == SubscriptionExpenseSource.trialPayment,
      )) {
    throw StateError('试用费用无效或已经确认');
  }
  if (subscriptionDateOnly(paidOn).isAfter(subscriptionDateOnly(now))) {
    throw ArgumentError('实际付款日期不能晚于今天');
  }
  final expense = SubscriptionExpenseRecord.fromDraft(
    id: 'expense-${source.nextExpenseId}',
    source: SubscriptionExpenseSource.trialPayment,
    recordedAtUtc: now,
    draft: SubscriptionExpenseDraft(
      subscriptionId: sub.id,
      accountId: sub.accountId,
      serviceName: sub.serviceName,
      occurredOn: paidOn,
      amount: trial.amount,
      currency: trial.currency,
      kind: SubscriptionExpenseKind.payment,
      expenseCategory: sub.expenseCategory,
      paymentMethodId: sub.management?.paymentMethodId,
      paymentMethodName: sub.paymentMethod,
    ),
  );
  return source.copyWith(
    nextExpenseId: source.nextExpenseId + 1,
    subscriptionExpenses: [...source.subscriptionExpenses, expense],
  );
}

VaultSnapshot savePaymentMethod(
  VaultSnapshot source,
  PaymentMethodRecord method,
) {
  if (source.paymentMethods.any(
    (p) =>
        p.id != method.id &&
        normalizedPaymentMethodName(p.name) ==
            normalizedPaymentMethodName(method.name),
  )) {
    throw ArgumentError('同名支付方式已存在');
  }
  SubscriptionRecord update(SubscriptionRecord s) =>
      s.management?.paymentMethodId == method.id
      ? s.applyDraft(
          SubscriptionDraft(
            accountId: s.accountId,
            details: s.details.copyWith(paymentMethod: method.name),
          ),
        )
      : s;
  return source.copyWith(
    paymentMethods: [
      ...source.paymentMethods.where((p) => p.id != method.id),
      method,
    ],
    subscriptions: source.subscriptions.map(update).toList(),
    trashSubscriptions: [
      for (final t in source.trashSubscriptions)
        TrashSubscription(
          record: update(t.record),
          deletedAtUtc: t.deletedAtUtc,
          batchId: t.batchId,
        ),
    ],
  );
}

VaultSnapshot mergePaymentMethods(
  VaultSnapshot source, {
  required String fromId,
  required String intoId,
}) {
  if (fromId == intoId) throw ArgumentError('请选择不同支付方式');
  source.paymentMethods.firstWhere((p) => p.id == fromId);
  final target = source.paymentMethods.firstWhere((p) => p.id == intoId);
  if (target.archived) throw ArgumentError('请先恢复目标支付方式');
  SubscriptionRecord update(SubscriptionRecord s) =>
      s.management?.paymentMethodId == fromId
      ? s.applyDraft(
          SubscriptionDraft(
            accountId: s.accountId,
            details: s.details.copyWith(
              paymentMethod: target.name,
              management: s.management!.copyWith(paymentMethodId: target.id),
            ),
          ),
        )
      : s;
  return source.copyWith(
    paymentMethods: source.paymentMethods.where((p) => p.id != fromId).toList(),
    subscriptions: source.subscriptions.map(update).toList(),
    trashSubscriptions: [
      for (final t in source.trashSubscriptions)
        TrashSubscription(
          record: update(t.record),
          deletedAtUtc: t.deletedAtUtc,
          batchId: t.batchId,
        ),
    ],
    // Preserve historical name snapshots even when the user explicitly merges identities.
    subscriptionExpenses: [
      for (final e in source.subscriptionExpenses)
        if (e.paymentMethodId == fromId)
          e.withPaymentMethod(id: intoId, name: e.paymentMethodName)
        else
          e,
    ],
  );
}

VaultSnapshot deletePaymentMethod(VaultSnapshot source, String id) {
  if ([
        ...source.subscriptions,
        ...source.trashSubscriptions.map((t) => t.record),
      ].any((s) => s.management?.paymentMethodId == id) ||
      source.subscriptionExpenses.any((e) => e.paymentMethodId == id)) {
    throw StateError('使用中的支付方式只能归档');
  }
  return source.copyWith(
    paymentMethods: source.paymentMethods.where((p) => p.id != id).toList(),
  );
}
