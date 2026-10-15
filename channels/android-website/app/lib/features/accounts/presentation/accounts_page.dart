import '../../../l10n/localized_material.dart';

import '../../../core/preferences/record_display_mode.dart';
import '../../../core/preferences/record_sort_mode.dart';
import '../../../core/theme/cardock_tokens.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/translations_records.dart';
import '../../../shared/widgets/empty_state_card.dart';
import '../../subscriptions/domain/subscription_record.dart';
import '../domain/account_record.dart';
import '../domain/account_analysis.dart';
import 'widgets/account_record_card.dart';

typedef AccountListAction = Future<void> Function(AccountRecord account);
typedef AccountListDeleteAction = Future<bool> Function(AccountRecord account);

const unclassifiedAccountCategory = '未分类';

String localizedAccountCategoryLabel(BuildContext context, String value) {
  if (value == '全部' ||
      value == unclassifiedAccountCategory ||
      accountCategories.contains(value)) {
    return context.tr(value);
  }
  return value;
}

final class AccountCategoryGroup {
  const AccountCategoryGroup({required this.label, required this.accounts});

  final String label;
  final List<AccountRecord> accounts;
}

List<AccountCategoryGroup> groupAccountsByCategory(
  Iterable<AccountRecord> accounts,
) {
  final grouped = <String, List<AccountRecord>>{};
  final labels = {
    for (final category in accountCategoryOptions(accounts))
      category.toLowerCase(): category,
  };
  for (final account in accounts) {
    final label =
        labels[account.category?.trim().toLowerCase()] ??
        unclassifiedAccountCategory;
    (grouped[label] ??= <AccountRecord>[]).add(account);
  }
  return <AccountCategoryGroup>[
    for (final entry in grouped.entries)
      AccountCategoryGroup(
        label: entry.key,
        accounts: List<AccountRecord>.unmodifiable(entry.value),
      ),
  ];
}

List<AccountRecord> sortAccountsForDisplay({
  required Iterable<AccountRecord> accounts,
  required Iterable<SubscriptionRecord> subscriptions,
  required RecordSortMode sortMode,
}) {
  final result = accounts.toList();
  final originalIndex = <String, int>{
    for (var index = 0; index < result.length; index += 1)
      result[index].id: index,
  };
  final nearestRenewalByAccount = <String, DateTime>{};
  for (final subscription in subscriptions) {
    final accountId = subscription.accountId;
    if (subscription.status != SubscriptionStatus.active || accountId == null) {
      continue;
    }
    final current = nearestRenewalByAccount[accountId];
    if (current == null || subscription.nextRenewalOn.isBefore(current)) {
      nearestRenewalByAccount[accountId] = subscription.nextRenewalOn;
    }
  }

  int originalOrder(AccountRecord left, AccountRecord right) =>
      originalIndex[left.id]!.compareTo(originalIndex[right.id]!);

  int compareRenewal(AccountRecord left, AccountRecord right) {
    final leftDate = nearestRenewalByAccount[left.id];
    final rightDate = nearestRenewalByAccount[right.id];
    if (leftDate == null) {
      return rightDate == null ? originalOrder(left, right) : 1;
    }
    if (rightDate == null) {
      return -1;
    }
    final compared = leftDate.compareTo(rightDate);
    return compared == 0 ? originalOrder(left, right) : compared;
  }

  int compareName(AccountRecord left, AccountRecord right) {
    final compared = left.platformName.toLowerCase().compareTo(
      right.platformName.toLowerCase(),
    );
    if (compared != 0) {
      return compared;
    }
    final exact = left.platformName.compareTo(right.platformName);
    return exact == 0 ? originalOrder(left, right) : exact;
  }

  result.sort(switch (sortMode) {
    RecordSortMode.renewalSoonest => compareRenewal,
    RecordSortMode.newestAdded => (left, right) => originalOrder(right, left),
    RecordSortMode.oldestAdded => originalOrder,
    RecordSortMode.nameAscending ||
    RecordSortMode.accountCategory => compareName,
  });
  return result;
}

class AccountsPage extends StatefulWidget {
  const AccountsPage({
    required this.accounts,
    required this.subscriptions,
    required this.onAddAccount,
    this.displayMode = RecordDisplayMode.expandedCards,
    this.sortMode = RecordSortMode.oldestAdded,
    this.resetFilterToken = 0,
    this.searchFocusToken = 0,
    this.onOpenAccount,
    this.onEditAccount,
    this.onDeleteAccount,
    this.onAddSubscription,
    this.onAccountViewed,
    this.onSortModeChanged,
    this.onOpenPasswordReview,
    this.analysis,
    this.onOpenPasswordHealth,
    this.onOpenBindings,
    this.onBatchCategory,
    this.onBatchRecycle,
    this.countPendingDrafts,
    this.initialFilters = const <AccountFilter>{},
    this.filterToken = 0,
    this.dataRevision,
    super.key,
  });

  final List<AccountRecord> accounts;
  final List<SubscriptionRecord> subscriptions;
  final VoidCallback onAddAccount;
  final RecordDisplayMode displayMode;
  final RecordSortMode sortMode;
  final int resetFilterToken;
  final int searchFocusToken;
  final AccountListAction? onOpenAccount;
  final AccountListAction? onEditAccount;
  final AccountListDeleteAction? onDeleteAccount;
  final AccountListAction? onAddSubscription;
  final AccountListAction? onAccountViewed;
  final ValueChanged<RecordSortMode>? onSortModeChanged;
  final VoidCallback? onOpenPasswordReview;
  final AccountAnalysisSnapshot? analysis;
  final VoidCallback? onOpenPasswordHealth;
  final VoidCallback? onOpenBindings;
  final Future<bool> Function(
    Set<String> accountIds,
    String? category, {
    int? expectedRevision,
  })?
  onBatchCategory;
  final Future<bool> Function(Set<String> accountIds, {int? expectedRevision})?
  onBatchRecycle;
  final int Function(Set<String> accountIds)? countPendingDrafts;
  final Set<AccountFilter> initialFilters;
  final int filterToken;
  final int? dataRevision;

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  static const _allCategory = '全部';

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final Set<String> _collapsedCategories = <String>{};
  String _selectedCategory = _allCategory;
  String _query = '';
  late Set<AccountFilter> _filters;
  final Set<String> _selectedIds = {};
  bool _selectionMode = false;
  bool _batchBusy = false;

  @override
  void initState() {
    super.initState();
    _filters = {...widget.initialFilters};
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AccountsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetFilterToken != widget.resetFilterToken) {
      _searchController.clear();
      _selectedCategory = _allCategory;
      _query = '';
      _collapsedCategories.clear();
      _filters.clear();
      _selectedIds.clear();
      _selectionMode = false;
    }
    if (oldWidget.filterToken != widget.filterToken) {
      _filters = {...widget.initialFilters};
      _selectedIds.clear();
      _selectedCategory = _allCategory;
      _query = '';
      _searchController.clear();
    }
    _selectedIds.retainAll(widget.accounts.map((a) => a.id));
    _collapsedCategories.retainAll(
      widget.accounts
          .map((account) => account.category ?? unclassifiedAccountCategory)
          .toSet(),
    );
    if (oldWidget.searchFocusToken != widget.searchFocusToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
  }

  List<String> get _categories => [
    _allCategory,
    ...accountCategoryOptions(widget.accounts),
  ];

  Future<void> _openAccount(AccountRecord account) async {
    await widget.onAccountViewed?.call(account);
    await widget.onOpenAccount?.call(account);
  }

  void _toggleCategory(String category) {
    setState(() {
      _selectedIds.clear();
      if (!_collapsedCategories.add(category)) {
        _collapsedCategories.remove(category);
      }
    });
  }

  Future<void> _confirmDelete(AccountRecord account) async {
    final action = widget.onDeleteAccount;
    if (action == null) {
      return;
    }
    final subscriptionCount = widget.subscriptions
        .where((subscription) => subscription.accountId == account.id)
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移入回收站？'),
        content: Text(
          subscriptionCount == 0
              ? '记录将在回收站保留 30 天，可恢复。这不会注销对应平台账号。'
              : dialogContext.tr(
                  '关联的{countLabel}也将移入回收站保留 30 天。历史费用保留；这不会在对应平台取消订阅或停止扣费。',
                  <String, Object?>{
                    'countLabel': localizedSubscriptionItemCount(
                      dialogContext.l10n.language,
                      subscriptionCount,
                    ),
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey<String>('confirm-card-delete-account'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('移入回收站'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final deleted = await action(account);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(deleted ? '账号及关联订阅已移入回收站。' : '删除失败，原记录仍保留。')),
      );
  }

  Future<void> _openFilters() async {
    final selected = {..._filters};
    final result = await showModalBottomSheet<Set<AccountFilter>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => FractionallySizedBox(
          heightFactor: 0.85,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '账号组合筛选',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final filter in AccountFilter.values)
                        CheckboxListTile(
                          key: ValueKey('account-filter-${filter.name}'),
                          title: Text(filter.label),
                          value: selected.contains(filter),
                          onChanged: (value) => update(() {
                            if (value == true) {
                              selected.add(filter);
                              if (filter == AccountFilter.hasPassword) {
                                selected.remove(AccountFilter.noPassword);
                              }
                              if (filter == AccountFilter.noPassword) {
                                selected.remove(AccountFilter.hasPassword);
                              }
                              if (filter == AccountFilter.hasSubscription) {
                                selected.remove(AccountFilter.noSubscription);
                              }
                              if (filter == AccountFilter.noSubscription) {
                                selected.remove(AccountFilter.hasSubscription);
                              }
                            } else {
                              selected.remove(filter);
                            }
                          }),
                        ),
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('登录标识跨平台复用仅用于资料整理，不代表危险、泄露或账号重复。'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        key: const ValueKey('clear-all-account-filters'),
                        onPressed: () => update(selected.clear),
                        child: const Text('清除全部'),
                      ),
                      FilledButton(
                        key: const ValueKey('apply-account-filters'),
                        onPressed: () => Navigator.pop(context, selected),
                        child: const Text('应用筛选'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _filters = result;
        _selectedIds.clear();
        _collapsedCategories.clear();
      });
    }
  }

  Future<void> _batchCategory() async {
    if (_selectedIds.isEmpty || _batchBusy) return;
    final ids = Set<String>.of(_selectedIds);
    final revision = widget.dataRevision;
    const custom = '__stage3_custom__';
    var category = unclassifiedAccountCategory;
    final input = TextEditingController();
    final form = GlobalKey<FormState>();
    final categories = [
      unclassifiedAccountCategory,
      ...accountCategoryOptions(widget.accounts),
      custom,
    ];
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('批量修改账号分类'),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: category,
                    items: [
                      for (final value in categories)
                        DropdownMenuItem(
                          value: value,
                          child: Text(
                            value == custom
                                ? context.tr('自定义分类…')
                                : localizedAccountCategoryLabel(context, value),
                            translate: false,
                          ),
                        ),
                    ],
                    onChanged: (value) => update(() => category = value!),
                  ),
                  if (category == custom)
                    TextFormField(
                      key: const ValueKey('batch-custom-category'),
                      controller: input,
                      maxLength: 100,
                      decoration: InputDecoration(
                        labelText: context.tr('自定义分类 *'),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? context.tr('请输入自定义分类')
                          : null,
                    ),
                  const SizedBox(height: 12),
                  const Text('只修改账号分类，不改变订阅分类、费用、密码或自定义字段。'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('confirm-batch-category'),
              onPressed: () {
                if (form.currentState?.validate() ?? false) {
                  Navigator.pop(
                    context,
                    category == custom ? input.text.trim() : category,
                  );
                }
              },
              child: const Text('确认修改'),
            ),
          ],
        ),
      ),
    );
    // Controllers outlive the dialog exit animation.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (choice == null || !mounted) return;
    await _runBatch(
      () => widget.onBatchCategory!(
        ids,
        choice == unclassifiedAccountCategory ? null : choice,
        expectedRevision: revision,
      ),
    );
  }

  Future<void> _batchRecycle() async {
    if (_selectedIds.isEmpty || _batchBusy) return;
    final ids = Set<String>.of(_selectedIds);
    final revision = widget.dataRevision;
    final subscriptions = widget.subscriptions
        .where((s) => ids.contains(s.accountId))
        .length;
    final drafts = widget.countPendingDrafts?.call(ids) ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量移入回收站？'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr(
                  '影响 {accounts} 个账号、{subscriptions} 条关联订阅、{drafts} 条待完善订阅草稿。',
                  {
                    'accounts': ids.length,
                    'subscriptions': subscriptions,
                    'drafts': drafts,
                  },
                ),
                translate: false,
              ),
              const SizedBox(height: 12),
              const Text('独立订阅不受影响。记录保留 30 天，可从回收站恢复；不会在外部平台注销账号或取消订阅。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('confirm-batch-recycle'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移入回收站'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _runBatch(
        () => widget.onBatchRecycle!(ids, expectedRevision: revision),
      );
    }
  }

  Future<void> _runBatch(Future<bool> Function() action) async {
    setState(() => _batchBusy = true);
    try {
      final ok = await action();
      if (mounted) {
        if (ok) setState(_selectedIds.clear);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? '批量操作已加密保存。' : '批量操作失败，原记录仍保留。')),
        );
      }
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    final selectedCategory = categories.contains(_selectedCategory)
        ? _selectedCategory
        : _allCategory;
    final query = _query.trim();
    final subscriptionsByAccount = <String, List<SubscriptionRecord>>{};
    for (final subscription in widget.subscriptions) {
      if (subscription.accountId case final id?) {
        (subscriptionsByAccount[id] ??= []).add(subscription);
      }
    }
    final filteredAccounts = sortAccountsForDisplay(
      accounts: widget.accounts.where((account) {
        final matchesCategory =
            selectedCategory == _allCategory ||
            account.category?.trim().toLowerCase() ==
                selectedCategory.toLowerCase();
        final relatedSubscriptions =
            subscriptionsByAccount[account.id] ?? const <SubscriptionRecord>[];
        final normalizedQuery = query.toLowerCase();
        final matchesSubscription = relatedSubscriptions.any(
          (subscription) =>
              <String?>[
                subscription.serviceName,
                subscription.planName,
              ].whereType<String>().any(
                (value) => value.toLowerCase().contains(normalizedQuery),
              ),
        );
        final matchesAnalysis = widget.analysis?.matches(
          account,
          matchesSubscription ? '' : query,
          _filters,
        );
        return matchesCategory &&
            (matchesAnalysis ??
                (account.matches(query) || matchesSubscription));
      }),
      subscriptions: widget.subscriptions,
      sortMode: widget.sortMode,
    );
    final groupedAccounts = groupAccountsByCategory(filteredAccounts);
    final visibleIds = {
      for (final group in groupedAccounts)
        if (!_collapsedCategories.contains(group.label))
          for (final account in group.accounts) account.id,
    };
    _selectedIds.retainAll(visibleIds);

    final rows = <Object>[
      for (final group in groupedAccounts) ...[
        group,
        if (!_collapsedCategories.contains(group.label)) ...group.accounts,
      ],
    ];
    return ListView.builder(
      key: const ValueKey<String>('accounts-page'),
      padding: const EdgeInsets.fromLTRB(
        CardockLayout.screenHorizontal,
        8,
        CardockLayout.screenHorizontal,
        112,
      ),
      itemCount: rows.length + 1,
      itemBuilder: (context, index) {
        if (index > 0) {
          final row = rows[index - 1];
          if (row is AccountCategoryGroup) {
            return Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 7),
              child: _AccountCategoryHeader(
                label: row.label,
                accountCount: row.accounts.length,
                collapsed: _collapsedCategories.contains(row.label),
                onToggle: () => _toggleCategory(row.label),
              ),
            );
          }
          final account = row as AccountRecord;
          return Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Column(
              children: [
                if (_selectionMode)
                  CheckboxListTile(
                    key: ValueKey('select-account-${account.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(account.platformName, translate: false),
                    value: _selectedIds.contains(account.id),
                    onChanged: _batchBusy
                        ? null
                        : (value) => setState(() {
                            if (value == true) {
                              _selectedIds.add(account.id);
                            } else {
                              _selectedIds.remove(account.id);
                            }
                          }),
                  ),
                AccountRecordCard(
                  account: account,
                  displayMode: widget.displayMode,
                  showCategory: false,
                  subscriptions: subscriptionsByAccount[account.id] ?? const [],
                  onOpen:
                      widget.onOpenAccount == null &&
                          widget.onAccountViewed == null
                      ? null
                      : () => _openAccount(account),
                  onEdit: widget.onEditAccount == null
                      ? null
                      : () => widget.onEditAccount!(account),
                  onDelete: widget.onDeleteAccount == null
                      ? null
                      : () => _confirmDelete(account),
                  onAddSubscription: widget.onAddSubscription == null
                      ? null
                      : () => widget.onAddSubscription!(account),
                ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey<String>('account-search'),
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: (value) {
                setState(() {
                  _query = value;
                  _selectedIds.clear();
                  _collapsedCategories.clear();
                });
              },
              autocorrect: false,
              enableSuggestions: true,
              enableIMEPersonalizedLearning: false,
              decoration: InputDecoration(
                hintText: context.tr('搜索平台、用户名、账号、手机号或邮箱'),
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    query.isEmpty &&
                            selectedCategory == _allCategory &&
                            _filters.isEmpty
                        ? context.tr(widget.sortMode.label)
                        : context.tr('找到{countLabel}', <String, Object?>{
                            'countLabel': localizedAccountCount(
                              context.l10n.language,
                              filteredAccounts.length,
                            ),
                          }),
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    translate: false,
                  ),
                ),
                if (widget.onOpenPasswordReview != null ||
                    widget.onOpenPasswordHealth != null ||
                    widget.onOpenBindings != null)
                  PopupMenuButton<String>(
                    key: const ValueKey('account-tools-menu'),
                    tooltip: context.tr('账号工具'),
                    icon: const Icon(Icons.build_outlined),
                    onSelected: (value) {
                      switch (value) {
                        case 'health':
                          widget.onOpenPasswordHealth?.call();
                        case 'bindings':
                          widget.onOpenBindings?.call();
                        case 'history':
                          widget.onOpenPasswordReview?.call();
                      }
                    },
                    itemBuilder: (context) => [
                      if (widget.onOpenPasswordHealth != null)
                        const PopupMenuItem(
                          value: 'health',
                          child: Text('密码健康'),
                        ),
                      if (widget.onOpenBindings != null)
                        const PopupMenuItem(
                          value: 'bindings',
                          child: Text('绑定资料'),
                        ),
                      if (widget.onOpenPasswordReview != null)
                        const PopupMenuItem(
                          value: 'history',
                          child: Text('密码变更记录'),
                        ),
                    ],
                  ),
                if (widget.analysis != null)
                  Semantics(
                    label: context.tr('账号筛选，已启用 {count} 项', {
                      'count': _filters.length,
                    }),
                    child: IconButton(
                      key: const ValueKey('account-combined-filters'),
                      tooltip: context.tr('账号组合筛选'),
                      onPressed: _openFilters,
                      icon: Badge(
                        isLabelVisible: _filters.isNotEmpty,
                        label: Text('${_filters.length}', translate: false),
                        child: const Icon(Icons.filter_alt_outlined),
                      ),
                    ),
                  ),
                if (widget.onBatchCategory != null ||
                    widget.onBatchRecycle != null)
                  IconButton(
                    key: const ValueKey('account-selection-mode'),
                    tooltip: context.tr(_selectionMode ? '退出批量选择' : '批量选择'),
                    onPressed: () => setState(() {
                      _selectionMode = !_selectionMode;
                      _selectedIds.clear();
                    }),
                    icon: Icon(_selectionMode ? Icons.close : Icons.checklist),
                  ),
                PopupMenuButton<RecordSortMode>(
                  key: const ValueKey<String>('account-sort-mode-menu'),
                  initialValue: widget.sortMode,
                  enabled: widget.onSortModeChanged != null,
                  tooltip: context.tr('选择账号排序方式'),
                  onSelected: widget.onSortModeChanged,
                  itemBuilder: (context) => [
                    for (final mode in RecordSortMode.values.where(
                      (mode) => mode != RecordSortMode.accountCategory,
                    ))
                      PopupMenuItem<RecordSortMode>(
                        key: ValueKey<String>('account-sort-${mode.name}'),
                        value: mode,
                        child: Text(mode.label),
                      ),
                  ],
                  icon: const Icon(Icons.sort),
                ),
              ],
            ),
            if (_filters.isNotEmpty)
              Wrap(
                spacing: 8,
                children: [
                  for (final filter in _filters)
                    InputChip(
                      label: Text(filter.label),
                      onDeleted: () => setState(() {
                        _filters.remove(filter);
                        _selectedIds.clear();
                      }),
                    ),
                  TextButton(
                    onPressed: () => setState(() {
                      _filters.clear();
                      _selectedIds.clear();
                    }),
                    child: const Text('清除全部'),
                  ),
                ],
              ),
            if (_selectionMode)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      context.tr('已选 {count} 个账号', {
                        'count': _selectedIds.length,
                      }),
                      translate: false,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        key: const ValueKey('select-visible-accounts'),
                        onPressed: _batchBusy
                            ? null
                            : () => setState(
                                () => _selectedIds.addAll(visibleIds),
                              ),
                        child: const Text('全选当前可见结果'),
                      ),
                      TextButton(
                        key: const ValueKey('clear-account-selection'),
                        onPressed: _batchBusy
                            ? null
                            : () => setState(_selectedIds.clear),
                        child: const Text('取消全部'),
                      ),
                      if (widget.onBatchCategory != null)
                        OutlinedButton(
                          key: const ValueKey('batch-account-category'),
                          onPressed: _selectedIds.isEmpty || _batchBusy
                              ? null
                              : _batchCategory,
                          child: const Text('修改分类'),
                        ),
                      if (widget.onBatchRecycle != null)
                        OutlinedButton(
                          key: const ValueKey('batch-account-recycle'),
                          onPressed: _selectedIds.isEmpty || _batchBusy
                              ? null
                              : _batchRecycle,
                          child: const Text('移入回收站'),
                        ),
                    ],
                  ),
                ],
              ),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final category in categories) ...[
                    FilterChip(
                      key: ValueKey<String>(
                        'account-category-filter-$category',
                      ),
                      visualDensity: const VisualDensity(
                        horizontal: -2,
                        vertical: -2,
                      ),
                      label: Text(
                        localizedAccountCategoryLabel(context, category),
                        translate: false,
                      ),
                      selected: category == selectedCategory,
                      onSelected: (_) {
                        setState(() {
                          _selectedCategory = category;
                          _selectedIds.clear();
                          _collapsedCategories.clear();
                        });
                      },
                    ),
                    const SizedBox(width: 7),
                  ],
                ],
              ),
            ),
            const SizedBox(height: CardockLayout.cardGap),
            if (widget.accounts.isEmpty)
              EmptyStateCard(
                icon: Icons.badge_outlined,
                title: '暂无账号记录',
                message: '每个平台账号会作为一张独立记录卡加密保存在本机。',
                action: FilledButton.icon(
                  key: const ValueKey<String>('empty-add-account'),
                  onPressed: widget.onAddAccount,
                  icon: const Icon(Icons.add),
                  label: const Text('新增账号'),
                ),
              )
            else if (filteredAccounts.isEmpty)
              const EmptyStateCard(
                icon: Icons.search_off,
                title: '没有匹配的账号',
                message: '可以更换搜索词或分类后再试。',
              ),
          ],
        );
      },
    );
  }
}

class _AccountCategoryHeader extends StatelessWidget {
  const _AccountCategoryHeader({
    required this.label,
    required this.accountCount,
    required this.collapsed,
    required this.onToggle,
  });

  final String label;
  final int accountCount;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final localizedLabel = localizedAccountCategoryLabel(context, label);
    final actionLabel = context.tr(
      collapsed ? '展开{category}分类' : '折叠{category}分类',
      <String, Object?>{'category': localizedLabel},
    );
    return Semantics(
      header: true,
      button: true,
      expanded: !collapsed,
      onTap: onToggle,
      excludeSemantics: true,
      label: context.tr('{category}分类，共{countLabel}', <String, Object?>{
        'category': localizedLabel,
        'countLabel': localizedAccountCount(
          context.l10n.language,
          accountCount,
        ),
      }),
      hint: actionLabel,
      child: InkWell(
        key: ValueKey<String>('account-category-group-$label'),
        onTap: onToggle,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(CardockRadius.control),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  key: ValueKey<String>('account-category-toggle-$label'),
                  width: 24,
                  child: Icon(
                    collapsed
                        ? Icons.chevron_right_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: palette.primary,
                  ),
                ),
                SizedBox(
                  width: 24,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      if (!collapsed)
                        Positioned(
                          top: 18,
                          bottom: -14,
                          child: Container(
                            width: 1.5,
                            color: palette.primary.withValues(alpha: 0.45),
                          ),
                        ),
                      Icon(
                        Icons.folder_outlined,
                        size: 17,
                        color: palette.accountAccent,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  flex: 3,
                  child: Text(
                    localizedLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    translate: false,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    localizedAccountCount(context.l10n.language, accountCount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                      fontSize: 10,
                    ),
                    translate: false,
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
