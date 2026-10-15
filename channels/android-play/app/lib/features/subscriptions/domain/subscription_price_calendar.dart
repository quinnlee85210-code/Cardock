import 'subscription_record.dart';

/// Date-only recurrence with the plan effective at each billing date. A cycle
/// change starts its own cadence; an amount-only change keeps the old anchor.
Iterable<DateTime> subscriptionPriceBillingDates(
  SubscriptionRecord subscription, {
  required DateTime anchor,
  required DateTime start,
  required DateTime endExclusive,
  bool includeAnchor = true,
}) sync* {
  var date = subscriptionDateOnly(anchor),
      cadenceAnchor = subscriptionDateOnly(anchor);
  var count =
      subscription.management?.priceAt(date)?.cycleCount ??
      subscription.cycleCount;
  var unit =
      subscription.management?.priceAt(date)?.cycleUnit ??
      subscription.cycleUnit;
  var index = 0;
  for (var iteration = 0; iteration < 125000; iteration++) {
    if (!date.isBefore(endExclusive)) return;
    if ((includeAnchor || date != anchor) && !date.isBefore(start)) yield date;
    final price = subscription.management?.priceAt(date);
    final nextCount = price?.cycleCount ?? subscription.cycleCount,
        nextUnit = price?.cycleUnit ?? subscription.cycleUnit;
    if (count != nextCount || unit != nextUnit) {
      cadenceAnchor = date;
      index = 0;
      count = nextCount;
      unit = nextUnit;
    }
    index++;
    DateTime next;
    if (unit == SubscriptionCycleUnit.day ||
        unit == SubscriptionCycleUnit.week) {
      next = DateTime(
        cadenceAnchor.year,
        cadenceAnchor.month,
        cadenceAnchor.day +
            count * index * (unit == SubscriptionCycleUnit.week ? 7 : 1),
      );
    } else {
      final month = DateTime(
        cadenceAnchor.year,
        cadenceAnchor.month +
            count * index * (unit == SubscriptionCycleUnit.year ? 12 : 1),
      );
      final last = DateTime(month.year, month.month + 1, 0).day,
          anchorLast = DateTime(
            cadenceAnchor.year,
            cadenceAnchor.month + 1,
            0,
          ).day;
      next = DateTime(
        month.year,
        month.month,
        cadenceAnchor.day == anchorLast
            ? last
            : (cadenceAnchor.day > last ? last : cadenceAnchor.day),
      );
    }
    if (!next.isAfter(date)) throw StateError('计费日期未能向前推进');
    if (next.year > 2300) return;
    date = next;
  }
  throw StateError('费用统计范围内的续费次数超过安全上限');
}
