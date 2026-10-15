import 'subscription_search_panel.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../../../l10n/translations_records.dart';

import '../../../core/preferences/record_display_mode.dart';
import '../../../core/preferences/record_sort_mode.dart';
import '../../../core/theme/cardock_tokens.dart';
import '../../../shared/widgets/cardock_platform_icon.dart';
import '../../../shared/widgets/cardock_ui.dart';
import '../../../shared/widgets/empty_state_card.dart';
import '../../accounts/domain/account_record.dart';
import '../domain/subscription_list_preset.dart';
import '../domain/subscription_expense_record.dart';
import '../domain/subscription_record.dart';

typedef SubscriptionRecordAction =
    Future<bool> Function(SubscriptionRecord subscription);
typedef SubscriptionRenewalAction =
    Future<bool> Function(
      SubscriptionRecord subscription, {
      SubscriptionExpenseDraft? expense,
    });
typedef SubscriptionSnoozeAction =
    Future<bool> Function(
      SubscriptionRecord subscription,
      SubscriptionSnoozeTarget target,
    );
typedef SubscriptionCancelAction =
    Future<bool> Function(
      SubscriptionRecord subscription, {
      DateTime? accessEndsOn,
    });

enum _SnoozeChoice {
  oneHour,
  fiveHours,
  tenHours,
  tomorrow,
  threeDays,
  sevenDays,
  customDate,
}

final class _RenewalDecision {
  const _RenewalDecision({this.expense});

  final SubscriptionExpenseDraft? expense;
}

class _RenewalExpenseDialog extends StatefulWidget {
  const _RenewalExpenseDialog({required this.subscription});

  final SubscriptionRecord subscription;

  @override
  State<_RenewalExpenseDialog> createState() => _RenewalExpenseDialogState();
}

class _RenewalExpenseDialogState extends State<_RenewalExpenseDialog> {
  late final TextEditingController _amountController;
  late final TextEditingController _currencyController;
  late final TextEditingController _categoryController;
  DateTime _occurredOn = DateUtils.dateOnly(DateTime.now());
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.subscription.amount ?? '',
    );
    _currencyController = TextEditingController(
      text: widget.subscription.currency,
    );
    _categoryController = TextEditingController(
      text: widget.subscription.expenseCategory ?? '',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _currencyController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredOn,
      firstDate: DateTime(1970),
      lastDate: DateTime(2300, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() => _occurredOn = DateUtils.dateOnly(picked));
    }
  }

  void _submit() {
    if (_amountController.text.trim().isEmpty &&
        widget.subscription.amount == null) {
      Navigator.pop(context, const _RenewalDecision());
      return;
    }
    try {
      final expense = SubscriptionExpenseDraft(
        subscriptionId: widget.subscription.id,
        serviceName: widget.subscription.serviceName,
        occurredOn: _occurredOn,
        amount: _amountController.text.trim().isEmpty
            ? widget.subscription.amount!
            : _amountController.text,
        currency: _currencyController.text,
        kind: SubscriptionExpenseKind.payment,
        expenseCategory: _categoryController.text,
        scheduledRenewalOn: widget.subscription.nextRenewalOn,
      );
      Navigator.pop(context, _RenewalDecision(expense: expense));
    } on ArgumentError catch (error) {
      setState(() => _error = error.message?.toString() ?? '费用内容无效。');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('确认已续费？'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr(
                '本机日期将从{date}只推进一个{cycle}周期。此操作不会向平台付款。',
                <String, Object?>{
                  'date': localizedRecordDate(
                    context.l10n.language,
                    widget.subscription.nextRenewalOn,
                  ),
                  'cycle': localizedSubscriptionCycle(
                    context.l10n.language,
                    widget.subscription.cycleUnit,
                    widget.subscription.cycleCount,
                  ),
                },
              ),
              translate: false,
            ),
            const SizedBox(height: 12),
            const Text('续费自动按已录入金额计入支出，也可修改本次实际金额。'),
            ...[
              TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  context.tr('支付日期：{date}', <String, Object?>{
                    'date': localizedRecordDate(
                      context.l10n.language,
                      _occurredOn,
                    ),
                  }),
                  translate: false,
                ),
              ),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: '实际支付金额'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _currencyController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: '币种'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: '费用分类',
                  hintText: '例如：影音娱乐、云服务',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确认已续费')),
      ],
    );
  }
}

List<SubscriptionRecord> sortSubscriptionsForDisplay({
  required Iterable<SubscriptionRecord> subscriptions,
  required RecordSortMode sortMode,
  Iterable<AccountRecord> accounts = const [],
}) {
  final result = subscriptions.toList();
  final accountsById = {for (final account in accounts) account.id: account};
  final originalIndex = <String, int>{
    for (var index = 0; index < result.length; index += 1)
      result[index].id: index,
  };

  int originalOrder(SubscriptionRecord left, SubscriptionRecord right) =>
      originalIndex[left.id]!.compareTo(originalIndex[right.id]!);

  int compareRenewal(SubscriptionRecord left, SubscriptionRecord right) {
    final leftCancelled = left.status == SubscriptionStatus.cancelled;
    final rightCancelled = right.status == SubscriptionStatus.cancelled;
    if (leftCancelled != rightCancelled) {
      return leftCancelled ? 1 : -1;
    }
    final compared = left.nextRenewalOn.compareTo(right.nextRenewalOn);
    return compared == 0 ? originalOrder(left, right) : compared;
  }

  int compareName(SubscriptionRecord left, SubscriptionRecord right) {
    final compared = left.serviceName.toLowerCase().compareTo(
      right.serviceName.toLowerCase(),
    );
    if (compared != 0) {
      return compared;
    }
    final exact = left.serviceName.compareTo(right.serviceName);
    return exact == 0 ? originalOrder(left, right) : exact;
  }

  int compareAccount(SubscriptionRecord left, SubscriptionRecord right) {
    final a = accountsById[left.accountId];
    final b = accountsById[right.accountId];
    if (a == null || b == null) {
      if (a != null) return -1;
      if (b != null) return 1;
      return compareName(left, right);
    }
    for (final pair in [
      (a.category ?? '', b.category ?? ''),
      (a.platformName, b.platformName),
      (a.loginAccount ?? a.username ?? '', b.loginAccount ?? b.username ?? ''),
      (a.id, b.id),
    ]) {
      final order = pair.$1.toLowerCase().compareTo(pair.$2.toLowerCase());
      if (order != 0) return order;
      final exact = pair.$1.compareTo(pair.$2);
      if (exact != 0) return exact;
    }
    return compareRenewal(left, right);
  }

  result.sort(switch (sortMode) {
    RecordSortMode.renewalSoonest => compareRenewal,
    RecordSortMode.newestAdded => (left, right) => originalOrder(right, left),
    RecordSortMode.oldestAdded => originalOrder,
    RecordSortMode.nameAscending => compareName,
    RecordSortMode.accountCategory => compareAccount,
  });
  return result;
}

class SubscriptionsPage extends StatelessWidget {
  const SubscriptionsPage({
    required this.accounts,
    required this.subscriptions,
    this.onAddSubscription,
    this.onEditSubscription,
    this.displayMode = RecordDisplayMode.expandedCards,
    this.sortMode = RecordSortMode.renewalSoonest,
    this.filterPreset,
    this.onClearFilter,
    this.readOnly = false,
    this.onOpenSubscription,
    this.onOpenCostStats,
    this.onOpenAttention,
    this.onMarkRenewed,
    this.onMarkRenewedWithExpense,
    this.onSnoozeReminder,
    this.onCancelSubscription,
    this.onRestoreSubscription,
    this.onDeleteSubscription,
    this.onSortModeChanged,
    super.key,
  });

  final bool readOnly;
  final List<AccountRecord> accounts;
  final List<SubscriptionRecord> subscriptions;
  final VoidCallback? onAddSubscription;
  final ValueChanged<SubscriptionRecord>? onEditSubscription;
  final RecordDisplayMode displayMode;
  final RecordSortMode sortMode;
  final SubscriptionListPreset? filterPreset;
  final VoidCallback? onClearFilter;
  final ValueChanged<SubscriptionRecord>? onOpenSubscription;
  final VoidCallback? onOpenCostStats;
  final VoidCallback? onOpenAttention;
  final SubscriptionRecordAction? onMarkRenewed;
  final SubscriptionRenewalAction? onMarkRenewedWithExpense;
  final SubscriptionSnoozeAction? onSnoozeReminder;
  final SubscriptionCancelAction? onCancelSubscription;
  final SubscriptionRecordAction? onRestoreSubscription;
  final SubscriptionRecordAction? onDeleteSubscription;
  final ValueChanged<RecordSortMode>? onSortModeChanged;

  @override
  Widget build(BuildContext context) => SubscriptionSearchPanel(
    records: subscriptions,
    accounts: accounts,
    readOnly: readOnly,
    builder: (context, filtered, active) =>
        _buildContent(context, filtered, active),
  );

  Widget _buildContent(
    BuildContext context,
    List<SubscriptionRecord> subscriptions,
    bool searching,
  ) {
    final today = DateUtils.dateOnly(DateTime.now());
    final accountById = <String, AccountRecord>{
      for (final account in accounts) account.id: account,
    };
    if (searching) {
      final records = sortSubscriptionsForDisplay(
        accounts: readOnly ? const [] : accounts,
        subscriptions: filterPreset == null
            ? subscriptions
            : subscriptionsForPreset(
                subscriptions,
                filterPreset!,
                today: today,
              ),
        sortMode: sortMode,
      );
      return Column(
        children: [
          _SubscriptionSortMenu(
            subscriptionCount: records.length,
            sortMode: sortMode,
            onSortModeChanged: onSortModeChanged,
            onOpenCostStats: onOpenCostStats,
            onOpenAttention: onOpenAttention,
          ),
          Expanded(
            child: _SubscriptionList(
              label: context.tr('搜索结果'),
              records: records,
              accountById: accountById,
              hasAccounts: accounts.isNotEmpty,
              onAddSubscription: onAddSubscription,
              onEditSubscription: onEditSubscription,
              onMarkRenewed: onMarkRenewed,
              onMarkRenewedWithExpense: onMarkRenewedWithExpense,
              onSnoozeReminder: onSnoozeReminder,
              onCancelSubscription: onCancelSubscription,
              onRestoreSubscription: onRestoreSubscription,
              onDeleteSubscription: onDeleteSubscription,
              displayMode: displayMode,
              onOpenSubscription: onOpenSubscription,
              groupByAccount:
                  !readOnly && sortMode == RecordSortMode.accountCategory,
              groupByRenewalDate: sortMode == RecordSortMode.renewalSoonest,
            ),
          ),
        ],
      );
    }
    if (filterPreset case final preset?) {
      final presetLabel = context.tr(preset.label);
      final filtered = sortSubscriptionsForDisplay(
        accounts: readOnly ? const [] : accounts,
        subscriptions: subscriptionsForPreset(
          subscriptions,
          preset,
          today: today,
        ),
        sortMode: sortMode,
      );
      return Column(
        key: const ValueKey<String>('subscriptions-page'),
        children: [
          const _SubscriptionPrivacyNotice(),
          _SubscriptionSortMenu(
            subscriptionCount: subscriptions.length,
            sortMode: sortMode,
            onSortModeChanged: onSortModeChanged,
            onOpenCostStats: onOpenCostStats,
            onOpenAttention: onOpenAttention,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                key: const ValueKey<String>('subscription-filter-banner'),
                leading: const Icon(Icons.filter_alt_outlined),
                title: Text(presetLabel, translate: false),
                subtitle: Text(
                  context.tr('共{countLabel}，点击记录查看完整详情', <String, Object?>{
                    'countLabel': localizedRecordCount(
                      context.l10n.language,
                      filtered.length,
                    ),
                  }),
                  translate: false,
                ),
                trailing: onClearFilter == null
                    ? null
                    : TextButton(
                        key: const ValueKey<String>(
                          'clear-subscription-filter',
                        ),
                        onPressed: onClearFilter,
                        child: const Text('清除筛选'),
                      ),
              ),
            ),
          ),
          Expanded(
            child: _SubscriptionList(
              label: presetLabel,
              records: filtered,
              accountById: accountById,
              hasAccounts: accounts.isNotEmpty,
              onAddSubscription: onAddSubscription,
              onEditSubscription: onEditSubscription,
              onMarkRenewed: onMarkRenewed,
              onMarkRenewedWithExpense: onMarkRenewedWithExpense,
              onSnoozeReminder: onSnoozeReminder,
              onCancelSubscription: onCancelSubscription,
              onRestoreSubscription: onRestoreSubscription,
              onDeleteSubscription: onDeleteSubscription,
              displayMode: displayMode,
              onOpenSubscription: onOpenSubscription,
              groupByAccount:
                  !readOnly && sortMode == RecordSortMode.accountCategory,
              groupByRenewalDate: sortMode == RecordSortMode.renewalSoonest,
            ),
          ),
        ],
      );
    }
    final upcoming = sortSubscriptionsForDisplay(
      accounts: readOnly ? const [] : accounts,
      subscriptions: subscriptions.where(
        (subscription) =>
            subscription.status == SubscriptionStatus.active &&
            !subscription.nextRenewalOn.isBefore(today),
      ),
      sortMode: sortMode,
    );
    final all = sortSubscriptionsForDisplay(
      accounts: readOnly ? const [] : accounts,
      subscriptions: subscriptions,
      sortMode: sortMode,
    );
    final expired = sortSubscriptionsForDisplay(
      accounts: readOnly ? const [] : accounts,
      subscriptions: subscriptions.where(
        (subscription) =>
            subscription.status == SubscriptionStatus.expired ||
            (subscription.status == SubscriptionStatus.active &&
                subscription.nextRenewalOn.isBefore(today)),
      ),
      sortMode: sortMode,
    );
    final cancelled = sortSubscriptionsForDisplay(
      accounts: readOnly ? const [] : accounts,
      subscriptions: subscriptions.where(
        (subscription) => subscription.status == SubscriptionStatus.cancelled,
      ),
      sortMode: sortMode,
    );

    final tabs = <({String label, List<SubscriptionRecord> records})>[
      (label: context.tr('即将续费'), records: upcoming),
      (label: context.tr('全部订阅'), records: all),
      (label: context.tr('已到期'), records: expired),
      (label: context.tr('已取消'), records: cancelled),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        key: const ValueKey<String>('subscriptions-page'),
        children: [
          const _SubscriptionPrivacyNotice(),
          _SubscriptionSortMenu(
            subscriptionCount: subscriptions.length,
            sortMode: sortMode,
            onSortModeChanged: onSortModeChanged,
            onOpenCostStats: onOpenCostStats,
            onOpenAttention: onOpenAttention,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.cardockTheme.palette.surfaceAlt,
                borderRadius: BorderRadius.circular(CardockRadius.control),
              ),
              child: TabBar(
                isScrollable: false,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: context.cardockTheme.palette.surface,
                  borderRadius: BorderRadius.circular(CardockRadius.control),
                  border: Border.all(
                    color: context.cardockTheme.palette.border,
                  ),
                ),
                tabs: [for (final tab in tabs) Tab(text: tab.label)],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final tab in tabs)
                  _SubscriptionList(
                    label: tab.label,
                    records: tab.records,
                    accountById: accountById,
                    hasAccounts: accounts.isNotEmpty,
                    onAddSubscription: onAddSubscription,
                    onEditSubscription: onEditSubscription,
                    onMarkRenewed: onMarkRenewed,
                    onMarkRenewedWithExpense: onMarkRenewedWithExpense,
                    onSnoozeReminder: onSnoozeReminder,
                    onCancelSubscription: onCancelSubscription,
                    onRestoreSubscription: onRestoreSubscription,
                    onDeleteSubscription: onDeleteSubscription,
                    displayMode: displayMode,
                    onOpenSubscription: onOpenSubscription,
                    groupByAccount:
                        !readOnly && sortMode == RecordSortMode.accountCategory,
                    groupByRenewalDate:
                        sortMode == RecordSortMode.renewalSoonest,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionSortMenu extends StatelessWidget {
  const _SubscriptionSortMenu({
    required this.subscriptionCount,
    required this.sortMode,
    required this.onSortModeChanged,
    required this.onOpenCostStats,
    this.onOpenAttention,
  });

  final int subscriptionCount;
  final RecordSortMode sortMode;
  final ValueChanged<RecordSortMode>? onSortModeChanged;
  final VoidCallback? onOpenCostStats;
  final VoidCallback? onOpenAttention;

  @override
  Widget build(BuildContext context) {
    Widget sortControl({required bool compact}) => Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        PopupMenuButton<RecordSortMode>(
          key: const ValueKey<String>('subscription-sort-mode-menu'),
          initialValue: sortMode,
          enabled: onSortModeChanged != null,
          tooltip: context.tr(
            onSortModeChanged == null ? '使用真实主密码后可修改并保存排序' : '选择订阅排序方式',
          ),
          onSelected: onSortModeChanged,
          itemBuilder: (context) => [
            for (final mode in RecordSortMode.values)
              PopupMenuItem<RecordSortMode>(
                key: ValueKey<String>('subscription-sort-${mode.name}'),
                value: mode,
                child: Text(mode.label),
              ),
          ],
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: CardockLayout.minimumTapTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort, size: 20),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      compact
                          ? context.tr('排序')
                          : context.tr('排序：{mode}', <String, Object?>{
                              'mode': context.tr(sortMode.label),
                            }),
                      translate: false,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          final count = Text(
            compact
                ? context.tr('共{countLabel}', <String, Object?>{
                    'countLabel': localizedSubscriptionCount(
                      context.l10n.language,
                      subscriptionCount,
                    ),
                  })
                : context.tr('订阅统计 · 共{countLabel}', <String, Object?>{
                    'countLabel': localizedSubscriptionCount(
                      context.l10n.language,
                      subscriptionCount,
                    ),
                  }),
            translate: false,
            key: const ValueKey<String>('subscription-total-count'),
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: count),
                  if (onOpenCostStats != null)
                    IconButton(
                      key: const ValueKey<String>(
                        'open-subscription-cost-stats',
                      ),
                      onPressed: onOpenCostStats,
                      tooltip: context.tr('费用统计'),
                      icon: const Icon(Icons.insights_outlined),
                    ),
                  if (onOpenAttention != null)
                    IconButton(
                      key: const ValueKey('open-subscription-attention'),
                      onPressed: onOpenAttention,
                      tooltip: context.tr('待处理中心'),
                      icon: const Icon(Icons.pending_actions_outlined),
                    ),
                  Flexible(child: sortControl(compact: compact)),
                ],
              ),
              if (onSortModeChanged == null)
                Text(
                  '订阅只读视图不可保存排序；请使用真实主密码解锁。',
                  key: const ValueKey<String>(
                    'subscription-sort-read-only-hint',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.end,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SubscriptionPrivacyNotice extends StatelessWidget {
  const _SubscriptionPrivacyNotice();

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 5),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 14,
            color: palette.fieldSubscription,
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              '本地加密 · 汇率合计使用离线参考值',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionRailEntry extends StatelessWidget {
  const _SubscriptionRailEntry({
    required this.date,
    required this.showDate,
    required this.child,
    required this.isLast,
  });

  final DateTime date;
  final bool showDate;
  final Widget child;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final textScaler = MediaQuery.textScalerOf(context);
    final railHeight =
        102.0 + ((textScaler.scale(10) / 10 - 1).clamp(0.0, 1.0) * 80);
    final today = DateUtils.dateOnly(DateTime.now());
    final value = DateUtils.dateOnly(date);
    final upcoming = !value.isBefore(today);
    final nodeColor = upcoming ? palette.statusRenewSoon : palette.textTertiary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 38,
          height: railHeight,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              if (!isLast)
                Positioned(
                  top: 28,
                  bottom: -8,
                  child: Container(width: 1.5, color: palette.borderStrong),
                ),
              Positioned(
                top: 29,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: nodeColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              if (showDate)
                Positioned(
                  top: 1,
                  left: 0,
                  right: 7,
                  child: Column(
                    children: [
                      Text(
                        value.day.toString().padLeft(2, '0'),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 20,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                      Text(
                        localizedRecordMonth(
                          context.l10n.language,
                          value.month,
                        ),
                        translate: false,
                        style: TextStyle(
                          color: palette.textTertiary,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 1),
        Expanded(child: child),
      ],
    );
  }
}

String _subscriptionAccountHeading(
  BuildContext context,
  AccountRecord? account,
) {
  if (account == null) return context.tr('独立订阅');
  return [
    localizedAccountCategory(context.l10n.language, account.category ?? '其他'),
    account.platformName,
    account.loginAccount ?? account.username ?? '',
  ].where((part) => part.isNotEmpty).join(' · ');
}

class _SubscriptionList extends StatelessWidget {
  const _SubscriptionList({
    required this.label,
    required this.records,
    required this.accountById,
    required this.hasAccounts,
    required this.onAddSubscription,
    required this.onEditSubscription,
    required this.onMarkRenewed,
    required this.onMarkRenewedWithExpense,
    required this.onSnoozeReminder,
    required this.onCancelSubscription,
    required this.onRestoreSubscription,
    required this.onDeleteSubscription,
    required this.displayMode,
    required this.onOpenSubscription,
    required this.groupByRenewalDate,
    this.groupByAccount = false,
  });

  final String label;
  final List<SubscriptionRecord> records;
  final Map<String, AccountRecord> accountById;
  final bool hasAccounts;
  final VoidCallback? onAddSubscription;
  final ValueChanged<SubscriptionRecord>? onEditSubscription;
  final SubscriptionRecordAction? onMarkRenewed;
  final SubscriptionRenewalAction? onMarkRenewedWithExpense;
  final SubscriptionSnoozeAction? onSnoozeReminder;
  final SubscriptionCancelAction? onCancelSubscription;
  final SubscriptionRecordAction? onRestoreSubscription;
  final SubscriptionRecordAction? onDeleteSubscription;
  final RecordDisplayMode displayMode;
  final ValueChanged<SubscriptionRecord>? onOpenSubscription;
  final bool groupByRenewalDate;
  final bool groupByAccount;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
        children: [
          EmptyStateCard(
            icon: Icons.event_note_outlined,
            title: context.tr('暂无{label}记录', <String, Object?>{'label': label}),
            message: hasAccounts
                ? '可以新增独立订阅，也可以关联到现有账号。'
                : '可以直接新增独立订阅，以后再按需关联账号。',
            action: onAddSubscription != null
                ? FilledButton.icon(
                    key: const ValueKey<String>('empty-add-subscription'),
                    onPressed: onAddSubscription,
                    icon: const Icon(Icons.add),
                    label: const Text('新增订阅'),
                  )
                : null,
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 112),
      children: [
        for (var index = 0; index < records.length; index += 1) ...[
          if (groupByAccount &&
              (index == 0 ||
                  records[index - 1].accountId != records[index].accountId))
            Padding(
              key: ValueKey(
                'subscription-account-group-${records[index].accountId ?? 'independent'}',
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _subscriptionAccountHeading(
                  context,
                  accountById[records[index].accountId],
                ),
                translate: false,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          _SubscriptionRailEntry(
            date: records[index].nextRenewalOn,
            showDate:
                !groupByRenewalDate ||
                index == 0 ||
                !DateUtils.isSameDay(
                  records[index - 1].nextRenewalOn,
                  records[index].nextRenewalOn,
                ),
            isLast: index == records.length - 1,
            child: SubscriptionRecordCard(
              subscription: records[index],
              account: accountById[records[index].accountId],
              displayMode: displayMode,
              onOpen: onOpenSubscription == null
                  ? null
                  : () => onOpenSubscription!(records[index]),
              onEdit: onEditSubscription == null
                  ? null
                  : () => onEditSubscription!(records[index]),
              onMarkRenewed: onMarkRenewed,
              onMarkRenewedWithExpense: onMarkRenewedWithExpense,
              onSnoozeReminder: onSnoozeReminder,
              onCancelSubscription: onCancelSubscription,
              onRestoreSubscription: onRestoreSubscription,
              onDeleteSubscription: onDeleteSubscription,
            ),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class SubscriptionRecordCard extends StatefulWidget {
  const SubscriptionRecordCard({
    required this.subscription,
    required this.account,
    this.onEdit,
    required this.onMarkRenewed,
    this.onMarkRenewedWithExpense,
    required this.onSnoozeReminder,
    required this.onCancelSubscription,
    required this.onRestoreSubscription,
    required this.onDeleteSubscription,
    this.displayMode = RecordDisplayMode.expandedCards,
    this.showFullDetails = false,
    this.onOpen,
    super.key,
  });

  final SubscriptionRecord subscription;
  final AccountRecord? account;
  final VoidCallback? onEdit;
  final SubscriptionRecordAction? onMarkRenewed;
  final SubscriptionRenewalAction? onMarkRenewedWithExpense;
  final SubscriptionSnoozeAction? onSnoozeReminder;
  final SubscriptionCancelAction? onCancelSubscription;
  final SubscriptionRecordAction? onRestoreSubscription;
  final SubscriptionRecordAction? onDeleteSubscription;
  final RecordDisplayMode displayMode;
  final bool showFullDetails;
  final VoidCallback? onOpen;

  @override
  State<SubscriptionRecordCard> createState() => _SubscriptionRecordCardState();
}

class _SubscriptionRecordCardState extends State<SubscriptionRecordCard> {
  bool _busy = false;
  bool _renewalDialogOpen = false;
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.displayMode != RecordDisplayMode.collapsibleCards;
  }

  @override
  void didUpdateWidget(covariant SubscriptionRecordCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.displayMode != widget.displayMode) {
      _expanded = widget.displayMode != RecordDisplayMode.collapsibleCards;
    }
  }

  Future<void> _perform(
    Future<bool> Function() operation,
    String successMessage,
  ) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    var succeeded = false;
    try {
      succeeded = await operation();
    } on Object {
      succeeded = false;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(succeeded ? successMessage : '操作未保存，请稍后重试。'),
          translate: false,
        ),
      ),
    );
  }

  Future<void> _markRenewed() async {
    if (_busy || _renewalDialogOpen) return;
    _renewalDialogOpen = true;
    final subscription = widget.subscription;
    try {
      final callback = widget.onMarkRenewed;
      final callbackWithExpense = widget.onMarkRenewedWithExpense;
      if (callback == null && callbackWithExpense == null) {
        return;
      }
      if (subscription.renewalHistory.any(
        (event) => DateUtils.isSameDay(event.recordedOn, DateTime.now()),
      )) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            key: const ValueKey('same-day-renewal-confirmation'),
            title: const Text('当日已续费'),
            content: Text(
              context.tr('今天已经记录过续费，下次续费日期为{date}。继续会再延后一个计费周期并新增一笔支出，是否继续？', {
                'date': localizedRecordDate(
                  context.l10n.language,
                  subscription.nextRenewalOn,
                ),
              }),
              translate: false,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const ValueKey('confirm-repeat-renewal'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('继续续费'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      final decision = await showDialog<_RenewalDecision>(
        context: context,
        builder: (context) => _RenewalExpenseDialog(subscription: subscription),
      );
      if (decision != null && mounted) {
        await _perform(
          () => callbackWithExpense != null
              ? callbackWithExpense(subscription, expense: decision.expense)
              : callback!(subscription),
          callbackWithExpense == null
              ? '已推进一期续费日期。'
              : decision.expense == null
              ? '已推进一期续费日期；本次未记录确认支出。'
              : '已推进一期续费日期并保存确认支出。',
        );
      }
    } finally {
      _renewalDialogOpen = false;
    }
  }

  Future<void> _snooze() async {
    final callback = widget.onSnoozeReminder;
    if (callback == null) {
      return;
    }
    final choice = await showDialog<_SnoozeChoice>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('延后本机提醒'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _SnoozeChoice.oneHour),
            child: const Text('1小时后提醒'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _SnoozeChoice.fiveHours),
            child: const Text('5小时后提醒'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _SnoozeChoice.tenHours),
            child: const Text('10小时后提醒'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _SnoozeChoice.tomorrow),
            child: const Text('明天提醒'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _SnoozeChoice.threeDays),
            child: const Text('3天后提醒'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _SnoozeChoice.sevenDays),
            child: const Text('7天后提醒'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _SnoozeChoice.customDate),
            child: const Text('选择日期…'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) {
      return;
    }
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    SubscriptionSnoozeTarget? target;
    switch (choice) {
      case _SnoozeChoice.oneHour:
        target = SubscriptionSnoozeTarget.after(
          const Duration(hours: 1),
          now: now,
        );
      case _SnoozeChoice.fiveHours:
        target = SubscriptionSnoozeTarget.after(
          const Duration(hours: 5),
          now: now,
        );
      case _SnoozeChoice.tenHours:
        target = SubscriptionSnoozeTarget.after(
          const Duration(hours: 10),
          now: now,
        );
      case _SnoozeChoice.tomorrow:
        target = SubscriptionSnoozeTarget.calendarDate(
          today.add(const Duration(days: 1)),
        );
      case _SnoozeChoice.threeDays:
        target = SubscriptionSnoozeTarget.calendarDate(
          today.add(const Duration(days: 3)),
        );
      case _SnoozeChoice.sevenDays:
        target = SubscriptionSnoozeTarget.calendarDate(
          today.add(const Duration(days: 7)),
        );
      case _SnoozeChoice.customDate:
        final date = await showDatePicker(
          context: context,
          initialDate: today.add(const Duration(days: 1)),
          firstDate: today,
          lastDate: DateTime(2300, 12, 31),
          helpText: context.tr('选择再次提醒日期'),
        );
        if (date != null) {
          target = SubscriptionSnoozeTarget.calendarDate(date);
        }
    }
    if (target != null && mounted) {
      await _perform(
        () => callback(widget.subscription, target!),
        '已更新本机提醒时间。',
      );
    }
  }

  Future<void> _cancel() async {
    final callback = widget.onCancelSubscription;
    if (callback == null) {
      return;
    }
    final choice = await showDialog<_CancelChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('记录为已取消'),
        content: const Text('这只会更新本机记录并停止本机提醒，不会在对应平台取消订阅、停止扣费或申请退款。请仍到平台核实。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _CancelChoice.withAccessEnd),
            child: const Text('选择权益截止日'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, _CancelChoice.withoutAccessEnd),
            child: const Text('仅记录取消'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) {
      return;
    }
    DateTime? accessEndsOn;
    if (choice == _CancelChoice.withAccessEnd) {
      final today = DateUtils.dateOnly(DateTime.now());
      accessEndsOn = await showDatePicker(
        context: context,
        initialDate: widget.subscription.nextRenewalOn.isBefore(today)
            ? today
            : widget.subscription.nextRenewalOn,
        firstDate: today,
        lastDate: DateTime(2300, 12, 31),
        helpText: context.tr('选择权益截止日期'),
      );
      if (accessEndsOn == null || !mounted) {
        return;
      }
    }
    await _perform(
      () => callback(widget.subscription, accessEndsOn: accessEndsOn),
      '已在本机记录取消；请继续到平台核实。',
    );
  }

  Future<void> _restore() async {
    final callback = widget.onRestoreSubscription;
    if (callback == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复本机订阅记录？'),
        content: const Text('恢复后状态改为正常并重新启用本机提醒，不会在平台重新订阅。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复记录'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _perform(() => callback(widget.subscription), '已恢复本机订阅记录。');
    }
  }

  Future<void> _delete() async {
    final callback = widget.onDeleteSubscription;
    if (callback == null || _busy) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移入回收站？'),
        content: const Text('记录将在回收站保留 30 天；这不会在对应平台取消订阅或停止扣费。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          FilledButton(
            key: ValueKey<String>(
              'confirm-delete-subscription-${widget.subscription.id}',
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移入回收站'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _perform(() => callback(widget.subscription), '订阅记录已移入回收站。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final subscription = widget.subscription;
    final plan = subscription.planName;
    final amount = subscription.amount;
    final active = subscription.status == SubscriptionStatus.active;
    final cancelled = subscription.status == SubscriptionStatus.cancelled;
    final visualStatus = _subscriptionVisualStatus(context, subscription);
    final amountLabel = amount == null
        ? context.tr('金额未填写')
        : '${subscription.currency} $amount';
    final accountLabel = subscription.accountId == null
        ? context.tr('独立订阅')
        : widget.account?.platformName ?? context.tr('关联账号不可用');
    final renewalDate = localizedRecordDate(
      context.l10n.language,
      subscription.nextRenewalOn,
    );
    final cycleLabel = localizedSubscriptionCycle(
      context.l10n.language,
      subscription.cycleUnit,
      subscription.cycleCount,
    );
    if (!widget.showFullDetails &&
        widget.displayMode != RecordDisplayMode.collapsibleCards) {
      return CardockSurfaceCard(
        key: ValueKey<String>('subscription-card-${subscription.id}'),
        padding: EdgeInsets.zero,
        onTap: widget.onOpen,
        semanticLabel: context.tr(
          '{service}，{account}，{amount}，{date}，{status}',
          <String, Object?>{
            'service': subscription.serviceName,
            'account': accountLabel,
            'amount': amountLabel,
            'date': renewalDate,
            'status': visualStatus.label,
          },
        ),
        child: _CompactSubscriptionRow(
          subscription: subscription,
          accountLabel: accountLabel,
          amountLabel: amountLabel,
          visualStatus: visualStatus,
          showChevron: widget.onOpen != null,
          comfortable: widget.displayMode == RecordDisplayMode.expandedCards,
        ),
      );
    }

    final showDetails = widget.showFullDetails || _expanded;

    return CardockSurfaceCard(
      key: ValueKey<String>('subscription-card-${subscription.id}'),
      padding: EdgeInsets.zero,
      semanticLabel: context.tr('{service}，{status}', <String, Object?>{
        'service': subscription.serviceName,
        'status': visualStatus.label,
      }),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onOpen,
          borderRadius: BorderRadius.circular(CardockRadius.card),
          child: Padding(
            padding: const EdgeInsets.all(CardockLayout.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CardockResolvedPlatformIcon(
                      key: ValueKey<String>(
                        'subscription-brand-icon-${subscription.id}',
                      ),
                      name: subscription.serviceName,
                      size: 44,
                      role: CardockPlatformIconRole.subscription,
                      semanticLabel: context.tr('{name}图标', <String, Object?>{
                        'name': subscription.serviceName,
                      }),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subscription.serviceName,
                            translate: false,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            accountLabel,
                            translate: false,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (widget.displayMode ==
                        RecordDisplayMode.collapsibleCards)
                      IconButton(
                        key: ValueKey<String>(
                          'toggle-subscription-${subscription.id}',
                        ),
                        tooltip: context.tr(_expanded ? '折叠卡片' : '展开卡片'),
                        onPressed: _busy
                            ? null
                            : () => setState(() => _expanded = !_expanded),
                        icon: Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    CardockStatusPill(
                      status: visualStatus.status,
                      label: visualStatus.label,
                    ),
                    if (plan != null) _InfoCapsule(label: plan),
                    _InfoCapsule(label: amountLabel),
                    _InfoCapsule(label: cycleLabel),
                  ],
                ),
                if (showDetails) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      children: [
                        if (widget.onEdit != null)
                          IconButton(
                            key: ValueKey<String>(
                              'edit-subscription-${subscription.id}',
                            ),
                            tooltip: context.tr('编辑订阅'),
                            onPressed: _busy ? null : widget.onEdit,
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        if (widget.onDeleteSubscription != null)
                          IconButton(
                            key: ValueKey<String>(
                              'delete-subscription-${subscription.id}',
                            ),
                            tooltip: context.tr('删除订阅记录'),
                            onPressed: _busy ? null : _delete,
                            icon: const Icon(Icons.delete_outline),
                          ),
                      ],
                    ),
                  ),
                  CardockFieldRow(
                    icon: Icons.event_available_outlined,
                    color: palette.fieldSubscription,
                    label: '首次订阅：',
                    value: localizedRecordDate(
                      context.l10n.language,
                      subscription.firstSubscribedOn,
                    ),
                  ),
                  CardockFieldRow(
                    icon: Icons.event_repeat_outlined,
                    color:
                        visualStatus.status == CardockVisualStatus.renewToday ||
                            visualStatus.status == CardockVisualStatus.expired
                        ? palette.statusDanger
                        : palette.renewalAccent,
                    label: '下次续费：',
                    value: renewalDate,
                  ),
                  CardockFieldRow(
                    icon: Icons.autorenew_rounded,
                    color: palette.fieldSubscription,
                    label: '周期：',
                    value: cycleLabel,
                  ),
                  CardockFieldRow(
                    icon: Icons.autorenew_rounded,
                    color: palette.fieldSubscription,
                    label: '自动续费：',
                    value: context.tr(subscription.autoRenew ? '是' : '否'),
                  ),
                  CardockFieldRow(
                    icon: subscription.reminderEnabled
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                    color: palette.statusInformation,
                    label: '本机提醒：',
                    value: subscription.reminderEnabled
                        ? localizedDaysBefore(
                            context.l10n.language,
                            subscription.reminderDaysBefore,
                          )
                        : context.tr('已关闭'),
                  ),
                  if (subscription.snoozedUntil != null ||
                      subscription.snoozedUntilUtc != null)
                    CardockFieldRow(
                      icon: Icons.snooze_outlined,
                      color: palette.statusPaused,
                      label: '已延后到：',
                      value: subscription.snoozedUntilUtc == null
                          ? localizedRecordDate(
                              context.l10n.language,
                              subscription.snoozedUntil!,
                            )
                          : localizedRecordDateTime(
                              context.l10n.language,
                              subscription.snoozedUntilUtc!.toLocal(),
                            ),
                    ),
                  if (amount != null)
                    CardockFieldRow(
                      icon: Icons.payments_outlined,
                      color: palette.fieldCurrency,
                      label: '金额：',
                      value: '${subscription.currency} $amount',
                    ),
                  if (subscription.paymentMethod != null)
                    CardockFieldRow(
                      icon: Icons.account_balance_wallet_outlined,
                      color: palette.fieldPhone,
                      label: '支付方式：',
                      value: subscription.paymentMethod!,
                    ),
                  if (subscription.cancelledOn != null)
                    CardockFieldRow(
                      icon: Icons.block_outlined,
                      color: palette.statusCancelled,
                      label: '本机记录取消：',
                      value: localizedRecordDate(
                        context.l10n.language,
                        subscription.cancelledOn!,
                      ),
                    ),
                  if (subscription.accessEndsOn != null)
                    CardockFieldRow(
                      icon: Icons.event_busy_outlined,
                      color: palette.statusDanger,
                      label: '权益截止：',
                      value: localizedRecordDate(
                        context.l10n.language,
                        subscription.accessEndsOn!,
                      ),
                    ),
                  if (subscription.renewalHistory.isNotEmpty)
                    CardockFieldRow(
                      icon: Icons.history_rounded,
                      color: palette.fieldNote,
                      label: '已记录续费：',
                      value: localizedRenewalHistoryCount(
                        context.l10n.language,
                        subscription.renewalHistory.length,
                      ),
                    ),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (active &&
                          (widget.onMarkRenewed != null ||
                              widget.onMarkRenewedWithExpense != null))
                        FilledButton.tonalIcon(
                          key: ValueKey<String>(
                            'renew-subscription-${subscription.id}',
                          ),
                          onPressed: _busy ? null : _markRenewed,
                          icon: const Icon(Icons.event_repeat_outlined),
                          label: const Text('已续费'),
                        ),
                      if (active && widget.onSnoozeReminder != null)
                        OutlinedButton.icon(
                          key: ValueKey<String>(
                            'snooze-subscription-${subscription.id}',
                          ),
                          onPressed: _busy ? null : _snooze,
                          icon: const Icon(Icons.snooze_outlined),
                          label: const Text('延后提醒'),
                        ),
                      if (!cancelled && widget.onCancelSubscription != null)
                        TextButton.icon(
                          key: ValueKey<String>(
                            'cancel-subscription-${subscription.id}',
                          ),
                          onPressed: _busy ? null : _cancel,
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('记录取消'),
                        ),
                      if (cancelled && widget.onRestoreSubscription != null)
                        FilledButton.tonalIcon(
                          key: ValueKey<String>(
                            'restore-subscription-${subscription.id}',
                          ),
                          onPressed: _busy ? null : _restore,
                          icon: const Icon(Icons.restore_outlined),
                          label: const Text('恢复记录'),
                        ),
                      if (widget.onOpen != null)
                        TextButton.icon(
                          key: ValueKey<String>(
                            'open-subscription-${subscription.id}',
                          ),
                          onPressed: _busy ? null : widget.onOpen,
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('查看详情'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactSubscriptionRow extends StatelessWidget {
  const _CompactSubscriptionRow({
    required this.subscription,
    required this.accountLabel,
    required this.amountLabel,
    required this.visualStatus,
    required this.showChevron,
    this.comfortable = false,
  });

  final SubscriptionRecord subscription;
  final String accountLabel;
  final String amountLabel;
  final ({CardockVisualStatus status, String label}) visualStatus;
  final bool showChevron;
  final bool comfortable;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final statusColor = switch (visualStatus.status) {
      CardockVisualStatus.normal => palette.statusNormal,
      CardockVisualStatus.renewSoon => palette.statusRenewSoon,
      CardockVisualStatus.renewToday ||
      CardockVisualStatus.expired => palette.statusDanger,
      CardockVisualStatus.cancelled => palette.statusCancelled,
      CardockVisualStatus.paused => palette.statusPaused,
      CardockVisualStatus.information => palette.statusInformation,
    };
    final status = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _compactStatusIcon(visualStatus.status),
          size: 13,
          color: statusColor,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            visualStatus.label,
            translate: false,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
    final amount = Text(
      amountLabel,
      translate: false,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
    final renewalDate = Text(
      localizedRecordDate(context.l10n.language, subscription.nextRenewalOn),
      translate: false,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
    final identity = Row(
      children: [
        CardockResolvedPlatformIcon(
          key: ValueKey<String>('subscription-brand-icon-${subscription.id}'),
          name: subscription.serviceName,
          size: comfortable ? 38 : 36,
          role: CardockPlatformIconRole.subscription,
          semanticLabel: context.tr('{name}图标', <String, Object?>{
            'name': subscription.serviceName,
          }),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subscription.serviceName,
                translate: false,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                accountLabel,
                translate: false,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: comfortable ? 96 : 76),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: comfortable ? 12 : 10,
          vertical: comfortable ? 12 : 8,
        ),
        child: textScale > 1.5
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  identity,
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    runSpacing: 6,
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [amount, renewalDate, status],
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 126,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [amount, renewalDate, status],
                    ),
                  ),
                  if (showChevron) ...[
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ],
              ),
      ),
    );
  }
}

IconData _compactStatusIcon(CardockVisualStatus status) => switch (status) {
  CardockVisualStatus.normal => Icons.check_circle_outline_rounded,
  CardockVisualStatus.renewSoon => Icons.schedule_rounded,
  CardockVisualStatus.renewToday => Icons.today_rounded,
  CardockVisualStatus.expired => Icons.error_outline_rounded,
  CardockVisualStatus.cancelled => Icons.block_rounded,
  CardockVisualStatus.paused => Icons.pause_circle_outline_rounded,
  CardockVisualStatus.information => Icons.info_outline_rounded,
};

class _InfoCapsule extends StatelessWidget {
  const _InfoCapsule({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(CardockRadius.pill),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        label,
        translate: false,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

({CardockVisualStatus status, String label}) _subscriptionVisualStatus(
  BuildContext context,
  SubscriptionRecord subscription,
) {
  switch (subscription.status) {
    case SubscriptionStatus.cancelled:
      return (status: CardockVisualStatus.cancelled, label: context.tr('已取消'));
    case SubscriptionStatus.paused:
      return (status: CardockVisualStatus.paused, label: context.tr('已暂停'));
    case SubscriptionStatus.expired:
      return (status: CardockVisualStatus.expired, label: context.tr('已到期'));
    case SubscriptionStatus.active:
      final today = DateUtils.dateOnly(DateTime.now());
      final renewal = DateUtils.dateOnly(subscription.nextRenewalOn);
      final days = renewal.difference(today).inDays;
      if (days < 0) {
        return (
          status: CardockVisualStatus.expired,
          label: context.tr('逾期待确认'),
        );
      }
      if (days == 0) {
        return (
          status: CardockVisualStatus.renewToday,
          label: context.tr('今天续费'),
        );
      }
      if (days <= 30) {
        return (
          status: CardockVisualStatus.renewSoon,
          label: context.tr('{days}天后续费', <String, Object?>{'days': days}),
        );
      }
      return (
        status: CardockVisualStatus.normal,
        label: localizedSubscriptionStatus(
          context.l10n.language,
          SubscriptionStatus.active,
        ),
      );
  }
}

enum _CancelChoice { withoutAccessEnd, withAccessEnd }
