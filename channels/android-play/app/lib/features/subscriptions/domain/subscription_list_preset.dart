import 'subscription_record.dart';

enum SubscriptionListPreset {
  renewalsThisMonth,
  renewingWithinThirtyDays,
  renewalsNextMonth,
  overdue,
}

extension SubscriptionListPresetPresentation on SubscriptionListPreset {
  String get label => switch (this) {
    SubscriptionListPreset.renewalsThisMonth => '本月订阅续费总额',
    SubscriptionListPreset.renewingWithinThirtyDays => '30天内续费',
    SubscriptionListPreset.renewalsNextMonth => '次月续费总额',
    SubscriptionListPreset.overdue => '逾期待确认',
  };
}

DateTime? subscriptionRenewalOccurrenceForPreset(
  SubscriptionRecord subscription,
  SubscriptionListPreset preset, {
  required DateTime today,
}) {
  final date = subscriptionDateOnly(today);
  final monthOffset = switch (preset) {
    SubscriptionListPreset.renewalsThisMonth => 0,
    SubscriptionListPreset.renewalsNextMonth => 1,
    _ => null,
  };
  if (monthOffset == null) return null;

  final start = DateTime(date.year, date.month + monthOffset);
  final end = DateTime(date.year, date.month + monthOffset + 1);
  bool isInRange(DateTime value) {
    final normalized = subscriptionDateOnly(value);
    return !normalized.isBefore(start) && normalized.isBefore(end);
  }

  if (isInRange(subscription.nextRenewalOn)) {
    return subscriptionDateOnly(subscription.nextRenewalOn);
  }
  for (final event in subscription.renewalHistory.reversed) {
    if (isInRange(event.previousRenewalOn)) {
      return subscriptionDateOnly(event.previousRenewalOn);
    }
  }
  return null;
}

bool subscriptionMatchesPreset(
  SubscriptionRecord subscription,
  SubscriptionListPreset preset, {
  required DateTime today,
}) {
  final date = subscriptionDateOnly(today);
  final renewalDate = subscriptionDateOnly(subscription.nextRenewalOn);
  final daysUntilRenewal = renewalDate.difference(date).inDays;

  return switch (preset) {
    SubscriptionListPreset.renewalsThisMonth ||
    SubscriptionListPreset.renewalsNextMonth =>
      subscriptionRenewalOccurrenceForPreset(
            subscription,
            preset,
            today: date,
          ) !=
          null,
    SubscriptionListPreset.renewingWithinThirtyDays =>
      subscription.status == SubscriptionStatus.active &&
          daysUntilRenewal >= 0 &&
          daysUntilRenewal <= 30,
    SubscriptionListPreset.overdue =>
      subscription.status == SubscriptionStatus.expired ||
          (subscription.status == SubscriptionStatus.active &&
              renewalDate.isBefore(date)),
  };
}

List<SubscriptionRecord> subscriptionsForPreset(
  Iterable<SubscriptionRecord> subscriptions,
  SubscriptionListPreset preset, {
  DateTime? today,
}) {
  final date = subscriptionDateOnly(today ?? DateTime.now());
  final result = subscriptions
      .where(
        (subscription) =>
            subscriptionMatchesPreset(subscription, preset, today: date),
      )
      .toList(growable: false);
  result.sort((left, right) {
    final leftOccurrence = subscriptionRenewalOccurrenceForPreset(
      left,
      preset,
      today: date,
    );
    final rightOccurrence = subscriptionRenewalOccurrenceForPreset(
      right,
      preset,
      today: date,
    );
    return (leftOccurrence ?? left.nextRenewalOn).compareTo(
      rightOccurrence ?? right.nextRenewalOn,
    );
  });
  return result;
}
