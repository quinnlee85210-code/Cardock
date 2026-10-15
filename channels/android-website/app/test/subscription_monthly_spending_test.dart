import 'dart:convert';

import 'package:account_subscription_manager/features/subscriptions/domain/subscription_cost_summary.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_expense_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter_test/flutter_test.dart';

final _today = DateTime(2026, 9, 3);

void main() {
  group('按付款账期统计每月订阅支出', () {
    test('月费200季度600年费1200均在付款月份计全额并补齐过去正常续费', () {
      final subscriptions = _mixedSubscriptions();
      final analysis = _analyze(
        subscriptions,
        expenses: subscriptions.map(_entry),
        start: DateTime(2026, 1),
        end: DateTime(2026, 12),
      );

      expect(_monthlyTotals(analysis, SubscriptionCostBasis.confirmed), {
        '2026-01': '200',
        '2026-02': '800',
        '2026-03': '200',
        '2026-04': '200',
        '2026-05': '800',
        '2026-06': '200',
        '2026-07': '200',
        '2026-08': '2000',
      });
      expect(_monthlyTotals(analysis, SubscriptionCostBasis.futureEstimate), {
        '2026-09': '200',
        '2026-10': '200',
        '2026-11': '800',
        '2026-12': '200',
      });
      expect(
        analysis
            .currencyTotals(SubscriptionCostBasis.confirmed)
            .single
            .formattedAmount,
        '4600',
      );
      expect(
        analysis
            .currencyTotals(SubscriptionCostBasis.futureEstimate)
            .single
            .formattedAmount,
        '1400',
      );
      expect(
        analysis.lines
            .where((line) => line.subscriptionId == 'annual')
            .map((line) => formatSubscriptionDate(line.date)),
        ['2026-08-20'],
        reason: '年费只在续费月计1200，不应摊为每月100',
      );
    });

    test('首笔不重复过去账期不遗漏且未来尊重保存的下次续费日期', () {
      final subscription = _subscription(
        id: 'monthly',
        first: DateTime(2026, 6, 7),
        next: DateTime(2026, 10, 7),
        amount: '200',
      );
      final analysis = _analyze(
        [subscription],
        expenses: [_entry(subscription)],
        start: DateTime(2026, 6),
        end: DateTime(2026, 10),
      );

      expect(_monthlyTotals(analysis, SubscriptionCostBasis.confirmed), {
        '2026-06': '200',
        '2026-07': '200',
        '2026-08': '200',
      });
      expect(_monthlyTotals(analysis, SubscriptionCostBasis.futureEstimate), {
        '2026-10': '200',
      });
      expect(analysis.lines, hasLength(4));
    });

    test('无账期首笔流水占用首次日期而旧续费历史不能再派生同一期', () {
      final subscription = _subscription(
        id: 'entry-overlapping-history',
        first: DateTime(2026, 6, 1),
        next: DateTime(2026, 6, 1),
        amount: '20',
      ).markRenewed(recordedOn: DateTime(2026, 6, 3));
      final initialPayment = _expense(
        id: 'entry-without-scheduled-date',
        subscription: subscription,
        occurred: DateTime(2026, 6, 1),
        amount: '20',
        source: SubscriptionExpenseSource.subscriptionEntry,
      );
      final analysis = _analyze(
        [subscription],
        expenses: [initialPayment],
        start: DateTime(2026, 6),
        end: DateTime(2026, 6),
      );

      expect(_monthlyTotals(analysis, SubscriptionCostBasis.confirmed), {
        '2026-06': '20',
      });
      expect(analysis.lines, hasLength(1));
      expect(analysis.lines.single.date, DateTime(2026, 6, 1));
      expect(analysis.lines.single.fromSchedule, isFalse);
    });

    test('首笔来源已有明确账期时跨月付款不占用实际付款日的另一期续费', () {
      final subscription = _subscription(
        id: 'entry-with-explicit-cycle',
        first: DateTime(2026, 6, 1),
        next: DateTime(2026, 10, 1),
        amount: '20',
      );
      final initialPayment = _expense(
        id: 'entry-paid-in-later-month',
        subscription: subscription,
        occurred: DateTime(2026, 9, 1),
        scheduled: DateTime(2026, 8, 1),
        amount: '15',
        source: SubscriptionExpenseSource.subscriptionEntry,
      );
      final analysis = _analyze(
        [subscription],
        expenses: [initialPayment],
        start: DateTime(2026, 8),
        end: DateTime(2026, 9),
      );

      expect(_monthlyTotals(analysis, SubscriptionCostBasis.confirmed), {
        '2026-09': '35',
      });
      expect(analysis.lines, hasLength(2));
      expect(analysis.lines.map((line) => line.scheduledOn).toSet(), {
        DateTime(2026, 8, 1),
        DateTime(2026, 9, 1),
      });
      expect(analysis.lines.map((line) => line.amount).toSet(), {'15', '20'});
    });

    test('正常状态的下次日期虽已过期仍按账期补齐每月并区分未来且不改原日期', () {
      final subscription = _subscription(
        id: 'overdue-next-date',
        first: DateTime(2026, 5, 7),
        next: DateTime(2026, 6, 7),
        amount: '200',
      );
      final original = jsonEncode(subscription.toEncryptedPayloadJson());
      final analysis = _analyze(
        [subscription],
        expenses: [_entry(subscription)],
        start: DateTime(2026, 6),
        end: DateTime(2026, 10),
      );

      expect(_monthlyTotals(analysis, SubscriptionCostBasis.confirmed), {
        '2026-06': '200',
        '2026-07': '200',
        '2026-08': '200',
      });
      expect(_monthlyTotals(analysis, SubscriptionCostBasis.futureEstimate), {
        '2026-09': '200',
        '2026-10': '200',
      });
      expect(analysis.lines, hasLength(5));
      expect(jsonEncode(subscription.toEncryptedPayloadJson()), original);
      expect(subscription.nextRenewalOn, DateTime(2026, 6, 7));
    });

    test('日和周周期跨三月夏令时日历边界仍逐次完整计入正确日期', () {
      final daily = _subscription(
        id: 'two-day-cycle',
        first: DateTime(2026, 3, 1),
        next: DateTime(2026, 4, 2),
        amount: '1',
        cycleCount: 2,
        cycleUnit: SubscriptionCycleUnit.day,
      );
      final weekly = _subscription(
        id: 'week-cycle',
        first: DateTime(2026, 3, 1),
        next: DateTime(2026, 4, 5),
        amount: '10',
        cycleUnit: SubscriptionCycleUnit.week,
      );
      final analysis = _analyze(
        [daily, weekly],
        expenses: [_entry(daily), _entry(weekly)],
        start: DateTime(2026, 3),
        end: DateTime(2026, 3),
      );

      expect(
        analysis.lines
            .where((line) => line.subscriptionId == daily.id)
            .map((line) => formatSubscriptionDate(line.date)),
        [
          '2026-03-01',
          '2026-03-03',
          '2026-03-05',
          '2026-03-07',
          '2026-03-09',
          '2026-03-11',
          '2026-03-13',
          '2026-03-15',
          '2026-03-17',
          '2026-03-19',
          '2026-03-21',
          '2026-03-23',
          '2026-03-25',
          '2026-03-27',
          '2026-03-29',
          '2026-03-31',
        ],
      );
      expect(
        analysis.lines
            .where((line) => line.subscriptionId == weekly.id)
            .map((line) => formatSubscriptionDate(line.date)),
        ['2026-03-01', '2026-03-08', '2026-03-15', '2026-03-22', '2026-03-29'],
      );
      expect(analysis.forBasis(SubscriptionCostBasis.futureEstimate), isEmpty);
      expect(
        analysis
            .currencyTotals(SubscriptionCostBasis.confirmed)
            .single
            .formattedAmount,
        '66',
      );
    });

    test('明确关联账期的跨月付款按真实记录金额币种入账且不双计', () {
      final subscription = _subscription(
        id: 'late-paid',
        first: DateTime(2026, 1, 31),
        next: DateTime(2026, 9, 30),
        amount: '20',
      );
      final payment = _expense(
        id: 'late-payment',
        subscription: subscription,
        occurred: DateTime(2026, 9, 2),
        scheduled: DateTime(2026, 8, 31),
        amount: '19.5',
        currency: 'USD',
      );
      final august = _analyze(
        [subscription],
        expenses: [payment],
        start: DateTime(2026, 8),
        end: DateTime(2026, 8),
      );
      final september = _analyze(
        [subscription],
        expenses: [payment],
        start: DateTime(2026, 9),
        end: DateTime(2026, 9),
      );

      expect(august.lines, isEmpty);
      final confirmed = september.forBasis(SubscriptionCostBasis.confirmed);
      expect(confirmed, hasLength(1));
      expect(confirmed.single.date, DateTime(2026, 9, 2));
      expect(confirmed.single.scheduledOn, DateTime(2026, 8, 31));
      expect(confirmed.single.amount, '19.5');
      expect(confirmed.single.currency, 'USD');
      final future = september.forBasis(SubscriptionCostBasis.futureEstimate);
      expect(future, hasLength(1));
      expect(future.single.date, DateTime(2026, 9, 30));
      expect(future.single.amount, '20');
      expect(future.single.currency, 'CNY');
    });

    test('提前一个月支付也只覆盖指定的一期续费', () {
      final subscription = _subscription(
        id: 'early-paid',
        first: DateTime(2026, 1, 10),
        next: DateTime(2026, 9, 10),
        amount: '200',
      );
      final payment = _expense(
        id: 'early-payment',
        subscription: subscription,
        occurred: DateTime(2026, 7, 31),
        scheduled: DateTime(2026, 8, 10),
        amount: '175',
      );
      final analysis = _analyze(
        [subscription],
        expenses: [payment],
        start: DateTime(2026, 7),
        end: DateTime(2026, 8),
      );

      expect(_monthlyTotals(analysis, SubscriptionCostBasis.confirmed), {
        '2026-07': '375',
      });
      expect(
        analysis.lines.where(
          (line) => line.scheduledOn == DateTime(2026, 8, 10),
        ),
        hasLength(1),
      );
    });

    test('退款按退款月份扣减且关联原账期不能抑制正常续费金额', () {
      final subscription = _subscription(
        id: 'refund',
        first: DateTime(2026, 1, 10),
        next: DateTime(2026, 9, 10),
        amount: '200',
      );
      final refund = _expense(
        id: 'refund-1',
        subscription: subscription,
        occurred: DateTime(2026, 8, 22),
        scheduled: DateTime(2026, 7, 10),
        amount: '50',
        kind: SubscriptionExpenseKind.refund,
      );
      final analysis = _analyze(
        [subscription],
        expenses: [refund],
        start: DateTime(2026, 7),
        end: DateTime(2026, 8),
      );

      expect(_monthlyTotals(analysis, SubscriptionCostBasis.confirmed), {
        '2026-07': '200',
        '2026-08': '150',
      });
      expect(analysis.lines.where((line) => line.refund), hasLength(1));
      expect(analysis.lines, hasLength(3));
    });

    test('未注明账期的手工补充付款不得凭相同月份金额吞掉正常续费', () {
      final subscription = _subscription(
        id: 'supplement',
        first: DateTime(2026, 1, 10),
        next: DateTime(2026, 9, 10),
        amount: '200',
      );
      final supplemental = _expense(
        id: 'supplement-payment',
        subscription: subscription,
        occurred: DateTime(2026, 8, 17),
        amount: '200',
      );
      final analysis = _analyze(
        [subscription],
        expenses: [supplemental],
        start: DateTime(2026, 8),
        end: DateTime(2026, 8),
      );

      expect(_monthlyTotals(analysis, SubscriptionCostBasis.confirmed), {
        '2026-08': '400',
      });
      expect(analysis.lines, hasLength(2));
    });

    test('数月后无账期补款不会吞掉首月费用且补款月保留正常续费', () {
      final subscription = _subscription(
        id: 'entry-with-later-supplement',
        first: DateTime(2026, 1, 10),
        next: DateTime(2026, 9, 10),
        amount: '200',
      );
      final laterPayment = _expense(
        id: 'later-supplement',
        subscription: subscription,
        occurred: DateTime(2026, 8, 17),
        amount: '35',
      );
      final analysis = _analyze(
        [subscription],
        expenses: [laterPayment],
        start: DateTime(2026, 1),
        end: DateTime(2026, 8),
      );

      expect(_monthlyTotals(analysis, SubscriptionCostBasis.confirmed), {
        '2026-01': '200',
        '2026-02': '200',
        '2026-03': '200',
        '2026-04': '200',
        '2026-05': '200',
        '2026-06': '200',
        '2026-07': '200',
        '2026-08': '235',
      });
      expect(analysis.lines, hasLength(9));
    });

    test('相同服务名的不同订阅按各自ID统计且付款只覆盖对应账号订阅', () {
      final first = _subscription(
        id: 'same-service-a',
        serviceName: '相同服务',
        accountId: 'account-a',
        first: DateTime(2026, 1, 5),
        next: DateTime(2026, 9, 5),
        amount: '20',
      );
      final second = _subscription(
        id: 'same-service-b',
        serviceName: '相同服务',
        accountId: 'account-b',
        first: DateTime(2026, 1, 5),
        next: DateTime(2026, 9, 5),
        amount: '30',
      );
      final analysis = _analyze(
        [first, second],
        expenses: [
          _expense(
            id: 'same-service-payment',
            subscription: first,
            occurred: DateTime(2026, 8, 5),
            scheduled: DateTime(2026, 8, 5),
            amount: '15',
          ),
        ],
        start: DateTime(2026, 8),
        end: DateTime(2026, 8),
      );

      expect(_monthlyTotals(analysis, SubscriptionCostBasis.confirmed), {
        '2026-08': '45',
      });
      expect(analysis.lines, hasLength(2));
      expect(analysis.lines.map((line) => line.subscriptionId).toSet(), {
        first.id,
        second.id,
      });
    });

    test('没有金额的过去账期保留缺失项而不是伪造零费用', () {
      final subscription = _subscription(
        id: 'missing-amount',
        first: DateTime(2026, 6, 8),
        next: DateTime(2026, 9, 8),
      );
      final analysis = _analyze(
        [subscription],
        start: DateTime(2026, 6),
        end: DateTime(2026, 9),
      );

      final confirmed = analysis.forBasis(SubscriptionCostBasis.confirmed);
      expect(confirmed, hasLength(3));
      expect(confirmed.every((line) => line.amount == null), isTrue);
      expect(analysis.currencyTotals(SubscriptionCostBasis.confirmed), isEmpty);
      expect(
        analysis
            .cnyEstimate(SubscriptionCostBasis.confirmed)
            .missingAmountCount,
        3,
      );
      expect(
        analysis.cnyEstimate(SubscriptionCostBasis.confirmed).convertedCount,
        0,
      );
      final future = analysis.forBasis(SubscriptionCostBasis.futureEstimate);
      expect(future, hasLength(1));
      expect(future.single.amount, isNull);
    });

    test('明确录入的零费用与缺失金额保持不同', () {
      final subscription = _subscription(
        id: 'zero-amount',
        first: DateTime(2026, 8, 8),
        next: DateTime(2026, 9, 8),
        amount: '0',
      );
      final analysis = _analyze(
        [subscription],
        expenses: [_entry(subscription)],
        start: DateTime(2026, 8),
        end: DateTime(2026, 8),
      );

      expect(analysis.lines, hasLength(1));
      expect(analysis.lines.single.amount, '0');
      expect(
        analysis
            .currencyTotals(SubscriptionCostBasis.confirmed)
            .single
            .formattedAmount,
        '0',
      );
      expect(
        analysis
            .cnyEstimate(SubscriptionCostBasis.confirmed)
            .missingAmountCount,
        0,
      );
    });

    test('固定30日账期经过二月后仍回到30日且不被后续月末反向改为31日', () {
      final subscription = _subscription(
        id: 'day-30',
        first: DateTime(2026, 1, 30),
        next: DateTime(2026, 9, 30),
        amount: '1',
      );
      final analysis = _analyze(
        [subscription],
        expenses: [_entry(subscription)],
        start: DateTime(2026, 1),
        end: DateTime(2026, 9),
      );

      expect(analysis.lines.map((line) => formatSubscriptionDate(line.date)), [
        '2026-01-30',
        '2026-02-28',
        '2026-03-30',
        '2026-04-30',
        '2026-05-30',
        '2026-06-30',
        '2026-07-30',
        '2026-08-30',
        '2026-09-30',
      ]);
    });

    test('31日月末账期在长短月份均按同一月末锚点产生一次费用', () {
      final subscription = _subscription(
        id: 'month-end',
        first: DateTime(2026, 1, 31),
        next: DateTime(2026, 9, 30),
        amount: '1',
      );
      final analysis = _analyze(
        [subscription],
        expenses: [_entry(subscription)],
        start: DateTime(2026, 1),
        end: DateTime(2026, 9),
      );

      expect(analysis.lines.map((line) => formatSubscriptionDate(line.date)), [
        '2026-01-31',
        '2026-02-28',
        '2026-03-31',
        '2026-04-30',
        '2026-05-31',
        '2026-06-30',
        '2026-07-31',
        '2026-08-31',
        '2026-09-30',
      ]);
    });

    test('闰年2月29日年度账期在下一闰年恢复29日并区分过去未来', () {
      final subscription = _subscription(
        id: 'leap-year',
        first: DateTime(2024, 2, 29),
        next: DateTime(2027, 2, 28),
        amount: '1200',
        cycleUnit: SubscriptionCycleUnit.year,
      );
      final analysis = _analyze(
        [subscription],
        expenses: [_entry(subscription)],
        start: DateTime(2024, 1),
        end: DateTime(2028, 12),
      );

      expect(
        analysis
            .forBasis(SubscriptionCostBasis.confirmed)
            .map((line) => formatSubscriptionDate(line.date)),
        ['2024-02-29', '2025-02-28', '2026-02-28'],
      );
      expect(
        analysis
            .forBasis(SubscriptionCostBasis.futureEstimate)
            .map((line) => formatSubscriptionDate(line.date)),
        ['2027-02-28', '2028-02-29'],
      );
    });

    test('旧续费历史没有费用流水时仍完整计入对应月份且每一期不重复', () {
      final subscription =
          _subscription(
                id: 'old-renewal-history',
                first: DateTime(2026, 6, 1),
                next: DateTime(2026, 7, 1),
                amount: '200',
              )
              .markRenewed(recordedOn: DateTime(2026, 7, 3))
              .markRenewed(recordedOn: DateTime(2026, 8, 2));
      final analysis = _analyze(
        [subscription],
        expenses: [_entry(subscription)],
        start: DateTime(2026, 6),
        end: DateTime(2026, 8),
      );

      expect(_monthlyTotals(analysis, SubscriptionCostBasis.confirmed), {
        '2026-06': '200',
        '2026-07': '200',
        '2026-08': '200',
      });
      expect(analysis.lines, hasLength(3));
      expect(subscription.renewalHistory, hasLength(2));
    });

    test('任意自选月份与全年结果中同月份逐笔一致并且不改原订阅和流水JSON', () {
      final subscriptions = _mixedSubscriptions();
      final expenses = [
        ...subscriptions.map(_entry),
        _expense(
          id: 'shifted-quarter',
          subscription: subscriptions[1],
          occurred: DateTime(2026, 4, 30),
          scheduled: DateTime(2026, 5, 15),
          amount: '550',
        ),
        _expense(
          id: 'later-refund',
          subscription: subscriptions[2],
          occurred: DateTime(2026, 9, 2),
          scheduled: DateTime(2026, 8, 20),
          amount: '100',
          kind: SubscriptionExpenseKind.refund,
        ),
      ];
      final originalSubscriptions = jsonEncode([
        for (final subscription in subscriptions)
          subscription.toEncryptedPayloadJson(),
      ]);
      final originalExpenses = jsonEncode([
        for (final expense in expenses) expense.toEncryptedPayloadJson(),
      ]);
      final wholeYear = _analyze(
        subscriptions,
        expenses: expenses,
        start: DateTime(2026, 1),
        end: DateTime(2026, 12),
      );
      expect(wholeYear.lines, isNotEmpty);

      for (var month = 1; month <= 12; month++) {
        final selected = _analyze(
          subscriptions,
          expenses: expenses,
          start: DateTime(2026, month),
          end: DateTime(2026, month),
        );
        final fromYear = wholeYear.lines.where(
          (line) => line.date.year == 2026 && line.date.month == month,
        );
        expect(
          selected.lines.map(_lineFingerprint).toList()..sort(),
          fromYear.map(_lineFingerprint).toList()..sort(),
          reason: '自选2026年$month月须与全年拆分相同',
        );
      }
      expect(
        jsonEncode([
          for (final subscription in subscriptions)
            subscription.toEncryptedPayloadJson(),
        ]),
        originalSubscriptions,
      );
      expect(
        jsonEncode([
          for (final expense in expenses) expense.toEncryptedPayloadJson(),
        ]),
        originalExpenses,
      );
    });
  });
}

List<SubscriptionRecord> _mixedSubscriptions() => [
  _subscription(
    id: 'monthly',
    first: DateTime(2026, 1, 10),
    next: DateTime(2026, 9, 10),
    amount: '200',
  ),
  _subscription(
    id: 'quarterly',
    first: DateTime(2026, 2, 15),
    next: DateTime(2026, 11, 15),
    cycleCount: 3,
    amount: '600',
  ),
  _subscription(
    id: 'annual',
    first: DateTime(2025, 8, 20),
    next: DateTime(2027, 8, 20),
    cycleUnit: SubscriptionCycleUnit.year,
    amount: '1200',
  ),
];

SubscriptionRecord _subscription({
  required String id,
  required DateTime first,
  required DateTime next,
  String? serviceName,
  String? accountId,
  String? amount,
  int cycleCount = 1,
  SubscriptionCycleUnit cycleUnit = SubscriptionCycleUnit.month,
}) => SubscriptionRecord.fromDraft(
  id: id,
  draft: SubscriptionDraft(
    accountId: accountId,
    details: SubscriptionDetailsDraft(
      serviceName: serviceName ?? id,
      firstSubscribedOn: first,
      nextRenewalOn: next,
      amount: amount,
      cycleCount: cycleCount,
      cycleUnit: cycleUnit,
    ),
  ),
);

SubscriptionExpenseRecord _entry(SubscriptionRecord subscription) => _expense(
  id: 'entry-${subscription.id}',
  subscription: subscription,
  occurred: subscription.firstSubscribedOn,
  scheduled: subscription.firstSubscribedOn,
  amount: subscription.amount!,
  source: SubscriptionExpenseSource.subscriptionEntry,
);

SubscriptionExpenseRecord _expense({
  required String id,
  required SubscriptionRecord subscription,
  required DateTime occurred,
  required String amount,
  DateTime? scheduled,
  String currency = 'CNY',
  SubscriptionExpenseKind kind = SubscriptionExpenseKind.payment,
  SubscriptionExpenseSource source = SubscriptionExpenseSource.manual,
}) => SubscriptionExpenseRecord.fromDraft(
  id: id,
  draft: SubscriptionExpenseDraft(
    subscriptionId: subscription.id,
    accountId: subscription.accountId,
    serviceName: subscription.serviceName,
    occurredOn: occurred,
    scheduledRenewalOn: scheduled,
    amount: amount,
    currency: currency,
    kind: kind,
  ),
  recordedAtUtc: DateTime.utc(2026, 9, 3, 12),
  source: source,
);

SubscriptionCostAnalysis _analyze(
  Iterable<SubscriptionRecord> subscriptions, {
  Iterable<SubscriptionExpenseRecord> expenses = const [],
  required DateTime start,
  required DateTime end,
}) => SubscriptionCostAnalysis.build(
  subscriptions: subscriptions,
  expenses: expenses,
  range: SubscriptionCostRange(startMonth: start, endMonth: end),
  today: _today,
);

Map<String, String> _monthlyTotals(
  SubscriptionCostAnalysis analysis,
  SubscriptionCostBasis basis,
) => {
  for (final month in analysis.byMonth(basis).entries)
    month.key: formatScaledSubscriptionAmount(
      month.value.fold<BigInt>(BigInt.zero, (total, line) {
        expect(line.currency, 'CNY');
        expect(line.amount, isNotNull);
        final amount = parseScaledSubscriptionAmount(line.amount!);
        return total + (line.refund ? -amount : amount);
      }),
    ),
};

String _lineFingerprint(SubscriptionCostLine line) => jsonEncode([
  line.basis.name,
  line.subscriptionId,
  formatSubscriptionDate(line.date),
  line.scheduledOn == null ? null : formatSubscriptionDate(line.scheduledOn!),
  line.serviceName,
  line.currency,
  line.amount,
  line.refund,
]);
