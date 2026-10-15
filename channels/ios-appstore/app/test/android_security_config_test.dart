import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 主清单关闭备份且只声明业务所需最小权限', () async {
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();

    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
    expect(manifest, isNot(contains('USE_EXACT_ALARM')));
    expect(manifest, contains('android.permission.USE_BIOMETRIC'));
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    expect(manifest, contains('android.permission.FOREGROUND_SERVICE'));
    expect(
      manifest,
      contains('android.permission.FOREGROUND_SERVICE_DATA_SYNC'),
    );
    expect(manifest, contains('android.permission.WAKE_LOCK'));
    expect(manifest, isNot(contains('READ_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('WRITE_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
    expect(manifest, contains('ScheduledNotificationReceiver'));
  });

  test('Android 临时网页连接使用非导出 dataSync 前台服务且通知不含业务数据', () async {
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();
    final serviceBlock = RegExp(
      r'<service\s+[^>]*android:name="\.TemporaryWebForegroundService"'
      r'[^>]*/>',
    ).firstMatch(manifest)?.group(0);
    expect(serviceBlock, isNotNull);
    expect(serviceBlock, contains('android:exported="false"'));
    expect(serviceBlock, contains('android:foregroundServiceType="dataSync"'));

    final service = await File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/TemporaryWebForegroundService.kt',
    ).readAsString();
    expect(service, contains('FOREGROUND_SERVICE_TYPE_DATA_SYNC'));
    expect(service, contains('START_NOT_STICKY'));
    expect(service, contains('NotificationManager.IMPORTANCE_LOW'));
    expect(service, contains('NotificationCompat.VISIBILITY_PRIVATE'));
    expect(service, contains('stopForeground(STOP_FOREGROUND_REMOVE)'));
    expect(service, contains('PowerManager.PARTIAL_WAKE_LOCK'));
    expect(service, contains('WAKE_LOCK_TIMEOUT_MILLIS = 30 * 60 * 1000L'));
    expect(service, contains('lock.acquire(WAKE_LOCK_TIMEOUT_MILLIS)'));
    expect(service, contains('override fun onTaskRemoved'));
    expect(service, contains('WifiManager.WIFI_MODE_FULL_HIGH_PERF'));
    expect(service, contains('runtimeTimeoutHandler.postDelayed'));
    expect(service, contains('runtimeTimeoutHandler.removeCallbacks'));
    expect(
      '::releaseRuntimeLocks'.allMatches(service).length,
      greaterThanOrEqualTo(5),
    );
    expect(
      'completeRuntimeShutdown('.allMatches(service).length,
      greaterThanOrEqualTo(5),
    );
    expect(service, isNot(contains('SCREEN_BRIGHT_WAKE_LOCK')));
    expect(service, isNot(contains('FULL_WAKE_LOCK')));
    expect(service, isNot(contains('Log.')));

    final activity = await File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/MainActivity.kt',
    ).readAsString();
    expect(activity, contains('"cardock/temporary_web_runtime"'));
    expect(activity, contains('TemporaryWebForegroundService.start'));
    expect(activity, contains('TemporaryWebForegroundService.stop'));
  });

  test('Android 防截屏默认先于首帧开启并可由非敏感偏好切换', () async {
    final activity = await File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/MainActivity.kt',
    ).readAsString();

    expect(activity, contains('WindowManager.LayoutParams.FLAG_SECURE'));
    expect(activity, contains('window.addFlags'));
    expect(activity, contains('window.clearFlags'));
    expect(activity, contains('PREF_SECURE_WINDOW_ENABLED'));
    expect(activity, contains('.getBoolean(PREF_SECURE_WINDOW_ENABLED, true)'));
    expect(activity, contains('SCREEN_PROTECTION_CHANNEL'));
    final applyBeforeSuper = activity.indexOf(
      'applySecureWindowProtection(readSecureWindowPreference())',
    );
    final superOnCreate = activity.indexOf(
      'super.onCreate(savedInstanceState)',
    );
    expect(applyBeforeSuper, greaterThanOrEqualTo(0));
    expect(superOnCreate, greaterThan(applyBeforeSuper));
    expect(activity, contains('FlutterFragmentActivity'));
    expect(activity, contains('EXTRA_IS_SENSITIVE'));
    expect(activity, contains('clearPrimaryClip'));
  });

  test('Android 通知使用反糖化且主题兼容生物识别弹窗', () async {
    final gradle = await File('android/app/build.gradle.kts').readAsString();
    final styles = await File(
      'android/app/src/main/res/values/styles.xml',
    ).readAsString();

    expect(gradle, contains('isCoreLibraryDesugaringEnabled = true'));
    expect(gradle, contains('desugar_jdk_libs:2.1.4'));
    expect(styles, contains('Theme.AppCompat.DayNight.NoActionBar'));
  });

  test('Android 上架构建保留内置语言并固定平台安全分支', () async {
    final gradle = await File('android/app/build.gradle.kts').readAsString();
    final activity = await File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/MainActivity.kt',
    ).readAsString();
    final storageBridge = await File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/DocumentStorageBridge.kt',
    ).readAsString();
    final temporaryWebService = await File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/TemporaryWebForegroundService.kt',
    ).readAsString();

    expect(gradle, contains('enableSplit = false'));
    expect(
      activity,
      contains('if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)'),
    );
    expect(
      activity,
      contains('channelImportance = reminderChannel?.importance'),
    );
    expect(storageBridge, contains('persistablePermissionMode('));
    expect(storageBridge, contains('PersistablePermissionMode.READ_WRITE'));
    expect(
      storageBridge,
      isNot(contains('takePersistableUriPermission(uri, flags)')),
    );
    expect(temporaryWebService, contains('releaseRuntimeResources('));
    expect(
      temporaryWebService,
      contains('releaseWifi = ::releaseRuntimeWifiLock'),
    );
    expect(
      temporaryWebService,
      contains('releaseWake = ::releaseRuntimeWakeLock'),
    );
  });

  test('Android 云备份与设备迁移规则均排除应用数据', () async {
    final legacyRules = await File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsString();
    final currentRules = await File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsString();

    for (final domain in ['root', 'file', 'database', 'sharedpref']) {
      expect(legacyRules, contains('domain="$domain" path="."'));
      expect(currentRules, contains('domain="$domain" path="."'));
    }
    expect(currentRules, contains('<cloud-backup>'));
    expect(currentRules, contains('<device-transfer>'));
  });
}
