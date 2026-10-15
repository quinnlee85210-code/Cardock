import '../../../app/app_state.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import 'data_safety_dialogs.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({required this.appState, super.key});
  final AppState appState;
  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  String query = '';
  void message(bool success) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? '操作完成。' : widget.appState.errorMessage ?? '操作未完成，原数据保持不变。',
        ),
      ),
    );
  }

  Future<void> remove({
    String? accountId,
    String? subscriptionId,
    bool all = false,
  }) async {
    if (!await safetyConfirm(
      context,
      '永久删除回收站记录？',
      '此操作无法撤销。已记录的历史费用仍会保留；外部备份文件不受影响。',
      action: '继续',
    )) {
      return;
    }
    if (!mounted) return;
    String? phrase;
    if (all) {
      phrase = await safetyInput(context, '输入“清空回收站”', secret: false);
      if (phrase != '清空回收站' || !mounted) return;
    }
    final password = await safetyInput(context, '当前保险库密码');
    if (password == null || !mounted) return;
    message(
      await widget.appState.permanentlyDeleteTrash(
        currentPassword: password,
        accountIds: {?accountId},
        subscriptionIds: {?subscriptionId},
        emptyAll: all,
        confirmation: phrase ?? '',
      ),
    );
  }

  Widget record({
    required String title,
    required DateTime deleted,
    required DateTime expires,
    String? accountId,
    String? subscriptionId,
  }) {
    final remaining =
        (expires.difference(DateTime.now().toUtc()).inSeconds / 86400)
            .ceil()
            .clamp(0, 30);
    return Card(
      child: ListTile(
        title: Text(title, translate: false),
        subtitle: Text(
          context.tr('删除：{date} · 剩余 {days} 天', {
            'date': deleted.toLocal().toIso8601String().split('.').first,
            'days': remaining,
          }),
        ),
        trailing: PopupMenuButton<String>(
          enabled: !widget.appState.isBusy,
          onSelected: (action) async {
            if (action == 'delete') {
              await remove(
                accountId: accountId,
                subscriptionId: subscriptionId,
              );
            } else {
              message(
                await widget.appState.restoreTrash(
                  accountId: accountId,
                  subscriptionId: subscriptionId,
                  wholeBatch: action == 'batch',
                ),
              );
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'restore', child: Text('恢复此项')),
            PopupMenuItem(value: 'batch', child: Text('恢复整个删除组合')),
            PopupMenuItem(value: 'delete', child: Text('永久删除')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.appState,
    builder: (context, _) {
      final app = widget.appState;
      if (!app.isUnlocked || !app.hasFullVaultAccess) {
        return const Scaffold(body: Center(child: Text('请完整解锁当前保险库。')));
      }
      final accounts = app.trashAccounts.where(
        (e) =>
            e.record.platformName.toLowerCase().contains(query.toLowerCase()),
      );
      final subscriptions = app.trashSubscriptions.where(
        (e) => e.record.serviceName.toLowerCase().contains(query.toLowerCase()),
      );
      return Scaffold(
        appBar: AppBar(
          title: const Text('回收站'),
          actions: [
            IconButton(
              tooltip: context.tr('清空回收站'),
              onPressed:
                  app.isBusy ||
                      (app.trashAccounts.isEmpty &&
                          app.trashSubscriptions.isEmpty)
                  ? null
                  : () => remove(all: true),
              icon: const Icon(Icons.delete_forever_outlined),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('记录保留 30 天，到期后在完整解锁时自动清理。恢复会保留原账期和状态。'),
            const SizedBox(height: 12),
            TextField(
              onChanged: (value) => setState(() => query = value),
              decoration: InputDecoration(
                labelText: context.tr('搜索回收站'),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            if (accounts.isEmpty && subscriptions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('回收站中没有匹配记录。'),
              ),
            for (final item in accounts)
              record(
                title: item.record.platformName,
                deleted: item.deletedAtUtc,
                expires: item.expiresAtUtc,
                accountId: item.record.id,
              ),
            for (final item in subscriptions)
              record(
                title: item.record.serviceName,
                deleted: item.deletedAtUtc,
                expires: item.expiresAtUtc,
                subscriptionId: item.record.id,
              ),
          ],
        ),
      );
    },
  );
}
