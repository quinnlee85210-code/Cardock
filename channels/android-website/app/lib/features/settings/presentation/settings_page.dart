import '../../../app/navigation/vault_navigation.dart';
import '../../product/presentation/website_authorization_dialog.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';

import '../../../app/app_state.dart';
import '../../../core/app_metadata.dart';
import '../../../core/entitlements/entitlement_guard.dart';
import '../../../core/entitlements/entitlement_model.dart';
import '../../../core/entitlements/entitlement_service.dart';
import '../../../core/entitlements/distribution_channel.dart';
import '../../../core/platform/sensitive_clipboard.dart';
import '../../../core/preferences/appearance_preferences.dart';
import '../../../core/preferences/language_preferences.dart';
import '../../../core/preferences/record_display_mode.dart';
import '../../../core/security/offline_password_advisor.dart';
import '../../../core/security/vault_recovery.dart';
import '../../../core/storage/data_transfer_file_classifier.dart';
import '../../../core/storage/layered_vault_store.dart';
import '../../../core/storage/portable_backup_service.dart';
import '../../../core/temporary_web/temporary_web_controller.dart';
import '../../../core/temporary_web/temporary_web_models.dart';
import '../../../core/theme/cardock_tokens.dart';
import '../../../core/theme/custom_theme.dart';
import '../../subscriptions/domain/subscription_list_preset.dart';
import '../../subscriptions/domain/subscription_record.dart';
import '../../about/presentation/about_cardock_page.dart';
import '../../about/presentation/developer_note_page.dart';
import '../../data_import/presentation/data_import_ui_controller.dart';
import '../../data_import/presentation/app_data_import_ui_controller.dart';
import '../../data_import/presentation/data_migration_center_hub_page.dart';
import '../../data_import/presentation/pending_subscription_drafts_page.dart';
import '../../product/presentation/full_version_page.dart';
import '../../product/presentation/full_version_upsell_sheet.dart';
import '../../product/presentation/purchase_credential_page.dart';
import '../../../shared/widgets/cardock_ui.dart';
import '../../../shared/widgets/cardock_brand_symbol.dart';
import 'custom_theme_editor_page.dart';
import 'notification_reliability_page.dart';
import 'temporary_web_session_page.dart';
import 'vault_health_page.dart';
import 'trash_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.appState,
    required this.onLock,
    this.temporaryWebController,
    this.dataImportControllerFactory,
    this.backupService = const FilePickerPortableBackupService(),
    this.sensitiveClipboard = const PlatformSensitiveClipboard(),
    this.onNotificationsChanged,
    this.healthOpenSignal = 0,
    super.key,
  });

  final AppState appState;
  final int healthOpenSignal;
  final VoidCallback onLock;
  final TemporaryWebSessionController? temporaryWebController;
  final DataImportUiControllerFactory? dataImportControllerFactory;
  final PortableBackupService backupService;
  final SensitiveClipboard sensitiveClipboard;
  final Future<NotificationSettingResult> Function(bool enabled)?
  onNotificationsChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    VaultNavigationScope.maybeOf(context)?.handlers.addAll({
      'appearance': (_) =>
          _openAppearanceSettings(CardockAppearanceScope.of(context)),
      'fullVersion': (_) =>
          _openFullVersion(ProductEntitlementScope.of(context)),
      'purchaseCredential': (_) =>
          _openPurchaseCredential(ProductEntitlementScope.of(context)),
      'about': (_) => _openAboutCardock(),
      'developer': (_) => _openDeveloperNote(),
      'notificationReliability': (_) {
        _openNotificationReliability();
      },
      'temporaryWeb': (_) {
        _openTemporaryWebSession();
      },
      'dataMigration': (_) {
        _openDataMigrationCenter();
      },
      'pendingDrafts': (_) {
        _openPendingSubscriptionDrafts();
      },
      'vaultHealth': (_) {
        _openVaultHealth();
      },
      'trash': (_) {
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            settings: const VaultPageLocation('trash'),
            builder: (_) => TrashPage(appState: widget.appState),
          ),
        );
      },
    });
  }

  bool get _offlineWebsite =>
      const String.fromEnvironment('CARDOCK_DISTRIBUTION') == 'website' ||
      ProductEntitlementScope.maybeOf(context)?.distributionChannel ==
          CardockDistributionChannel.website;
  bool _working = false;
  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.healthOpenSignal != oldWidget.healthOpenSignal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.appState.isUnlocked &&
            widget.appState.canManageSecurity) {
          _openVaultHealth();
        }
      });
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr(text))));
  }

  Future<void> _toggleBiometric(bool enabled) async {
    if (_working) return;
    if (!enabled) {
      final confirmed = await _confirm(
        title: '关闭生物识别解锁？',
        message: '关闭后仍可继续使用主密码，不会删除加密库。',
        confirmLabel: '关闭',
      );
      if (!confirmed) return;
      setState(() => _working = true);
      final ok = await widget.appState.disableQuickUnlock();
      if (mounted) setState(() => _working = false);
      _message(ok ? '已关闭生物识别快速解锁。' : '关闭失败，请重试。');
      return;
    }

    final scope = await _chooseBiometricScope();
    if (scope == null) return;
    await _enableBiometric(scope);
  }

  Future<void> _toggleScreenProtection(bool enabled) async {
    if (_working) return;
    if (!enabled) {
      final confirmed = await _confirm(
        title: '关闭防截屏保护？',
        message: '关闭后，系统截图、录屏和最近任务预览可能暴露应用中的账号、密码与订阅内容。是否继续？',
        confirmLabel: '关闭保护',
      );
      if (!confirmed) return;
    }
    setState(() => _working = true);
    final saved = await widget.appState.setScreenProtectionEnabled(enabled);
    if (mounted) setState(() => _working = false);
    _message(
      saved ? (enabled ? '防截屏保护已开启。' : '防截屏保护已关闭。') : '防截屏保护设置保存失败，请重试。',
    );
  }

  Future<void> _enableBiometric(QuickUnlockScope scope) async {
    if (scope == QuickUnlockScope.fullVault) {
      final accepted = await _confirm(
        title: '完整保险库可被生物识别打开',
        message:
            '启用后，成功验证指纹或人脸会直接显示账号和密码。在人身胁迫场景中，对方可能强迫你使用生物识别；诱饵密码只有在先输入时才能停用这条路径。是否继续？',
        confirmLabel: '我了解并继续',
      );
      if (!accepted) return;
    }

    final password = await _askPassword(
      title: '启用生物识别解锁',
      message: scope == QuickUnlockScope.subscriptionsOnly
          ? '先重新输入当前主密码，再由系统验证。生物识别只保存独立订阅视图的数据密钥，账号秘密仍需主密码。'
          : '先重新输入当前主密码，再由系统验证。完整模式会允许生物识别直接打开账号和订阅；应用不会保存主密码。',
      label: '当前主密码',
    );
    if (password == null) return;
    setState(() => _working = true);
    final ok = await widget.appState.enableQuickUnlock(password, scope: scope);
    if (mounted) setState(() => _working = false);
    _message(
      ok
          ? (scope == QuickUnlockScope.subscriptionsOnly
                ? '已启用“仅查看订阅”的生物识别。'
                : '已启用“完整保险库”的生物识别。')
          : widget.appState.errorMessage ?? '启用失败，请检查主密码和系统生物识别。',
    );
  }

  Future<QuickUnlockScope?> _chooseBiometricScope() =>
      showDialog<QuickUnlockScope>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择生物识别范围'),
          children: [
            SimpleDialogOption(
              key: const ValueKey<String>('biometric-subscriptions-only'),
              onPressed: () =>
                  Navigator.pop(context, QuickUnlockScope.subscriptionsOnly),
              child: const ListTile(
                leading: Icon(Icons.event_note_outlined),
                title: Text('仅查看订阅（推荐）'),
                subtitle: Text('账号资料和密码继续保持锁定；订阅视图只读'),
              ),
            ),
            SimpleDialogOption(
              key: const ValueKey<String>('biometric-full-vault'),
              onPressed: () =>
                  Navigator.pop(context, QuickUnlockScope.fullVault),
              child: const ListTile(
                leading: Icon(Icons.lock_open_outlined),
                title: Text('完整保险库'),
                subtitle: Text('更方便，但被迫使用生物识别时会暴露真实账号'),
              ),
            ),
          ],
        ),
      );

  Future<void> _changeBiometricScope() async {
    if (_working || !widget.appState.quickUnlockEnabled) return;
    final scope = await _chooseBiometricScope();
    if (scope == null || scope == widget.appState.quickUnlockScope) return;
    await _enableBiometric(scope);
  }

  Future<void> _setupDecoyVault() async {
    if (_working || widget.appState.decoyVaultConfigured) {
      return;
    }
    final currentPassword = await _askPassword(
      title: '验证真实保险库',
      message: '创建诱饵库前先输入真实主密码。该密码不会保存。',
      label: '当前真实主密码',
    );
    if (currentPassword == null) return;
    final decoyPassword = await _askNewPassword(
      title: '设置诱饵密码',
      message: '这不是“任意输错密码”。只有这一个明确设置的密码会打开独立诱饵库；它绝不会删除或修改真实数据。',
      label: '诱饵密码',
      purpose: NewPasswordPurpose.decoy,
    );
    if (decoyPassword == null) return;

    setState(() => _working = true);
    final ok = await widget.appState.createDecoyVault(
      currentMasterPassword: currentPassword,
      decoyPassword: decoyPassword,
    );
    if (mounted) setState(() => _working = false);
    _message(
      ok
          ? '诱饵库已创建；请锁定后用诱饵密码进入并亲自准备内容。'
          : widget.appState.errorMessage ?? '诱饵库创建失败。',
    );
  }

  Future<void> _configurePasswordRecovery(VaultRecoveryScope scope) async {
    if (_working ||
        !widget.appState.canManageSecurity ||
        widget.appState.recoveryChallengeFor(scope) != null ||
        (scope == VaultRecoveryScope.decoy &&
            !widget.appState.decoyVaultConfigured)) {
      return;
    }
    final currentPassword = await _askPassword(
      title: '验证真实保险库',
      message: scope == VaultRecoveryScope.primary
          ? '设置真实保险库密码恢复前请重新输入当前真实主密码。主密码和密保答案都不会保存。'
          : '管理诱饵保险库密码恢复需要真实主密码和当前诱饵密码双重授权；两者都不会保存。',
      label: '当前真实主密码',
    );
    if (currentPassword == null || !mounted) return;
    String? currentDecoyPassword;
    if (scope == VaultRecoveryScope.decoy) {
      currentDecoyPassword = await _askPassword(
        title: '验证当前诱饵密码',
        message: '此步骤不会打开诱饵库，也不会修改真实保险库。',
        label: '当前诱饵密码',
      );
      if (currentDecoyPassword == null || !mounted) return;
    }
    final otherChallenge = widget.appState.recoveryChallengeFor(
      scope == VaultRecoveryScope.primary
          ? VaultRecoveryScope.decoy
          : VaultRecoveryScope.primary,
    );
    final input = await showDialog<_RecoverySetupInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RecoverySetupDialog(
        title: scope == VaultRecoveryScope.primary
            ? '设置真实保险库密码恢复'
            : '设置诱饵保险库密码恢复',
        avoidQuestionIds: otherChallenge?.questionIds ?? const <String>[],
      ),
    );
    if (input == null) return;
    if (otherChallenge != null) {
      final selected = input.questionIds.toSet();
      final other = otherChallenge.questionIds.toSet();
      if (selected.length == other.length && selected.containsAll(other)) {
        _message('两套保险库不能使用完全相同的三道密保问题；请至少更换一道。');
        return;
      }
    }

    setState(() => _working = true);
    final ok = await widget.appState.configurePasswordRecovery(
      currentMasterPassword: currentPassword,
      currentDecoyPassword: currentDecoyPassword,
      questionIds: input.questionIds,
      answers: input.answers,
      entryMode: input.entryMode,
      scope: scope,
    );
    if (mounted) setState(() => _working = false);
    _message(
      ok
          ? scope == VaultRecoveryScope.primary
                ? '真实保险库密码恢复已启用；请锁定后亲自验证入口和三道答案。'
                : '诱饵保险库密码恢复已启用；请锁定后亲自验证入口和三道答案。'
          : widget.appState.errorMessage ?? '密码恢复设置失败，保险库仍可使用原主密码。',
    );
  }

  Future<void> _disablePasswordRecovery(VaultRecoveryScope scope) async {
    if (_working ||
        !widget.appState.canManageSecurity ||
        widget.appState.recoveryChallengeFor(scope) == null) {
      return;
    }
    final confirmed = await _confirm(
      title: scope == VaultRecoveryScope.primary
          ? '关闭真实保险库密码恢复？'
          : '关闭诱饵保险库密码恢复？',
      message: scope == VaultRecoveryScope.primary
          ? '关闭后，忘记真实主密码时只能依赖你单独保存的加密备份。业务数据和当前密码不会改变。'
          : '关闭后，如果忘记诱饵密码，独立诱饵库内容将无法通过真实库备份恢复。现有内容和当前密码不会改变。',
      confirmLabel: '继续关闭',
    );
    if (!confirmed) return;
    final currentPassword = await _askPassword(
      title: '验证真实保险库',
      message: scope == VaultRecoveryScope.primary
          ? '关闭恢复前必须重新验证真实主密码。'
          : '管理诱饵保险库密码恢复需要真实主密码和当前诱饵密码双重授权。',
      label: '当前真实主密码',
    );
    if (currentPassword == null) return;
    String? currentDecoyPassword;
    if (scope == VaultRecoveryScope.decoy) {
      currentDecoyPassword = await _askPassword(
        title: '验证当前诱饵密码',
        message: '此步骤不会打开诱饵库，也不会修改真实保险库。',
        label: '当前诱饵密码',
      );
      if (currentDecoyPassword == null) return;
    }

    setState(() => _working = true);
    final ok = await widget.appState.disablePasswordRecovery(
      currentMasterPassword: currentPassword,
      currentDecoyPassword: currentDecoyPassword,
      scope: scope,
    );
    if (mounted) setState(() => _working = false);
    _message(
      ok
          ? scope == VaultRecoveryScope.primary
                ? '真实保险库密码恢复已关闭。'
                : '诱饵保险库密码恢复已关闭。'
          : widget.appState.errorMessage ?? '密码恢复关闭失败，原配置仍保持不变。',
    );
  }

  Future<void> _changeMasterPassword() async {
    if (_working || !widget.appState.canManageSecurity) return;
    if (widget.appState.recoveryConfigured) {
      _message('为保证双因子恢复不会继续包装旧数据密钥，请先关闭真实保险库密码恢复，再修改真实主密码；修改后可重新设置。');
      return;
    }
    if (widget.appState.hasUncertainRecoveryTransaction) {
      _message('检测到尚未确认的恢复事务；请先核对并处理“撤销最近一次备份恢复”，再修改主密码。');
      return;
    }
    final currentPassword = await _askPassword(
      title: '验证当前主密码',
      message: '修改前必须重新验证真实主密码。密码只在本机参与解密，不会保存。',
      label: '当前真实主密码',
    );
    if (currentPassword == null) return;
    final newPassword = await _askNewPassword(
      title: '设置新的主密码',
      message: '修改时会生成全新的随机 256 位数据密钥，并重新加密真实保险库；请务必记住新密码。',
      label: '新主密码',
    );
    if (newPassword == null) return;

    final discardingRollback = widget.appState.hasRecoveryRollback;
    final confirmed = await _confirm(
      title: '确认修改主密码？',
      message: discardingRollback
          ? '完成后旧主密码不能再打开当前保险库，生物识别快速解锁会安全停用，需要之后用新主密码重新开启。\n\n本机“上次导入前”的加密回滚副本仍受旧密码保护，将先被永久废弃；独立导出的 .asmbackup 文件不受影响。'
          : '完成后旧主密码不能再打开当前保险库，生物识别快速解锁会安全停用，需要之后用新主密码重新开启。',
      confirmLabel: '确认修改',
    );
    if (!confirmed) return;

    setState(() => _working = true);
    final ok = await widget.appState.changeMasterPassword(
      currentMasterPassword: currentPassword,
      newMasterPassword: newPassword,
      discardRecoveryRollback: discardingRollback,
    );
    if (mounted) setState(() => _working = false);
    _message(
      ok
          ? '主密码已修改；当前数据已换用新随机密钥加密，生物识别已停用。'
          : widget.appState.errorMessage ?? '主密码修改失败，当前数据未被确认切换。',
    );
  }

  Future<void> _changeDecoyPassword() async {
    if (_working ||
        !widget.appState.canManageSecurity ||
        !widget.appState.decoyVaultConfigured) {
      return;
    }
    if (widget.appState.decoyRecoveryConfigured) {
      _message('请先关闭诱饵保险库密码恢复，再修改诱饵密码；完成后可重新设置三道密保。');
      return;
    }
    final currentMasterPassword = await _askPassword(
      title: '验证真实保险库',
      message: '修改诱饵密码需要真实主密码和当前诱饵密码双重授权；两者都不会保存。',
      label: '当前真实主密码',
    );
    if (currentMasterPassword == null) return;
    final currentDecoyPassword = await _askPassword(
      title: '验证当前诱饵密码',
      message: '输入当前诱饵密码。此步骤不会打开诱饵库，也不会改变生物识别设置。',
      label: '当前诱饵密码',
    );
    if (currentDecoyPassword == null) return;
    final newDecoyPassword = await _askNewPassword(
      title: '设置新的诱饵密码',
      message: '新密码会打开原有诱饵库内容，不会创建空库，也不会删除或修改真实数据。',
      label: '新诱饵密码',
      purpose: NewPasswordPurpose.decoy,
    );
    if (newDecoyPassword == null) return;

    setState(() => _working = true);
    final ok = await widget.appState.changeDecoyPassword(
      currentMasterPassword: currentMasterPassword,
      currentDecoyPassword: currentDecoyPassword,
      newDecoyPassword: newDecoyPassword,
    );
    if (mounted) setState(() => _working = false);
    _message(
      ok
          ? '诱饵密码已修改；原诱饵内容保留，旧诱饵密码已失效，生物识别设置未改变。'
          : widget.appState.errorMessage ?? '诱饵密码修改失败，原诱饵密码仍然有效。',
    );
  }

  Future<void> _chooseAutoLock() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('自动锁定时间'),
        children: [
          for (final option in const <int, String>{
            0: '离开应用立即锁定',
            30: '30秒',
            60: '1分钟',
            300: '5分钟',
            900: '15分钟',
          }.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option.key),
              child: Row(
                children: [
                  Expanded(child: Text(option.value)),
                  if (widget.appState.preferences.autoLockSeconds == option.key)
                    const Icon(Icons.check),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected == null) return;
    final ok = await widget.appState.updatePreferences(
      widget.appState.preferences.copyWith(autoLockSeconds: selected),
    );
    _message(ok ? '自动锁定时间已更新。' : '设置保存失败。');
  }

  Future<void> _chooseReminderDays() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('新增订阅默认提前提醒'),
        children: [
          for (final days in const <int>[0, 1, 3, 7, 15, 30])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, days),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      days == 0
                          ? context.tr('续费当天')
                          : context.tr('提前{days}天', <String, Object?>{
                              'days': days,
                            }),
                      translate: false,
                    ),
                  ),
                  if (widget.appState.preferences.defaultReminderDaysBefore ==
                      days)
                    const Icon(Icons.check),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected == null) return;
    final ok = await widget.appState.updatePreferences(
      widget.appState.preferences.copyWith(defaultReminderDaysBefore: selected),
    );
    _message(ok ? '默认提醒时间已更新，仅影响以后新增订阅。' : '设置保存失败。');
  }

  Future<void> _chooseReminderTime({bool second = false}) async {
    final current = second
        ? widget.appState.preferences.secondReminderTimeMinutes
        : widget.appState.preferences.defaultReminderTimeMinutes;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: context.tr(second ? '选择第二次提醒时间' : '选择第一次提醒时间'),
      confirmText: context.tr('确定'),
      cancelText: context.tr('取消'),
    );
    if (selected == null) return;
    final minutes = selected.hour * 60 + selected.minute;
    final ok = await widget.appState.updatePreferences(
      widget.appState.preferences.copyWith(
        defaultReminderTimeMinutes: second ? null : minutes,
        secondReminderTimeMinutes: second ? minutes : null,
      ),
    );
    _message(ok ? '提醒时间已更新，已安排的本地提醒会同步调整。' : '设置保存失败。');
  }

  String _formatReminderTime(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _chooseCurrency() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('新增订阅默认货币'),
        children: [
          for (final currency in subscriptionCurrencies)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, currency),
              child: Row(
                children: [
                  Expanded(child: Text(currency, translate: false)),
                  if (widget.appState.preferences.defaultCurrency == currency)
                    const Icon(Icons.check),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected == null) return;
    final ok = await widget.appState.updatePreferences(
      widget.appState.preferences.copyWith(defaultCurrency: selected),
    );
    _message(ok ? '默认货币已更新，仅影响以后新增订阅。' : '设置保存失败。');
  }

  Future<void> _chooseDisplayMode({required bool forAccounts}) async {
    final preferences = widget.appState.preferences;
    final current = forAccounts
        ? preferences.accountDisplayMode
        : preferences.subscriptionDisplayMode;
    final selected = await showDialog<RecordDisplayMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(
          context.tr(forAccounts ? '账号显示方式' : '订阅显示方式'),
          translate: false,
        ),
        children: [
          for (final mode in RecordDisplayMode.values)
            SimpleDialogOption(
              key: ValueKey<String>(
                '${forAccounts ? 'account' : 'subscription'}-display-${mode.name}',
              ),
              onPressed: () => Navigator.pop(context, mode),
              child: Row(
                children: [
                  Expanded(child: Text(mode.label)),
                  if (mode == current) const Icon(Icons.check),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected == null || selected == current) return;
    final next = forAccounts
        ? preferences.copyWith(accountDisplayMode: selected)
        : preferences.copyWith(subscriptionDisplayMode: selected);
    final ok = await widget.appState.updatePreferences(next);
    _message(ok ? '显示方式已更新。' : '设置保存失败。');
  }

  Future<void> _chooseLanguage(CardockLanguageController controller) async {
    final current = controller.language;
    final selected = await showDialog<CardockLanguage>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('选择语言'),
        children: [
          for (final language in CardockLanguage.values)
            SimpleDialogOption(
              key: ValueKey<String>('language-${language.storageCode}'),
              onPressed: () => Navigator.pop(dialogContext, language),
              child: Row(
                children: [
                  Expanded(child: Text(language.nativeName, translate: false)),
                  if (language == current) const Icon(Icons.check),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected == null || selected == current) return;

    setState(() => _working = true);
    try {
      await controller.setLanguage(selected);
      try {
        await widget.appState.refreshReminderScheduleForReliability();
      } on Object {
        // The language is already persisted. Reminder rescheduling must not
        // roll it back or expose subscription details in an error message.
      }
      if (mounted) _message(context.tr('语言已切换'));
    } on Object {
      if (mounted) _message(context.tr('语言切换失败，请重试。'));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _openAppearanceSettings(CardockAppearanceController controller) {
    final renewalsWithinThirtyDays = subscriptionsForPreset(
      widget.appState.subscriptions,
      SubscriptionListPreset.renewingWithinThirtyDays,
    ).length;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const VaultPageLocation('appearance'),
        builder: (context) => _AppearanceSettingsPage(
          controller: controller,
          accountCount: widget.appState.accounts.length,
          subscriptionCount: widget.appState.subscriptions.length,
          renewalsWithinThirtyDays: renewalsWithinThirtyDays,
        ),
      ),
    );
  }

  void _openFullVersion(ProductEntitlementController controller) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const VaultPageLocation('fullVersion'),
        builder: (context) => FullVersionPage(controller: controller),
      ),
    );
  }

  void _openPurchaseCredential(ProductEntitlementController controller) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const VaultPageLocation('purchaseCredential'),
        builder: (context) => PurchaseCredentialPage(
          controller: controller,
          managementAllowed:
              widget.appState.hasFullVaultAccess &&
              widget.appState.canManageSecurity,
          onImportWebsiteAuthorization: () =>
              showWebsiteAuthorizationDialog(context, controller),
          onRestoreStorePurchase: () async {
            final result = await controller.restore();
            if (context.mounted) _message(result.message);
          },
        ),
      ),
    );
  }

  void _openAboutCardock() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const VaultPageLocation('about'),
        builder: (context) => const AboutCardockPage(),
      ),
    );
  }

  void _openDeveloperNote() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const VaultPageLocation('developer'),
        builder: (context) => const DeveloperNotePage(),
      ),
    );
  }

  Future<void> _toggleNotifications(bool enabled) async {
    if (_working) return;
    setState(() => _working = true);
    NotificationSettingResult result;
    try {
      result = widget.onNotificationsChanged != null
          ? await widget.onNotificationsChanged!(enabled)
          : await widget.appState.setNotificationsEnabled(enabled);
    } on Object {
      result = NotificationSettingResult.permissionCheckFailed;
    }
    if (mounted) setState(() => _working = false);
    _message(_notificationResultMessage(result));
  }

  String _notificationResultMessage(
    NotificationSettingResult result,
  ) => switch (result) {
    NotificationSettingResult.enabled => '本地续费提醒已开启。',
    NotificationSettingResult.disabled => '本地续费提醒已关闭。',
    NotificationSettingResult.applicationNotificationsDisabled =>
      '手机系统已关闭本应用的总通知权限，请先在系统设置中开启。',
    NotificationSettingResult.reminderChannelDisabled =>
      '本应用总通知权限已开启，但“本机订阅提醒”通知通道已关闭，请在系统通知设置中开启该类别。',
    NotificationSettingResult.permissionCheckFailed => '无法检查系统通知状态，请稍后重试。',
    NotificationSettingResult.saveFailed => '系统通知可用，但通知设置保存失败。',
    NotificationSettingResult.initializationFailed =>
      '设置已保存为开启，但系统通知初始化失败；请前往“通知可靠性”测试通知并重试。',
    NotificationSettingResult.scheduleFailed => '设置已保存为开启，但部分提醒重排失败；下次解锁会自动重试。',
    NotificationSettingResult.cancelFailed => '设置已保存为关闭，但旧提醒清理失败；下次解锁会自动重试。',
    NotificationSettingResult.rejected => '当前状态无法更改通知设置，请稍后重试。',
  };

  Future<void> _openNotificationReliability() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const VaultPageLocation('notificationReliability'),
        builder: (context) =>
            NotificationReliabilityPage(appState: widget.appState),
      ),
    );
  }

  Future<void> _exportBackup() async {
    if (_working) return;
    final saveDialogTitle = context.tr('保存加密备份');
    final backupPassword = await _askNewPassword(
      title: '设置独立备份密码',
      message: '每次导出都会使用新的随机密钥材料重新加密。备份密码可以与本机主密码不同，应用不会保存；遗失后无法恢复文件。',
      label: '备份密码',
    );
    if (backupPassword == null) return;
    setState(() => _working = true);
    final bytes = await widget.appState.exportEncryptedBackup(
      backupMasterPassword: backupPassword,
    );
    if (bytes == null) {
      if (mounted) setState(() => _working = false);
      _message('无法生成加密备份。');
      return;
    }
    bool saved = false;
    try {
      widget.appState.beginExternalInteraction();
      saved = await widget.backupService.saveEncryptedBackup(
        bytes,
        dialogTitle: saveDialogTitle,
      );
    } on Object {
      _message('保存备份失败，请检查文件位置。');
    } finally {
      widget.appState.endExternalInteraction();
      bytes.fillRange(0, bytes.length, 0);
      if (mounted) setState(() => _working = false);
    }
    if (saved) {
      await widget.appState.recordBackupExported();
      _message(
        '加密备份已保存为 .asmbackup。请打开“自动备份与备份检查”→“检查 Cardock 加密备份（不恢复）”核对文件。',
      );
    }
  }

  Future<void> _restoreBackup({bool verifyOnly = false}) async {
    if (_working) return;
    setState(() => _working = true);
    PortableBackupSelection? selection;
    try {
      widget.appState.beginExternalInteraction();
      selection = await widget.backupService.pickEncryptedBackup(
        dialogTitle: context.tr('选择 .asmbackup 加密备份'),
      );
    } on FormatException catch (error) {
      _message(error.message.toString());
    } on Object {
      _message('无法读取所选备份文件。');
    } finally {
      widget.appState.endExternalInteraction();
      if (mounted) setState(() => _working = false);
    }
    if (selection == null) return;
    final bytes = selection.bytes;
    if (!mounted) {
      bytes.fillRange(0, bytes.length, 0);
      return;
    }
    final rejectionMessage = switch (classifyDataTransferFile(
      fileName: selection.name,
      bytes: bytes,
    )) {
      DataTransferFileRole.encryptedBackup => null,
      DataTransferFileRole.calendarIcs =>
        '这是日历 .ics 文件，不包含可恢复的 Cardock 保险库；请选择 .asmbackup。',
      DataTransferFileRole.externalImport =>
        '这是外部表格或文档；请使用“导入外部数据”。恢复入口只接受 .asmbackup。',
      DataTransferFileRole.unsupported =>
        '所选文件不是可识别的 Cardock 加密备份；请选择 .asmbackup。',
    };
    if (rejectionMessage != null) {
      bytes.fillRange(0, bytes.length, 0);
      _message(rejectionMessage);
      return;
    }

    final backupPassword = await _askPassword(
      title: '验证加密备份',
      message: '请输入创建这份备份时设置的独立备份密码。验证前不会修改本机数据。',
      label: '备份密码',
    );
    if (backupPassword == null) {
      bytes.fillRange(0, bytes.length, 0);
      return;
    }
    final preview = await widget.appState.inspectEncryptedBackup(
      bytes: bytes,
      backupMasterPassword: backupPassword,
    );
    if (preview == null) {
      bytes.fillRange(0, bytes.length, 0);
      _message(widget.appState.errorMessage ?? '备份验证失败。');
      return;
    }

    if (verifyOnly) {
      bytes.fillRange(0, bytes.length, 0);
      _message('备份已完整验证，本机数据未改变。');
      return;
    }
    final authorization = await _askRestoreAuthorization(preview);
    if (authorization == null) {
      bytes.fillRange(0, bytes.length, 0);
      return;
    }
    setState(() => _working = true);
    final restored = await widget.appState.restoreEncryptedBackup(
      bytes: bytes,
      backupMasterPassword: backupPassword,
      currentMasterPassword: authorization,
    );
    bytes.fillRange(0, bytes.length, 0);
    if (mounted) setState(() => _working = false);
    _message(
      restored
          ? '恢复成功：已用当前本机主密码重新加密保存。'
          : (widget.appState.errorMessage ?? '恢复失败，本机原数据未被替换。'),
    );
  }

  Future<String?> _askRestoreAuthorization(
    EncryptedBackupPreview preview,
  ) async {
    final passwordController = TextEditingController();
    final phraseController = TextEditingController();
    final navigator = Navigator.of(context, rootNavigator: true);
    late final DialogRoute<String> route;
    var obscure = true;
    try {
      route = DialogRoute<String>(
        context: context,
        themes: InheritedTheme.capture(from: context, to: navigator.context),
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('确认覆盖本机记录'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.tr(
                      '备份格式 v{format}，数据 schema {schema}{created}。\n'
                      '备份包含 {backupAccounts} 个账号、{backupSubscriptions} 条订阅；本机当前有 '
                      '{currentAccounts} 个账号、{currentSubscriptions} 条订阅。\n\n'
                      '恢复会替换业务内容，但保留当前本机主密码、自动锁定和通知开关；写入前会先生成本机加密回滚副本。',
                      <String, Object?>{
                        'format': preview.formatVersion,
                        'schema': preview.sourceSchemaVersion,
                        'created': preview.createdAtUtc == null
                            ? ''
                            : context.tr('，创建于 {time}', <String, Object?>{
                                'time': _formatBackupTime(
                                  preview.createdAtUtc!,
                                ),
                              }),
                        'backupAccounts': preview.accountCount,
                        'backupSubscriptions': preview.subscriptionCount,
                        'currentAccounts': widget.appState.accounts.length,
                        'currentSubscriptions':
                            widget.appState.subscriptions.length,
                      },
                    ),
                    translate: false,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey<String>(
                      'restore-authorization-password',
                    ),
                    controller: passwordController,
                    obscureText: obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    decoration: InputDecoration(
                      labelText: context.tr('当前本机主密码'),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setDialogState(() => obscure = !obscure),
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey<String>('restore-authorization-phrase'),
                    controller: phraseController,
                    decoration: InputDecoration(
                      labelText: context.tr('输入“恢复”确认'),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (phraseController.text.trim() == context.tr('恢复') &&
                      passwordController.text.isNotEmpty) {
                    Navigator.pop(context, passwordController.text);
                  }
                },
                child: const Text('确认恢复'),
              ),
            ],
          ),
        ),
      );
      final result = await navigator.push(route);
      await route.completed;
      return result;
    } finally {
      passwordController.clear();
      phraseController.clear();
      passwordController.dispose();
      phraseController.dispose();
    }
  }

  String _formatBackupTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _rollbackLastRestore() async {
    if (_working || !widget.appState.hasRecoveryRollback) return;
    final confirmed = await _confirm(
      title: '恢复到导入前的数据？',
      message: '这会用上次导入前自动保存的本机加密副本替换当前业务内容。当前主密码保持不变。',
      confirmLabel: '继续验证',
    );
    if (!confirmed) return;
    final password = await _askPassword(
      title: '验证当前主密码',
      message: '只有当前真实主密码才能使用恢复前回滚副本。',
      label: '当前本机主密码',
    );
    if (password == null) return;
    setState(() => _working = true);
    final ok = await widget.appState.restoreLastRecoveryRollback(
      currentMasterPassword: password,
    );
    if (mounted) setState(() => _working = false);
    _message(
      ok ? '已撤销最近一次备份恢复，已回到恢复前的数据。' : widget.appState.errorMessage ?? '回滚失败。',
    );
  }

  Future<String?> _askPassword({
    required String title,
    required String message,
    required String label,
  }) => showDialog<String>(
    context: context,
    builder: (context) =>
        _PasswordPromptDialog(title: title, message: message, label: label),
  );

  Future<String?> _askNewPassword({
    required String title,
    required String message,
    required String label,
    NewPasswordPurpose purpose = NewPasswordPurpose.critical,
  }) => showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _NewPasswordPromptDialog(
      title: title,
      message: message,
      label: label,
      purpose: purpose,
      sensitiveClipboard: widget.sensitiveClipboard,
    ),
  );

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr(title), translate: false),
          content: Text(context.tr(message), translate: false),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr(confirmLabel), translate: false),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _openTemporaryWebSession() async {
    final controller = widget.temporaryWebController;
    if (controller == null || _offlineWebsite) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const VaultPageLocation('temporaryWeb'),
        builder: (context) => TemporaryWebSessionPage(
          controller: controller,
          sensitiveClipboard: widget.sensitiveClipboard,
        ),
      ),
    );
  }

  Future<void> _openDataMigrationCenter() async {
    final factory =
        widget.dataImportControllerFactory ??
        () => AppDataImportUiController(appState: widget.appState);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const VaultPageLocation('dataMigration'),
        builder: (context) => DataMigrationCenterHubPage(
          appState: widget.appState,
          controllerFactory: factory,
          onOpenComputerBatch:
              widget.temporaryWebController == null || _offlineWebsite
              ? null
              : _openTemporaryWebSession,
          onUndoLastBatch: _undoLastBatchImport,
        ),
      ),
    );
  }

  Future<void> _openPendingSubscriptionDrafts() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const VaultPageLocation('pendingDrafts'),
      builder: (context) =>
          PendingSubscriptionDraftsPage(appState: widget.appState),
    ),
  );

  Future<void> _undoLastBatchImport() async {
    if (_working || !widget.appState.canUndoLastBatchImport) return;
    final impact = widget.appState.lastBatchRollbackImpact;
    if (impact == null) return;
    final confirmed = await _confirm(
      title: '撤销最近一次批量导入？',
      message:
          '这与“恢复到上次备份导入前”完全独立。只会撤销最近一次批量导入的精确加密快照：新增账号 ${impact.addedAccountCount}、更新账号 ${impact.updatedAccountCount}、正式订阅 ${impact.formalSubscriptionCount}、待完善草稿 ${impact.pendingSubscriptionDraftCount}，共影响 ${impact.affectedRecordCount} 条。\n\n如果批量导入后已有其他保存，入口会自动失效，不会覆盖后续修改。',
      confirmLabel: '确认撤销这一次批量导入',
    );
    if (!confirmed) return;
    setState(() => _working = true);
    final ok = await widget.appState.undoLastBatchImport();
    if (mounted) setState(() => _working = false);
    _message(ok ? '最近一次批量导入已撤销。' : '撤销条件已变化；没有覆盖当前数据。');
  }

  @override
  Widget build(BuildContext context) {
    final preferences = widget.appState.preferences;
    final palette = context.cardockTheme.palette;
    final appearanceController = CardockAppearanceScope.maybeOf(context);
    final languageController = CardockLanguageScope.maybeOf(context);
    final entitlementController = ProductEntitlementScope.of(context);
    final appearancePreferences =
        appearanceController?.preferences ?? const AppearancePreferences();
    final subscriptionOnly = widget.appState.hasSubscriptionOnlyAccess;
    final editable = !subscriptionOnly;
    final canRestore = editable && widget.appState.canManageSecurity;
    return ListView(
      key: const ValueKey<String>('settings-page'),
      padding: const EdgeInsets.fromLTRB(
        CardockLayout.screenHorizontal,
        8,
        CardockLayout.screenHorizontal,
        24,
      ),
      children: [
        _VaultSummary(
          quickUnlockEnabled: widget.appState.quickUnlockEnabled,
          autoLockLabel: _autoLockLabel(preferences.autoLockSeconds),
          decoyConfigured: widget.appState.canManageSecurity
              ? widget.appState.decoyVaultConfigured
              : null,
        ),
        const SizedBox(height: 9),
        const _LocalOnlyNotice(),
        const SizedBox(height: 18),
        if (subscriptionOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                key: const ValueKey<String>(
                  'subscription-only-settings-notice',
                ),
                leading: CardockSemanticIcon(
                  icon: Icons.visibility_outlined,
                  color: palette.statusInformation,
                ),
                title: const Text('当前仅解锁订阅只读视图'),
                subtitle: const Text('账号、编辑、安全配置和备份仍需真实主密码；可随时点“立即锁定”后改用主密码。'),
              ),
            ),
          ),
        _SettingsGroup(
          title: '安全',
          children: [
            _SettingsTile(
              key: const ValueKey<String>('change-master-password'),
              icon: Icons.password_outlined,
              title: '主密码',
              status: '已设置 · 点击修改；修改后需重新开启生物识别',
              onTap: _working || !editable || !widget.appState.canManageSecurity
                  ? null
                  : _changeMasterPassword,
            ),
            if (widget.appState.canManageSecurity)
              _SettingsTile(
                key: const ValueKey<String>('password-recovery-setting'),
                icon: Icons.admin_panel_settings_outlined,
                title: '真实保险库密码恢复',
                status: widget.appState.primaryRecoveryConfigured
                    ? widget.appState.primaryRecoveryChallenge?.entryMode ==
                              VaultRecoveryEntryMode.logoFiveTap
                          ? '已配置 · 3秒内连续点锁屏Logo 5次'
                          : '已配置 · 锁屏页直接显示入口'
                    : '未配置 · 独立三道密保 + 本机系统强认证',
                onTap: _working || !editable
                    ? null
                    : widget.appState.primaryRecoveryConfigured
                    ? () => _disablePasswordRecovery(VaultRecoveryScope.primary)
                    : () => _configurePasswordRecovery(
                        VaultRecoveryScope.primary,
                      ),
              ),
            if (widget.appState.canManageSecurity &&
                widget.appState.decoyVaultConfigured)
              _SettingsTile(
                key: const ValueKey<String>('decoy-password-recovery-setting'),
                icon: Icons.shield_outlined,
                title: '诱饵保险库密码恢复',
                status: widget.appState.decoyRecoveryConfigured
                    ? widget.appState.decoyRecoveryChallenge?.entryMode ==
                              VaultRecoveryEntryMode.logoFiveTap
                          ? '已配置 · 3秒内连续点锁屏Logo 5次'
                          : '已配置 · 锁屏页直接显示入口'
                    : '未配置 · 独立三道密保 + 本机系统强认证',
                onTap: _working || !editable
                    ? null
                    : widget.appState.decoyRecoveryConfigured
                    ? () => _disablePasswordRecovery(VaultRecoveryScope.decoy)
                    : () =>
                          _configurePasswordRecovery(VaultRecoveryScope.decoy),
              ),
            SwitchListTile(
              key: const ValueKey<String>('screen-protection-switch'),
              secondary: CardockSemanticIcon(
                icon: Icons.screenshot_monitor_outlined,
                color: palette.statusInformation,
              ),
              title: const Text('防截屏保护'),
              subtitle: const Text('开启后系统将阻止截图与录屏，并在最近任务中隐藏应用画面预览'),
              value: widget.appState.screenProtectionEnabled,
              onChanged: _working ? null : _toggleScreenProtection,
            ),
            SwitchListTile(
              secondary: CardockSemanticIcon(
                icon: Icons.fingerprint,
                color: palette.fieldLogin,
              ),
              title: const Text('指纹或人脸解锁'),
              subtitle: Text(
                !widget.appState.canManageSecurity
                    ? '当前会话中不可修改；请先锁定后再进入安全设置'
                    : widget.appState.quickUnlockScope ==
                          QuickUnlockScope.subscriptionsOnly
                    ? '当前仅解锁独立订阅只读视图；账号秘密仍需主密码'
                    : '完整模式会直接打开账号和订阅；不保存主密码',
              ),
              value: widget.appState.quickUnlockEnabled,
              onChanged:
                  _working || !editable || !widget.appState.canManageSecurity
                  ? null
                  : _toggleBiometric,
            ),
            if (widget.appState.quickUnlockEnabled)
              _SettingsTile(
                icon: Icons.layers_outlined,
                title: '生物识别解锁范围',
                status:
                    widget.appState.quickUnlockScope ==
                        QuickUnlockScope.subscriptionsOnly
                    ? '仅查看订阅（推荐）'
                    : '完整保险库 · 存在人身胁迫风险',
                onTap: _working || !editable ? null : _changeBiometricScope,
              ),
            if (widget.appState.canManageSecurity)
              _SettingsTile(
                key: const ValueKey<String>('decoy-vault-setting'),
                icon: Icons.theater_comedy_outlined,
                title: '诱饵密码与独立诱饵库',
                status: widget.appState.decoyVaultConfigured
                    ? '已配置 · 点击修改；原诱饵内容会保留'
                    : '未配置 · 由你亲自准备诱饵内容',
                onTap: _working || !editable
                    ? null
                    : widget.appState.decoyVaultConfigured
                    ? _changeDecoyPassword
                    : _setupDecoyVault,
              ),
            _SettingsTile(
              icon: Icons.lock_clock_outlined,
              title: '自动锁定时间',
              status: _autoLockLabel(preferences.autoLockSeconds),
              onTap: _working || !editable ? null : _chooseAutoLock,
            ),
            _SettingsTile(
              icon: Icons.lock_outline,
              title: '立即锁定',
              status: '清除内存中的解锁密钥和记录',
              onTap: _working ? null : widget.onLock,
            ),
          ],
        ),
        if (widget.appState.quickUnlockEnabled &&
            widget.appState.quickUnlockScope == QuickUnlockScope.fullVault)
          const _CoercionWarning(),
        _SettingsGroup(
          title: '提醒与订阅偏好',
          children: [
            SwitchListTile(
              secondary: CardockSemanticIcon(
                icon: Icons.notifications_active_outlined,
                color: palette.fieldSubscription,
              ),
              title: const Text('本地续费提醒'),
              subtitle: const Text('通知内容取决于你选择的隐私级别；应用内记录才是权威来源'),
              value: preferences.notificationsEnabled,
              onChanged: _working || !editable ? null : _toggleNotifications,
            ),
            if (widget.appState.canManageSecurity)
              _SettingsTile(
                key: const ValueKey<String>('notification-reliability-entry'),
                icon: Icons.health_and_safety_outlined,
                title: '通知可靠性',
                status: '权限、通道、电池优化、厂商后台策略与恢复记录',
                onTap: _working ? null : _openNotificationReliability,
              ),
            _SettingsTile(
              icon: Icons.notifications_none,
              title: '新增订阅默认提前量',
              status: preferences.defaultReminderDaysBefore == 0
                  ? '续费当天'
                  : context.tr('提前{days}天', <String, Object?>{
                      'days': preferences.defaultReminderDaysBefore,
                    }),
              onTap: _working || !editable ? null : _chooseReminderDays,
            ),
            _SettingsTile(
              icon: Icons.schedule_outlined,
              key: const ValueKey<String>('first-reminder-time'),
              title: '第一次提醒发送时间',
              status: _formatReminderTime(
                preferences.defaultReminderTimeMinutes,
              ),
              translateStatus: false,
              onTap: _working || !editable ? null : () => _chooseReminderTime(),
            ),
            _SettingsTile(
              key: const ValueKey<String>('second-reminder-time'),
              icon: Icons.schedule_outlined,
              title: '第二次提醒发送时间',
              status: _formatReminderTime(
                preferences.secondReminderTimeMinutes,
              ),
              translateStatus: false,
              onTap: _working || !editable
                  ? null
                  : () => _chooseReminderTime(second: true),
            ),
            _SettingsTile(
              icon: Icons.payments_outlined,
              title: '默认货币',
              status: preferences.defaultCurrency,
              translateStatus: false,
              onTap: _working || !editable ? null : _chooseCurrency,
            ),
          ],
        ),
        _SettingsGroup(
          title: '显示偏好',
          children: [
            _SettingsTile(
              key: const ValueKey<String>('language-setting'),
              icon: Icons.language_outlined,
              title: '语言',
              status:
                  languageController?.language.nativeName ??
                  CardockLanguage.simplifiedChinese.nativeName,
              translateStatus: false,
              onTap: _working || languageController == null
                  ? null
                  : () => _chooseLanguage(languageController),
            ),
            _SettingsTile(
              key: const ValueKey<String>('account-display-mode-setting'),
              icon: Icons.badge_outlined,
              title: '账号显示方式',
              status: preferences.accountDisplayMode.label,
              onTap: _working || !editable
                  ? null
                  : () => _chooseDisplayMode(forAccounts: true),
            ),
            _SettingsTile(
              key: const ValueKey<String>('subscription-display-mode-setting'),
              icon: Icons.event_repeat_outlined,
              title: '订阅显示方式',
              status: preferences.subscriptionDisplayMode.label,
              onTap: _working || !editable
                  ? null
                  : () => _chooseDisplayMode(forAccounts: false),
            ),
          ],
        ),
        _SettingsGroup(
          title: '外观',
          children: [
            _SettingsTile(
              key: const ValueKey<String>('appearance-settings-entry'),
              icon: Icons.palette_outlined,
              title: '外观与桌面图标',
              status: context.tr('{theme} · {brightness} · 桌面 {launcher}', <
                String,
                Object?
              >{
                'theme': context.tr(
                  _themeFamilyName(appearancePreferences.family),
                ),
                'brightness': context.tr(
                  appearancePreferences.brightnessMode.label,
                ),
                'launcher':
                    '${appearancePreferences.desktopIconMode == CardockDesktopIconMode.followTheme ? context.tr('跟随→') : ''}'
                    '${context.tr(_launcherFamilyName(appearancePreferences.resolvedLauncherFamily))}',
              }),
              onTap: _working || appearanceController == null
                  ? null
                  : () => _openAppearanceSettings(appearanceController),
            ),
          ],
        ),
        _SettingsGroup(
          title: '数据导入与备份',
          children: [
            _SettingsTile(
              key: const ValueKey<String>('data-migration-center-entry'),
              icon: Icons.move_to_inbox_outlined,
              title: '导入外部数据',
              status: subscriptionOnly
                  ? '订阅只读视图不能导入，请先完整解锁保险库'
                  : !widget.appState.canManageSecurity
                  ? '当前会话不能导入外部数据'
                  : 'XLSX/CSV 等外部文件；.asmbackup 请用“恢复”',
              statusMaxLines: 6,
              onTap: _working || !editable || !widget.appState.canManageSecurity
                  ? null
                  : _openDataMigrationCenter,
            ),
            _SettingsTile(
              key: const ValueKey<String>('encrypted-backup-export-entry'),
              icon: Icons.backup_outlined,
              title: '导出 Cardock 加密备份',
              status: widget.appState.canManageSecurity
                  ? '.asmbackup · 账号与订阅 · 独立备份密码'
                  : '当前会话不能导出 Cardock 加密备份',
              statusMaxLines: 6,
              onTap: _working || !editable || !widget.appState.canManageSecurity
                  ? null
                  : _exportBackup,
            ),
            if (widget.appState.canManageSecurity)
              _SettingsTile(
                key: const ValueKey<String>('encrypted-backup-restore-entry'),
                icon: Icons.restore_outlined,
                title: '恢复 Cardock 加密备份',
                status: '手动/自动备份 .asmbackup；先验证再恢复',
                statusMaxLines: 6,
                onTap: _working || !canRestore ? null : _restoreBackup,
              ),
            if (widget.appState.canManageSecurity)
              _SettingsTile(
                key: const ValueKey<String>('backup-health-status'),
                icon: Icons.health_and_safety_outlined,
                title: '自动备份与备份检查',
                status: _backupHealthLabel(),
                onTap: _working || !canRestore ? null : _openVaultHealth,
              ),
            _SettingsTile(
              key: const ValueKey<String>('pending-subscription-drafts-entry'),
              icon: Icons.edit_calendar_outlined,
              title: '待完善订阅',
              status: widget.appState.pendingSubscriptionDrafts.isEmpty
                  ? '当前没有待完善订阅'
                  : context.tr('{count} 条加密草稿等待补全', <String, Object?>{
                      'count': widget.appState.pendingSubscriptionDrafts.length,
                    }),
              onTap: _working || !editable || !widget.appState.canManageSecurity
                  ? null
                  : _openPendingSubscriptionDrafts,
            ),
            if (widget.appState.canUndoLastBatchImport &&
                widget.appState.canManageSecurity)
              _SettingsTile(
                key: const ValueKey<String>('undo-last-batch-import'),
                icon: Icons.undo_rounded,
                title: '撤销最近一次批量导入',
                status: switch (widget.appState.lastBatchRollbackImpact) {
                  final impact? => context.tr(
                    '独立加密回滚 · 将影响 {count} 条记录',
                    <String, Object?>{'count': impact.affectedRecordCount},
                  ),
                  _ => '仅撤销最近一次批量导入，不使用备份恢复副本',
                },
                onTap: _working || !editable ? null : _undoLastBatchImport,
              ),
            if (!_offlineWebsite)
              if (widget.temporaryWebController case final controller?)
                ListenableBuilder(
                  listenable: controller,
                  builder: (context, child) => _SettingsTile(
                    key: const ValueKey<String>('temporary-web-session-entry'),
                    icon: Icons.laptop_chromebook_outlined,
                    title: '电脑临时录入',
                    status: _temporaryWebStatus(controller.snapshot),
                    onTap:
                        _working ||
                            !editable ||
                            !widget.appState.canManageSecurity
                        ? null
                        : _openTemporaryWebSession,
                  ),
                ),
            if (widget.appState.hasRecoveryRollback &&
                widget.appState.canManageSecurity)
              _SettingsTile(
                key: const ValueKey<String>('restore-preimport-rollback'),
                icon: Icons.settings_backup_restore_outlined,
                title: '撤销最近一次备份恢复',
                status: widget.appState.hasUncertainRecoveryTransaction
                    ? '上次恢复结果未确认 · 恢复前加密副本仍在'
                    : '回到恢复 .asmbackup 前的本机记录',
                onTap: _working || !editable ? null : _rollbackLastRestore,
              ),
            if (editable)
              _SettingsTile(
                icon: Icons.delete_outline,
                title: '回收站',
                status: '保留 30 天，可恢复原记录与关联关系',
                onTap: _working
                    ? null
                    : () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          settings: const VaultPageLocation('trash'),
                          builder: (_) => TrashPage(appState: widget.appState),
                        ),
                      ),
              ),
          ],
        ),
        _SettingsGroup(
          title: '产品',
          children: [
            _SettingsTile(
              key: const ValueKey<String>('unlock-full-version-entry'),
              icon: Icons.workspace_premium_outlined,
              title: '解锁完整版',
              status: entitlementController.hasFullVersion
                  ? '已解锁完整版 · 感谢支持'
                  : '免费版 5 订阅 / 15 账户 · 一次购买，永久解锁',
              onTap: () => _openFullVersion(entitlementController),
            ),
            if (widget.appState.canManageSecurity)
              _SettingsTile(
                key: const ValueKey<String>('purchase-credential-entry'),
                icon: Icons.receipt_long_outlined,
                title: '购买凭证',
                status:
                    entitlementController.isReviewAuthorized &&
                        !entitlementController.hasStorePurchase
                    ? '免费审核授权'
                    : entitlementController.isPromoActivated
                    ? '推广激活凭证 · 与购买渠道独立'
                    : entitlementController.hasStorePurchase &&
                          entitlementController.debugOverrideAvailable
                    ? '开发环境模拟状态 · 不是真实付款'
                    : entitlementController.hasStorePurchase
                    ? '当前安装的完整版权益已验证'
                    : '当前未购买',
                onTap: _working
                    ? null
                    : () => _openPurchaseCredential(entitlementController),
              ),
            _SettingsTile(
              key: const ValueKey<String>('about-cardock-entry'),
              icon: Icons.info_outline,
              title: '关于Cardock',
              status: AppMetadata.version,
              translateStatus: false,
              onTap: _openAboutCardock,
            ),
            _SettingsTile(
              key: const ValueKey<String>('developer-note-entry'),
              icon: Icons.edit_note_outlined,
              title: '开发者的话',
              status: '第一款作品 · 关于初心与维护',
              onTap: _openDeveloperNote,
            ),
          ],
        ),
        if (_working) const LinearProgressIndicator(),
      ],
    );
  }

  static String _autoLockLabel(int seconds) => switch (seconds) {
    0 => '离开应用立即锁定',
    30 => '离开应用30秒后锁定',
    60 => '离开应用1分钟后锁定',
    300 => '离开应用5分钟后锁定',
    900 => '离开应用15分钟后锁定',
    _ => '离开应用立即锁定',
  };

  static String _temporaryWebStatus(TemporaryWebSessionSnapshot snapshot) =>
      switch (snapshot.phase) {
        TemporaryWebSessionPhase.starting => '正在开启可信局域网临时服务…',
        TemporaryWebSessionPhase.waitingForPairing => '已开启 · 等待电脑输入一次性连接码',
        TemporaryWebSessionPhase.connected => '电脑网页已连接 · 点击管理或断开',
        TemporaryWebSessionPhase.stopped => '不访问公网/云 · 仅主动开启时监听可信局域网',
      };

  Future<void> _openVaultHealth() => Navigator.push<void>(
    context,
    MaterialPageRoute(
      settings: const VaultPageLocation('vaultHealth'),
      builder: (_) => VaultHealthPage(
        appState: widget.appState,
        onManualBackup: _exportBackup,
        onVerify: () => _restoreBackup(verifyOnly: true),
        onRestore: _restoreBackup,
        onRecovery: () =>
            _configurePasswordRecovery(VaultRecoveryScope.primary),
      ),
    ),
  );

  String _backupHealthLabel() {
    final verified = widget.appState.lastBackupVerifiedAtUtc;
    if (verified != null) {
      return context.tr('最近验证 {time} · 格式 v{version}', <String, Object?>{
        'time': _formatBackupTime(verified),
        'version': widget.appState.lastVerifiedBackupFormatVersion ?? '?',
      });
    }
    final exported = widget.appState.lastBackupExportedAtUtc;
    if (exported != null) {
      return context.tr('最近导出 {time} · 尚未重新读取验证', <String, Object?>{
        'time': _formatBackupTime(exported),
      });
    }
    return '尚无已验证备份 · 点击选择文件做只读检查';
  }
}

final class _RecoverySetupInput {
  const _RecoverySetupInput({
    required this.questionIds,
    required this.answers,
    required this.entryMode,
  });

  final List<String> questionIds;
  final List<String> answers;
  final VaultRecoveryEntryMode entryMode;
}

class _RecoverySetupDialog extends StatefulWidget {
  const _RecoverySetupDialog({
    required this.title,
    this.avoidQuestionIds = const <String>[],
  });

  final String title;
  final List<String> avoidQuestionIds;

  @override
  State<_RecoverySetupDialog> createState() => _RecoverySetupDialogState();
}

class _RecoverySetupDialogState extends State<_RecoverySetupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _answerControllers = List<TextEditingController>.generate(
    3,
    (_) => TextEditingController(),
  );
  final _confirmationControllers = List<TextEditingController>.generate(
    3,
    (_) => TextEditingController(),
  );
  late final List<String> _questionIds;
  VaultRecoveryEntryMode _entryMode = VaultRecoveryEntryMode.visible;
  bool _obscureAnswers = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final avoided = widget.avoidQuestionIds.toSet();
    final preferred = vaultRecoveryQuestionCatalog
        .where((question) => !avoided.contains(question.id))
        .followedBy(
          vaultRecoveryQuestionCatalog.where(
            (question) => avoided.contains(question.id),
          ),
        );
    _questionIds = preferred
        .take(3)
        .map((question) => question.id)
        .toList(growable: false);
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      ..._answerControllers,
      ..._confirmationControllers,
    ]) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    setState(() => _error = null);
    if (_questionIds.toSet().length != 3) {
      setState(() => _error = '三道密保问题不能重复。');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final answers = _answerControllers
        .map((controller) => controller.text)
        .toList(growable: false);
    for (var index = 0; index < 3; index++) {
      if (normalizeVaultRecoveryAnswer(answers[index]) !=
          normalizeVaultRecoveryAnswer(_confirmationControllers[index].text)) {
        setState(
          () => _error = context.tr('第{number}道问题的两次答案不一致。', <String, Object?>{
            'number': index + 1,
          }),
        );
        return;
      }
    }
    Navigator.of(context).pop(
      _RecoverySetupInput(
        questionIds: List<String>.unmodifiable(_questionIds),
        answers: List<String>.unmodifiable(answers),
        entryMode: _entryMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr(widget.title), translate: false),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '恢复不会显示旧密码。每次恢复都必须同时答对三题，并通过本机指纹或安全级人脸。请使用只有你知道且长期稳定的答案；两套保险库的三道问题组合不能完全相同。',
                ),
                const SizedBox(height: 16),
                for (var index = 0; index < 3; index++) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>('recovery-question-$index'),
                    initialValue: _questionIds[index],
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.tr('密保问题 {number}', <String, Object?>{
                        'number': index + 1,
                      }),
                    ),
                    items: [
                      for (final question in vaultRecoveryQuestionCatalog)
                        DropdownMenuItem<String>(
                          value: question.id,
                          child: Text(
                            context.tr(question.label),
                            translate: false,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _questionIds[index] = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: ValueKey<String>('recovery-setup-answer-$index'),
                    controller: _answerControllers[index],
                    obscureText: _obscureAnswers,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    maxLength: 256,
                    decoration: InputDecoration(
                      labelText: context.tr('答案'),
                      counterText: '',
                    ),
                    validator: (value) =>
                        normalizeVaultRecoveryAnswer(value ?? '').isEmpty
                        ? context.tr('答案不能为空')
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: ValueKey<String>('recovery-setup-confirm-$index'),
                    controller: _confirmationControllers[index],
                    obscureText: _obscureAnswers,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    maxLength: 256,
                    decoration: InputDecoration(
                      labelText: context.tr('再次输入答案'),
                      counterText: '',
                    ),
                    validator: (value) =>
                        normalizeVaultRecoveryAnswer(value ?? '').isEmpty
                        ? context.tr('请再次输入答案')
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _obscureAnswers = !_obscureAnswers),
                  icon: Icon(
                    _obscureAnswers
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  label: Text(_obscureAnswers ? '显示答案' : '隐藏答案'),
                ),
                const SizedBox(height: 8),
                Text('锁屏入口', style: Theme.of(context).textTheme.titleSmall),
                RadioGroup<VaultRecoveryEntryMode>(
                  groupValue: _entryMode,
                  onChanged: (value) {
                    if (value != null) setState(() => _entryMode = value);
                  },
                  child: const Column(
                    children: [
                      RadioListTile<VaultRecoveryEntryMode>(
                        key: ValueKey<String>('recovery-entry-visible'),
                        value: VaultRecoveryEntryMode.visible,
                        title: Text('直接显示“忘记密码？恢复保险库访问”'),
                        subtitle: Text('更容易找到，默认推荐'),
                      ),
                      RadioListTile<VaultRecoveryEntryMode>(
                        key: ValueKey<String>('recovery-entry-logo-five-tap'),
                        value: VaultRecoveryEntryMode.logoFiveTap,
                        title: Text('3秒内连续点 Logo 5次'),
                        subtitle: Text('只是降低入口可见度，不增加安全性；辅助功能用户建议直接显示'),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    key: const ValueKey<String>('recovery-setup-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey<String>('confirm-recovery-setup'),
          onPressed: _submit,
          child: const Text('系统认证并启用'),
        ),
      ],
    );
  }
}

class _PasswordPromptDialog extends StatefulWidget {
  const _PasswordPromptDialog({
    required this.title,
    required this.message,
    required this.label,
  });

  final String title;
  final String message;
  final String label;

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr(widget.title), translate: false),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(context.tr(widget.message), translate: false),
        const SizedBox(height: 16),
        TextField(
          autofocus: true,
          controller: _controller,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          decoration: InputDecoration(
            labelText: context.tr(widget.label),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
            ),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => _controller.text.isEmpty
            ? null
            : Navigator.pop(context, _controller.text),
        child: const Text('继续'),
      ),
    ],
  );
}

class _NewPasswordPromptDialog extends StatefulWidget {
  const _NewPasswordPromptDialog({
    required this.title,
    required this.message,
    required this.label,
    required this.purpose,
    required this.sensitiveClipboard,
  });

  final String title;
  final String message;
  final String label;
  final NewPasswordPurpose purpose;
  final SensitiveClipboard sensitiveClipboard;

  @override
  State<_NewPasswordPromptDialog> createState() =>
      _NewPasswordPromptDialogState();
}

class _NewPasswordPromptDialogState extends State<_NewPasswordPromptDialog> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _obscure = true;
  String? _error;
  String? _guidance;

  PasswordAssessment get _assessment => OfflinePasswordAdvisor.assess(
    _passwordController.text,
    purpose: widget.purpose,
  );

  bool get _canSubmit =>
      _passwordController.text.isNotEmpty &&
      _assessment.accepted &&
      _passwordController.text == _confirmationController.text;

  int get _maxLength => switch (widget.purpose) {
    NewPasswordPurpose.critical => 128,
    NewPasswordPurpose.decoy => 32,
  };

  String get _requirements => switch (widget.purpose) {
    NewPasswordPurpose.critical =>
      '设置要求：16–128个字符。自定义密码建议同时包含大写字母、小写字母、数字和符号；也可以使用本机离线生成的高强度随机密码。',
    NewPasswordPurpose.decoy =>
      '设置要求：6–32个字符。请选择容易记住、但与真实主密码完全不同的故事密码；诱饵密码不用于保护真实账号。',
  };

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_refreshInputState);
    _confirmationController.addListener(_refreshInputState);
  }

  void _refreshInputState() {
    if (!mounted) return;
    setState(() {
      _error = null;
      if (_guidance != null && !_guidance!.startsWith('已在本机离线生成')) {
        _guidance = null;
      }
    });
  }

  @override
  void dispose() {
    _passwordController.removeListener(_refreshInputState);
    _confirmationController.removeListener(_refreshInputState);
    _passwordController.clear();
    _confirmationController.clear();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _generate() {
    final generated = OfflinePasswordAdvisor.generate();
    setState(() {
      _passwordController.text = generated;
      _confirmationController.text = generated;
      _obscure = false;
      _error = null;
      _guidance = '已在本机离线生成。请立即离线保存并核对；应用不会保存或找回这个密码。';
    });
  }

  Future<void> _copy() async {
    final password = _passwordController.text;
    if (password.isEmpty) return;
    try {
      await widget.sensitiveClipboard.copySensitive(
        text: password,
        label: context.tr(widget.label),
        clearAfter: const Duration(seconds: 60),
      );
      if (!mounted) return;
      setState(() {
        _error = null;
        _guidance = '已复制，应用会在60秒后尽力清除；请留意键盘或厂商剪贴板历史。';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _guidance = null;
        _error = '复制失败，未写入剪贴板。';
      });
    }
  }

  void _submit() {
    final password = _passwordController.text;
    final assessment = OfflinePasswordAdvisor.assess(
      password,
      purpose: widget.purpose,
    );
    if (!assessment.accepted) {
      setState(() => _error = assessment.message);
      return;
    }
    if (password != _confirmationController.text) {
      setState(() => _error = '两次输入的密码不一致。');
      return;
    }
    Navigator.pop(context, password);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr(widget.title), translate: false),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.tr(widget.message), translate: false),
          const SizedBox(height: 12),
          Text(
            context.tr(_requirements),
            translate: false,
            key: const ValueKey<String>('new-password-requirements'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            maxLength: _maxLength,
            decoration: InputDecoration(
              labelText: context.tr(widget.label),
              counterText: '',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmationController,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            maxLength: _maxLength,
            decoration: InputDecoration(
              labelText: context.tr('再次输入确认'),
              counterText: '',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          if (widget.purpose == NewPasswordPurpose.critical)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey<String>('generate-new-secret-offline'),
                  onPressed: _generate,
                  icon: const Icon(Icons.casino_outlined),
                  label: const Text('离线生成高强度密码'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey<String>('copy-new-secret-safely'),
                  onPressed: _passwordController.text.isEmpty ? null : _copy,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('复制（60秒后尽力清理）'),
                ),
              ],
            ),
          if (_passwordController.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              context.tr(_assessment.message),
              translate: false,
              key: const ValueKey<String>('new-password-live-assessment'),
              style: TextStyle(
                color: _assessment.accepted
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          if (_guidance != null) ...[
            const SizedBox(height: 8),
            Text(
              context.tr(_guidance!),
              translate: false,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              context.tr(_error!),
              translate: false,
              key: const ValueKey<String>('new-password-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _canSubmit ? _submit : null,
        child: const Text('确认'),
      ),
    ],
  );
}

String _themeFamilyName(CardockThemeFamily family) => family.label;

String _desktopIconDescription(CardockLauncherFamily family) =>
    switch (family) {
      CardockLauncherFamily.ceramicBlue => '瓷蓝与暖黄',
      CardockLauncherFamily.sakuraMist => '樱粉与丁香',
      CardockLauncherFamily.paperArchive => '烧橙、橄榄与油墨',
      CardockLauncherFamily.lilacMoon => '丁香与烟紫',
      CardockLauncherFamily.glacierBlue => '冰蓝与青色',
      CardockLauncherFamily.mistCoral => '薄荷与珊瑚',
      CardockLauncherFamily.neonZero => '荧光绿与黑',
      CardockLauncherFamily.obsidianGold => '黑曜与鎏金',
    };

String _launcherFamilyName(CardockLauncherFamily family) => family.label;

class _AppearanceSettingsPage extends StatefulWidget {
  const _AppearanceSettingsPage({
    required this.controller,
    required this.accountCount,
    required this.subscriptionCount,
    required this.renewalsWithinThirtyDays,
  });

  final CardockAppearanceController controller;
  final int accountCount;
  final int subscriptionCount;
  final int renewalsWithinThirtyDays;

  @override
  State<_AppearanceSettingsPage> createState() =>
      _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<_AppearanceSettingsPage> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    VaultNavigationScope.maybeOf(context)?.handlers['customTheme'] = (_) =>
        _openCustomEditor();
  }

  bool _working = false;
  late CardockThemeFamily _previewFamily;

  @override
  void initState() {
    super.initState();
    _previewFamily = widget.controller.family;
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr(text))));
  }

  Future<void> _setBrightness(CardockBrightnessMode mode) async {
    if (_working || widget.controller.brightnessMode == mode) return;
    setState(() => _working = true);
    try {
      await widget.controller.setBrightnessMode(mode);
    } on Object {
      _message('外观模式保存失败，已恢复之前的设置。');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _setTheme(CardockThemeFamily family) {
    if (_working || _previewFamily == family) return;
    setState(() => _previewFamily = family);
  }

  Future<void> _applyTheme() async {
    if (_working || widget.controller.family == _previewFamily) return;
    final entitlement = ProductEntitlementScope.of(context).value;
    const guard = EntitlementGuard();
    if (!guard.canUseTheme(entitlement: entitlement, family: _previewFamily)) {
      await showFullVersionUpsell(
        context,
        scene: FullVersionUpsellScene.premiumTheme,
      );
      return;
    }
    setState(() => _working = true);
    try {
      await widget.controller.setFamily(_previewFamily);
      _message('主题已应用。');
    } on Object {
      _message('主题保存失败，已恢复之前的设置。');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _setDesktopIconMode(CardockDesktopIconMode mode) async {
    if (_working) return;
    final fixed = mode.fixedFamily;
    if (fixed != null &&
        !const EntitlementGuard().canUseLauncher(
          entitlement: ProductEntitlementScope.of(context).value,
          family: fixed,
        )) {
      await showFullVersionUpsell(
        context,
        scene: FullVersionUpsellScene.premiumTheme,
      );
      return;
    }
    final shouldApplyPreview =
        mode == CardockDesktopIconMode.followTheme &&
        widget.controller.family != _previewFamily;
    if (shouldApplyPreview) {
      final entitlement = ProductEntitlementScope.of(context).value;
      const guard = EntitlementGuard();
      if (!guard.canUseTheme(
        entitlement: entitlement,
        family: _previewFamily,
      )) {
        await showFullVersionUpsell(
          context,
          scene: FullVersionUpsellScene.premiumTheme,
        );
        return;
      }
    }
    setState(() => _working = true);
    try {
      if (shouldApplyPreview) {
        await widget.controller.setFamilyAndFollowDesktopIcon(_previewFamily);
      } else {
        await widget.controller.setDesktopIconMode(mode);
      }
      _message('桌面图标将在几秒内更新');
    } on Object {
      _message('桌面图标切换失败，已恢复之前的设置。');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _openCustomEditor() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const VaultPageLocation('customTheme'),
        builder: (context) => CustomThemeEditorPage(
          controller: widget.controller,
          accountCount: widget.accountCount,
          subscriptionCount: widget.subscriptionCount,
          renewalsWithinThirtyDays: widget.renewalsWithinThirtyDays,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('外观与桌面图标')),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, child) {
          final preferences = widget.controller.preferences;
          return ListView(
            key: const ValueKey<String>('appearance-settings-page'),
            padding: const EdgeInsets.fromLTRB(
              CardockLayout.screenHorizontal,
              8,
              CardockLayout.screenHorizontal,
              32,
            ),
            children: [
              _AppearancePreview(
                family: _previewFamily,
                customTheme: preferences.customTheme,
                renewalsWithinThirtyDays: widget.renewalsWithinThirtyDays,
              ),
              const SizedBox(height: 22),
              Text('外观模式', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final scaledLabelHeight = MediaQuery.textScalerOf(
                    context,
                  ).scale(14);
                  final useVerticalSegments =
                      constraints.maxWidth < 330 || scaledLabelHeight >= 21;
                  return SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<CardockBrightnessMode>(
                      key: const ValueKey<String>('appearance-brightness-mode'),
                      direction: useVerticalSegments
                          ? Axis.vertical
                          : Axis.horizontal,
                      segments: [
                        for (final mode in CardockBrightnessMode.values)
                          ButtonSegment<CardockBrightnessMode>(
                            value: mode,
                            label: Text(
                              mode.label,
                              key: ValueKey<String>(
                                'appearance-brightness-${mode.name}',
                              ),
                            ),
                          ),
                      ],
                      selected: <CardockBrightnessMode>{
                        preferences.brightnessMode,
                      },
                      showSelectedIcon: false,
                      onSelectionChanged: _working
                          ? null
                          : (selection) {
                              if (selection.isNotEmpty) {
                                _setBrightness(selection.first);
                              }
                            },
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              _AppearanceSectionHeading(
                title: '主题',
                subtitle: '应用内品牌标志自动跟随主题。',
              ),
              const SizedBox(height: 10),
              _AppearanceChoiceGrid(
                selected: _previewFamily,
                customTheme: preferences.customTheme,
                disabled: _working,
                entitlement: ProductEntitlementScope.of(context).value,
                onSelected: _setTheme,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey<String>('appearance-apply-theme'),
                onPressed:
                    _working || widget.controller.family == _previewFamily
                    ? null
                    : _applyTheme,
                icon: const Icon(Icons.check_rounded),
                label: const Text('应用主题'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey<String>('appearance-edit-custom-theme'),
                onPressed: _working ? null : _openCustomEditor,
                icon: const Icon(Icons.palette_outlined),
                label: const Text('编辑自定义配色'),
              ),
              const SizedBox(height: 24),
              _AppearanceSectionHeading(
                title: '桌面图标颜色',
                subtitle:
                    preferences.desktopIconMode ==
                        CardockDesktopIconMode.followTheme
                    ? context.tr('跟随主题 · 当前 {family}', <String, Object?>{
                        'family': context.tr(
                          preferences.resolvedLauncherFamily.label,
                        ),
                      })
                    : context.tr('固定为 {family}', <String, Object?>{
                        'family': context.tr(
                          preferences.resolvedLauncherFamily.label,
                        ),
                      }),
              ),
              const SizedBox(height: 10),
              Card(
                child: SwitchListTile.adaptive(
                  key: const ValueKey<String>(
                    'appearance-desktop-icon-follow-theme',
                  ),
                  value:
                      preferences.desktopIconMode ==
                      CardockDesktopIconMode.followTheme,
                  onChanged: _working
                      ? null
                      : (enabled) => _setDesktopIconMode(
                          enabled
                              ? CardockDesktopIconMode.followTheme
                              : cardockDesktopIconModeFor(
                                  preferences.resolvedLauncherFamily,
                                ),
                        ),
                  title: const Text('跟随主题'),
                  subtitle: Text(
                    preferences.family == CardockThemeFamily.custom
                        ? '自定义主题使用已选的固定图标回退'
                        : '八套固定主题各自使用对应颜色的桌面图标',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _DesktopIconChoiceGrid(
                selected: preferences.desktopIconMode,
                disabled: _working,
                onSelected: _setDesktopIconMode,
              ),
              const SizedBox(height: 12),
              const _DesktopIconNotice(),
              if (_working) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AppearancePreview extends StatelessWidget {
  const _AppearancePreview({
    required this.family,
    required this.customTheme,
    required this.renewalsWithinThirtyDays,
  });

  final CardockThemeFamily family;
  final CardockCustomTheme customTheme;
  final int renewalsWithinThirtyDays;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final spec = CardockTokens.spec(
      family,
      brightness,
      customTheme: customTheme,
    );
    final palette = spec.palette;
    final materialProfile = spec.material;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final useCompactSpacing = constraints.maxWidth / textScale < 300;
        return Container(
          key: const ValueKey<String>('appearance-live-preview'),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: palette.overviewGradient,
            borderRadius: BorderRadius.circular(CardockRadius.largeCard),
            boxShadow: materialProfile.heroShadows
                .map((layer) => layer.toBoxShadow())
                .toList(growable: false),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -18,
                bottom: -38,
                child: Opacity(
                  opacity: materialProfile.heroWatermarkOpacity,
                  child: CardockBrandSymbol(
                    family: family,
                    brightness: brightness,
                    customColors: customTheme.colorsFor(brightness),
                    size: 150,
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CardockBrandSymbol(
                        family: family,
                        brightness: brightness,
                        customColors: customTheme.colorsFor(brightness),
                        size: 28,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Cardock',
                          translate: false,
                          style: TextStyle(
                            color: palette.gradientContent,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: useCompactSpacing ? 14 : 24),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: palette.gradientContent.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(
                        CardockRadius.control,
                      ),
                      border: Border.all(
                        color: palette.gradientContent.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      context.tr('{count} 项 · 未来30天待续费', <String, Object?>{
                        'count': renewalsWithinThirtyDays,
                      }),
                      translate: false,
                      style: TextStyle(
                        color: palette.gradientContent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AppearanceSectionHeading extends StatelessWidget {
  const _AppearanceSectionHeading({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr(title),
          translate: false,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 3),
        Text(
          context.tr(subtitle),
          translate: false,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _AppearanceChoiceGrid extends StatelessWidget {
  const _AppearanceChoiceGrid({
    required this.selected,
    required this.customTheme,
    required this.disabled,
    required this.entitlement,
    required this.onSelected,
  });

  final CardockThemeFamily selected;
  final CardockCustomTheme customTheme;
  final bool disabled;
  final ProductEntitlement entitlement;
  final ValueChanged<CardockThemeFamily> onSelected;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return LayoutBuilder(
      builder: (context, constraints) {
        final useColumns = constraints.maxWidth >= 300 && textScale < 1.5;
        final itemWidth = useColumns
            ? (constraints.maxWidth - 8) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 8,
          runSpacing: 10,
          children: [
            for (final family in cardockSelectableThemeFamilies)
              SizedBox(
                width: itemWidth,
                child: _AppearanceChoiceCard(
                  key: ValueKey<String>('appearance-theme-${family.name}'),
                  family: family,
                  customTheme: customTheme,
                  selected: selected == family,
                  locked: const EntitlementGuard().isThemeLocked(
                    entitlement: entitlement,
                    family: family,
                  ),
                  onTap: disabled ? null : () => onSelected(family),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AppearanceChoiceCard extends StatelessWidget {
  const _AppearanceChoiceCard({
    required this.family,
    required this.customTheme,
    required this.selected,
    required this.locked,
    required this.onTap,
    super.key,
  });

  final CardockThemeFamily family;
  final CardockCustomTheme customTheme;
  final bool selected;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final spec = CardockTokens.spec(
      family,
      brightness,
      customTheme: customTheme,
    );
    final palette = spec.palette;
    final materialProfile = spec.material;
    final currentPalette = context.cardockTheme.palette;
    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: context.tr(
        locked ? '主题，{theme}，完整版专属' : '主题，{theme}',
        <String, Object?>{'theme': context.tr(_themeFamilyName(family))},
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CardockRadius.largeCard),
          child: Ink(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: currentPalette.surface,
              borderRadius: BorderRadius.circular(CardockRadius.largeCard),
              border: Border.all(
                color: selected
                    ? currentPalette.primary
                    : currentPalette.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 78,
                      width: double.infinity,
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: palette.background,
                        borderRadius: BorderRadius.circular(
                          CardockRadius.control,
                        ),
                        border: Border.all(
                          color: palette.border,
                          width: materialProfile.cardBorderWidth,
                        ),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: palette.overviewGradient,
                                borderRadius: BorderRadius.circular(
                                  CardockRadius.small,
                                ),
                              ),
                              child: CardockBrandSymbol(
                                family: family,
                                brightness: brightness,
                                customColors: customTheme.colorsFor(brightness),
                                size: 30,
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: palette.surface,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: palette.border,
                                      width: materialProfile.cardBorderWidth,
                                    ),
                                    boxShadow: materialProfile.cardShadows
                                        .take(1)
                                        .map((layer) => layer.toBoxShadow())
                                        .toList(growable: false),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              _ThemeColorDot(color: palette.primary),
                              const SizedBox(width: 4),
                              _ThemeColorDot(
                                color: palette.brandSecondaryDecorative,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      _themeFamilyName(family),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      family.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                if (selected)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 22,
                      color: currentPalette.primary,
                    ),
                  ),
                if (locked)
                  Positioned(
                    right: selected ? 26 : 0,
                    top: 0,
                    child: Icon(
                      Icons.lock_rounded,
                      key: ValueKey<String>(
                        'appearance-theme-lock-${family.name}',
                      ),
                      size: 21,
                      color: currentPalette.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeColorDot extends StatelessWidget {
  const _ThemeColorDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(
        color: context.cardockTheme.palette.border,
        width: 0.7,
      ),
    ),
  );
}

class _DesktopIconChoiceGrid extends StatelessWidget {
  const _DesktopIconChoiceGrid({
    required this.selected,
    required this.disabled,
    required this.onSelected,
  });

  final CardockDesktopIconMode selected;
  final bool disabled;
  final ValueChanged<CardockDesktopIconMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return LayoutBuilder(
      builder: (context, constraints) {
        final useColumns = constraints.maxWidth >= 300 && textScale < 1.5;
        final itemWidth = useColumns
            ? (constraints.maxWidth - 8) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 8,
          runSpacing: 10,
          children: [
            for (final family in cardockLauncherFamilies)
              SizedBox(
                width: itemWidth,
                child: _DesktopIconChoiceCard(
                  key: ValueKey<String>(
                    'appearance-desktop-icon-${family.name}',
                  ),
                  family: family,
                  locked: !const EntitlementGuard().canUseLauncher(
                    entitlement: ProductEntitlementScope.of(context).value,
                    family: family,
                  ),
                  selected: selected == cardockDesktopIconModeFor(family),
                  onTap: disabled
                      ? null
                      : () => onSelected(cardockDesktopIconModeFor(family)),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DesktopIconChoiceCard extends StatelessWidget {
  const _DesktopIconChoiceCard({
    required this.family,
    required this.selected,
    required this.locked,
    required this.onTap,
    super.key,
  });

  final CardockLauncherFamily family;
  final bool selected;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: context.tr('桌面图标颜色，{family}', <String, Object?>{
        'family': context.tr(family.label),
      }),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CardockRadius.largeCard),
          child: Ink(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(CardockRadius.largeCard),
              border: Border.all(
                color: selected ? palette.primary : palette.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          family.launcherAssetName,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      _launcherFamilyName(family),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _desktopIconDescription(family),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                if (locked)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Icon(
                      Icons.lock_outline,
                      key: ValueKey('appearance-icon-lock-${family.name}'),
                      size: 22,
                      color: palette.textSecondary,
                    ),
                  ),
                if (selected && !locked)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 22,
                      color: palette.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopIconNotice extends StatelessWidget {
  const _DesktopIconNotice();

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.primarySoft,
        borderRadius: BorderRadius.circular(CardockRadius.control),
        border: Border.all(color: palette.primary.withValues(alpha: 0.28)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: context.tr('真实替换手机桌面图标。'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: context.tr(
                '免费版使用橙墨旧刊，其他桌面图标随完整版解锁。系统桌面可能需要几秒刷新；应用内 LOGO 跟随主题。',
              ),
            ),
          ],
        ),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
      ),
    );
  }
}

class _VaultSummary extends StatelessWidget {
  const _VaultSummary({
    required this.quickUnlockEnabled,
    required this.autoLockLabel,
    required this.decoyConfigured,
  });

  final bool quickUnlockEnabled;
  final String autoLockLabel;
  final bool? decoyConfigured;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final configuredDecoy = decoyConfigured;
    final statuses = <({String label, String value, bool active})>[
      (label: '主密码', value: '已设置', active: true),
      (
        label: '生物识别',
        value: quickUnlockEnabled ? '已开启' : '未开启',
        active: quickUnlockEnabled,
      ),
      (
        label: '自动锁定',
        value: autoLockLabel.replaceFirst('离开应用', ''),
        active: true,
      ),
      if (configuredDecoy != null)
        (
          label: '诱饵保险库',
          value: configuredDecoy ? '已配置' : '未配置',
          active: configuredDecoy,
        ),
    ];
    final header = Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: palette.primarySoft,
            borderRadius: BorderRadius.circular(CardockRadius.control),
          ),
          child: Icon(Icons.shield_outlined, color: palette.primary, size: 20),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '本地保险库',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
    final statusGrid = Column(
      key: const ValueKey<String>('vault-status-grid'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < statuses.length; index += 2) ...[
          if (index > 0) const SizedBox(height: 4),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _VaultStatusTile(
                    key: ValueKey<String>(
                      'vault-status-${statuses[index].label}',
                    ),
                    label: context.tr(statuses[index].label),
                    value: context.tr(statuses[index].value),
                    active: statuses[index].active,
                  ),
                ),
                const SizedBox(width: 5),
                if (index + 1 < statuses.length)
                  Expanded(
                    child: _VaultStatusTile(
                      key: ValueKey<String>(
                        'vault-status-${statuses[index + 1].label}',
                      ),
                      label: context.tr(statuses[index + 1].label),
                      value: context.tr(statuses[index + 1].value),
                      active: statuses[index + 1].active,
                    ),
                  )
                else
                  const Spacer(),
              ],
            ),
          ),
        ],
      ],
    );
    return Semantics(
      container: true,
      label: statuses
          .map(
            (item) => context.tr('{label}: {value}', <String, Object?>{
              'label': context.tr(item.label),
              'value': context.tr(item.value),
            }),
          )
          .join(context.tr('，')),
      child: Container(
        key: const ValueKey<String>('vault-summary'),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.surface,
              palette.primarySoft.withValues(alpha: 0.46),
            ],
          ),
          borderRadius: BorderRadius.circular(CardockRadius.card),
          border: Border.all(
            color: palette.border,
            width: context.cardockTheme.material.cardBorderWidth,
          ),
          boxShadow: context.cardockTheme.material.cardShadows
              .map((layer) => layer.toBoxShadow())
              .toList(growable: false),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useSideHeader =
                constraints.maxWidth >= 300 && textScale <= 1.5;
            if (!useSideHeader) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [header, const SizedBox(height: 8), statusGrid],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 108, child: header),
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 7),
                    color: palette.divider,
                  ),
                  Expanded(child: statusGrid),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VaultStatusTile extends StatelessWidget {
  const _VaultStatusTile({
    super.key,
    required this.label,
    required this.value,
    required this.active,
  });

  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final statusColor = active ? palette.statusNormal : palette.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: active ? 0.09 : 0.055),
        borderRadius: BorderRadius.circular(CardockRadius.control),
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    translate: false,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: palette.textTertiary,
                      fontSize: 9.5,
                      height: 1.18,
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    translate: false,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 10.5,
                      height: 1.18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalOnlyNotice extends StatefulWidget {
  const _LocalOnlyNotice();

  @override
  State<_LocalOnlyNotice> createState() => _LocalOnlyNoticeState();
}

class _LocalOnlyNoticeState extends State<_LocalOnlyNotice> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey<String>('local-only-notice'),
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(CardockRadius.control),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: palette.statusNormal.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(CardockRadius.control),
            border: Border.all(
              color: palette.statusNormal.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 17,
                color: palette.statusNormal,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (const String.fromEnvironment('CARDOCK_DISTRIBUTION') ==
                              'website' ||
                          CardockDistributionConfig.channel ==
                              CardockDistributionChannel.website)
                      ? (_expanded
                            ? 'Cardock本身完全离线；购买、订单查询与恢复由外部浏览器联网完成。'
                            : '完全离线 · APP 不访问互联网或局域网')
                      : _expanded
                      ? '本地优先 · 业务数据不访问公网或云；只有主动开启电脑临时录入时才监听可信局域网，断开即停止。'
                      : '本地优先 · 业务数据不访问公网或云端',
                  maxLines: _expanded ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.chevron_right_rounded,
                size: 18,
                color: palette.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoercionWarning extends StatelessWidget {
  const _CoercionWarning();

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return Container(
      key: const ValueKey<String>('full-biometric-coercion-warning'),
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.statusRenewSoon.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CardockRadius.control),
        border: Border.all(
          color: palette.statusRenewSoon.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_outlined,
            size: 18,
            color: palette.statusRenewSoon,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '完整生物识别存在胁迫风险：他人若能强迫你通过系统验证，可能看到真实账号；诱饵密码需先输入才会停用生物识别。',
              style: TextStyle(fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 1, bottom: 7),
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: children.length * 57.0,
                decoration: BoxDecoration(
                  color: palette.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    listTileTheme: const ListTileThemeData(
                      dense: true,
                      minVerticalPadding: 3,
                      contentPadding: EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ),
                  child: Column(
                    children: [
                      for (var index = 0; index < children.length; index++) ...[
                        children[index],
                        if (index < children.length - 1)
                          Divider(height: 1, color: palette.divider),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.status,
    this.translateStatus = true,
    this.statusMaxLines = 2,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String status;
  final bool translateStatus;
  final int statusMaxLines;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return ListTile(
      minTileHeight: 57,
      enabled: onTap != null,
      onTap: onTap,
      leading: Container(
        width: 31,
        height: 31,
        decoration: BoxDecoration(
          color: _semanticColor(context).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: _semanticColor(context)),
      ),
      title: Text(
        context.tr(title),
        translate: false,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        translateStatus ? context.tr(status) : status,
        translate: false,
        maxLines: statusMaxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: palette.textTertiary, fontSize: 9.5),
      ),
      trailing: onTap == null
          ? null
          : const Icon(Icons.chevron_right_rounded, size: 18),
    );
  }

  Color _semanticColor(BuildContext context) {
    final palette = context.cardockTheme.palette;
    if (icon == Icons.password_outlined ||
        icon == Icons.lock_clock_outlined ||
        icon == Icons.lock_outline) {
      return palette.fieldPassword;
    }
    if (icon == Icons.notifications_none ||
        icon == Icons.notification_add_outlined ||
        icon == Icons.event_repeat_outlined) {
      return palette.fieldSubscription;
    }
    if (icon == Icons.backup_outlined ||
        icon == Icons.restore_outlined ||
        icon == Icons.settings_backup_restore_outlined ||
        icon == Icons.health_and_safety_outlined) {
      return palette.fieldEmail;
    }
    if (icon == Icons.payments_outlined) return palette.fieldPhone;
    if (icon == Icons.computer_outlined) return palette.fieldUrl;
    if (icon == Icons.theater_comedy_outlined) {
      return palette.statusPaused;
    }
    return Theme.of(context).colorScheme.primary;
  }
}
