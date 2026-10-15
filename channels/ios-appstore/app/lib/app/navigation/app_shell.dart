import 'vault_navigation.dart';
import '../../features/accounts/domain/account_analysis.dart';
import '../../features/accounts/presentation/password_health_center_page.dart';
import '../../features/accounts/presentation/binding_center_page.dart';
import '../../features/accounts/presentation/account_duplicate_dialog.dart';
import '../../features/subscriptions/presentation/subscription_management_panel.dart';
import '../../features/subscriptions/presentation/subscription_insights_page.dart';
import '../../features/subscriptions/domain/subscription_insights.dart';
import 'dart:async';

import '../../l10n/context_l10n.dart';
import '../../l10n/localized_material.dart';
import '../../l10n/translations_records.dart';

import '../../core/entitlements/entitlement_guard.dart';
import '../../features/accounts/domain/account_record.dart';
import '../../core/preferences/record_sort_mode.dart';
import '../../core/temporary_web/temporary_web_controller.dart';
import '../../core/theme/cardock_tokens.dart';
import '../../features/accounts/presentation/account_details_page.dart';
import '../../features/accounts/presentation/account_editor_page.dart';
import '../../features/accounts/presentation/accounts_page.dart';
import '../../features/accounts/presentation/password_review_center_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/product/presentation/full_version_upsell_sheet.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/settings/presentation/trash_page.dart';
import '../../features/subscriptions/domain/subscription_list_preset.dart';
import '../../features/subscriptions/domain/subscription_record.dart';
import '../../features/subscriptions/presentation/subscription_details_page.dart';
import '../../features/subscriptions/presentation/subscription_finance_page.dart';
import '../../features/subscriptions/presentation/subscription_editor_page.dart';
import '../../features/subscriptions/presentation/subscriptions_page.dart';
import '../../shared/widgets/cardock_ui.dart';
import '../app_state.dart';
import 'app_destination.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.appState,
    required this.onManualLock,
    this.temporaryWebController,
    super.key,
  });

  final AppState appState;
  final VoidCallback onManualLock;
  final TemporaryWebSessionController? temporaryWebController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  VaultNavigation? _navigation;
  bool _navigationInitialized = false;
  int _healthOpenSignal = 0;
  bool _editorOpen = false;

  Future<T?> _pushEditor<T>({
    required String kind,
    String? existingId,
    required Widget Function(ValueChanged<Map<String, Object?>> onChanged)
    build,
  }) async {
    _editorOpen = true;
    final writer = widget.appState.editorDraftWriter();
    try {
      final result = await Navigator.of(context).push<T>(
        MaterialPageRoute<T>(
          builder: (_) => build((fields) {
            unawaited(
              writer({
                'kind': kind,
                'existingId': existingId,
                'fields': fields,
              }),
            );
          }),
        ),
      );
      // A lock also pops the route. Its session-bound writer rejects this
      // clear, preserving the encrypted form for the next authenticated unlock.
      if (result == null && mounted && widget.appState.isUnlocked) {
        await writer(null);
      }
      return result;
    } finally {
      _editorOpen = false;
    }
  }

  Future<void> _restoreEditor() async {
    if (!widget.appState.hasFullVaultAccess) return;
    final draft = await widget.appState.readEditorDraft();
    if (!mounted ||
        _editorOpen ||
        !widget.appState.isUnlocked ||
        draft == null) {
      return;
    }
    final fields = Map<String, Object?>.from(draft['fields'] as Map);
    final existingId = draft['existingId'];
    if (draft['kind'] == 'account') {
      _selectDestination(AppDestination.accounts.index);
      if (existingId == null) {
        await _openAddAccount(initialDraft: fields);
      } else {
        final account = widget.appState.accounts
            .where((a) => a.id == existingId)
            .firstOrNull;
        if (account != null) {
          await _openEditAccount(account, initialDraft: fields);
        }
      }
    } else if (draft['kind'] == 'subscription') {
      _selectDestination(AppDestination.subscriptions.index);
      if (existingId == null) {
        await _openAddSubscription(initialDraft: fields);
      } else {
        final subscription = widget.appState.subscriptions
            .where((s) => s.id == existingId)
            .firstOrNull;
        if (subscription != null) {
          await _openEditSubscription(subscription, initialDraft: fields);
        }
      }
    }
  }

  Set<AccountFilter> _stage3Filters = const {};
  int _stage3FilterToken = 0;
  int _accountFilterResetToken = 0;
  int _accountSearchFocusToken = 0;
  SubscriptionListPreset? _subscriptionFilterPreset;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_handleReminderOpen);
    if (widget.appState.hasSubscriptionOnlyAccess) {
      _selectedIndex = AppDestination.subscriptions.index;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_handleReminderOpen()) {
        unawaited(() async {
          await _navigation?.restore(widget.appState.navigationVaultScope);
          if (mounted && widget.appState.isUnlocked) await _restoreEditor();
        }());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navigation = VaultNavigationScope.maybeOf(context);
    if (!_navigationInitialized) {
      _navigationInitialized = true;
      _selectedIndex =
          _navigation?.beginSession(
            widget.appState.navigationVaultScope,
            _selectedIndex,
          ) ??
          _selectedIndex;
    }
    _navigation?.handlers.addAll({
      'account': (location) {
        final id = (location as VaultPageLocation).recordId;
        final record = widget.appState.accounts
            .where((a) => a.id == id)
            .firstOrNull;
        if (record != null && widget.appState.hasFullVaultAccess) {
          unawaited(_openAccountDetails(record));
        }
      },
      'subscription': (location) {
        final id = (location as VaultPageLocation).recordId;
        final record = widget.appState.subscriptions
            .where((s) => s.id == id)
            .firstOrNull;
        if (record != null) unawaited(_openSubscriptionDetails(record));
      },
      'passwordHealth': (_) {
        unawaited(_openPasswordHealth());
      },
      'bindings': (_) {
        unawaited(_openBindings());
      },
      'passwordHistory': (_) {
        unawaited(_openPasswordReviewCenter());
      },
      'subscriptionAttention': (_) {
        unawaited(_openSubscriptionAttention());
      },
      'subscriptionFinance': (location) {
        unawaited(
          _openSubscriptionCostStats(
            initialTab: (location as VaultPageLocation).tab,
            currentMonth: location.recordId == 'currentMonth',
          ),
        );
      },
    });
  }

  bool _handleReminderOpen() {
    if (!mounted || !widget.appState.consumeReminderOpenRequest()) return false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.appState.isUnlocked) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      _openAllSubscriptions();
      unawaited(_openSubscriptionAttention());
    });
    return true;
  }

  @override
  void dispose() {
    widget.appState.removeListener(_handleReminderOpen);
    super.dispose();
  }

  AppDestination get _selectedDestination =>
      AppDestination.values[_selectedIndex];

  void _selectDestination(int index) {
    final clearingSubscriptionFilter =
        index == AppDestination.subscriptions.index &&
        _subscriptionFilterPreset != null;
    if (index == _selectedIndex && !clearingSubscriptionFilter) {
      return;
    }
    setState(() {
      _selectedIndex = index;
      if (index == AppDestination.subscriptions.index) {
        _subscriptionFilterPreset = null;
      }
    });
  }

  void _openAllAccounts() {
    setState(() {
      _stage3Filters = const {};
      _stage3FilterToken++;
      _accountFilterResetToken += 1;
      _selectedIndex = AppDestination.accounts.index;
    });
  }

  void _openAllSubscriptions() {
    _selectDestination(AppDestination.subscriptions.index);
  }

  void _openAccountSearch() {
    setState(() {
      _accountSearchFocusToken += 1;
      _selectedIndex = AppDestination.accounts.index;
    });
  }

  void _openSubscriptionFilter(SubscriptionListPreset preset) {
    setState(() {
      _subscriptionFilterPreset = preset;
      _selectedIndex = AppDestination.subscriptions.index;
    });
  }

  void _clearSubscriptionFilter() {
    if (_subscriptionFilterPreset == null) return;
    setState(() => _subscriptionFilterPreset = null);
  }

  Future<void> _changeAccountSortMode(RecordSortMode mode) async {
    final saved = await widget.appState.updatePreferences(
      widget.appState.preferences.copyWith(accountSortMode: mode),
    );
    if (!mounted || saved) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('账号排序偏好未能保存，请稍后重试。')));
  }

  Future<void> _changeSubscriptionSortMode(RecordSortMode mode) async {
    final saved = await widget.appState.updatePreferences(
      widget.appState.preferences.copyWith(subscriptionSortMode: mode),
    );
    if (!mounted || saved) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('订阅排序偏好未能保存，请稍后重试。')));
  }

  int get _navigationBarIndex => switch (_selectedDestination) {
    AppDestination.home => 0,
    AppDestination.accounts => 1,
    AppDestination.subscriptions => 3,
    AppDestination.settings => 4,
  };

  String _destinationSubtitle(BuildContext context) =>
      switch (_selectedDestination) {
        AppDestination.home => '',
        AppDestination.accounts =>
          context.tr('{countLabel} · 本地加密档案', <String, Object?>{
            'countLabel': localizedAccountCount(
              context.l10n.language,
              widget.appState.accounts.length,
            ),
          }),
        AppDestination.subscriptions =>
          context.tr('{countLabel} · 按具体续费日期排列', <String, Object?>{
            'countLabel': localizedSubscriptionCount(
              context.l10n.language,
              widget.appState.subscriptions.length,
            ),
          }),
        AppDestination.settings => context.tr('安全、隐私与本地保险库'),
      };

  Future<void> _selectNavigationItem(int index) async {
    if (index == 2) {
      await _openQuickAddMenu();
      return;
    }
    final destinationIndex = index < 2 ? index : index - 1;
    _selectDestination(destinationIndex);
  }

  Future<void> _openQuickAddMenu() async {
    if (widget.appState.hasSubscriptionOnlyAccess) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('订阅只读视图不能新增记录，请改用真实主密码解锁。')),
        );
      return;
    }
    if (widget.appState.isBusy) return;
    final action = await showModalBottomSheet<_QuickAddAction>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => const _QuickAddSheet(),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _QuickAddAction.account:
        await _openAddAccount();
      case _QuickAddAction.subscription:
        await _openAddSubscription();
    }
  }

  Future<bool> _reviewTrashSimilarity(bool similar) async {
    if (!similar) return true;
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('回收站中有相似记录'),
        content: const Text('可以先到回收站恢复原记录，也可以继续新增。回收站记录不会阻止本次保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('查看回收站'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续新增'),
          ),
        ],
      ),
    );
    if (choice == false && mounted) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => TrashPage(appState: widget.appState)),
      );
    }
    return choice == true;
  }

  Future<void> _openAddAccount({Map<String, Object?>? initialDraft}) async {
    final openingDecision = widget.appState.accountCreationDecision;
    if (!openingDecision.allowed) {
      await _showLimitUpsell(openingDecision);
      return;
    }
    final result = await _pushEditor<AccountEditorResult>(
      kind: 'account',
      build: (onChanged) => AccountEditorPage(
        initialDraft: initialDraft,
        onDraftChanged: onChanged,
        onBeforeSubmit: _saveNewAccountFromEditor,
        categoryOptions: accountCategoryOptions(widget.appState.accounts),
        defaultCurrency: widget.appState.preferences.defaultCurrency,
        defaultReminderDays:
            widget.appState.preferences.defaultReminderDaysBefore,
        canAddInitialSubscription:
            widget.appState.subscriptionCreationDecision.allowed,
        onInitialSubscriptionLimitReached: () {
          unawaited(
            _showLimitUpsell(widget.appState.subscriptionCreationDecision),
          );
        },
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() => _selectedIndex = AppDestination.accounts.index);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已加密保存到本机。')));
  }

  Future<AccountRecord?> _openEditAccount(
    AccountRecord account, {
    Map<String, Object?>? initialDraft,
  }) async {
    final result = await _pushEditor<AccountEditorResult>(
      kind: 'account',
      existingId: account.id,
      build: (onChanged) => AccountEditorPage(
        initialDraft: initialDraft,
        onDraftChanged: onChanged,
        onBeforeSubmit: (result) =>
            _saveEditedAccountFromEditor(account.id, result),
        existing: account,
        categoryOptions: accountCategoryOptions(widget.appState.accounts),
        defaultCurrency: widget.appState.preferences.defaultCurrency,
        defaultReminderDays:
            widget.appState.preferences.defaultReminderDaysBefore,
      ),
    );
    if (!mounted || result == null) {
      return null;
    }
    return widget.appState.accounts
        .where((candidate) => candidate.id == account.id)
        .firstOrNull;
  }

  Future<void> _openAccountDetails(AccountRecord account) async {
    final current = widget.appState.accounts
        .where((candidate) => candidate.id == account.id)
        .firstOrNull;
    if (current == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        settings: VaultPageLocation('account', recordId: current.id),
        builder: (context) => AccountDetailsPage(
          account: current,
          subscriptions: widget.appState.subscriptions
              .where((subscription) => subscription.accountId == current.id)
              .toList(growable: false),
          subscriptionsProvider: (record) => widget.appState.subscriptions
              .where((subscription) => subscription.accountId == record.id)
              .toList(growable: false),
          accountProvider: (id) => widget.appState.accounts
              .where((candidate) => candidate.id == id)
              .firstOrNull,
          onEdit: _openEditAccount,
          onDelete: (record) => widget.appState.deleteAccount(record.id),
          onAddSubscription: (record) =>
              _openAddSubscription(initialAccount: record),
        ),
      ),
    );
  }

  Future<void> _openRecentAccount(AccountRecord account) async {
    await widget.appState.markAccountViewed(account.id);
    if (!mounted) return;
    await _openAccountDetails(account);
  }

  Future<AccountEditorResult?> _saveNewAccountFromEditor(
    AccountEditorResult result,
  ) async {
    while (mounted &&
        widget.appState.isUnlocked &&
        widget.appState.hasFullVaultAccess) {
      final revision = widget.appState.localWebRevision;
      final candidates = widget.appState.findAccountDuplicates(result.account);
      if (candidates.isNotEmpty) {
        final choice = await showAccountDuplicateDialog(
          context: context,
          candidates: candidates,
          onOpenAccount: _openDuplicateRecord,
          onRestoreAccount: (account) =>
              widget.appState.restoreTrash(accountId: account.id),
        );
        if (!mounted ||
            !widget.appState.isUnlocked ||
            choice != AccountDuplicateChoice.addAnyway) {
          return null;
        }
        if (revision != widget.appState.localWebRevision) continue;
      }
      final creation = await widget.appState.createAccount(
        result.account,
        initialSubscription: result.initialSubscription,
        duplicateApprovedRevision: revision,
      );
      if (!mounted || !widget.appState.isUnlocked) return null;
      if (creation.status ==
          RecordCreationStatus.duplicateConfirmationRequired) {
        continue;
      }
      if (creation.status == RecordCreationStatus.limitReached) {
        await _showLimitUpsell(creation.limit!);
        return null;
      }
      if (!creation.saved) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，记录未写入。')));
        return null;
      }
      return result.copyWith(duplicateApprovedRevision: revision);
    }
    return null;
  }

  Future<AccountEditorResult?> _saveEditedAccountFromEditor(
    String id,
    AccountEditorResult result,
  ) async {
    final saved = await widget.appState.updateAccount(
      accountId: id,
      draft: result.account,
      passwordMode: result.passwordUpdateMode,
    );
    if (!mounted || !widget.appState.isUnlocked) return null;
    if (!saved) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('修改失败，原账号记录仍保留。')));
      return null;
    }
    return result;
  }

  Future<void> _openDuplicateRecord(AccountRecord record) async {
    if (!widget.appState.isUnlocked || !widget.appState.hasFullVaultAccess) {
      return;
    }
    if (widget.appState.accounts.any((a) => a.id == record.id)) {
      await _openAccountDetails(record);
    } else {
      final current = widget.appState.trashAccounts
          .where((a) => a.record.id == record.id)
          .firstOrNull;
      if (current == null) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => AccountDetailsPage(
            account: current.record,
            subscriptions: widget.appState.trashSubscriptions
                .where((s) => s.record.accountId == record.id)
                .map((s) => s.record)
                .toList(),
          ),
        ),
      );
    }
  }

  void _openStage3FilteredAccounts(AccountFilter filter) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      _stage3Filters = {filter};
      _stage3FilterToken++;
      _selectedIndex = AppDestination.accounts.index;
    });
  }

  Future<void> _openPasswordHealth() async {
    if (!widget.appState.isUnlocked || !widget.appState.hasFullVaultAccess) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: VaultPageLocation('passwordHealth'),
        builder: (_) => PasswordHealthCenterPage(
          analysisProvider: () => widget.appState.accountAnalysis,
          accountsProvider: () => widget.appState.accounts,
          changes: widget.appState,
          onOpenAccount: _openAccountDetails,
          onEditAccount: (a) async {
            await _openEditAccount(a);
          },
          onIgnore: widget.appState.ignorePasswordHealth,
          onRestore: (f) => widget.appState.restorePasswordHealthHint(
            f.accountId,
            f.issueType,
          ),
          onOpenFilteredAccounts: () =>
              _openStage3FilteredAccounts(AccountFilter.hasPasswordHealth),
        ),
      ),
    );
  }

  Future<void> _openBindings() async {
    if (!widget.appState.isUnlocked || !widget.appState.hasFullVaultAccess) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: VaultPageLocation('bindings'),
        builder: (_) => BindingCenterPage(
          analysisProvider: () => widget.appState.accountAnalysis,
          accountsProvider: () => widget.appState.accounts,
          changes: widget.appState,
          onOpenAccount: _openAccountDetails,
          onEditAccount: (a) async {
            await _openEditAccount(a);
          },
          onCreatePlan: widget.appState.createBindingRetirementPlan,
          onClosePlan: widget.appState.closeBindingRetirementPlan,
          onDeletePlan: (id) =>
              widget.appState.closeBindingRetirementPlan(id, delete: true),
          onOpenFilteredAccounts: () =>
              _openStage3FilteredAccounts(AccountFilter.hasBindingPending),
        ),
      ),
    );
  }

  Future<void> _openPasswordReviewCenter() async {
    if (widget.appState.hasSubscriptionOnlyAccess) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: VaultPageLocation('passwordHistory'),
        builder: (context) => PasswordChangeHistoryPage(
          recordsListenable: widget.appState,
          accountsProvider: () => widget.appState.accounts,
        ),
      ),
    );
  }

  Future<void> _openSubscriptionInsights() =>
      _openSubscriptionCostStats(initialTab: 1);
  Future<void> _openSubscriptionAttention() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: VaultPageLocation('subscriptionAttention'),
      builder: (context) => SubscriptionAttentionPage(
        state: widget.appState,
        onOpen: _openSubscriptionDetails,
      ),
    ),
  );

  Widget _monthlyEquivalentSummary(BuildContext context) {
    final totals = monthlyEquivalentTotals(
      monthlyEquivalentLines(widget.appState.subscriptions, DateTime.now()),
    );
    return Card(
      child: ListTile(
        title: const Text('当前有效订阅月等效费用'),
        subtitle: Text(
          totals.isEmpty
              ? context.tr('暂无可计算的正式订阅')
              : totals.entries
                    .map((e) => '${e.key} ${e.value.display}')
                    .join(' · '),
          translate: false,
        ),
        trailing: const Icon(Icons.insights_outlined),
        onTap: _openSubscriptionInsights,
      ),
    );
  }

  Future<void> _openSubscriptionCostStats({
    int initialTab = 0,
    bool currentMonth = false,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: VaultPageLocation(
        'subscriptionFinance',
        tab: initialTab,
        recordId: currentMonth ? 'currentMonth' : null,
      ),
      builder: (context) => SubscriptionFinancePage(
        state: widget.appState,
        initialTab: initialTab,
        currentMonth: currentMonth,
        onOpenSubscription: _openSubscriptionDetails,
      ),
    ),
  );

  Future<void> _openAddSubscription({
    AccountRecord? initialAccount,
    Map<String, Object?>? initialDraft,
  }) async {
    final openingDecision = widget.appState.subscriptionCreationDecision;
    if (!openingDecision.allowed) {
      await _showLimitUpsell(openingDecision);
      return;
    }
    final draft = await _pushEditor<SubscriptionDraft>(
      kind: 'subscription',
      build: (onChanged) => SubscriptionEditorPage(
        paymentMethods: widget.appState.paymentMethods,
        initialDraft: initialDraft,
        onDraftChanged: onChanged,
        accounts: sortAccountsForDisplay(
          accounts: widget.appState.accounts,
          subscriptions: widget.appState.subscriptions,
          sortMode: widget.appState.preferences.accountSortMode,
        ),
        initialAccountId: initialAccount?.id,
        defaultCurrency: widget.appState.preferences.defaultCurrency,
        defaultReminderDays:
            widget.appState.preferences.defaultReminderDaysBefore,
      ),
    );
    if (!mounted || draft == null) {
      return;
    }

    if (!await _reviewTrashSimilarity(
          widget.appState.hasSimilarTrashSubscription(
            draft.details.serviceName,
          ),
        ) ||
        !mounted) {
      return;
    }
    final creation = await widget.appState.createSubscription(draft);
    if (!mounted) {
      return;
    }
    if (creation.status == RecordCreationStatus.limitReached) {
      await _showLimitUpsell(creation.limit!);
      return;
    }
    final saved = creation.saved;
    if (saved && initialAccount == null) {
      setState(() {
        _subscriptionFilterPreset = null;
        _selectedIndex = AppDestination.subscriptions.index;
      });
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(saved ? '订阅已加密保存。' : '保存失败，订阅未写入。')),
      );
  }

  Future<void> _showLimitUpsell(EntitlementLimitDecision decision) =>
      showFullVersionUpsell(
        context,
        scene: decision.recordType == LimitedRecordType.account
            ? FullVersionUpsellScene.accountLimit
            : FullVersionUpsellScene.subscriptionLimit,
        usageLabel: decision.usageLabel,
      );

  Future<void> _openEditSubscription(
    SubscriptionRecord subscription, {
    Map<String, Object?>? initialDraft,
  }) async {
    final draft = await _pushEditor<SubscriptionDraft>(
      kind: 'subscription',
      existingId: subscription.id,
      build: (onChanged) => SubscriptionEditorPage(
        paymentMethods: widget.appState.paymentMethods,
        initialDraft: initialDraft,
        onDraftChanged: onChanged,
        accounts: sortAccountsForDisplay(
          accounts: widget.appState.accounts,
          subscriptions: widget.appState.subscriptions,
          sortMode: widget.appState.preferences.accountSortMode,
        ),
        existing: subscription,
        defaultCurrency: widget.appState.preferences.defaultCurrency,
        defaultReminderDays:
            widget.appState.preferences.defaultReminderDaysBefore,
      ),
    );
    if (!mounted || draft == null) {
      return;
    }

    final saved = await widget.appState.updateSubscription(
      subscriptionId: subscription.id,
      draft: draft,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(saved ? '订阅修改已加密保存。' : '修改失败，订阅未写入。')),
      );
  }

  Future<void> _openSubscriptionDetails(SubscriptionRecord subscription) async {
    final subscriptionOnly = widget.appState.hasSubscriptionOnlyAccess;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: VaultPageLocation('subscription', recordId: subscription.id),
        builder: (context) => SubscriptionDetailsPage(
          subscriptionId: subscription.id,
          managementBuilder: (record) => SubscriptionManagementPanel(
            state: widget.appState,
            subscription: record,
            onEdit: subscriptionOnly
                ? null
                : () => _openEditSubscription(record),
          ),
          recordsListenable: widget.appState,
          findSubscription: (id) => widget.appState.subscriptions
              .where((candidate) => candidate.id == id)
              .firstOrNull,
          findAccount: (id) => id == null
              ? null
              : widget.appState.accounts
                    .where((candidate) => candidate.id == id)
                    .firstOrNull,
          onEditSubscription: subscriptionOnly ? null : _openEditSubscription,
          onMarkRenewed: null,
          onMarkRenewedWithExpense: subscriptionOnly
              ? null
              : widget.appState.markSubscriptionRenewed,
          onSnoozeReminder: subscriptionOnly
              ? null
              : widget.appState.snoozeSubscriptionReminder,
          onCancelSubscription: subscriptionOnly
              ? null
              : widget.appState.cancelSubscription,
          onRestoreSubscription: subscriptionOnly
              ? null
              : widget.appState.restoreSubscription,
          onDeleteSubscription: subscriptionOnly
              ? null
              : (record) => widget.appState.deleteSubscription(record.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    _navigation?.selectedIndex = _selectedIndex;
    final subscriptionOnly = widget.appState.hasSubscriptionOnlyAccess;
    final shellTextScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.3);

    return PopScope<Object?>(
      canPop: _selectedDestination == AppDestination.home,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedDestination != AppDestination.home) {
          setState(() => _selectedIndex = AppDestination.home.index);
        }
      },
      child: Scaffold(
        appBar: _selectedDestination == AppDestination.home
            ? null
            : AppBar(
                toolbarHeight: 72,
                titleSpacing: CardockLayout.screenHorizontal,
                title: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedDestination.label,
                      key: const ValueKey<String>('page-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: shellTextScaler,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700, height: 1.05),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _destinationSubtitle(context),
                      translate: false,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: shellTextScaler,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    key: const ValueKey<String>('app-bar-manual-lock'),
                    onPressed: widget.appState.isBusy
                        ? null
                        : widget.onManualLock,
                    tooltip: context.tr('立即锁定'),
                    icon: const Icon(Icons.lock_outline_rounded),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
        body: ListenableBuilder(
          listenable: widget.appState,
          builder: (context, child) => SafeArea(
            top: _selectedDestination == AppDestination.home,
            child: Column(
              children: [
                if (widget.appState.warningMessage case final warning?)
                  MaterialBanner(
                    key: const ValueKey<String>('vault-recovery-warning'),
                    leading: CardockSemanticIcon(
                      icon: Icons.warning_amber_rounded,
                      color: palette.statusRenewSoon,
                    ),
                    content: Text(context.tr(warning), translate: false),
                    actions: [
                      TextButton(
                        onPressed: widget.appState.dismissWarning,
                        child: const Text('知道了'),
                      ),
                    ],
                  ),
                if (_selectedDestination == AppDestination.home &&
                    widget.appState.backupWarning != null)
                  MaterialBanner(
                    key: const ValueKey<String>('vault-backup-warning'),
                    content: Text(widget.appState.backupWarning!),
                    actions: [
                      TextButton(
                        onPressed: () => setState(() {
                          _selectedIndex = AppDestination.settings.index;
                          _healthOpenSignal++;
                        }),
                        child: const Text('数据安全与备份'),
                      ),
                      TextButton(
                        onPressed: widget.appState.dismissBackupWarning,
                        child: const Text('稍后提醒'),
                      ),
                    ],
                  ),
                if (_selectedDestination == AppDestination.home ||
                    subscriptionOnly)
                  SubscriptionAttentionBanner(
                    state: widget.appState,
                    onOpen: _openSubscriptionDetails,
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      if (subscriptionOnly)
                        _FullUnlockRequiredView(onLock: widget.onManualLock)
                      else
                        HomePage(
                          insightsSummary: _monthlyEquivalentSummary(context),
                          expenses: widget.appState.subscriptionExpenses,
                          onOpenMonthlyExpenses: () =>
                              _openSubscriptionCostStats(currentMonth: true),
                          accounts: widget.appState.accounts,
                          subscriptions: widget.appState.subscriptions,
                          recentAccounts: widget.appState.recentAccounts,
                          autoLockSeconds:
                              widget.appState.preferences.autoLockSeconds,
                          onOpenAccount: _openRecentAccount,
                          onOpenAccounts: _openAllAccounts,
                          onOpenSubscriptions: _openSubscriptionFilter,
                          onOpenAllSubscriptions: _openAllSubscriptions,
                          onOpenSubscription: _openSubscriptionDetails,
                          onSearch: _openAccountSearch,
                          onLock: widget.appState.isBusy
                              ? null
                              : widget.onManualLock,
                          onAddAccount: widget.appState.isBusy
                              ? null
                              : _openAddAccount,
                        ),
                      if (subscriptionOnly)
                        _FullUnlockRequiredView(onLock: widget.onManualLock)
                      else
                        AccountsPage(
                          key: ValueKey(widget.appState.subscriptionQueryScope),
                          analysis: widget.appState.accountAnalysis,
                          dataRevision: widget.appState.localWebRevision,
                          initialFilters: _stage3Filters,
                          filterToken: _stage3FilterToken,
                          onOpenPasswordHealth: _openPasswordHealth,
                          onOpenBindings: _openBindings,
                          onBatchCategory:
                              widget.appState.batchUpdateAccountCategory,
                          onBatchRecycle:
                              widget.appState.batchMoveAccountsToTrash,
                          countPendingDrafts: (ids) => widget.appState
                              .previewAccountBatchImpact(ids)
                              .pendingDraftCount,
                          accounts: widget.appState.accounts,
                          subscriptions: widget.appState.subscriptions,
                          displayMode:
                              widget.appState.preferences.accountDisplayMode,
                          sortMode: widget.appState.preferences.accountSortMode,
                          onSortModeChanged: _changeAccountSortMode,
                          resetFilterToken: _accountFilterResetToken,
                          searchFocusToken: _accountSearchFocusToken,
                          onAddAccount: _openAddAccount,
                          onOpenAccount: _openAccountDetails,
                          onEditAccount: (account) async {
                            await _openEditAccount(account);
                          },
                          onDeleteAccount: (account) =>
                              widget.appState.deleteAccount(account.id),
                          onAddSubscription: (account) =>
                              _openAddSubscription(initialAccount: account),
                          onAccountViewed: (account) async {
                            await widget.appState.markAccountViewed(account.id);
                          },
                          onOpenPasswordReview: _openPasswordReviewCenter,
                        ),
                      SubscriptionsPage(
                        key: ValueKey(widget.appState.subscriptionQueryScope),
                        readOnly: subscriptionOnly,
                        onOpenAttention: _openSubscriptionAttention,
                        accounts: widget.appState.accounts,
                        subscriptions: widget.appState.subscriptions,
                        displayMode:
                            widget.appState.preferences.subscriptionDisplayMode,
                        sortMode:
                            widget.appState.preferences.subscriptionSortMode,
                        onSortModeChanged: subscriptionOnly
                            ? null
                            : _changeSubscriptionSortMode,
                        filterPreset: _subscriptionFilterPreset,
                        onClearFilter: _clearSubscriptionFilter,
                        onOpenSubscription: _openSubscriptionDetails,
                        onAddSubscription: subscriptionOnly
                            ? null
                            : _openAddSubscription,
                        onEditSubscription: subscriptionOnly
                            ? null
                            : _openEditSubscription,
                        onMarkRenewedWithExpense: subscriptionOnly
                            ? null
                            : widget.appState.markSubscriptionRenewed,
                        onOpenCostStats: _openSubscriptionCostStats,
                        onSnoozeReminder: subscriptionOnly
                            ? null
                            : widget.appState.snoozeSubscriptionReminder,
                        onCancelSubscription: subscriptionOnly
                            ? null
                            : widget.appState.cancelSubscription,
                        onRestoreSubscription: subscriptionOnly
                            ? null
                            : widget.appState.restoreSubscription,
                        onDeleteSubscription: subscriptionOnly
                            ? null
                            : (subscription) => widget.appState
                                  .deleteSubscription(subscription.id),
                      ),
                      SettingsPage(
                        healthOpenSignal: _healthOpenSignal,
                        appState: widget.appState,
                        onLock: widget.onManualLock,
                        temporaryWebController: widget.temporaryWebController,
                        onNotificationsChanged:
                            widget.appState.setNotificationsEnabled,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _CardockBottomDock(
          selectedIndex: _navigationBarIndex,
          addEnabled: !subscriptionOnly && !widget.appState.isBusy,
          onSelected: _selectNavigationItem,
        ),
      ),
    );
  }
}

enum _QuickAddAction { account, subscription }

class _CardockBottomDock extends StatelessWidget {
  const _CardockBottomDock({
    required this.selectedIndex,
    required this.addEnabled,
    required this.onSelected,
  });

  static const double _topFadeHeight = CardockLayout.dockTopScrimHeight;
  static const double _bodyHeight = CardockLayout.bottomNavigationHeight;
  static const double _quickAddSize = CardockLayout.floatingActionButtonSize;
  static const double _quickAddLift = CardockLayout.centerActionOverhang;

  final int selectedIndex;
  final bool addEnabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final extension = context.cardockTheme;
    final palette = extension.palette;
    final materialProfile = extension.material;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        key: const ValueKey<String>('cardock-bottom-dock'),
        height: _topFadeHeight + _bodyHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              key: const ValueKey<String>('cardock-bottom-dock-top-fade'),
              top: 0,
              left: 0,
              right: 0,
              height: _topFadeHeight,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        palette.background.withValues(alpha: 0),
                        palette.background,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: _topFadeHeight,
              left: CardockLayout.dockHorizontal,
              right: CardockLayout.dockHorizontal,
              height: _bodyHeight,
              child: CustomPaint(
                key: const ValueKey<String>('cardock-bottom-dock-body'),
                painter: _DockBodyPainter(
                  fill: palette.surfaceDock,
                  border: palette.border,
                  borderWidth: materialProfile.cardBorderWidth,
                  shadows: materialProfile.dockShadows,
                ),
                child: ClipPath(
                  clipper: const _DockBodyClipper(),
                  child: Material(
                    color: palette.surfaceDock,
                    child: Row(
                      children: [
                        Expanded(
                          child: _DockNavigationItem(
                            destination: AppDestination.home,
                            selected: selectedIndex == 0,
                            onTap: () => onSelected(0),
                          ),
                        ),
                        Expanded(
                          child: _DockNavigationItem(
                            destination: AppDestination.accounts,
                            selected: selectedIndex == 1,
                            onTap: () => onSelected(1),
                          ),
                        ),
                        const SizedBox(width: 66),
                        Expanded(
                          child: _DockNavigationItem(
                            destination: AppDestination.subscriptions,
                            selected: selectedIndex == 3,
                            onTap: () => onSelected(3),
                          ),
                        ),
                        Expanded(
                          child: _DockNavigationItem(
                            destination: AppDestination.settings,
                            selected: selectedIndex == 4,
                            onTap: () => onSelected(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: _topFadeHeight - _quickAddLift,
              left: 0,
              right: 0,
              child: Center(
                child: _DockQuickAddButton(
                  enabled: addEnabled,
                  size: _quickAddSize,
                  onTap: () => onSelected(2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Path _dockBodyPath(Size size) {
  const radius = 23.0;
  const notchHalfWidth = 35.0;
  const notchDepth = 16.0;
  final center = size.width / 2;
  return Path()
    ..moveTo(radius, 0)
    ..lineTo(center - notchHalfWidth, 0)
    ..cubicTo(center - 24, 0, center - 23, notchDepth, center, notchDepth)
    ..cubicTo(
      center + 23,
      notchDepth,
      center + 24,
      0,
      center + notchHalfWidth,
      0,
    )
    ..lineTo(size.width - radius, 0)
    ..quadraticBezierTo(size.width, 0, size.width, radius)
    ..lineTo(size.width, size.height - radius)
    ..quadraticBezierTo(
      size.width,
      size.height,
      size.width - radius,
      size.height,
    )
    ..lineTo(radius, size.height)
    ..quadraticBezierTo(0, size.height, 0, size.height - radius)
    ..lineTo(0, radius)
    ..quadraticBezierTo(0, 0, radius, 0)
    ..close();
}

class _DockBodyClipper extends CustomClipper<Path> {
  const _DockBodyClipper();

  @override
  Path getClip(Size size) => _dockBodyPath(size);

  @override
  bool shouldReclip(covariant _DockBodyClipper oldClipper) => false;
}

class _DockBodyPainter extends CustomPainter {
  const _DockBodyPainter({
    required this.fill,
    required this.border,
    required this.borderWidth,
    required this.shadows,
  });

  final Color fill;
  final Color border;
  final double borderWidth;
  final List<CardockShadowSpec> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _dockBodyPath(size);
    for (final shadow in shadows) {
      canvas
        ..save()
        ..translate(shadow.offset.dx, shadow.offset.dy)
        ..drawPath(
          path,
          Paint()
            ..color = shadow.color
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              (shadow.blurRadius * 0.57735) + 0.5,
            ),
        )
        ..restore();
    }
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _DockBodyPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.border != border ||
      oldDelegate.borderWidth != borderWidth ||
      oldDelegate.shadows != shadows;
}

class _DockNavigationItem extends StatelessWidget {
  const _DockNavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final color = selected ? palette.navigationActive : palette.textTertiary;
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.3);
    return _DockPressScale(
      key: ValueKey<String>('nav-${destination.name}'),
      scaleKey: ValueKey<String>('nav-${destination.name}-scale'),
      semanticLabel: context.tr(destination.label),
      selected: selected,
      enabled: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: CardockLayout.minimumTapTarget,
          minHeight: CardockLayout.minimumTapTarget,
        ),
        child: SizedBox(
          height: _CardockBottomDock._bodyHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration:
                    MediaQuery.maybeOf(context)?.disableAnimations ?? false
                    ? Duration.zero
                    : CardockMotion.quick,
                width: 38,
                height: 28,
                decoration: BoxDecoration(
                  color: selected
                      ? palette.primarySoft.withValues(alpha: 0.72)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(CardockRadius.pill),
                ),
                alignment: Alignment.center,
                child: Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                destination.label,
                textScaler: textScaler,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  color: color,
                  fontSize: CardockTypography.navigation,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  height: 1.05,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockQuickAddButton extends StatelessWidget {
  const _DockQuickAddButton({
    required this.enabled,
    required this.size,
    required this.onTap,
  });

  final bool enabled;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final extension = context.cardockTheme;
    final palette = extension.palette;
    final materialProfile = extension.material;
    final color = enabled ? palette.primary : palette.surfaceAlt;
    return _DockPressScale(
      key: const ValueKey<String>('nav-add'),
      scaleKey: const ValueKey<String>('nav-add-scale'),
      semanticLabel: context.tr('新增账号或订阅'),
      selected: false,
      enabled: enabled,
      onTap: onTap,
      customBorder: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CardockRadius.floatingActionButton),
      ),
      child: Material(
        key: const ValueKey<String>('cardock-bottom-dock-add-button'),
        color: color,
        elevation: enabled ? materialProfile.fabElevation : 0,
        shadowColor: materialProfile.cardShadows.isEmpty
            ? Colors.transparent
            : materialProfile.cardShadows.first.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            CardockRadius.floatingActionButton,
          ),
          side: BorderSide(
            color: enabled ? palette.primary : palette.border,
            width: materialProfile.cardBorderWidth,
          ),
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            Icons.add_rounded,
            color: enabled
                ? Theme.of(context).colorScheme.onPrimary
                : palette.textTertiary,
            size: 28,
          ),
        ),
      ),
    );
  }
}

class _DockPressScale extends StatefulWidget {
  const _DockPressScale({
    required this.scaleKey,
    required this.semanticLabel,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.child,
    this.customBorder,
    super.key,
  });

  final Key scaleKey;
  final String semanticLabel;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;
  final ShapeBorder? customBorder;

  @override
  State<_DockPressScale> createState() => _DockPressScaleState();
}

class _DockPressScaleState extends State<_DockPressScale> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: AnimatedScale(
        key: widget.scaleKey,
        scale: _pressed ? 0.96 : 1,
        duration: disableAnimations ? Duration.zero : CardockMotion.quick,
        curve: CardockMotion.standard,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (value) {
              if (_pressed == value) return;
              setState(() => _pressed = value);
            },
            customBorder: widget.customBorder,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _QuickAddSheet extends StatelessWidget {
  const _QuickAddSheet();

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return Padding(
      key: const ValueKey<String>('quick-add-sheet'),
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('新增记录', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '选择要保存到本机加密保险库的记录类型。',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textTertiary),
          ),
          const SizedBox(height: 12),
          CardockSurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  key: const ValueKey<String>('quick-add-account'),
                  leading: CardockSemanticIcon(
                    icon: Icons.badge_outlined,
                    color: palette.accountAccent,
                  ),
                  title: const Text('新增账号'),
                  subtitle: const Text('记录登录资料、密码和账号备注'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      Navigator.of(context).pop(_QuickAddAction.account),
                ),
                Divider(height: 1, color: palette.border),
                ListTile(
                  key: const ValueKey<String>('quick-add-subscription'),
                  leading: CardockSemanticIcon(
                    icon: Icons.event_repeat_outlined,
                    color: palette.subscriptionAccent,
                  ),
                  title: const Text('新增订阅'),
                  subtitle: const Text('记录套餐、续费日期和提醒'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      Navigator.of(context).pop(_QuickAddAction.subscription),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FullUnlockRequiredView extends StatelessWidget {
  const _FullUnlockRequiredView({required this.onLock});

  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return Center(
      key: const ValueKey<String>('full-vault-unlock-required'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: CardockSurfaceCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CardockSemanticIcon(
                  icon: Icons.lock_person_outlined,
                  color: palette.fieldPassword,
                  size: 56,
                ),
                const SizedBox(height: 16),
                Text(
                  '账号信息仍处于加密锁定状态',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  '当前生物识别只解开了独立的订阅只读视图。要查看账号、编辑记录或使用备份，请改用真实主密码。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onLock,
                  icon: const Icon(Icons.password_outlined),
                  label: const Text('锁定并改用主密码'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
