import '../../../app/app_state.dart';
import '../../../core/storage/readable_export.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import 'data_safety_dialogs.dart';

class ReadableExportPage extends StatefulWidget {
  const ReadableExportPage({required this.appState, super.key});
  final AppState appState;
  @override
  State<ReadableExportPage> createState() => _ReadableExportPageState();
}

class _ReadableExportPageState extends State<ReadableExportPage> {
  bool trash = false,
      passwords = false,
      sensitiveFields = false,
      working = false;
  ReadableExportFormat format = ReadableExportFormat.csvZip;
  Future<void> export() async {
    if (passwords &&
        !await safetyConfirm(
          context,
          '包含当前账号密码？',
          '文件包含明文密码，任何取得文件的人都能读取。密码变更历史仅包含日期，不包含旧密码。',
        )) {
      return;
    }
    if (!mounted) return;
    if (sensitiveFields) {
      if (!await safetyConfirm(
        context,
        '包含敏感自定义字段值？',
        '这些字段将以明文导出，任何取得文件的人都能读取。此选项独立于账号密码。',
      )) {
        return;
      }
    }
    if (!mounted) return;
    final password = await safetyInput(context, '当前保险库密码');
    if (password == null || !mounted) return;
    setState(() => working = true);
    widget.appState.beginExternalInteraction();
    bool ok;
    try {
      ok = await widget.appState.exportReadable(
        options: ReadableExportOptions(
          format: format,
          includeTrash: trash,
          includePasswords: passwords,
          includeSensitiveCustomFields: sensitiveFields,
        ),
        currentPassword: password,
        passwordDisclosureConfirmed: passwords,
        sensitiveFieldsDisclosureConfirmed: sensitiveFields,
      );
    } finally {
      widget.appState.endExternalInteraction();
    }
    if (!mounted) return;
    setState(() => working = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? context.tr(
                  '已导出 {format} · {time} · 包含密码：{passwords}。文件为明文，请妥善保存。',
                  {
                    'format': format == ReadableExportFormat.json
                        ? 'JSON'
                        : 'CSV ZIP',
                    'time': DateTime.now().toIso8601String().split('.').first,
                    'passwords': context.tr(passwords ? '是' : '否'),
                  },
                )
              : widget.appState.errorMessage ?? '导出已取消或未完成。',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.appState,
    builder: (context, _) {
      final app = widget.appState;
      return Scaffold(
        appBar: AppBar(title: const Text('导出可读数据')),
        body: !app.isUnlocked || !app.hasFullVaultAccess
            ? const Center(child: Text('请完整解锁当前保险库。'))
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    '加密备份用于Cardock恢复。CSV / JSON 为明文，可被其他程序读取，不能直接恢复保险库。',
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<ReadableExportFormat>(
                    isExpanded: true,
                    initialValue: format,
                    decoration: InputDecoration(labelText: context.tr('导出格式')),
                    items: const [
                      DropdownMenuItem(
                        value: ReadableExportFormat.csvZip,
                        child: Text('CSV ZIP'),
                      ),
                      DropdownMenuItem(
                        value: ReadableExportFormat.json,
                        child: Text('JSON'),
                      ),
                    ],
                    onChanged: working
                        ? null
                        : (value) => setState(() => format = value!),
                  ),
                  SwitchListTile(
                    value: trash,
                    title: const Text('包含回收站记录'),
                    onChanged: working
                        ? null
                        : (value) => setState(() => trash = value),
                  ),
                  SwitchListTile(
                    value: passwords,
                    title: const Text('包含当前账号密码'),
                    onChanged: working
                        ? null
                        : (value) => setState(() => passwords = value),
                  ),
                  SwitchListTile(
                    value: sensitiveFields,
                    title: const Text('包含敏感自定义字段值'),
                    subtitle: const Text('默认脱敏；与包含账号密码分别确认。'),
                    onChanged: working
                        ? null
                        : (value) => setState(() => sensitiveFields = value),
                  ),
                  Text(
                    context.tr(
                      '账号 {accounts} · 订阅 {subscriptions} · 回收站 {trash}',
                      {
                        'accounts':
                            app.accounts.length +
                            (trash ? app.trashAccounts.length : 0),
                        'subscriptions':
                            app.subscriptions.length +
                            (trash ? app.trashSubscriptions.length : 0),
                        'trash': trash
                            ? app.trashAccounts.length +
                                  app.trashSubscriptions.length
                            : 0,
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('包含明文备注。历史费用会保留，关联记录可能已被删除。'),
                  const Text('绑定停用计划会包含手机号或邮箱，请妥善保存明文导出文件。'),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: working || app.isBusy ? null : export,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('验证密码并导出'),
                  ),
                  if (working) const LinearProgressIndicator(),
                ],
              ),
      );
    },
  );
}
