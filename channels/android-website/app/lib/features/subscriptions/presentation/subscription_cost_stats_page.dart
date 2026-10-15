import 'package:flutter/services.dart';

import '../../../core/exchange_rates/semiannual_cny_exchange_rates.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../../../l10n/translations_records.dart';
import '../domain/subscription_cost_summary.dart';
import '../domain/subscription_expense_record.dart';
import '../domain/subscription_record.dart';
import '../../accounts/domain/account_record.dart';
import '../domain/subscription_expense_automation.dart';
import 'subscription_editor_page.dart';

enum _CostRangePreset { currentYear, lastTwelveMonths, custom }

enum _CostBreakdownMode { month, category }

class SubscriptionCostStatsPage extends StatefulWidget {
  const SubscriptionCostStatsPage({
    required this.subscriptions,
    required this.expenses,
    this.accounts = const [],
    this.paymentMethods = const [],
    this.onAddExpense,
    this.onEditExpense,
    this.onDeleteExpense,
    this.currentMonth = false,
    this.ledgerOnly = false,
    this.today,
    this.embedded = false,
    super.key,
  });

  final List<SubscriptionRecord> subscriptions;
  final List<SubscriptionExpenseRecord> expenses;
  final List<AccountRecord> accounts;
  final List<PaymentMethodRecord> paymentMethods;
  final Future<bool> Function(SubscriptionExpenseDraft draft)? onAddExpense;
  final Future<bool> Function(
    SubscriptionCostLine line,
    SubscriptionExpenseDraft draft,
  )?
  onEditExpense;
  final Future<bool> Function(SubscriptionCostLine line)? onDeleteExpense;
  final bool currentMonth;
  final bool ledgerOnly;
  final DateTime? today;
  final bool embedded;

  @override
  State<SubscriptionCostStatsPage> createState() =>
      _SubscriptionCostStatsPageState();
}

class _SubscriptionCostStatsPageState extends State<SubscriptionCostStatsPage> {
  _CostRangePreset _rangePreset = _CostRangePreset.currentYear;
  _CostBreakdownMode _breakdownMode = _CostBreakdownMode.month;
  SubscriptionCostBasis _selectedBasis = SubscriptionCostBasis.confirmed;
  late DateTime _startMonth;
  late DateTime _endMonth;

  DateTime get _today => DateUtils.dateOnly(widget.today ?? DateTime.now());

  @override
  void initState() {
    super.initState();
    _applyPreset(_CostRangePreset.currentYear, notify: false);
    if (widget.currentMonth) {
      _rangePreset = _CostRangePreset.custom;
      _startMonth = _endMonth = DateTime(_today.year, _today.month);
    }
  }

  @override
  void didUpdateWidget(covariant SubscriptionCostStatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_rangePreset != _CostRangePreset.custom &&
        oldWidget.today != widget.today) {
      _applyPreset(_rangePreset, notify: false);
    }
  }

  void _applyPreset(_CostRangePreset preset, {bool notify = true}) {
    final today = _today;
    late final DateTime start;
    late final DateTime end;
    switch (preset) {
      case _CostRangePreset.currentYear:
        start = DateTime(today.year);
        end = DateTime(today.year, 12);
      case _CostRangePreset.lastTwelveMonths:
        start = DateTime(today.year, today.month - 11);
        end = DateTime(today.year, today.month);
      case _CostRangePreset.custom:
        start = _startMonth;
        end = _endMonth;
    }
    void update() {
      _rangePreset = preset;
      _startMonth = start;
      _endMonth = end;
    }

    if (notify) {
      setState(update);
    } else {
      update();
    }
  }

  Future<void> _chooseMonth({required bool start}) async {
    final current = start ? _startMonth : _endMonth;
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (context) => _MonthPickerDialog(initialMonth: current),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _rangePreset = _CostRangePreset.custom;
      if (start) {
        _startMonth = selected;
        if (_endMonth.isBefore(selected)) _endMonth = selected;
      } else {
        _endMonth = selected;
        if (_startMonth.isAfter(selected)) _startMonth = selected;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    SubscriptionCostAnalysis? analysis;
    try {
      analysis = SubscriptionCostAnalysis.build(
        subscriptions: widget.ledgerOnly ? const [] : widget.subscriptions,
        accounts: widget.accounts,
        expenses: widget.expenses,
        range: SubscriptionCostRange(
          startMonth: _startMonth,
          endMonth: _endMonth,
        ),
        today: _today,
      );
    } on Object {
      analysis = null;
    }
    return Scaffold(
      key: const ValueKey<String>('subscription-cost-stats-page'),
      appBar: widget.embedded ? null : AppBar(title: const Text('订阅费用统计')),
      floatingActionButton: widget.onAddExpense == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey<String>('add-subscription-expense'),
              onPressed: _showAddExpenseSheet,
              icon: const Icon(Icons.add_card_outlined),
              label: const Text('记录支付或退款'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
        children: [
          _buildRangeCard(),
          const SizedBox(height: 12),
          _buildReferenceNotice(),
          const SizedBox(height: 16),
          if (analysis == null)
            _buildAnalysisFailure()
          else ...[
            _buildBasisSummaries(analysis),
            const SizedBox(height: 18),
            _buildBreakdownHeader(),
            const SizedBox(height: 8),
            _CostBreakdown(
              analysis: analysis,
              basis: _selectedBasis,
              mode: _breakdownMode,
              onEdit: widget.onEditExpense == null ? null : _editExpense,
              onDelete: widget.onDeleteExpense == null ? null : _deleteExpense,
            ),
          ],
          if (widget.onAddExpense == null) ...[
            const SizedBox(height: 12),
            const Card(
              child: ListTile(
                leading: Icon(Icons.visibility_outlined),
                title: Text('当前为只读统计'),
                subtitle: Text('可以查看费用，不会提供新增支付或退款入口。'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRangeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('统计月份', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const ValueKey<String>('cost-range-current-year'),
                  label: const Text('本年'),
                  selected: _rangePreset == _CostRangePreset.currentYear,
                  onSelected: (_) => _applyPreset(_CostRangePreset.currentYear),
                ),
                ChoiceChip(
                  key: const ValueKey<String>('cost-range-last-twelve-months'),
                  label: const Text('近12个月'),
                  selected: _rangePreset == _CostRangePreset.lastTwelveMonths,
                  onSelected: (_) =>
                      _applyPreset(_CostRangePreset.lastTwelveMonths),
                ),
                ChoiceChip(
                  key: const ValueKey<String>('cost-range-custom'),
                  label: const Text('自选起止月份'),
                  selected: _rangePreset == _CostRangePreset.custom,
                  onSelected: (_) => _applyPreset(_CostRangePreset.custom),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 330;
                final startButton = _MonthButton(
                  key: const ValueKey<String>('cost-range-start-month'),
                  label: '开始月份',
                  value: _monthLabel(context, _startMonth),
                  onPressed: () => _chooseMonth(start: true),
                );
                final endButton = _MonthButton(
                  key: const ValueKey<String>('cost-range-end-month'),
                  label: '结束月份',
                  value: _monthLabel(context, _endMonth),
                  onPressed: () => _chooseMonth(start: false),
                );
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      startButton,
                      const SizedBox(height: 8),
                      endButton,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: startButton),
                    const SizedBox(width: 10),
                    Expanded(child: endButton),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferenceNotice() {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: const ListTile(
        leading: Icon(Icons.offline_bolt_outlined),
        title: Text('2026 年上半年离线参考汇率'),
        subtitle: Text('原币金额是主要统计口径；参考人民币只用于离线查看，不代表实际扣款汇率。'),
      ),
    );
  }

  Widget _buildAnalysisFailure() {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: const ListTile(
        leading: Icon(Icons.warning_amber_rounded),
        title: Text('所选月份暂时无法统计'),
        subtitle: Text('请缩短月份范围后重试，原始订阅和费用记录没有改变。'),
      ),
    );
  }

  Widget _buildBasisSummaries(SubscriptionCostAnalysis analysis) {
    final cards = <Widget>[
      for (final basis in SubscriptionCostBasis.values)
        _BasisSummaryCard(
          key: ValueKey<String>('cost-basis-${basis.name}'),
          basis: basis,
          analysis: analysis,
          selected: basis == _selectedBasis,
          onTap: () => setState(() => _selectedBasis = basis),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < cards.length; index += 1) ...[
                Expanded(child: cards[index]),
                if (index != cards.length - 1) const SizedBox(width: 10),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var index = 0; index < cards.length; index += 1) ...[
              cards[index],
              if (index != cards.length - 1) const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _buildBreakdownHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('{basis}明细', <String, Object?>{
            'basis': context.tr(_basisLabel(_selectedBasis)),
          }),
          translate: false,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey<String>('cost-breakdown-month'),
              label: const Text('按月统计'),
              selected: _breakdownMode == _CostBreakdownMode.month,
              onSelected: (_) =>
                  setState(() => _breakdownMode = _CostBreakdownMode.month),
            ),
            ChoiceChip(
              key: const ValueKey<String>('cost-breakdown-category'),
              label: const Text('按费用分类统计'),
              selected: _breakdownMode == _CostBreakdownMode.category,
              onSelected: (_) =>
                  setState(() => _breakdownMode = _CostBreakdownMode.category),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editExpense(SubscriptionCostLine line) async {
    final action = widget.onEditExpense;
    if (action == null) return;
    final record = widget.expenses
        .where((e) => e.id == line.expenseId)
        .firstOrNull;
    final initial =
        record?.draft ??
        SubscriptionExpenseDraft(
          subscriptionId: line.subscriptionId,
          serviceName: line.serviceName,
          occurredOn: line.date,
          amount: line.amount ?? '0',
          currency: line.currency,
          kind: line.refund
              ? SubscriptionExpenseKind.refund
              : SubscriptionExpenseKind.payment,
          expenseCategory: line.expenseCategory,
          scheduledRenewalOn: line.scheduledOn,
        );
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _AddExpenseSheet(
        paymentMethods: widget.paymentMethods,
        accounts: widget.accounts,
        subscriptions: widget.subscriptions,
        expenses: widget.expenses,
        today: _today,
        initial: initial,
        onSave: (draft) => action(line, draft),
      ),
    );
    if (saved == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('费用记录已加密保存到本机。')));
    }
  }

  Future<void> _deleteExpense(SubscriptionCostLine line) async {
    final action = widget.onDeleteExpense;
    if (action == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这笔费用？'),
        content: Text(
          context.tr(
            '将从统计中删除“{service}”的这笔费用。订阅和下次续费日期保持不变；误点续费造成的日期延后，可在订阅详情中编辑修正。',
            {'service': line.serviceName},
          ),
          translate: false,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-expense'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    var saved = false;
    try {
      saved = await action(line);
    } on Object {
      saved = false;
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(saved ? '费用记录已删除。' : '操作未保存，请稍后重试。')),
    );
  }

  Future<void> _showAddExpenseSheet() async {
    final action = widget.onAddExpense;
    if (action == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _AddExpenseSheet(
        paymentMethods: widget.paymentMethods,
        accounts: widget.accounts,
        subscriptions: widget.subscriptions,
        expenses: widget.expenses,
        today: _today,
        onSave: action,
      ),
    );
    if (saved == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('费用记录已加密保存到本机。')));
    }
  }
}

class _BasisSummaryCard extends StatelessWidget {
  const _BasisSummaryCard({
    required this.basis,
    required this.analysis,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final SubscriptionCostBasis basis;
  final SubscriptionCostAnalysis analysis;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lines = analysis.forBasis(basis);
    final original = analysis.currencyTotals(basis);
    final cny = analysis.cnyEstimate(basis);
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                key: ValueKey<String>('cost-basis-title-${basis.name}'),
                children: [
                  Icon(_basisIcon(basis), color: _basisColor(context, basis)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _basisLabel(basis),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (selected) Icon(Icons.check_circle, color: colors.primary),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _basisDescription(basis),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (basis == SubscriptionCostBasis.confirmed &&
                  analysis.gaps.isNotEmpty) ...[
                const SizedBox(height: 12),
                _UncountedPeriodsNotice(gaps: analysis.gaps),
              ],
              const SizedBox(height: 12),
              _CurrencyTotals(
                totals: original,
                rowKeyPrefix: 'cost-total-${basis.name}',
                prominent: true,
              ),
              const SizedBox(height: 4),
              Text(
                cny.convertedCount == 0
                    ? context.tr('参考人民币：暂无可折算金额')
                    : context.tr('参考人民币：约 {amount}', <String, Object?>{
                        'amount': _formatCny(cny.totalCny),
                      }),
                translate: false,
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('{count}条记录', <String, Object?>{
                  'count': lines.length,
                }),
                translate: false,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (cny.excludedCount > 0) ...[
                const SizedBox(height: 3),
                Text(
                  context.tr('{count}条因缺少金额或不支持的币种未计入参考人民币', <String, Object?>{
                    'count': cny.excludedCount,
                  }),
                  translate: false,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UncountedPeriodsNotice extends StatelessWidget {
  const _UncountedPeriodsNotice({required this.gaps});

  final List<SubscriptionCostGap> gaps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      key: const ValueKey<String>('cost-uncounted-periods'),
      color: colors.errorContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: colors.onErrorContainer),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: colors.onErrorContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '部分账期暂未计入',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '保存的日期无法按当前周期衔接，需核对原记录；总额暂不含这些账期。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onErrorContainer,
                ),
              ),
              ExpansionTile(
                key: const ValueKey<String>('cost-uncounted-periods-toggle'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                iconColor: colors.onErrorContainer,
                collapsedIconColor: colors.onErrorContainer,
                title: Text(
                  context.tr('查看未计入账期（{count}）', <String, Object?>{
                    'count': gaps.length,
                  }),
                  key: const ValueKey<String>('cost-uncounted-periods-title'),
                  translate: false,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onErrorContainer,
                  ),
                ),
                children: [
                  for (var index = 0; index < gaps.length; index += 1) ...[
                    if (index > 0) const Divider(height: 20),
                    _UncountedPeriodDetails(gap: gaps[index]),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UncountedPeriodDetails extends StatelessWidget {
  const _UncountedPeriodDetails({required this.gap});

  final SubscriptionCostGap gap;

  @override
  Widget build(BuildContext context) {
    // Display the final included calendar day without applying a DST offset.
    final through = DateTime(
      gap.endExclusive.year,
      gap.endExclusive.month,
      gap.endExclusive.day - 1,
    );
    return Column(
      key: ValueKey<String>(
        'cost-gap-${gap.subscriptionId}-${formatSubscriptionDate(gap.start)}',
      ),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          gap.serviceName,
          translate: false,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (gap.accountLabel != null) ...[
          const SizedBox(height: 4),
          Text(gap.accountLabel!, translate: false),
        ],
        const SizedBox(height: 6),
        Text(
          context.tr('未计入区间：{start} 至 {end}', <String, Object?>{
            'start': localizedRecordDate(context.l10n.language, gap.start),
            'end': localizedRecordDate(context.l10n.language, through),
          }),
          translate: false,
        ),
      ],
    );
  }
}

class _CostBreakdown extends StatelessWidget {
  const _CostBreakdown({
    required this.analysis,
    required this.basis,
    required this.mode,
    this.onEdit,
    this.onDelete,
  });

  final SubscriptionCostAnalysis analysis;
  final SubscriptionCostBasis basis;
  final _CostBreakdownMode mode;

  final ValueChanged<SubscriptionCostLine>? onEdit;
  final ValueChanged<SubscriptionCostLine>? onDelete;

  @override
  Widget build(BuildContext context) {
    final groups = mode == _CostBreakdownMode.month
        ? analysis.byMonth(basis)
        : analysis.byCategory(basis);
    if (groups.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.receipt_long_outlined, size: 38),
              SizedBox(height: 10),
              Text('这个口径在所选月份内暂无记录。'),
            ],
          ),
        ),
      );
    }
    final entries = groups.entries.toList();
    entries.sort((left, right) {
      final compared = left.key.compareTo(right.key);
      return mode == _CostBreakdownMode.month ? -compared : compared;
    });
    return Column(
      children: [
        for (var index = 0; index < entries.length; index += 1) ...[
          _BreakdownGroupCard(
            groupKey:
                'cost-group-${basis.name}-${mode.name}-${entries[index].key}',
            label: mode == _CostBreakdownMode.month
                ? _monthKeyLabel(context, entries[index].key)
                : _categoryLabel(context, entries[index].key),
            lines: entries[index].value,
            onEdit: onEdit,
            onDelete: onDelete,
          ),
          if (index != entries.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _BreakdownGroupCard extends StatelessWidget {
  const _BreakdownGroupCard({
    required this.groupKey,
    required this.label,
    required this.lines,
    this.onEdit,
    this.onDelete,
  });

  final String groupKey;

  final String label;
  final List<SubscriptionCostLine> lines;

  final ValueChanged<SubscriptionCostLine>? onEdit;
  final ValueChanged<SubscriptionCostLine>? onDelete;

  @override
  Widget build(BuildContext context) {
    final summary = _summarizeLines(lines);
    return Card(
      child: ExpansionTile(
        key: ValueKey<String>(groupKey),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(
          label,
          key: ValueKey<String>('$groupKey-title'),
          translate: false,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            _CurrencyTotals(
              totals: summary.originalTotals,
              rowKeyPrefix: '$groupKey-total',
            ),
            const SizedBox(height: 6),
            Text(
              summary.convertedCount == 0
                  ? context.tr('参考人民币：暂无可折算金额')
                  : context.tr('参考人民币：约 {amount}', <String, Object?>{
                      'amount': _formatCny(summary.totalCny),
                    }),
              translate: false,
            ),
            if (summary.excludedCount > 0)
              Text(
                context.tr('{count}条未计入参考人民币', <String, Object?>{
                  'count': summary.excludedCount,
                }),
                translate: false,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              context.tr('{count}条', <String, Object?>{'count': lines.length}),
              translate: false,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        children: [
          for (var index = 0; index < lines.length; index += 1) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            _CostLineTile(
              line: lines[index],
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          ],
        ],
      ),
    );
  }
}

class _CostLineTile extends StatelessWidget {
  const _CostLineTile({required this.line, this.onEdit, this.onDelete});

  final ValueChanged<SubscriptionCostLine>? onEdit;
  final ValueChanged<SubscriptionCostLine>? onDelete;

  final SubscriptionCostLine line;

  @override
  Widget build(BuildContext context) {
    final cycleCount = line.cycleCount;
    final cycleUnit = line.cycleUnit;
    final scheduledOn = line.scheduledOn;
    final detailStyle = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                line.refund
                    ? Icons.currency_exchange_outlined
                    : Icons.payments_outlined,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  line.serviceName,
                  translate: false,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          if (line.basis == SubscriptionCostBasis.confirmed &&
              (onEdit != null || onDelete != null))
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                if (onEdit != null)
                  TextButton.icon(
                    key: ValueKey(
                      'edit-expense-${line.expenseId ?? '${line.subscriptionId}-${line.scheduledOn}'}',
                    ),
                    onPressed: () => onEdit!(line),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('编辑'),
                  ),
                if (onDelete != null)
                  TextButton.icon(
                    key: ValueKey(
                      'delete-expense-${line.expenseId ?? '${line.subscriptionId}-${line.scheduledOn}'}',
                    ),
                    onPressed: () => onDelete!(line),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除'),
                  ),
              ],
            ),
          if (line.accountLabel != null) ...[
            const SizedBox(height: 6),
            Text(line.accountLabel!, translate: false, style: detailStyle),
          ],
          if (line.planName != null) ...[
            const SizedBox(height: 4),
            Text(line.planName!, translate: false, style: detailStyle),
          ],
          const SizedBox(height: 6),
          Text(
            localizedRecordDate(context.l10n.language, line.date),
            translate: false,
            style: detailStyle,
          ),
          if (cycleCount != null && cycleUnit != null) ...[
            const SizedBox(height: 4),
            Text(
              context.tr('计费周期：{cycle}', <String, Object?>{
                'cycle': localizedSubscriptionCycle(
                  context.l10n.language,
                  cycleUnit,
                  cycleCount,
                ),
              }),
              translate: false,
              style: detailStyle,
            ),
          ],
          if (scheduledOn != null &&
              !DateUtils.isSameDay(scheduledOn, line.date)) ...[
            const SizedBox(height: 4),
            Text(
              context.tr('对应续费日：{date}', <String, Object?>{
                'date': localizedRecordDate(context.l10n.language, scheduledOn),
              }),
              translate: false,
              style: detailStyle,
            ),
          ],
          const SizedBox(height: 10),
          if (line.amount == null)
            Text(
              context.tr('{currency} 未记录金额', <String, Object?>{
                'currency': line.currency,
              }),
              translate: false,
            )
          else
            _CurrencyAmountRow(
              currency: line.currency,
              amount: '${line.refund ? '-' : ''}${line.amount}',
            ),
        ],
      ),
    );
  }
}

/// Keep currencies separate and keep complete amounts readable at large scales.
class _CurrencyTotals extends StatelessWidget {
  const _CurrencyTotals({
    required this.totals,
    required this.rowKeyPrefix,
    this.prominent = false,
  });

  final List<SubscriptionCurrencyTotal> totals;
  final String rowKeyPrefix;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    if (totals.isEmpty) return const Text('暂无可合计的原币金额');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < totals.length; index += 1) ...[
          if (index > 0) const Divider(height: 1),
          Padding(
            key: ValueKey<String>(
              '$rowKeyPrefix-currency-${totals[index].currency}',
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _CurrencyAmountRow(
              currency: totals[index].currency,
              amount: totals[index].formattedAmount,
              prominent: prominent,
            ),
          ),
        ],
      ],
    );
  }
}

class _CurrencyAmountRow extends StatelessWidget {
  const _CurrencyAmountRow({
    required this.currency,
    required this.amount,
    this.prominent = false,
  });

  final String currency;
  final String amount;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyStyle = theme.textTheme.labelLarge;
    final amountStyle =
        (prominent ? theme.textTheme.titleLarge : theme.textTheme.bodyLarge)
            ?.copyWith(fontWeight: FontWeight.w700);
    return LayoutBuilder(
      builder: (context, constraints) {
        double widthOf(String value, TextStyle? style) {
          final painter = TextPainter(
            text: TextSpan(text: value, style: style),
            textScaler: MediaQuery.textScalerOf(context),
            textDirection: Directionality.of(context),
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        final stacked =
            widthOf(currency, currencyStyle) +
                widthOf(amount, amountStyle) +
                16 >
            constraints.maxWidth;
        final currencyText = Text(
          currency,
          translate: false,
          style: currencyStyle,
        );
        final amountText = Text(
          amount,
          translate: false,
          style: amountStyle,
          softWrap: true,
          textAlign: stacked ? TextAlign.start : TextAlign.end,
        );
        return Semantics(
          container: true,
          label: '$currency $amount',
          excludeSemantics: true,
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    currencyText,
                    const SizedBox(height: 4),
                    amountText,
                  ],
                )
              : Row(
                  children: [
                    currencyText,
                    const SizedBox(width: 16),
                    Expanded(child: amountText),
                  ],
                ),
        );
      },
    );
  }
}

class _AddExpenseSheet extends StatefulWidget {
  const _AddExpenseSheet({
    this.paymentMethods = const [],
    required this.accounts,
    required this.subscriptions,
    required this.expenses,
    required this.today,
    required this.onSave,
    this.initial,
  });

  final SubscriptionExpenseDraft? initial;
  final List<SubscriptionRecord> subscriptions;
  final List<SubscriptionExpenseRecord> expenses;
  final DateTime today;
  final Future<bool> Function(SubscriptionExpenseDraft draft) onSave;
  final List<AccountRecord> accounts;
  final List<PaymentMethodRecord> paymentMethods;

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _serviceController = TextEditingController();
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController();
  String? _paymentMethodId;
  var _subscriptionId = '';
  var _currency = 'CNY';
  var _kind = SubscriptionExpenseKind.refund;
  String? _accountId;
  bool _accountChosen = false;
  late DateTime _occurredOn = widget.today;
  var _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    _serviceController.text = initial.serviceName;
    _amountController.text = initial.amount;
    _categoryController.text = initial.expenseCategory ?? '';
    _currency = initial.currency;
    _kind = initial.kind;
    _occurredOn = initial.occurredOn;
    _subscriptionId = initial.subscriptionId ?? '';
    _accountId = initial.accountId;
    _accountChosen = true;
    _paymentMethodId = initial.paymentMethodId;
  }

  List<String> get _currencies {
    final values = <String>{
      ...subscriptionCurrencies,
      _currency,
      for (final subscription in widget.subscriptions) subscription.currency,
      for (final expense in widget.expenses) expense.currency,
    }.toList()..sort();
    return values;
  }

  SubscriptionRecord? get _selectedSubscription =>
      _subscriptionWithId(widget.subscriptions, _subscriptionId);

  @override
  void dispose() {
    _serviceController.dispose();
    _amountController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.initial == null ? '记录支付或退款' : '编辑费用记录',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('关闭'),
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.initial == null
                    ? '订阅费用已自动计入支出，退款会直接扣减。支付入口仅用于补充尚未记录的付款。'
                    : '只修改这笔费用，不改变订阅金额、计费周期或下次续费日期。',
              ),
              const SizedBox(height: 16),
              SegmentedButton<SubscriptionExpenseKind>(
                key: const ValueKey<String>('expense-kind-selector'),
                segments: const [
                  ButtonSegment(
                    value: SubscriptionExpenseKind.payment,
                    icon: Icon(Icons.payments_outlined),
                    label: Text('支付'),
                  ),
                  ButtonSegment(
                    value: SubscriptionExpenseKind.refund,
                    icon: Icon(Icons.currency_exchange_outlined),
                    label: Text('退款'),
                  ),
                ],
                selected: <SubscriptionExpenseKind>{_kind},
                onSelectionChanged: _saving || widget.initial != null
                    ? null
                    : (value) => setState(() => _kind = value.single),
              ),
              const SizedBox(height: 16),
              ListTile(
                key: const ValueKey('expense-account-field'),
                contentPadding: EdgeInsets.zero,
                title: const Text('关联账号'),
                subtitle: Text(_accountDisplay, translate: false),
                trailing: const Icon(Icons.chevron_right),
                onTap: _saving || widget.initial != null
                    ? null
                    : _chooseAccount,
              ),
              ListTile(
                key: const ValueKey('expense-subscription-field'),
                contentPadding: EdgeInsets.zero,
                title: const Text('该账号的订阅'),
                subtitle: Text(
                  _selectedSubscription == null
                      ? context.tr('选择订阅或手动填写')
                      : _subscriptionDisplay(_selectedSubscription!),
                  translate: false,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _saving || widget.initial != null || !_accountChosen
                    ? null
                    : _chooseSubscription,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('expense-service-name'),
                controller: _serviceController,
                maxLength: 100,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: context.tr('订阅服务名称 *'),
                  counterText: '',
                ),
                validator: (value) {
                  if ((value?.trim() ?? '').isEmpty) {
                    return context.tr('请输入订阅服务名称');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      key: const ValueKey<String>('expense-amount'),
                      controller: _amountController,
                      enabled: !_saving,
                      maxLength: 17,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: InputDecoration(
                        labelText: context.tr('金额 *'),
                        counterText: '',
                      ),
                      validator: (value) {
                        if (!RegExp(
                          r'^(0|[1-9]\d{0,11})(\.\d{1,4})?$',
                        ).hasMatch(value?.trim() ?? '')) {
                          return context.tr('请输入有效金额，最多保留4位小数');
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey<String>('expense-currency-$_currency'),
                      initialValue: _currency,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: context.tr('币种')),
                      items: [
                        for (final currency in _currencies)
                          DropdownMenuItem(
                            value: currency,
                            child: Text(currency, translate: false),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _currency = value);
                              }
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _paymentMethodId,
                decoration: const InputDecoration(labelText: '实际支付或退款方式'),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('使用订阅默认方式'),
                  ),
                  for (final p in widget.paymentMethods.where(
                    (p) => !p.archived || p.id == _paymentMethodId,
                  ))
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(p.name, translate: false),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _paymentMethodId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('expense-category'),
                controller: _categoryController,
                enabled: !_saving,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: context.tr('费用分类（可选）'),
                  hintText: context.tr('例如：影音娱乐、云服务'),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('实际支付或退款日期'),
                subtitle: Text(
                  localizedRecordDate(context.l10n.language, _occurredOn),
                  translate: false,
                ),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _saving ? null : _pickOccurredOn,
              ),
              if (_selectedSubscription != null) ...[
                const SizedBox(height: 4),
                Text(
                  context.tr(
                    '将保留与“{service}”的关联；删除订阅卡片后，这笔历史记录仍会保留。',
                    <String, Object?>{
                      'service': _selectedSubscription!.serviceName,
                    },
                  ),
                  translate: false,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_saveError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _saveError!,
                  translate: false,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const ValueKey<String>('save-expense'),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _kind == SubscriptionExpenseKind.payment
                            ? Icons.save_outlined
                            : Icons.currency_exchange_outlined,
                      ),
                label: Text(
                  _kind == SubscriptionExpenseKind.payment
                      ? '保存支付记录'
                      : '保存退款记录',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  AccountRecord? get _selectedAccount =>
      widget.accounts.where((account) => account.id == _accountId).firstOrNull;

  String get _accountDisplay => !_accountChosen
      ? context.tr('请选择分类与账号')
      : _selectedAccount == null
      ? context.tr('独立订阅')
      : subscriptionExpenseAccountLabel(_selectedAccount!);

  List<SubscriptionRecord> get _accountSubscriptions => widget.subscriptions
      .where((subscription) => subscription.accountId == _accountId)
      .toList();

  String _subscriptionDisplay(SubscriptionRecord subscription) => <String>[
    subscription.serviceName,
    if (subscription.planName != null) subscription.planName!,
    if (subscription.amount != null)
      '${subscription.currency} ${subscription.amount}',
    localizedRecordDate(context.l10n.language, subscription.firstSubscribedOn),
  ].join(' · ');

  Future<void> _chooseAccount() async {
    final result = await showSubscriptionAccountPicker(
      context: context,
      accounts: widget.accounts,
      selectedAccountId: _accountId,
    );
    if (!mounted || result == null) return;
    setState(() {
      _accountChosen = true;
      _accountId = result.accountId;
      _subscriptionId = '';
      _serviceController.clear();
      _amountController.clear();
      _categoryController.text = _selectedAccount?.category ?? '';
      _currency = 'CNY';
    });
    final subscriptions = _accountSubscriptions;
    if (subscriptions.length == 1) _selectSubscription(subscriptions.single.id);
  }

  Future<void> _chooseSubscription() async {
    final subscriptions = _accountSubscriptions;
    final id = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .9,
        child: Column(
          children: [
            ListTile(
              title: const Text('该账号的订阅'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                tooltip: context.tr('关闭'),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  ListTile(title: Text(_accountDisplay, translate: false)),
                  ListTile(
                    title: const Text('手动填写费用'),
                    onTap: () => Navigator.pop(context, ''),
                  ),
                  for (var index = 0; index < subscriptions.length; index++)
                    ListTile(
                      key: ValueKey('expense-pick-${subscriptions[index].id}'),
                      leading: Text('${index + 1}', translate: false),
                      title: Text(
                        subscriptions[index].serviceName,
                        translate: false,
                      ),
                      subtitle: Text(
                        _subscriptionDisplay(subscriptions[index]),
                        translate: false,
                      ),
                      onTap: () =>
                          Navigator.pop(context, subscriptions[index].id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (mounted && id != null) _selectSubscription(id);
  }

  void _selectSubscription(String? value) {
    final id = value ?? '';
    final subscription = _subscriptionWithId(widget.subscriptions, id);
    setState(() {
      _subscriptionId = id;
      if (subscription != null) {
        _serviceController.text = subscription.serviceName;
        _amountController.text = subscription.amount ?? '';
        _currency = subscription.currency;
        _categoryController.text =
            subscription.expenseCategory ?? _selectedAccount?.category ?? '';
      } else {
        _serviceController.clear();
        _amountController.clear();
        _categoryController.text = _selectedAccount?.category ?? '';
      }
    });
  }

  Future<void> _pickOccurredOn() async {
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

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final draft = SubscriptionExpenseDraft(
        paymentMethodId:
            _paymentMethodId ??
            _selectedSubscription?.management?.paymentMethodId,
        paymentMethodName:
            widget.paymentMethods
                .where((p) => p.id == _paymentMethodId)
                .firstOrNull
                ?.name ??
            widget.initial?.paymentMethodName ??
            _selectedSubscription?.paymentMethod,
        subscriptionId: _subscriptionId.isEmpty ? null : _subscriptionId,
        accountId: _accountId,
        serviceName: _serviceController.text,
        occurredOn: _occurredOn,
        amount: _amountController.text,
        currency: _currency,
        kind: _kind,
        expenseCategory: _categoryController.text,
        scheduledRenewalOn: widget.initial?.scheduledRenewalOn,
      );
      final success = await widget.onSave(draft);
      if (!mounted) return;
      if (success) {
        Navigator.pop(context, true);
        return;
      }
      setState(() => _saveError = context.tr('保存失败，记录未写入。'));
    } on Object {
      if (!mounted) return;
      setState(() => _saveError = context.tr('记录格式无效，请检查后重试。'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.label,
    required this.value,
    required this.onPressed,
    super.key,
  });

  final String label;
  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.calendar_month_outlined),
      label: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(
              value,
              translate: false,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({required this.initialMonth});

  final DateTime initialMonth;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _year = widget.initialMonth.year;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择月份'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: context.tr('上一年'),
                  onPressed: _year <= 1970
                      ? null
                      : () => setState(() => _year -= 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    context.tr('{year}年', <String, Object?>{'year': _year}),
                    translate: false,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: context.tr('下一年'),
                  onPressed: _year >= 2300
                      ? null
                      : () => setState(() => _year += 1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              childAspectRatio: 1.8,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (var month = 1; month <= 12; month += 1)
                  FilledButton.tonal(
                    key: ValueKey<String>('pick-month-$_year-$month'),
                    onPressed: () =>
                        Navigator.pop(context, DateTime(_year, month)),
                    child: Text(
                      localizedRecordMonth(context.l10n.language, month),
                      translate: false,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class _LineSummary {
  const _LineSummary({
    required this.originalTotals,
    required this.totalCny,
    required this.convertedCount,
    required this.excludedCount,
  });

  final List<SubscriptionCurrencyTotal> originalTotals;
  final double totalCny;
  final int convertedCount;
  final int excludedCount;
}

_LineSummary _summarizeLines(Iterable<SubscriptionCostLine> lines) {
  final totals = <String, BigInt>{};
  var totalCny = 0.0;
  var compensation = 0.0;
  var convertedCount = 0;
  var excludedCount = 0;
  for (final line in lines) {
    final amount = line.amount;
    if (amount == null) {
      excludedCount += 1;
      continue;
    }
    final scaled = parseScaledSubscriptionAmount(amount);
    totals.update(
      line.currency,
      (current) => current + (line.refund ? -scaled : scaled),
      ifAbsent: () => line.refund ? -scaled : scaled,
    );
    final parsed = double.tryParse(amount);
    final converted = parsed == null
        ? null
        : SemiannualCnyExchangeRates.convertToCny(
            currency: line.currency,
            amount: parsed,
          );
    if (converted == null) {
      excludedCount += 1;
      continue;
    }
    final signed = line.refund ? -converted : converted;
    final adjusted = signed - compensation;
    final next = totalCny + adjusted;
    compensation = (next - totalCny) - adjusted;
    totalCny = next;
    convertedCount += 1;
  }
  final currencyTotals = <SubscriptionCurrencyTotal>[
    for (final entry in totals.entries)
      SubscriptionCurrencyTotal(currency: entry.key, scaledAmount: entry.value),
  ]..sort((left, right) => left.currency.compareTo(right.currency));
  return _LineSummary(
    originalTotals: currencyTotals,
    totalCny: totalCny,
    convertedCount: convertedCount,
    excludedCount: excludedCount,
  );
}

String _formatCny(double value) {
  final absolute = value.abs().toStringAsFixed(2);
  return value < 0 ? '-¥$absolute' : '¥$absolute';
}

String _basisLabel(SubscriptionCostBasis basis) => switch (basis) {
  SubscriptionCostBasis.confirmed => '已确认支出',
  SubscriptionCostBasis.futureEstimate => '未来预计',
};

String _basisDescription(SubscriptionCostBasis basis) => switch (basis) {
  SubscriptionCostBasis.confirmed => '按已录入金额和账期逐期累计，已记录付款优先，退款按发生月份扣减。',
  SubscriptionCostBasis.futureEstimate => '按当前订阅金额、周期和状态预测，尚未实际发生。',
};

IconData _basisIcon(SubscriptionCostBasis basis) => switch (basis) {
  SubscriptionCostBasis.confirmed => Icons.verified_outlined,
  SubscriptionCostBasis.futureEstimate => Icons.query_stats_outlined,
};

Color _basisColor(BuildContext context, SubscriptionCostBasis basis) {
  final colors = Theme.of(context).colorScheme;
  return switch (basis) {
    SubscriptionCostBasis.confirmed => colors.primary,
    SubscriptionCostBasis.futureEstimate => colors.secondary,
  };
}

String _monthLabel(BuildContext context, DateTime value) => context.tr(
  '{year}年{month}月',
  <String, Object?>{'year': value.year, 'month': value.month},
);

String _monthKeyLabel(BuildContext context, String value) {
  final parts = value.split('-');
  final year = int.tryParse(parts.first);
  final month = parts.length == 2 ? int.tryParse(parts.last) : null;
  if (year == null || month == null) return value;
  return _monthLabel(context, DateTime(year, month));
}

String _categoryLabel(BuildContext context, String value) => value == '未分类'
    ? context.tr('未分类')
    : localizedAccountCategory(context.l10n.language, value);

SubscriptionRecord? _subscriptionWithId(
  Iterable<SubscriptionRecord> subscriptions,
  String id,
) {
  if (id.isEmpty) return null;
  for (final subscription in subscriptions) {
    if (subscription.id == id) return subscription;
  }
  return null;
}
