import 'dart:io';

import 'package:flutter/services.dart';

enum NotificationSettingsTarget {
  applicationNotifications,
  reminderChannel,
  batteryOptimization,
  exactAlarms,
  vendorBackground,
}

enum ReminderRecoveryResult { rescheduled, inexactFallback, failed, unknown }

final class ReminderRecoveryRecord {
  const ReminderRecoveryRecord({
    required this.occurredAtUtc,
    required this.trigger,
    required this.result,
  });

  final DateTime occurredAtUtc;
  final String trigger;
  final ReminderRecoveryResult result;
}

final class PlatformNotificationReliabilityStatus {
  const PlatformNotificationReliabilityStatus({
    required this.applicationNotificationsEnabled,
    required this.reminderChannelEnabled,
    required this.batteryOptimizationExempt,
    required this.exactAlarmsAllowed,
    required this.manufacturer,
    required this.model,
    required this.androidApiLevel,
    this.reminderChannelImportance,
    this.reminderChannelSoundEnabled,
    this.reminderChannelVibrationEnabled,
    this.lastRecovery,
    this.lastSystemStopAtUtc,
  });

  const PlatformNotificationReliabilityStatus.unavailable()
    : applicationNotificationsEnabled = null,
      reminderChannelEnabled = null,
      batteryOptimizationExempt = null,
      exactAlarmsAllowed = null,
      manufacturer = 'unknown',
      model = 'unknown',
      androidApiLevel = null,
      reminderChannelImportance = null,
      reminderChannelSoundEnabled = null,
      reminderChannelVibrationEnabled = null,
      lastRecovery = null,
      lastSystemStopAtUtc = null;

  final bool? applicationNotificationsEnabled;
  final bool? reminderChannelEnabled;
  final bool? batteryOptimizationExempt;
  final bool? exactAlarmsAllowed;
  final String manufacturer;
  final String model;
  final int? androidApiLevel;
  final int? reminderChannelImportance;
  final bool? reminderChannelSoundEnabled;
  final bool? reminderChannelVibrationEnabled;
  final ReminderRecoveryRecord? lastRecovery;
  final DateTime? lastSystemStopAtUtc;
}

final class NotificationReliabilityReport {
  const NotificationReliabilityReport({
    required this.platform,
    required this.pendingReminderCount,
    this.reconciliation = const NotificationReconciliationStatus.upToDate(),
  });

  final PlatformNotificationReliabilityStatus platform;
  final int? pendingReminderCount;
  final NotificationReconciliationStatus reconciliation;
}

enum NotificationReconciliationHealth { upToDate, pending, unavailable }

final class NotificationReconciliationStatus {
  const NotificationReconciliationStatus.upToDate()
    : health = NotificationReconciliationHealth.upToDate,
      attemptCount = 0,
      pendingSinceUtc = null,
      lastAttemptAtUtc = null;

  const NotificationReconciliationStatus.pending({
    required this.attemptCount,
    required this.pendingSinceUtc,
    this.lastAttemptAtUtc,
  }) : health = NotificationReconciliationHealth.pending;

  const NotificationReconciliationStatus.unavailable()
    : health = NotificationReconciliationHealth.unavailable,
      attemptCount = 0,
      pendingSinceUtc = null,
      lastAttemptAtUtc = null;

  final NotificationReconciliationHealth health;
  final int attemptCount;
  final DateTime? pendingSinceUtc;
  final DateTime? lastAttemptAtUtc;
}

abstract interface class NotificationReliabilityService {
  Future<PlatformNotificationReliabilityStatus> inspect();

  Future<bool> openSettings(NotificationSettingsTarget target);
}

final class MethodChannelNotificationReliabilityService
    implements NotificationReliabilityService {
  MethodChannelNotificationReliabilityService({
    MethodChannel? channel,
    bool Function()? isAndroid,
  }) : _channel = channel ?? const MethodChannel(channelName),
       _isAndroid = isAndroid ?? _platformIsAndroid;

  static const String channelName = 'cardock/notification_reliability';
  static const String inspectMethod = 'inspect';
  static const String openSettingsMethod = 'openSettings';

  final MethodChannel _channel;
  final bool Function() _isAndroid;

  static bool _platformIsAndroid() => Platform.isAndroid;

  @override
  Future<PlatformNotificationReliabilityStatus> inspect() async {
    if (!_isAndroid()) {
      return const PlatformNotificationReliabilityStatus.unavailable();
    }
    final value = await _channel.invokeMapMethod<String, Object?>(
      inspectMethod,
    );
    if (value == null) {
      throw const NotificationReliabilityProtocolException(
        'Android notification reliability channel returned no status.',
      );
    }
    return _decodeStatus(value);
  }

  @override
  Future<bool> openSettings(NotificationSettingsTarget target) async {
    if (!_isAndroid()) return false;
    return await _channel.invokeMethod<bool>(
          openSettingsMethod,
          <String, Object?>{'target': target.name},
        ) ??
        false;
  }

  PlatformNotificationReliabilityStatus _decodeStatus(
    Map<String, Object?> value,
  ) {
    final manufacturer = value['manufacturer'];
    final model = value['model'];
    final apiLevel = value['androidApiLevel'];
    final recoveryAt = value['lastRecoveryAtEpochMillis'];
    final recoveryTrigger = value['lastRecoveryTrigger'];
    final recoveryResult = value['lastRecoveryResult'];

    ReminderRecoveryRecord? lastRecovery;
    if (recoveryAt is int && recoveryAt > 0 && recoveryTrigger is String) {
      lastRecovery = ReminderRecoveryRecord(
        occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
          recoveryAt,
          isUtc: true,
        ),
        trigger: recoveryTrigger,
        result: switch (recoveryResult) {
          'rescheduled' => ReminderRecoveryResult.rescheduled,
          'rescheduled_inexact' => ReminderRecoveryResult.inexactFallback,
          'failed' => ReminderRecoveryResult.failed,
          _ => ReminderRecoveryResult.unknown,
        },
      );
    }

    return PlatformNotificationReliabilityStatus(
      applicationNotificationsEnabled: _nullableBool(
        value['applicationNotificationsEnabled'],
      ),
      reminderChannelEnabled: _nullableBool(value['reminderChannelEnabled']),
      reminderChannelImportance: value['reminderChannelImportance'] is int
          ? value['reminderChannelImportance']! as int
          : null,
      reminderChannelSoundEnabled: _nullableBool(
        value['reminderChannelSoundEnabled'],
      ),
      reminderChannelVibrationEnabled: _nullableBool(
        value['reminderChannelVibrationEnabled'],
      ),
      batteryOptimizationExempt: _nullableBool(
        value['batteryOptimizationExempt'],
      ),
      exactAlarmsAllowed: _nullableBool(value['exactAlarmsAllowed']),
      manufacturer: manufacturer is String && manufacturer.trim().isNotEmpty
          ? manufacturer.trim()
          : 'unknown',
      model: model is String && model.trim().isNotEmpty
          ? model.trim()
          : 'unknown',
      androidApiLevel: apiLevel is int ? apiLevel : null,
      lastRecovery: lastRecovery,
      lastSystemStopAtUtc:
          value['lastSystemStopAtEpochMillis'] is int &&
              (value['lastSystemStopAtEpochMillis']! as int) > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              value['lastSystemStopAtEpochMillis']! as int,
              isUtc: true,
            )
          : null,
    );
  }

  bool? _nullableBool(Object? value) => value is bool ? value : null;
}

final class MemoryNotificationReliabilityService
    implements NotificationReliabilityService {
  MemoryNotificationReliabilityService({
    this.status = const PlatformNotificationReliabilityStatus.unavailable(),
    this.openSettingsResult = true,
  });

  PlatformNotificationReliabilityStatus status;
  bool openSettingsResult;
  int inspectCalls = 0;
  final List<NotificationSettingsTarget> openedTargets =
      <NotificationSettingsTarget>[];

  @override
  Future<PlatformNotificationReliabilityStatus> inspect() async {
    inspectCalls += 1;
    return status;
  }

  @override
  Future<bool> openSettings(NotificationSettingsTarget target) async {
    openedTargets.add(target);
    return openSettingsResult;
  }
}

final class NotificationReliabilityProtocolException implements Exception {
  const NotificationReliabilityProtocolException(this.message);

  final String message;

  @override
  String toString() => 'NotificationReliabilityProtocolException: $message';
}
