import 'dart:async';

import '../../../app/app_state.dart';
import '../../../core/platform/share_intake_bridge.dart';
import '../../../core/share_intake/share_subscription_text_parser.dart';
import '../../../core/theme/cardock_tokens.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../../../shared/widgets/cardock_ui.dart';
import '../domain/subscription_record.dart';
import 'subscription_editor_page.dart';

enum ShareDraftPageResult { saved, canceled, cleared, expired }

class ShareSubscriptionDraftPage extends StatefulWidget {
  const ShareSubscriptionDraftPage({
    required this.appState,
    required this.payload,
    super.key,
  });

  final AppState appState;
  final ShareIntakePayload payload;

  @override
  State<ShareSubscriptionDraftPage> createState() =>
      _ShareSubscriptionDraftPageState();
}

class _ShareSubscriptionDraftPageState
    extends State<ShareSubscriptionDraftPage> {
  final _formKey = GlobalKey<FormState>();
  final _platformController = TextEditingController();
  final _planController = TextEditingController();
  final _amountController = TextEditingController();
  final _currencyController = TextEditingController();
  final _cycleCountController = TextEditingController();
  final _urlController = TextEditingController();

  late final ShareTextExtraction _extraction;
  Timer? _expiryTimer;
  String? _rawText;
  String? _rawSubject;
  String? _rawTitle;
  String? _selectedAccountId;
  SubscriptionCycleUnit? _cycleUnit;
  DateTime? _renewalDate;
  bool? _autoRenew;
  bool _working = false;
  bool _expired = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final payload = widget.payload;
    _rawText = payload.text;
    _rawSubject = payload.subject;
    _rawTitle = payload.title;
    _extraction = const ShareSubscriptionTextParser().parse(
      text: payload.text,
      subject: payload.subject,
      title: payload.title,
    );
    _applyUniqueCandidates();
    _selectedAccountId = _suggestUniqueAccount();
    _expiryTimer = Timer(payload.remainingLifetime, _expire);
  }

  void _applyUniqueCandidates() {
    if (_extraction.platforms.length == 1) {
      _platformController.text = _extraction.platforms.single;
    }
    if (_extraction.plans.length == 1) {
      _planController.text = _extraction.plans.single;
    }
    if (_extraction.amounts.length == 1) {
      final candidate = _extraction.amounts.single;
      _amountController.text = candidate.amount;
      if (candidate.currency != null) {
        _currencyController.text = candidate.currency!;
      }
    }
    if (_currencyController.text.isEmpty &&
        _extraction.currencies.length == 1) {
      _currencyController.text = _extraction.currencies.single;
    }
    if (_extraction.cycles.length == 1) {
      _selectCycle(_extraction.cycles.single, rebuild: false);
    }
    if (_extraction.renewalDates.length == 1) {
      _renewalDate = _extraction.renewalDates.single;
    }
    if (_extraction.autoRenewValues.length == 1) {
      _autoRenew = _extraction.autoRenewValues.single;
    }
    if (_extraction.urls.length == 1) {
      _urlController.text = _extraction.urls.single;
    }
  }

  String? _suggestUniqueAccount() {
    final platform = _platformController.text.trim().toLowerCase();
    final url = _urlController.text.trim();
    final host = Uri.tryParse(url)?.host.toLowerCase();
    final matches = widget.appState.accounts
        .where((account) {
          final platformMatches =
              platform.isNotEmpty &&
              account.platformName.trim().toLowerCase() == platform;
          final accountHost = Uri.tryParse(
            account.website ?? '',
          )?.host.toLowerCase();
          final hostMatches =
              host != null &&
              host.isNotEmpty &&
              accountHost != null &&
              accountHost == host;
          return platformMatches || hostMatches;
        })
        .toList(growable: false);
    return matches.length == 1 ? matches.single.id : null;
  }

  void _expire() {
    if (!mounted || _expired) return;
    _expired = true;
    _clearSensitiveControllers();
    Navigator.of(context).pop(ShareDraftPageResult.expired);
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _rawText = null;
    _rawSubject = null;
    _rawTitle = null;
    for (final controller in <TextEditingController>[
      _platformController,
      _planController,
      _amountController,
      _currencyController,
      _cycleCountController,
      _urlController,
    ]) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  void _clearSensitiveControllers() {
    _rawText = null;
    _rawSubject = null;
    _rawTitle = null;
    _platformController.clear();
    _planController.clear();
    _amountController.clear();
    _currencyController.clear();
    _cycleCountController.clear();
    _urlController.clear();
    _selectedAccountId = null;
    _cycleUnit = null;
    _renewalDate = null;
    _autoRenew = null;
  }

  void _close(ShareDraftPageResult result) {
    if (_working) return;
    _clearSensitiveControllers();
    Navigator.of(context).pop(result);
  }

  Future<void> _selectAccount() async {
    final selected = await showSubscriptionAccountPicker(
      context: context,
      accounts: widget.appState.accounts,
      selectedAccountId: _selectedAccountId,
      allowStandalone: false,
    );
    if (!mounted || selected == null) return;
    setState(() => _selectedAccountId = selected.accountId);
  }

  String _accountLabel() {
    final account = widget.appState.accounts
        .where((item) => item.id == _selectedAccountId)
        .firstOrNull;
    if (account == null) return context.tr('尚未选择已有账号');
    final detail = account.loginAccount ?? account.username;
    return <String?>[
      account.platformName,
      detail,
    ].whereType<String>().join(' · ');
  }

  void _selectCycle(
    ShareBillingCycleCandidate candidate, {
    bool rebuild = true,
  }) {
    void apply() {
      _cycleCountController.text = '${candidate.count}';
      _cycleUnit = switch (candidate.unit) {
        ShareCycleUnit.day => SubscriptionCycleUnit.day,
        ShareCycleUnit.month => SubscriptionCycleUnit.month,
        ShareCycleUnit.year => SubscriptionCycleUnit.year,
      };
    }

    if (rebuild) {
      setState(apply);
    } else {
      apply();
    }
  }

  Future<void> _pickRenewalDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _renewalDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) {
      setState(() => _renewalDate = subscriptionDateOnly(selected));
    }
  }

  Future<void> _save() async {
    if (_working || _expired || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final accountId = _selectedAccountId;
    if (accountId == null) {
      setState(() => _error = '请先选择当前保险库中的已有账号。');
      return;
    }
    final cycleCountText = _cycleCountController.text.trim();
    final cycleCount = cycleCountText.isEmpty
        ? null
        : int.tryParse(cycleCountText);
    if ((cycleCount == null) != (_cycleUnit == null) ||
        (cycleCount != null && (cycleCount < 1 || cycleCount > 120))) {
      setState(() => _error = '计费周期数量和单位必须同时填写，数量为 1 到 120。');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
      _rawText = null;
      _rawSubject = null;
      _rawTitle = null;
    });
    final saved = await widget.appState.saveSharedTextPendingSubscriptionDraft(
      accountId: accountId,
      planName: _optional(_planController.text),
      amount: _optional(_amountController.text),
      currency: _optional(_currencyController.text)?.toUpperCase(),
      billingCycleCount: cycleCount,
      billingCycleUnit: _cycleUnit,
      nextRenewalDate: _renewalDate,
      autoRenew: _autoRenew,
    );
    if (!mounted) return;
    if (saved) {
      _clearSensitiveControllers();
      Navigator.of(context).pop(ShareDraftPageResult.saved);
    } else {
      setState(() {
        _working = false;
        _error = widget.appState.errorMessage ?? '待完善订阅草稿未能保存。';
      });
    }
  }

  String? _optional(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return PopScope(
      canPop: !_working,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _clearSensitiveControllers();
      },
      child: Scaffold(
        key: const ValueKey<String>('share-subscription-draft-page'),
        appBar: AppBar(
          title: const Text('从分享内容整理订阅'),
          leading: IconButton(
            key: const ValueKey<String>('share-draft-cancel'),
            tooltip: context.tr('取消并清除'),
            onPressed: _working
                ? null
                : () => _close(ShareDraftPageResult.canceled),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              CardockSurfaceCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CardockSemanticIcon(
                      icon: Icons.phone_android_rounded,
                      color: palette.fieldSubscription,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '只在本机内存中解析，不上传、不联网打开网址。只有点按保存后，所选结构化字段才会进入当前解锁保险库的待完善草稿。',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildOriginalCard(),
              const SizedBox(height: 16),
              Text('候选字段', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _candidateNotice(),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('share-platform-field'),
                controller: _platformController,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: '平台或服务名（仅用于核对）',
                  helperText: '不会新建或修改账号；保存时以你选择的已有账号为准。',
                ),
              ),
              _stringCandidateChips(
                values: _extraction.platforms,
                onSelected: (value) => setState(() {
                  _platformController.text = value;
                  _selectedAccountId = _suggestUniqueAccount();
                }),
              ),
              TextFormField(
                key: const ValueKey<String>('share-plan-field'),
                controller: _planController,
                maxLength: 200,
                decoration: const InputDecoration(labelText: '套餐名称（可留空）'),
              ),
              _stringCandidateChips(
                values: _extraction.plans,
                onSelected: (value) =>
                    setState(() => _planController.text = value),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      key: const ValueKey<String>('share-amount-field'),
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: '金额（可留空）'),
                      validator: (value) {
                        final normalized = value?.trim() ?? '';
                        if (normalized.isEmpty) return null;
                        return RegExp(
                              r'^(?:0|[1-9]\d{0,11})(?:\.\d{1,4})?$',
                            ).hasMatch(normalized)
                            ? null
                            : context.tr('金额格式无效');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      key: const ValueKey<String>('share-currency-field'),
                      controller: _currencyController,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 3,
                      decoration: const InputDecoration(labelText: '币种'),
                      validator: (value) {
                        final normalized = value?.trim() ?? '';
                        if (normalized.isEmpty) return null;
                        return RegExp(r'^[A-Za-z]{3}$').hasMatch(normalized)
                            ? null
                            : context.tr('币种必须为 3 位字母代码');
                      },
                    ),
                  ),
                ],
              ),
              _amountCandidateChips(),
              _stringCandidateChips(
                values: _extraction.currencies,
                onSelected: (value) =>
                    setState(() => _currencyController.text = value),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey<String>('share-cycle-count-field'),
                      controller: _cycleCountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '计费周期数量'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<SubscriptionCycleUnit>(
                      key: ValueKey<String>(
                        'share-cycle-unit-field-${_cycleUnit?.name ?? 'none'}',
                      ),
                      initialValue: _cycleUnit,
                      decoration: const InputDecoration(labelText: '计费周期单位'),
                      items: [
                        for (final unit in SubscriptionCycleUnit.values)
                          DropdownMenuItem<SubscriptionCycleUnit>(
                            value: unit,
                            child: Text(_cycleUnitLabel(unit)),
                          ),
                      ],
                      onChanged: (value) => setState(() => _cycleUnit = value),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('清空计费周期'),
                    onPressed: () => setState(() {
                      _cycleCountController.clear();
                      _cycleUnit = null;
                    }),
                    icon: const Icon(Icons.clear_rounded),
                  ),
                ],
              ),
              _cycleCandidateChips(),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('下次续费日期（可留空）'),
                subtitle: Text(
                  _renewalDate == null
                      ? context.tr('尚未选择')
                      : _formatDate(_renewalDate!),
                  translate: false,
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: context.tr('清空日期'),
                      onPressed: () => setState(() => _renewalDate = null),
                      icon: const Icon(Icons.clear_rounded),
                    ),
                    IconButton(
                      tooltip: context.tr('选择日期'),
                      onPressed: _pickRenewalDate,
                      icon: const Icon(Icons.calendar_month_outlined),
                    ),
                  ],
                ),
              ),
              _dateCandidateChips(),
              const SizedBox(height: 8),
              Text('自动续费（可留空）', style: Theme.of(context).textTheme.bodyLarge),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('留空'),
                    selected: _autoRenew == null,
                    onSelected: (_) => setState(() => _autoRenew = null),
                  ),
                  ChoiceChip(
                    label: const Text('是'),
                    selected: _autoRenew == true,
                    onSelected: (_) => setState(() => _autoRenew = true),
                  ),
                  ChoiceChip(
                    label: const Text('否'),
                    selected: _autoRenew == false,
                    onSelected: (_) => setState(() => _autoRenew = false),
                  ),
                ],
              ),
              if (_extraction.autoRenewValues.length > 1)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('检测到互相冲突的自动续费候选，请明确选择或留空。'),
                ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey<String>('share-url-field'),
                controller: _urlController,
                maxLength: 2048,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '网页地址（仅用于核对）',
                  helperText: '只接受 http(s)；Cardock 不会打开、抓取或保存为新账号网址。',
                ),
                validator: (value) {
                  final normalized = value?.trim() ?? '';
                  if (normalized.isEmpty) return null;
                  final uri = Uri.tryParse(normalized);
                  return uri != null &&
                          (uri.scheme == 'http' || uri.scheme == 'https') &&
                          uri.host.isNotEmpty &&
                          uri.userInfo.isEmpty
                      ? null
                      : context.tr('只接受有效的 http(s) 网页地址');
                },
              ),
              _stringCandidateChips(
                values: _extraction.urls,
                onSelected: (value) => setState(() {
                  _urlController.text = value;
                  _selectedAccountId = _suggestUniqueAccount();
                }),
              ),
              const SizedBox(height: 18),
              Semantics(
                button: true,
                label: context.tr('关联当前保险库中的已有账号'),
                value: _accountLabel(),
                child: InkWell(
                  key: const ValueKey<String>('share-account-field'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: widget.appState.accounts.isEmpty
                      ? null
                      : _selectAccount,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '关联已有账号（保存草稿必选）',
                      helperText: '草稿只写入这个账号所在的当前真实库或诱饵库，不会跨库。',
                      suffixIcon: Icon(Icons.arrow_drop_down_rounded),
                    ),
                    isEmpty: false,
                    child: Text(_accountLabel(), translate: false),
                  ),
                ),
              ),
              if (widget.appState.accounts.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('当前保险库没有已有账号；本次只能取消或清除，不会自动创建账号。'),
                ),
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Text(
                  context.tr(error),
                  translate: false,
                  key: const ValueKey<String>('share-draft-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              TextButton.icon(
                key: const ValueKey<String>('share-draft-clear'),
                onPressed: _working
                    ? null
                    : () => _close(ShareDraftPageResult.cleared),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('清除本次内容'),
              ),
              const Spacer(),
              FilledButton.icon(
                key: const ValueKey<String>('share-draft-save'),
                onPressed: _working || widget.appState.accounts.isEmpty
                    ? null
                    : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_working ? '正在保存…' : '保存待完善草稿'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOriginalCard() => Card(
    child: ExpansionTile(
      key: const ValueKey<String>('share-original-expansion'),
      leading: const Icon(Icons.subject_rounded),
      title: const Text('原始分享内容'),
      subtitle: const Text('默认收起；离开、锁定、过期或保存后清除'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        if (_rawTitle case final title?)
          _OriginalLine(label: '标题', value: title),
        if (_rawSubject case final subject?)
          _OriginalLine(label: '主题', value: subject),
        if (_rawText case final text?) _OriginalLine(label: '正文', value: text),
      ],
    ),
  );

  Widget _candidateNotice() {
    final ambiguous = <Object>[
      _extraction.platforms,
      _extraction.plans,
      _extraction.amounts,
      _extraction.currencies,
      _extraction.cycles,
      _extraction.renewalDates,
      _extraction.autoRenewValues,
      _extraction.urls,
    ].whereType<List<Object>>().any((values) => values.length > 1);
    return Text(
      ambiguous
          ? '检测到多个候选的字段没有自动选定；请点选、手工编辑、清空或保持留空。'
          : '候选只作为本机建议；你可以编辑、清空或保持留空。',
    );
  }

  Widget _stringCandidateChips({
    required List<String> values,
    required ValueChanged<String> onSelected,
  }) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final value in values)
            ActionChip(
              label: Text(value, translate: false),
              onPressed: () => onSelected(value),
            ),
        ],
      ),
    );
  }

  Widget _amountCandidateChips() {
    if (_extraction.amounts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final candidate in _extraction.amounts)
          ActionChip(
            label: Text(candidate.label, translate: false),
            onPressed: () => setState(() {
              _amountController.text = candidate.amount;
              if (candidate.currency != null) {
                _currencyController.text = candidate.currency!;
              }
            }),
          ),
      ],
    );
  }

  Widget _cycleCandidateChips() {
    if (_extraction.cycles.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final candidate in _extraction.cycles)
          ActionChip(
            label: Text(
              '${candidate.count} ${context.tr(switch (candidate.unit) {
                ShareCycleUnit.day => '天',
                ShareCycleUnit.month => '个月',
                ShareCycleUnit.year => '年',
              })}',
              translate: false,
            ),
            onPressed: () => _selectCycle(candidate),
          ),
      ],
    );
  }

  Widget _dateCandidateChips() {
    if (_extraction.renewalDates.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final date in _extraction.renewalDates)
          ActionChip(
            label: Text(_formatDate(date), translate: false),
            onPressed: () => setState(() => _renewalDate = date),
          ),
      ],
    );
  }

  String _cycleUnitLabel(SubscriptionCycleUnit unit) => switch (unit) {
    SubscriptionCycleUnit.day => context.tr('天'),
    SubscriptionCycleUnit.week => context.tr('周'),
    SubscriptionCycleUnit.month => context.tr('月'),
    SubscriptionCycleUnit.year => context.tr('年'),
  };

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class _OriginalLine extends StatelessWidget {
  const _OriginalLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 48, child: Text(label)),
        Expanded(child: Text(value, translate: false)),
      ],
    ),
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
