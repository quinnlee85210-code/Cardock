import 'package:account_subscription_manager/core/exchange_rates/semiannual_cny_exchange_rates.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_cost_summary.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_expense_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('订阅费用统计', () {
    test('确认支出与退款按四位小数精确相减并保留分类快照', () {
      final expenses = <SubscriptionExpenseRecord>[
        _expense(
          id: 'expense-1',
          serviceName: '云服务旧名称',
          occurredOn: DateTime(2026, 2, 10),
          amount: '10.1234',
          expenseCategory: '工作-当时快照',
        ),
        _expense(
          id: 'expense-2',
          serviceName: '云服务旧名称',
          occurredOn: DateTime(2026, 2, 12),
          amount: '0.1234',
          kind: SubscriptionExpenseKind.refund,
          expenseCategory: '退款-当时快照',
        ),
      ];

      final analysis = SubscriptionCostAnalysis.build(
        subscriptions: const <SubscriptionRecord>[],
        expenses: expenses,
        range: SubscriptionCostRange(
          startMonth: DateTime(2026, 1),
          endMonth: DateTime(2026, 12),
        ),
        today: DateTime(2026, 12, 31),
      );

      expect(analysis.forBasis(SubscriptionCostBasis.confirmed), hasLength(2));
      final totals = analysis.currencyTotals(SubscriptionCostBasis.confirmed);
      expect(totals, hasLength(1));
      expect(totals.single.currency, 'CNY');
      expect(totals.single.scaledAmount, BigInt.from(100000));
      expect(totals.single.formattedAmount, '10');
      expect(
        analysis.byCategory(SubscriptionCostBasis.confirmed).keys,
        containsAll(<String>['工作-当时快照', '退款-当时快照']),
      );
      expect(
        analysis.byMonth(SubscriptionCostBasis.confirmed)['2026-02'],
        hasLength(2),
      );

      final cny = analysis.cnyEstimate(SubscriptionCostBasis.confirmed);
      expect(cny.convertedCount, 2);
      expect(cny.excludedCount, 0);
      expect(cny.totalCny, closeTo(10, 0.0000001));
    });

    test('确认付款不重复计入未来预测且不再回算旧续费', () {
      final renewed = _subscription(
        id: 'subscription-covered',
        nextRenewalOn: DateTime(2026, 6, 1),
        amount: '9.9',
        expenseCategory: '当前分类',
      ).markRenewed(recordedOn: DateTime(2026, 6, 2));
      final expenses = <SubscriptionExpenseRecord>[
        _expense(
          id: 'expense-1',
          subscriptionId: renewed.id,
          serviceName: '续费时服务名',
          occurredOn: DateTime(2026, 6, 2),
          scheduledRenewalOn: DateTime(2026, 6, 1),
          amount: '8.8',
          expenseCategory: '历史分类快照',
        ),
        _expense(
          id: 'expense-2',
          subscriptionId: renewed.id,
          serviceName: '续费时服务名',
          occurredOn: DateTime(2026, 7, 3),
          scheduledRenewalOn: DateTime(2026, 7, 1),
          amount: '10.5',
          expenseCategory: '七月分类快照',
        ),
      ];

      final analysis = SubscriptionCostAnalysis.build(
        subscriptions: <SubscriptionRecord>[renewed],
        expenses: expenses,
        range: SubscriptionCostRange(
          startMonth: DateTime(2026, 6),
          endMonth: DateTime(2026, 8),
        ),
        today: DateTime(2026, 6, 1),
      );

      expect(analysis.forBasis(SubscriptionCostBasis.confirmed), hasLength(2));
      expect(SubscriptionCostBasis.values, hasLength(2));
      final future = analysis.forBasis(SubscriptionCostBasis.futureEstimate);
      expect(future, hasLength(1));
      expect(future.single.date, DateTime(2026, 8, 1));
      expect(future.single.expenseCategory, '当前分类');
      expect(
        analysis.byCategory(SubscriptionCostBasis.confirmed).keys,
        containsAll(<String>['历史分类快照', '七月分类快照']),
      );
    });

    test('日周期与周周期会列出统计月份内的每次未来续费', () {
      final daily = _subscription(
        id: 'subscription-daily',
        nextRenewalOn: DateTime(2026, 9, 1),
        cycleCount: 2,
        cycleUnit: SubscriptionCycleUnit.day,
        amount: '1',
      );
      final weekly = _subscription(
        id: 'subscription-weekly',
        nextRenewalOn: DateTime(2026, 9, 1),
        cycleUnit: SubscriptionCycleUnit.week,
        amount: '2',
      );

      final analysis = SubscriptionCostAnalysis.build(
        subscriptions: <SubscriptionRecord>[daily, weekly],
        expenses: const <SubscriptionExpenseRecord>[],
        range: SubscriptionCostRange(
          startMonth: DateTime(2026, 9),
          endMonth: DateTime(2026, 9),
        ),
        today: DateTime(2026, 9, 1),
      );
      final future = analysis.forBasis(SubscriptionCostBasis.futureEstimate);

      expect(
        future.where((line) => line.serviceName == 'subscription-daily'),
        hasLength(15),
      );
      expect(
        future.where((line) => line.serviceName == 'subscription-weekly'),
        hasLength(5),
      );
      expect(future, hasLength(20));
      expect(
        analysis
            .currencyTotals(SubscriptionCostBasis.futureEstimate)
            .single
            .formattedAmount,
        '25',
      );
    });

    test('远古日周期续费日可直接快进到统计区间且不丢失日期', () {
      final ancient = _subscription(
        id: 'subscription-ancient',
        firstSubscribedOn: DateTime(1970, 1, 1),
        nextRenewalOn: DateTime(1970, 1, 1),
        cycleUnit: SubscriptionCycleUnit.day,
        amount: '0.0001',
      );

      final analysis = SubscriptionCostAnalysis.build(
        subscriptions: <SubscriptionRecord>[ancient],
        expenses: const <SubscriptionExpenseRecord>[],
        range: SubscriptionCostRange(
          startMonth: DateTime(2026, 9),
          endMonth: DateTime(2026, 9),
        ),
        today: DateTime(2026, 9, 1),
      );
      final future = analysis.forBasis(SubscriptionCostBasis.futureEstimate);

      expect(future, hasLength(30));
      expect(future.first.date, DateTime(2026, 9, 1));
      expect(future.last.date, DateTime(2026, 9, 30));
      expect(
        analysis
            .currencyTotals(SubscriptionCostBasis.futureEstimate)
            .single
            .formattedAmount,
        '0.003',
      );
    });

    test('金额解析严格限制四位小数且不经过浮点累计', () {
      expect(parseScaledSubscriptionAmount('0'), BigInt.zero);
      expect(parseScaledSubscriptionAmount('1.2'), BigInt.from(12000));
      expect(
        parseScaledSubscriptionAmount('999999999999.9999'),
        BigInt.parse('9999999999999999'),
      );
      expect(formatScaledSubscriptionAmount(BigInt.from(-12000)), '-1.2');

      for (final invalid in <String>[
        '-1',
        '01',
        '.5',
        '1.',
        '1.00000',
        '1e2',
        '1000000000000',
      ]) {
        expect(
          () => parseScaledSubscriptionAmount(invalid),
          throwsArgumentError,
          reason: invalid,
        );
        expect(
          () => SubscriptionExpenseDraft(
            subscriptionId: null,
            serviceName: '非法金额测试',
            occurredOn: DateTime(2026, 1, 1),
            amount: invalid,
            currency: 'CNY',
            kind: SubscriptionExpenseKind.payment,
          ),
          throwsArgumentError,
          reason: invalid,
        );
      }
    });

    test('人民币参考折算继续使用既有2026上半年离线汇率快照', () {
      final usd = _expense(
        id: 'expense-usd',
        serviceName: '美元订阅',
        occurredOn: DateTime(2026, 4, 1),
        amount: '2',
        currency: 'USD',
      );
      final analysis = SubscriptionCostAnalysis.build(
        subscriptions: const <SubscriptionRecord>[],
        expenses: <SubscriptionExpenseRecord>[usd],
        range: SubscriptionCostRange(
          startMonth: DateTime(2026, 4),
          endMonth: DateTime(2026, 4),
        ),
        today: DateTime(2026, 4, 30),
      );

      expect(SemiannualCnyExchangeRates.periodLabel, '2026上半年');
      expect(SemiannualCnyExchangeRates.snapshotId, 'cny-2026-h1-v1');
      final estimate = analysis.cnyEstimate(SubscriptionCostBasis.confirmed);
      expect(estimate.convertedCount, 1);
      expect(estimate.totalCny, isPositive);
      expect(
        SemiannualCnyExchangeRates.convertToCny(currency: 'USD', amount: 2),
        isNotNull,
      );
    });
  });
}

SubscriptionRecord _subscription({
  required String id,
  DateTime? firstSubscribedOn,
  required DateTime nextRenewalOn,
  int cycleCount = 1,
  SubscriptionCycleUnit cycleUnit = SubscriptionCycleUnit.month,
  String? amount,
  String? expenseCategory,
}) => SubscriptionRecord.fromDraft(
  id: id,
  draft: SubscriptionDraft(
    accountId: null,
    details: SubscriptionDetailsDraft(
      serviceName: id,
      firstSubscribedOn: firstSubscribedOn ?? DateTime(2026, 1, 1),
      nextRenewalOn: nextRenewalOn,
      cycleCount: cycleCount,
      cycleUnit: cycleUnit,
      amount: amount,
      expenseCategory: expenseCategory,
    ),
  ),
);

SubscriptionExpenseRecord _expense({
  required String id,
  String? subscriptionId,
  required String serviceName,
  required DateTime occurredOn,
  required String amount,
  String currency = 'CNY',
  SubscriptionExpenseKind kind = SubscriptionExpenseKind.payment,
  String? expenseCategory,
  DateTime? scheduledRenewalOn,
}) => SubscriptionExpenseRecord.fromDraft(
  id: id,
  draft: SubscriptionExpenseDraft(
    subscriptionId: subscriptionId,
    serviceName: serviceName,
    occurredOn: occurredOn,
    amount: amount,
    currency: currency,
    kind: kind,
    expenseCategory: expenseCategory,
    scheduledRenewalOn: scheduledRenewalOn,
  ),
  recordedAtUtc: DateTime.utc(2026, 9, 1, 12),
);
