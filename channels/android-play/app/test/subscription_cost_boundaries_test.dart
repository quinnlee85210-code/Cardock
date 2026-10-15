import 'dart:convert';

import 'package:account_subscription_manager/features/subscriptions/domain/subscription_cost_summary.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_expense_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('订阅费用账期边界', () {
    test('续费后的日期延长不补出原到期日付款，同月只有保存的新账期', () {
      final renewed = _subscription(
        first: DateTime(2026, 4, 1),
        next: DateTime(2026, 5, 1),
      ).markRenewed(recordedOn: DateTime(2026, 5, 1));
      final adjusted = _edit(renewed, next: DateTime(2026, 6, 15));

      final analysis = _analyzeUnchanged(
        adjusted,
        startMonth: DateTime(2026, 6),
        endMonth: DateTime(2026, 6),
      );
      final confirmed = analysis.forBasis(SubscriptionCostBasis.confirmed);

      expect(confirmed, hasLength(1));
      expect(confirmed.single.date, DateTime(2026, 6, 15));
      expect(confirmed.single.scheduledOn, DateTime(2026, 6, 15));
      expect(_total(analysis), '10');
      expect(analysis.gaps, hasLength(1));
      expect(analysis.gaps.single.start, DateTime(2026, 6, 1));
      expect(analysis.gaps.single.endExclusive, DateTime(2026, 6, 15));
    });

    test('当前周期改短且日期调早不拆分已有季付，明确付款金额保持原快照', () {
      final quarterly = _subscription(
        first: DateTime(2026, 1, 31),
        next: DateTime(2026, 4, 30),
        cycleCount: 3,
        amount: '90',
      ).markRenewed(recordedOn: DateTime(2026, 4, 30));
      final adjusted = _edit(
        quarterly,
        next: DateTime(2026, 2, 28),
        cycleCount: 1,
        amount: '30',
      );
      final paidQuarter = _payment(
        subscription: adjusted,
        occurredOn: DateTime(2026, 4, 30),
        scheduledOn: DateTime(2026, 4, 30),
        amount: '90',
      );

      final analysis = _analyzeUnchanged(
        adjusted,
        expenses: [paidQuarter],
        startMonth: DateTime(2026, 4),
        endMonth: DateTime(2026, 6),
      );
      final confirmed = analysis.forBasis(SubscriptionCostBasis.confirmed);

      expect(confirmed, hasLength(1));
      expect(confirmed.single.date, DateTime(2026, 4, 30));
      expect(confirmed.single.amount, '90');
      expect(confirmed.single.fromSchedule, isFalse);
      expect(_total(analysis), '90');
      expect(analysis.byMonth(SubscriptionCostBasis.confirmed).keys, [
        '2026-04',
      ]);
      expect(analysis.gaps, isNotEmpty);
    });

    test('取消停止未来预测，取消前每月费用保留，权益结束不构成付款', () {
      final cancelled =
          _subscription(
            first: DateTime(2026, 1, 10),
            next: DateTime(2026, 9, 10),
          ).cancel(
            cancelledOn: DateTime(2026, 8, 20),
            accessEndsOn: DateTime(2026, 10, 31),
          );

      final analysis = _analyzeUnchanged(
        cancelled,
        startMonth: DateTime(2026, 1),
        endMonth: DateTime(2026, 12),
      );
      final confirmed = analysis.forBasis(SubscriptionCostBasis.confirmed);

      expect(confirmed, hasLength(8));
      expect(confirmed.map((line) => line.date), [
        for (var month = 1; month <= 8; month++) DateTime(2026, month, 10),
      ]);
      expect(_total(analysis), '80');
      expect(analysis.forBasis(SubscriptionCostBasis.futureEstimate), isEmpty);
      expect(analysis.gaps, isEmpty);
    });

    test('暂停不清除已有付款或此前连续账期，付款日期和金额覆盖计划日期', () {
      final paused = _subscription(
        first: DateTime(2026, 1, 10),
        next: DateTime(2026, 9, 10),
        status: SubscriptionStatus.paused,
      );
      final actualPayment = _payment(
        subscription: paused,
        occurredOn: DateTime(2026, 2, 11),
        scheduledOn: DateTime(2026, 2, 10),
        amount: '11',
      );

      final analysis = _analyzeUnchanged(
        paused,
        expenses: [actualPayment],
        startMonth: DateTime(2026, 1),
        endMonth: DateTime(2026, 12),
      );
      final confirmed = analysis.forBasis(SubscriptionCostBasis.confirmed);

      expect(confirmed, hasLength(8));
      expect(_total(analysis), '81');
      final february = analysis.byMonth(
        SubscriptionCostBasis.confirmed,
      )['2026-02']!;
      expect(february, hasLength(1));
      expect(february.single.date, DateTime(2026, 2, 11));
      expect(february.single.amount, '11');
      expect(february.single.fromSchedule, isFalse);
      expect(analysis.forBasis(SubscriptionCostBasis.futureEstimate), isEmpty);
      expect(analysis.gaps, isEmpty);
    });

    test('首次与下一续费不能按季度衔接时标记缺口而不反推虚构月份', () {
      final subscription = _subscription(
        first: DateTime(2026, 1, 15),
        next: DateTime(2026, 11, 15),
        cycleCount: 3,
        amount: '90',
      );

      final analysis = _analyzeUnchanged(
        subscription,
        startMonth: DateTime(2026, 1),
        endMonth: DateTime(2026, 12),
      );
      final confirmed = analysis.forBasis(SubscriptionCostBasis.confirmed);
      final future = analysis.forBasis(SubscriptionCostBasis.futureEstimate);

      expect(confirmed, hasLength(1));
      expect(confirmed.single.date, DateTime(2026, 1, 15));
      expect(_total(analysis), '90');
      expect(future, hasLength(1));
      expect(future.single.date, DateTime(2026, 11, 15));
      expect(analysis.gaps, hasLength(1));
      expect(analysis.gaps.single.subscriptionId, subscription.id);
      expect(analysis.gaps.single.start, DateTime(2026, 4, 15));
      expect(analysis.gaps.single.endExclusive, DateTime(2026, 9, 3));
    });
  });
}

SubscriptionRecord _subscription({
  required DateTime first,
  required DateTime next,
  int cycleCount = 1,
  String amount = '10',
  SubscriptionStatus status = SubscriptionStatus.active,
}) => SubscriptionRecord.fromDraft(
  id: 'subscription-boundary',
  draft: SubscriptionDraft(
    accountId: null,
    details: SubscriptionDetailsDraft(
      serviceName: '边界测试订阅',
      planName: '测试套餐',
      amount: amount,
      firstSubscribedOn: first,
      nextRenewalOn: next,
      cycleCount: cycleCount,
      status: status,
      notes: '仅用于自动化的虚构记录',
    ),
  ),
);

SubscriptionRecord _edit(
  SubscriptionRecord subscription, {
  required DateTime next,
  int? cycleCount,
  String? amount,
}) => subscription.applyDraft(
  SubscriptionDraft(
    accountId: subscription.accountId,
    details: SubscriptionDetailsDraft(
      serviceName: subscription.serviceName,
      planName: subscription.planName,
      amount: amount ?? subscription.amount,
      currency: subscription.currency,
      firstSubscribedOn: subscription.firstSubscribedOn,
      nextRenewalOn: next,
      cycleCount: cycleCount ?? subscription.cycleCount,
      cycleUnit: subscription.cycleUnit,
      status: subscription.status,
      notes: subscription.notes,
    ),
  ),
);

SubscriptionExpenseRecord _payment({
  required SubscriptionRecord subscription,
  required DateTime occurredOn,
  required DateTime scheduledOn,
  required String amount,
}) => SubscriptionExpenseRecord.fromDraft(
  id: 'expense-boundary',
  draft: SubscriptionExpenseDraft(
    subscriptionId: subscription.id,
    serviceName: '付款时的服务名称',
    occurredOn: occurredOn,
    scheduledRenewalOn: scheduledOn,
    amount: amount,
    currency: 'CNY',
    kind: SubscriptionExpenseKind.payment,
  ),
  recordedAtUtc: DateTime.utc(2026, 9, 1),
  source: SubscriptionExpenseSource.renewal,
);

SubscriptionCostAnalysis _analyzeUnchanged(
  SubscriptionRecord subscription, {
  required DateTime startMonth,
  required DateTime endMonth,
  List<SubscriptionExpenseRecord> expenses = const [],
}) {
  final subscriptionBefore = jsonEncode(subscription.toEncryptedPayloadJson());
  final expensesBefore = jsonEncode(
    expenses.map((expense) => expense.toEncryptedPayloadJson()).toList(),
  );
  final analysis = SubscriptionCostAnalysis.build(
    subscriptions: [subscription],
    expenses: expenses,
    range: SubscriptionCostRange(startMonth: startMonth, endMonth: endMonth),
    today: DateTime(2026, 9, 3),
  );
  expect(
    jsonEncode(subscription.toEncryptedPayloadJson()),
    subscriptionBefore,
    reason: '统计不能修改保存的日期、周期、金额、状态或续费历史',
  );
  expect(
    jsonEncode(
      expenses.map((expense) => expense.toEncryptedPayloadJson()).toList(),
    ),
    expensesBefore,
    reason: '统计不能修改已记录付款的金额、日期与账期',
  );
  return analysis;
}

String _total(SubscriptionCostAnalysis analysis) => analysis
    .currencyTotals(SubscriptionCostBasis.confirmed)
    .single
    .formattedAmount;
