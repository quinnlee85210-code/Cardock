import '../../../app/app_state.dart';
import '../../../core/security/offline_password_advisor.dart';
import '../../../core/app_metadata.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import 'data_safety_dialogs.dart';
import 'readable_export_page.dart';
import 'trash_page.dart';

String backupFailureLabel(String? code) => switch (code) {
  'invalid_password' => '备份密码不符合要求，请使用16–128个字符并避免常见口令。',
  'config_write_failed' => '备份已验证，但本机自动备份设置保存失败，请重试。',
  'write_failed' => '备份文件写入失败，旧有效备份已保留。',
  'encryption_failed' => '备份加密未完成，旧有效备份已保留。',
  'permission_revoked' => '目录权限失效，请重新选择目录。',
  'directory_missing' => '备份目录或文件不存在。',
  'storage_full' => '保存位置空间不足。',
  'provider_refused' => '文件提供方拒绝操作。',
  'read_failed' => '文件写入后无法重新读取。',
  'verification_failed' => '文件完整解密验证失败，旧有效备份已保留。',
  'config_unreadable' => '设备备份配置无法解密或版本不受支持，自动备份已停用。',
  'cleanup_failed' => '新备份已验证，但旧文件删除失败；将自动重试清理。',
  'interrupted' => '写入中断，旧有效备份已保留。',
  _ => '备份未完成，请检查保存位置后重试。',
};

class VaultHealthPage extends StatefulWidget {
  const VaultHealthPage({
    required this.appState,
    required this.onManualBackup,
    required this.onVerify,
    required this.onRestore,
    required this.onRecovery,
    super.key,
  });
  final AppState appState;
  final Future<void> Function() onManualBackup, onVerify, onRestore, onRecovery;
  @override
  State<VaultHealthPage> createState() => _VaultHealthPageState();
}

class _VaultHealthPageState extends State<VaultHealthPage> {
  bool working = false;
  int intervalDays = 15;
  int _intervalRevision = 0;
  @override
  void initState() {
    super.initState();
    intervalDays = widget.appState.autoBackup.status.intervalDays;
    widget.appState.autoBackup.refreshPermission();
  }

  String date(DateTime? value) => value == null
      ? context.tr('尚无记录')
      : value.toLocal().toIso8601String().split('.').first;
  Future<void> setup() async {
    if (working) return;
    String? tree;
    widget.appState.beginExternalInteraction();
    try {
      tree = await widget.appState.autoBackup.storage.pickDirectory();
    } on Object {
      if (mounted) message('无法取得目录授权。');
    } finally {
      widget.appState.endExternalInteraction();
    }
    if (tree == null || !mounted) return;
    final password = await safetyInput(
      context,
      '自动备份独立密码',
      validator: (value) {
        final assessment = OfflinePasswordAdvisor.assess(value);
        return assessment.accepted ? null : assessment.message;
      },
      allowVisibilityToggle: true,
      message: '密码仅由本机真实保险库加密保护，不进入备份文件。忘记密码无法恢复旧文件；更换密码只影响以后生成的备份。',
    );
    if (password == null || !mounted) return;
    final confirmation = await safetyInput(
      context,
      '再次输入备份密码',
      allowVisibilityToggle: true,
    );
    if (confirmation == null || !mounted) return;
    if (password != confirmation) {
      message('两次备份密码不一致。');
      return;
    }
    final master = await safetyInput(context, '当前保险库密码');
    if (master == null || !mounted) return;
    setState(() => working = true);
    final ok = await widget.appState.configureAutoBackup(
      tree: tree,
      backupPassword: password,
      confirmation: confirmation,
      currentPassword: master,
      intervalDays: intervalDays,
    );
    if (!mounted) return;
    setState(() => working = false);
    message(
      ok
          ? '首份备份已重新读取并完整验证，自动备份已启用。'
          : widget.appState.errorMessage ??
                backupFailureLabel(
                  widget.appState.autoBackup.status.failureCode,
                ),
    );
  }

  Future<void> changeInterval(int days) async {
    if (!widget.appState.autoBackup.status.enabled) {
      setState(() => intervalDays = days);
      return;
    }
    setState(() => working = true);
    final ok = await widget.appState.autoBackup.updateInterval(days);
    if (!mounted) return;
    setState(() {
      working = false;
      _intervalRevision++;
      if (ok) intervalDays = days;
    });
    message(ok ? '备份周期已保存。' : '备份周期保存失败，原设置保持不变。');
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void open(Widget page) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.appState,
    builder: (context, _) {
      final app = widget.appState, status = app.autoBackup.status;
      final allowed =
          app.isUnlocked && app.hasFullVaultAccess && app.canManageSecurity;
      final busy = working || status.busy || app.isBusy;
      final lastManual = app.lastBackupExportedAtUtc,
          lastAuto = status.lastWritten;
      final latestAuto =
          lastAuto != null &&
          (lastManual == null || lastAuto.isAfter(lastManual));
      final expiry = [
        ...app.trashAccounts.map((e) => e.expiresAtUtc),
        ...app.trashSubscriptions.map((e) => e.expiresAtUtc),
      ]..sort();
      Widget tile(
        String title,
        String subtitle, {
        VoidCallback? action,
        IconData icon = Icons.info_outline,
      }) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: busy ? null : action,
      );
      return Scaffold(
        appBar: AppBar(title: const Text('数据安全与备份')),
        body: !allowed
            ? const Center(child: Text('请完整解锁真实保险库。'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  tile(
                    '最近加密备份',
                    '${context.tr(latestAuto ? '自动备份' : '手动备份')} · ${date(latestAuto ? lastAuto : lastManual)}',
                  ),
                  tile(
                    '最近完整验证',
                    date(
                      [
                        app.lastBackupVerifiedAtUtc,
                        status.lastVerified,
                      ].whereType<DateTime>().fold<DateTime?>(
                        null,
                        (a, b) => a == null || b.isAfter(a) ? b : a,
                      ),
                    ),
                  ),
                  tile(
                    '自动备份',
                    context.tr(status.enabled ? '已启用，仅完整解锁真实库时工作' : '未启用'),
                  ),
                  tile(
                    '目录授权',
                    context.tr(
                      status.permission == true
                          ? '授权有效'
                          : status.permission == false
                          ? '目录权限失效'
                          : '未选择或待检查',
                    ),
                  ),
                  tile(
                    '已验证且仍存在的自动备份',
                    context.tr('{count} 份 · 保留 {keep} 份', {
                      'count': status.validCount,
                      'keep': status.retention,
                    }),
                  ),
                  if (status.enabled)
                    tile(
                      '下次自动备份',
                      date(status.nextDueAt),
                      icon: Icons.schedule_outlined,
                    ),
                  tile(
                    '待备份更改',
                    status.dirtySince == null
                        ? context.tr('没有待处理更改')
                        : date(status.dirtySince),
                  ),
                  if (status.failureCode != null)
                    tile(
                      '最近备份失败',
                      '${date(status.lastFailure)}\n${context.tr(backupFailureLabel(status.failureCode))}',
                    ),
                  tile(
                    '回收站',
                    context.tr(
                      '账号 {accounts} · 订阅 {subscriptions} · 最近到期 {time}',
                      {
                        'accounts': app.trashAccounts.length,
                        'subscriptions': app.trashSubscriptions.length,
                        'time': date(expiry.firstOrNull),
                      },
                    ),
                    icon: Icons.delete_outline,
                    action: () => open(TrashPage(appState: app)),
                  ),
                  tile(
                    '保险库密码恢复准备',
                    context.tr(switch ((
                      app.primaryRecoveryConfigured,
                      app.decoyRecoveryConfigured,
                    )) {
                      (true, true) => '真实库和诱饵库均已配置恢复',
                      (true, false) => '仅真实库已配置恢复',
                      (false, true) => '仅诱饵库已配置恢复',
                      (false, false) => '尚未配置恢复方式',
                    }),
                    action: widget.onRecovery,
                  ),
                  const Divider(),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    key: ValueKey((
                      status.enabled ? status.intervalDays : intervalDays,
                      _intervalRevision,
                    )),
                    initialValue: status.enabled
                        ? status.intervalDays
                        : intervalDays,
                    decoration: InputDecoration(
                      labelText: context.tr('自动备份周期'),
                    ),
                    items: [
                      for (final days in [7, 15, 30])
                        DropdownMenuItem(
                          value: days,
                          child: Text(
                            context.tr(switch (days) {
                              7 => '7 天（每周）',
                              15 => '15 天（半个月）',
                              _ => '30 天（一个月）',
                            }),
                          ),
                        ),
                    ],
                    onChanged: busy ? null : (value) => changeInterval(value!),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '到期后完整解锁时自动备份，即使内容相同也会生成。仅保留最近 3 份；应用自动校验新备份，成功后自动删除最旧文件，无需手动验证。',
                    ),
                  ),
                  if (status.enabled) const Text('周期从最近一次成功的自动备份起计算；选择后自动保存。'),
                  tile(
                    '选择或更换备份目录与密码',
                    '先生成并验证一份新备份，再保存配置。',
                    action: setup,
                    icon: Icons.folder_open,
                  ),
                  tile(
                    '立即自动备份',
                    '使用本机已配置的目录和独立备份密码',
                    action: status.enabled
                        ? () async {
                            final ok = await app.autoBackup.runNow();
                            message(
                              ok
                                  ? '自动备份已完整验证。'
                                  : backupFailureLabel(
                                      app.autoBackup.status.failureCode,
                                    ),
                            );
                          }
                        : null,
                    icon: Icons.backup_outlined,
                  ),
                  if (status.enabled)
                    tile(
                      '关闭自动备份',
                      '保留外部文件，可稍后重新配置。',
                      action: () async {
                        if (await safetyConfirm(
                          context,
                          '关闭自动备份？',
                          '已生成的外部备份不会删除。',
                        )) {
                          await app.autoBackup.disable();
                        }
                      },
                    ),
                  tile(
                    '导出 Cardock 加密备份',
                    '生成 .asmbackup，使用独立备份密码。',
                    action: widget.onManualBackup,
                    icon: Icons.save_outlined,
                  ),
                  tile(
                    '检查 Cardock 加密备份（不恢复）',
                    '重新选择 .asmbackup 并完整解密，不改变本机数据。',
                    action: widget.onVerify,
                    icon: Icons.verified_outlined,
                  ),
                  tile(
                    '恢复 Cardock 加密备份',
                    '仅恢复 .asmbackup；恢复前仍需当前主密码和明确确认。',
                    action: widget.onRestore,
                    icon: Icons.restore,
                  ),
                  tile(
                    '导出可读副本（非备份）',
                    'CSV / JSON 为明文，不能用于恢复 Cardock。',
                    action: () => open(ReadableExportPage(appState: app)),
                    icon: Icons.file_download_outlined,
                  ),
                  tile(
                    '数据安全帮助',
                    '备份、验证、恢复与重建说明',
                    action: () => safetyConfirm(
                      context,
                      '数据安全帮助',
                      '加密备份需要对应备份密码。建议将已验证文件保存在另一处。可读导出包含明文备注。回收站保留 30 天。忘记主密码时，可在锁屏使用已配置恢复方式，或受控删除本机数据后新建保险库，再恢复自己的备份。',
                      action: '知道了',
                    ),
                  ),
                  Text(
                    context.tr('应用 {version} · 加密备份格式 v2 · 可读导出格式 v1', {
                      'version': AppMetadata.displayVersion,
                    }),
                  ),
                  const Text('手动备份的时间是历史验证记录；请重新选择文件检查当前可用性。'),
                  if (busy) const LinearProgressIndicator(),
                ],
              ),
      );
    },
  );
}
