import '../../../app/app_state.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../domain/subscription_cost_summary.dart';
import '../domain/subscription_expense_record.dart';
import '../domain/subscription_insights.dart';
import '../domain/subscription_record.dart';
import 'payment_methods_page.dart';

class SubscriptionInsightsPage extends StatefulWidget {
  const SubscriptionInsightsPage({
    required this.state,
    required this.onOpenSubscription,
    this.embedded = false,
    super.key,
  });
  final AppState state;
  final bool embedded;
  final ValueChanged<SubscriptionRecord> onOpenSubscription;
  @override
  State<SubscriptionInsightsPage> createState() =>
      _SubscriptionInsightsPageState();
}

class _SubscriptionInsightsPageState extends State<SubscriptionInsightsPage> {
  String? _method, _category, _account;
  int? _selectedMonth;
  Widget _filter(
    String label,
    Map<String, String> options,
    String? selected,
    ValueChanged<String?> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$selected'),
      initialValue: options.containsKey(selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text('全部')),
        ...options.entries.map(
          (e) => DropdownMenuItem(
            value: e.key,
            child: Text(
              e.value,
              translate: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: onChanged,
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded
        ? null
        : AppBar(
            title: const Text('费用洞察'),
            actions: [
              if (!widget.state.hasSubscriptionOnlyAccess)
                IconButton(
                  tooltip: context.tr('管理支付方式'),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          PaymentMethodsPage(state: widget.state),
                    ),
                  ),
                ),
            ],
          ),
    body: ListenableBuilder(
      listenable: widget.state,
      builder: (context, child) {
        final state = widget.state;
        final records = state.subscriptions
            .where(
              (s) =>
                  (_method == null ||
                      (s.management?.paymentMethodId ?? '') == _method) &&
                  (_category == null ||
                      (s.expenseCategory ?? '') == _category) &&
                  (_account == null || (s.accountId ?? '') == _account),
            )
            .toList();
        final monthly = monthlyEquivalentLines(records, DateTime.now()),
            forecast = SubscriptionForecast.build(records, DateTime.now());
        final current = monthlyEquivalentTotals(monthly),
            potential = monthlyEquivalentTotals(monthly, potential: true);
        final payments = state.subscriptionExpenses.where(
          (e) =>
              e.source != SubscriptionExpenseSource.subscriptionEntry &&
              (_method == null || (e.paymentMethodId ?? '') == _method) &&
              (_category == null || (e.expenseCategory ?? '') == _category) &&
              (_account == null || (e.accountId ?? '') == _account),
        );
        final paidTotals = <String, BigInt>{};
        for (final p in payments) {
          paidTotals[p.currency] =
              (paidTotals[p.currency] ?? BigInt.zero) +
              (p.kind == SubscriptionExpenseKind.refund
                  ? -parseScaledSubscriptionAmount(p.amount)
                  : parseScaledSubscriptionAmount(p.amount));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            const Text('月等效、未来预测与实际付款分别计算。各币种独立汇总；本页不会推进日期或写入费用。'),
            const SizedBox(height: 12),
            ExpansionTile(
              title: const Text('费用筛选'),
              children: [
                _filter(
                  '支付方式',
                  {
                    '': context.tr('未设置'),
                    for (final p in state.paymentMethods) p.id: p.name,
                  },
                  _method,
                  (v) => setState(() => _method = v),
                ),
                _filter(
                  '费用分类',
                  {
                    for (final s in state.subscriptions)
                      (s.expenseCategory ?? ''):
                          s.expenseCategory ?? context.tr('未分类'),
                  },
                  _category,
                  (v) => setState(() => _category = v),
                ),
                if (!state.hasSubscriptionOnlyAccess)
                  _filter(
                    '关联账号',
                    {
                      '': context.tr('独立订阅'),
                      for (final a in state.accounts) a.id: a.platformName,
                    },
                    _account,
                    (v) => setState(() => _account = v),
                  ),
                TextButton(
                  onPressed: () => setState(() {
                    _method = null;
                    _category = null;
                    _account = null;
                  }),
                  child: const Text('清除筛选'),
                ),
              ],
            ),
            _heading(context, '当前有效订阅月等效费用'),
            Text(
              current.isEmpty
                  ? context.tr('暂无可计算的正式订阅')
                  : current.entries
                        .map((e) => '${e.key} ${e.value.display}')
                        .join(' · '),
              translate: false,
            ),
            const Text('包含手动续费；不包含试用、暂停、取消、到期和回收站。天/周周期使用平均月长估算。'),
            if (potential.isNotEmpty) ...[
              _heading(context, '试用转付费潜在月均'),
              Text(
                potential.entries
                    .map((e) => '${e.key} ${e.value.display}')
                    .join(' · '),
                translate: false,
              ),
            ],
            ExpansionTile(
              title: const Text('月等效明细'),
              children: [
                for (final l in monthly)
                  ListTile(
                    onTap: () => widget.onOpenSubscription(l.subscription),
                    title: Text(
                      '${l.subscription.serviceName}${l.subscription.planName == null ? '' : ' · ${l.subscription.planName}'}',
                      translate: false,
                    ),
                    subtitle: Text(
                      '${l.originalAmount} ${l.currency} / ${l.count} ${context.tr(l.unit.label)}\n${l.subscription.paymentMethod ?? context.tr('未设置')} · ${context.tr(l.potential ? '潜在试用' : '正常')}',
                      translate: false,
                    ),
                    trailing: Text(
                      '${l.currency} ${l.amount.display}\n${context.tr(l.estimated ? '估算月均' : '月等效')}',
                      translate: false,
                    ),
                  ),
              ],
            ),
            _heading(context, '未来12个月预计续费支出'),
            const Text('从今天起计算，展示当前自然月及之后11个月。全部为预计支出，不代表已扣款。'),
            for (final currency
                in forecast.lines.map((l) => l.currency).toSet())
              _chart(context, forecast, currency),
            const SizedBox(height: 8),
            Text(
              context.tr('参与预测的订阅：{count}', {
                'count': forecast.lines
                    .map((l) => l.subscription.id)
                    .toSet()
                    .length,
              }),
              translate: false,
            ),
            for (final exclusion in forecast.excluded.entries)
              Text(
                context.tr('{reason}：{count} 条', {
                  'reason': context.tr(forecastExclusionLabel(exclusion.key)),
                  'count': exclusion.value,
                }),
                translate: false,
              ),
            for (var i = 0; i < forecast.months.length; i++)
              ListTile(
                key: ValueKey('forecast-month-$i'),
                selected: _selectedMonth == i,
                title: Text(
                  '${forecast.months[i].year}-${forecast.months[i].month.toString().padLeft(2, '0')}',
                  translate: false,
                ),
                subtitle: Text(
                  forecast
                          .totalsForMonth(forecast.months[i])
                          .entries
                          .map(
                            (e) =>
                                '${e.key} ${formatScaledSubscriptionAmount(e.value)}',
                          )
                          .join(' · ')
                          .isEmpty
                      ? context.tr('无预计支出')
                      : forecast
                            .totalsForMonth(forecast.months[i])
                            .entries
                            .map(
                              (e) =>
                                  '${e.key} ${formatScaledSubscriptionAmount(e.value)}',
                            )
                            .join(' · '),
                  translate: false,
                ),
                trailing: const Icon(Icons.expand_more),
                onTap: () => setState(
                  () => _selectedMonth = _selectedMonth == i ? null : i,
                ),
              ),
            if (_selectedMonth != null) ...[
              for (final line in forecast.lines.where(
                (l) =>
                    l.date.year == forecast.months[_selectedMonth!].year &&
                    l.date.month == forecast.months[_selectedMonth!].month,
              ))
                ListTile(
                  onTap: () => widget.onOpenSubscription(line.subscription),
                  title: Text(line.subscription.serviceName, translate: false),
                  subtitle: Text(
                    '${formatSubscriptionDate(line.date)} · ${line.subscription.paymentMethod ?? context.tr('未设置')} · ${context.tr(line.fromTrial ? '预计试用转付费' : '预计续费')}',
                    translate: false,
                  ),
                  trailing: Text(
                    '${line.currency} ${line.amount}',
                    translate: false,
                  ),
                ),
            ],
            _heading(context, '明确付款记录净额'),
            Text(
              paidTotals.isEmpty
                  ? context.tr('暂无明确付款记录')
                  : paidTotals.entries
                        .map(
                          (e) =>
                              '${e.key} ${formatScaledSubscriptionAmount(e.value)}',
                        )
                        .join(' · '),
              translate: false,
            ),
            Text(
              context.tr('当前筛选订阅数：{count}', {'count': records.length}),
              translate: false,
            ),
            const Text('退款按实际发生日期计入。旧记录缺少支付方式时显示未记录；历史账期推算不计入这里的明确付款。'),
          ],
        );
      },
    ),
  );
  Widget _heading(BuildContext context, String value) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(value, style: Theme.of(context).textTheme.titleMedium),
  );
  Widget _chart(BuildContext context, SubscriptionForecast f, String currency) {
    final values = [
      for (final m in f.months) f.totalsForMonth(m)[currency] ?? BigInt.zero,
    ];
    final maximum = values.fold(BigInt.one, (a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(currency, translate: false),
          SizedBox(
            height: 170,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 12; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      label:
                          '${f.months[i].year}-${f.months[i].month} $currency ${formatScaledSubscriptionAmount(values[i])}',
                      child: InkWell(
                        onTap: () => setState(() => _selectedMonth = i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height:
                                    ((values[i] * BigInt.from(88)) ~/ maximum)
                                        .toDouble() +
                                    2,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              Text(
                                '${f.months[i].month}',
                                translate: false,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String forecastExclusionLabel(ForecastExclusion reason) => switch (reason) {
  ForecastExclusion.inactive => '暂停、取消或到期',
  ForecastExclusion.missingAmount => '金额未记录',
  ForecastExclusion.overdue => '逾期待确认',
  ForecastExclusion.trialPending => '试用结果待确认',
  ForecastExclusion.trialNoConversion => '试用不自动转付费',
  ForecastExclusion.missingTrialDate => '试用首次扣费日期未记录',
  ForecastExclusion.invalidRange => '超出可预测范围',
};

class SubscriptionAttentionBanner extends StatefulWidget {
  const SubscriptionAttentionBanner({
    required this.state,
    required this.onOpen,
    super.key,
  });
  final AppState state;
  final ValueChanged<SubscriptionRecord> onOpen;
  @override
  State<SubscriptionAttentionBanner> createState() =>
      _SubscriptionAttentionBannerState();
}

class _SubscriptionAttentionBannerState
    extends State<SubscriptionAttentionBanner> {
  String? _dismissedOn;
  @override
  Widget build(BuildContext context) {
    final today = formatSubscriptionDate(DateTime.now()),
        items = subscriptionAttention(
          widget.state.subscriptions,
          DateTime.now(),
        );
    if (items.isEmpty || _dismissedOn == today) return const SizedBox.shrink();
    return MaterialBanner(
      content: Text(
        context.tr('有 {count} 项订阅需要确认', {'count': items.length}),
        translate: false,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => SubscriptionAttentionPage(
                state: widget.state,
                onOpen: widget.onOpen,
              ),
            ),
          ),
          child: const Text('查看待处理'),
        ),
        TextButton(
          onPressed: () => setState(() => _dismissedOn = today),
          child: const Text('今天稍后处理'),
        ),
      ],
    );
  }
}

class SubscriptionAttentionPage extends StatelessWidget {
  const SubscriptionAttentionPage({
    required this.state,
    required this.onOpen,
    super.key,
  });
  final AppState state;
  final ValueChanged<SubscriptionRecord> onOpen;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('订阅待处理中心')),
    body: ListenableBuilder(
      listenable: state,
      builder: (context, child) {
        final items = subscriptionAttention(
          state.subscriptions,
          DateTime.now(),
        );
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('日期到达不会自动记账或判断扣款结果。打开详情确认续费、修改日期、暂停、取消或处理试用结果。'),
            if (items.isEmpty) const ListTile(title: Text('暂无待处理订阅')),
            for (final kind in SubscriptionAttentionKind.values)
              if (items.any((i) => i.kind == kind)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(switch (kind) {
                    SubscriptionAttentionKind.overdue => '正式订阅逾期',
                    SubscriptionAttentionKind.trialEnded => '试用已结束',
                    SubscriptionAttentionKind.trialConversionDue => '预计转付费待确认',
                  }, style: Theme.of(context).textTheme.titleMedium),
                ),
                for (final item in items.where((i) => i.kind == kind))
                  ListTile(
                    title: Text(
                      item.subscription.serviceName,
                      translate: false,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onOpen(item.subscription),
                  ),
              ],
          ],
        );
      },
    ),
  );
}
