import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../../accounts/domain/account_record.dart';
import '../domain/subscription_record.dart';
import '../domain/subscription_search.dart';

class SubscriptionSearchPanel extends StatefulWidget {
  const SubscriptionSearchPanel({
    required this.records,
    required this.accounts,
    required this.builder,
    this.readOnly = false,
    super.key,
  });
  final List<SubscriptionRecord> records;
  final List<AccountRecord> accounts;
  final Widget Function(BuildContext, List<SubscriptionRecord>, bool) builder;
  final bool readOnly;
  @override
  State<SubscriptionSearchPanel> createState() =>
      _SubscriptionSearchPanelState();
}

class _SubscriptionSearchPanelState extends State<SubscriptionSearchPanel> {
  final _query = TextEditingController();
  var _filter = const SubscriptionSearch();
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SubscriptionSearchPanel old) {
    super.didUpdateWidget(old);
    if (old.readOnly != widget.readOnly) {
      _query.clear();
      _filter = const SubscriptionSearch();
    }
  }

  Future<void> _filters() async {
    final selected = await showDialog<SubscriptionSearch>(
      context: context,
      builder: (context) =>
          _FiltersDialog(records: widget.records, initial: _filter),
    );
    if (!mounted || selected == null) return;
    setState(() => _filter = selected);
  }

  @override
  Widget build(BuildContext context) {
    final records = _filter.apply(
      widget.records,
      today: DateTime.now(),
      accounts: widget.accounts,
      includeAccountPlatform: !widget.readOnly,
      includeCancellation: !widget.readOnly,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('subscription-search'),
                  controller: _query,
                  decoration: InputDecoration(
                    labelText: '搜索订阅',
                    hintText: '服务、套餐、分类或备注',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: context.tr('清除搜索'),
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _query.clear();
                              setState(
                                () => _filter = _filter.copyWith(query: ''),
                              );
                            },
                          ),
                  ),
                  onChanged: (value) =>
                      setState(() => _filter = _filter.copyWith(query: value)),
                ),
              ),
              IconButton(
                key: const ValueKey('subscription-search-filters'),
                tooltip: context.tr('组合筛选'),
                onPressed: _filters,
                icon: Icon(
                  _filter.active ? Icons.filter_alt : Icons.filter_alt_outlined,
                ),
              ),
            ],
          ),
        ),
        if (_filter.active)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  context.tr('匹配 {count} 条订阅', {'count': records.length}),
                  translate: false,
                ),
                TextButton(
                  onPressed: () {
                    _query.clear();
                    setState(() => _filter = const SubscriptionSearch());
                  },
                  child: const Text('清除全部筛选'),
                ),
              ],
            ),
          ),
        Expanded(child: widget.builder(context, records, _filter.active)),
      ],
    );
  }
}

class _FiltersDialog extends StatefulWidget {
  const _FiltersDialog({required this.records, required this.initial});
  final List<SubscriptionRecord> records;
  final SubscriptionSearch initial;
  @override
  State<_FiltersDialog> createState() => _FiltersDialogState();
}

class _FiltersDialogState extends State<_FiltersDialog> {
  late SubscriptionSearch _filter = widget.initial;
  Widget _group<T>(
    String title,
    Iterable<T> values,
    Set<T> selected,
    String Function(T) label,
    void Function(Set<T>) onChange,
  ) => ExpansionTile(
    title: Text(title),
    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final value in values)
              FilterChip(
                label: Text(label(value)),
                selected: selected.contains(value),
                onSelected: (checked) => setState(() {
                  final next = {...selected};
                  checked ? next.add(value) : next.remove(value);
                  onChange(next);
                }),
              ),
          ],
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    List<String> unique(String Function(SubscriptionRecord) f) =>
        (widget.records.map(f).toSet().toList()..sort());
    return AlertDialog(
      title: const Text('组合筛选'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('不同类别同时满足，同一类别满足任意一项。'),
              _group(
                '订阅状态',
                SubscriptionSearchStatus.values,
                _filter.statuses,
                (v) => switch (v) {
                  SubscriptionSearchStatus.active => '正常',
                  SubscriptionSearchStatus.trial => '试用中',
                  SubscriptionSearchStatus.paused => '暂停',
                  SubscriptionSearchStatus.cancelled => '已取消',
                  SubscriptionSearchStatus.expired => '已到期',
                },
                (v) => _filter = _filter.copyWith(statuses: v),
              ),
              _group(
                '续费方式',
                [true, false],
                _filter.autoRenew,
                (v) => v ? '自动续费' : '手动续费',
                (v) => _filter = _filter.copyWith(autoRenew: v),
              ),
              _group(
                '日期范围',
                SubscriptionDateFilter.values,
                _filter.dates,
                (v) => switch (v) {
                  SubscriptionDateFilter.days30 => '未来30天',
                  SubscriptionDateFilter.days60 => '未来60天',
                  SubscriptionDateFilter.days90 => '未来90天',
                  SubscriptionDateFilter.overdue => '已逾期',
                },
                (v) => _filter = _filter.copyWith(dates: v),
              ),
              _group(
                '计费周期',
                unique((s) => '${s.cycleCount}:${s.cycleUnit.name}'),
                _filter.cycles,
                (v) {
                  final s = widget.records.firstWhere(
                    (s) => '${s.cycleCount}:${s.cycleUnit.name}' == v,
                  );
                  return s.cycleLabel;
                },
                (v) => _filter = _filter.copyWith(cycles: v),
              ),
              _group(
                '币种',
                unique((s) => s.currency),
                _filter.currencies,
                (v) => v,
                (v) => _filter = _filter.copyWith(currencies: v),
              ),
              _group(
                '支付方式',
                unique((s) => s.paymentMethod ?? ''),
                _filter.paymentMethods,
                (v) => v.isEmpty ? '未设置' : v,
                (v) => _filter = _filter.copyWith(paymentMethods: v),
              ),
              _group(
                '费用分类',
                unique((s) => s.expenseCategory ?? ''),
                _filter.categories,
                (v) => v.isEmpty ? '未分类' : v,
                (v) => _filter = _filter.copyWith(categories: v),
              ),
              _group(
                '关联账号',
                [true, false],
                _filter.linked,
                (v) => v ? '已关联账号' : '独立订阅',
                (v) => _filter = _filter.copyWith(linked: v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => setState(
            () => _filter = SubscriptionSearch(query: _filter.query),
          ),
          child: const Text('清除筛选'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _filter),
          child: const Text('应用筛选'),
        ),
      ],
    );
  }
}
