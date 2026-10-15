import 'package:account_subscription_manager/core/notifications/reminder_scheduler.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';

enum ReminderSchedulerOperation {
  requestPermission,
  schedule,
  cancel,
  cancelAll,
  rescheduleAll,
  pendingReminderCount,
  showTestNotification,
  scheduleTestReminder,
}

final class ReminderScheduleCall {
  const ReminderScheduleCall({
    required this.subscriptionId,
    required this.reminderTimeMinutes,
    this.secondReminderTimeMinutes,
  });

  final String subscriptionId;
  final int reminderTimeMinutes;
  final int? secondReminderTimeMinutes;
}

final class ReminderRescheduleCall {
  const ReminderRescheduleCall({
    required this.subscriptionIds,
    required this.reminderTimeMinutes,
    this.secondReminderTimeMinutes,
    this.passwordReviewAtUtc,
  });

  final List<String> subscriptionIds;
  final DateTime? passwordReviewAtUtc;
  final int reminderTimeMinutes;
  final int? secondReminderTimeMinutes;
}

/// 记录 AppState 与系统提醒边界的交互，不触发真实平台插件。
final class RecordingReminderScheduler implements ReminderScheduler {
  ReminderPermissionStatus permissionStatus = ReminderPermissionStatus.allowed;
  ReminderSchedulerOperation? failOn;
  ReminderSchedulingException? structuredFailure;
  int pendingCount = 0;

  int requestPermissionCalls = 0;
  int cancelAllCalls = 0;
  int pendingReminderCountCalls = 0;
  int showTestNotificationCalls = 0;
  final List<Duration> testReminderDelays = <Duration>[];
  final List<ReminderScheduleCall> scheduleCalls = <ReminderScheduleCall>[];
  final List<String> cancelCalls = <String>[];
  final List<ReminderRescheduleCall> rescheduleCalls =
      <ReminderRescheduleCall>[];

  bool get permissionGranted =>
      permissionStatus == ReminderPermissionStatus.allowed;

  set permissionGranted(bool value) {
    permissionStatus = value
        ? ReminderPermissionStatus.allowed
        : ReminderPermissionStatus.applicationNotificationsDisabled;
  }

  @override
  Future<ReminderPermissionStatus> requestPermission() async {
    requestPermissionCalls += 1;
    _maybeFail(ReminderSchedulerOperation.requestPermission);
    return permissionStatus;
  }

  @override
  Future<void> schedule(
    SubscriptionRecord subscription, {
    int reminderTimeMinutes = 12 * 60 + 30,
    int? secondReminderTimeMinutes,
  }) async {
    scheduleCalls.add(
      ReminderScheduleCall(
        subscriptionId: subscription.id,
        reminderTimeMinutes: reminderTimeMinutes,
        secondReminderTimeMinutes: secondReminderTimeMinutes,
      ),
    );
    _maybeFail(ReminderSchedulerOperation.schedule);
  }

  @override
  Future<void> cancel(String subscriptionId) async {
    cancelCalls.add(subscriptionId);
    _maybeFail(ReminderSchedulerOperation.cancel);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls += 1;
    _maybeFail(ReminderSchedulerOperation.cancelAll);
  }

  @override
  Future<void> rescheduleAll(
    Iterable<SubscriptionRecord> subscriptions, {
    int reminderTimeMinutes = 12 * 60 + 30,
    int? secondReminderTimeMinutes,
    DateTime? passwordReviewAtUtc,
  }) async {
    rescheduleCalls.add(
      ReminderRescheduleCall(
        subscriptionIds: List<String>.unmodifiable(
          subscriptions.map((subscription) => subscription.id),
        ),
        passwordReviewAtUtc: passwordReviewAtUtc,
        reminderTimeMinutes: reminderTimeMinutes,
        secondReminderTimeMinutes: secondReminderTimeMinutes,
      ),
    );
    _maybeFail(ReminderSchedulerOperation.rescheduleAll);
  }

  @override
  Future<int> pendingReminderCount() async {
    pendingReminderCountCalls += 1;
    _maybeFail(ReminderSchedulerOperation.pendingReminderCount);
    return pendingCount;
  }

  @override
  Future<void> showTestNotification() async {
    showTestNotificationCalls += 1;
    _maybeFail(ReminderSchedulerOperation.showTestNotification);
  }

  @override
  Future<void> scheduleTestReminder({
    Duration delay = const Duration(minutes: 1),
  }) async {
    testReminderDelays.add(delay);
    _maybeFail(ReminderSchedulerOperation.scheduleTestReminder);
  }

  void reset({bool clearFailure = true}) {
    requestPermissionCalls = 0;
    cancelAllCalls = 0;
    pendingReminderCountCalls = 0;
    showTestNotificationCalls = 0;
    testReminderDelays.clear();
    scheduleCalls.clear();
    cancelCalls.clear();
    rescheduleCalls.clear();
    if (clearFailure) {
      failOn = null;
      structuredFailure = null;
    }
  }

  void _maybeFail(ReminderSchedulerOperation operation) {
    if (failOn == operation) {
      final failure = structuredFailure;
      if (failure != null) {
        throw failure;
      }
      throw StateError('TEST-ONLY reminder scheduler failure: $operation');
    }
  }
}
