import '../../../core/platform/import_document_picker.dart';
import '../../../app/app_state.dart';
import '../../../core/security/vault_contract.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import 'data_import_ui_controller.dart';
import 'data_migration_center_page.dart';
import 'pending_subscription_drafts_page.dart';

class DataMigrationCenterHubPage extends StatelessWidget {
  const DataMigrationCenterHubPage({
    required this.appState,
    required this.controllerFactory,
    required this.onOpenComputerBatch,
    required this.onUndoLastBatch,
    this.documentPicker = pickImportDocument,
    super.key,
  });

  final AppState appState;
  final DataImportUiControllerFactory controllerFactory;
  final Future<void> Function()? onOpenComputerBatch;
  final Future<void> Function() onUndoLastBatch;
  final DataImportDocumentPicker documentPicker;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appState,
    builder: (context, child) => Scaffold(
      appBar: AppBar(title: const Text('外部数据导入')),
      body: ListView(
        key: const ValueKey<String>('data-migration-center-hub'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            '从密码管理器或 XLSX、DOCX、CSV、TSV、TXT 文件快速整理',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          const Text('所有解析、预览和提交都在本机完成；提交前会再次核对当前保险库代次和数量限制。'),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey<String>('start-data-import-wizard'),
            onPressed: _canWrite ? () => _openWizard(context) : null,
            icon: const Icon(Icons.move_to_inbox_outlined),
            label: const Text('选择文件并开始导入'),
          ),
          const SizedBox(height: 14),
          _HubTile(
            key: const ValueKey<String>('migration-export-guide'),
            icon: Icons.ios_share_outlined,
            title: '从原应用导出文件',
            subtitle:
                '支持 Chrome、Google Password Manager、Bitwarden、KeePassXC、1Password 与 Cardock 模板',
            onTap: () => _showExportGuide(context),
          ),
          _HubTile(
            key: const ValueKey<String>('migration-share-text-help'),
            icon: Icons.share_outlined,
            title: '从其他应用分享文字',
            subtitle: 'Android 可分享普通文字或 http(s) 链接；解锁后在本机核对候选',
            onTap: () => _showShareTextHelp(context),
          ),
          _HubTile(
            key: const ValueKey<String>('migration-computer-batch'),
            icon: Icons.laptop_chromebook_outlined,
            title: '用电脑批量整理',
            subtitle: '复用现有一次性连接和端到端加密；最终仍在手机审批',
            onTap: onOpenComputerBatch == null || !_canWrite
                ? null
                : onOpenComputerBatch,
          ),
          _HubTile(
            key: const ValueKey<String>('migration-pending-subscriptions'),
            icon: Icons.edit_calendar_outlined,
            title: '继续完善订阅',
            subtitle: appState.pendingSubscriptionDrafts.isEmpty
                ? '当前没有待完善订阅'
                : context.tr('有 {count} 条加密草稿等待补全', <String, Object?>{
                    'count': appState.pendingSubscriptionDrafts.length,
                  }),
            badge: appState.pendingSubscriptionDrafts.length,
            onTap: _canWrite ? () => _openPending(context) : null,
          ),
          _HubTile(
            key: const ValueKey<String>('migration-undo-last-batch'),
            icon: Icons.undo_rounded,
            title: '撤销最近一次批量导入',
            subtitle: _rollbackSubtitle(context),
            onTap: !_canWrite || !appState.hasLastBatchRollbackArtifact
                ? null
                : appState.canUndoLastBatchImport
                ? onUndoLastBatch
                : () => _confirmDiscardRollback(context),
          ),
          _HubTile(
            key: const ValueKey<String>('migration-format-safety'),
            icon: Icons.shield_outlined,
            title: '格式与安全说明',
            subtitle: '10 MiB / 5000 行；敏感列排除、遮挡密码确认与内存清理',
            onTap: () => _showSafety(context),
          ),
        ],
      ),
    ),
  );

  bool get _canWrite =>
      appState.isUnlocked &&
      appState.hasFullVaultAccess &&
      appState.canManageSecurity &&
      !appState.isBusy &&
      appState.importVaultScopeId != null;

  String _rollbackSubtitle(BuildContext context) {
    switch (appState.lastBatchRollbackAvailability) {
      case BatchRollbackAvailability.none:
        return '当前没有可撤销的批量导入';
      case BatchRollbackAvailability.revisionChanged:
        return '导入后业务数据已变化，无法安全整体撤销；可点此明确丢弃旧回滚点';
      case BatchRollbackAvailability.unreadable:
        return '加密回滚点无法读取，已禁止应用；可点此明确丢弃';
      case BatchRollbackAvailability.available:
        break;
    }
    final impact = appState.lastBatchRollbackImpact;
    if (impact == null) return '加密回滚点仍可用；请确认后撤销最近一次批量导入';
    return context.tr(
      '影响 {affected} 条：新增账号 {added}、更新 {updated}、正式订阅 {formal}、草稿 {drafts}',
      <String, Object?>{
        'affected': impact.affectedRecordCount,
        'added': impact.addedAccountCount,
        'updated': impact.updatedAccountCount,
        'formal': impact.formalSubscriptionCount,
        'drafts': impact.pendingSubscriptionDraftCount,
      },
    );
  }

  Future<void> _confirmDiscardRollback(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('丢弃批量导入回滚点？'),
        content: const Text(
          '这只会删除最近一次批量导入的独立加密回滚点，不会改变当前账号、订阅或备份恢复前回滚。删除后无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认丢弃回滚点'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final discarded = await appState.discardLastBatchImportRollback();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(discarded ? '批量导入回滚点已丢弃' : '未能丢弃批量导入回滚点'),
          translate: false,
        ),
      ),
    );
  }

  Future<void> _openWizard(BuildContext context) {
    // One controller belongs to one pushed route. Rebuilding a route after a
    // system picker, theme or locale change must not discard the import session.
    final controller = controllerFactory();
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => DataMigrationCenterPage(
          controller: controller,
          documentPicker: () async {
            appState.beginExternalInteraction();
            try {
              return await documentPicker();
            } finally {
              appState.endExternalInteraction();
            }
          },
          pendingDraftCount: appState.pendingSubscriptionDrafts.length,
          onOpenPendingSubscriptions: () => _openPending(context),
        ),
      ),
    );
  }

  Future<void> _openPending(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => PendingSubscriptionDraftsPage(appState: appState),
    ),
  );

  Future<void> _showExportGuide(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('先从原应用导出'),
      content: const Text(
        '在原密码管理器中选择 CSV 导出，或下载 Cardock 空模板后用 Excel / WPS 填写。导入支持 XLSX、DOCX、CSV、TSV、TXT；这些文件可能包含明文密码，请不要上传到网盘。导入后请在确认备份无误后自行安全删除源文件。',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  Future<void> _showShareTextHelp(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Android“分享至卡坞”'),
      content: const SingleChildScrollView(
        child: Text(
          '在其他 Android 应用的分享菜单中选择“分享至卡坞”。Cardock 只接受单条 text/plain 普通文字和 http(s) 链接；图片、PDF、附件、HTML、文件 URI 和可执行内容都会拒绝。\n\n'
          '原文只在进程内存中保留最多 5 分钟。必须先解锁真实库或诱饵库，确认候选并选择当前库中的已有账号后，才能保存为待完善订阅草稿。不会打开网址、联网抓取、上传、自动新建账号或正式订阅。',
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  Future<void> _showSafety(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('格式与安全说明'),
      content: const SingleChildScrollView(
        child: Text(
          '支持 XLSX、DOCX、CSV、TSV、TXT；XLSX 读取首个工作表，DOCX 读取首个表格，文本文件支持 UTF-8 / UTF-16 BOM 以及逗号、制表符或分号分隔。单文件不超过 10 MiB、5000 行、200 列。\n\n'
          '未识别列不会静默写入；一次性验证码等敏感列会按规则排除。密码默认遮挡，疑似星号或圆点占位值不会自动导入。\n\n'
          '流程离开前台、锁定保险库、取消或完成后会清理本次内存；不会申请新的存储权限。',
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge = 0,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Row(
        children: [
          Expanded(child: Text(context.tr(title), translate: false)),
          if (badge > 0)
            Badge(
              label: Text('$badge', translate: false),
              child: const SizedBox(width: 1, height: 1),
            ),
        ],
      ),
      subtitle: Text(context.tr(subtitle), translate: false),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}
