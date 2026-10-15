import 'calendar_reminder_page.dart';
import 'package:flutter/services.dart';
import '../../../app/app_state.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../domain/subscription_record.dart';
import '../domain/subscription_cost_summary.dart';

class SubscriptionManagementPanel extends StatelessWidget {
  const SubscriptionManagementPanel({
    required this.state,
    required this.subscription,
    this.onEdit,
    super.key,
  });
  final AppState state;
  final SubscriptionRecord subscription;
  final VoidCallback? onEdit;
  Future<void> _resolve(BuildContext context, TrialOutcome outcome) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认试用结果'),
        content: Text(
          outcome == TrialOutcome.cancelled
              ? '仅记录已取消；请确认你已自行到平台取消。'
              : '记录试用未继续；不会增加费用或推进续费日期。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await state.resolveTrial(
        subscriptionId: subscription.id,
        outcome: outcome,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = subscription.management, t = m?.trial, c = m?.cancellation;
    final writable = !state.hasSubscriptionOnlyAccess && !state.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('subscription-add-calendar'),
          onPressed: state.canOpenCalendar
              ? () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CalendarReminderPage(
                      state: state,
                      singleRecordId: subscription.id,
                    ),
                  ),
                )
              : null,
          icon: const Icon(Icons.event_outlined),
          label: const Text('加入系统日历'),
        ),
        if (!state.hasFullVaultAccess) const Text('请完整解锁当前保险库后加入系统日历。'),
        if (t != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('试用期', style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    '${formatSubscriptionDate(t.startsOn)} – ${formatSubscriptionDate(t.endsOn)}',
                    translate: false,
                  ),
                  Text(
                    context.tr('试用费用：{amount} {currency}', {
                      'amount': t.amount,
                      'currency': t.currency,
                    }),
                    translate: false,
                  ),
                  Text(
                    context.tr('正式方案：{amount} {currency}', {
                      'amount': t.formalAmount,
                      'currency': t.formalCurrency,
                    }),
                    translate: false,
                  ),
                  Text(
                    trialOutcomeLabel(
                      t.needsConfirmation(DateTime.now())
                          ? TrialOutcome.pending
                          : t.outcome,
                    ),
                  ),
                  if (t.firstPaidOn != null)
                    Text(
                      context.tr('预计首次扣费：{date}', {
                        'date': formatSubscriptionDate(t.firstPaidOn!),
                      }),
                      translate: false,
                    ),
                  if (t.lastConfirmedAt != null)
                    Text(
                      context.tr('上次确认：{date}', {
                        'date': t.lastConfirmedAt!.toLocal().toString(),
                      }),
                      translate: false,
                    ),
                  if (writable && t.unresolved)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (context) => TrialConversionDialog(
                              state: state,
                              subscription: subscription,
                            ),
                          ),
                          child: const Text('确认已转付费'),
                        ),
                        TextButton(
                          onPressed: onEdit,
                          child: const Text('修改试用日期'),
                        ),
                        TextButton(
                          onPressed: () =>
                              _resolve(context, TrialOutcome.cancelled),
                          child: const Text('已取消试用'),
                        ),
                        TextButton(
                          onPressed: () =>
                              _resolve(context, TrialOutcome.ended),
                          child: const Text('试用结束未继续'),
                        ),
                        if (!t.startsOn.isAfter(
                              subscriptionDateOnly(DateTime.now()),
                            ) &&
                            parseScaledSubscriptionAmount(t.amount) >
                                BigInt.zero &&
                            !state.subscriptionExpenses.any(
                              (e) =>
                                  e.subscriptionId == subscription.id &&
                                  e.source.name == 'trialPayment',
                            ))
                          TextButton(
                            onPressed: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: t.startsOn,
                                lastDate: DateTime.now(),
                              );
                              if (date == null || !context.mounted) return;
                              final yes = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('确认试用费已实际支付'),
                                  content: Text(
                                    '${t.amount} ${t.currency} · ${formatSubscriptionDate(date)}',
                                    translate: false,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('确认已支付'),
                                    ),
                                  ],
                                ),
                              );
                              if (yes == true) {
                                await state.confirmTrialPayment(
                                  subscription.id,
                                  date,
                                );
                              }
                            },
                            child: const Text('确认试用费已支付'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        Card(
          child: ExpansionTile(
            title: const Text('提醒规则'),
            children: [
              for (final rule in subscription.effectiveReminderRules)
                ListTile(
                  title: Text(reminderEventLabel(rule.event)),
                  subtitle: Text(
                    context.tr('提前天数：{days}', {
                      'days': rule.daysBefore.join(' / '),
                    }),
                    translate: false,
                  ),
                ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('通知仅显示通用文案。已过去的提醒点不会补发。'),
              ),
            ],
          ),
        ),
        if (c != null && !state.hasSubscriptionOnlyAccess)
          Card(
            child: ExpansionTile(
              title: const Text('取消指引'),
              children: [
                if (c.location != null)
                  ListTile(
                    title: const Text('取消位置'),
                    subtitle: Text(c.location!, translate: false),
                  ),
                if (c.steps != null)
                  ListTile(
                    title: const Text('取消步骤'),
                    subtitle: Text(c.steps!, translate: false),
                    trailing: IconButton(
                      tooltip: context.tr('复制步骤'),
                      icon: const Icon(Icons.copy),
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: c.steps!)),
                    ),
                  ),
                if (c.url != null)
                  ListTile(
                    title: const Text('取消链接'),
                    subtitle: Text(c.url!, translate: false),
                    trailing: IconButton(
                      tooltip: context.tr('复制链接'),
                      icon: const Icon(Icons.link),
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: c.url!)),
                    ),
                  ),
                if (c.channelNotes != null)
                  ListTile(
                    title: const Text('渠道备注'),
                    subtitle: Text(c.channelNotes!, translate: false),
                  ),
                ListTile(
                  title: const Text('人工确认日期'),
                  subtitle: Text(
                    c.manuallyConfirmedOn == null
                        ? context.tr('未确认')
                        : formatSubscriptionDate(c.manuallyConfirmedOn!),
                    translate: false,
                  ),
                ),
                if (writable)
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: onEdit,
                        child: const Text('编辑取消指引'),
                      ),
                      TextButton(
                        onPressed: () => state.saveSubscriptionManagement(
                          subscription.id,
                          m!.copyWith(
                            cancellation: SubscriptionCancellationInfo(
                              location: c.location,
                              url: c.url,
                              steps: c.steps,
                              channelNotes: c.channelNotes,
                              manuallyConfirmedOn: DateTime.now(),
                            ),
                          ),
                        ),
                        child: const Text('今天已人工确认'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        Card(
          child: ExpansionTile(
            title: const Text('价格与方案历史'),
            children: [
              if (m?.historyIncomplete ?? true)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('历史不完整。兼容基线用于延续原统计，不代表从首日就使用当前价格。'),
                ),
              if (m?.priceHistory.isEmpty ?? true)
                const ListTile(title: Text('尚无明确的价格变更记录')),
              for (final p in m?.priceHistory ?? <SubscriptionPricePoint>[])
                ListTile(
                  title: Text(
                    '${formatSubscriptionDate(p.effectiveOn)} · ${p.amount} ${p.currency}',
                    translate: false,
                  ),
                  subtitle: Text(
                    [
                      context.tr('周期：{count} {unit} · {kind}', {
                        'count': p.cycleCount,
                        'unit': context.tr(p.cycleUnit.label),
                        'kind': context.tr(priceKindLabel(p.kind)),
                      }),
                      _priceComparison(context, m!, p),
                      if (p.note != null) p.note!,
                    ].join('\n'),
                    translate: false,
                  ),
                  trailing: writable
                      ? IconButton(
                          tooltip: context.tr('删除历史记录'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deletePrice(context, p),
                        )
                      : null,
                ),
              if (writable)
                TextButton(onPressed: onEdit, child: const Text('记录价格或方案变更')),
            ],
          ),
        ),
      ],
    );
  }

  String _priceComparison(
    BuildContext context,
    SubscriptionManagement m,
    SubscriptionPricePoint p,
  ) {
    final previous =
        m.priceHistory
            .where((e) => e.effectiveOn.isBefore(p.effectiveOn))
            .lastOrNull ??
        m.compatibilityBaseline;
    if (previous == null) return context.tr('此前方案未记录');
    final oldLabel =
        '${previous.amount} ${previous.currency} · ${previous.cycleCount} ${context.tr(previous.cycleUnit.label)}';
    String change;
    if (previous.currency != p.currency) {
      change = context.tr('币种变化，不直接比较百分比');
    } else if (previous.cycleCount != p.cycleCount ||
        previous.cycleUnit != p.cycleUnit) {
      change = context.tr('计费周期变化');
    } else {
      final diff =
          parseScaledSubscriptionAmount(p.amount) -
          parseScaledSubscriptionAmount(previous.amount);
      change = diff == BigInt.zero
          ? context.tr('金额不变')
          : '${context.tr(diff.isNegative ? '降价' : '涨价')} ${formatScaledSubscriptionAmount(diff.abs())} ${p.currency}';
    }
    return '${context.tr('此前方案：{plan}', {'plan': oldLabel})}\n$change';
  }

  Future<void> _deletePrice(
    BuildContext context,
    SubscriptionPricePoint point,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除价格历史记录'),
        content: const Text('历史付款保持不变。当前方案会保留为今天的信息更正；未来预测按剩余历史计算。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final m = subscription.management!,
        today = subscriptionDateOnly(DateTime.now());
    var next = m.copyWith(
      priceHistory: m.priceHistory.where((p) => p.id != point.id).toList(),
    );
    final current = m.priceAt(today);
    if (!point.effectiveOn.isAfter(today) &&
        (current?.amount ?? subscription.amount) != null) {
      next = next.putPrice(
        SubscriptionPricePoint(
          id: 'price-${DateTime.now().toUtc().microsecondsSinceEpoch}',
          effectiveOn: today,
          amount: current?.amount ?? subscription.amount!,
          currency: current?.currency ?? subscription.currency,
          cycleCount: current?.cycleCount ?? subscription.cycleCount,
          cycleUnit: current?.cycleUnit ?? subscription.cycleUnit,
          kind: PriceChangeKind.correction,
          createdAt: DateTime.now(),
        ),
        replaceSameDay: true,
      );
    }
    await state.saveSubscriptionManagement(subscription.id, next);
  }
}

String trialOutcomeLabel(TrialOutcome outcome) => switch (outcome) {
  TrialOutcome.active => '试用中',
  TrialOutcome.pending => '待确认试用结果',
  TrialOutcome.converted => '已转付费',
  TrialOutcome.cancelled => '已取消试用',
  TrialOutcome.ended => '试用结束未继续',
};
String reminderEventLabel(SubscriptionReminderEvent e) => switch (e) {
  SubscriptionReminderEvent.renewal => '正式续费',
  SubscriptionReminderEvent.decision => '续费决策',
  SubscriptionReminderEvent.trialEnd => '试用结束',
};
String priceKindLabel(PriceChangeKind k) => switch (k) {
  PriceChangeKind.correction => '信息更正',
  PriceChangeKind.change => '方案变更',
  PriceChangeKind.backfill => '历史补录',
  PriceChangeKind.baseline => '兼容基线',
};

class TrialConversionDialog extends StatefulWidget {
  const TrialConversionDialog({
    required this.state,
    required this.subscription,
    super.key,
  });
  final AppState state;
  final SubscriptionRecord subscription;
  @override
  State<TrialConversionDialog> createState() => _TrialConversionDialogState();
}

class _TrialConversionDialogState extends State<TrialConversionDialog> {
  late final _amount = TextEditingController(
    text: widget.subscription.management!.trial!.formalAmount,
  );
  late final _currency = TextEditingController(
    text: widget.subscription.management!.trial!.formalCurrency,
  );
  final _date = TextEditingController(
    text: formatSubscriptionDate(DateTime.now()),
  );
  bool _paid = false, _busy = false;
  String? _error;
  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final saved = await widget.state.resolveTrial(
        subscriptionId: widget.subscription.id,
        outcome: TrialOutcome.converted,
        actualPaidOn: parseSubscriptionDate(_date.text.trim()),
        actualAmount: _amount.text.trim(),
        actualCurrency: _currency.text.trim(),
        paymentConfirmed: _paid,
      );
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context);
        return;
      }
      setState(() => _error = '保存失败或试用已处理，请检查当前记录。');
    } on Object {
      if (mounted) setState(() => _error = '请检查实际日期、金额与币种。');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('确认已转付费'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _date,
            decoration: const InputDecoration(labelText: '实际转付费日期（YYYY-MM-DD）'),
          ),
          TextFormField(
            controller: _amount,
            decoration: const InputDecoration(labelText: '实际正式金额'),
          ),
          TextFormField(
            controller: _currency,
            decoration: const InputDecoration(labelText: '实际正式币种'),
          ),
          CheckboxListTile(
            value: _paid,
            onChanged: _busy ? null : (v) => setState(() => _paid = v ?? false),
            title: const Text('我确认这笔费用已经实际支付'),
          ),
          const Text('仅勾选实际已支付才新增一笔费用。确认后保留试用历史，按实际日期计算下一续费日。'),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('确认结果')),
    ],
  );
}
