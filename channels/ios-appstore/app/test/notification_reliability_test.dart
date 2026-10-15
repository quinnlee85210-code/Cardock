import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/platform/notification_reliability.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/features/settings/presentation/notification_reliability_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';
import 'support/recording_reminder_scheduler.dart';

const _testPassword = 'TEST-ONLY-MASTER-1234';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'background recovery reports inexact fallback and system stop without business details',
    () async {
      const channel = MethodChannel(
        'cardock/notification_reliability/fallback-test',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => {
              'lastRecoveryAtEpochMillis': 1776092400000,
              'lastRecoveryTrigger': 'android.intent.action.BOOT_COMPLETED',
              'lastRecoveryResult': 'rescheduled_inexact',
              'lastSystemStopAtEpochMillis': 1776092300000,
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final status = await MethodChannelNotificationReliabilityService(
        channel: channel,
        isAndroid: () => true,
      ).inspect();
      expect(
        status.lastRecovery?.result,
        ReminderRecoveryResult.inexactFallback,
      );
      expect(status.lastSystemStopAtUtc?.millisecondsSinceEpoch, 1776092300000);
      expect(status.applicationNotificationsEnabled, isNull);
    },
  );

  test('MethodChannel 解码三态状态、厂商与恢复记录', () async {
    const channel = MethodChannel('cardock/notification_reliability/test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method ==
              MethodChannelNotificationReliabilityService.inspectMethod) {
            return <String, Object?>{
              'applicationNotificationsEnabled': true,
              'reminderChannelEnabled': false,
              'reminderChannelImportance': 2,
              'reminderChannelSoundEnabled': false,
              'reminderChannelVibrationEnabled': true,
              'batteryOptimizationExempt': true,
              'exactAlarmsAllowed': false,
              'manufacturer': 'HUAWEI',
              'model': 'CLS-AL00',
              'androidApiLevel': 31,
              'lastRecoveryAtEpochMillis': 1776092400000,
              'lastRecoveryTrigger':
                  'android.intent.action.MY_PACKAGE_REPLACED',
              'lastRecoveryResult': 'rescheduled',
            };
          }
          return true;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final service = MethodChannelNotificationReliabilityService(
      channel: channel,
      isAndroid: () => true,
    );

    final status = await service.inspect();
    expect(status.applicationNotificationsEnabled, isTrue);
    expect(status.reminderChannelEnabled, isFalse);
    expect(status.reminderChannelImportance, 2);
    expect(status.reminderChannelSoundEnabled, isFalse);
    expect(status.reminderChannelVibrationEnabled, isTrue);
    expect(status.batteryOptimizationExempt, isTrue);
    expect(status.exactAlarmsAllowed, isFalse);
    expect(status.manufacturer, 'HUAWEI');
    expect(status.model, 'CLS-AL00');
    expect(status.androidApiLevel, 31);
    expect(status.lastRecovery?.result, ReminderRecoveryResult.rescheduled);

    expect(
      await service.openSettings(NotificationSettingsTarget.reminderChannel),
      isTrue,
    );
    expect(calls, hasLength(2));
    expect(calls.last.arguments, <String, Object?>{
      'target': 'reminderChannel',
    });
  });

  test('厂商说明覆盖主流品牌、别名与通用回退', () {
    expect(notificationVendorGuidance('HUAWEI').vendorLabel, '华为');
    expect(
      notificationVendorGuidance('Xiaomi').instructions.join(),
      contains('自启动'),
    );
    expect(notificationVendorGuidance('POCO').vendorLabel, '小米 / Redmi / POCO');
    expect(notificationVendorGuidance('Google').vendorLabel, 'Google / Pixel');
    expect(
      notificationVendorGuidance('motorola').vendorLabel,
      'Motorola / Lenovo',
    );
    expect(notificationVendorGuidance('asus').vendorLabel, 'ASUS / ROG');
    expect(notificationVendorGuidance('ZTE').vendorLabel, '中兴 / nubia');
    expect(notificationVendorGuidance('Meizu').vendorLabel, '魅族');
    expect(notificationVendorGuidance('Nothing').vendorLabel, 'Nothing');
    expect(
      notificationVendorGuidance('Transsion').vendorLabel,
      'TECNO / Infinix / itel',
    );
    expect(notificationVendorGuidance('Sony').vendorLabel, 'Sony');
    expect(notificationVendorGuidance('HMD').vendorLabel, 'Nokia / HMD');
    expect(notificationVendorGuidance('unknown').vendorLabel, '通用 Android');
  });

  test('最近任务固定说明区分华为操作并保留系统边界', () {
    final huawei = recentTasksPinGuidance('HUAWEI');
    expect(huawei, contains('向下滑动任务卡'));
    expect(huawei, contains('点击锁形图标'));
    expect(huawei, contains('Android 不允许应用读取或代替用户设置此状态'));
    expect(huawei, contains('重新打开并解锁'));

    final generic = recentTasksPinGuidance('unknown');
    expect(generic, contains('如果系统提供锁定或固定功能'));
    expect(generic, isNot(contains('向下滑动任务卡')));
  });

  test('AppState 合并平台状态和待发数且系统跳转可注入', () async {
    final scheduler = RecordingReminderScheduler()..pendingCount = 4;
    final service = MemoryNotificationReliabilityService(
      status: const PlatformNotificationReliabilityStatus(
        applicationNotificationsEnabled: true,
        reminderChannelEnabled: true,
        reminderChannelImportance: 2,
        reminderChannelSoundEnabled: false,
        reminderChannelVibrationEnabled: false,
        batteryOptimizationExempt: false,
        exactAlarmsAllowed: false,
        manufacturer: 'HUAWEI',
        model: 'CLS-AL00',
        androidApiLevel: 31,
      ),
    );
    final state = AppState(
      vaultStore: FakeVaultStore(),
      reminderScheduler: scheduler,
      notificationReliabilityService: service,
    );
    addTearDown(state.dispose);
    await state.initialize();
    expect(await state.createVault(_testPassword), VaultActionResult.success);

    final report = await state.inspectNotificationReliability();
    expect(report.pendingReminderCount, 4);
    expect(report.platform.batteryOptimizationExempt, isFalse);
    expect(service.inspectCalls, 1);
    expect(
      await state.openNotificationReliabilitySettings(
        NotificationSettingsTarget.vendorBackground,
      ),
      isTrue,
    );
    expect(service.openedTargets, <NotificationSettingsTarget>[
      NotificationSettingsTarget.vendorBackground,
    ]);
  });

  testWidgets('诱饵会话不读取通知可靠性元数据且页面保持角色中性', (tester) async {
    final scheduler = RecordingReminderScheduler()..pendingCount = 7;
    final service = MemoryNotificationReliabilityService(
      status: const PlatformNotificationReliabilityStatus(
        applicationNotificationsEnabled: true,
        reminderChannelEnabled: true,
        batteryOptimizationExempt: true,
        exactAlarmsAllowed: true,
        manufacturer: 'TEST-ONLY',
        model: 'TEST-ONLY',
        androidApiLevel: 35,
      ),
    );
    final store = FakeVaultStore();
    final state = AppState(
      vaultStore: store,
      reminderScheduler: scheduler,
      notificationReliabilityService: service,
    );
    addTearDown(state.dispose);
    await state.initialize();
    expect(await state.createVault(_testPassword), VaultActionResult.success);
    expect(
      await state.createDecoyVault(
        currentMasterPassword: _testPassword,
        decoyPassword: 'TEST-ONLY-DECOY-1234',
      ),
      isTrue,
    );
    state.lock();
    expect(
      await state.unlock('TEST-ONLY-DECOY-1234'),
      VaultActionResult.success,
    );
    scheduler.reset();

    final report = await state.inspectNotificationReliability();
    expect(report.pendingReminderCount, isNull);
    expect(report.platform.androidApiLevel, isNull);
    expect(
      report.reconciliation.health,
      NotificationReconciliationHealth.unavailable,
    );
    expect(service.inspectCalls, 0);
    expect(scheduler.pendingReminderCountCalls, 0);
    expect(
      await state.openNotificationReliabilitySettings(
        NotificationSettingsTarget.vendorBackground,
      ),
      isFalse,
    );
    expect(service.openedTargets, isEmpty);

    await tester.pumpWidget(
      MaterialApp(home: NotificationReliabilityPage(appState: state)),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>('notification-reliability-unavailable'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('真实保险库'), findsNothing);
    expect(find.textContaining('诱饵库'), findsNothing);
  });

  test('系统时间恢复记录仅在成功全量重排后消费且失败可重试', () async {
    final scheduler = RecordingReminderScheduler();
    final service = MemoryNotificationReliabilityService(
      status: PlatformNotificationReliabilityStatus(
        applicationNotificationsEnabled: true,
        reminderChannelEnabled: true,
        batteryOptimizationExempt: true,
        exactAlarmsAllowed: true,
        manufacturer: 'Google',
        model: 'TEST-ONLY',
        androidApiLevel: 35,
        lastRecovery: ReminderRecoveryRecord(
          occurredAtUtc: DateTime.utc(2026, 8, 29, 12),
          trigger: 'android.intent.action.TIME_SET',
          result: ReminderRecoveryResult.rescheduled,
        ),
      ),
    );
    final state = AppState(
      vaultStore: FakeVaultStore(
        configured: true,
        acceptedPassword: _testPassword,
        snapshot: VaultSnapshot.empty().copyWith(
          preferences: const VaultPreferences(notificationsEnabled: true),
        ),
      ),
      reminderScheduler: scheduler,
      notificationReliabilityService: service,
    );
    addTearDown(state.dispose);
    await state.initialize();
    expect(await state.unlock(_testPassword), VaultActionResult.success);
    await _drainEventQueue();
    scheduler.reset();

    scheduler.failOn = ReminderSchedulerOperation.rescheduleAll;
    expect(await state.refreshReminderScheduleForSystemTimeRecovery(), isFalse);
    expect(scheduler.rescheduleCalls, hasLength(1));

    scheduler.reset();
    expect(await state.refreshReminderScheduleForSystemTimeRecovery(), isTrue);
    expect(scheduler.rescheduleCalls, hasLength(1));
    expect(await state.refreshReminderScheduleForSystemTimeRecovery(), isFalse);
    expect(scheduler.rescheduleCalls, hasLength(1));
  });

  testWidgets('应用前台恢复只为新的系统时区记录非阻塞重排一次', (tester) async {
    final scheduler = RecordingReminderScheduler();
    final service = MemoryNotificationReliabilityService(
      status: PlatformNotificationReliabilityStatus(
        applicationNotificationsEnabled: true,
        reminderChannelEnabled: true,
        batteryOptimizationExempt: true,
        exactAlarmsAllowed: true,
        manufacturer: 'Google',
        model: 'TEST-ONLY',
        androidApiLevel: 35,
        lastRecovery: ReminderRecoveryRecord(
          occurredAtUtc: DateTime.utc(2026, 8, 29, 13),
          trigger: 'android.intent.action.TIMEZONE_CHANGED',
          result: ReminderRecoveryResult.rescheduled,
        ),
      ),
    );
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testPassword,
      snapshot: VaultSnapshot.empty().copyWith(
        preferences: const VaultPreferences(
          autoLockSeconds: 300,
          notificationsEnabled: true,
        ),
      ),
    );

    await tester.pumpWidget(
      AccountSubscriptionApp(
        vaultStore: store,
        reminderScheduler: scheduler,
        notificationReliabilityService: service,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('unlock-master-password-field')),
      _testPassword,
    );
    await tester.tap(find.byKey(const ValueKey<String>('unlock-vault-button')));
    await tester.pumpAndSettle();
    scheduler.reset();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(scheduler.rescheduleCalls, hasLength(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(scheduler.rescheduleCalls, hasLength(1));

    service.status = PlatformNotificationReliabilityStatus(
      applicationNotificationsEnabled: true,
      reminderChannelEnabled: true,
      batteryOptimizationExempt: true,
      exactAlarmsAllowed: true,
      manufacturer: 'Google',
      model: 'TEST-ONLY',
      androidApiLevel: 35,
      lastRecovery: ReminderRecoveryRecord(
        occurredAtUtc: DateTime.utc(2026, 8, 29, 14),
        trigger: 'android.intent.action.TIMEZONE_CHANGED',
        result: ReminderRecoveryResult.rescheduled,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(scheduler.rescheduleCalls, hasLength(2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('可靠性页展示九项状态、防误划说明、人工重同步并分开两种测试', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final scheduler = RecordingReminderScheduler()..pendingCount = 3;
    final service = MemoryNotificationReliabilityService(
      status: PlatformNotificationReliabilityStatus(
        applicationNotificationsEnabled: true,
        reminderChannelEnabled: true,
        reminderChannelImportance: 2,
        reminderChannelSoundEnabled: false,
        reminderChannelVibrationEnabled: false,
        batteryOptimizationExempt: false,
        exactAlarmsAllowed: true,
        manufacturer: 'HUAWEI',
        model: 'CLS-AL00',
        androidApiLevel: 31,
        lastRecovery: ReminderRecoveryRecord(
          occurredAtUtc: DateTime.utc(2026, 8, 13, 7, 30),
          trigger: 'android.intent.action.MY_PACKAGE_REPLACED',
          result: ReminderRecoveryResult.rescheduled,
        ),
      ),
    );
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testPassword,
      snapshot: VaultSnapshot.empty().copyWith(
        preferences: const VaultPreferences(notificationsEnabled: true),
      ),
    );
    final state = AppState(
      vaultStore: store,
      reminderScheduler: scheduler,
      notificationReliabilityService: service,
    );
    addTearDown(state.dispose);
    await state.initialize();
    expect(await state.unlock(_testPassword), VaultActionResult.success);
    // Widget tests use a fake clock; pump it instead of awaiting Timer.run/
    // Future.delayed(Duration.zero), which cannot advance without a frame.
    await tester.pump();
    await tester.pump();
    await tester.pump();
    scheduler.reset();
    expect(await state.refreshReminderScheduleForReliability(), isTrue);
    expect(scheduler.rescheduleCalls, hasLength(1));
    scheduler.reset();

    await tester.pumpWidget(
      MaterialApp(home: NotificationReliabilityPage(appState: state)),
    );
    await tester.pumpAndSettle();

    expect(find.text('应用总通知权限'), findsOneWidget);
    expect(find.text('“本机订阅提醒”通道'), findsOneWidget);
    expect(find.textContaining('静默或最低优先级'), findsOneWidget);
    expect(find.text('电池优化'), findsOneWidget);
    expect(find.text('精确提醒权限'), findsOneWidget);
    expect(find.textContaining('HUAWEI CLS-AL00'), findsOneWidget);
    expect(find.text('固定在最近任务'), findsOneWidget);
    expect(find.text('建议操作'), findsOneWidget);
    expect(find.textContaining('向下滑动任务卡'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('notification-recents-pin-guidance')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('notification-reconciliation-status')),
      250,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('notification-reconciliation-status')),
      findsOneWidget,
    );
    expect(find.text('提醒协调状态'), findsOneWidget);
    expect(find.text('重新同步提醒'), findsOneWidget);
    expect(find.textContaining('3 条'), findsOneWidget);
    final recovery = find.byKey(
      const ValueKey<String>('notification-recovery-status'),
    );
    await tester.scrollUntilVisible(recovery, 250);
    await tester.pumpAndSettle();
    expect(recovery, findsOneWidget);
    expect(find.textContaining('应用覆盖升级'), findsOneWidget);

    final immediate = find.byKey(
      const ValueKey<String>('notification-immediate-test'),
    );
    await tester.ensureVisible(immediate);
    await tester.pumpAndSettle();
    await tester.tap(immediate);
    await tester.pumpAndSettle();
    expect(scheduler.showTestNotificationCalls, 1);
    expect(find.text('已发送即时测试通知。'), findsOneWidget);

    final scheduled = find.byKey(
      const ValueKey<String>('notification-minute-test'),
    );
    await tester.ensureVisible(scheduled);
    await tester.pumpAndSettle();
    await tester.tap(scheduled);
    await tester.pumpAndSettle();
    expect(scheduler.testReminderDelays, <Duration>[
      const Duration(minutes: 1),
    ]);
    expect(find.text('已安排约1分钟后的测试提醒。'), findsOneWidget);
  });
}

Future<void> _drainEventQueue() async {
  for (var index = 0; index < 3; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}
