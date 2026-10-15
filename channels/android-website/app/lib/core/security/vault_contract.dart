import 'dart:typed_data';
import 'trash_record.dart';
import 'subscription_metadata_migration.dart';
export 'trash_record.dart';

import '../preferences/record_display_mode.dart';
import '../preferences/record_sort_mode.dart';
import '../../features/accounts/domain/account_record.dart';
import '../../features/subscriptions/domain/pending_subscription_draft.dart';
import '../../features/subscriptions/domain/subscription_expense_record.dart';
import '../../features/subscriptions/domain/subscription_record.dart';
import '../../features/subscriptions/domain/subscription_expense_automation.dart';

abstract interface class VaultStore {
  Future<bool> exists();

  Future<VaultOpenResult> create({required String masterPassword});

  Future<VaultOpenResult> unlock({required String masterPassword});

  Future<bool> isQuickUnlockEnabled();

  Future<VaultOpenResult> unlockWithQuickUnlock();

  Future<void> disableQuickUnlock();

  Future<VaultSnapshot> readEncryptedBackup({
    required List<int> bytes,
    required String masterPassword,
  });
}

abstract interface class VaultSession {
  int get generation;

  Future<void> save(VaultSnapshot snapshot);

  Future<Uint8List> exportEncryptedBackup();

  Future<void> enableQuickUnlock();

  void close();
}

/// A stable, non-secret identifier for binding an in-memory capability to the
/// same encrypted vault across lock/unlock cycles.
abstract interface class VaultBoundSession implements VaultSession {
  String get vaultBindingId;
}

/// 仅完整可写保险库会话实现的批量事务能力。
abstract interface class BatchRollbackVaultSession implements VaultSession {
  BatchRollbackAvailability get batchRollbackAvailability;

  BatchRollbackSummary? get lastBatchRollbackSummary;

  bool get canUndoLastBatch;

  Future<void> saveBatchWithRollback({
    required VaultSnapshot before,
    required VaultSnapshot after,
  });

  Future<VaultSnapshot> undoLastBatch();

  Future<void> discardLastBatchRollback();
}

/// 最近一次批量导入回滚点在当前保险库 revision 下的可用状态。
enum BatchRollbackAvailability { none, available, revisionChanged, unreadable }

/// 回滚点解密后，根据“导入前快照”和当前精确快照重新计算的影响范围。
///
/// 这里只保存数量，不保存任何业务字段；应用重启后也不依赖明文旁路元数据。
final class BatchRollbackSummary {
  const BatchRollbackSummary({
    required this.addedAccountCount,
    required this.updatedAccountCount,
    required this.formalSubscriptionCount,
    required this.pendingSubscriptionDraftCount,
  });

  final int addedAccountCount;
  final int updatedAccountCount;
  final int formalSubscriptionCount;
  final int pendingSubscriptionDraftCount;
}

final class VaultOpenResult {
  const VaultOpenResult({
    required this.session,
    required this.snapshot,
    this.recoveredFromFallback = false,
  });

  final VaultSession session;
  final VaultSnapshot snapshot;
  final bool recoveredFromFallback;
}

final class VaultSnapshot {
  static const currentSchemaVersion = 15;

  factory VaultSnapshot({
    bool requiresSchemaUpgrade = false,
    required int nextAccountId,
    required List<AccountRecord> accounts,
    List<PaymentMethodRecord> paymentMethods = const [],
    List<PasswordHealthIgnoreRule> passwordHealthIgnoreRules = const [],
    List<BindingRetirementPlan> bindingRetirementPlans = const [],
    List<TrashAccount> trashAccounts = const [],
    List<TrashSubscription> trashSubscriptions = const [],
    int nextSubscriptionId = 1,
    List<SubscriptionRecord> subscriptions = const <SubscriptionRecord>[],
    int nextExpenseId = 1,
    List<SubscriptionExpenseRecord> subscriptionExpenses =
        const <SubscriptionExpenseRecord>[],
    List<PendingSubscriptionDraft> pendingSubscriptionDrafts =
        const <PendingSubscriptionDraft>[],
    VaultPreferences preferences = const VaultPreferences(),
    List<String> recentAccountIds = const <String>[],
  }) {
    final frozenAccounts = List<AccountRecord>.unmodifiable(accounts);
    final frozenTrashAccounts = List<TrashAccount>.unmodifiable(trashAccounts);
    final frozenTrashSubscriptions = List<TrashSubscription>.unmodifiable(
      trashSubscriptions,
    );
    final frozenSubscriptions = List<SubscriptionRecord>.unmodifiable(
      subscriptions,
    );
    final frozenSubscriptionExpenses =
        List<SubscriptionExpenseRecord>.unmodifiable(subscriptionExpenses);
    final frozenPendingSubscriptionDrafts =
        List<PendingSubscriptionDraft>.unmodifiable(pendingSubscriptionDrafts);
    final frozenRecentAccountIds = List<String>.unmodifiable(recentAccountIds);
    _validateSnapshot(
      nextAccountId: nextAccountId,
      accounts: frozenAccounts,
      paymentMethods: paymentMethods,
      passwordHealthIgnoreRules: passwordHealthIgnoreRules,
      bindingRetirementPlans: bindingRetirementPlans,
      trashAccounts: frozenTrashAccounts,
      trashSubscriptions: frozenTrashSubscriptions,
      nextSubscriptionId: nextSubscriptionId,
      subscriptions: frozenSubscriptions,
      nextExpenseId: nextExpenseId,
      subscriptionExpenses: frozenSubscriptionExpenses,
      pendingSubscriptionDrafts: frozenPendingSubscriptionDrafts,
      preferences: preferences,
      recentAccountIds: frozenRecentAccountIds,
    );
    return VaultSnapshot._(
      requiresSchemaUpgrade: requiresSchemaUpgrade,
      nextAccountId: nextAccountId,
      accounts: frozenAccounts,
      paymentMethods: List.unmodifiable(paymentMethods),
      passwordHealthIgnoreRules: List.unmodifiable(passwordHealthIgnoreRules),
      bindingRetirementPlans: List.unmodifiable(bindingRetirementPlans),
      trashAccounts: frozenTrashAccounts,
      trashSubscriptions: frozenTrashSubscriptions,
      nextSubscriptionId: nextSubscriptionId,
      subscriptions: frozenSubscriptions,
      nextExpenseId: nextExpenseId,
      subscriptionExpenses: frozenSubscriptionExpenses,
      pendingSubscriptionDrafts: frozenPendingSubscriptionDrafts,
      preferences: preferences,
      recentAccountIds: frozenRecentAccountIds,
    );
  }

  const VaultSnapshot._({
    this.requiresSchemaUpgrade = false,
    required this.nextAccountId,
    required this.accounts,
    required this.paymentMethods,
    required this.passwordHealthIgnoreRules,
    required this.bindingRetirementPlans,
    required this.trashAccounts,
    required this.trashSubscriptions,
    required this.nextSubscriptionId,
    required this.subscriptions,
    required this.nextExpenseId,
    required this.subscriptionExpenses,
    required this.pendingSubscriptionDrafts,
    required this.preferences,
    required this.recentAccountIds,
  });

  factory VaultSnapshot.empty() => VaultSnapshot(
    nextAccountId: 1,
    accounts: const <AccountRecord>[],
    nextSubscriptionId: 1,
    subscriptions: const <SubscriptionRecord>[],
    nextExpenseId: 1,
    subscriptionExpenses: const <SubscriptionExpenseRecord>[],
    pendingSubscriptionDrafts: const <PendingSubscriptionDraft>[],
    preferences: const VaultPreferences(),
    recentAccountIds: const <String>[],
  );

  factory VaultSnapshot.fromEncryptedPayloadJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const VaultFormatException();
    }

    final schemaVersion = value['schemaVersion'];
    if (schemaVersion is int && schemaVersion > currentSchemaVersion) {
      throw VaultUnsupportedSchemaVersionException(schemaVersion);
    }
    if (schemaVersion is! int || schemaVersion < 1) {
      throw const VaultFormatException();
    }
    final nextAccountId = value['nextAccountId'];
    final rawAccounts = value['accounts'];
    if (nextAccountId is! int ||
        nextAccountId < 1 ||
        nextAccountId > 1000000000 ||
        rawAccounts is! List<Object?> ||
        rawAccounts.length > 10000) {
      throw const VaultFormatException();
    }

    try {
      final rawTrashAccounts = (schemaVersion >= 11)
          ? value['trashAccounts']
          : const [];
      final rawTrashSubscriptions = (schemaVersion >= 11)
          ? value['trashSubscriptions']
          : const [];
      if (rawTrashAccounts is! List ||
          rawTrashAccounts.length > 10000 ||
          rawTrashSubscriptions is! List ||
          rawTrashSubscriptions.length > 50000) {
        throw const VaultFormatException();
      }
      final trashAccounts = rawTrashAccounts
          .map(
            (item) => TrashAccount.fromJson(
              item,
              allowStage3Metadata: schemaVersion >= 13,
            ),
          )
          .toList();
      final trashSubscriptions = rawTrashSubscriptions
          .map(TrashSubscription.fromJson)
          .toList();
      final accounts = rawAccounts
          .map(
            (item) => AccountRecord.fromEncryptedPayloadJson(
              item,
              allowStage3Metadata: schemaVersion >= 13,
              allowPasswordReviewMetadata:
                  (schemaVersion == 9 ||
                  schemaVersion == 10 ||
                  (schemaVersion >= 11)),
              allowPasswordChangeHistory:
                  schemaVersion == 10 || (schemaVersion >= 11),
            ),
          )
          .toList(growable: false);

      if (schemaVersion == 1) {
        return VaultSnapshot(
          nextAccountId: nextAccountId,
          accounts: accounts,
          requiresSchemaUpgrade: true,
        );
      }

      final nextSubscriptionId = value['nextSubscriptionId'];
      final rawSubscriptions = value['subscriptions'];
      if (nextSubscriptionId is! int ||
          nextSubscriptionId < 1 ||
          nextSubscriptionId > 1000000000 ||
          rawSubscriptions is! List<Object?> ||
          rawSubscriptions.length > 50000) {
        throw const VaultFormatException();
      }
      final subscriptions = rawSubscriptions
          .map(
            (value) => SubscriptionRecord.fromEncryptedPayloadJson(
              value,
              allowStandalone:
                  schemaVersion == 5 ||
                  schemaVersion == 6 ||
                  schemaVersion == 7 ||
                  schemaVersion == 8 ||
                  (schemaVersion == 9 ||
                      schemaVersion == 10 ||
                      (schemaVersion >= 11)),
              allowInstantSnooze:
                  schemaVersion == 6 ||
                  schemaVersion == 7 ||
                  schemaVersion == 8 ||
                  (schemaVersion == 9 ||
                      schemaVersion == 10 ||
                      (schemaVersion >= 11)),
              allowExpenseCategory:
                  (schemaVersion == 9 ||
                  schemaVersion == 10 ||
                  (schemaVersion >= 11)),
            ),
          )
          .toList(growable: false);
      final hasPreferences =
          schemaVersion == 4 ||
          schemaVersion == 5 ||
          schemaVersion == 6 ||
          schemaVersion == 7 ||
          schemaVersion == 8 ||
          (schemaVersion == 9 || schemaVersion == 10 || (schemaVersion >= 11));
      final preferences = hasPreferences
          ? VaultPreferences.fromEncryptedPayloadJson(
              value['preferences'],
              requireSecondReminderTime: schemaVersion >= 14,
              allowPasswordReviewNotifications:
                  (schemaVersion == 9 ||
                  schemaVersion == 10 ||
                  (schemaVersion >= 11)),
            )
          : const VaultPreferences();
      final rawRecentAccountIds = hasPreferences
          ? value['recentAccountIds']
          : const <Object?>[];
      if (rawRecentAccountIds is! List<Object?> ||
          rawRecentAccountIds.length > 10 ||
          rawRecentAccountIds.any((item) => item is! String)) {
        throw const VaultFormatException();
      }
      final rawPendingSubscriptionDrafts =
          schemaVersion == 7 ||
              schemaVersion == 8 ||
              (schemaVersion == 9 ||
                  schemaVersion == 10 ||
                  (schemaVersion >= 11))
          ? value['pendingSubscriptionDrafts']
          : const <Object?>[];
      if (rawPendingSubscriptionDrafts is! List<Object?> ||
          rawPendingSubscriptionDrafts.length > 50000) {
        throw const VaultFormatException();
      }
      final pendingSubscriptionDrafts = rawPendingSubscriptionDrafts
          .map(PendingSubscriptionDraft.fromEncryptedPayloadJson)
          .toList(growable: false);
      final nextExpenseId =
          (schemaVersion == 9 || schemaVersion == 10 || (schemaVersion >= 11))
          ? value['nextExpenseId']
          : 1;
      final rawSubscriptionExpenses =
          (schemaVersion == 9 || schemaVersion == 10 || (schemaVersion >= 11))
          ? value['subscriptionExpenses']
          : const <Object?>[];
      if (nextExpenseId is! int ||
          nextExpenseId < 1 ||
          nextExpenseId > 1000000000 ||
          rawSubscriptionExpenses is! List<Object?> ||
          rawSubscriptionExpenses.length >
              maximumConfirmedSubscriptionExpenses) {
        throw const VaultFormatException();
      }
      if (schemaVersion >= 15 &&
          rawSubscriptionExpenses.any(
            (entry) => entry is! Map || entry['isDeleted'] is! bool,
          )) {
        throw const VaultFormatException();
      }
      final subscriptionExpenses = rawSubscriptionExpenses
          .map(SubscriptionExpenseRecord.fromEncryptedPayloadJson)
          .toList(growable: false);
      final ledger = (schemaVersion == 10 || (schemaVersion >= 11))
          ? null
          : recordSubscriptionActions(
              previousSubscriptions: const [],
              subscriptions: subscriptions,
              accounts: accounts,
              expenses: subscriptionExpenses,
              nextExpenseId: nextExpenseId,
              migrating: true,
            );
      final rawPaymentMethods = schemaVersion >= 12
          ? value['paymentMethods']
          : const [];
      if (rawPaymentMethods is! List || rawPaymentMethods.length > 10000) {
        throw const VaultFormatException();
      }
      final rawIgnores = schemaVersion >= 13
          ? value['passwordHealthIgnoreRules']
          : const [];
      final rawPlans = schemaVersion >= 13
          ? value['bindingRetirementPlans']
          : const [];
      if (rawIgnores is! List ||
          rawIgnores.length > 100000 ||
          rawPlans is! List ||
          rawPlans.length > 10000) {
        throw const VaultFormatException();
      }
      final result = VaultSnapshot(
        requiresSchemaUpgrade: schemaVersion != currentSchemaVersion,
        passwordHealthIgnoreRules: rawIgnores
            .map(PasswordHealthIgnoreRule.fromJson)
            .toList(),
        bindingRetirementPlans: rawPlans
            .map(BindingRetirementPlan.fromJson)
            .toList(),
        paymentMethods: rawPaymentMethods
            .map(PaymentMethodRecord.fromJson)
            .toList(),
        nextAccountId: nextAccountId,
        accounts: accounts,
        trashAccounts: trashAccounts,
        trashSubscriptions: trashSubscriptions,
        nextSubscriptionId: nextSubscriptionId,
        subscriptions: subscriptions,
        nextExpenseId: ledger?.nextExpenseId ?? nextExpenseId,
        subscriptionExpenses: ledger?.expenses ?? subscriptionExpenses,
        pendingSubscriptionDrafts: pendingSubscriptionDrafts,
        preferences: preferences,
        recentAccountIds: rawRecentAccountIds.cast<String>(),
      );
      return schemaVersion >= 12
          ? result
          : normalizeSubscriptionMetadata(result);
    } on VaultFormatException {
      rethrow;
    } on FormatException {
      throw const VaultFormatException();
    } on ArgumentError {
      throw const VaultFormatException();
    }
  }

  final bool requiresSchemaUpgrade;
  final int nextAccountId;
  final List<AccountRecord> accounts;
  final List<PaymentMethodRecord> paymentMethods;
  final List<PasswordHealthIgnoreRule> passwordHealthIgnoreRules;
  final List<BindingRetirementPlan> bindingRetirementPlans;
  final List<TrashAccount> trashAccounts;
  final List<TrashSubscription> trashSubscriptions;
  final int nextSubscriptionId;
  final List<SubscriptionRecord> subscriptions;
  final int nextExpenseId;
  final List<SubscriptionExpenseRecord> subscriptionExpenses;
  final List<PendingSubscriptionDraft> pendingSubscriptionDrafts;
  final VaultPreferences preferences;
  final List<String> recentAccountIds;

  VaultSnapshot copyWith({
    bool? requiresSchemaUpgrade,
    int? nextAccountId,
    List<AccountRecord>? accounts,
    List<PaymentMethodRecord>? paymentMethods,
    List<PasswordHealthIgnoreRule>? passwordHealthIgnoreRules,
    List<BindingRetirementPlan>? bindingRetirementPlans,
    List<TrashAccount>? trashAccounts,
    List<TrashSubscription>? trashSubscriptions,
    int? nextSubscriptionId,
    List<SubscriptionRecord>? subscriptions,
    int? nextExpenseId,
    List<SubscriptionExpenseRecord>? subscriptionExpenses,
    List<PendingSubscriptionDraft>? pendingSubscriptionDrafts,
    VaultPreferences? preferences,
    List<String>? recentAccountIds,
  }) => VaultSnapshot(
    requiresSchemaUpgrade: requiresSchemaUpgrade ?? this.requiresSchemaUpgrade,
    nextAccountId: nextAccountId ?? this.nextAccountId,
    accounts: accounts ?? this.accounts,
    paymentMethods: paymentMethods ?? this.paymentMethods,
    passwordHealthIgnoreRules:
        passwordHealthIgnoreRules ?? this.passwordHealthIgnoreRules,
    bindingRetirementPlans:
        bindingRetirementPlans ?? this.bindingRetirementPlans,
    trashAccounts: trashAccounts ?? this.trashAccounts,
    trashSubscriptions: trashSubscriptions ?? this.trashSubscriptions,
    nextSubscriptionId: nextSubscriptionId ?? this.nextSubscriptionId,
    subscriptions: subscriptions ?? this.subscriptions,
    nextExpenseId: nextExpenseId ?? this.nextExpenseId,
    subscriptionExpenses: subscriptionExpenses ?? this.subscriptionExpenses,
    pendingSubscriptionDrafts:
        pendingSubscriptionDrafts ?? this.pendingSubscriptionDrafts,
    preferences: preferences ?? this.preferences,
    recentAccountIds: recentAccountIds ?? this.recentAccountIds,
  );

  Map<String, Object?> toEncryptedPayloadJson() => <String, Object?>{
    'schemaVersion': currentSchemaVersion,
    'paymentMethods': paymentMethods.map((p) => p.toJson()).toList(),
    'passwordHealthIgnoreRules': passwordHealthIgnoreRules
        .map((rule) => rule.toJson())
        .toList(),
    'bindingRetirementPlans': bindingRetirementPlans
        .map((plan) => plan.toJson())
        .toList(),
    'nextAccountId': nextAccountId,
    'nextSubscriptionId': nextSubscriptionId,
    'nextExpenseId': nextExpenseId,
    'trashAccounts': trashAccounts.map((item) => item.toJson()).toList(),
    'trashSubscriptions': trashSubscriptions
        .map((item) => item.toJson())
        .toList(),
    'accounts': accounts
        .map((account) => account.toEncryptedPayloadJson())
        .toList(growable: false),
    'subscriptions': subscriptions
        .map((subscription) => subscription.toEncryptedPayloadJson())
        .toList(growable: false),
    'subscriptionExpenses': subscriptionExpenses
        .map((expense) => expense.toEncryptedPayloadJson())
        .toList(growable: false),
    'pendingSubscriptionDrafts': pendingSubscriptionDrafts
        .map((draft) => draft.toEncryptedPayloadJson())
        .toList(growable: false),
    'preferences': preferences.toEncryptedPayloadJson(),
    'recentAccountIds': recentAccountIds,
  };

  static void _validateSnapshot({
    required int nextAccountId,
    required List<AccountRecord> accounts,
    List<PaymentMethodRecord> paymentMethods = const [],
    List<PasswordHealthIgnoreRule> passwordHealthIgnoreRules = const [],
    List<BindingRetirementPlan> bindingRetirementPlans = const [],
    List<TrashAccount> trashAccounts = const [],
    List<TrashSubscription> trashSubscriptions = const [],
    required int nextSubscriptionId,
    required List<SubscriptionRecord> subscriptions,
    required int nextExpenseId,
    required List<SubscriptionExpenseRecord> subscriptionExpenses,
    required List<PendingSubscriptionDraft> pendingSubscriptionDrafts,
    required VaultPreferences preferences,
    required List<String> recentAccountIds,
  }) {
    if (nextAccountId < 1 ||
        nextAccountId > 1000000000 ||
        nextSubscriptionId < 1 ||
        nextSubscriptionId > 1000000000 ||
        nextExpenseId < 1 ||
        nextExpenseId > 1000000000 ||
        accounts.length + trashAccounts.length > 10000 ||
        subscriptions.length + trashSubscriptions.length > 50000 ||
        subscriptionExpenses.length > maximumConfirmedSubscriptionExpenses ||
        pendingSubscriptionDrafts.length > 50000) {
      throw const VaultFormatException();
    }
    final allAccounts = [
      ...accounts,
      ...trashAccounts.map((item) => item.record),
    ];
    final allSubscriptions = [
      ...subscriptions,
      ...trashSubscriptions.map((item) => item.record),
    ];
    final allPendingDrafts = [
      ...pendingSubscriptionDrafts,
      ...trashAccounts.expand((item) => item.pendingDrafts),
    ];
    if (allPendingDrafts.length > 50000) throw const VaultFormatException();
    final activeAccountIds = accounts.map((account) => account.id).toSet();
    final accountIds = allAccounts.map((account) => account.id).toSet();
    final subscriptionIds = allSubscriptions
        .map((subscription) => subscription.id)
        .toSet();
    final pendingDraftIds = allPendingDrafts
        .map((draft) => draft.draftId)
        .toSet();
    final expenseIds = subscriptionExpenses
        .map((expense) => expense.id)
        .toSet();
    final generatedExpenseNumbers = subscriptionExpenses
        .map(
          (expense) =>
              RegExp(r'^expense-(\d+)$').firstMatch(expense.id)?.group(1),
        )
        .whereType<String>()
        .map(int.parse);
    final recentIdSet = recentAccountIds.toSet();
    if (accountIds.length != allAccounts.length ||
        subscriptionIds.length != allSubscriptions.length ||
        pendingDraftIds.length != allPendingDrafts.length ||
        expenseIds.length != subscriptionExpenses.length ||
        generatedExpenseNumbers.any((number) => number >= nextExpenseId) ||
        recentAccountIds.length > 10 ||
        recentIdSet.length != recentAccountIds.length ||
        recentAccountIds.any((id) => !activeAccountIds.contains(id)) ||
        subscriptions.any(
          (subscription) =>
              subscription.accountId != null &&
              !activeAccountIds.contains(subscription.accountId),
        ) ||
        allSubscriptions.any(
          (sub) => sub.accountId != null && !accountIds.contains(sub.accountId),
        ) ||
        subscriptionExpenses.any(
          (expense) =>
              (expense.subscriptionId != null &&
                  !subscriptionIds.contains(expense.subscriptionId)) ||
              (expense.accountId != null &&
                  !accountIds.contains(expense.accountId)),
        ) ||
        pendingSubscriptionDrafts.any(
          (draft) => !activeAccountIds.contains(draft.accountId),
        )) {
      throw const VaultFormatException();
    }
    final methodIds = paymentMethods.map((p) => p.id).toSet();
    if (paymentMethods.length > 10000 ||
        methodIds.length != paymentMethods.length ||
        allSubscriptions.any(
          (s) =>
              s.management?.paymentMethodId != null &&
              !methodIds.contains(s.management!.paymentMethodId),
        )) {
      throw const VaultFormatException();
    }
    final activePlanKeys = bindingRetirementPlans
        .where((plan) => !plan.isClosed)
        .map((plan) => '${plan.type.name}:${plan.normalizedValue}')
        .toList();
    if (passwordHealthIgnoreRules.length > 100000 ||
        passwordHealthIgnoreRules.map((rule) => rule.key).toSet().length !=
            passwordHealthIgnoreRules.length ||
        passwordHealthIgnoreRules.any(
          (rule) =>
              !accountIds.contains(rule.accountId) ||
              rule.memberRevisions.keys.any((id) => !accountIds.contains(id)),
        ) ||
        bindingRetirementPlans.length > 10000 ||
        bindingRetirementPlans.map((plan) => plan.id).toSet().length !=
            bindingRetirementPlans.length ||
        activePlanKeys.toSet().length != activePlanKeys.length ||
        bindingRetirementPlans.any(
          (plan) =>
              plan.accountIds.isEmpty ||
              plan.accountIds.any((id) => !accountIds.contains(id)),
        )) {
      throw const VaultFormatException();
    }
    preferences.validate();
  }
}

final class VaultPreferences {
  const VaultPreferences({
    this.autoLockSeconds = 0,
    this.defaultReminderDaysBefore = 7,
    this.defaultReminderTimeMinutes = 12 * 60 + 30,
    this.secondReminderTimeMinutes = 17 * 60,
    this.defaultCurrency = 'CNY',
    this.notificationsEnabled = false,
    this.passwordReviewNotificationsEnabled = false,
    this.accountDisplayMode = RecordDisplayMode.expandedCards,
    this.subscriptionDisplayMode = RecordDisplayMode.expandedCards,
    this.accountSortMode = RecordSortMode.oldestAdded,
    this.subscriptionSortMode = RecordSortMode.renewalSoonest,
  });

  factory VaultPreferences.fromEncryptedPayloadJson(
    Object? value, {
    bool allowPasswordReviewNotifications = false,
    bool requireSecondReminderTime = false,
  }) {
    if (value is! Map<Object?, Object?>) {
      throw const VaultFormatException();
    }
    final autoLockSeconds = value['autoLockSeconds'];
    final defaultReminderDaysBefore = value['defaultReminderDaysBefore'];
    final defaultReminderTimeMinutes = value['defaultReminderTimeMinutes'];
    // Preserve the saved first time when upgrading an older vault.
    final secondReminderTimeMinutes =
        !requireSecondReminderTime &&
            !value.containsKey('secondReminderTimeMinutes')
        ? 17 * 60
        : value['secondReminderTimeMinutes'];
    final defaultCurrency = value['defaultCurrency'];
    final notificationsEnabled = value['notificationsEnabled'];
    final rawPasswordReviewNotificationsEnabled =
        value['passwordReviewNotificationsEnabled'];
    final passwordReviewNotificationsEnabled = allowPasswordReviewNotifications
        ? rawPasswordReviewNotificationsEnabled
        : false;
    final rawAccountDisplayMode = value['accountDisplayMode'];
    final rawSubscriptionDisplayMode = value['subscriptionDisplayMode'];
    final accountDisplayMode = rawAccountDisplayMode == null
        ? RecordDisplayMode.expandedCards
        : recordDisplayModeFromStorage(rawAccountDisplayMode);
    final subscriptionDisplayMode = rawSubscriptionDisplayMode == null
        ? RecordDisplayMode.expandedCards
        : recordDisplayModeFromStorage(rawSubscriptionDisplayMode);
    final rawAccountSortMode = value['accountSortMode'];
    final rawSubscriptionSortMode = value['subscriptionSortMode'];
    final accountSortMode = rawAccountSortMode == null
        ? RecordSortMode.oldestAdded
        : recordSortModeFromStorage(rawAccountSortMode);
    final subscriptionSortMode = rawSubscriptionSortMode == null
        ? RecordSortMode.renewalSoonest
        : recordSortModeFromStorage(rawSubscriptionSortMode);
    if (autoLockSeconds is! int ||
        defaultReminderDaysBefore is! int ||
        defaultReminderTimeMinutes is! int ||
        secondReminderTimeMinutes is! int ||
        defaultCurrency is! String ||
        notificationsEnabled is! bool ||
        passwordReviewNotificationsEnabled is! bool ||
        accountDisplayMode == null ||
        subscriptionDisplayMode == null ||
        accountSortMode == null ||
        subscriptionSortMode == null) {
      throw const VaultFormatException();
    }
    final result = VaultPreferences(
      autoLockSeconds: autoLockSeconds,
      defaultReminderDaysBefore: defaultReminderDaysBefore,
      defaultReminderTimeMinutes: defaultReminderTimeMinutes,
      secondReminderTimeMinutes: secondReminderTimeMinutes,
      defaultCurrency: defaultCurrency,
      notificationsEnabled: notificationsEnabled,
      passwordReviewNotificationsEnabled: passwordReviewNotificationsEnabled,
      accountDisplayMode: accountDisplayMode,
      subscriptionDisplayMode: subscriptionDisplayMode,
      accountSortMode: accountSortMode,
      subscriptionSortMode: subscriptionSortMode,
    );
    result.validate();
    return result;
  }

  final int autoLockSeconds;
  final int defaultReminderDaysBefore;
  final int defaultReminderTimeMinutes;
  final int secondReminderTimeMinutes;
  final String defaultCurrency;
  final bool notificationsEnabled;
  final bool passwordReviewNotificationsEnabled;
  final RecordDisplayMode accountDisplayMode;
  final RecordDisplayMode subscriptionDisplayMode;
  final RecordSortMode accountSortMode;
  final RecordSortMode subscriptionSortMode;

  VaultPreferences copyWith({
    int? autoLockSeconds,
    int? defaultReminderDaysBefore,
    int? defaultReminderTimeMinutes,
    int? secondReminderTimeMinutes,
    String? defaultCurrency,
    bool? notificationsEnabled,
    bool? passwordReviewNotificationsEnabled,
    RecordDisplayMode? accountDisplayMode,
    RecordDisplayMode? subscriptionDisplayMode,
    RecordSortMode? accountSortMode,
    RecordSortMode? subscriptionSortMode,
  }) => VaultPreferences(
    autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
    defaultReminderDaysBefore:
        defaultReminderDaysBefore ?? this.defaultReminderDaysBefore,
    defaultReminderTimeMinutes:
        defaultReminderTimeMinutes ?? this.defaultReminderTimeMinutes,
    secondReminderTimeMinutes:
        secondReminderTimeMinutes ?? this.secondReminderTimeMinutes,
    defaultCurrency: defaultCurrency ?? this.defaultCurrency,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    passwordReviewNotificationsEnabled:
        passwordReviewNotificationsEnabled ??
        this.passwordReviewNotificationsEnabled,
    accountDisplayMode: accountDisplayMode ?? this.accountDisplayMode,
    subscriptionDisplayMode:
        subscriptionDisplayMode ?? this.subscriptionDisplayMode,
    accountSortMode: accountSortMode ?? this.accountSortMode,
    subscriptionSortMode: subscriptionSortMode ?? this.subscriptionSortMode,
  );

  void validate() {
    const allowedAutoLockSeconds = <int>{0, 30, 60, 300, 900};
    final currencyPattern = RegExp(r'^[A-Z]{3}$');
    if (!allowedAutoLockSeconds.contains(autoLockSeconds) ||
        defaultReminderDaysBefore < 0 ||
        defaultReminderDaysBefore > 365 ||
        defaultReminderTimeMinutes < 0 ||
        defaultReminderTimeMinutes > 1439 ||
        secondReminderTimeMinutes < 0 ||
        secondReminderTimeMinutes > 1439 ||
        !currencyPattern.hasMatch(defaultCurrency)) {
      throw const VaultFormatException();
    }
  }

  Map<String, Object?> toEncryptedPayloadJson() => <String, Object?>{
    'autoLockSeconds': autoLockSeconds,
    'defaultReminderDaysBefore': defaultReminderDaysBefore,
    'defaultReminderTimeMinutes': defaultReminderTimeMinutes,
    'secondReminderTimeMinutes': secondReminderTimeMinutes,
    'defaultCurrency': defaultCurrency,
    'notificationsEnabled': notificationsEnabled,
    'passwordReviewNotificationsEnabled': passwordReviewNotificationsEnabled,
    'accountDisplayMode': accountDisplayMode.storageValue,
    'subscriptionDisplayMode': subscriptionDisplayMode.storageValue,
    'accountSortMode': accountSortMode.storageValue,
    'subscriptionSortMode': subscriptionSortMode.storageValue,
  };
}

sealed class VaultException implements Exception {
  const VaultException();
}

enum QuickUnlockFailureReason {
  userCanceled,
  timeout,
  temporaryLockout,
  biometricLockout,
  hardwareUnavailable,
  unavailable,
  notEnrolled,
  securityUpdateRequired,
  unsupported,
  statusUnknown,
  systemCanceled,
  lifecycleCanceled,
  uiUnavailable,
  activityUnavailable,
  promptStartFailed,
  authInProgress,
  keySetupFailed,
  keyInvalidated,
  keyMissing,
  corruptedSecret,
  notConfigured,
  storageError,
  cryptoError,
  unknown,
}

extension QuickUnlockFailureReasonPolicy on QuickUnlockFailureReason {
  bool get invalidatesConfiguration => switch (this) {
    QuickUnlockFailureReason.keyInvalidated ||
    QuickUnlockFailureReason.keyMissing ||
    QuickUnlockFailureReason.corruptedSecret ||
    QuickUnlockFailureReason.notConfigured => true,
    _ => false,
  };
}

final class QuickUnlockException extends VaultException {
  const QuickUnlockException(
    this.reason, {
    this.platformCode,
    this.diagnosticStage,
    this.diagnosticType,
  });

  final QuickUnlockFailureReason reason;
  final String? platformCode;
  final String? diagnosticStage;
  final String? diagnosticType;
}

final class VaultAlreadyExistsException extends VaultException {
  const VaultAlreadyExistsException();
}

final class VaultNotFoundException extends VaultException {
  const VaultNotFoundException();
}

base class VaultUnlockException extends VaultException {
  const VaultUnlockException();
}

/// 当前输入无法认证任何允许的保险库凭据。
///
/// 密码错误与“包装后的数据密钥被篡改”在密码学上无法区分，
/// 因此调用方只能将它视为一次凭据认证失败，不得回显更多细节。
final class VaultCredentialRejectedException extends VaultUnlockException {
  const VaultCredentialRejectedException();
}

/// 密码已能解开数据密钥，但业务密文的认证或解析失败。
///
/// 该错误不应计入密码尝试次数，也不应导向诱饵库。
final class VaultIntegrityException extends VaultUnlockException {
  const VaultIntegrityException();
}

final class VaultPasswordUnchangedException extends VaultException {
  const VaultPasswordUnchangedException();
}

base class VaultFormatException extends VaultException {
  const VaultFormatException();
}

/// KDF 参数本身合法，但不在当前版本明确允许的 profile 中。
///
/// 该异常必须与普通格式损坏区分：旧版本不得回退到上一代密文后
/// 继续写入，否则可能覆盖由未来 KDF profile 保护的最新数据。
final class VaultUnsupportedKdfProfileException extends VaultFormatException {
  const VaultUnsupportedKdfProfileException();
}

final class VaultUnsupportedEnvelopeVersionException extends VaultException {
  const VaultUnsupportedEnvelopeVersionException(this.version);

  final int version;
}

final class VaultUnsupportedSchemaVersionException extends VaultException {
  const VaultUnsupportedSchemaVersionException(this.version);

  final int version;
}

final class VaultStorageException extends VaultException {
  const VaultStorageException();
}

final class VaultBatchRollbackUnavailableException extends VaultException {
  const VaultBatchRollbackUnavailableException();
}

/// 主库已经提交、但安全辅助副本未能同步。
final class VaultCompanionSyncException extends VaultException {
  const VaultCompanionSyncException();
}

final class DecoyVaultAlreadyConfiguredException extends VaultException {
  const DecoyVaultAlreadyConfiguredException();
}

final class DecoyPasswordConflictException extends VaultException {
  const DecoyPasswordConflictException();
}

/// 当前保险库没有可用的本机密码恢复配置。
final class VaultRecoveryNotConfiguredException extends VaultException {
  const VaultRecoveryNotConfiguredException();
}

/// 三个密保答案、设备绑定或恢复密文无法共同认证。
///
/// 调用方不得区分具体是哪一道问题、哪个绑定字段或哪个认证标签失败。
final class VaultRecoveryRejectedException extends VaultUnlockException {
  const VaultRecoveryRejectedException();
}

/// 已启用密码恢复时，主密码轮换必须先刷新恢复双因子或明确关闭恢复。
final class VaultRecoveryRefreshRequiredException extends VaultException {
  const VaultRecoveryRefreshRequiredException();
}

final class VaultRecoveryQuestionSetConflictException extends VaultException {
  const VaultRecoveryQuestionSetConflictException();
}

final class VaultClosedException extends VaultException {
  const VaultClosedException();
}
