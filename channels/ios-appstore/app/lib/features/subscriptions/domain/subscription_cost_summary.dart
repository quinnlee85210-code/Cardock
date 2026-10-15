import 'subscription_price_calendar.dart';
import '../../../core/exchange_rates/semiannual_cny_exchange_rates.dart';
import '../../accounts/domain/account_record.dart';
import 'subscription_expense_automation.dart';
import 'subscription_expense_record.dart';
import 'subscription_record.dart';

enum SubscriptionCostBasis { confirmed, futureEstimate }

final class SubscriptionCostRange {
  factory SubscriptionCostRange({
    required DateTime startMonth,
    required DateTime endMonth,
  }) {
    final start = DateTime(startMonth.year, startMonth.month);
    final end = DateTime(endMonth.year, endMonth.month);
    if (end.isBefore(start)) {
      throw ArgumentError('结束月份不能早于开始月份');
    }
    return SubscriptionCostRange._(
      start: start,
      endExclusive: DateTime(end.year, end.month + 1),
    );
  }

  const SubscriptionCostRange._({
    required this.start,
    required this.endExclusive,
  });

  final DateTime start;
  final DateTime endExclusive;

  bool contains(DateTime value) =>
      !value.isBefore(start) && value.isBefore(endExclusive);
}

final class SubscriptionCostLine {
  const SubscriptionCostLine({
    required this.basis,
    required this.date,
    required this.serviceName,
    required this.currency,
    required this.amount,
    required this.refund,
    required this.expenseCategory,
    this.accountLabel,
    this.expenseId,
    this.subscriptionId,
    this.scheduledOn,
    this.planName,
    this.cycleCount,
    this.cycleUnit,
    this.fromSchedule = false,
  });

  final SubscriptionCostBasis basis;
  final DateTime date;
  final String serviceName;
  final String currency;
  final String? amount;
  final bool refund;
  final String? expenseCategory;
  final String? accountLabel;
  final String? expenseId;
  final String? subscriptionId;
  final DateTime? scheduledOn;
  final String? planName;
  final int? cycleCount;
  final SubscriptionCycleUnit? cycleUnit;
  final bool fromSchedule;
}

final class SubscriptionCurrencyTotal {
  const SubscriptionCurrencyTotal({
    required this.currency,
    required this.scaledAmount,
  });

  final String currency;
  final BigInt scaledAmount;

  String get formattedAmount => formatScaledSubscriptionAmount(scaledAmount);
}

final class SubscriptionCnyEstimate {
  const SubscriptionCnyEstimate({
    required this.totalCny,
    required this.convertedCount,
    required this.missingAmountCount,
    required this.unsupportedCurrencyCount,
  });

  final double totalCny;
  final int convertedCount;
  final int missingAmountCount;
  final int unsupportedCurrencyCount;

  int get excludedCount => missingAmountCount + unsupportedCurrencyCount;
}

final class SubscriptionCostAnalysis {
  SubscriptionCostAnalysis._(this.lines, this.gaps);

  factory SubscriptionCostAnalysis.build({
    required Iterable<SubscriptionRecord> subscriptions,
    required Iterable<SubscriptionExpenseRecord> expenses,
    required SubscriptionCostRange range,
    DateTime? today,
    Iterable<AccountRecord> accounts = const [],
  }) {
    final nowDate = subscriptionDateOnly(today ?? DateTime.now());
    final subscriptionList = subscriptions.toList(growable: false);
    final expenseList = expenses.toList(growable: false);
    final lines = <SubscriptionCostLine>[];
    final gaps = <SubscriptionCostGap>[];
    final subscriptionsById = {
      for (final subscription in subscriptionList)
        subscription.id: subscription,
    };
    final accountsById = {for (final account in accounts) account.id: account};
    final paidKeys = <String>{};
    final entrySubscriptionIds = <String>{};
    for (final expense in expenseList) {
      if (expense.kind != SubscriptionExpenseKind.payment ||
          expense.subscriptionId == null) {
        continue;
      }
      if (expense.scheduledRenewalOn != null) {
        paidKeys.add(
          _renewalKey(expense.subscriptionId!, expense.scheduledRenewalOn!),
        );
      }
      // Keep the legacy entry convention; unassigned supplemental payments
      // remain separate ledger lines and never consume a recurring period.
      if (expense.source == SubscriptionExpenseSource.subscriptionEntry ||
          (expense.scheduledRenewalOn == null &&
              expense.occurredOn ==
                  subscriptionsById[expense.subscriptionId]
                      ?.firstSubscribedOn) ||
          expense.scheduledRenewalOn ==
              subscriptionsById[expense.subscriptionId]?.firstSubscribedOn) {
        entrySubscriptionIds.add(expense.subscriptionId!);
        if (expense.scheduledRenewalOn == null) {
          paidKeys.add(
            _renewalKey(expense.subscriptionId!, expense.occurredOn),
          );
        }
      }
    }
    for (final expense in expenseList) {
      if (expense.isDeleted || !range.contains(expense.occurredOn)) continue;
      final subscription = subscriptionsById[expense.subscriptionId];
      lines.add(
        SubscriptionCostLine(
          expenseId: expense.id,
          basis: SubscriptionCostBasis.confirmed,
          date: expense.occurredOn,
          serviceName: expense.serviceName,
          currency: expense.currency,
          amount: expense.amount,
          refund: expense.kind == SubscriptionExpenseKind.refund,
          expenseCategory: expense.expenseCategory,
          accountLabel: expense.accountLabel,
          subscriptionId: expense.subscriptionId,
          scheduledOn: expense.scheduledRenewalOn,
          planName: subscription?.planName,
          cycleCount: subscription?.cycleCount,
          cycleUnit: subscription?.cycleUnit,
        ),
      );
    }

    for (final subscription in subscriptionList) {
      // Trial fees and conversion fees are explicit ledger events. No inferred
      // entry charge or backfilled trial periods may enter the historical basis.
      final trial = subscription.management?.trial;
      if (trial != null) {
        if (trial.outcome == TrialOutcome.converted &&
            subscription.status == SubscriptionStatus.active &&
            !subscription.nextRenewalOn.isBefore(nowDate)) {
          final cadence = _BillingCadence(
            subscription,
            subscription.nextRenewalOn,
          );
          for (final date in cadence.between(
            range.start.isAfter(nowDate) ? range.start : nowDate,
            range.endExclusive,
          )) {
            final price = subscription.management?.priceAt(date);
            lines.add(
              SubscriptionCostLine(
                basis: SubscriptionCostBasis.futureEstimate,
                date: date,
                serviceName: subscription.serviceName,
                currency: price?.currency ?? subscription.currency,
                amount: price?.amount ?? subscription.amount,
                refund: false,
                expenseCategory: subscription.expenseCategory,
                accountLabel: null,
                subscriptionId: subscription.id,
                scheduledOn: date,
                planName: subscription.planName,
                cycleCount: price?.cycleCount ?? subscription.cycleCount,
                cycleUnit: price?.cycleUnit ?? subscription.cycleUnit,
                fromSchedule: true,
              ),
            );
          }
        }
        continue;
      }
      final account = accountsById[subscription.accountId];
      final accountLabel = account == null
          ? null
          : subscriptionExpenseAccountLabel(account);
      final usedKeys = <String>{};
      final history = [...subscription.renewalHistory]
        ..sort(
          (left, right) =>
              left.previousRenewalOn.compareTo(right.previousRenewalOn),
        );
      final latestHistoryEnd = history.fold<DateTime>(
        subscription.firstSubscribedOn,
        (latest, event) =>
            event.nextRenewalOn.isAfter(latest) ? event.nextRenewalOn : latest,
      );
      final historyFitsCycle = history.every(
        (event) =>
            _BillingCadence(subscription, event.previousRenewalOn).at(1) ==
            event.nextRenewalOn,
      );
      var generatedCount = 0;
      void add(DateTime scheduled, {DateTime? paidOn, bool entry = false}) {
        final key = _renewalKey(subscription.id, scheduled);
        if (paidKeys.contains(key) || !usedKeys.add(key)) return;
        if (entry && entrySubscriptionIds.contains(subscription.id)) return;
        final date = paidOn ?? scheduled;
        if (!range.contains(date)) return;
        generatedCount += 1;
        if (generatedCount > 5000) {
          throw StateError('费用统计范围内的续费次数超过安全上限');
        }
        lines.add(
          SubscriptionCostLine(
            basis: paidOn != null || entry || date.isBefore(nowDate)
                ? SubscriptionCostBasis.confirmed
                : SubscriptionCostBasis.futureEstimate,
            date: date,
            serviceName: subscription.serviceName,
            currency:
                subscription.management?.priceAt(scheduled)?.currency ??
                subscription.currency,
            amount:
                subscription.management?.priceAt(scheduled)?.amount ??
                subscription.amount,
            refund: false,
            expenseCategory: subscription.expenseCategory ?? account?.category,
            accountLabel: accountLabel,
            subscriptionId: subscription.id,
            scheduledOn: scheduled,
            planName: subscription.planName,
            cycleCount:
                subscription.management?.priceAt(scheduled)?.cycleCount ??
                subscription.cycleCount,
            cycleUnit:
                subscription.management?.priceAt(scheduled)?.cycleUnit ??
                subscription.cycleUnit,
            fromSchedule: true,
          ),
        );
      }

      // Recorded renewals own their billing date even when paid outside the
      // selected range. Never also add that date as a scheduled payment.
      for (final event in history) {
        add(event.previousRenewalOn, paidOn: event.recordedOn);
      }
      add(subscription.firstSubscribedOn, entry: true);
      final pastEnd = subscription.status == SubscriptionStatus.active
          ? nowDate
          : _earlierDate(
              nowDate,
              subscription.cancelledOn ?? subscription.nextRenewalOn,
            );
      void fillHistory(
        DateTime anchor,
        DateTime end, {
        required bool includeAnchor,
      }) {
        if (!end.isAfter(anchor)) return;
        if (subscription.management?.priceHistory.isNotEmpty ?? false) {
          for (final date in subscriptionPriceBillingDates(
            subscription,
            anchor: anchor,
            start: range.start,
            endExclusive: _earlierDate(
              _earlierDate(end, pastEnd),
              range.endExclusive,
            ),
            includeAnchor: includeAnchor,
          )) {
            add(date);
          }
          return;
        }
        final cadence = _cadenceFor(subscription, anchor);
        final anchorIndex = cadence.indexOf(anchor);
        final firstRenewal = cadence.at(anchorIndex + 1);
        // A manually chosen short first period is an explicit date, not an
        // extra full period. Longer inconsistent intervals need source data.
        final shortFirstPeriod =
            !includeAnchor &&
            anchor == subscription.firstSubscribedOn &&
            !end.isAfter(firstRenewal);
        if ((!cadence.contains(end) && !shortFirstPeriod) ||
            (!historyFitsCycle && anchor.isBefore(latestHistoryEnd))) {
          final gapStart = includeAnchor ? anchor : firstRenewal;
          final gapEnd = _earlierDate(end, pastEnd);
          if (gapEnd.isAfter(gapStart) &&
              gapStart.isBefore(range.endExclusive) &&
              gapEnd.isAfter(range.start)) {
            gaps.add(
              SubscriptionCostGap(
                subscriptionId: subscription.id,
                serviceName: subscription.serviceName,
                accountLabel: accountLabel,
                start: gapStart,
                endExclusive: gapEnd,
              ),
            );
          }
          return;
        }
        final stop = _earlierDate(end, pastEnd);
        for (final date in cadence.between(
          range.start,
          _earlierDate(stop, range.endExclusive),
          minimumIndex: anchorIndex + (includeAnchor ? 0 : 1),
        )) {
          add(date);
        }
      }

      var anchor = subscription.firstSubscribedOn;
      var includeAnchor = false;
      for (final event in history) {
        if (event.previousRenewalOn.isBefore(anchor)) {
          // Preserve an explicit record but do not fabricate overlapping
          // schedules from inconsistent historical anchors.
          continue;
        }
        fillHistory(
          anchor,
          event.previousRenewalOn,
          includeAnchor: includeAnchor,
        );
        // The recorded jump is one renewal, including a manually extended
        // period. Do not split it into payments that were never recorded.
        anchor = event.nextRenewalOn;
        includeAnchor = true;
      }
      fillHistory(
        anchor,
        subscription.nextRenewalOn,
        includeAnchor: includeAnchor,
      );

      if (subscription.status == SubscriptionStatus.active) {
        if (subscription.nextRenewalOn.isBefore(latestHistoryEnd)) {
          final gapEnd = _earlierDate(latestHistoryEnd, nowDate);
          if (subscription.nextRenewalOn.isBefore(gapEnd) &&
              subscription.nextRenewalOn.isBefore(range.endExclusive) &&
              gapEnd.isAfter(range.start)) {
            gaps.add(
              SubscriptionCostGap(
                subscriptionId: subscription.id,
                serviceName: subscription.serviceName,
                accountLabel: accountLabel,
                start: subscription.nextRenewalOn,
                endExclusive: gapEnd,
              ),
            );
          }
        }
        if (subscription.management?.priceHistory.isNotEmpty ?? false) {
          for (final date in subscriptionPriceBillingDates(
            subscription,
            anchor: subscription.nextRenewalOn,
            start: range.start,
            endExclusive: range.endExclusive,
          )) {
            if (!date.isBefore(latestHistoryEnd)) add(date);
          }
          continue;
        }
        final cadence = _cadenceFor(subscription, subscription.nextRenewalOn);
        for (final date in cadence.between(
          range.start,
          range.endExclusive,
          minimumIndex: cadence.indexOf(subscription.nextRenewalOn),
        )) {
          // Editing the current due date backwards cannot split a historical
          // renewal's already saved coverage into extra charges.
          if (date.isBefore(latestHistoryEnd)) continue;
          add(date);
        }
      }
    }
    lines.sort((left, right) {
      final byDate = left.date.compareTo(right.date);
      return byDate != 0
          ? byDate
          : left.serviceName.compareTo(right.serviceName);
    });
    return SubscriptionCostAnalysis._(
      List<SubscriptionCostLine>.unmodifiable(lines),
      List<SubscriptionCostGap>.unmodifiable(gaps),
    );
  }

  final List<SubscriptionCostLine> lines;
  final List<SubscriptionCostGap> gaps;

  List<SubscriptionCostLine> forBasis(SubscriptionCostBasis basis) =>
      lines.where((line) => line.basis == basis).toList(growable: false);

  List<SubscriptionCurrencyTotal> currencyTotals(SubscriptionCostBasis basis) {
    final totals = <String, BigInt>{};
    for (final line in lines.where((line) => line.basis == basis)) {
      final amount = line.amount;
      if (amount == null) continue;
      final scaled = parseScaledSubscriptionAmount(amount);
      totals.update(
        line.currency,
        (current) => current + (line.refund ? -scaled : scaled),
        ifAbsent: () => line.refund ? -scaled : scaled,
      );
    }
    final result = <SubscriptionCurrencyTotal>[
      for (final entry in totals.entries)
        SubscriptionCurrencyTotal(
          currency: entry.key,
          scaledAmount: entry.value,
        ),
    ]..sort((left, right) => left.currency.compareTo(right.currency));
    return List<SubscriptionCurrencyTotal>.unmodifiable(result);
  }

  SubscriptionCnyEstimate cnyEstimate(SubscriptionCostBasis basis) {
    var total = 0.0;
    var compensation = 0.0;
    var converted = 0;
    var missing = 0;
    var unsupported = 0;
    for (final line in lines.where((line) => line.basis == basis)) {
      final amount = double.tryParse(line.amount ?? '');
      if (amount == null || !amount.isFinite || amount < 0) {
        missing += 1;
        continue;
      }
      final convertedAmount = SemiannualCnyExchangeRates.convertToCny(
        currency: line.currency,
        amount: amount,
      );
      if (convertedAmount == null) {
        unsupported += 1;
        continue;
      }
      final signed = line.refund ? -convertedAmount : convertedAmount;
      final adjusted = signed - compensation;
      final next = total + adjusted;
      compensation = (next - total) - adjusted;
      total = next;
      converted += 1;
    }
    return SubscriptionCnyEstimate(
      totalCny: total,
      convertedCount: converted,
      missingAmountCount: missing,
      unsupportedCurrencyCount: unsupported,
    );
  }

  Map<String, List<SubscriptionCostLine>> byMonth(SubscriptionCostBasis basis) {
    final result = <String, List<SubscriptionCostLine>>{};
    for (final line in lines.where((line) => line.basis == basis)) {
      final key =
          '${line.date.year.toString().padLeft(4, '0')}-'
          '${line.date.month.toString().padLeft(2, '0')}';
      (result[key] ??= <SubscriptionCostLine>[]).add(line);
    }
    return result;
  }

  Map<String, List<SubscriptionCostLine>> byCategory(
    SubscriptionCostBasis basis,
  ) {
    final result = <String, List<SubscriptionCostLine>>{};
    for (final line in lines.where((line) => line.basis == basis)) {
      final category = line.expenseCategory?.trim();
      final key = category == null || category.isEmpty ? '未分类' : category;
      (result[key] ??= <SubscriptionCostLine>[]).add(line);
    }
    return result;
  }
}

/// An interval whose saved dates cannot be joined by the saved billing cycle.
/// Expose this instead of presenting a partial total as complete.
final class SubscriptionCostGap {
  const SubscriptionCostGap({
    required this.subscriptionId,
    required this.serviceName,
    required this.accountLabel,
    required this.start,
    required this.endExclusive,
  });
  final String subscriptionId;
  final String serviceName;
  final String? accountLabel;
  final DateTime start;
  final DateTime endExclusive;
}

/// Calendar occurrences measured from a fixed anchor. Clipping in February
/// must not change the day of later months; day/week jumps use UTC date ordinals
/// so a daylight-saving transition cannot drop or duplicate a calendar date.
final class _BillingCadence {
  _BillingCadence(SubscriptionRecord subscription, this.anchor)
    : count = subscription.cycleCount,
      unit = subscription.cycleUnit;
  final DateTime anchor;
  final int count;
  final SubscriptionCycleUnit unit;

  bool get _calendarMonths =>
      unit == SubscriptionCycleUnit.month || unit == SubscriptionCycleUnit.year;
  int get _step =>
      count *
      (unit == SubscriptionCycleUnit.year
          ? 12
          : unit == SubscriptionCycleUnit.week
          ? 7
          : 1);

  DateTime at(int index) {
    if (!_calendarMonths) {
      return DateTime(anchor.year, anchor.month, anchor.day + index * _step);
    }
    final month = DateTime(anchor.year, anchor.month + index * _step);
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final isMonthEnd =
        anchor.day == DateTime(anchor.year, anchor.month + 1, 0).day;
    final day = isMonthEnd || anchor.day > lastDay ? lastDay : anchor.day;
    return DateTime(month.year, month.month, day);
  }

  int _nearIndex(DateTime date) {
    final difference = _calendarMonths
        ? (date.year - anchor.year) * 12 + date.month - anchor.month
        : DateTime.utc(date.year, date.month, date.day)
              .difference(DateTime.utc(anchor.year, anchor.month, anchor.day))
              .inDays;
    return (difference / _step).floor();
  }

  bool contains(DateTime date) => at(_nearIndex(date)) == date;
  int indexOf(DateTime date) => _nearIndex(date);

  Iterable<DateTime> between(
    DateTime start,
    DateTime endExclusive, {
    int minimumIndex = 0,
  }) sync* {
    var index = _nearIndex(start);
    if (index < minimumIndex) index = minimumIndex;
    var date = at(index);
    if (date.isBefore(start)) date = at(++index);
    while (date.isBefore(endExclusive)) {
      yield date;
      date = at(++index);
    }
  }
}

_BillingCadence _cadenceFor(SubscriptionRecord subscription, DateTime anchor) {
  final original = _BillingCadence(
    subscription,
    subscription.firstSubscribedOn,
  );
  // Preserve a fixed billing day through short months when the saved dates
  // still lie on that original grid. Explicit changed anchors take precedence.
  final followsOriginal =
      original.contains(anchor) &&
      subscription.renewalHistory.every(
        (event) =>
            event.previousRenewalOn.isAfter(anchor) ||
            (original.contains(event.previousRenewalOn) &&
                original.contains(event.nextRenewalOn)),
      );
  return followsOriginal ? original : _BillingCadence(subscription, anchor);
}

DateTime _earlierDate(DateTime left, DateTime right) =>
    left.isBefore(right) ? left : right;

BigInt parseScaledSubscriptionAmount(String value) {
  if (!RegExp(r'^(0|[1-9]\d{0,11})(\.\d{1,4})?$').hasMatch(value)) {
    throw ArgumentError.value(value, 'value', '订阅金额格式无效');
  }
  final parts = value.split('.');
  final whole = BigInt.parse(parts.first);
  final fraction = parts.length == 1
      ? BigInt.zero
      : BigInt.parse(parts[1].padRight(4, '0'));
  return whole * BigInt.from(10000) + fraction;
}

String _renewalKey(String subscriptionId, DateTime scheduledOn) =>
    '$subscriptionId|${formatSubscriptionDate(scheduledOn)}';

String formatScaledSubscriptionAmount(BigInt value) {
  final negative = value.isNegative;
  final absolute = value.abs();
  final whole = absolute ~/ BigInt.from(10000);
  final fraction = (absolute % BigInt.from(10000)).toString().padLeft(4, '0');
  final trimmed = fraction.replaceFirst(RegExp(r'0+$'), '');
  final formatted = trimmed.isEmpty ? '$whole' : '$whole.$trimmed';
  return negative ? '-$formatted' : formatted;
}
