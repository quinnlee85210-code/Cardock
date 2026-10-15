import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../domain/subscription_record.dart';

Future<SubscriptionDetailsDraft?> reviewSubscriptionPriceChange(
  BuildContext context,
  SubscriptionRecord? existing,
  SubscriptionDetailsDraft draft,
) async {
  if (existing == null ||
      existing.isUnresolvedTrial ||
      (existing.amount == draft.amount &&
          existing.currency == draft.currency &&
          existing.cycleCount == draft.cycleCount &&
          existing.cycleUnit == draft.cycleUnit)) {
    return draft;
  }
  return showDialog<SubscriptionDetailsDraft>(
    context: context,
    builder: (context) => _PriceReview(existing: existing, draft: draft),
  );
}

class _PriceReview extends StatefulWidget {
  const _PriceReview({required this.existing, required this.draft});
  final SubscriptionRecord existing;
  final SubscriptionDetailsDraft draft;
  @override
  State<_PriceReview> createState() => _PriceReviewState();
}

class _PriceReviewState extends State<_PriceReview> {
  PriceChangeKind? _kind;
  final _date = TextEditingController(
    text: formatSubscriptionDate(DateTime.now()),
  );
  final _note = TextEditingController();
  bool _replace = false;
  String? _error;
  @override
  void dispose() {
    _date.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final kind = _kind;
      if (kind == null) throw ArgumentError('请选择金额或方案变更的含义');
      final date = parseSubscriptionDate(_date.text.trim()),
          today = subscriptionDateOnly(DateTime.now());
      if (kind == PriceChangeKind.correction && date != today) {
        throw ArgumentError('当前信息更正使用今天；过去生效请选择补录');
      }
      if (kind == PriceChangeKind.backfill && date.isAfter(today)) {
        throw ArgumentError('补录日期不能晚于今天');
      }
      final old = widget.existing, draft = widget.draft;
      if (draft.amount == null) throw ArgumentError('价格变更需要明确金额');
      var management =
          draft.management ??
          SubscriptionManagement(reminderRules: old.effectiveReminderRules);
      if (management.compatibilityBaseline == null && old.amount != null) {
        management = management.copyWith(
          compatibilityBaseline: SubscriptionPricePoint(
            id: 'legacy-baseline',
            effectiveOn: DateTime(1970),
            amount: old.amount!,
            currency: old.currency,
            cycleCount: old.cycleCount,
            cycleUnit: old.cycleUnit,
            kind: PriceChangeKind.baseline,
            createdAt: DateTime.utc(1970),
          ),
        );
      }
      management = management.putPrice(
        SubscriptionPricePoint(
          id: 'price-${DateTime.now().toUtc().microsecondsSinceEpoch}',
          effectiveOn: date,
          amount: draft.amount!,
          currency: draft.currency,
          cycleCount: draft.cycleCount,
          cycleUnit: draft.cycleUnit,
          kind: kind,
          createdAt: DateTime.now(),
          note: _note.text,
        ),
        replaceSameDay: _replace,
      );
      final current = management.priceAt(today);
      Navigator.pop(
        context,
        draft.copyWith(
          management: management,
          amount: current?.amount ?? old.amount,
          currency: current?.currency ?? old.currency,
          cycleCount: current?.cycleCount ?? old.cycleCount,
          cycleUnit: current?.cycleUnit ?? old.cycleUnit,
        ),
      );
    } on Object {
      setState(() => _error = '请选择有效的变更方式和日期；同日已有方案时需确认覆盖。');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('确认价格或方案变更'),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr('原方案：{amount} {currency} · {cycle}', {
                'amount': widget.existing.amount ?? context.tr('未记录'),
                'currency': widget.existing.currency,
                'cycle': context.tr(widget.existing.cycleLabel),
              }),
              translate: false,
            ),
            Text(
              context.tr('新方案：{amount} {currency}', {
                'amount': widget.draft.amount ?? context.tr('未记录'),
                'currency': widget.draft.currency,
              }),
              translate: false,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PriceChangeKind>(
              isExpanded: true,
              decoration: const InputDecoration(labelText: '变更含义'),
              items: [
                for (final k in [
                  PriceChangeKind.correction,
                  PriceChangeKind.change,
                  PriceChangeKind.backfill,
                ])
                  DropdownMenuItem(
                    value: k,
                    child: Text(switch (k) {
                      PriceChangeKind.correction => '更正当前信息',
                      PriceChangeKind.change => '从指定日期变更',
                      _ => '补录过去变更',
                    }),
                  ),
              ],
              onChanged: (v) => setState(() => _kind = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _date,
              decoration: const InputDecoration(labelText: '生效日期（YYYY-MM-DD）'),
            ),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: '方案备注'),
            ),
            CheckboxListTile(
              value: _replace,
              onChanged: (v) => setState(() => _replace = v ?? false),
              title: const Text('同一天已有方案时覆盖该条记录'),
            ),
            const Text('已确认的历史付款不会改变。更正当前信息不会被当作普通涨价；旧历史不完整时保留兼容基线。'),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
      FilledButton(onPressed: _save, child: const Text('确认方案')),
    ],
  );
}
