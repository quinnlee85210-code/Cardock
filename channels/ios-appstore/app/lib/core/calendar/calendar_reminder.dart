import '../../features/subscriptions/domain/subscription_record.dart';
import '../notifications/subscription_notification_content.dart';
import '../preferences/language_preferences.dart';
import '../preferences/notification_privacy_preferences.dart';

enum CalendarAlarm {
  none(null),
  sameDay(0),
  oneDay(1),
  threeDays(3),
  sevenDays(7);

  const CalendarAlarm(this.days);
  final int? days;
  String get label => switch (this) {
    none => '不设置',
    sameDay => '当天',
    oneDay => '1 天前',
    threeDays => '3 天前',
    sevenDays => '7 天前',
  };
}

enum CalendarExclusion { inactive, pastDate, conflictingDate }

final class CalendarEventProjection {
  const CalendarEventProjection({
    required this.recordId,
    required this.date,
    required this.summary,
  });
  final String recordId;
  final DateTime date;
  final SubscriptionPublicSummary summary;
  SubscriptionReminderEvent get type => summary.event;
  String title(NotificationPrivacy privacy, CardockLanguage language) =>
      subscriptionNotificationContent(
        summary: summary,
        privacy: privacy,
        language: language,
      ).body;
}

/// A session-bound, allowlisted projection. It contains no vault snapshot or
/// account records and is never persisted in the app.
final class CalendarReminderPlan {
  CalendarReminderPlan._({
    required this.vaultBindingId,
    required this.revision,
    required this.today,
    required this.events,
    required this.excluded,
  });
  final String vaultBindingId;
  final int revision;
  final DateTime today;
  final List<CalendarEventProjection> events;
  final Map<CalendarExclusion, int> excluded;
  int get renewalCount =>
      events.where((e) => e.type == SubscriptionReminderEvent.renewal).length;
  int get trialCount => events.length - renewalCount;
  int get excludedCount => excluded.values.fold(0, (a, b) => a + b);

  factory CalendarReminderPlan.build({
    required Iterable<SubscriptionRecord> records,
    required String vaultBindingId,
    required int revision,
    required DateTime today,
    required String singleRecordId,
  }) {
    final start = subscriptionDateOnly(today);
    final events = <CalendarEventProjection>[];
    final excluded = <CalendarExclusion, int>{};
    void exclude(CalendarExclusion reason) =>
        excluded.update(reason, (n) => n + 1, ifAbsent: () => 1);
    for (final s in records) {
      if (s.id != singleRecordId) continue;
      if (s.status != SubscriptionStatus.active ||
          (!s.isUnresolvedTrial && !s.isFormalSubscription)) {
        exclude(CalendarExclusion.inactive);
        continue;
      }
      if (s.isUnresolvedTrial) {
        final date = s.management!.trial!.endsOn;
        if (date.isBefore(start)) {
          exclude(CalendarExclusion.pastDate);
          continue;
        }
        events.add(
          CalendarEventProjection(
            recordId: s.id,
            date: date,
            summary: SubscriptionPublicSummary.fromSubscription(
              s,
              SubscriptionReminderEvent.trialEnd,
            ),
          ),
        );
        continue;
      }
      if (s.nextRenewalOn.isBefore(start)) {
        exclude(CalendarExclusion.pastDate);
        continue;
      }
      if (s.renewalHistory.any(
        (h) => s.nextRenewalOn.isBefore(h.nextRenewalOn),
      )) {
        exclude(CalendarExclusion.conflictingDate);
        continue;
      }
      events.add(
        CalendarEventProjection(
          recordId: s.id,
          date: s.nextRenewalOn,
          summary: SubscriptionPublicSummary.fromSubscription(
            s,
            SubscriptionReminderEvent.renewal,
          ),
        ),
      );
    }
    events.sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c == 0 ? a.recordId.compareTo(b.recordId) : c;
    });
    return CalendarReminderPlan._(
      vaultBindingId: vaultBindingId,
      revision: revision,
      today: start,
      events: List.unmodifiable(events),
      excluded: Map.unmodifiable(excluded),
    );
  }
}

String calendarDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
