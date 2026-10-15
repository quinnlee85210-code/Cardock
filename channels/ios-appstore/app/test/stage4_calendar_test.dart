import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:account_subscription_manager/core/calendar/calendar_reminder.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'stage2_subscription_management_test.dart' as f;

CalendarReminderPlan plan(
  List<SubscriptionRecord> records, {
  DateTime? today,
  String? selected,
}) => CalendarReminderPlan.build(
  records: records,
  singleRecordId: selected ?? (records.isEmpty ? 'missing' : records.first.id),
  vaultBindingId: 'synthetic-vault',
  revision: 3,
  today: today ?? DateTime(2026, 9, 4),
);

void main() {
  test('only explicitly selected record contributes one next event', () {
    final p = plan([
      f.sub(id: 'a'),
      f.sub(id: 'b', next: DateTime(2028, 9, 4)),
    ], selected: 'b');
    expect(p.events, hasLength(1));
    expect(p.events.single.recordId, 'b');
    expect(p.events.single.date, DateTime(2028, 9, 4));
    expect(plan([f.sub()], selected: 'missing').events, isEmpty);
    expect(plan([f.sub()], selected: '').events, isEmpty);
  });
  for (final unit in SubscriptionCycleUnit.values) {
    test('cycle ${unit.name} does not expand future events', () {
      final p = plan([f.sub(unit: unit, next: DateTime(2026, 9, 4))]);
      expect(p.events, hasLength(1));
      expect(p.events.single.date, DateTime(2026, 9, 4));
    });
  }
  for (final status in [
    SubscriptionStatus.paused,
    SubscriptionStatus.cancelled,
  ]) {
    test('inactive ${status.name} has no calendar event', () {
      final p = plan([f.sub(status: status)]);
      expect(p.events, isEmpty);
      expect(p.excluded[CalendarExclusion.inactive], 1);
    });
  }
  test('past date excluded and today allowed', () {
    expect(
      plan([
        f.sub(next: DateTime(2026, 9, 3)),
      ]).excluded[CalendarExclusion.pastDate],
      1,
    );
    expect(plan([f.sub(next: DateTime(2026, 9, 4))]).events, hasLength(1));
  });
  test('month end and leap day remain the selected business day', () {
    for (final day in [
      DateTime(2024, 1, 31),
      DateTime(2024, 2, 29),
      DateTime(2024, 12, 31),
    ]) {
      expect(
        plan([f.sub(first: day, next: day)], today: day).events.single.date,
        day,
      );
    }
  });
  test('only selected event date determines known price and currency', () {
    final management = SubscriptionManagement(
      priceHistory: [
        f.price('p1', DateTime(2026, 1, 1), '120'),
        f.price('p2', DateTime(2026, 10, 1), '8', currency: 'USD'),
      ],
    );
    final current = plan([f.sub(management: management)]).events.single.summary;
    final later = plan([
      f.sub(next: DateTime(2026, 10, 10), management: management),
    ]).events.single.summary;
    expect(current.amount, '120');
    expect(later.amount, '8');
    expect(later.currency, 'USD');
  });
  test('trial contributes only its end date and no invented formal price', () {
    final p = plan([
      f.sub(management: SubscriptionManagement(trial: f.trial())),
    ]);
    expect(p.events, hasLength(1));
    expect(p.trialCount, 1);
    expect(p.events.single.date, DateTime(2026, 9, 10));
    expect(p.events.single.summary.amount, isNull);
  });
  test('history conflict cannot produce an event', () {
    final renewed = f.sub(next: DateTime(2026, 9, 10)).markRenewed();
    final inconsistent = renewed.applyDraft(
      SubscriptionDraft(
        accountId: null,
        details: f.sub(next: DateTime(2026, 9, 12)).details,
      ),
    );
    final p = plan([inconsistent]);
    expect(p.events, isEmpty);
    expect(p.excluded[CalendarExclusion.conflictingDate], 1);
  });
  test('UTC-10 UTC+14 and DST zones retain all-day date', () {
    tz_data.initializeTimeZones();
    for (final zone in [
      'Pacific/Honolulu',
      'Pacific/Kiritimati',
      'America/Los_Angeles',
      'Asia/Shanghai',
    ]) {
      final date = tz.TZDateTime(tz.getLocation(zone), 2026, 9, 4);
      expect(
        calendarDate(plan([f.sub(next: date)], today: date).events.single.date),
        '20260904',
        reason: zone,
      );
    }
  });
}
