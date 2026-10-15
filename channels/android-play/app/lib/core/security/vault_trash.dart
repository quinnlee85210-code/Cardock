import '../../features/subscriptions/domain/subscription_cost_archive.dart';
import 'vault_contract.dart';
import '../../features/subscriptions/domain/pending_subscription_draft.dart';

/// All transitions produce one validated immutable snapshot before any write.
abstract final class VaultTrash {
  static VaultSnapshot move(
    VaultSnapshot source, {
    String? accountId,
    String? subscriptionId,
    required DateTime now,
    required String batchId,
  }) => _moveSelected(
    source,
    accountIds: accountId == null ? const {} : {accountId},
    subscriptionIds: subscriptionId == null ? const {} : {subscriptionId},
    now: now,
    batchId: batchId,
  );

  /// Bulk selection is validated and archived once, independent of selection size.
  static VaultSnapshot moveAccounts(
    VaultSnapshot source, {
    required Set<String> accountIds,
    required DateTime now,
    required String batchId,
  }) =>
      _moveSelected(source, accountIds: accountIds, now: now, batchId: batchId);

  static VaultSnapshot _moveSelected(
    VaultSnapshot source, {
    Set<String> accountIds = const {},
    Set<String> subscriptionIds = const {},
    required DateTime now,
    required String batchId,
  }) {
    final accounts = source.accounts
        .where((item) => accountIds.contains(item.id))
        .toList();
    final subscriptions = source.subscriptions
        .where(
          (item) =>
              subscriptionIds.contains(item.id) ||
              accountIds.contains(item.accountId),
        )
        .toList();
    final selectedSubscriptionIds = subscriptions
        .map((item) => item.id)
        .toSet();
    if (accountIds.isEmpty && subscriptionIds.isEmpty ||
        accounts.length != accountIds.length ||
        !selectedSubscriptionIds.containsAll(subscriptionIds)) {
      throw const VaultFormatException();
    }
    final draftsByAccount = <String, List<PendingSubscriptionDraft>>{};
    for (final draft in source.pendingSubscriptionDrafts) {
      if (accountIds.contains(draft.accountId)) {
        (draftsByAccount[draft.accountId] ??= []).add(draft);
      }
    }
    final removed = subscriptions.map((item) => item.id).toSet();
    final archived = archiveRemovedSubscriptionCosts(
      removedSubscriptions: subscriptions,
      accounts: source.accounts,
      retainedAccountIds: {
        ...source.accounts.map((item) => item.id),
        ...source.trashAccounts.map((item) => item.record.id),
      },
      previousExpenses: source.subscriptionExpenses,
      expenses: source.subscriptionExpenses,
      nextExpenseId: source.nextExpenseId,
      today: now,
      preserveSubscriptionId: true,
    );
    return source.copyWith(
      accounts: source.accounts
          .where((item) => !accountIds.contains(item.id))
          .toList(),
      subscriptions: source.subscriptions
          .where((item) => !removed.contains(item.id))
          .toList(),
      trashAccounts: [
        ...source.trashAccounts,
        for (final account in accounts)
          TrashAccount(
            record: account,
            deletedAtUtc: now,
            batchId: batchId,
            pendingDrafts: draftsByAccount[account.id] ?? const [],
          ),
      ],
      trashSubscriptions: [
        ...source.trashSubscriptions,
        for (final sub in subscriptions)
          TrashSubscription(record: sub, deletedAtUtc: now, batchId: batchId),
      ],
      pendingSubscriptionDrafts: source.pendingSubscriptionDrafts
          .where((item) => !accountIds.contains(item.accountId))
          .toList(),
      recentAccountIds: source.recentAccountIds
          .where((id) => !accountIds.contains(id))
          .toList(),
      nextExpenseId: archived.nextExpenseId,
      subscriptionExpenses: archived.expenses,
    );
  }

  static VaultSnapshot restore(
    VaultSnapshot source, {
    String? accountId,
    String? subscriptionId,
    bool wholeBatch = false,
  }) {
    final account = source.trashAccounts
        .where((item) => item.record.id == accountId)
        .firstOrNull;
    final sub = source.trashSubscriptions
        .where((item) => item.record.id == subscriptionId)
        .firstOrNull;
    if (account == null && sub == null) throw const VaultFormatException();
    final batch = account?.batchId ?? sub!.batchId;
    final accounts = source.trashAccounts
        .where(
          (item) =>
              item.record.id == accountId ||
              (wholeBatch && item.batchId == batch),
        )
        .toList();
    final subscriptions = source.trashSubscriptions
        .where(
          (item) =>
              item.record.id == subscriptionId ||
              (wholeBatch && item.batchId == batch),
        )
        .toList();
    return source.copyWith(
      accounts: [...source.accounts, ...accounts.map((item) => item.record)],
      subscriptions: [
        ...source.subscriptions,
        ...subscriptions.map((item) => item.record),
      ],
      pendingSubscriptionDrafts: [
        ...source.pendingSubscriptionDrafts,
        ...accounts.expand((item) => item.pendingDrafts),
      ],
      trashAccounts: source.trashAccounts
          .where((item) => !accounts.contains(item))
          .toList(),
      trashSubscriptions: source.trashSubscriptions
          .where((item) => !subscriptions.contains(item))
          .toList(),
    );
  }

  static VaultSnapshot remove(
    VaultSnapshot source, {
    Set<String> accountIds = const {},
    Set<String> subscriptionIds = const {},
  }) {
    final accounts = source.trashAccounts
        .where((item) => accountIds.contains(item.record.id))
        .map((item) => item.record.id)
        .toSet();
    final subscriptions = source.trashSubscriptions
        .where(
          (item) =>
              subscriptionIds.contains(item.record.id) ||
              accounts.contains(item.record.accountId),
        )
        .map((item) => item.record.id)
        .toSet();
    return source.copyWith(
      passwordHealthIgnoreRules: source.passwordHealthIgnoreRules
          .where(
            (rule) =>
                !accounts.contains(rule.accountId) &&
                !rule.memberRevisions.keys.any(accounts.contains),
          )
          .toList(),
      bindingRetirementPlans: source.bindingRetirementPlans
          .map(
            (plan) =>
                plan.copyWith(accountIds: plan.accountIds.difference(accounts)),
          )
          .where((plan) => plan.accountIds.isNotEmpty)
          .toList(),
      trashAccounts: source.trashAccounts
          .where((item) => !accounts.contains(item.record.id))
          .toList(),
      trashSubscriptions: source.trashSubscriptions
          .where((item) => !subscriptions.contains(item.record.id))
          .toList(),
      subscriptionExpenses: source.subscriptionExpenses.map((expense) {
        final unlinked = subscriptions.contains(expense.subscriptionId)
            ? expense.unlinkSubscription()
            : expense;
        return accounts.contains(unlinked.accountId)
            ? unlinked.withAccountContext(
                accountId: null,
                accountLabel: unlinked.accountLabel,
              )
            : unlinked;
      }).toList(),
    );
  }

  static VaultSnapshot purgeExpired(VaultSnapshot source, DateTime now) =>
      remove(
        source,
        accountIds: source.trashAccounts
            .where((item) => item.expired(now))
            .map((item) => item.record.id)
            .toSet(),
        subscriptionIds: source.trashSubscriptions
            .where((item) => item.expired(now))
            .map((item) => item.record.id)
            .toSet(),
      );
}
