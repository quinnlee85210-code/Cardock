import 'dart:convert';
import 'dart:typed_data';

import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_service.dart';
import 'package:account_subscription_manager/core/entitlements/mock_store_gateway.dart';
import 'package:account_subscription_manager/core/entitlements/promo_activation_config.dart';
import 'package:account_subscription_manager/core/entitlements/promo_activation_codec.dart';
import 'package:account_subscription_manager/core/entitlements/promo_activation_service.dart';
import 'package:account_subscription_manager/core/entitlements/promo_activation_store.dart';
import 'package:account_subscription_manager/core/notifications/reminder_scheduler.dart';
import 'package:account_subscription_manager/core/platform/notification_reliability.dart';
import 'package:account_subscription_manager/core/platform/screen_protection.dart';
import 'package:account_subscription_manager/core/platform/sensitive_clipboard.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_recovery.dart';
import 'package:account_subscription_manager/core/storage/layered_vault_store.dart';
import 'package:account_subscription_manager/core/storage/portable_backup_service.dart';
import 'package:account_subscription_manager/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';
import 'support/recording_reminder_scheduler.dart';

const _testMasterPassword = 'TEST-ONLY-MASTER-1234';

void main() {
  testWidgets('诱饵完整会话设置不泄露角色且不能导出正式便携备份', (tester) async {
    final state = AppState(
      vaultStore: const _ScopedTestVaultStore(
        accessLevel: VaultAccessLevel.full,
        canManageSecurity: false,
      ),
    );
    addTearDown(state.dispose);
    await state.initialize();
    expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
    await tester.pumpWidget(_testApp(state));

    expect(
      find.byKey(const ValueKey<String>('vault-status-诱饵保险库')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('notification-reliability-entry')),
      findsNothing,
    );

    final biometric = _biometricSwitch();
    await tester.scrollUntilVisible(
      biometric,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('当前会话中不可修改；请先锁定后再进入安全设置'), findsOneWidget);

    final migration = find.byKey(
      const ValueKey<String>('data-migration-center-entry'),
    );
    await tester.scrollUntilVisible(
      migration,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('当前会话不能导入外部数据'), findsOneWidget);

    final entry = find.byKey(
      const ValueKey<String>('encrypted-backup-export-entry'),
    );
    await tester.scrollUntilVisible(
      entry,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final tile = tester.widget<ListTile>(
      find.descendant(of: entry, matching: find.byType(ListTile)),
    );
    expect(tile.enabled, isFalse);
    expect(tile.onTap, isNull);
    expect(find.text('当前会话不能导出 Cardock 加密备份'), findsOneWidget);
    expect(find.textContaining('诱饵保险库'), findsNothing);
    expect(find.textContaining('真实主密码'), findsNothing);
  });

  testWidgets('外部导入与 Cardock 加密备份入口名称清楚且导出恢复相邻', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final state = await _unlockedState(
      FakeVaultStore(configured: true, acceptedPassword: _testMasterPassword),
      RecordingReminderScheduler(),
    );
    addTearDown(state.dispose);

    await tester.pumpWidget(_testApp(state));
    final importEntry = find.byKey(
      const ValueKey<String>('data-migration-center-entry'),
    );
    final exportEntry = find.byKey(
      const ValueKey<String>('encrypted-backup-export-entry'),
    );
    final restoreEntry = find.byKey(
      const ValueKey<String>('encrypted-backup-restore-entry'),
    );
    await tester.scrollUntilVisible(
      restoreEntry,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('数据导入与备份'), findsOneWidget);
    expect(find.text('导入外部数据'), findsOneWidget);
    expect(find.text('XLSX/CSV 等外部文件；.asmbackup 请用“恢复”'), findsOneWidget);
    expect(find.text('导出 Cardock 加密备份'), findsOneWidget);
    expect(find.text('恢复 Cardock 加密备份'), findsOneWidget);
    expect(find.text('手动/自动备份 .asmbackup；先验证再恢复'), findsOneWidget);
    expect(
      tester.getTopLeft(importEntry).dy,
      lessThan(tester.getTopLeft(exportEntry).dy),
    );
    expect(
      tester.getTopLeft(exportEntry).dy,
      lessThan(tester.getTopLeft(restoreEntry).dy),
    );
  });

  testWidgets('产品信息在真实库、诱饵库和订阅只读视图均可见且不暴露库内容', (tester) async {
    for (final scenario in <({VaultAccessLevel level, bool canManage})>[
      (level: VaultAccessLevel.full, canManage: true),
      (level: VaultAccessLevel.full, canManage: false),
      (level: VaultAccessLevel.subscriptionsOnly, canManage: false),
    ]) {
      final state = AppState(
        vaultStore: _ScopedTestVaultStore(
          accessLevel: scenario.level,
          canManageSecurity: scenario.canManage,
        ),
      );
      addTearDown(state.dispose);
      await state.initialize();
      expect(
        await state.unlock(_testMasterPassword),
        VaultActionResult.success,
      );
      await tester.pumpWidget(_testApp(state));
      final unlockEntry = find.byKey(
        const ValueKey<String>('unlock-full-version-entry'),
      );
      await tester.scrollUntilVisible(
        unlockEntry,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(unlockEntry, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('about-cardock-entry')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('developer-note-entry')),
        findsOneWidget,
      );
      expect(find.text('产品账号'), findsNothing);
      expect(find.textContaining('TEST-ONLY-MASTER'), findsNothing);
    }
  });

  testWidgets('产品区按解锁、关于、开发者的话顺序提供正式用户信息', (tester) async {
    final scheduler = RecordingReminderScheduler();
    final state = await _unlockedState(
      FakeVaultStore(configured: true, acceptedPassword: _testMasterPassword),
      scheduler,
    );
    addTearDown(state.dispose);
    final entitlementController = ProductEntitlementController(
      gateway: MockStoreGateway(simulationEnabled: true),
    );
    addTearDown(entitlementController.dispose);
    await entitlementController.initialize();

    await tester.pumpWidget(
      _testApp(state, entitlementController: entitlementController),
    );
    final unlockEntry = find.byKey(
      const ValueKey<String>('unlock-full-version-entry'),
    );
    await tester.scrollUntilVisible(
      unlockEntry,
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('解锁完整版'), findsOneWidget);
    expect(find.text('免费版 5 订阅 / 15 账户 · 一次购买，永久解锁'), findsOneWidget);
    expect(find.text('关于Cardock'), findsOneWidget);
    expect(find.text('开发者的话'), findsOneWidget);
    expect(find.text('第一款作品 · 关于初心与维护'), findsOneWidget);
    final productEntries = <Finder>[
      find.byKey(const ValueKey<String>('unlock-full-version-entry')),
      find.byKey(const ValueKey<String>('about-cardock-entry')),
      find.byKey(const ValueKey<String>('developer-note-entry')),
    ];
    final verticalPositions = productEntries
        .map((finder) => tester.getTopLeft(finder).dy)
        .toList(growable: false);
    expect(
      verticalPositions,
      orderedEquals(<double>[...verticalPositions]..sort()),
    );
    expect(find.text('产品账号'), findsNothing);
    expect(find.textContaining('暂不开发'), findsNothing);
    expect(find.textContaining('模拟商店已完成'), findsNothing);
    expect(find.textContaining('正式 IAP 尚未接入'), findsNothing);

    await entitlementController.debugSetEntitlement(
      ProductEntitlement.purchased,
    );
    await tester.pumpAndSettle();
    expect(find.text('已解锁完整版 · 感谢支持'), findsOneWidget);
    await entitlementController.debugSetEntitlement(ProductEntitlement.free);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('about-cardock-entry')));
    await tester.pumpAndSettle();
    expect(find.text('关于Cardock'), findsOneWidget);
    expect(find.text('版本 1.0.3+87'), findsOneWidget);
    expect(find.textContaining('不会申请通讯录、位置、外部存储或媒体读取权限'), findsOneWidget);
    expect(find.textContaining('不会扫描设备上的其他文件'), findsOneWidget);
    expect(find.textContaining('INTERNET 权限仅用于'), findsOneWidget);
    expect(find.textContaining('不会连接公网、云端或中继'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('about-encryption-backup')),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('随机 256 位数据密钥'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('about-password-protection')),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('19 MiB 内存'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('about-encrypted-backup')),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('安装标识和推广激活码不进入备份'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('about-licenses')),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Simple Icons（CC0-1.0）'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('developer-note-entry')),
      findsNothing,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('developer-note-entry')),
    );
    await tester.pumpAndSettle();
    expect(find.text('开发者的话'), findsOneWidget);
    expect(find.text('谢谢你选择Cardock'), findsOneWidget);
    expect(find.textContaining('第一款正式 App'), findsWidgets);
    final contactSection = find.byKey(
      const ValueKey<String>('developer-note-contact'),
    );
    await tester.scrollUntilVisible(
      contactSection,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('联系与反馈'), findsOneWidget);
    expect(find.text('kawucardock'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('developer-note-copy-wechat')),
      findsOneWidget,
    );
    expect(find.textContaining('开发者不会通过微信向你索取这些信息'), findsOneWidget);
    expect(find.text('微信赞赏码'), findsNothing);
    expect(find.text('支付宝收款码'), findsNothing);
    expect(find.textContaining('¥6 / ¥18 / ¥66'), findsNothing);
    expect(find.text('登录账号'), findsNothing);
    expect(find.text('检查更新'), findsNothing);
  });

  testWidgets('生物识别启动失败时显示结构化且可理解的具体原因', (tester) async {
    final scheduler = RecordingReminderScheduler();
    final store =
        FakeVaultStore(configured: true, acceptedPassword: _testMasterPassword)
          ..quickUnlockEnableFailure = const QuickUnlockException(
            QuickUnlockFailureReason.keySetupFailed,
            platformCode: 'key_generation_failed',
          );
    final state = await _unlockedState(store, scheduler);
    addTearDown(state.dispose);

    await tester.pumpWidget(_testApp(state));
    await tester.tap(_biometricSwitch());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('biometric-full-vault')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我了解并继续'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _testMasterPassword);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(
      state.quickUnlockFailureReason,
      QuickUnlockFailureReason.keySetupFailed,
    );
    expect(find.text('本机安全密钥初始化失败，请先用手机锁屏密码解锁设备后重试。'), findsOneWidget);
    expect(find.text('启用失败，请检查主密码和系统生物识别。'), findsNothing);
  });

  testWidgets('开启通知权限被拒绝时不落盘', (tester) async {
    final scheduler = RecordingReminderScheduler()..permissionGranted = false;
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
    );
    final state = await _unlockedState(store, scheduler);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      _testApp(state, onNotificationsChanged: state.setNotificationsEnabled),
    );
    await _tapVisible(tester, _notificationSwitch());
    await tester.pumpAndSettle();

    expect(scheduler.requestPermissionCalls, 1);
    expect(state.preferences.notificationsEnabled, isFalse);
    expect(store.saveCalls, 0);
    expect(find.text('手机系统已关闭本应用的总通知权限，请先在系统设置中开启。'), findsOneWidget);
  });

  testWidgets('开启通知会申请权限并保存设置', (tester) async {
    final scheduler = RecordingReminderScheduler();
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
    );
    final state = await _unlockedState(store, scheduler);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      _testApp(state, onNotificationsChanged: state.setNotificationsEnabled),
    );
    await _tapVisible(tester, _notificationSwitch());
    await tester.pumpAndSettle();

    expect(scheduler.requestPermissionCalls, 1);
    expect(state.preferences.notificationsEnabled, isTrue);
    expect(store.snapshot.preferences.notificationsEnabled, isTrue);
    expect(store.saveCalls, 1);
    expect(find.text('本地续费提醒已开启。'), findsOneWidget);
  });

  testWidgets('通知设置说明反映用户选择的隐私级别', (tester) async {
    final scheduler = RecordingReminderScheduler();
    final state = await _unlockedState(
      FakeVaultStore(configured: true, acceptedPassword: _testMasterPassword),
      scheduler,
    );
    addTearDown(state.dispose);

    await tester.pumpWidget(_testApp(state));
    await tester.scrollUntilVisible(
      find.text('通知内容取决于你选择的隐私级别；应用内记录才是权威来源'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('通知内容取决于你选择的隐私级别；应用内记录才是权威来源'), findsOneWidget);
    expect(find.text('通知只显示通用隐私文案，应用内记录才是权威来源'), findsNothing);
  });

  testWidgets('取消恢复授权时输入控制器随对话框安全退出且不覆盖数据', (tester) async {
    const backupPassword = 'TEST-ONLY-BACKUP-1234';
    final scheduler = RecordingReminderScheduler();
    final state = await _unlockedState(
      FakeVaultStore(configured: true, acceptedPassword: _testMasterPassword),
      scheduler,
    );
    addTearDown(state.dispose);
    final backup = await tester.runAsync(
      () => state.exportEncryptedBackup(backupMasterPassword: backupPassword),
    );
    expect(backup, isNotNull);

    await tester.pumpWidget(
      _testApp(state, backupService: _FixedPortableBackupService(backup!)),
    );
    await _tapVisible(tester, find.text('恢复 Cardock 加密备份'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), backupPassword);
    await tester.tap(find.text('继续'));
    await tester.pump();
    for (var attempt = 0; attempt < 300; attempt += 1) {
      if (state.lastBackupVerifiedAtUtc != null || state.errorMessage != null) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(
      state.lastBackupVerifiedAtUtc,
      isNotNull,
      reason:
          'backup preview error=${state.errorMessage}, busy=${state.isBusy}',
    );
    expect(find.text('确认覆盖本机记录'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('restore-authorization-password')),
      _testMasterPassword,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('restore-authorization-phrase')),
      '恢复',
    );
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();

    expect(find.text('确认覆盖本机记录'), findsNothing);
    expect(state.hasRecoveryRollback, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('恢复入口选到 ICS 或外部表格时在询问密码前明确拒绝并清零字节', (tester) async {
    final cases = <({String name, String contents, String message})>[
      (
        name: 'Cardock-calendar.ics',
        contents: 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR',
        message: '这是日历 .ics 文件，不包含可恢复的 Cardock 保险库；请选择 .asmbackup。',
      ),
      (
        name: 'accounts.csv',
        contents: 'platform,login\nExample,user@example.invalid',
        message: '这是外部表格或文档；请使用“导入外部数据”。恢复入口只接受 .asmbackup。',
      ),
    ];

    for (final testCase in cases) {
      final state = await _unlockedState(
        FakeVaultStore(configured: true, acceptedPassword: _testMasterPassword),
        RecordingReminderScheduler(),
      );
      addTearDown(state.dispose);
      final backupService = _FixedPortableBackupService(
        Uint8List.fromList(utf8.encode(testCase.contents)),
        name: testCase.name,
      );

      await tester.pumpWidget(_testApp(state, backupService: backupService));
      await _tapVisible(tester, find.text('恢复 Cardock 加密备份'));
      await tester.pumpAndSettle();

      expect(find.text(testCase.message), findsOneWidget);
      expect(find.text('验证加密备份'), findsNothing);
      expect(state.lastBackupVerifiedAtUtc, isNull);
      expect(backupService.lastReturnedBytes, isNotNull);
      expect(
        backupService.lastReturnedBytes!.every((value) => value == 0),
        isTrue,
      );
    }
  });

  testWidgets('关闭通知不申请权限并保存设置', (tester) async {
    final scheduler = RecordingReminderScheduler();
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
      snapshot: VaultSnapshot.empty().copyWith(
        preferences: const VaultPreferences(notificationsEnabled: true),
      ),
    );
    final state = await _unlockedState(store, scheduler);
    scheduler.reset();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      _testApp(state, onNotificationsChanged: state.setNotificationsEnabled),
    );
    await _tapVisible(tester, _notificationSwitch());
    await tester.pumpAndSettle();

    expect(scheduler.requestPermissionCalls, 0);
    expect(state.preferences.notificationsEnabled, isFalse);
    expect(store.snapshot.preferences.notificationsEnabled, isFalse);
    expect(store.saveCalls, 1);
    expect(scheduler.cancelAllCalls, 1);
    expect(find.text('本地续费提醒已关闭。'), findsOneWidget);
  });

  testWidgets('应用总通知允许但提醒通道关闭时不保存开启设置', (tester) async {
    final scheduler = RecordingReminderScheduler()
      ..permissionStatus = ReminderPermissionStatus.reminderChannelDisabled;
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
    );
    final state = await _unlockedState(store, scheduler);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      _testApp(state, onNotificationsChanged: state.setNotificationsEnabled),
    );
    await _tapVisible(tester, _notificationSwitch());
    await tester.pumpAndSettle();

    expect(state.preferences.notificationsEnabled, isFalse);
    expect(store.saveCalls, 0);
    expect(
      find.text('本应用总通知权限已开启，但“本机订阅提醒”通知通道已关闭，请在系统通知设置中开启该类别。'),
      findsOneWidget,
    );
    expect(find.text('本地续费提醒已开启。'), findsNothing);
  });

  testWidgets('开启设置已保存但提醒重排失败时不显示开启成功', (tester) async {
    final scheduler = RecordingReminderScheduler();
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
    );
    final state = await _unlockedState(store, scheduler);
    scheduler.failOn = ReminderSchedulerOperation.rescheduleAll;
    addTearDown(state.dispose);

    await tester.pumpWidget(
      _testApp(state, onNotificationsChanged: state.setNotificationsEnabled),
    );
    await _tapVisible(tester, _notificationSwitch());
    await tester.pumpAndSettle();

    expect(state.preferences.notificationsEnabled, isTrue);
    expect(store.snapshot.preferences.notificationsEnabled, isTrue);
    expect(scheduler.rescheduleCalls, hasLength(1));
    expect(find.text('设置已保存为开启，但部分提醒重排失败；下次解锁会自动重试。'), findsOneWidget);
    expect(find.text('本地续费提醒已开启。'), findsNothing);
  });

  testWidgets('通知初始化失败与普通重排失败使用不同提示', (tester) async {
    final scheduler = RecordingReminderScheduler();
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
    );
    final state = await _unlockedState(store, scheduler);
    scheduler
      ..failOn = ReminderSchedulerOperation.rescheduleAll
      ..structuredFailure =
          ReminderSchedulingException(<ReminderOperationFailure>[
            ReminderOperationFailure(
              stage: ReminderFailureStage.initialize,
              cause: StateError('TEST-ONLY initialization failure'),
              stackTrace: StackTrace.empty,
            ),
          ]);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      _testApp(state, onNotificationsChanged: state.setNotificationsEnabled),
    );
    await _tapVisible(tester, _notificationSwitch());
    await tester.pumpAndSettle();

    expect(state.preferences.notificationsEnabled, isTrue);
    expect(find.text('设置已保存为开启，但系统通知初始化失败；请前往“通知可靠性”测试通知并重试。'), findsOneWidget);
    expect(find.text('本地续费提醒已开启。'), findsNothing);
  });

  testWidgets('通知测试从通知可靠性进入并保留即时与一分钟提醒', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final scheduler = RecordingReminderScheduler();
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
      snapshot: VaultSnapshot.empty().copyWith(
        preferences: const VaultPreferences(notificationsEnabled: true),
      ),
    );
    final state = await _unlockedState(store, scheduler);
    scheduler.reset();
    addTearDown(state.dispose);

    await tester.pumpWidget(_testApp(state));
    expect(
      find.byKey(const ValueKey('notification-runtime-test')),
      findsNothing,
    );
    final reliability = find.byKey(
      const ValueKey('notification-reliability-entry'),
    );
    await tester.ensureVisible(reliability);
    await tester.tap(reliability);
    await tester.pumpAndSettle();
    final immediate = find.byKey(const ValueKey('notification-immediate-test'));
    await tester.scrollUntilVisible(
      immediate,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(immediate);
    await tester.pumpAndSettle();
    expect(find.text('已发送即时测试通知。'), findsOneWidget);
    final scheduled = find.byKey(const ValueKey('notification-minute-test'));
    await tester.ensureVisible(scheduled);
    await tester.tap(scheduled);
    await tester.pumpAndSettle();
    expect(scheduler.requestPermissionCalls, 2);
    expect(scheduler.showTestNotificationCalls, 1);
    expect(scheduler.testReminderDelays, <Duration>[
      const Duration(minutes: 1),
    ]);
    expect(find.text('已安排约1分钟后的测试提醒。'), findsOneWidget);
  });

  testWidgets('关闭设置已保存但旧提醒清理失败时不显示关闭成功', (tester) async {
    final scheduler = RecordingReminderScheduler();
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
    );
    final state = await _unlockedState(store, scheduler);
    expect(
      await state.setNotificationsEnabled(true),
      NotificationSettingResult.enabled,
    );
    scheduler.reset();
    scheduler.failOn = ReminderSchedulerOperation.cancelAll;
    addTearDown(state.dispose);

    await tester.pumpWidget(
      _testApp(state, onNotificationsChanged: state.setNotificationsEnabled),
    );
    await _tapVisible(tester, _notificationSwitch());
    await tester.pumpAndSettle();

    expect(state.preferences.notificationsEnabled, isFalse);
    expect(store.snapshot.preferences.notificationsEnabled, isFalse);
    expect(scheduler.cancelAllCalls, 1);
    expect(find.text('设置已保存为关闭，但旧提醒清理失败；下次解锁会自动重试。'), findsOneWidget);
    expect(find.text('本地续费提醒已关闭。'), findsNothing);
  });

  testWidgets('系统通知可用但加密设置保存失败时不执行提醒重排', (tester) async {
    final scheduler = RecordingReminderScheduler();
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
    );
    final state = await _unlockedState(store, scheduler);
    store.failSaves = true;
    addTearDown(state.dispose);

    await tester.pumpWidget(
      _testApp(state, onNotificationsChanged: state.setNotificationsEnabled),
    );
    await _tapVisible(tester, _notificationSwitch());
    await tester.pumpAndSettle();

    expect(state.preferences.notificationsEnabled, isFalse);
    expect(store.snapshot.preferences.notificationsEnabled, isFalse);
    expect(scheduler.rescheduleCalls, isEmpty);
    expect(find.text('系统通知可用，但通知设置保存失败。'), findsOneWidget);
    expect(find.text('本地续费提醒已开启。'), findsNothing);
  });

  testWidgets('自定义提醒时间可保存并回显', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final scheduler = RecordingReminderScheduler();
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
    );
    final state = await _unlockedState(store, scheduler);
    addTearDown(state.dispose);

    await tester.pumpWidget(_testApp(state));
    expect(find.text('12:30'), findsOneWidget);

    final reminderTimeTile = find.text('第一次提醒发送时间');
    await tester.ensureVisible(reminderTimeTile);
    await tester.tap(reminderTimeTile);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final timeFields = find.byType(TextField);
    expect(timeFields, findsNWidgets(2));
    await tester.enterText(timeFields.at(0), '14');
    await tester.enterText(timeFields.at(1), '35');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(state.preferences.defaultReminderTimeMinutes, 14 * 60 + 35);
    expect(store.snapshot.preferences.defaultReminderTimeMinutes, 14 * 60 + 35);
    expect(find.text('14:35'), findsOneWidget);
    expect(find.text('提醒时间已更新，已安排的本地提醒会同步调整。'), findsOneWidget);
  });

  testWidgets('备份密码要求预先可见且离线生成后可复制并保留眼睛按钮', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final scheduler = RecordingReminderScheduler();
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
    );
    final clipboard = _RecordingSensitiveClipboard();
    final state = await _unlockedState(store, scheduler);
    addTearDown(state.dispose);

    await tester.pumpWidget(_testApp(state, sensitiveClipboard: clipboard));
    final exportTile = find.text('导出 Cardock 加密备份');
    await tester.scrollUntilVisible(
      exportTile,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(exportTile);
    await tester.pumpAndSettle();
    await tester.tap(exportTile);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('new-password-requirements')),
      findsOneWidget,
    );
    expect(find.textContaining('大写字母、小写字母、数字和符号'), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('generate-new-secret-offline')),
    );
    await tester.pump();
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('copy-new-secret-safely')),
    );
    await tester.pump();

    expect(clipboard.copyCalls, 1);
    expect(clipboard.lastLabel, '备份密码');
    expect(clipboard.lastClearAfter, const Duration(seconds: 60));
    expect(clipboard.lastText, isNotEmpty);
    expect(find.textContaining('60秒后尽力清除'), findsOneWidget);
  });

  testWidgets('加密备份导出成功后引导到只读检查而不是恢复', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final state = await _unlockedState(
      FakeVaultStore(configured: true, acceptedPassword: _testMasterPassword),
      RecordingReminderScheduler(),
    );
    addTearDown(state.dispose);
    final backupService = _FixedPortableBackupService(
      Uint8List(0),
      saveResult: true,
    );

    await tester.pumpWidget(_testApp(state, backupService: backupService));
    await _tapVisible(tester, find.text('导出 Cardock 加密备份'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('generate-new-secret-offline')),
    );
    await tester.pump();
    final confirm = find.widgetWithText(FilledButton, '确认');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pump();
    const successMessage =
        '加密备份已保存为 .asmbackup。请打开“自动备份与备份检查”→“检查 Cardock 加密备份（不恢复）”核对文件。';
    for (var attempt = 0; attempt < 600; attempt += 1) {
      if (find.text(successMessage).evaluate().isNotEmpty ||
          state.errorMessage != null) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    expect(
      backupService.saveCallCount,
      1,
      reason: state.errorMessage ?? '导出操作未在30秒内完成',
    );
    expect(find.text(successMessage), findsOneWidget);
    expect(find.textContaining('选择同一文件完成只读验证'), findsNothing);
  });

  testWidgets('诱饵密码在输入前说明6到32位且六位即可确认', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final state = await _unlockedState(
      FakeVaultStore(configured: true, acceptedPassword: _testMasterPassword),
      RecordingReminderScheduler(),
    );
    addTearDown(state.dispose);

    await tester.pumpWidget(_testApp(state));
    final decoyTile = find.byKey(const ValueKey<String>('decoy-vault-setting'));
    await tester.ensureVisible(decoyTile);
    await tester.tap(decoyTile);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _testMasterPassword);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(find.textContaining('6–32个字符'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generate-new-secret-offline')),
      findsNothing,
    );
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    for (final field in tester.widgetList<TextField>(fields)) {
      expect(field.maxLength, 32);
    }
    await tester.enterText(fields.at(0), '故事密码12');
    await tester.enterText(fields.at(1), '故事密码12');
    await tester.pump();
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '确认'),
    );
    expect(confirm.onPressed, isNotNull);
  });

  testWidgets('设置页可通过当前密码、强度提示和确认流程修改主密码', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
    );
    final state = await _unlockedState(store, RecordingReminderScheduler());
    addTearDown(state.dispose);

    await tester.pumpWidget(_testApp(state));
    final tile = find.byKey(const ValueKey<String>('change-master-password'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _testMasterPassword);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(find.textContaining('大写字母、小写字母、数字和符号'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Quartz-Cobalt-85!Harbor-Lane');
    await tester.enterText(fields.at(1), 'Quartz-Cobalt-85!Harbor-Lane');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();
    expect(find.text('确认修改主密码？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '确认修改'));
    await tester.pumpAndSettle();

    expect(find.textContaining('主密码已修改'), findsOneWidget);
    state.lock();
    expect(await state.unlock(_testMasterPassword), VaultActionResult.rejected);
    expect(
      await state.unlock('Quartz-Cobalt-85!Harbor-Lane'),
      VaultActionResult.success,
    );
  });

  testWidgets('已配置诱饵密码仍可点击并通过双授权修改', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
    );
    final state = await _unlockedState(store, RecordingReminderScheduler());
    addTearDown(state.dispose);
    expect(
      await state.createDecoyVault(
        currentMasterPassword: _testMasterPassword,
        decoyPassword: '故事1234',
      ),
      isTrue,
    );

    await tester.pumpWidget(_testApp(state));
    final tile = find.byKey(const ValueKey<String>('decoy-vault-setting'));
    await tester.ensureVisible(tile);
    expect(find.textContaining('点击修改；原诱饵内容会保留'), findsOneWidget);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _testMasterPassword);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '故事1234');
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '新故事789');
    await tester.enterText(fields.at(1), '新故事789');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();

    expect(find.textContaining('诱饵密码已修改'), findsOneWidget);
    expect(store.changeDecoyPasswordCalls, 1);
    expect(store.acceptedDecoyPassword, '新故事789');
  });

  testWidgets('双库恢复分别显示，诱饵设置默认避让并拒绝显式相同题组', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
    );
    final state = await _unlockedState(store, RecordingReminderScheduler());
    addTearDown(state.dispose);
    final primaryQuestions = vaultRecoveryQuestionCatalog
        .take(3)
        .map((question) => question.id)
        .toList(growable: false);
    final decoyQuestions = vaultRecoveryQuestionCatalog
        .skip(3)
        .take(3)
        .map((question) => question.id)
        .toList(growable: false);
    const primaryAnswers = <String>['杭州', '实验小学', '王老师'];
    const decoyAnswers = <String>['红色', '小狗', '图书馆'];
    const decoyPassword = 'DECOY-TEST-PASSWORD-5678';

    expect(
      await state.configurePasswordRecovery(
        currentMasterPassword: _testMasterPassword,
        questionIds: primaryQuestions,
        answers: primaryAnswers,
        entryMode: VaultRecoveryEntryMode.visible,
      ),
      isTrue,
    );
    expect(
      await state.createDecoyVault(
        currentMasterPassword: _testMasterPassword,
        decoyPassword: decoyPassword,
      ),
      isTrue,
      reason: '真实库已有恢复配置时仍应允许创建独立诱饵库',
    );

    await tester.pumpWidget(_testApp(state));
    final primaryTile = find.byKey(
      const ValueKey<String>('password-recovery-setting'),
    );
    final decoyTile = find.byKey(
      const ValueKey<String>('decoy-password-recovery-setting'),
    );
    await tester.scrollUntilVisible(
      primaryTile,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(primaryTile, findsOneWidget);
    expect(decoyTile, findsOneWidget);
    expect(find.text('真实保险库密码恢复'), findsOneWidget);
    expect(find.text('诱饵保险库密码恢复'), findsOneWidget);

    await tester.tap(decoyTile);
    await tester.pumpAndSettle();
    expect(find.text('验证真实保险库'), findsOneWidget);
    await tester.enterText(find.byType(TextField), _testMasterPassword);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('验证当前诱饵密码'), findsOneWidget);
    await tester.enterText(find.byType(TextField), decoyPassword);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('设置诱饵保险库密码恢复'), findsOneWidget);

    for (var index = 0; index < 3; index += 1) {
      final question = find.byKey(ValueKey<String>('recovery-question-$index'));
      expect(
        tester.state<FormFieldState<String>>(question).value,
        decoyQuestions[index],
        reason: '第二套恢复默认题组应避开已配置的真实库题组',
      );
      tester.widget<DropdownButtonFormField<String>>(question).onChanged!(
        primaryQuestions[index],
      );
      await tester.pump();
    }

    for (var index = 0; index < 3; index += 1) {
      await tester.enterText(
        find.byKey(ValueKey<String>('recovery-setup-answer-$index')),
        '相同题组答案$index',
      );
      await tester.enterText(
        find.byKey(ValueKey<String>('recovery-setup-confirm-$index')),
        '相同题组答案$index',
      );
    }
    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-recovery-setup')),
    );
    await tester.pumpAndSettle();

    expect(find.text('两套保险库不能使用完全相同的三道密保问题；请至少更换一道。'), findsOneWidget);
    expect(state.decoyRecoveryConfigured, isFalse);
    expect(
      await state.configurePasswordRecovery(
        currentMasterPassword: _testMasterPassword,
        currentDecoyPassword: decoyPassword,
        questionIds: decoyQuestions,
        answers: decoyAnswers,
        entryMode: VaultRecoveryEntryMode.logoFiveTap,
        scope: VaultRecoveryScope.decoy,
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(state.primaryRecoveryConfigured, isTrue);
    expect(state.decoyRecoveryConfigured, isTrue);
  });

  testWidgets('防截屏默认开启且关闭前要求明确确认', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final service = MemoryScreenProtectionService();
    final state = await _unlockedState(
      FakeVaultStore(configured: true, acceptedPassword: _testMasterPassword),
      RecordingReminderScheduler(),
      screenProtectionService: service,
    );
    addTearDown(state.dispose);

    await tester.pumpWidget(_testApp(state));
    final screenProtection = find.byKey(
      const ValueKey<String>('screen-protection-switch'),
    );
    await tester.ensureVisible(screenProtection);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(screenProtection).value, isTrue);

    await tester.tap(screenProtection);
    await tester.pumpAndSettle();
    expect(find.text('关闭防截屏保护？'), findsOneWidget);
    expect(service.writeCalls, 0);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(state.screenProtectionEnabled, isTrue);
    expect(service.writeCalls, 0);

    await tester.tap(screenProtection);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '关闭保护'));
    await tester.pumpAndSettle();
    expect(state.screenProtectionEnabled, isFalse);
    expect(service.enabled, isFalse);
    expect(service.writeCalls, 1);
    expect(find.text('防截屏保护已关闭。'), findsOneWidget);
  });

  testWidgets('设置页可进入通知可靠性诊断页', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final state = await _unlockedState(
      FakeVaultStore(configured: true, acceptedPassword: _testMasterPassword),
      RecordingReminderScheduler(),
      notificationReliabilityService: MemoryNotificationReliabilityService(),
    );
    addTearDown(state.dispose);

    await tester.pumpWidget(_testApp(state));
    final entry = find.byKey(
      const ValueKey<String>('notification-reliability-entry'),
    );
    await tester.scrollUntilVisible(
      entry,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '通知可靠性'), findsOneWidget);
    expect(find.text('本机状态检查'), findsOneWidget);
  });
}

Future<AppState> _unlockedState(
  FakeVaultStore store,
  RecordingReminderScheduler scheduler, {
  NotificationReliabilityService? notificationReliabilityService,
  ScreenProtectionService? screenProtectionService,
}) async {
  final state = AppState(
    vaultStore: store,
    reminderScheduler: scheduler,
    notificationReliabilityService: notificationReliabilityService,
    screenProtectionService: screenProtectionService,
  );
  await state.initialize();
  expect(await state.unlock(_testMasterPassword), VaultActionResult.success);
  return state;
}

Widget _testApp(
  AppState state, {
  Future<NotificationSettingResult> Function(bool enabled)?
  onNotificationsChanged,
  SensitiveClipboard sensitiveClipboard = const PlatformSensitiveClipboard(),
  ProductEntitlementController? entitlementController,
  PortableBackupService backupService = const FilePickerPortableBackupService(),
}) {
  final controller =
      entitlementController ??
      ProductEntitlementController(
        gateway: MockStoreGateway(simulationEnabled: true),
      );
  if (entitlementController == null) addTearDown(controller.dispose);
  final promoController = PromoActivationController(
    store: MemoryPromoActivationStore(),
    verifier: PromoActivationVerifier(
      publicKeyBytes: PromoActivationConfig.publicKeyBytes,
    ),
  );
  addTearDown(promoController.dispose);
  return PromoActivationScope(
    controller: promoController,
    child: ProductEntitlementScope(
      controller: controller,
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
        home: ListenableBuilder(
          listenable: state,
          builder: (context, child) => Scaffold(
            body: SettingsPage(
              appState: state,
              onLock: () {},
              sensitiveClipboard: sensitiveClipboard,
              backupService: backupService,
              onNotificationsChanged: onNotificationsChanged,
            ),
          ),
        ),
      ),
    ),
  );
}

final class _FixedPortableBackupService implements PortableBackupService {
  _FixedPortableBackupService(
    Uint8List bytes, {
    this.name = 'test.asmbackup',
    this.saveResult = false,
  }) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;
  final String name;
  final bool saveResult;
  Uint8List? lastReturnedBytes;
  int saveCallCount = 0;

  @override
  Future<PortableBackupSelection?> pickEncryptedBackup({
    String? dialogTitle,
  }) async {
    final bytes = Uint8List.fromList(_bytes);
    lastReturnedBytes = bytes;
    return (name: name, bytes: bytes);
  }

  @override
  Future<bool> saveEncryptedBackup(
    Uint8List bytes, {
    String? dialogTitle,
  }) async {
    saveCallCount += 1;
    return saveResult;
  }
}

Finder _notificationSwitch() => find.widgetWithText(SwitchListTile, '本地续费提醒');

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find.byType(Scrollable).first,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

Finder _biometricSwitch() => find.widgetWithText(SwitchListTile, '指纹或人脸解锁');

final class _RecordingSensitiveClipboard implements SensitiveClipboard {
  int copyCalls = 0;
  String? lastText;
  String? lastLabel;
  Duration? lastClearAfter;

  @override
  Future<void> copySensitive({
    required String text,
    required String label,
    Duration clearAfter = const Duration(seconds: 60),
  }) async {
    copyCalls += 1;
    lastText = text;
    lastLabel = label;
    lastClearAfter = clearAfter;
  }
}

final class _ScopedTestVaultStore implements VaultStore {
  const _ScopedTestVaultStore({
    required this.accessLevel,
    required this.canManageSecurity,
  });

  final VaultAccessLevel accessLevel;
  final bool canManageSecurity;

  VaultOpenResult _result() => VaultOpenResult(
    session: _ScopedTestVaultSession(
      accessLevel: accessLevel,
      canManageSecurity: canManageSecurity,
    ),
    snapshot: VaultSnapshot.empty(),
  );

  @override
  Future<VaultOpenResult> create({required String masterPassword}) async =>
      throw const VaultAlreadyExistsException();

  @override
  Future<void> disableQuickUnlock() async {}

  @override
  Future<bool> exists() async => true;

  @override
  Future<bool> isQuickUnlockEnabled() async => false;

  @override
  Future<VaultSnapshot> readEncryptedBackup({
    required List<int> bytes,
    required String masterPassword,
  }) async => VaultSnapshot.empty();

  @override
  Future<VaultOpenResult> unlock({required String masterPassword}) async =>
      _result();

  @override
  Future<VaultOpenResult> unlockWithQuickUnlock() async => _result();
}

final class _ScopedTestVaultSession implements ScopedVaultSession {
  const _ScopedTestVaultSession({
    required this.accessLevel,
    required this.canManageSecurity,
  });

  @override
  final VaultAccessLevel accessLevel;

  @override
  final bool canManageSecurity;

  @override
  int get generation => 0;

  @override
  void close() {}

  @override
  Future<void> enableQuickUnlock() async {}

  @override
  Future<Uint8List> exportEncryptedBackup() async => Uint8List(0);

  @override
  Future<void> save(VaultSnapshot snapshot) async {}
}
