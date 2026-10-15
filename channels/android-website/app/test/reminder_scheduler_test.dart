import 'dart:async';
import 'package:flutter/services.dart';

import 'package:account_subscription_manager/core/notifications/reminder_scheduler.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  test(
    'stage2 changed subscription cancels only its own old points; unchanged resync is idempotent',
    () async {
      final gateway = _RecordingNotificationGateway();
      final scheduler = LocalReminderScheduler(
        gateway: gateway,
        now: () => DateTime(2026, 3, 1),
        timeZoneIdentifier: () async => 'Asia/Shanghai',
        targetPlatform: TargetPlatform.android,
      );
      SubscriptionRecord rule(String id, List<int> days) =>
          _record(
            id: id,
            nextRenewalOn: id == 'b' ? DateTime(2026, 4, 15) : null,
          ).withManagement(
            SubscriptionManagement(
              reminderRules: [
                SubscriptionReminderRule(
                  event: SubscriptionReminderEvent.renewal,
                  daysBefore: days,
                ),
              ],
            ),
          );
      final a = rule('a', [3, 0]), b = rule('b', [7, 1, 0]);
      await scheduler.rescheduleAll([a, b]);
      expect(gateway.scheduled, hasLength(5));
      gateway.cancelAttempts.clear();
      gateway.scheduleAttempts.clear();
      await scheduler.rescheduleAll([
        rule('a', [5, 0]),
        b,
      ]);
      final bIds = subscriptionReminderOccurrences(
        b,
        reminderTimeMinutes: 540,
        now: DateTime(2026, 3, 1),
      ).map((o) => o.id).toSet();
      expect(gateway.cancelAttempts.where(bIds.contains), isEmpty);
      expect(gateway.scheduleAttempts.where(bIds.contains), isEmpty);
      expect(gateway.pending, hasLength(5));
      gateway.cancelAttempts.clear();
      gateway.scheduleAttempts.clear();
      await scheduler.rescheduleAll([
        rule('a', [5, 0]),
        b,
      ]);
      expect(gateway.cancelAttempts, isEmpty);
      expect(gateway.scheduleAttempts, isEmpty);
    },
  );
  test(
    'permission revoked between check and scheduling still creates an idle-capable reminder',
    () async {
      final gateway = _RecordingNotificationGateway(permissionGranted: true)
        ..revokeExactOnSchedule = true;
      final scheduler = LocalReminderScheduler(
        gateway: gateway,
        now: () => DateTime(2026, 3, 1),
        timeZoneIdentifier: () async => 'Asia/Shanghai',
        targetPlatform: TargetPlatform.android,
      );
      await scheduler.schedule(_record());
      expect(gateway.scheduled, hasLength(1));
      expect(gateway.scheduled.single.useExactAlarm, isFalse);
      expect(gateway.scheduleAttempts, hasLength(2));
      expect(
        gateway.scheduled.single.scheduledDate.toUtc(),
        DateTime.utc(2026, 3, 24, 4, 30),
      );
    },
  );

  test('提醒日期按续费日减提前天数计算', () {
    final subscription = _record();
    expect(subscriptionReminderOn(subscription), DateTime(2026, 3, 24));
  });

  test('延期日期优先，取消或关闭提醒后不再计划', () {
    final snoozed = _record().snoozeReminderUntil(DateTime(2026, 3, 30));
    expect(subscriptionReminderOn(snoozed), DateTime(2026, 3, 30));

    final cancelled = snoozed.cancel(cancelledOn: DateTime(2026, 3, 1));
    expect(subscriptionReminderOn(cancelled), isNull);

    final disabled = SubscriptionRecord.fromDraft(
      id: 'subscription-disabled',
      draft: SubscriptionDraft(
        accountId: 'account-1',
        details: SubscriptionDetailsDraft(
          serviceName: '关闭提醒',
          firstSubscribedOn: DateTime(2026, 1, 1),
          nextRenewalOn: DateTime(2026, 4, 1),
          reminderEnabled: false,
        ),
      ),
    );
    expect(subscriptionReminderOn(disabled), isNull);
  });

  test('精确小时延后保留UTC瞬时且不再套用全局提醒时间', () {
    final exact = DateTime.utc(2026, 8, 30, 4, 30);
    final snoozed = _record().snoozeReminder(
      SubscriptionSnoozeTarget.exactInstant(exact),
    );

    expect(subscriptionReminderAt(snoozed, reminderTimeMinutes: 1), exact);
    expect(
      subscriptionReminderAt(snoozed, reminderTimeMinutes: 23 * 60 + 59),
      exact,
    );
  });

  test('通知编号跨调用稳定、为正数且不同订阅通常不同', () {
    final first = reminderNotificationId('subscription-1');
    expect(first, greaterThan(0));
    expect(first, lessThanOrEqualTo(maximumBusinessReminderNotificationId));
    expect(reminderNotificationId('subscription-1'), first);
    expect(reminderNotificationId('subscription-2'), isNot(first));
    expect(maximumBusinessReminderNotificationId, lessThan(0x7ffffffd));
  });

  test('空实现可安全注入且不申请权限', () async {
    const scheduler = NoopReminderScheduler();
    expect(
      await scheduler.requestPermission(),
      ReminderPermissionStatus.applicationNotificationsDisabled,
    );
    await expectLater(scheduler.schedule(_record()), completes);
    await expectLater(scheduler.cancel('subscription-1'), completes);
    await expectLater(
      scheduler.rescheduleAll(<SubscriptionRecord>[_record()]),
      completes,
    );
    await expectLater(scheduler.showTestNotification(), completes);
    await expectLater(scheduler.scheduleTestReminder(), completes);
  });

  test('权限检查不触发时区或调度初始化且可直接返回系统已允许', () async {
    final gateway = _RecordingNotificationGateway(permissionGranted: true)
      ..initializeFailuresRemaining = 1;
    var timeZoneLookups = 0;
    final scheduler = LocalReminderScheduler(
      gateway: gateway,
      timeZoneIdentifier: () async {
        timeZoneLookups += 1;
        throw StateError('测试不应读取时区');
      },
    );

    expect(
      await scheduler.requestPermission(),
      ReminderPermissionStatus.allowed,
    );
    expect(gateway.permissionRequests, 1);
    expect(gateway.channelChecks, 1);
    expect(gateway.initializeCalls, 0);
    expect(timeZoneLookups, 0);
  });

  test('应用总通知被禁用时不继续创建或查询提醒通道', () async {
    final gateway = _RecordingNotificationGateway(permissionGranted: false);
    final scheduler = LocalReminderScheduler(gateway: gateway);

    expect(
      await scheduler.requestPermission(),
      ReminderPermissionStatus.applicationNotificationsDisabled,
    );
    expect(gateway.permissionRequests, 1);
    expect(gateway.channelChecks, 0);
    expect(gateway.initializeCalls, 0);
  });

  test('应用总通知允许但提醒通道被禁用时返回独立状态', () async {
    final gateway = _RecordingNotificationGateway(channelEnabled: false);
    final scheduler = LocalReminderScheduler(gateway: gateway);

    expect(
      await scheduler.requestPermission(),
      ReminderPermissionStatus.reminderChannelDisabled,
    );
    expect(gateway.permissionRequests, 1);
    expect(gateway.channelChecks, 1);
    expect(gateway.initializeCalls, 0);
  });

  test('调度初始化失败不会缓存失败Future且下一次操作可重试', () async {
    final gateway = _RecordingNotificationGateway()
      ..initializeFailuresRemaining = 1;
    var timeZoneLookups = 0;
    final scheduler = LocalReminderScheduler(
      gateway: gateway,
      timeZoneIdentifier: () async {
        timeZoneLookups += 1;
        return 'Asia/Shanghai';
      },
    );

    await expectLater(
      scheduler.cancelAll(),
      throwsA(
        isA<ReminderSchedulingException>().having(
          (error) => error.stages,
          'stages',
          <ReminderFailureStage>{ReminderFailureStage.initialize},
        ),
      ),
    );
    await expectLater(scheduler.cancelAll(), completes);

    expect(gateway.initializeCalls, 2);
    expect(timeZoneLookups, 2);
    expect(gateway.cancelAllCalls, 1);
  });

  test('未知厂商时区按目标日期本机偏移保持单次提醒墙上时间', () async {
    final gateway = _RecordingNotificationGateway();
    final scheduler = LocalReminderScheduler(
      gateway: gateway,
      now: () => DateTime(2026, 3, 1, 8),
      timeZoneIdentifier: () async => 'Vendor/Beijing-Standard-Time',
      timeZoneOffsetAt: (_) => const Duration(hours: 8),
    );

    await scheduler.schedule(_record(), reminderTimeMinutes: 9 * 60 + 45);

    expect(gateway.scheduled, hasLength(1));
    final call = gateway.scheduled.single;
    expect(call.title, '订阅提醒');
    expect(call.body, '订阅事项 · 即将续费');
    expect(call.scheduledDate.year, 2026);
    expect(call.scheduledDate.month, 3);
    expect(call.scheduledDate.day, 24);
    expect(call.scheduledDate.hour, 9);
    expect(call.scheduledDate.minute, 45);
    expect(call.scheduledDate.timeZoneOffset, const Duration(hours: 8));
    expect(call.scheduledDate.location.name, '+08:00');
    expect(call.scheduledDate.toUtc(), DateTime.utc(2026, 3, 24, 1, 45));
  });

  test('厂商时区查询异常仍可用目标日期本机偏移安排提醒', () async {
    final gateway = _RecordingNotificationGateway();
    final scheduler = LocalReminderScheduler(
      gateway: gateway,
      now: () => DateTime(2026, 3, 1, 8),
      timeZoneIdentifier: () async => throw StateError('测试时区插件异常'),
      timeZoneOffsetAt: (_) => const Duration(hours: 5, minutes: 30),
    );

    await expectLater(scheduler.schedule(_record()), completes);

    final scheduled = gateway.scheduled.single.scheduledDate;
    expect(scheduled.hour, 12);
    expect(scheduled.minute, 30);
    expect(scheduled.timeZoneOffset, const Duration(hours: 5, minutes: 30));
    expect(scheduled.location.name, '+05:30');
    expect(gateway.initializeCalls, 1);
  });

  test('每次全量重排刷新设备时区且日期提醒保持新时区墙上时间', () async {
    final gateway = _RecordingNotificationGateway();
    var identifier = 'Asia/Shanghai';
    var timeZoneLookups = 0;
    final scheduler = LocalReminderScheduler(
      gateway: gateway,
      now: () => DateTime(2026, 3, 1, 8),
      timeZoneIdentifier: () async {
        timeZoneLookups += 1;
        return identifier;
      },
      targetPlatform: TargetPlatform.android,
    );

    await scheduler.rescheduleAll(<SubscriptionRecord>[_record()]);
    final shanghai = gateway.scheduled.last.scheduledDate;

    identifier = 'America/New_York';
    await scheduler.rescheduleAll(<SubscriptionRecord>[_record()]);
    final newYork = gateway.scheduled.last.scheduledDate;

    expect(timeZoneLookups, 2);
    expect(shanghai.location.name, 'Asia/Shanghai');
    expect(newYork.location.name, 'America/New_York');
    expect(shanghai.hour, 12);
    expect(shanghai.minute, 30);
    expect(newYork.hour, 12);
    expect(newYork.minute, 30);
    expect(shanghai.toUtc(), DateTime.utc(2026, 3, 24, 4, 30));
    expect(newYork.toUtc(), DateTime.utc(2026, 3, 24, 16, 30));
  });

  test('全量重排刷新时区但精确延期始终保留同一UTC瞬时', () async {
    final gateway = _RecordingNotificationGateway();
    var identifier = 'Asia/Shanghai';
    var timeZoneLookups = 0;
    final exact = DateTime.utc(2026, 3, 24, 5, 30);
    final record = _record(
      id: 'exact-time-zone',
    ).snoozeReminder(SubscriptionSnoozeTarget.exactInstant(exact));
    final scheduler = LocalReminderScheduler(
      gateway: gateway,
      now: () => DateTime.utc(2026, 3, 1),
      timeZoneIdentifier: () async {
        timeZoneLookups += 1;
        return identifier;
      },
      targetPlatform: TargetPlatform.android,
    );

    await scheduler.rescheduleAll(<SubscriptionRecord>[record]);
    final shanghai = gateway.scheduled.last.scheduledDate;

    identifier = 'America/New_York';
    await scheduler.rescheduleAll(<SubscriptionRecord>[record]);
    final newYork = gateway.scheduled.last.scheduledDate;

    expect(timeZoneLookups, 2);
    expect(shanghai.location.name, 'Asia/Shanghai');
    expect(newYork.location.name, 'America/New_York');
    expect(shanghai.toUtc(), exact);
    expect(newYork.toUtc(), exact);
    expect(shanghai.hour, 13);
    expect(newYork.hour, 1);
  });

  test('固定偏移名称可由 Android ZoneId 识别', () {
    expect(javaZoneOffsetIdentifier(Duration.zero), 'UTC');
    expect(javaZoneOffsetIdentifier(const Duration(hours: 8)), '+08:00');
    expect(
      javaZoneOffsetIdentifier(const Duration(hours: 5, minutes: 30)),
      '+05:30',
    );
    expect(
      javaZoneOffsetIdentifier(const Duration(hours: -3, minutes: -30)),
      '-03:30',
    );
    expect(
      () => javaZoneOffsetIdentifier(const Duration(hours: 19)),
      throwsArgumentError,
    );
  });

  test('未知厂商时区支持UTC与负偏移并保留墙上时间', () async {
    for (final testCase in <(Duration, String)>[
      (Duration.zero, 'UTC'),
      (const Duration(hours: -7), '-07:00'),
    ]) {
      final gateway = _RecordingNotificationGateway();
      final scheduler = LocalReminderScheduler(
        gateway: gateway,
        now: () => DateTime(2026, 3, 1, 8),
        timeZoneIdentifier: () async => 'Vendor/Unknown-Time-Zone',
        timeZoneOffsetAt: (_) => testCase.$1,
      );

      await scheduler.schedule(_record());

      final scheduled = gateway.scheduled.single.scheduledDate;
      expect(scheduled.location.name, testCase.$2);
      expect(scheduled.timeZoneOffset, testCase.$1);
      expect(scheduled.hour, 12);
      expect(scheduled.minute, 30);
    }
  });

  test('Android可安排第61条提醒而iOS仍保留60条安全上限', () async {
    final records = List<SubscriptionRecord>.generate(
      61,
      (index) => _record(
        id: 'capacity-$index',
        nextRenewalOn: DateTime(2026, 3, 31 + index),
      ),
      growable: false,
    );

    for (final testCase in <(TargetPlatform, int)>[
      (TargetPlatform.android, 61),
      (TargetPlatform.iOS, 60),
    ]) {
      final gateway = _RecordingNotificationGateway();
      final scheduler = LocalReminderScheduler(
        gateway: gateway,
        now: () => DateTime(2026, 3, 1, 8),
        timeZoneIdentifier: () async => 'Asia/Shanghai',
        targetPlatform: testCase.$1,
      );

      await scheduler.rescheduleAll(records);

      expect(gateway.scheduleAttempts, hasLength(testCase.$2));
      expect(gateway.cancelAllCalls, 0);
    }
  });

  test('陈旧记录先过滤且不占用iOS最近60条容量', () async {
    final expired = List<SubscriptionRecord>.generate(
      65,
      (index) =>
          _record(id: 'expired-$index', nextRenewalOn: DateTime(2026, 2, 1)),
      growable: false,
    );
    final future = List<SubscriptionRecord>.generate(
      61,
      (index) => _record(
        id: 'future-$index',
        nextRenewalOn: DateTime(2026, 4, 1 + index),
      ),
      growable: false,
    );
    final gateway = _RecordingNotificationGateway();
    for (final subscription in expired) {
      gateway.seedBusinessReminder(reminderNotificationId(subscription.id));
    }
    final scheduler = LocalReminderScheduler(
      gateway: gateway,
      now: () => DateTime(2026, 3, 1, 8),
      timeZoneIdentifier: () async => 'Asia/Shanghai',
      targetPlatform: TargetPlatform.iOS,
    );

    await scheduler.rescheduleAll(<SubscriptionRecord>[...expired, ...future]);

    final futureIds = future
        .map((record) => reminderNotificationId(record.id))
        .toSet();
    expect(gateway.scheduleAttempts, hasLength(60));
    expect(gateway.scheduleAttempts.every(futureIds.contains), isTrue);
    expect(
      gateway.cancelAttempts.toSet(),
      containsAll(expired.map((record) => reminderNotificationId(record.id))),
    );
  });

  test('续费日虽已过但用户明确延期到未来的提醒仍会保留', () async {
    final snoozed = _record(
      id: 'future-snooze',
      nextRenewalOn: DateTime(2026, 2, 1),
    ).snoozeReminderUntil(DateTime(2026, 3, 10));
    final gateway = _RecordingNotificationGateway();
    final scheduler = LocalReminderScheduler(
      gateway: gateway,
      now: () => DateTime(2026, 3, 1, 8),
      timeZoneIdentifier: () async => 'Asia/Shanghai',
      targetPlatform: TargetPlatform.android,
    );

    await scheduler.rescheduleAll(<SubscriptionRecord>[snoozed]);

    expect(gateway.scheduleAttempts, <int>[reminderNotificationId(snoozed.id)]);
    expect(gateway.scheduled.single.scheduledDate.day, 10);
  });

  test('精确延后以同一绝对瞬时调度到目标设备时区', () async {
    final exact = DateTime.utc(2026, 8, 30, 4, 30);
    final snoozed = _record(
      id: 'exact-hour-snooze',
      nextRenewalOn: DateTime(2026, 9, 1),
    ).snoozeReminder(SubscriptionSnoozeTarget.exactInstant(exact));
    final gateway = _RecordingNotificationGateway();
    final scheduler = LocalReminderScheduler(
      gateway: gateway,
      now: () => DateTime.utc(2026, 8, 29, 20),
      timeZoneIdentifier: () async => 'Asia/Shanghai',
      targetPlatform: TargetPlatform.android,
    );

    await scheduler.rescheduleAll(<SubscriptionRecord>[
      snoozed,
    ], reminderTimeMinutes: 23 * 60 + 59);

    expect(gateway.scheduled, hasLength(1));
    expect(gateway.scheduled.single.scheduledDate.toUtc(), exact);
    expect(gateway.scheduled.single.scheduledDate.hour, 12);
    expect(gateway.scheduled.single.scheduledDate.minute, 30);
  });

  test('差量重排先取消旧计划再写入目标且聚合部分失败', () async {
    final failedId = reminderNotificationId('subscription-2');
    final staleSuccessId = reminderNotificationId('stale-success');
    final staleFailureId = reminderNotificationId('stale-failure');
    const scheduledTestId = 0x7ffffffd;
    const unrelatedId = 0x70000000;
    final gateway = _RecordingNotificationGateway()
      ..seedBusinessReminder(failedId)
      ..seedBusinessReminder(staleSuccessId)
      ..seedBusinessReminder(staleFailureId)
      ..seedPending(
        const PendingReminderNotification(
          id: scheduledTestId,
          title: '通知测试',
          body: '这是一条本机测试提醒，不包含账号或订阅信息。',
        ),
      )
      ..seedPending(
        const PendingReminderNotification(
          id: unrelatedId,
          title: '其他本机通知',
          body: '不由订阅提醒调度器管理。',
        ),
      )
      ..scheduleFailures.add(failedId)
      ..cancelFailures.add(staleFailureId);
    final scheduler = LocalReminderScheduler(
      gateway: gateway,
      now: () => DateTime(2026, 3, 1, 8),
      timeZoneIdentifier: () async => 'Asia/Shanghai',
      targetPlatform: TargetPlatform.android,
    );

    late ReminderSchedulingException captured;
    try {
      await scheduler.rescheduleAll(<SubscriptionRecord>[
        _record(id: 'subscription-1'),
        _record(id: 'subscription-2', nextRenewalOn: DateTime(2026, 4, 1)),
        _record(id: 'subscription-3', nextRenewalOn: DateTime(2026, 4, 2)),
      ]);
      fail('应返回聚合失败');
    } on ReminderSchedulingException catch (error) {
      captured = error;
    }

    expect(gateway.cancelAllCalls, 0);
    expect(gateway.scheduleAttempts, hasLength(3));
    expect(
      gateway.scheduleAttempts,
      containsAll(<int>[
        reminderNotificationId('subscription-1'),
        failedId,
        reminderNotificationId('subscription-3'),
      ]),
    );
    final lastSchedule = gateway.operationOrder.lastIndexWhere(
      (operation) => operation.startsWith('schedule:'),
    );
    final firstCancel = gateway.operationOrder.indexWhere(
      (operation) => operation.startsWith('cancel:'),
    );
    expect(firstCancel, lessThan(lastSchedule));
    expect(captured.failures, hasLength(2));
    expect(captured.stages, <ReminderFailureStage>{
      ReminderFailureStage.cancel,
      ReminderFailureStage.schedule,
    });
    expect(
      captured.failures
          .singleWhere(
            (failure) => failure.stage == ReminderFailureStage.schedule,
          )
          .subscriptionId,
      'subscription-2',
    );
    expect(gateway.pending, isNot(contains(failedId)));
    expect(gateway.pending, isNot(contains(staleSuccessId)));
    expect(gateway.pending, contains(staleFailureId));
    expect(gateway.pending, contains(scheduledTestId));
    expect(gateway.pending, contains(unrelatedId));
  });

  test('并发重排严格串行且后调用快照决定最终待发队列', () async {
    final first = _record(id: 'concurrent-first');
    final second = _record(id: 'concurrent-second');
    final firstId = reminderNotificationId(first.id);
    final secondId = reminderNotificationId(second.id);
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final gateway = _RecordingNotificationGateway()
      ..scheduleStartedSignals[firstId] = firstStarted
      ..scheduleBarriers[firstId] = releaseFirst.future;
    final scheduler = LocalReminderScheduler(
      gateway: gateway,
      now: () => DateTime(2026, 3, 1, 8),
      timeZoneIdentifier: () async => 'Asia/Shanghai',
      targetPlatform: TargetPlatform.android,
    );

    final firstCall = scheduler.rescheduleAll(<SubscriptionRecord>[first]);
    await firstStarted.future;
    final secondCall = scheduler.rescheduleAll(<SubscriptionRecord>[second]);
    await Future<void>.delayed(Duration.zero);

    expect(gateway.scheduleAttempts, <int>[firstId]);
    releaseFirst.complete();
    await firstCall;
    await secondCall;

    final businessPendingIds = gateway.pending.values
        .where(
          (request) =>
              request.title == '订阅提醒' &&
              request.payload == reminderNavigationPayload,
        )
        .map((request) => request.id)
        .toSet();
    expect(businessPendingIds, <int>{secondId});
  });

  test('一次排队重排失败不会阻断后续重排', () async {
    final failed = _record(id: 'queued-failure');
    final succeeding = _record(id: 'queued-success');
    final failedId = reminderNotificationId(failed.id);
    final succeedingId = reminderNotificationId(succeeding.id);
    final gateway = _RecordingNotificationGateway()
      ..scheduleFailures.add(failedId);
    final scheduler = LocalReminderScheduler(
      gateway: gateway,
      now: () => DateTime(2026, 3, 1, 8),
      timeZoneIdentifier: () async => 'Asia/Shanghai',
      targetPlatform: TargetPlatform.android,
    );

    final failedCall = scheduler.rescheduleAll(<SubscriptionRecord>[failed]);
    final succeedingCall = scheduler.rescheduleAll(<SubscriptionRecord>[
      succeeding,
    ]);

    await expectLater(failedCall, throwsA(isA<ReminderSchedulingException>()));
    await expectLater(succeedingCall, completes);
    expect(gateway.pending, contains(succeedingId));
  });

  test('即时测试通知与一分钟测试提醒只使用通用隐私文案', () async {
    final gateway = _RecordingNotificationGateway();
    final scheduler = LocalReminderScheduler(
      gateway: gateway,
      now: () => DateTime(2026, 3, 1, 8),
      timeZoneIdentifier: () async => 'Asia/Shanghai',
    );

    await scheduler.showTestNotification();
    await scheduler.scheduleTestReminder();

    expect(gateway.shown, hasLength(1));
    expect(gateway.shown.single.id, 0x7ffffffe);
    expect(gateway.shown.single.title, '通知测试');
    expect(gateway.shown.single.body, '这是一条本机测试通知，不包含账号或订阅信息。');
    final scheduled = gateway.scheduled.single;
    expect(scheduled.id, 0x7ffffffd);
    expect(scheduled.id, greaterThan(maximumBusinessReminderNotificationId));
    expect(scheduled.title, '通知测试');
    expect(scheduled.body, '这是一条本机测试提醒，不包含账号或订阅信息。');
    expect(scheduled.useExactAlarm, isTrue);
    expect(
      scheduled.scheduledDate,
      tz.TZDateTime(tz.getLocation('Asia/Shanghai'), 2026, 3, 1, 8, 1),
    );
  });

  test('精确闹钟未授权时保留非精确休眠调度而不丢提醒', () async {
    final gateway = _RecordingNotificationGateway(exactAlarmsAllowed: false);
    final scheduler = LocalReminderScheduler(
      gateway: gateway,
      now: () => DateTime(2026, 3, 1, 8),
      timeZoneIdentifier: () async => 'Asia/Shanghai',
    );

    await scheduler.scheduleTestReminder();

    expect(gateway.scheduled, hasLength(1));
    expect(gateway.scheduled.single.useExactAlarm, isFalse);
  });

  test('测试提醒拒绝非正延迟且不初始化插件', () async {
    final gateway = _RecordingNotificationGateway();
    final scheduler = LocalReminderScheduler(gateway: gateway);

    await expectLater(
      scheduler.scheduleTestReminder(delay: Duration.zero),
      throwsArgumentError,
    );
    expect(gateway.initializeCalls, 0);
  });

  test('待发数量只包含业务提醒和1分钟测试提醒', () async {
    final gateway = _RecordingNotificationGateway()
      ..seedBusinessReminder(reminderNotificationId('subscription-1'))
      ..seedPending(
        const PendingReminderNotification(
          id: 0x7ffffffd,
          title: '通知测试',
          body: '这是一条本机测试提醒，不包含账号或订阅信息。',
        ),
      )
      ..seedPending(
        const PendingReminderNotification(
          id: 0x70000000,
          title: '其他本机通知',
          body: '不由订阅提醒调度器管理。',
        ),
      );
    final scheduler = LocalReminderScheduler(gateway: gateway);

    expect(await scheduler.pendingReminderCount(), 2);
    expect(gateway.pendingRequestCalls, 1);
  });
}

SubscriptionRecord _record({
  String id = 'subscription-1',
  DateTime? nextRenewalOn,
}) => SubscriptionRecord.fromDraft(
  id: id,
  draft: SubscriptionDraft(
    accountId: 'account-1',
    details: SubscriptionDetailsDraft(
      serviceName: '隐私提醒测试',
      firstSubscribedOn: DateTime(2026, 1, 31),
      nextRenewalOn: nextRenewalOn ?? DateTime(2026, 3, 31),
      reminderDaysBefore: 7,
    ),
  ),
);

final class _ScheduledNotificationCall {
  const _ScheduledNotificationCall({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledDate,
    required this.useExactAlarm,
  });

  final int id;
  final String title;
  final String body;
  final tz.TZDateTime scheduledDate;
  final bool useExactAlarm;
}

final class _ShownNotificationCall {
  const _ShownNotificationCall({
    required this.id,
    required this.title,
    required this.body,
  });

  final int id;
  final String title;
  final String body;
}

final class _RecordingNotificationGateway
    implements ReminderNotificationGateway {
  _RecordingNotificationGateway({
    this.permissionGranted = true,
    this.channelEnabled = true,
    this.exactAlarmsAllowed = true,
  });

  final bool permissionGranted;
  final bool channelEnabled;
  final bool exactAlarmsAllowed;
  int initializeFailuresRemaining = 0;
  int permissionRequests = 0;
  int channelChecks = 0;
  int initializeCalls = 0;
  int pendingRequestCalls = 0;
  int cancelAllCalls = 0;
  bool pendingRequestsShouldFail = false;
  bool cancelAllShouldFail = false;
  final Set<int> scheduleFailures = <int>{};
  final Set<int> cancelFailures = <int>{};
  final Map<int, Completer<void>> scheduleStartedSignals =
      <int, Completer<void>>{};
  final Map<int, Future<void>> scheduleBarriers = <int, Future<void>>{};
  final List<int> scheduleAttempts = <int>[];
  final List<int> cancelAttempts = <int>[];
  final List<String> operationOrder = <String>[];
  final Map<int, PendingReminderNotification> pending =
      <int, PendingReminderNotification>{};
  final List<_ScheduledNotificationCall> scheduled =
      <_ScheduledNotificationCall>[];
  final List<_ShownNotificationCall> shown = <_ShownNotificationCall>[];

  bool revokeExactOnSchedule = false;

  void seedBusinessReminder(int id) {
    seedPending(
      PendingReminderNotification(
        id: id,
        title: '订阅提醒',
        body: '有一项本机订阅记录需要查看，请解锁应用确认。',
      ),
    );
  }

  void seedPending(PendingReminderNotification request) {
    pending[request.id] = request;
  }

  @override
  Future<bool> requestApplicationPermission() async {
    permissionRequests += 1;
    return permissionGranted;
  }

  @override
  Future<bool> ensureReminderChannelEnabled() async {
    channelChecks += 1;
    return channelEnabled;
  }

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    if (initializeFailuresRemaining > 0) {
      initializeFailuresRemaining -= 1;
      throw StateError('测试调度初始化失败');
    }
  }

  @override
  Future<bool> canScheduleExactNotifications() async => exactAlarmsAllowed;

  @override
  Future<List<PendingReminderNotification>>
  pendingNotificationRequests() async {
    pendingRequestCalls += 1;
    operationOrder.add('inspect');
    if (pendingRequestsShouldFail) {
      throw StateError('测试读取待发提醒失败');
    }
    return pending.values.toList(growable: false);
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required bool useExactAlarm,
    String? payload,
  }) async {
    scheduleAttempts.add(id);
    if (revokeExactOnSchedule && useExactAlarm) {
      throw PlatformException(code: 'exact_alarms_not_permitted');
    }
    operationOrder.add('schedule:$id');
    scheduleStartedSignals.remove(id)?.complete();
    final barrier = scheduleBarriers.remove(id);
    if (barrier != null) {
      await barrier;
    }
    if (scheduleFailures.contains(id)) {
      throw StateError('测试单条调度失败');
    }
    scheduled.add(
      _ScheduledNotificationCall(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        useExactAlarm: useExactAlarm,
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
  }) async {
    shown.add(_ShownNotificationCall(id: id, title: title, body: body));
  }

  @override
  Future<void> cancel(int id) async {
    cancelAttempts.add(id);
    operationOrder.add('cancel:$id');
    if (cancelFailures.contains(id)) {
      throw StateError('测试单条取消失败');
    }
    pending.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls += 1;
    if (cancelAllShouldFail) {
      throw StateError('测试取消全部提醒失败');
    }
    pending.clear();
  }
}
