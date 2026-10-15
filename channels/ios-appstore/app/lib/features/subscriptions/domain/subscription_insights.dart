import 'subscription_record.dart';
import 'subscription_cost_summary.dart';

/// Exact rational arithmetic in 1/10000 units. Only presentation rounds.
final class ExactMonthlyAmount {
  ExactMonthlyAmount(BigInt numerator, BigInt denominator)
    : assert(denominator > BigInt.zero),
      numerator = numerator ~/ numerator.gcd(denominator),
      denominator = denominator ~/ numerator.gcd(denominator);
  factory ExactMonthlyAmount.zero() =>
      ExactMonthlyAmount(BigInt.zero, BigInt.one);
  final BigInt numerator, denominator;
  ExactMonthlyAmount operator +(ExactMonthlyAmount other) => ExactMonthlyAmount(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );
  BigInt get roundedScaled =>
      (numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two);
  String get display => formatScaledSubscriptionAmount(roundedScaled);
}

ExactMonthlyAmount monthlyEquivalent(
  String amount,
  int count,
  SubscriptionCycleUnit unit,
) {
  if (count < 1 || count > 120) throw ArgumentError('计费周期数量必须为1到120');
  final scaled = parseScaledSubscriptionAmount(amount);
  return switch (unit) {
    SubscriptionCycleUnit.month => ExactMonthlyAmount(
      scaled,
      BigInt.from(count),
    ),
    SubscriptionCycleUnit.year => ExactMonthlyAmount(
      scaled,
      BigInt.from(12 * count),
    ),
    // 365.2425 / 12 = 30.436875, represented exactly.
    SubscriptionCycleUnit.day => ExactMonthlyAmount(
      scaled * BigInt.from(30436875),
      BigInt.from(1000000 * count),
    ),
    SubscriptionCycleUnit.week => ExactMonthlyAmount(
      scaled * BigInt.from(30436875),
      BigInt.from(7000000 * count),
    ),
  };
}

enum SubscriptionAttentionKind { overdue, trialEnded, trialConversionDue }

final class SubscriptionAttention {
  const SubscriptionAttention(this.subscription, this.kind);
  final SubscriptionRecord subscription;
  final SubscriptionAttentionKind kind;
}

List<SubscriptionAttention> subscriptionAttention(
  Iterable<SubscriptionRecord> records,
  DateTime today,
) {
  final now = subscriptionDateOnly(today);
  final result = <SubscriptionAttention>[];
  for (final s in records) {
    if (s.status != SubscriptionStatus.active) continue;
    if (s.isUnresolvedTrial) {
      final trial = s.management!.trial!;
      if (trial.expectedAutoConvert &&
          trial.firstPaidOn != null &&
          !trial.firstPaidOn!.isAfter(now)) {
        result.add(
          SubscriptionAttention(
            s,
            SubscriptionAttentionKind.trialConversionDue,
          ),
        );
      } else if (!trial.endsOn.isAfter(now)) {
        result.add(
          SubscriptionAttention(s, SubscriptionAttentionKind.trialEnded),
        );
      }
    } else if (s.nextRenewalOn.isBefore(now)) {
      result.add(SubscriptionAttention(s, SubscriptionAttentionKind.overdue));
    }
  }
  return result;
}

final class MonthlyEquivalentLine {
  const MonthlyEquivalentLine({
    required this.subscription,
    required this.currency,
    required this.originalAmount,
    required this.count,
    required this.unit,
    required this.amount,
    required this.potential,
  });
  final SubscriptionRecord subscription;
  final String currency, originalAmount;
  final int count;
  final SubscriptionCycleUnit unit;
  final ExactMonthlyAmount amount;
  final bool potential;
  bool get estimated =>
      unit == SubscriptionCycleUnit.day || unit == SubscriptionCycleUnit.week;
}

List<MonthlyEquivalentLine> monthlyEquivalentLines(
  Iterable<SubscriptionRecord> subscriptions,
  DateTime today,
) {
  final now = subscriptionDateOnly(today), result = <MonthlyEquivalentLine>[];
  for (final s in subscriptions) {
    if (s.status != SubscriptionStatus.active) continue;
    final trial = s.management?.trial;
    if (trial != null && trial.unresolved) {
      if (!trial.expectedAutoConvert ||
          trial.firstPaidOn == null ||
          trial.needsConfirmation(now)) {
        continue;
      }
      result.add(
        MonthlyEquivalentLine(
          subscription: s,
          currency: trial.formalCurrency,
          originalAmount: trial.formalAmount,
          count: trial.formalCycleCount,
          unit: trial.formalCycleUnit,
          amount: monthlyEquivalent(
            trial.formalAmount,
            trial.formalCycleCount,
            trial.formalCycleUnit,
          ),
          potential: true,
        ),
      );
    } else {
      if (trial != null && trial.outcome != TrialOutcome.converted) continue;
      final price = s.management?.priceAt(now),
          amount = price?.amount ?? s.amount;
      if (amount == null) continue;
      final count = price?.cycleCount ?? s.cycleCount,
          unit = price?.cycleUnit ?? s.cycleUnit;
      result.add(
        MonthlyEquivalentLine(
          subscription: s,
          currency: price?.currency ?? s.currency,
          originalAmount: amount,
          count: count,
          unit: unit,
          amount: monthlyEquivalent(amount, count, unit),
          potential: false,
        ),
      );
    }
  }
  return List.unmodifiable(result);
}

Map<String, ExactMonthlyAmount> monthlyEquivalentTotals(
  Iterable<MonthlyEquivalentLine> lines, {
  bool potential = false,
}) {
  final totals = <String, ExactMonthlyAmount>{};
  for (final line in lines.where((l) => l.potential == potential)) {
    totals[line.currency] =
        (totals[line.currency] ?? ExactMonthlyAmount.zero()) + line.amount;
  }
  return totals;
}

final class SubscriptionForecastLine {
  const SubscriptionForecastLine({
    required this.subscription,
    required this.date,
    required this.amount,
    required this.currency,
    required this.fromTrial,
  });
  final SubscriptionRecord subscription;
  final DateTime date;
  final String amount, currency;
  final bool fromTrial;
}

enum ForecastExclusion {
  inactive,
  missingAmount,
  overdue,
  trialPending,
  trialNoConversion,
  missingTrialDate,
  invalidRange,
}

final class SubscriptionForecast {
  const SubscriptionForecast(this.months, this.lines, this.excluded);
  final List<DateTime> months;
  final List<SubscriptionForecastLine> lines;
  final Map<ForecastExclusion, int> excluded;
  factory SubscriptionForecast.build(
    Iterable<SubscriptionRecord> records,
    DateTime today,
  ) {
    final now = subscriptionDateOnly(today),
        end = DateTime(today.year, today.month + 12);
    final lines = <SubscriptionForecastLine>[],
        excluded = <ForecastExclusion, int>{};
    void exclude(ForecastExclusion reason) =>
        excluded.update(reason, (n) => n + 1, ifAbsent: () => 1);
    for (final s in records) {
      if (s.status != SubscriptionStatus.active) {
        exclude(ForecastExclusion.inactive);
        continue;
      }
      final trial = s.management?.trial;
      if (trial != null &&
          !trial.unresolved &&
          trial.outcome != TrialOutcome.converted) {
        exclude(ForecastExclusion.inactive);
        continue;
      }
      final fromTrial = trial?.unresolved ?? false;
      DateTime anchor;
      int count;
      SubscriptionCycleUnit unit;
      String? amount;
      String currency;
      if (fromTrial) {
        if (trial!.needsConfirmation(now)) {
          exclude(ForecastExclusion.trialPending);
          continue;
        }
        if (!trial.expectedAutoConvert) {
          exclude(ForecastExclusion.trialNoConversion);
          continue;
        }
        if (trial.firstPaidOn == null) {
          exclude(ForecastExclusion.missingTrialDate);
          continue;
        }
        anchor = trial.firstPaidOn!;
        count = trial.formalCycleCount;
        unit = trial.formalCycleUnit;
        amount = trial.formalAmount;
        currency = trial.formalCurrency;
      } else {
        anchor = s.nextRenewalOn;
        count = s.cycleCount;
        unit = s.cycleUnit;
        amount = s.amount;
        currency = s.currency;
      }
      if (anchor.isBefore(now)) {
        exclude(ForecastExclusion.overdue);
        continue;
      }
      if (!fromTrial) amount = s.management?.priceAt(anchor)?.amount ?? amount;
      if (amount == null) {
        exclude(ForecastExclusion.missingAmount);
        continue;
      }
      var date = anchor, index = 0;
      while (date.isBefore(end)) {
        if (++index > 370) {
          exclude(ForecastExclusion.invalidRange);
          break;
        }
        final price = fromTrial ? null : s.management?.priceAt(date);
        lines.add(
          SubscriptionForecastLine(
            subscription: s,
            date: date,
            amount: price?.amount ?? amount,
            currency: price?.currency ?? currency,
            fromTrial: fromTrial,
          ),
        );
        final nextCount = price?.cycleCount ?? count,
            nextUnit = price?.cycleUnit ?? unit;
        // On a real plan change start a new cadence; otherwise use the original
        // calendar anchor to preserve Jan-30 and leap-day behavior.
        if (nextCount != count || nextUnit != unit) {
          anchor = date;
          count = nextCount;
          unit = nextUnit;
        }
        final next = _nextAnchoredDate(anchor, date, count, unit);
        if (next == null || !next.isAfter(date)) {
          exclude(ForecastExclusion.invalidRange);
          break;
        }
        date = next;
      }
    }
    lines.sort((a, b) => a.date.compareTo(b.date));
    return SubscriptionForecast(
      List.generate(12, (i) => DateTime(now.year, now.month + i)),
      List.unmodifiable(lines),
      Map.unmodifiable(excluded),
    );
  }
  Map<String, BigInt> totalsForMonth(DateTime month) {
    final result = <String, BigInt>{};
    for (final line in lines.where(
      (l) => l.date.year == month.year && l.date.month == month.month,
    )) {
      result[line.currency] =
          (result[line.currency] ?? BigInt.zero) +
          parseScaledSubscriptionAmount(line.amount);
    }
    return result;
  }
}

DateTime? _nextAnchoredDate(
  DateTime anchor,
  DateTime date,
  int count,
  SubscriptionCycleUnit unit,
) {
  try {
    if (unit == SubscriptionCycleUnit.day ||
        unit == SubscriptionCycleUnit.week) {
      return advanceSubscriptionDate(date, count: count, unit: unit);
    }
    final months = count * (unit == SubscriptionCycleUnit.year ? 12 : 1);
    final elapsed = (date.year - anchor.year) * 12 + date.month - anchor.month;
    final target = DateTime(
      anchor.year,
      anchor.month + (elapsed ~/ months + 1) * months,
    );
    final last = DateTime(target.year, target.month + 1, 0).day;
    final anchorLast = DateTime(anchor.year, anchor.month + 1, 0).day;
    return subscriptionDateOnly(
      DateTime(
        target.year,
        target.month,
        anchor.day == anchorLast
            ? last
            : (anchor.day > last ? last : anchor.day),
      ),
    );
  } on ArgumentError {
    return null;
  }
}
