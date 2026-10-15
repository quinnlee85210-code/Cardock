import '../../../app/app_state.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../../subscriptions/domain/pending_subscription_draft.dart';
import '../../subscriptions/domain/subscription_record.dart';
import '../../subscriptions/presentation/subscription_form_fields.dart';

class PendingSubscriptionDraftsPage extends StatelessWidget {
  const PendingSubscriptionDraftsPage({required this.appState, super.key});

  final AppState appState;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appState,
    builder: (context, child) {
      final drafts = appState.pendingSubscriptionDrafts;
      return Scaffold(
        appBar: AppBar(title: const Text('待完善订阅')),
        body: drafts.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('没有待完善订阅。批量导入中的不完整订阅会加密保存在这里。'),
                ),
              )
            : ListView.separated(
                key: const ValueKey<String>('pending-subscription-list'),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: drafts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final draft = drafts[index];
                  final account = appState.accounts
                      .where((item) => item.id == draft.accountId)
                      .firstOrNull;
                  final title =
                      draft.planName ??
                      account?.platformName ??
                      context.tr('待完善订阅');
                  return Card(
                    child: ListTile(
                      key: ValueKey<String>(
                        'pending-subscription-${draft.draftId}',
                      ),
                      leading: const Icon(Icons.edit_calendar_outlined),
                      title: Text(title, translate: false),
                      subtitle: Text(
                        context.tr(
                          '关联 {account} · 还需完善 {count} 项',
                          <String, Object?>{
                            'account': account?.platformName ?? '—',
                            'count': draft.missingFormalFields.length,
                          },
                        ),
                        translate: false,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap:
                          !appState.isUnlocked ||
                              !appState.hasFullVaultAccess ||
                              appState.isBusy ||
                              account == null
                          ? null
                          : () => _openCompletion(context, draft),
                    ),
                  );
                },
              ),
      );
    },
  );

  Future<void> _openCompletion(
    BuildContext context,
    PendingSubscriptionDraft draft,
  ) async {
    final account = appState.accounts
        .where((item) => item.id == draft.accountId)
        .firstOrNull;
    if (account == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => _PendingSubscriptionCompletionPage(
          appState: appState,
          draft: draft,
          accountName: account.platformName,
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('订阅已完善并加密保存。')));
  }
}

class _PendingSubscriptionCompletionPage extends StatefulWidget {
  const _PendingSubscriptionCompletionPage({
    required this.appState,
    required this.draft,
    required this.accountName,
  });

  final AppState appState;
  final PendingSubscriptionDraft draft;
  final String accountName;

  @override
  State<_PendingSubscriptionCompletionPage> createState() =>
      _PendingSubscriptionCompletionPageState();
}

class _PendingSubscriptionCompletionPageState
    extends State<_PendingSubscriptionCompletionPage> {
  final _formKey = GlobalKey<FormState>();
  SubscriptionFormController? _controller;
  final TextEditingController _cycleCountController = TextEditingController();
  final TextEditingController _reminderDaysController = TextEditingController();
  DateTime? _startDate;
  DateTime? _renewalDate;
  SubscriptionCycleUnit? _cycleUnit;
  bool? _autoRenew;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    _startDate = draft.subscriptionStartDate;
    _renewalDate = draft.nextRenewalDate;
    _cycleUnit = draft.billingCycle?.unit;
    _autoRenew = draft.autoRenew;
    if (draft.billingCycle != null) {
      _cycleCountController.text = draft.billingCycle!.count.toString();
    }
    if (draft.reminderDays != null) {
      _reminderDaysController.text = draft.reminderDays.toString();
    }
    if (_requiredChoicesComplete) _createFormController();
  }

  bool get _requiredChoicesComplete {
    final cycleCount = int.tryParse(_cycleCountController.text.trim());
    final reminderDays = int.tryParse(_reminderDaysController.text.trim());
    return _startDate != null &&
        _renewalDate != null &&
        !_renewalDate!.isBefore(_startDate!) &&
        _cycleUnit != null &&
        _autoRenew != null &&
        cycleCount != null &&
        cycleCount > 0 &&
        reminderDays != null &&
        reminderDays >= 0 &&
        reminderDays <= 365;
  }

  void _createFormController() {
    if (!_requiredChoicesComplete) return;
    final draft = widget.draft;
    final start = _startDate!;
    final renewal = _renewalDate!;
    _controller = SubscriptionFormController(
      initial: SubscriptionDetailsDraft(
        serviceName: widget.accountName,
        planName: draft.planName,
        amount: draft.amount,
        currency: draft.currency ?? '',
        firstSubscribedOn: start,
        nextRenewalOn: renewal,
        cycleCount: int.parse(_cycleCountController.text.trim()),
        cycleUnit: _cycleUnit!,
        autoRenew: _autoRenew!,
        paymentMethod: draft.paymentMethod,
        reminderDaysBefore: int.parse(_reminderDaysController.text.trim()),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _cycleCountController.dispose();
    _reminderDaysController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final controller = _controller;
    if (_working ||
        controller == null ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final result = await widget.appState.completePendingSubscriptionDraft(
        draftId: widget.draft.draftId,
        details: controller.toDraft(),
      );
      if (!mounted) return;
      if (result.saved) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _error = widget.appState.errorMessage ?? '订阅内容仍不完整或数量限制已变化；原草稿已保留。';
        });
      }
    } on ArgumentError catch (error) {
      if (mounted) setState(() => _error = error.message?.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('继续完善订阅')),
      body: controller == null
          ? _buildRequiredChoices(context)
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                children: [
                  ListTile(
                    leading: const Icon(Icons.link_outlined),
                    title: const Text('关联账号'),
                    subtitle: Text(widget.accountName, translate: false),
                  ),
                  const SizedBox(height: 12),
                  SubscriptionFormFields(
                    controller: controller,
                    keyPrefix: 'pending-subscription',
                  ),
                  if (_error case final error?) ...[
                    const SizedBox(height: 12),
                    Text(
                      context.tr(error),
                      translate: false,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: FilledButton.icon(
          key: const ValueKey<String>('complete-pending-subscription'),
          onPressed: _working || controller == null ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_working ? '正在保存…' : '完成并转为正式订阅'),
        ),
      ),
    );
  }

  Widget _buildRequiredChoices(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    children: [
      const Text(
        '先确认导出文件中缺失的正式订阅字段。Cardock 不会用续费日期代替首次订阅日期，也不会猜测日期、账单周期、自动续费或提醒天数。',
      ),
      const SizedBox(height: 16),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('首次订阅日期'),
        subtitle: Text(
          _startDate == null
              ? context.tr('尚未选择')
              : '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
          translate: false,
        ),
        trailing: OutlinedButton(
          onPressed: () async {
            final selected = await showDatePicker(
              context: context,
              initialDate: _startDate ?? _renewalDate ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (selected != null && mounted) {
              setState(() => _startDate = subscriptionDateOnly(selected));
            }
          },
          child: const Text('选择'),
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('下次续费日期'),
        subtitle: Text(
          _renewalDate == null
              ? context.tr('尚未选择')
              : '${_renewalDate!.year}-${_renewalDate!.month.toString().padLeft(2, '0')}-${_renewalDate!.day.toString().padLeft(2, '0')}',
          translate: false,
        ),
        trailing: OutlinedButton(
          onPressed: () async {
            final selected = await showDatePicker(
              context: context,
              initialDate: _renewalDate ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (selected != null && mounted) {
              setState(() => _renewalDate = subscriptionDateOnly(selected));
            }
          },
          child: const Text('选择'),
        ),
      ),
      if (_startDate != null &&
          _renewalDate != null &&
          _renewalDate!.isBefore(_startDate!)) ...[
        Text(
          context.tr('下次续费日期不能早于首次订阅日期'),
          translate: false,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        const SizedBox(height: 12),
      ],
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _cycleCountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '每几个周期'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<SubscriptionCycleUnit>(
              initialValue: _cycleUnit,
              decoration: const InputDecoration(labelText: '周期单位'),
              items: const [
                DropdownMenuItem(
                  value: SubscriptionCycleUnit.day,
                  child: Text('天'),
                ),
                DropdownMenuItem(
                  value: SubscriptionCycleUnit.week,
                  child: Text('周'),
                ),
                DropdownMenuItem(
                  value: SubscriptionCycleUnit.month,
                  child: Text('月'),
                ),
                DropdownMenuItem(
                  value: SubscriptionCycleUnit.year,
                  child: Text('年'),
                ),
              ],
              onChanged: (value) => setState(() => _cycleUnit = value),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const Text('是否自动续费'),
      const SizedBox(height: 8),
      SegmentedButton<bool>(
        emptySelectionAllowed: true,
        segments: const [
          ButtonSegment(value: true, label: Text('是')),
          ButtonSegment(value: false, label: Text('否')),
        ],
        selected: _autoRenew == null ? const <bool>{} : <bool>{_autoRenew!},
        onSelectionChanged: (value) {
          if (value.isNotEmpty) setState(() => _autoRenew = value.single);
        },
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _reminderDaysController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: '提前提醒天数',
          helperText: '请输入 0 到 365。',
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _requiredChoicesComplete
            ? () => setState(_createFormController)
            : null,
        child: const Text('使用这些值继续填写'),
      ),
    ],
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
