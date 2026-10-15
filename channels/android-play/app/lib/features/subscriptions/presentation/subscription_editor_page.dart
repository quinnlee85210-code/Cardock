import 'subscription_price_review.dart';
import 'dart:convert';

import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../../../l10n/translations_records.dart';

import '../../../core/theme/cardock_tokens.dart';
import '../../../shared/widgets/cardock_ui.dart';
import '../../accounts/domain/account_record.dart';
import '../domain/subscription_record.dart';
import 'subscription_form_fields.dart';

class SubscriptionEditorPage extends StatefulWidget {
  const SubscriptionEditorPage({
    required this.accounts,
    this.paymentMethods = const [],
    this.existing,
    this.initialDraft,
    this.onDraftChanged,
    this.initialAccountId,
    this.defaultCurrency = 'CNY',
    this.defaultReminderDays = 7,
    super.key,
  });

  final List<AccountRecord> accounts;
  final List<PaymentMethodRecord> paymentMethods;
  final SubscriptionRecord? existing;
  final Map<String, Object?>? initialDraft;
  final ValueChanged<Map<String, Object?>>? onDraftChanged;
  final String? initialAccountId;
  final String defaultCurrency;
  final int defaultReminderDays;

  @override
  State<SubscriptionEditorPage> createState() => _SubscriptionEditorPageState();
}

class _SubscriptionEditorPageState extends State<SubscriptionEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final SubscriptionFormController _subscriptionController;
  late String? _accountId;
  String? _localError;
  bool _draftReady = false;
  String? _lastDraft;

  void _publishDraft() {
    if (!_draftReady) return;
    final fields = <String, Object?>{
      'accountId': _accountId,
      'subscription': _subscriptionController.exportEditorFields(),
    };
    final encoded = jsonEncode(fields);
    if (encoded == _lastDraft) return;
    _lastDraft = encoded;
    widget.onDraftChanged?.call(fields);
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _publishDraft();
  }

  @override
  void initState() {
    super.initState();
    _subscriptionController = SubscriptionFormController(
      initial: widget.existing?.details,
      availablePaymentMethods: widget.paymentMethods,
      defaultCurrency: widget.defaultCurrency,
      defaultReminderDays: widget.defaultReminderDays,
    );
    final requestedAccountId = widget.existing == null
        ? widget.initialAccountId
        : widget.existing!.accountId;
    _accountId =
        requestedAccountId != null &&
            widget.accounts.any((account) => account.id == requestedAccountId)
        ? requestedAccountId
        : null;
    if (widget.existing == null) {
      _subscriptionController.setExpenseCategoryIfEmpty(
        widget.accounts
            .where((account) => account.id == _accountId)
            .firstOrNull
            ?.category,
      );
    }
    final draft = widget.initialDraft;
    if (draft != null) {
      final accountId = draft['accountId'];
      _accountId =
          accountId is String && widget.accounts.any((a) => a.id == accountId)
          ? accountId
          : null;
      if (draft['subscription'] case final Map<String, Object?> fields) {
        _subscriptionController.restoreEditorFields(fields);
      }
    }
    _draftReady = true;
    for (final controller in _subscriptionController.textControllers) {
      controller.addListener(_publishDraft);
    }
    _subscriptionController.onDraftChanged = _publishDraft;
  }

  @override
  void dispose() {
    _draftReady = false;
    _lastDraft = null;
    _subscriptionController.onDraftChanged = null;
    for (final controller in _subscriptionController.textControllers) {
      controller.removeListener(_publishDraft);
    }
    _subscriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _localError = null);
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    try {
      final details = await reviewSubscriptionPriceChange(
        context,
        widget.existing,
        _subscriptionController.toDraft(),
      );
      if (!mounted || details == null) return;
      Navigator.of(
        context,
      ).pop(SubscriptionDraft(accountId: _accountId, details: details));
    } on ArgumentError catch (error) {
      setState(() => _localError = error.message?.toString());
    } on FormatException {
      setState(() => _localError = '请检查日期格式和新增字段。');
    }
  }

  Future<void> _selectAccount() async {
    final selected = await showSubscriptionAccountPicker(
      context: context,
      accounts: widget.accounts,
      selectedAccountId: _accountId,
    );
    if (!mounted || selected == null) return;
    setState(() {
      _accountId = selected.accountId;
      if (widget.existing == null) {
        _subscriptionController.setExpenseCategoryIfEmpty(
          widget.accounts
              .where((account) => account.id == _accountId)
              .firstOrNull
              ?.category,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final palette = context.cardockTheme.palette;

    return Scaffold(
      appBar: AppBar(title: Text(editing ? '编辑订阅' : '新增订阅')),
      body: Form(
        key: _formKey,
        child: ListView(
          key: const ValueKey<String>('subscription-editor-page'),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            CardockSurfaceCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CardockSemanticIcon(
                    icon: Icons.lock_outline_rounded,
                    color: palette.fieldSubscription,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '订阅会加密保存在本机；可以独立记录，也可以选择关联账号。这里只记录信息，不会执行付款或取消。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              button: true,
              label: context.tr('关联账号（可选）'),
              value: _selectedAccountLabel(context),
              child: InkWell(
                key: const ValueKey<String>('subscription-account-field'),
                borderRadius: BorderRadius.circular(12),
                onTap: _selectAccount,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: context.tr('关联账号（可选）'),
                    helperText: context.tr('不关联账号时，将保存为独立订阅。'),
                    suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
                  ),
                  isEmpty: false,
                  child: Text(
                    _selectedAccountLabel(context),
                    translate: false,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SubscriptionFormFields(
              controller: _subscriptionController,
              keyPrefix: 'subscription',
            ),
            if (_localError != null) ...[
              const SizedBox(height: 12),
              Text(
                _localError!,
                key: const ValueKey<String>('subscription-editor-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: FilledButton.icon(
          key: const ValueKey<String>('save-subscription-button'),
          onPressed: _submit,
          icon: const Icon(Icons.save_outlined),
          label: Text(editing ? '保存修改' : '加密保存订阅'),
        ),
      ),
    );
  }

  String _selectedAccountLabel(BuildContext context) {
    final selected = widget.accounts
        .where((account) => account.id == _accountId)
        .firstOrNull;
    if (selected == null) {
      return context.tr('不关联账号 · 独立订阅');
    }
    return _accountLabel(context, selected);
  }
}

final class SubscriptionAccountPickerResult {
  const SubscriptionAccountPickerResult(this.accountId);

  final String? accountId;
}

Future<SubscriptionAccountPickerResult?> showSubscriptionAccountPicker({
  required BuildContext context,
  required List<AccountRecord> accounts,
  required String? selectedAccountId,
  bool allowStandalone = true,
}) async {
  final selection = await showModalBottomSheet<_SubscriptionAccountSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _SubscriptionAccountPickerSheet(
      accounts: accounts,
      selectedAccountId: selectedAccountId,
      allowStandalone: allowStandalone,
    ),
  );
  return selection == null
      ? null
      : SubscriptionAccountPickerResult(selection.accountId);
}

String _accountLabel(BuildContext context, AccountRecord account) {
  final detail = account.loginAccount ?? account.username;
  return '${account.platformName} · ${detail ?? context.tr('未填写')}';
}

final class _SubscriptionAccountSelection {
  const _SubscriptionAccountSelection(this.accountId);

  final String? accountId;
}

final class _SubscriptionAccountCategoryGroup {
  const _SubscriptionAccountCategoryGroup({
    required this.key,
    required this.label,
    required this.accounts,
    required this.isBuiltIn,
  });

  final String key;
  final String? label;
  final List<AccountRecord> accounts;
  final bool isBuiltIn;
}

List<_SubscriptionAccountCategoryGroup> _groupAccountsForSubscriptionPicker(
  Iterable<AccountRecord> accounts,
) {
  const unclassifiedKey = 'unclassified';
  final grouped = <String, List<AccountRecord>>{};
  final representativeLabels = <String, String>{};

  for (final account in accounts) {
    final category = account.category?.trim();
    final key = category == null || category.isEmpty
        ? unclassifiedKey
        : 'category:${category.toLowerCase()}';
    (grouped[key] ??= <AccountRecord>[]).add(account);
    if (key != unclassifiedKey) {
      representativeLabels.putIfAbsent(key, () => category!);
    }
  }

  final result = <_SubscriptionAccountCategoryGroup>[];
  final consumed = <String>{};
  for (final category in accountCategories) {
    final key = 'category:${category.toLowerCase()}';
    final categoryAccounts = grouped[key];
    if (categoryAccounts == null) continue;
    consumed.add(key);
    result.add(
      _SubscriptionAccountCategoryGroup(
        key: key,
        label: category,
        accounts: List<AccountRecord>.unmodifiable(categoryAccounts),
        isBuiltIn: true,
      ),
    );
  }
  for (final entry in grouped.entries) {
    if (entry.key == unclassifiedKey || consumed.contains(entry.key)) continue;
    result.add(
      _SubscriptionAccountCategoryGroup(
        key: entry.key,
        label: representativeLabels[entry.key]!,
        accounts: List<AccountRecord>.unmodifiable(entry.value),
        isBuiltIn: false,
      ),
    );
  }
  final unclassified = grouped[unclassifiedKey];
  if (unclassified != null) {
    result.add(
      _SubscriptionAccountCategoryGroup(
        key: unclassifiedKey,
        label: null,
        accounts: List<AccountRecord>.unmodifiable(unclassified),
        isBuiltIn: false,
      ),
    );
  }
  return List<_SubscriptionAccountCategoryGroup>.unmodifiable(result);
}

class _SubscriptionAccountPickerSheet extends StatefulWidget {
  const _SubscriptionAccountPickerSheet({
    required this.accounts,
    required this.selectedAccountId,
    required this.allowStandalone,
  });

  final List<AccountRecord> accounts;
  final String? selectedAccountId;
  final bool allowStandalone;

  @override
  State<_SubscriptionAccountPickerSheet> createState() =>
      _SubscriptionAccountPickerSheetState();
}

class _SubscriptionAccountPickerSheetState
    extends State<_SubscriptionAccountPickerSheet> {
  _SubscriptionAccountCategoryGroup? _selectedCategory;

  late final List<_SubscriptionAccountCategoryGroup> _categories =
      _groupAccountsForSubscriptionPicker(widget.accounts);

  @override
  Widget build(BuildContext context) {
    final selectedCategory = _selectedCategory;
    return FractionallySizedBox(
      key: const ValueKey<String>('subscription-account-picker-sheet'),
      heightFactor: 0.9,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              children: [
                if (selectedCategory != null)
                  BackButton(
                    key: const ValueKey<String>(
                      'subscription-account-category-back',
                    ),
                    onPressed: () => setState(() => _selectedCategory = null),
                  )
                else
                  const SizedBox(width: 48, height: 48),
                Expanded(
                  child: Text(
                    selectedCategory == null
                        ? context.tr('关联账号（可选）')
                        : _categoryLabel(context, selectedCategory),
                    translate: false,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>(
                    'subscription-account-picker-close',
                  ),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: selectedCategory == null
                ? _buildCategoryList(context)
                : _buildAccountList(context, selectedCategory),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryList(BuildContext context) {
    return ListView(
      key: const ValueKey<String>('subscription-account-category-list'),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      children: [
        if (widget.allowStandalone) ...[
          ListTile(
            key: const ValueKey<String>('subscription-account-standalone'),
            minTileHeight: 56,
            leading: const Icon(Icons.link_off_rounded),
            title: const Text('不关联账号 · 独立订阅', overflow: TextOverflow.ellipsis),
            trailing: widget.selectedAccountId == null
                ? const Icon(Icons.check_rounded)
                : null,
            onTap: () => Navigator.of(
              context,
            ).pop(const _SubscriptionAccountSelection(null)),
          ),
          if (_categories.isNotEmpty) const Divider(),
        ],
        for (final category in _categories)
          ListTile(
            key: ValueKey<String>(
              'subscription-account-category-${category.key}',
            ),
            minTileHeight: 56,
            leading: Icon(
              category.label == null
                  ? Icons.folder_off_outlined
                  : Icons.folder_outlined,
            ),
            title: Text(
              _categoryLabel(context, category),
              translate: false,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${category.accounts.length}', translate: false),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            onTap: () => setState(() => _selectedCategory = category),
          ),
        if (_categories.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Text('暂无账号记录', textAlign: TextAlign.center),
          ),
      ],
    );
  }

  Widget _buildAccountList(
    BuildContext context,
    _SubscriptionAccountCategoryGroup category,
  ) {
    return ListView.builder(
      key: const ValueKey<String>('subscription-account-list'),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      itemCount: category.accounts.length,
      itemBuilder: (context, index) {
        final account = category.accounts[index];
        final detail = account.loginAccount ?? account.username;
        return ListTile(
          key: ValueKey<String>('subscription-account-option-${account.id}'),
          minTileHeight: 56,
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(
            account.platformName,
            translate: false,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            detail ?? context.tr('未填写'),
            translate: false,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: widget.selectedAccountId == account.id
              ? const Icon(Icons.check_rounded)
              : null,
          onTap: () => Navigator.of(
            context,
          ).pop(_SubscriptionAccountSelection(account.id)),
        );
      },
    );
  }

  String _categoryLabel(
    BuildContext context,
    _SubscriptionAccountCategoryGroup category,
  ) {
    final label = category.label;
    if (label == null) return context.tr('未分类');
    if (category.isBuiltIn) {
      return localizedAccountCategory(context.l10n.language, label);
    }
    if (label == context.tr('未分类')) return '“$label”';
    return label;
  }
}
