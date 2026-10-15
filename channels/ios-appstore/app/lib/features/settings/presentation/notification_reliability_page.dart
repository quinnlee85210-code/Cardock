import 'package:flutter/foundation.dart';
import 'notification_privacy_card.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';

import '../../../app/app_state.dart';
import '../../../core/platform/notification_reliability.dart';
import '../../../core/theme/cardock_tokens.dart';

final class NotificationVendorGuidance {
  const NotificationVendorGuidance({
    required this.vendorLabel,
    required this.instructions,
  });

  final String vendorLabel;
  final List<String> instructions;
}

NotificationVendorGuidance _standardAndroidGuidance(String vendorLabel) =>
    NotificationVendorGuidance(
      vendorLabel: vendorLabel,
      instructions: const <String>[
        '在应用详情中允许通知和后台活动。',
        '在电池优化中将 Cardock 设为不受限制或允许后台运行。',
      ],
    );

NotificationVendorGuidance notificationVendorGuidance(String manufacturer) {
  final value = manufacturer.trim().toLowerCase();
  if (value.contains('huawei')) {
    return const NotificationVendorGuidance(
      vendorLabel: '华为',
      instructions: <String>[
        '设置 > 应用和服务 > 应用启动管理 > Cardock。',
        '关闭“自动管理”，再允许自启动、关联启动和后台活动。',
        '在电池设置中确认本应用未被高耗电优化限制。',
      ],
    );
  }
  if (value.contains('honor')) {
    return const NotificationVendorGuidance(
      vendorLabel: '荣耀',
      instructions: <String>[
        '设置 > 应用 > 应用启动管理 > Cardock。',
        '关闭自动管理，允许自启动、关联启动和后台运行。',
      ],
    );
  }
  if (value.contains('xiaomi') ||
      value.contains('redmi') ||
      value.contains('poco')) {
    return const NotificationVendorGuidance(
      vendorLabel: '小米 / Redmi / POCO',
      instructions: <String>[
        '设置 > 应用设置 > 应用管理 > Cardock > 自启动。',
        '电量和性能 > 应用智能省电，将本应用设为无限制。',
      ],
    );
  }
  if (value.contains('oppo') ||
      value.contains('oneplus') ||
      value.contains('realme')) {
    return const NotificationVendorGuidance(
      vendorLabel: 'OPPO / OnePlus / realme',
      instructions: <String>[
        '设置 > 应用 > 自启动，允许 Cardock 自启动。',
        '电池 > 应用耗电管理，允许后台活动。',
      ],
    );
  }
  if (value.contains('vivo') || value.contains('iqoo')) {
    return const NotificationVendorGuidance(
      vendorLabel: 'vivo / iQOO',
      instructions: <String>[
        '设置 > 应用与权限 > 权限管理 > 自启动，允许本应用。',
        '电池 > 后台耗电管理，允许后台高耗电。',
      ],
    );
  }
  if (value.contains('samsung')) {
    return const NotificationVendorGuidance(
      vendorLabel: '三星',
      instructions: <String>[
        '设置 > 电池和设备维护 > 电池 > 后台使用限制。',
        '确认本应用不在休眠或深度休眠列表，并加入“永不休眠的应用”（若系统提供）。',
      ],
    );
  }
  if (value.contains('google')) {
    return _standardAndroidGuidance('Google / Pixel');
  }
  if (value.contains('motorola') || value.contains('lenovo')) {
    return _standardAndroidGuidance('Motorola / Lenovo');
  }
  if (value.contains('asus')) {
    return _standardAndroidGuidance('ASUS / ROG');
  }
  if (value.contains('zte') || value.contains('nubia')) {
    return _standardAndroidGuidance('中兴 / nubia');
  }
  if (value.contains('meizu')) {
    return _standardAndroidGuidance('魅族');
  }
  if (value.contains('nothing')) {
    return _standardAndroidGuidance('Nothing');
  }
  if (value.contains('tecno') ||
      value.contains('infinix') ||
      value.contains('itel') ||
      value.contains('transsion')) {
    return _standardAndroidGuidance('TECNO / Infinix / itel');
  }
  if (value.contains('sony')) {
    return _standardAndroidGuidance('Sony');
  }
  if (value.contains('nokia') || value.contains('hmd')) {
    return _standardAndroidGuidance('Nokia / HMD');
  }
  return _standardAndroidGuidance('通用 Android');
}

String recentTasksPinGuidance(String manufacturer) {
  final value = manufacturer.trim().toLowerCase();
  final instruction = value.contains('huawei') || value.contains('honor')
      ? '打开最近任务，找到“Cardock”任务卡，将卡片设为锁定/固定（通常是向下滑动任务卡或点击锁形图标，以当前系统界面为准）。'
      : '打开最近任务，找到“Cardock”任务卡；如果系统提供锁定或固定功能，请为本应用启用。';
  return '$instruction\n'
      '固定只能减少误划和“一键清理”造成的退出；Android 不允许应用读取或代替用户设置此状态。若任务卡仍被划掉并导致系统停止，请重新打开并解锁，以恢复正式提醒。';
}

class NotificationReliabilityPage extends StatefulWidget {
  const NotificationReliabilityPage({required this.appState, super.key});

  final AppState appState;

  @override
  State<NotificationReliabilityPage> createState() =>
      _NotificationReliabilityPageState();
}

class _NotificationReliabilityPageState
    extends State<NotificationReliabilityPage>
    with WidgetsBindingObserver {
  NotificationReliabilityReport? _report;
  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;
  bool _loading = true;
  bool _working = false;
  bool _waitingForSettingsReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_waitingForSettingsReturn) {
      return;
    }
    _waitingForSettingsReturn = false;
    _refresh(rescheduleIfExact: true);
  }

  Future<void> _refresh({bool rescheduleIfExact = false}) async {
    if (mounted) setState(() => _loading = true);
    var report = await widget.appState.inspectNotificationReliability();
    if (rescheduleIfExact && report.platform.exactAlarmsAllowed == true) {
      await widget.appState.refreshReminderScheduleForReliability();
      report = await widget.appState.inspectNotificationReliability();
    }
    if (!mounted) return;
    setState(() {
      _report = report;
      _loading = false;
    });
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr(text))));
  }

  Future<void> _open(NotificationSettingsTarget target) async {
    final opened = await widget.appState.openNotificationReliabilitySettings(
      target,
    );
    if (opened) {
      _waitingForSettingsReturn = true;
    } else {
      _message(
        _isIOS
            ? '请打开 iPhone 设置 > 通知 > Cardock，开启允许通知，并检查声音、横幅和锁定屏幕。'
            : '系统设置入口不可用，请手动打开本应用详情。',
      );
    }
  }

  Future<void> _runTest({required bool scheduled}) async {
    if (_working) return;
    setState(() => _working = true);
    final result = scheduled
        ? await widget.appState.testOneMinuteReminder()
        : await widget.appState.testImmediateNotification();
    if (mounted) setState(() => _working = false);
    _message(_testMessage(result));
    if (scheduled && result == NotificationTestResult.scheduled) {
      await _refresh();
    }
  }

  Future<void> _runReconciliation() async {
    if (_working) return;
    setState(() => _working = true);
    final synchronized = await widget.appState
        .refreshReminderScheduleForReliability();
    if (mounted) setState(() => _working = false);
    _message(synchronized ? '系统提醒已完成同步。' : '系统提醒仍未完成同步，待协调状态已保留。');
    await _refresh();
  }

  String _testMessage(NotificationTestResult result) => switch (result) {
    NotificationTestResult.immediateSent => '已发送即时测试通知。',
    NotificationTestResult.scheduled => '已安排约1分钟后的测试提醒。',
    NotificationTestResult.notificationsDisabled => '请先开启“本地续费提醒”。',
    NotificationTestResult.applicationNotificationsDisabled =>
      '手机系统已关闭本应用的总通知权限。',
    NotificationTestResult.reminderChannelDisabled => '“本机订阅提醒”通知通道已关闭。',
    NotificationTestResult.permissionCheckFailed => '无法检查系统通知状态。',
    NotificationTestResult.initializationFailed => '系统通知初始化失败。',
    NotificationTestResult.immediateFailed => '即时测试通知发送失败。',
    NotificationTestResult.scheduleFailed => '1分钟测试提醒安排失败。',
    NotificationTestResult.rejected => '当前状态无法执行通知测试。',
    NotificationTestResult.immediateAndScheduled => '测试通知和定时提醒已安排。',
  };

  @override
  Widget build(BuildContext context) {
    if (!widget.appState.canManageSecurity) {
      return Scaffold(
        appBar: AppBar(title: const Text('通知可靠性')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.tr('当前会话不能查看通知可靠性'),
                key: const ValueKey<String>(
                  'notification-reliability-unavailable',
                ),
                translate: false,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }
    final palette = context.cardockTheme.palette;
    final report = _report;
    final platform = report?.platform;
    final guidance = notificationVendorGuidance(platform?.manufacturer ?? '');
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知可靠性'),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('notification-reliability-refresh'),
            onPressed: _loading ? null : _refresh,
            tooltip: context.tr('刷新状态'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            CardockLayout.screenHorizontal,
            CardockLayout.cardGap,
            CardockLayout.screenHorizontal,
            CardockLayout.moduleGapLarge,
          ),
          children: <Widget>[
            NotificationPrivacyCard(state: widget.appState),
            Container(
              padding: const EdgeInsets.all(CardockLayout.cardPaddingLarge),
              decoration: BoxDecoration(
                color: palette.surfaceAlt,
                borderRadius: BorderRadius.circular(CardockRadius.largeCard),
                border: Border.all(color: palette.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '本机状态检查',
                    style: TextStyle(
                      fontSize: CardockTypography.sectionTitle,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _isIOS
                        ? '只读取本应用的通知授权状态，不读取账号、密码、金额或具体订阅内容。'
                        : '只读取系统通知与电池状态，不读取账号、密码、金额或具体订阅内容。',
                  ),
                ],
              ),
            ),
            const SizedBox(height: CardockLayout.moduleGap),
            if (_loading && report == null)
              const Center(child: CircularProgressIndicator())
            else ...<Widget>[
              if (platform?.lastSystemStopAtUtc != null)
                _StatusCard(
                  key: const ValueKey<String>(
                    'notification-system-stop-status',
                  ),
                  icon: Icons.warning_amber_rounded,
                  title: '检测到系统停止记录',
                  state: _ReliabilityState.negative,
                  detail: context.tr(
                    '系统曾在 {time} 停止 Cardock，可能清除已安排的提醒。请允许自启动、关联启动和后台活动，并固定最近任务卡片。',
                    {
                      'time': platform!.lastSystemStopAtUtc!
                          .toLocal()
                          .toString()
                          .substring(0, 16),
                    },
                  ),
                  actionLabel: '打开厂商后台设置',
                  onAction: () =>
                      _open(NotificationSettingsTarget.vendorBackground),
                ),
              _StatusCard(
                key: const ValueKey<String>('notification-app-status'),
                icon: Icons.notifications_active_outlined,
                title: '应用总通知权限',
                state: _boolState(platform?.applicationNotificationsEnabled),
                detail: _boolText(
                  platform?.applicationNotificationsEnabled,
                  enabled: '系统允许本应用发送通知',
                  disabled: '系统已阻止本应用的所有通知',
                ),
                actionLabel: '打开通知设置',
                onAction: () =>
                    _open(NotificationSettingsTarget.applicationNotifications),
              ),
              if (!_isIOS) ...[
                _StatusCard(
                  key: const ValueKey<String>('notification-channel-status'),
                  icon: Icons.tune_outlined,
                  title: '“本机订阅提醒”通道',
                  state: _channelState(platform),
                  detail: _channelDetail(platform),
                  actionLabel: '打开通道设置',
                  onAction: () =>
                      _open(NotificationSettingsTarget.reminderChannel),
                ),
                _StatusCard(
                  key: const ValueKey<String>('notification-battery-status'),
                  icon: Icons.battery_saver_outlined,
                  title: '电池优化',
                  state: _boolState(platform?.batteryOptimizationExempt),
                  detail: _boolText(
                    platform?.batteryOptimizationExempt,
                    enabled: '本应用当前不受系统电池优化限制',
                    disabled: '系统电池优化可能延迟后台提醒',
                  ),
                  actionLabel: '打开电池优化',
                  onAction: () =>
                      _open(NotificationSettingsTarget.batteryOptimization),
                ),
                _StatusCard(
                  key: const ValueKey<String>(
                    'notification-exact-alarm-status',
                  ),
                  icon: Icons.alarm_on_outlined,
                  title: '精确提醒权限',
                  state: _boolState(platform?.exactAlarmsAllowed),
                  detail: _boolText(
                    platform?.exactAlarmsAllowed,
                    enabled: '已使用可在休眠状态准时触发的精确闹钟',
                    disabled: '未允许时会安全降级，但 Android 可能延迟约1小时或更久',
                  ),
                  actionLabel: '允许精确提醒',
                  onAction: () => _open(NotificationSettingsTarget.exactAlarms),
                ),
                _StatusCard(
                  key: const ValueKey<String>('notification-vendor-status'),
                  icon: Icons.phone_android_outlined,
                  title: '设备与厂商后台策略',
                  state: _ReliabilityState.information,
                  detail: _vendorDetail(platform, guidance),
                  actionLabel: '打开厂商后台设置',
                  onAction: () =>
                      _open(NotificationSettingsTarget.vendorBackground),
                ),
                _StatusCard(
                  key: const ValueKey<String>(
                    'notification-recents-pin-guidance',
                  ),
                  icon: Icons.push_pin_outlined,
                  title: '固定在最近任务',
                  state: _ReliabilityState.information,
                  stateLabel: '建议操作',
                  detail: context.tr(
                    recentTasksPinGuidance(platform?.manufacturer ?? ''),
                  ),
                ),
              ] else ...[
                const _StatusCard(
                  key: ValueKey<String>('notification-ios-delivery-guidance'),
                  icon: Icons.notifications_outlined,
                  title: 'iPhone 通知显示与声音',
                  state: _ReliabilityState.information,
                  detail: '请打开 iPhone 设置 > 通知 > Cardock，开启允许通知，并检查声音、横幅和锁定屏幕。',
                ),
                const _StatusCard(
                  key: ValueKey<String>('notification-ios-focus-guidance'),
                  icon: Icons.do_not_disturb_on_outlined,
                  title: '专注模式与通知摘要',
                  state: _ReliabilityState.information,
                  detail:
                      '设置 > 专注模式 > 当前使用的模式 > App，允许 Cardock 通知；设置 > 通知 > 定时推送摘要，避免将 Cardock 设为延后推送。Cardock 无法读取或更改这些开关。',
                ),
                const _StatusCard(
                  key: ValueKey<String>('notification-ios-battery-guidance'),
                  icon: Icons.battery_saver_outlined,
                  title: 'iPhone 电池与后台说明',
                  state: _ReliabilityState.information,
                  detail:
                      'iOS 没有 Android 的通知通道、电池优化豁免或精确闹钟授权入口。低电量模式可在设置 > 电池中查看（部分版本位于电源模式内）。本机定时通知由系统管理，无需让 Cardock 持续在后台运行；更改提醒后请打开并解锁 Cardock 以同步。',
                ),
              ],
              _StatusCard(
                key: const ValueKey<String>(
                  'notification-reconciliation-status',
                ),
                icon: Icons.sync_outlined,
                title: '提醒协调状态',
                state: switch (report?.reconciliation.health) {
                  NotificationReconciliationHealth.upToDate =>
                    _ReliabilityState.positive,
                  NotificationReconciliationHealth.pending =>
                    _ReliabilityState.negative,
                  _ => _ReliabilityState.unknown,
                },
                detail: _reconciliationDetail(report?.reconciliation),
                actionLabel: '重新同步提醒',
                onAction: _working ? null : _runReconciliation,
              ),
              _StatusCard(
                key: const ValueKey<String>('notification-pending-count'),
                icon: Icons.schedule_outlined,
                title: '当前待发定时提醒',
                state: report?.pendingReminderCount == null
                    ? _ReliabilityState.unknown
                    : _ReliabilityState.information,
                detail: report?.pendingReminderCount == null
                    ? '无法读取本应用待发队列'
                    : context.tr('{count} 条（只统计本应用管理的通用提醒）', <String, Object?>{
                        'count': report!.pendingReminderCount,
                      }),
              ),
              if (!_isIOS)
                _StatusCard(
                  key: const ValueKey<String>('notification-recovery-status'),
                  icon: Icons.restart_alt_outlined,
                  title: '最近开机 / 升级恢复',
                  state: switch (platform?.lastRecovery?.result) {
                    ReminderRecoveryResult.rescheduled =>
                      _ReliabilityState.positive,
                    ReminderRecoveryResult.inexactFallback =>
                      _ReliabilityState.unknown,
                    ReminderRecoveryResult.failed => _ReliabilityState.negative,
                    _ => _ReliabilityState.unknown,
                  },
                  detail: _recoveryText(platform?.lastRecovery),
                ),
              const SizedBox(height: CardockLayout.cardGap),
              FilledButton.icon(
                key: const ValueKey<String>('notification-immediate-test'),
                onPressed: _working ? null : () => _runTest(scheduled: false),
                icon: const Icon(Icons.notification_add_outlined),
                label: const Text('发送即时测试通知'),
              ),
              const SizedBox(height: CardockLayout.cardGap),
              OutlinedButton.icon(
                key: const ValueKey<String>('notification-minute-test'),
                onPressed: _working ? null : () => _runTest(scheduled: true),
                icon: const Icon(Icons.timer_outlined),
                label: const Text('安排约1分钟测试提醒'),
              ),
              const SizedBox(height: CardockLayout.moduleGap),
              Text(
                '说明：精确闹钟可改善锁屏与 Doze 下的及时性，但系统“强行停止”会使应用进入停止状态，并可能取消或暂停提醒；应用无法绕过，必须由用户重新打开并解锁。部分厂商的划卡或一键清理也可能触发等效限制。请同时允许自启动、关联启动和后台活动。恢复记录只表示恢复入口已运行并通过当前可见检查，不代表最终送达。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _ReliabilityState _boolState(bool? value) => switch (value) {
    true => _ReliabilityState.positive,
    false => _ReliabilityState.negative,
    null => _ReliabilityState.unknown,
  };

  _ReliabilityState _channelState(
    PlatformNotificationReliabilityStatus? platform,
  ) {
    final enabled = platform?.reminderChannelEnabled;
    if (enabled == null) return _ReliabilityState.unknown;
    if (!enabled) return _ReliabilityState.negative;
    final importance = platform?.reminderChannelImportance;
    if ((importance != null && importance < 3) ||
        (platform?.reminderChannelSoundEnabled == false &&
            platform?.reminderChannelVibrationEnabled == false)) {
      return _ReliabilityState.negative;
    }
    return _ReliabilityState.positive;
  }

  String _channelDetail(PlatformNotificationReliabilityStatus? platform) {
    final enabled = platform?.reminderChannelEnabled;
    if (enabled == null) return '通道尚未创建或系统无法读取';
    if (!enabled) return '通知通道已被关闭';
    final importance = platform?.reminderChannelImportance;
    if (importance != null && importance < 3) {
      return '通知通道已开启，但当前为静默或最低优先级；提醒可能没有声音或不显示在状态栏。';
    }
    if (platform?.reminderChannelSoundEnabled == false &&
        platform?.reminderChannelVibrationEnabled == false) {
      return '通知通道已开启，但声音和振动都已关闭。';
    }
    return '通知通道已开启';
  }

  String _reconciliationDetail(NotificationReconciliationStatus? status) {
    if (status == null ||
        status.health == NotificationReconciliationHealth.unavailable) {
      return '无法读取保险库内的提醒协调状态';
    }
    if (status.health == NotificationReconciliationHealth.upToDate) {
      return '系统提醒已与当前保险库数据同步';
    }
    if (status.attemptCount == 0) {
      return '业务数据已保存，系统提醒仍待同步；应用或设备重启后，真实保险库下次解锁时会自动重试。';
    }
    return context.tr(
      '已重试 {count} 次，系统提醒仍待同步；应用或设备重启后，真实保险库下次解锁时会继续重试。',
      <String, Object?>{'count': status.attemptCount},
    );
  }

  String _boolText(
    bool? value, {
    required String enabled,
    required String disabled,
  }) => switch (value) {
    true => enabled,
    false => disabled,
    null => disabled,
  };

  String _recoveryText(ReminderRecoveryRecord? record) {
    if (record == null) return '暂无开机或覆盖升级后的恢复记录';
    final local = record.occurredAtUtc.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final time =
        '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
    final trigger = switch (record.trigger) {
      'android.intent.action.BOOT_COMPLETED' => '设备开机',
      'android.intent.action.MY_PACKAGE_REPLACED' => '应用覆盖升级',
      'android.intent.action.TIMEZONE_CHANGED' => '系统时区变更',
      'android.intent.action.TIME_SET' => '系统时间变更',
      'android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED' =>
        '精确提醒权限已授予',
      _ => '系统恢复信号',
    };
    final result = switch (record.result) {
      ReminderRecoveryResult.rescheduled => '已重新提交调度',
      ReminderRecoveryResult.inexactFallback => '已恢复非精确提醒，系统可能延迟',
      ReminderRecoveryResult.failed => '重新提交失败',
      ReminderRecoveryResult.unknown => '结果未知',
    };
    return context.tr('{time} · {trigger} · {result}', <String, Object?>{
      'time': time,
      'trigger': context.tr(trigger),
      'result': context.tr(result),
    });
  }

  String _vendorDetail(
    PlatformNotificationReliabilityStatus? platform,
    NotificationVendorGuidance guidance,
  ) {
    final identity =
        '${platform?.manufacturer ?? 'unknown'} ${platform?.model ?? ''} · '
        'Android API ${platform?.androidApiLevel?.toString() ?? context.tr('未知')}';
    final instructions = <String>[
      ...guidance.instructions,
      '系统版本和地区会改变菜单名称；若专用入口打不开，请在应用详情中逐项检查通知、电池和后台权限。',
    ].map(context.tr).join('\n');
    return '$identity\n${context.tr('{vendor}: {instructions}', <String, Object?>{'vendor': context.tr(guidance.vendorLabel), 'instructions': instructions})}';
  }
}

enum _ReliabilityState { positive, negative, information, unknown }

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.state,
    required this.detail,
    this.actionLabel,
    this.onAction,
    this.stateLabel,
    super.key,
  });

  final IconData icon;
  final String title;
  final _ReliabilityState state;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? stateLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final color = switch (state) {
      _ReliabilityState.positive => palette.statusNormal,
      _ReliabilityState.negative => palette.statusDanger,
      _ReliabilityState.information => palette.statusInformation,
      _ReliabilityState.unknown => palette.statusCancelled,
    };
    final label =
        stateLabel ??
        switch (state) {
          _ReliabilityState.positive => '正常',
          _ReliabilityState.negative => '需处理',
          _ReliabilityState.information => '信息',
          _ReliabilityState.unknown => '未知',
        };
    return Padding(
      padding: const EdgeInsets.only(bottom: CardockLayout.cardGap),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CardockRadius.card),
          side: BorderSide(color: palette.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(CardockLayout.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.tr(title),
                      translate: false,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(CardockRadius.pill),
                    ),
                    child: Text(
                      context.tr(label),
                      translate: false,
                      style: TextStyle(
                        color: color,
                        fontSize: CardockTypography.caption,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(context.tr(detail), translate: false),
              if (actionLabel != null && onAction != null) ...<Widget>[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onAction,
                  child: Text(context.tr(actionLabel!), translate: false),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
