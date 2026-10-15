import '../../../l10n/localized_material.dart';
import '../domain/subscription_record.dart';

Map<String, Object?> subscriptionAdvancedFields(
  SubscriptionDetailsDraft? initial,
) {
  final m = initial?.management, t = m?.trial, c = m?.cancellation;
  return {
    'trialEnabled': t != null,
    'trialPersisted': t != null,
    'trialStart': t == null ? '' : formatSubscriptionDate(t.startsOn),
    'trialEnd': t == null ? '' : formatSubscriptionDate(t.endsOn),
    'trialAmount': t?.amount ?? '0',
    'trialCurrency': t?.currency ?? initial?.currency ?? 'CNY',
    'trialAuto': t?.expectedAutoConvert ?? false,
    'trialFirstPaid': t?.firstPaidOn == null
        ? ''
        : formatSubscriptionDate(t!.firstPaidOn!),
    'formalAmount': t?.formalAmount ?? '',
    'formalCurrency': t?.formalCurrency ?? '',
    'renewalDays':
        m?.reminderRules
            .where((r) => r.event == SubscriptionReminderEvent.renewal)
            .firstOrNull
            ?.daysBefore
            .join(',') ??
        (initial == null
            ? '3,0'
            : initial.reminderEnabled
            ? '${initial.reminderDaysBefore}'
            : ''),
    'decisionDays':
        m?.reminderRules
            .where((r) => r.event == SubscriptionReminderEvent.decision)
            .firstOrNull
            ?.daysBefore
            .join(',') ??
        '',
    'trialDays':
        m?.reminderRules
            .where((r) => r.event == SubscriptionReminderEvent.trialEnd)
            .firstOrNull
            ?.daysBefore
            .join(',') ??
        '3,1,0',
    'cancelLocation': c?.location ?? '',
    'cancelUrl': c?.url ?? '',
    'cancelSteps': c?.steps ?? '',
    'cancelNotes': c?.channelNotes ?? '',
    'cancelConfirmed': c?.manuallyConfirmedOn == null
        ? ''
        : formatSubscriptionDate(c!.manuallyConfirmedOn!),
    'subscriptionNotes': initial?.notes ?? '',
  };
}

SubscriptionDetailsDraft applySubscriptionAdvancedFields(
  SubscriptionDetailsDraft base,
  Map<String, Object?> f,
) {
  String text(String k) => f[k] as String? ?? '';
  DateTime? optionalDate(String k) =>
      text(k).trim().isEmpty ? null : parseSubscriptionDate(text(k).trim());
  final previous = base.management;
  SubscriptionTrial? trial = previous?.trial;
  if (f['trialEnabled'] == true && (trial == null || trial.unresolved)) {
    trial = SubscriptionTrial(
      startsOn: optionalDate('trialStart') ?? base.firstSubscribedOn,
      endsOn: optionalDate('trialEnd') ?? (throw ArgumentError('请填写试用结束日期')),
      amount: text('trialAmount'),
      currency: text('trialCurrency'),
      expectedAutoConvert: f['trialAuto'] == true,
      firstPaidOn: optionalDate('trialFirstPaid'),
      formalAmount: text('formalAmount').trim().isEmpty
          ? (base.amount ?? (throw ArgumentError('请填写正式方案金额')))
          : text('formalAmount'),
      formalCurrency: text('formalCurrency').trim().isEmpty
          ? base.currency
          : text('formalCurrency'),
      formalCycleCount: base.cycleCount,
      formalCycleUnit: base.cycleUnit,
      outcome: trial?.outcome ?? TrialOutcome.active,
      lastConfirmedAt: trial?.lastConfirmedAt,
    );
  }
  final rules = <SubscriptionReminderRule>[];
  for (final entry in {
    'renewalDays': SubscriptionReminderEvent.renewal,
    'decisionDays': SubscriptionReminderEvent.decision,
    'trialDays': SubscriptionReminderEvent.trialEnd,
  }.entries) {
    final raw = text(entry.key).trim();
    if (raw.isEmpty ||
        (entry.value == SubscriptionReminderEvent.trialEnd && trial == null)) {
      continue;
    }
    final tokens = raw.split(RegExp(r'[,，\s]+'));
    final days = tokens.map((v) => int.tryParse(v) ?? -1).toList();
    rules.add(SubscriptionReminderRule(event: entry.value, daysBefore: days));
  }
  final cancellation = SubscriptionCancellationInfo(
    location: text('cancelLocation'),
    url: text('cancelUrl'),
    steps: text('cancelSteps'),
    channelNotes: text('cancelNotes'),
    manuallyConfirmedOn: optionalDate('cancelConfirmed'),
  );
  return base.copyWith(
    notes: text('subscriptionNotes'),
    management: SubscriptionManagement(
      trial: trial,
      reminderRules: rules,
      cancellation: cancellation,
      priceHistory: previous?.priceHistory ?? [],
      paymentMethodId: previous?.paymentMethodId,
      historyIncomplete: previous?.historyIncomplete ?? true,
      compatibilityBaseline: previous?.compatibilityBaseline,
    ),
  );
}

class SubscriptionAdvancedFields extends StatefulWidget {
  const SubscriptionAdvancedFields({
    required this.fields,
    required this.onChanged,
    this.trialResolved = false,
    super.key,
  });
  final Map<String, Object?> fields;
  final ValueChanged<Map<String, Object?>> onChanged;
  final bool trialResolved;
  @override
  State<SubscriptionAdvancedFields> createState() =>
      _SubscriptionAdvancedFieldsState();
}

class _SubscriptionAdvancedFieldsState
    extends State<SubscriptionAdvancedFields> {
  final _controllers = <String, TextEditingController>{};
  late final _values = Map<String, Object?>.of(widget.fields);
  void _set(String key, Object? value) {
    _values[key] = value;
    widget.onChanged(Map.of(_values));
  }

  TextEditingController _controller(String key) => _controllers.putIfAbsent(
    key,
    () => TextEditingController(text: _values[key] as String? ?? ''),
  );
  Widget _text(String key, String label, {int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: ValueKey('stage2-$key'),
      controller: _controller(key),
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
      onChanged: (v) => _set(key, v),
    ),
  );
  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _preset(String key, String value) {
    _controller(key).text = value;
    _set(key, value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ExpansionTile(
        title: const Text('试用期'),
        subtitle: const Text('到期后需人工确认，不会自动记为已付款'),
        children: [
          if (widget.trialResolved)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('试用结果已保留，请在详情查看历史。'),
            )
          else ...[
            SwitchListTile(
              title: const Text('这是一项试用'),
              value: _values['trialEnabled'] == true,
              onChanged: widget.fields['trialPersisted'] == true
                  ? null
                  : (v) => setState(() => _set('trialEnabled', v)),
            ),
            if (_values['trialEnabled'] == true)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _text('trialStart', '试用开始日期（YYYY-MM-DD，可留空）'),
                    _text('trialEnd', '试用结束日期（YYYY-MM-DD）'),
                    _text('trialAmount', '试用费用'),
                    _text('trialCurrency', '试用币种'),
                    SwitchListTile(
                      title: const Text('预计自动转付费'),
                      value: _values['trialAuto'] == true,
                      onChanged: (v) => setState(() => _set('trialAuto', v)),
                    ),
                    _text('trialFirstPaid', '预计首次扣费日期（YYYY-MM-DD，可留空）'),
                    _text('formalAmount', '正式方案金额（留空使用上方金额）'),
                    _text('formalCurrency', '正式方案币种（留空使用上方币种）'),
                    const Text('正式计费周期使用上方周期。非零试用费需保存后在详情确认实际已支付。'),
                  ],
                ),
              ),
          ],
        ],
      ),
      ExpansionTile(
        title: const Text('多点提醒'),
        subtitle: const Text('每种事件最多8点，以逗号分隔提前天数'),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => _preset('renewalDays', '3,0'),
                      child: const Text('普通续费 3/0'),
                    ),
                    TextButton(
                      onPressed: () => _preset('decisionDays', '30,7,1,0'),
                      child: const Text('年费决策 30/7/1/0'),
                    ),
                    TextButton(
                      onPressed: () => _preset('trialDays', '3,1,0'),
                      child: const Text('试用结束 3/1/0'),
                    ),
                  ],
                ),
                _text('renewalDays', '正式续费提醒点'),
                _text('decisionDays', '续费决策提醒点'),
                _text('trialDays', '试用结束提醒点'),
                const Text('留空关闭该事件。使用手机本地日期与全局提醒时间，不补发已过去的提醒。'),
              ],
            ),
          ),
        ],
      ),
      ExpansionTile(
        title: const Text('取消指引'),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _text('cancelLocation', '取消位置'),
                _text('cancelUrl', '取消链接（HTTP(S)，仅保存文本）'),
                _text('cancelSteps', '取消步骤', lines: 4),
                _text('cancelNotes', '渠道备注', lines: 2),
                _text('cancelConfirmed', '人工确认日期（YYYY-MM-DD，可留空）'),
                const Text('取消状态仅为本机记录；请自行到平台完成取消。'),
              ],
            ),
          ),
        ],
      ),
      ExpansionTile(
        title: const Text('订阅备注'),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: _text('subscriptionNotes', '订阅备注', lines: 4),
          ),
        ],
      ),
    ],
  );
}
