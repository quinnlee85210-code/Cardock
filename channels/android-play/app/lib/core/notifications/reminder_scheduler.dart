import '../preferences/notification_privacy_preferences.dart';
import 'subscription_notification_content.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../preferences/language_preferences.dart';
import '../../features/subscriptions/domain/subscription_record.dart';

/// Notifications deliberately use generic copy so no platform, account, or
/// amount can leak onto the lock screen.
@immutable
final class ReminderNotificationCopy {
  const ReminderNotificationCopy({
    required this.channelName,
    required this.channelDescription,
    required this.privacyTitle,
    required this.privacyBody,
    required this.testTitle,
    required this.immediateTestBody,
    required this.scheduledTestBody,
    required this.passwordReviewTitle,
    required this.passwordReviewBody,
  });

  final String channelName;
  final String channelDescription;
  final String privacyTitle;
  final String privacyBody;
  final String testTitle;
  final String immediateTestBody;
  final String scheduledTestBody;
  final String passwordReviewTitle;
  final String passwordReviewBody;
}

@visibleForTesting
ReminderNotificationCopy reminderNotificationCopyFor(
  CardockLanguage language,
) => switch (language) {
  CardockLanguage.simplifiedChinese => const ReminderNotificationCopy(
    channelName: '本机订阅提醒',
    channelDescription: '在本机提示订阅记录即将续费或到期',
    privacyTitle: '订阅提醒',
    privacyBody: '有一项本机订阅记录需要查看，请解锁应用确认。',
    testTitle: '通知测试',
    immediateTestBody: '这是一条本机测试通知，不包含账号或订阅信息。',
    scheduledTestBody: '这是一条本机测试提醒，不包含账号或订阅信息。',
    passwordReviewTitle: '安全复核提醒',
    passwordReviewBody: '有本机密码记录需要核对，请解锁应用查看。',
  ),
  CardockLanguage.english => const ReminderNotificationCopy(
    channelName: 'On-device subscription reminders',
    channelDescription: 'Reminders for upcoming renewals or expirations',
    privacyTitle: 'Subscription reminder',
    privacyBody:
        'A local subscription record needs your attention. Unlock the app to review it.',
    testTitle: 'Notification test',
    immediateTestBody:
        'This is a local test notification. It contains no account or subscription details.',
    scheduledTestBody:
        'This is a local test reminder. It contains no account or subscription details.',
    passwordReviewTitle: 'Security review reminder',
    passwordReviewBody:
        'A local password record needs review. Unlock the app to view it.',
  ),
  CardockLanguage.japanese => const ReminderNotificationCopy(
    channelName: '端末内のサブスクリプション通知',
    channelDescription: '更新日または有効期限が近い記録を端末内で通知します',
    privacyTitle: 'サブスクリプションのお知らせ',
    privacyBody: '確認が必要な端末内の記録があります。アプリのロックを解除して確認してください。',
    testTitle: '通知テスト',
    immediateTestBody: 'これは端末内のテスト通知です。アカウントやサブスクリプションの情報は含まれません。',
    scheduledTestBody: 'これは端末内のテストリマインダーです。アカウントやサブスクリプションの情報は含まれません。',
    passwordReviewTitle: 'セキュリティ確認のお知らせ',
    passwordReviewBody: '確認が必要な端末内のパスワード記録があります。アプリのロックを解除して確認してください。',
  ),
};

/// 可注入的本机提醒边界。数据保存不应依赖系统通知是否成功。
enum ReminderPermissionStatus {
  allowed,
  applicationNotificationsDisabled,
  reminderChannelDisabled,
}

/// 系统提醒失败所处的阶段，供界面给出稳定提示并支持后续诊断。
enum ReminderFailureStage { initialize, cancel, schedule, showTestNotification }

/// 单个提醒操作失败。对外字符串不包含订阅、账号或插件异常详情。
final class ReminderOperationFailure {
  const ReminderOperationFailure({
    required this.stage,
    required this.cause,
    required this.stackTrace,
    this.subscriptionId,
  });

  final ReminderFailureStage stage;
  final String? subscriptionId;
  final Object cause;
  final StackTrace stackTrace;
}

/// 一次操作可能包含多个失败，例如重排时某一条失败但其余条目仍继续。
final class ReminderSchedulingException implements Exception {
  ReminderSchedulingException(Iterable<ReminderOperationFailure> failures)
    : failures = List<ReminderOperationFailure>.unmodifiable(failures) {
    if (this.failures.isEmpty) {
      throw ArgumentError.value(failures, 'failures', '不能为空');
    }
  }

  final List<ReminderOperationFailure> failures;

  Set<ReminderFailureStage> get stages =>
      Set<ReminderFailureStage>.unmodifiable(
        failures.map((failure) => failure.stage),
      );

  @override
  String toString() =>
      'ReminderSchedulingException(${failures.length} operation(s) failed)';
}

abstract interface class ReminderScheduler {
  Future<ReminderPermissionStatus> requestPermission();

  /// The app passes both saved times. Omitting the second slot retains the
  /// single-time API for date calculations and explicit one-time callers.
  Future<void> schedule(
    SubscriptionRecord subscription, {
    int reminderTimeMinutes = 12 * 60 + 30,
    int? secondReminderTimeMinutes,
  });

  Future<void> cancel(String subscriptionId);

  Future<void> cancelAll();

  Future<void> rescheduleAll(
    Iterable<SubscriptionRecord> subscriptions, {
    int reminderTimeMinutes = 12 * 60 + 30,
    int? secondReminderTimeMinutes,
    DateTime? passwordReviewAtUtc,
  });

  /// 返回由本调度器管理的待发业务提醒与定时测试提醒总数。
  ///
  /// 不返回通知 payload，也不包含账号、订阅或金额内容。
  Future<int> pendingReminderCount();

  /// 立即显示一条不含账号或订阅信息的本机测试通知。
  Future<void> showTestNotification();

  /// 安排一条不含账号或订阅信息的测试提醒，默认一分钟后触发。
  Future<void> scheduleTestReminder({
    Duration delay = const Duration(minutes: 1),
  });
}

/// Optional capability used when the selected app language changes.
///
/// Callers can update the copy and then reschedule existing reminders so every
/// pending notification uses the newly selected language.
abstract interface class LanguageAwareReminderScheduler {
  void updateLanguage(CardockLanguage language);
}

final class NoopReminderScheduler implements ReminderScheduler {
  const NoopReminderScheduler();

  @override
  Future<ReminderPermissionStatus> requestPermission() async =>
      ReminderPermissionStatus.applicationNotificationsDisabled;

  @override
  Future<void> schedule(
    SubscriptionRecord subscription, {
    int reminderTimeMinutes = 12 * 60 + 30,
    int? secondReminderTimeMinutes,
  }) async {}

  @override
  Future<void> cancel(String subscriptionId) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> rescheduleAll(
    Iterable<SubscriptionRecord> subscriptions, {
    int reminderTimeMinutes = 12 * 60 + 30,
    int? secondReminderTimeMinutes,
    DateTime? passwordReviewAtUtc,
  }) async {}

  @override
  Future<int> pendingReminderCount() async => 0;

  @override
  Future<void> showTestNotification() async {}

  @override
  Future<void> scheduleTestReminder({
    Duration delay = const Duration(minutes: 1),
  }) async {}
}

/// 将通知插件隔离在可替换边界后面，避免权限检查被时区或调度初始化连带阻断。
@visibleForTesting
abstract interface class ReminderNotificationGateway {
  Future<bool> requestApplicationPermission();

  Future<bool> ensureReminderChannelEnabled();

  Future<void> initialize();

  /// Android 12+ 是否已允许精确闹钟；其他平台返回 true。
  Future<bool> canScheduleExactNotifications();

  Future<List<PendingReminderNotification>> pendingNotificationRequests();

  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required bool useExactAlarm,
    String? payload,
  });

  Future<void> show({
    required int id,
    required String title,
    required String body,
  });

  Future<void> cancel(int id);

  Future<void> cancelAll();
}

/// 插件待发队列中用于差量清理的最小非敏感视图。
///
/// 不暴露 payload 或业务记录；现有提醒只靠固定通用文案识别，以兼容
/// 0.5.1 已保存的插件队列。
@visibleForTesting
final class PendingReminderNotification {
  const PendingReminderNotification({
    required this.id,
    required this.title,
    required this.body,
    this.payload,
  });

  final String? payload;
  final int id;
  final String? title;
  final String? body;
}

final class _FlutterReminderNotificationGateway
    implements ReminderNotificationGateway {
  _FlutterReminderNotificationGateway(
    FlutterLocalNotificationsPlugin plugin,
    CardockLanguage language,
  ) : _plugin = plugin,
      _language = language;

  VoidCallback? onOpen;
  void _handleOpen(String? payload) {
    if (payload == reminderNavigationPayload) onOpen?.call();
  }

  static const _channelId = 'local_subscription_reminders';

  final FlutterLocalNotificationsPlugin _plugin;
  CardockLanguage _language;

  ReminderNotificationCopy get _copy => reminderNotificationCopyFor(_language);

  void updateLanguage(CardockLanguage language) {
    _language = language;
  }

  @override
  Future<bool> requestApplicationPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      // Android 13+ 会申请 POST_NOTIFICATIONS；Android 12 及以下返回系统
      // 当前的通知启用状态，因此已允许通知时可以直接得到 true。
      final requested = await android.requestNotificationsPermission() ?? true;
      if (!requested) {
        return false;
      }
      return await android.areNotificationsEnabled() ?? requested;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return true;
  }

  @override
  Future<bool> ensureReminderChannelEnabled() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) {
      return true;
    }

    await android.createNotificationChannel(
      AndroidNotificationChannel(
        _channelId,
        _copy.channelName,
        description: _copy.channelDescription,
        importance: Importance.defaultImportance,
      ),
    );
    final channels = await android.getNotificationChannels();
    if (channels == null) {
      return true;
    }
    for (final channel in channels) {
      if (channel.id == _channelId) {
        return channel.importance != Importance.none;
      }
    }
    // Android 8 以下没有通知通道；创建与查询均是兼容性空操作。
    return true;
  }

  @override
  Future<void> initialize() async {
    await _plugin.initialize(
      onDidReceiveNotificationResponse: (response) =>
          _handleOpen(response.payload),
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _handleOpen(launch?.notificationResponse?.payload);
    }
  }

  @override
  Future<List<PendingReminderNotification>>
  pendingNotificationRequests() async {
    final pending = await _plugin.pendingNotificationRequests();
    return <PendingReminderNotification>[
      for (final request in pending)
        PendingReminderNotification(
          id: request.id,
          title: request.title,
          body: request.body,
          payload: request.payload,
        ),
    ];
  }

  @override
  Future<bool> canScheduleExactNotifications() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return true;
    return await android.canScheduleExactNotifications() ?? false;
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required bool useExactAlarm,
    String? payload,
  }) => _plugin.zonedSchedule(
    id: id,
    title: title,
    body: body,
    scheduledDate: scheduledDate,
    payload: payload,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _copy.channelName,
        channelDescription: _copy.channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.private,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
      ),
    ),
    androidScheduleMode: useExactAlarm
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle,
  );

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) => _plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _copy.channelName,
        channelDescription: _copy.channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.private,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
      ),
    ),
  );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}

/// 使用系统通知的实现。通知标题与正文固定为隐私文案，不写入账号、平台或金额。
abstract interface class PrivacyAwareReminderScheduler {
  void updatePrivacy(NotificationPrivacy privacy);
}

const reminderNavigationPayload = 'cardock.reminders.v1';

final class LocalReminderScheduler
    implements
        ReminderScheduler,
        LanguageAwareReminderScheduler,
        PrivacyAwareReminderScheduler {
  LocalReminderScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    DateTime Function()? now,
    @visibleForTesting ReminderNotificationGateway? gateway,
    @visibleForTesting Future<String> Function()? timeZoneIdentifier,
    @visibleForTesting Duration Function(DateTime)? timeZoneOffsetAt,
    @visibleForTesting TargetPlatform? targetPlatform,
    CardockLanguage language = CardockLanguage.simplifiedChinese,
  }) : _gateway =
           gateway ??
           _FlutterReminderNotificationGateway(
             plugin ?? FlutterLocalNotificationsPlugin(),
             language,
           ),
       _language = language,
       _now = now ?? DateTime.now,
       _timeZoneIdentifier = timeZoneIdentifier ?? _systemTimeZoneIdentifier,
       _timeZoneOffsetAt = timeZoneOffsetAt ?? _systemTimeZoneOffsetAt,
       _targetPlatform = targetPlatform ?? defaultTargetPlatform;

  static const _immediateTestNotificationId = 0x7ffffffe;
  static const _scheduledTestNotificationId = 0x7ffffffd;
  static const _passwordReviewNotificationId = 0x7ffffffc;
  static const _iosPendingReminderLimit = 60;
  static const _androidPendingReminderLimit = 400;
  static const _fallbackPendingReminderLimit = 60;

  final ReminderNotificationGateway _gateway;
  final DateTime Function() _now;
  final Future<String> Function() _timeZoneIdentifier;
  final Duration Function(DateTime) _timeZoneOffsetAt;
  final TargetPlatform _targetPlatform;
  CardockLanguage _language;
  Future<void> _pendingMutationTail = Future<void>.value();
  Future<void>? _initializing;
  bool _initialized = false;
  tz.Location? _deviceLocation;

  ReminderNotificationCopy get _copy => reminderNotificationCopyFor(_language);

  @override
  void updateLanguage(CardockLanguage language) {
    _language = language;
    final gateway = _gateway;
    if (gateway is _FlutterReminderNotificationGateway) {
      gateway.updateLanguage(language);
    }
  }

  @override
  Future<ReminderPermissionStatus> requestPermission() async {
    if (!await _gateway.requestApplicationPermission()) {
      return ReminderPermissionStatus.applicationNotificationsDisabled;
    }
    if (!await _gateway.ensureReminderChannelEnabled()) {
      return ReminderPermissionStatus.reminderChannelDisabled;
    }
    return ReminderPermissionStatus.allowed;
  }

  @override
  Future<void> schedule(
    SubscriptionRecord subscription, {
    int reminderTimeMinutes = 12 * 60 + 30,
    int? secondReminderTimeMinutes,
  }) => _enqueuePendingMutation(() async {
    _validateReminderTime(reminderTimeMinutes);
    if (secondReminderTimeMinutes != null) {
      _validateReminderTime(secondReminderTimeMinutes);
    }
    await _ensureInitializedForOperation();
    await _scheduleAfterInitialized(
      subscription,
      reminderTimeMinutes: reminderTimeMinutes,
      secondReminderTimeMinutes: secondReminderTimeMinutes,
    );
  });

  Future<void> _scheduleAfterInitialized(
    SubscriptionRecord subscription, {
    required int reminderTimeMinutes,
    int? secondReminderTimeMinutes,
  }) async {
    final occurrences = subscriptionReminderOccurrences(
      subscription,
      reminderTimeMinutes: reminderTimeMinutes,
      secondReminderTimeMinutes: secondReminderTimeMinutes,
      now: _now(),
    );
    final owned = subscriptionReminderIds(subscription.id);
    final pending = await _gateway.pendingNotificationRequests();
    for (final request in pending.where(
      (p) => owned.contains(p.id) && _isManagedBusinessReminder(p),
    )) {
      await _runOperation(
        stage: ReminderFailureStage.cancel,
        subscriptionId: subscription.id,
        operation: () => _gateway.cancel(request.id),
      );
    }
    for (final occurrence in occurrences) {
      await _scheduleOccurrence(occurrence);
    }
  }

  NotificationPrivacy _privacy = NotificationPrivacy.privacy;
  @override
  void updatePrivacy(NotificationPrivacy privacy) {
    _privacy = privacy;
  }

  Future<void> prepareNavigation(VoidCallback onOpen) async {
    final gateway = _gateway;
    if (gateway is _FlutterReminderNotificationGateway) gateway.onOpen = onOpen;
    await _ensureInitializedForOperation();
  }

  ({String title, String body}) _content(SubscriptionReminderOccurrence p) =>
      subscriptionNotificationContent(
        summary:
            p.summary ??
            const SubscriptionPublicSummary(
              event: SubscriptionReminderEvent.renewal,
            ),
        privacy: _privacy,
        language: _language,
        count: p.count,
      );

  final Map<int, String> _occurrenceKeys = {};
  String _occurrenceKey(SubscriptionReminderOccurrence p) =>
      '${p.at.toIso8601String()}|${p.exactInstant}|${_deviceLocation?.name}|${_privacy.name}|${_content(p).title}|${_content(p).body}';

  Future<void> _scheduleOccurrence(SubscriptionReminderOccurrence occurrence) =>
      _runOperation(
        stage: ReminderFailureStage.schedule,
        subscriptionId: occurrence.subscriptionId,
        operation: () async {
          await _scheduleWithPermissionFallback(
            id: occurrence.id,
            title: _content(occurrence).title,
            body: _content(occurrence).body,
            scheduledDate: occurrence.exactInstant
                ? _asDeviceInstant(occurrence.at)
                : _asDeviceWallClock(occurrence.at),
            useExactAlarm: await _canUseExactAlarm(),
          );
          _occurrenceKeys[occurrence.id] = _occurrenceKey(occurrence);
        },
      );

  Future<void> _scheduleWithPermissionFallback({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required bool useExactAlarm,
  }) async {
    try {
      await _gateway.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        useExactAlarm: useExactAlarm,
        payload: id <= _passwordReviewNotificationId
            ? reminderNavigationPayload
            : null,
      );
    } on PlatformException catch (error) {
      if (!useExactAlarm || error.code != 'exact_alarms_not_permitted') rethrow;
      // Android may revoke permission between checking and setting the alarm.
      await _gateway.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        useExactAlarm: false,
        payload: id <= _passwordReviewNotificationId
            ? reminderNavigationPayload
            : null,
      );
    }
  }

  @override
  Future<void> cancel(String subscriptionId) => _enqueuePendingMutation(
    () async {
      await _ensureInitializedForOperation();
      final owned = subscriptionReminderIds(subscriptionId);
      final pending = await _gateway.pendingNotificationRequests();
      final ids = {
        reminderNotificationId(subscriptionId),
        ...pending
            .where((p) => owned.contains(p.id) && _isManagedBusinessReminder(p))
            .map((p) => p.id),
      };
      for (final id in ids) {
        await _runOperation(
          stage: ReminderFailureStage.cancel,
          subscriptionId: subscriptionId,
          operation: () => _gateway.cancel(id),
        );
      }
    },
  );

  @override
  Future<void> cancelAll() => _enqueuePendingMutation(() async {
    await _ensureInitializedForOperation();
    await _runOperation(
      stage: ReminderFailureStage.cancel,
      operation: _gateway.cancelAll,
    );
  });

  @override
  Future<void> rescheduleAll(
    Iterable<SubscriptionRecord> subscriptions, {
    int reminderTimeMinutes = 12 * 60 + 30,
    int? secondReminderTimeMinutes,
    DateTime? passwordReviewAtUtc,
  }) {
    final snapshot = List<SubscriptionRecord>.of(
      subscriptions,
      growable: false,
    );
    return _enqueuePendingMutation(
      () => _rescheduleAllAfterQueued(
        snapshot,
        reminderTimeMinutes: reminderTimeMinutes,
        secondReminderTimeMinutes: secondReminderTimeMinutes,
        passwordReviewAtUtc: passwordReviewAtUtc?.toUtc(),
      ),
    );
  }

  Future<void> _rescheduleAllAfterQueued(
    List<SubscriptionRecord> subscriptions, {
    required int reminderTimeMinutes,
    int? secondReminderTimeMinutes,
    required DateTime? passwordReviewAtUtc,
  }) async {
    _validateReminderTime(reminderTimeMinutes);
    if (secondReminderTimeMinutes != null) {
      _validateReminderTime(secondReminderTimeMinutes);
    }
    final now = _now();
    final desired =
        subscriptions
            .expand(
              (s) => subscriptionReminderOccurrences(
                s,
                reminderTimeMinutes: reminderTimeMinutes,
                secondReminderTimeMinutes: secondReminderTimeMinutes,
                now: now,
              ),
            )
            .toList()
          ..sort((a, b) {
            final order = a.at.compareTo(b.at);
            return order == 0 ? a.id.compareTo(b.id) : order;
          });
    if (desired.map((p) => p.id).toSet().length != desired.length) {
      throw StateError('提醒编号冲突，原队列保持不变');
    }
    final wasInitialized = _initialized;
    await _ensureInitializedForOperation();
    if (wasInitialized) await _refreshDeviceLocation();
    final grouped = _groupOccurrences(desired);
    if (grouped.map((p) => p.id).toSet().length != grouped.length) {
      throw StateError('提醒编号冲突，原队列保持不变');
    }
    final selected = grouped
        .take(_pendingReminderLimit - (passwordReviewAtUtc == null ? 0 : 1))
        .toList();
    final desiredIds = {
      for (final p in selected) p.id,
      if (passwordReviewAtUtc != null) _passwordReviewNotificationId,
    };
    final failures = <ReminderOperationFailure>[];
    final blocked = <int>{};
    // Clear the old business plan first. Test/foreign notifications are retained.
    // A failed cancellation prevents reusing that ID in this reconciliation.
    final pending = await _gateway.pendingNotificationRequests();
    final unchanged = <int>{};
    final selectedById = {for (final p in selected) p.id: p};
    for (final request in pending.where(_isManagedBusinessReminder)) {
      final wanted = selectedById[request.id];
      if (wanted != null &&
          _occurrenceKeys[request.id] == _occurrenceKey(wanted)) {
        unchanged.add(request.id);
        continue;
      }
      try {
        await _gateway.cancel(request.id);
        _occurrenceKeys.remove(request.id);
      } on Object catch (error, stack) {
        blocked.add(request.id);
        failures.add(
          ReminderOperationFailure(
            stage: ReminderFailureStage.cancel,
            cause: error,
            stackTrace: stack,
          ),
        );
      }
    }
    for (final p in selected) {
      if (blocked.contains(p.id) || unchanged.contains(p.id)) continue;
      try {
        await _scheduleOccurrence(p);
      } on ReminderSchedulingException catch (error) {
        failures.addAll(error.failures);
      } on Object catch (error, stack) {
        failures.add(
          ReminderOperationFailure(
            stage: ReminderFailureStage.schedule,
            subscriptionId: p.subscriptionId,
            cause: error,
            stackTrace: stack,
          ),
        );
      }
    }
    if (passwordReviewAtUtc != null &&
        !blocked.contains(_passwordReviewNotificationId)) {
      try {
        await _schedulePasswordReviewAfterInitialized(passwordReviewAtUtc);
      } on ReminderSchedulingException catch (error) {
        failures.addAll(error.failures);
      }
    }
    // Keep the desired ID set checked even when every point is already in the past.
    assert(desiredIds.length <= _pendingReminderLimit);
    if (failures.isNotEmpty) throw ReminderSchedulingException(failures);
  }

  List<SubscriptionReminderOccurrence> _groupOccurrences(
    List<SubscriptionReminderOccurrence> input,
  ) {
    final groups = <String, List<SubscriptionReminderOccurrence>>{};
    for (final p in input) {
      final instant = p.exactInstant
          ? _asDeviceInstant(p.at)
          : _asDeviceWallClock(p.at);
      final key = '${instant.microsecondsSinceEpoch}:${p.summary?.event.name}';
      (groups[key] ??= []).add(p);
    }
    return [
      for (final group in groups.entries)
        if (group.value.length == 1)
          group.value.single
        else
          SubscriptionReminderOccurrence(
            id: reminderNotificationId('group:${group.key}'),
            subscriptionId: '',
            at: group.value.first.at,
            exactInstant: group.value.first.exactInstant,
            summary: SubscriptionPublicSummary(
              event: group.value.first.summary!.event,
            ),
            count: group.value.map((p) => p.subscriptionId).toSet().length,
          ),
    ]..sort((a, b) {
      final order = a.at.compareTo(b.at);
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
  }

  @override
  Future<int> pendingReminderCount() async {
    // 等待先前已排队的变更完成，避免诊断页读到半更新状态。
    await _pendingMutationTail;
    await _ensureInitializedForOperation();
    final pending = await _gateway.pendingNotificationRequests();
    return pending.where(_isManagedPendingReminder).length;
  }

  @override
  Future<void> showTestNotification() async {
    await _ensureInitializedForOperation();
    await _runOperation(
      stage: ReminderFailureStage.showTestNotification,
      operation: () => _gateway.show(
        id: _immediateTestNotificationId,
        title: _copy.testTitle,
        body: _copy.immediateTestBody,
      ),
    );
  }

  @override
  Future<void> scheduleTestReminder({
    Duration delay = const Duration(minutes: 1),
  }) => _enqueuePendingMutation(() async {
    if (delay <= Duration.zero) {
      throw ArgumentError.value(delay, 'delay', '必须大于零');
    }
    await _ensureInitializedForOperation();
    await _runOperation(
      stage: ReminderFailureStage.schedule,
      operation: () async {
        final useExactAlarm = await _canUseExactAlarm();
        await _scheduleWithPermissionFallback(
          id: _scheduledTestNotificationId,
          title: _copy.testTitle,
          body: _copy.scheduledTestBody,
          scheduledDate: _asDeviceWallClock(_now().add(delay)),
          useExactAlarm: useExactAlarm,
        );
      },
    );
  });

  void _validateReminderTime(int reminderTimeMinutes) {
    if (reminderTimeMinutes < 0 || reminderTimeMinutes > 1439) {
      throw ArgumentError.value(reminderTimeMinutes, 'reminderTimeMinutes');
    }
  }

  Future<bool> _canUseExactAlarm() async {
    try {
      return await _gateway.canScheduleExactNotifications();
    } on Object {
      // 查询失败不应清空或阻断原有提醒；保留允许休眠的非精确调度，
      // 并由可靠性检查页明确显示系统授权状态。
      return false;
    }
  }

  int get _pendingReminderLimit => switch (_targetPlatform) {
    TargetPlatform.android => _androidPendingReminderLimit,
    TargetPlatform.iOS => _iosPendingReminderLimit,
    _ => _fallbackPendingReminderLimit,
  };

  bool _isManagedBusinessReminder(PendingReminderNotification request) =>
      request.payload == reminderNavigationPayload ||
      _occurrenceKeys.containsKey(request.id) ||
      CardockLanguage.values
          .map(reminderNotificationCopyFor)
          .any(
            (copy) =>
                (request.title == copy.privacyTitle &&
                    request.body == copy.privacyBody) ||
                (request.id == _passwordReviewNotificationId &&
                    request.title == copy.passwordReviewTitle &&
                    request.body == copy.passwordReviewBody),
          );

  Future<void> _schedulePasswordReviewAfterInitialized(
    DateTime passwordReviewAtUtc,
  ) async {
    var scheduled = passwordReviewAtUtc.toUtc();
    final now = _now().toUtc();
    if (!scheduled.isAfter(now)) {
      scheduled = now.add(const Duration(minutes: 1));
    }
    await _runOperation(
      stage: ReminderFailureStage.schedule,
      operation: () async {
        final useExactAlarm = await _canUseExactAlarm();
        await _scheduleWithPermissionFallback(
          id: _passwordReviewNotificationId,
          title: _copy.passwordReviewTitle,
          body: _copy.passwordReviewBody,
          scheduledDate: _asDeviceInstant(scheduled),
          useExactAlarm: useExactAlarm,
        );
      },
    );
  }

  bool _isManagedPendingReminder(PendingReminderNotification request) =>
      _isManagedBusinessReminder(request) ||
      (request.id == _scheduledTestNotificationId &&
          CardockLanguage.values
              .map(reminderNotificationCopyFor)
              .any(
                (copy) =>
                    request.title == copy.testTitle &&
                    request.body == copy.scheduledTestBody,
              ));

  Future<void> _enqueuePendingMutation(Future<void> Function() operation) {
    final completer = Completer<void>();
    _pendingMutationTail = _pendingMutationTail.then((_) async {
      try {
        await operation();
        completer.complete();
      } on Object catch (error, stackTrace) {
        // 调用方仍会收到本次失败，但队列尾本身保持成功，后续操作可继续。
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _ensureInitializedForOperation() => _runOperation(
    stage: ReminderFailureStage.initialize,
    operation: _ensureInitialized,
  );

  Future<void> _runOperation({
    required ReminderFailureStage stage,
    required Future<void> Function() operation,
    String? subscriptionId,
  }) async {
    try {
      await operation();
    } on ReminderSchedulingException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw ReminderSchedulingException(<ReminderOperationFailure>[
        ReminderOperationFailure(
          stage: stage,
          subscriptionId: subscriptionId,
          cause: error,
          stackTrace: stackTrace,
        ),
      ]);
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    final pending = _initializing;
    if (pending != null) {
      return pending;
    }

    final initialization = _initialize();
    _initializing = initialization;
    try {
      await initialization;
      _initialized = true;
    } finally {
      if (identical(_initializing, initialization)) {
        // 成功由 _initialized 记忆；失败不缓存，下一次操作可以重新初始化。
        _initializing = null;
      }
    }
  }

  Future<void> _initialize() async {
    try {
      tz_data.initializeTimeZones();
    } on Object {
      _deviceLocation = null;
    }
    await _refreshDeviceLocation();

    await _gateway.initialize();
  }

  Future<void> _refreshDeviceLocation() async {
    try {
      final identifier = await _timeZoneIdentifier();
      _deviceLocation = _knownLocation(identifier);
    } on Object {
      // 某些厂商会返回非 IANA 标识，甚至让时区插件暂时失败。调度时使用
      // 目标日期的本机 UTC 偏移构造固定时区，仍保持单次提醒的本机墙上时间。
      _deviceLocation = null;
    }
  }

  tz.Location? _knownLocation(String identifier) {
    final normalized = switch (identifier.trim()) {
      'Asia/Beijing' || 'PRC' => 'Asia/Shanghai',
      final value => value,
    };
    try {
      return tz.getLocation(normalized);
    } on tz.LocationNotFoundException {
      return null;
    }
  }

  tz.TZDateTime _asDeviceWallClock(DateTime scheduled) {
    final location =
        _deviceLocation ?? _fixedOffsetLocation(_timeZoneOffsetAt(scheduled));
    return tz.TZDateTime(
      location,
      scheduled.year,
      scheduled.month,
      scheduled.day,
      scheduled.hour,
      scheduled.minute,
      scheduled.second,
      scheduled.millisecond,
      scheduled.microsecond,
    );
  }

  tz.TZDateTime _asDeviceInstant(DateTime scheduled) {
    final instant = scheduled.toUtc();
    final location =
        _deviceLocation ??
        _fixedOffsetLocation(_timeZoneOffsetAt(instant.toLocal()));
    return tz.TZDateTime.from(instant, location);
  }

  tz.Location _fixedOffsetLocation(Duration offset) {
    final normalizedOffset = Duration(seconds: offset.inSeconds);
    final identifier = javaZoneOffsetIdentifier(normalizedOffset);
    return tz.Location(identifier, <int>[tz.minTime], <int>[0], <tz.TimeZone>[
      tz.TimeZone(normalizedOffset, isDst: false, abbreviation: identifier),
    ]);
  }

  static Future<String> _systemTimeZoneIdentifier() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;

  static Duration _systemTimeZoneOffsetAt(DateTime dateTime) =>
      dateTime.timeZoneOffset;
}

/// 将固定偏移格式化为 Android `ZoneId.of` 可识别的名称。
@visibleForTesting
String javaZoneOffsetIdentifier(Duration offset) {
  final totalSeconds = offset.inSeconds;
  const maximumOffsetSeconds = 18 * Duration.secondsPerHour;
  if (totalSeconds.abs() > maximumOffsetSeconds) {
    throw ArgumentError.value(offset, 'offset', 'UTC 偏移必须在正负18小时内');
  }
  if (totalSeconds == 0) {
    return 'UTC';
  }

  final absoluteSeconds = totalSeconds.abs();
  final hours = absoluteSeconds ~/ Duration.secondsPerHour;
  final minutes =
      (absoluteSeconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
  final seconds = absoluteSeconds % Duration.secondsPerMinute;
  String twoDigits(int value) => value.toString().padLeft(2, '0');

  final base =
      '${totalSeconds.isNegative ? '-' : '+'}'
      '${twoDigits(hours)}:${twoDigits(minutes)}';
  return seconds == 0 ? base : '$base:${twoDigits(seconds)}';
}

/// 计算提醒日期；延期日期优先于“续费日前N天”。
DateTime? subscriptionReminderOn(SubscriptionRecord subscription) {
  if (!subscription.reminderEnabled ||
      subscription.status != SubscriptionStatus.active) {
    return null;
  }
  final snoozed = subscription.snoozedUntil;
  if (snoozed != null) {
    return subscriptionDateOnly(snoozed);
  }
  final snoozedInstant = subscription.snoozedUntilUtc;
  if (snoozedInstant != null) {
    final local = snoozedInstant.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
  if (subscription.management != null) {
    final next = subscriptionReminderOccurrences(
      subscription,
      reminderTimeMinutes: 0,
      now: DateTime(1970),
    ).firstOrNull;
    return next == null ? null : subscriptionDateOnly(next.at);
  }
  final renewal = subscription.nextRenewalOn;
  return DateTime(
    renewal.year,
    renewal.month,
    renewal.day - subscription.reminderDaysBefore,
  );
}

/// 计算实际本机触发时刻。精确延后使用保存的 UTC 瞬时，其余日期使用全局时间。
@visibleForTesting
DateTime? subscriptionReminderAt(
  SubscriptionRecord subscription, {
  required int reminderTimeMinutes,
}) {
  if (reminderTimeMinutes < 0 || reminderTimeMinutes > 1439) {
    throw ArgumentError.value(reminderTimeMinutes, 'reminderTimeMinutes');
  }
  if (!subscription.reminderEnabled ||
      subscription.status != SubscriptionStatus.active) {
    return null;
  }
  final exact = subscription.snoozedUntilUtc;
  if (exact != null) {
    return exact;
  }
  final reminderOn = subscriptionReminderOn(subscription);
  if (reminderOn == null) return null;
  return DateTime(
    reminderOn.year,
    reminderOn.month,
    reminderOn.day,
    reminderTimeMinutes ~/ 60,
    reminderTimeMinutes % 60,
  );
}

/// 业务提醒使用的最大编号。更高编号专门留给隐私安全的运行时测试通知。
@visibleForTesting
const int maximumBusinessReminderNotificationId = 0x7ffffffb;

@visibleForTesting
const int passwordReviewReminderNotificationId = 0x7ffffffc;

/// 生成稳定的31位正整数通知编号，避免依赖运行时随机哈希盐。
@visibleForTesting
int reminderNotificationId(String subscriptionId) {
  var hash = 0x811c9dc5;
  for (final byte in subscriptionId.codeUnits) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  if (hash == 0) {
    return 1;
  }
  if (hash > maximumBusinessReminderNotificationId) {
    return hash - maximumBusinessReminderNotificationId;
  }
  return hash;
}

final class SubscriptionReminderOccurrence {
  const SubscriptionReminderOccurrence({
    required this.id,
    required this.subscriptionId,
    required this.at,
    required this.exactInstant,
    this.summary,
    this.count = 1,
  });
  final int id;
  final String subscriptionId;
  final DateTime at;
  final bool exactInstant;
  final SubscriptionPublicSummary? summary;
  final int count;
}

Set<int> subscriptionReminderIds(String id) => {
  reminderNotificationId(id),
  for (final event in SubscriptionReminderEvent.values)
    for (var day = 0; day <= 365; day++)
      reminderNotificationId('$id:${event.name}:$day'),
  reminderNotificationId('$id:snooze'),
  reminderNotificationId('$id:second'),
  for (final event in SubscriptionReminderEvent.values)
    for (var day = 0; day <= 365; day++)
      reminderNotificationId('$id:${event.name}:$day:second'),
};

List<SubscriptionReminderOccurrence> subscriptionReminderOccurrences(
  SubscriptionRecord subscription, {
  required int reminderTimeMinutes,
  int? secondReminderTimeMinutes,
  required DateTime now,
}) {
  if (reminderTimeMinutes < 0 || reminderTimeMinutes > 1439) {
    throw ArgumentError('提醒时间无效');
  }
  if (secondReminderTimeMinutes != null &&
      (secondReminderTimeMinutes < 0 || secondReminderTimeMinutes > 1439)) {
    throw ArgumentError('第二次提醒时间无效');
  }
  if (!subscription.reminderEnabled ||
      subscription.status != SubscriptionStatus.active) {
    return [];
  }
  final trial = subscription.management?.trial;
  final unresolved = subscription.isUnresolvedTrial;
  if (trial != null && !unresolved && trial.outcome != TrialOutcome.converted) {
    return [];
  }
  final result = <SubscriptionReminderOccurrence>[];
  void add(
    int id,
    DateTime at, {
    bool exact = false,
    SubscriptionReminderEvent? event,
  }) {
    if (at.isAfter(now)) {
      result.add(
        SubscriptionReminderOccurrence(
          id: id,
          subscriptionId: subscription.id,
          at: at,
          exactInstant: exact,
          summary: SubscriptionPublicSummary.fromSubscription(
            subscription,
            event ??
                (unresolved
                    ? SubscriptionReminderEvent.trialEnd
                    : SubscriptionReminderEvent.decision),
          ),
        ),
      );
    }
  }

  DateTime wall(DateTime date, int minutes) =>
      DateTime(date.year, date.month, date.day, minutes ~/ 60, minutes % 60);
  void addDay(
    String identity,
    DateTime day, {
    SubscriptionReminderEvent? event,
  }) {
    add(
      reminderNotificationId(identity),
      wall(day, reminderTimeMinutes),
      event: event,
    );
    final second = secondReminderTimeMinutes;
    if (second != null && second != reminderTimeMinutes) {
      add(
        reminderNotificationId('$identity:second'),
        wall(day, second),
        event: event,
      );
    }
  }

  if (subscription.snoozedUntilUtc != null ||
      subscription.snoozedUntil != null) {
    final exact = subscription.snoozedUntilUtc;
    if (exact != null) {
      add(reminderNotificationId(subscription.id), exact, exact: true);
    } else {
      addDay(subscription.id, subscription.snoozedUntil!);
    }
    result.sort((a, b) => a.at.compareTo(b.at));
    return result;
  }
  for (final rule in subscription.effectiveReminderRules) {
    if (unresolved != (rule.event == SubscriptionReminderEvent.trialEnd)) {
      continue;
    }
    final anchor = unresolved ? trial!.endsOn : subscription.nextRenewalOn;
    for (final day in rule.daysBefore) {
      // Preserve the historical single notification identity during migration.
      final legacy =
          subscription.effectiveReminderRules.length == 1 &&
          rule.event == SubscriptionReminderEvent.renewal &&
          rule.daysBefore.length == 1;
      addDay(
        legacy ? subscription.id : '${subscription.id}:${rule.event.name}:$day',
        DateTime(anchor.year, anchor.month, anchor.day - day),
        event: rule.event,
      );
    }
  }
  result.sort((a, b) => a.at.compareTo(b.at));
  return result;
}
