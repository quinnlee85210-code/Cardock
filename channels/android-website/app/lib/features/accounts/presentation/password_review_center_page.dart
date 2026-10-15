import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../../../l10n/translations_records.dart';
import '../../../shared/widgets/cardock_ui.dart';
import '../domain/account_record.dart';
import 'accounts_page.dart';

class PasswordChangeHistoryPage extends StatelessWidget {
  const PasswordChangeHistoryPage({
    required this.recordsListenable,
    required this.accountsProvider,
    this.nowUtc,
    super.key,
  });

  final Listenable recordsListenable;
  final List<AccountRecord> Function() accountsProvider;
  final DateTime Function()? nowUtc;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('密码变更记录')),
    body: SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: recordsListenable,
        builder: (context, _) {
          final accounts = accountsProvider()
              .where(
                (account) =>
                    account.password != null ||
                    account.passwordChangeHistory.isNotEmpty,
              )
              .toList();
          final count = accounts.fold<int>(
            0,
            (sum, account) => sum + account.passwordChangeHistory.length,
          );
          final groups = groupAccountsByCategory(accounts);
          return ListView(
            key: const ValueKey('password-change-history-page'),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              CardockSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('已记录{count}次密码变更', {'count': count}),
                      translate: false,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text('在Cardock保存不同的密码时自动记录，首次录入不计次，无需设置或复核。'),
                    const SizedBox(height: 6),
                    const Text('仅记录日期与间隔，不保留旧密码。升级前未保存的变更历史无法补录。'),
                    const SizedBox(height: 6),
                    const Text('点击分类展开或收起账号。'),
                  ],
                ),
              ),
              if (accounts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('暂无密码变更记录'),
                ),
              for (final group in groups)
                Padding(
                  key: ValueKey(
                    'password-history-group-${group.label.toLowerCase()}',
                  ),
                  padding: const EdgeInsets.only(top: 12),
                  child: CardockSurfaceCard(
                    padding: EdgeInsets.zero,
                    child: ExpansionTile(
                      key: PageStorageKey(
                        'password-history-category-${group.label.toLowerCase()}',
                      ),
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: Text(
                        localizedAccountCategoryLabel(context, group.label),
                        translate: false,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: Text(
                        context.tr('共{count}个账号 · {changes}次变更', {
                          'count': group.accounts.length,
                          'changes': group.accounts.fold<int>(
                            0,
                            (sum, account) =>
                                sum + account.passwordChangeHistory.length,
                          ),
                        }),
                        translate: false,
                      ),
                      children: [
                        for (final account in group.accounts)
                          Padding(
                            key: ValueKey(account.id),
                            padding: const EdgeInsets.only(bottom: 8),
                            child: PasswordChangeHistoryCard(
                              account: account,
                              showAccount: true,
                              nowUtc: nowUtc,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class PasswordChangeHistoryCard extends StatelessWidget {
  const PasswordChangeHistoryCard({
    required this.account,
    this.showAccount = false,
    this.nowUtc,
    super.key,
  });
  final AccountRecord account;
  final bool showAccount;
  final DateTime Function()? nowUtc;

  @override
  Widget build(BuildContext context) {
    final history = account.passwordChangeHistory;
    final latest = history.lastOrNull;
    final now = (nowUtc?.call() ?? DateTime.now()).toLocal();
    final elapsed = latest == null
        ? null
        : _calendarDays(latest.changedAtUtc.toLocal(), now);
    return CardockSurfaceCard(
      key: ValueKey('password-history-${account.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            showAccount ? account.platformName : context.tr('密码变更记录'),
            translate: false,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (showAccount)
            Text(
              account.loginAccount ?? account.username ?? context.tr('未填写'),
              translate: false,
            ),
          const SizedBox(height: 8),
          Text(
            context.tr('已记录{count}次密码变更', {'count': history.length}),
            translate: false,
          ),
          if (latest == null)
            const Text('首次录入不计次，尚未记录后续变更。')
          else ...[
            Text(
              context.tr('最近变更：{date}', {
                'date': _dateTime(context, latest.changedAtUtc),
              }),
              translate: false,
            ),
            if (elapsed != null && elapsed >= 0)
              Text(
                context.tr('距上次变更{days}天', {'days': elapsed}),
                translate: false,
              ),
            TextButton.icon(
              key: ValueKey('view-password-history-${account.id}'),
              onPressed: () => _showHistory(context),
              icon: const Icon(Icons.history),
              label: const Text('查看变更日期'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showHistory(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: .8,
      child: Column(
        children: [
          ListTile(
            title: Text(account.platformName, translate: false),
            subtitle: Text(
              [
                account.category,
                account.loginAccount ?? account.username,
              ].whereType<String>().join(' · '),
              translate: false,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              tooltip: context.tr('关闭'),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: account.passwordChangeHistory.length,
              itemBuilder: (context, index) {
                final event =
                    account.passwordChangeHistory[account
                            .passwordChangeHistory
                            .length -
                        1 -
                        index];
                final previous = event.previousStoredAtUtc;
                final days = previous == null
                    ? null
                    : _calendarDays(
                        previous.toLocal(),
                        event.changedAtUtc.toLocal(),
                      );
                return ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(
                    _dateTime(context, event.changedAtUtc),
                    translate: false,
                  ),
                  subtitle: Text(
                    days == null || days < 0
                        ? context.tr('已保存新的密码')
                        : context.tr('距前次保存{days}天', {'days': days}),
                    translate: false,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

int _calendarDays(DateTime earlier, DateTime later) => DateTime.utc(
  later.year,
  later.month,
  later.day,
).difference(DateTime.utc(earlier.year, earlier.month, earlier.day)).inDays;

String _dateTime(BuildContext context, DateTime utc) {
  final date = utc.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${localizedRecordDate(context.l10n.language, date)} ${pad(date.hour)}:${pad(date.minute)}:${pad(date.second)}';
}
