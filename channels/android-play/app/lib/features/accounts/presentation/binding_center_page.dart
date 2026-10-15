import 'dart:async';

import '../../../core/platform/sensitive_clipboard.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../../../shared/widgets/cardock_ui.dart';
import '../domain/account_analysis.dart';
import '../domain/account_record.dart';

class BindingCenterPage extends StatefulWidget {
  const BindingCenterPage({
    required this.analysisProvider,
    required this.accountsProvider,
    required this.changes,
    this.onOpenAccount,
    this.onEditAccount,
    this.onCreatePlan,
    this.onClosePlan,
    this.onDeletePlan,
    this.onOpenFilteredAccounts,
    this.sensitiveClipboard = const PlatformSensitiveClipboard(),
    this.revealDuration = const Duration(seconds: 30),
    super.key,
  });
  final AccountAnalysisSnapshot Function() analysisProvider;
  final List<AccountRecord> Function() accountsProvider;
  final Listenable changes;
  final Future<void> Function(AccountRecord account)? onOpenAccount;
  final Future<void> Function(AccountRecord account)? onEditAccount;
  final Future<bool> Function(BindingGroup group)? onCreatePlan;
  final Future<bool> Function(String planId)? onClosePlan;
  final Future<bool> Function(String planId)? onDeletePlan;
  final VoidCallback? onOpenFilteredAccounts;
  final SensitiveClipboard sensitiveClipboard;
  final Duration revealDuration;
  @override
  State<BindingCenterPage> createState() => _BindingCenterPageState();
}

class _BindingCenterPageState extends State<BindingCenterPage>
    with WidgetsBindingObserver {
  int _tab = 0;
  bool _busy = false;
  final Set<String> _visible = {};
  final Map<String, Timer> _timers = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _hideAll();
  }

  void _hideAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    if (mounted) setState(_visible.clear);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _visible.clear();
    _timers.clear();
    super.dispose();
  }

  void _toggle(String key) {
    _timers.remove(key)?.cancel();
    setState(() {
      if (!_visible.add(key)) _visible.remove(key);
    });
    if (_visible.contains(key)) {
      _timers[key] = Timer(widget.revealDuration, () {
        if (mounted) setState(() => _visible.remove(key));
      });
    }
  }

  Future<void> _copy(String value) async {
    try {
      await widget.sensitiveClipboard.copySensitive(
        text: value,
        label: context.tr('绑定资料'),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已安全复制，60 秒后自动清除。')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('复制失败，未写入剪贴板。')));
      }
    }
  }

  Future<void> _mutate(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await action();
      if (mounted && !ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('记录已变化或保存失败，请重新核对。')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _value(String value, String key, {String? controlId}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        label: context.tr(_visible.contains(key) ? '绑定资料已临时显示' : '绑定资料已隐藏'),
        child: ExcludeSemantics(
          child: Text(
            _visible.contains(key) ? value : '••••••••',
            key: ValueKey('binding-value-${controlId ?? key}'),
            translate: false,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
      Wrap(
        alignment: WrapAlignment.end,
        children: [
          IconButton(
            key: ValueKey('reveal-binding-${controlId ?? key}'),
            tooltip: context.tr(
              _visible.contains(key) ? '隐藏敏感值' : '临时显示敏感值30秒',
            ),
            onPressed: () => _toggle(key),
            icon: Icon(
              _visible.contains(key)
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
          IconButton(
            tooltip: context.tr('安全复制绑定资料'),
            onPressed: () => _copy(value),
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
    ],
  );
  Widget _accounts(Set<String> Function() idsProvider, String label) =>
      TextButton.icon(
        icon: const Icon(Icons.list_alt),
        label: Text(label),
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(title: Text(label)),
              body: ListenableBuilder(
                listenable: widget.changes,
                builder: (context, _) {
                  final ids = idsProvider();
                  final records = widget
                      .accountsProvider()
                      .where((a) => ids.contains(a.id))
                      .toList();
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final account = records[index];
                      return ListTile(
                        title: Text(account.platformName, translate: false),
                        onTap: widget.onOpenAccount == null
                            ? null
                            : () => widget.onOpenAccount!(account),
                        trailing: widget.onEditAccount == null
                            ? null
                            : IconButton(
                                tooltip: context.tr('编辑账号'),
                                onPressed: _busy
                                    ? null
                                    : () => widget.onEditAccount!(account),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );
  Set<String> _groupIds(String key) =>
      widget
          .analysisProvider()
          .bindingGroups
          .where((g) => g.key == key)
          .firstOrNull
          ?.activeAccountIds ??
      const {};
  Set<String> _planIds(String id, bool completed) {
    final progress = widget
        .analysisProvider()
        .bindingPlans
        .where((p) => p.plan.id == id)
        .firstOrNull;
    return completed
        ? (progress?.completedAccountIds ?? const {})
        : (progress?.pendingAccountIds ?? const {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('绑定资料中心')),
    body: ListenableBuilder(
      listenable: widget.changes,
      builder: (context, _) {
        final analysis = widget.analysisProvider();
        final planKeys = {
          for (final p in analysis.bindingPlans)
            if (!p.plan.isClosed)
              '${p.plan.type.name}:${p.plan.normalizedValue}',
        };
        final groups = analysis.bindingGroups
            .where(
              (g) =>
                  g.type == (_tab == 0 ? BindingType.phone : BindingType.email),
            )
            .toList();
        final count = _tab == 2 ? analysis.bindingPlans.length : groups.length;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: count + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CardockSurfaceCard(
                    child: Text(
                      '仅反查账号专用手机号和邮箱字段。进度根据卡坞记录自动变化，不代表真实平台已换绑；请到平台自行核对。',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (tab, label) in [
                        (0, '手机号'),
                        (1, '邮箱'),
                        (2, '准备停用计划'),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: _tab == tab,
                          onSelected: (_) => setState(() => _tab = tab),
                        ),
                    ],
                  ),
                  if (_tab == 2 && widget.onOpenFilteredAccounts != null)
                    OutlinedButton.icon(
                      onPressed: widget.onOpenFilteredAccounts,
                      icon: const Icon(Icons.filter_alt_outlined),
                      label: const Text('在账号列表查看并整理'),
                    ),
                  if (count == 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(_tab == 2 ? '没有准备停用计划' : '没有对应的绑定资料'),
                    ),
                ],
              );
            }
            if (_tab != 2) {
              final group = groups[index - 1];
              final exists = planKeys.contains(group.key);
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: CardockSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _value(
                        group.targetValue,
                        group.key,
                        controlId: 'group-$index',
                      ),
                      Text(
                        context.tr('活动账号 {active} · 回收站 {trash}', {
                          'active': group.activeAccountIds.length,
                          'trash': group.trashAccountIds.length,
                        }),
                        translate: false,
                      ),
                      _accounts(() => _groupIds(group.key), '查看全部关联账号'),
                      if (widget.onCreatePlan != null && !exists)
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () =>
                                    _mutate(() => widget.onCreatePlan!(group)),
                          icon: const Icon(Icons.checklist),
                          label: const Text('标记准备停用'),
                        ),
                    ],
                  ),
                ),
              );
            }
            final progress = analysis.bindingPlans[index - 1];
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: CardockSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      progress.plan.type == BindingType.phone ? '手机号' : '邮箱',
                    ),
                    _value(progress.plan.targetValue, progress.plan.id),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        context.tr('待处理 {pending} · 已处理 {done} · 回收站 {trash}', {
                          'pending': progress.pendingAccountIds.length,
                          'done': progress.completedAccountIds.length,
                          'trash': progress.trashAccountIds.length,
                        }),
                        translate: false,
                      ),
                    ),
                    if (progress.plan.isClosed)
                      const Text('计划已关闭')
                    else if (progress.pendingAccountIds.isEmpty)
                      Text(
                        progress.trashAccountIds.isEmpty
                            ? '活动账号已处理'
                            : '活动账号已处理，回收站仍保留此绑定资料',
                      ),
                    if (progress.pendingAccountIds.isNotEmpty)
                      _accounts(
                        () => _planIds(progress.plan.id, false),
                        '查看待处理账号',
                      ),
                    if (progress.completedAccountIds.isNotEmpty)
                      _accounts(
                        () => _planIds(progress.plan.id, true),
                        '查看已处理账号',
                      ),
                    if (progress.pendingAccountIds.isEmpty)
                      Wrap(
                        spacing: 8,
                        children: [
                          if (!progress.plan.isClosed &&
                              widget.onClosePlan != null)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _mutate(
                                      () =>
                                          widget.onClosePlan!(progress.plan.id),
                                    ),
                              child: const Text('关闭计划'),
                            ),
                          if (widget.onDeletePlan != null)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _mutate(
                                      () => widget.onDeletePlan!(
                                        progress.plan.id,
                                      ),
                                    ),
                              child: const Text('删除已完成计划'),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
