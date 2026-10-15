import '../../accounts/domain/account_record.dart';
import 'subscription_record.dart';

enum SubscriptionSearchStatus { active, trial, paused, cancelled, expired }

enum SubscriptionDateFilter { days30, days60, days90, overdue }

/// Ephemeral query state. It has no serializer and cannot mutate a vault.
final class SubscriptionSearch {
  const SubscriptionSearch({
    this.query = '',
    this.statuses = const {},
    this.autoRenew = const {},
    this.dates = const {},
    this.cycles = const {},
    this.currencies = const {},
    this.paymentMethods = const {},
    this.categories = const {},
    this.linked = const {},
  });
  final String query;
  final Set<SubscriptionSearchStatus> statuses;
  final Set<bool> autoRenew, linked;
  final Set<SubscriptionDateFilter> dates;
  final Set<String> cycles, currencies, paymentMethods, categories;
  bool get active =>
      query.trim().isNotEmpty ||
      [
        statuses,
        autoRenew,
        dates,
        cycles,
        currencies,
        paymentMethods,
        categories,
        linked,
      ].any((s) => s.isNotEmpty);
  SubscriptionSearch copyWith({
    String? query,
    Set<SubscriptionSearchStatus>? statuses,
    Set<bool>? autoRenew,
    Set<SubscriptionDateFilter>? dates,
    Set<String>? cycles,
    Set<String>? currencies,
    Set<String>? paymentMethods,
    Set<String>? categories,
    Set<bool>? linked,
  }) => SubscriptionSearch(
    query: query ?? this.query,
    statuses: statuses ?? this.statuses,
    autoRenew: autoRenew ?? this.autoRenew,
    dates: dates ?? this.dates,
    cycles: cycles ?? this.cycles,
    currencies: currencies ?? this.currencies,
    paymentMethods: paymentMethods ?? this.paymentMethods,
    categories: categories ?? this.categories,
    linked: linked ?? this.linked,
  );

  List<SubscriptionRecord> apply(
    Iterable<SubscriptionRecord> records, {
    required DateTime today,
    Iterable<AccountRecord> accounts = const [],
    bool includeAccountPlatform = true,
    bool includeCancellation = true,
  }) {
    final accountById = {for (final a in accounts) a.id: a};
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final date = subscriptionDateOnly(today);
    bool accepts<T>(Set<T> filter, T value) =>
        filter.isEmpty || filter.contains(value);
    return records
        .where((s) {
          final trial = s.management?.trial;
          final due = s.isUnresolvedTrial ? trial!.endsOn : s.nextRenewalOn;
          final status =
              s.isUnresolvedTrial && s.status == SubscriptionStatus.active
              ? SubscriptionSearchStatus.trial
              : SubscriptionSearchStatus.values.byName(s.status.name);
          final cancel = includeCancellation
              ? s.management?.cancellation
              : null;
          final fields = [
            s.serviceName,
            s.planName,
            s.expenseCategory,
            includeAccountPlatform
                ? accountById[s.accountId]?.platformName
                : null,
            s.paymentMethod,
            s.currency,
            s.notes,
            cancel?.location,
            cancel?.steps,
            cancel?.url,
            cancel?.channelNotes,
          ].whereType<String>().join('\n').toLowerCase();
          if (!terms.every(fields.contains)) return false;
          if (!accepts(statuses, status) ||
              !accepts(autoRenew, s.autoRenew) ||
              !accepts(cycles, '${s.cycleCount}:${s.cycleUnit.name}') ||
              !accepts(currencies, s.currency) ||
              !accepts(paymentMethods, s.paymentMethod ?? '') ||
              !accepts(categories, s.expenseCategory ?? '') ||
              !accepts(linked, s.accountId != null)) {
            return false;
          }
          return dates.isEmpty ||
              dates.any(
                (f) => f == SubscriptionDateFilter.overdue
                    ? due.isBefore(date)
                    : !due.isBefore(date) &&
                          !due.isAfter(
                            DateTime(
                              date.year,
                              date.month,
                              date.day +
                                  switch (f) {
                                    SubscriptionDateFilter.days30 => 30,
                                    SubscriptionDateFilter.days60 => 60,
                                    _ => 90,
                                  },
                            ),
                          ),
              );
        })
        .toList(growable: false);
  }
}
