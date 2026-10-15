import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../../../shared/widgets/cardock_ui.dart';
import '../domain/account_analysis.dart';
import '../domain/account_record.dart';

const passwordHealthNotice =
    '仅分析当前保险库中的活动账号。未保存密码不代表账号不安全；Cardock 无变更记录不代表平台密码从未变更。用户可能已在平台外改密。Cardock 无法知道平台真实密码状态、密码是否泄露或账号是否被盗，也不强制定期改密。';

class PasswordHealthCenterPage extends StatefulWidget {
  const PasswordHealthCenterPage({
    required this.analysisProvider,
    required this.accountsProvider,
    required this.changes,
    this.onOpenAccount,
    this.onEditAccount,
    this.onIgnore,
    this.onRestore,
    this.onOpenFilteredAccounts,
    super.key,
  });
  final AccountAnalysisSnapshot Function() analysisProvider;
  final List<AccountRecord> Function() accountsProvider;
  final Listenable changes;
  final Future<void> Function(AccountRecord account)? onOpenAccount;
  final Future<void> Function(AccountRecord account)? onEditAccount;
  final Future<bool> Function(PasswordHealthFinding finding)? onIgnore;
  final Future<bool> Function(PasswordHealthFinding finding)? onRestore;
  final VoidCallback? onOpenFilteredAccounts;
  @override
  State<PasswordHealthCenterPage> createState() =>
      _PasswordHealthCenterPageState();
}

class _PasswordHealthCenterPageState extends State<PasswordHealthCenterPage> {
  bool _showIgnored = false;
  bool _busy = false;
  Future<void> _change(PasswordHealthFinding finding) async {
    final action = finding.ignored ? widget.onRestore : widget.onIgnore;
    if (action == null || _busy) return;
    setState(() => _busy = true);
    try {
      final ok = await action(finding);
      if (mounted && !ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('记录已变化或保存失败，请重新核对。')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _findingCard(
    PasswordHealthFinding finding,
    AccountRecord account,
  ) => CardockSurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          account.platformName,
          translate: false,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(finding.title),
        Wrap(
          spacing: 8,
          children: [
            if (widget.onOpenAccount != null)
              TextButton(
                onPressed: _busy ? null : () => widget.onOpenAccount!(account),
                child: const Text('查看账号'),
              ),
            if (widget.onEditAccount != null)
              TextButton(
                onPressed: _busy ? null : () => widget.onEditAccount!(account),
                child: const Text('编辑账号'),
              ),
            if ((finding.ignored ? widget.onRestore : widget.onIgnore) != null)
              TextButton(
                key: ValueKey(
                  'health-${finding.accountId}-${finding.issueType}',
                ),
                onPressed: _busy ? null : () => _change(finding),
                child: Text(finding.ignored ? '恢复提示' : '忽略此项'),
              ),
          ],
        ),
      ],
    ),
  );
  Future<void> _openReuseGroup(String anchorId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('相同密码的账号')),
          body: ListenableBuilder(
            listenable: widget.changes,
            builder: (context, _) {
              final analysis = widget.analysisProvider();
              final records = {
                for (final a in widget.accountsProvider()) a.id: a,
              };
              final representative = analysis.healthFindings
                  .where(
                    (f) =>
                        f.issueType == 'reusedPassword' &&
                        f.accountId == anchorId,
                  )
                  .firstOrNull;
              final ids = representative?.relatedAccountIds ?? const <String>{};
              final findings = analysis.healthFindings
                  .where(
                    (f) =>
                        f.issueType == 'reusedPassword' &&
                        ids.contains(f.accountId) &&
                        f.ignored == _showIgnored,
                  )
                  .toList();
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: findings.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        context.tr('以下 {count} 个账号当前使用相同密码', {
                          'count': ids.length,
                        }),
                        translate: false,
                      ),
                    );
                  }
                  final finding = findings[index - 1];
                  final account = records[finding.accountId];
                  return account == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _findingCard(finding, account),
                        );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('密码健康')),
    body: ListenableBuilder(
      listenable: widget.changes,
      builder: (context, _) {
        final analysis = widget.analysisProvider();
        final records = {
          for (final account in widget.accountsProvider()) account.id: account,
        };
        final sections = {
          for (final severity in PasswordHealthSeverity.values)
            severity: <PasswordHealthFinding>[],
        };
        final reuseSeen = <String>{};
        for (final finding in analysis.healthFindings) {
          if (finding.ignored != _showIgnored) continue;
          if (finding.issueType == 'reusedPassword' &&
              finding.relatedAccountIds.isNotEmpty &&
              !reuseSeen.add(finding.relatedAccountIds.first)) {
            continue;
          }
          sections[finding.severity]!.add(finding);
        }
        final rows = <Object>[];
        for (final entry in sections.entries) {
          if (entry.value.isNotEmpty) {
            rows.add(entry.key);
            rows.addAll(entry.value);
          }
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CardockSurfaceCard(child: Text(passwordHealthNotice)),
                  SwitchListTile(
                    key: const ValueKey('show-ignored-health'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('查看已忽略项目'),
                    value: _showIgnored,
                    onChanged: (value) => setState(() => _showIgnored = value),
                  ),
                  if (widget.onOpenFilteredAccounts != null && !_showIgnored)
                    OutlinedButton.icon(
                      onPressed: widget.onOpenFilteredAccounts,
                      icon: const Icon(Icons.filter_alt_outlined),
                      label: const Text('在账号列表查看并整理'),
                    ),
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(_showIgnored ? '没有已忽略项目' : '当前没有未忽略的健康提示'),
                    ),
                ],
              );
            }
            final row = rows[index - 1];
            if (row is PasswordHealthSeverity) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Semantics(
                  header: true,
                  child: Text(switch (row) {
                    PasswordHealthSeverity.priority => '优先处理',
                    PasswordHealthSeverity.optimization => '建议优化',
                    PasswordHealthSeverity.verification => '资料核对',
                  }, style: Theme.of(context).textTheme.titleLarge),
                ),
              );
            }
            final finding = row as PasswordHealthFinding;
            final account = records[finding.accountId];
            if (account == null) return const SizedBox.shrink();
            if (finding.issueType == 'reusedPassword') {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: CardockSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.tr('以下 {count} 个账号当前使用相同密码', {
                          'count': finding.relatedAccountIds.length,
                        }),
                        translate: false,
                      ),
                      TextButton(
                        key: ValueKey(
                          'open-password-reuse-group-${finding.relatedAccountIds.first}',
                        ),
                        onPressed: () => _openReuseGroup(finding.accountId),
                        child: const Text('查看账号并逐项处理'),
                      ),
                    ],
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _findingCard(finding, account),
            );
          },
        );
      },
    ),
  );
}
