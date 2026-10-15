import 'package:account_subscription_manager/core/notifications/reminder_scheduler.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  group('密码复核汇总提醒', () {
    test('到期账号只产生一条通用汇总提醒且过期时顺延一分钟', () async {
      final now = DateTime.utc(2026, 9, 1, 8);
      final gateway = _Gateway();
      final scheduler = LocalReminderScheduler(
        gateway: gateway,
        now: () => now,
        timeZoneIdentifier: () async => 'UTC',
        targetPlatform: TargetPlatform.android,
      );

      await scheduler.rescheduleAll(
        const <SubscriptionRecord>[],
        passwordReviewAtUtc: now.subtract(const Duration(days: 30)),
      );

      expect(gateway.scheduled, hasLength(1));
      final passwordReminder = gateway.scheduled.single;
      expect(passwordReminder.id, passwordReviewReminderNotificationId);
      expect(passwordReminder.title, '安全复核提醒');
      expect(passwordReminder.body, '有本机密码记录需要核对，请解锁应用查看。');
      expect(
        passwordReminder.scheduledDate.toUtc(),
        now.add(const Duration(minutes: 1)),
      );
      expect(passwordReminder.title, isNot(contains('账号')));
      expect(passwordReminder.body, isNot(contains('平台')));
      expect(await scheduler.pendingReminderCount(), 1);
    });

    test('关闭密码复核提醒只清理密码通知并保留订阅提醒', () async {
      final gateway = _Gateway();
      final subscription = _subscription('subscription-kept');
      final subscriptionId = reminderNotificationId(subscription.id);
      final scheduler = LocalReminderScheduler(
        gateway: gateway,
        now: () => DateTime.utc(2026, 9, 1),
        timeZoneIdentifier: () async => 'UTC',
        targetPlatform: TargetPlatform.android,
      );

      await scheduler.rescheduleAll(<SubscriptionRecord>[
        subscription,
      ], passwordReviewAtUtc: DateTime.utc(2026, 10, 1));
      expect(
        gateway.pending.keys,
        containsAll(<int>[
          passwordReviewReminderNotificationId,
          subscriptionId,
        ]),
      );

      await scheduler.rescheduleAll(<SubscriptionRecord>[subscription]);

      expect(gateway.cancelled, contains(passwordReviewReminderNotificationId));
      expect(gateway.cancelled, isNot(contains(subscriptionId)));
      expect(gateway.pending.keys, <int>{subscriptionId});
    });

    test('Android容量为密码汇总提醒预留一席且业务编号不碰撞', () async {
      final gateway = _Gateway();
      final scheduler = LocalReminderScheduler(
        gateway: gateway,
        now: () => DateTime.utc(2026, 9, 1),
        timeZoneIdentifier: () async => 'UTC',
        targetPlatform: TargetPlatform.android,
      );
      final subscriptions = List<SubscriptionRecord>.generate(
        400,
        (index) => _subscription(
          'subscription-$index',
          next: DateTime(2026, 12, 31 + index),
        ),
        growable: false,
      );

      await scheduler.rescheduleAll(
        subscriptions,
        passwordReviewAtUtc: DateTime.utc(2026, 10, 1),
      );

      expect(
        gateway.scheduled.where(
          (call) => call.id == passwordReviewReminderNotificationId,
        ),
        hasLength(1),
      );
      final businessCalls = gateway.scheduled.where(
        (call) => call.id != passwordReviewReminderNotificationId,
      );
      expect(businessCalls, hasLength(399));
      expect(
        businessCalls.every(
          (call) =>
              call.id > 0 && call.id <= maximumBusinessReminderNotificationId,
        ),
        isTrue,
      );
      expect(
        maximumBusinessReminderNotificationId,
        lessThan(passwordReviewReminderNotificationId),
      );
    });
  });
}

SubscriptionRecord _subscription(String id, {DateTime? next}) =>
    SubscriptionRecord.fromDraft(
      id: id,
      draft: SubscriptionDraft(
        accountId: 'account-1',
        details: SubscriptionDetailsDraft(
          serviceName: '通用订阅提醒',
          firstSubscribedOn: DateTime(2026, 1, 1),
          nextRenewalOn: next ?? DateTime(2026, 12, 31),
          reminderDaysBefore: 7,
        ),
      ),
    );

final class _ScheduledCall {
  const _ScheduledCall({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledDate,
  });

  final int id;
  final String title;
  final String body;
  final tz.TZDateTime scheduledDate;
}

final class _Gateway implements ReminderNotificationGateway {
  final List<_ScheduledCall> scheduled = <_ScheduledCall>[];
  final List<int> cancelled = <int>[];
  final Map<int, PendingReminderNotification> pending =
      <int, PendingReminderNotification>{};

  @override
  Future<bool> requestApplicationPermission() async => true;

  @override
  Future<bool> ensureReminderChannelEnabled() async => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> canScheduleExactNotifications() async => true;

  @override
  Future<List<PendingReminderNotification>>
  pendingNotificationRequests() async => pending.values.toList(growable: false);

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required bool useExactAlarm,
    String? payload,
  }) async {
    scheduled.add(
      _ScheduledCall(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
      ),
    );
    pending[id] = PendingReminderNotification(
      id: id,
      title: title,
      body: body,
      payload: payload,
    );
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    pending.remove(id);
  }

  @override
  Future<void> cancelAll() async => pending.clear();
}
