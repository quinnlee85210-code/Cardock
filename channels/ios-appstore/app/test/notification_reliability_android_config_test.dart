import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 可靠性通道只读取非敏感系统状态并提供回退入口', () {
    final source = File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('cardock/notification_reliability'));
    expect(source, contains('NotificationManagerCompat.from(this)'));
    final statusStart = source.indexOf(
      'private fun notificationReliabilityStatus()',
    );
    final statusEnd = source.indexOf(
      'private fun openApplicationNotificationSettings()',
      statusStart,
    );
    expect(statusStart, isNonNegative);
    expect(statusEnd, greaterThan(statusStart));
    final statusSource = source.substring(statusStart, statusEnd);
    expect(
      statusSource,
      contains('if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)'),
    );
    expect(
      statusSource,
      matches(
        RegExp(
          r'getNotificationChannel\(\s*'
          r'REMINDER_NOTIFICATION_CHANNEL_ID,?\s*\)',
        ),
      ),
    );
    expect(statusSource, contains('channelEnabled = true'));
    expect(source, contains('"reminderChannelImportance"'));
    expect(source, contains('"reminderChannelSoundEnabled"'));
    expect(source, contains('"reminderChannelVibrationEnabled"'));
    expect(source, contains('isIgnoringBatteryOptimizations(packageName)'));
    expect(source, contains('Settings.ACTION_APP_NOTIFICATION_SETTINGS'));
    expect(source, contains('Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS'));
    expect(
      source,
      contains('Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS'),
    );
    expect(source, contains('openApplicationDetailsSettings()'));
    expect(source, contains('com.huawei.systemmanager'));
    expect(source, isNot(contains('REQUEST_IGNORE_BATTERY_OPTIMIZATIONS')));
  });

  test('Android 开机和覆盖升级恢复由可审计接收器委托现有插件', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final receiver = File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/ReminderRecoveryReceiver.kt',
    ).readAsStringSync();

    expect(manifest, contains('android:name=".ReminderRecoveryReceiver"'));
    expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
    expect(manifest, contains('android.intent.action.MY_PACKAGE_REPLACED'));
    expect(manifest, contains('android.intent.action.TIMEZONE_CHANGED'));
    expect(manifest, contains('android.intent.action.TIME_SET'));
    expect(manifest, isNot(contains('android.intent.action.DATE_CHANGED')));
    expect(
      manifest,
      contains(
        'android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED',
      ),
    );
    expect(
      manifest,
      isNot(
        contains(
          'android:name="com.dexterous.flutterlocalnotifications.'
          'ScheduledNotificationBootReceiver"',
        ),
      ),
    );
    expect(receiver, contains('ScheduledNotificationBootReceiver().onReceive'));
    expect(receiver, contains('Intent.ACTION_TIMEZONE_CHANGED'));
    expect(receiver, contains('Intent.ACTION_TIME_CHANGED'));
    expect(receiver, contains('canScheduleExactAlarms()'));
    expect(receiver, contains('readPluginScheduleCache'));
    expect(receiver, contains('restorePluginScheduleCache'));
    expect(receiver, contains('last_recovery_at_epoch_millis'));
    expect(receiver, contains('last_recovery_trigger'));
    expect(receiver, contains('last_recovery_result'));
    expect(receiver, isNot(contains('subscriptionId')));
    expect(receiver, isNot(contains('password')));
    expect(receiver, isNot(contains('payload')));
  });

  test('精确闹钟权限失败时保全的缓存键与锁定插件版本一致', () {
    final receiver = File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/ReminderRecoveryReceiver.kt',
    ).readAsStringSync();
    final packageConfig = File('.dart_tool/package_config.json');
    final config =
        jsonDecode(packageConfig.readAsStringSync()) as Map<String, Object?>;
    final packages = config['packages']! as List<Object?>;
    final pluginPackage = packages.cast<Map<String, Object?>>().singleWhere(
      (package) => package['name'] == 'flutter_local_notifications',
    );
    final pluginRoot = Directory.fromUri(
      packageConfig.absolute.uri.resolve(pluginPackage['rootUri']! as String),
    ).uri;
    final plugin = File.fromUri(
      pluginRoot.resolve(
        'android/src/main/java/com/dexterous/flutterlocalnotifications/'
        'FlutterLocalNotificationsPlugin.java',
      ),
    ).readAsStringSync();

    expect(
      plugin,
      contains(
        'private static final String SCHEDULED_NOTIFICATIONS = '
        '"scheduled_notifications"',
      ),
    );
    expect(plugin, contains('removeNotificationFromCache(context'));
    expect(
      receiver,
      contains(
        'PLUGIN_SCHEDULED_NOTIFICATIONS_FILE = "scheduled_notifications"',
      ),
    );
    expect(
      receiver,
      contains(
        'PLUGIN_SCHEDULED_NOTIFICATIONS_KEY = "scheduled_notifications"',
      ),
    );
  });
}
