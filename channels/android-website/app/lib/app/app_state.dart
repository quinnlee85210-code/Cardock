import '../features/subscriptions/domain/subscription_cost_summary.dart';
import '../core/calendar/calendar_reminder.dart';
import '../core/platform/calendar_bridge.dart';
import '../core/preferences/language_preferences.dart';
import '../core/preferences/notification_privacy_preferences.dart';
import '../features/accounts/domain/account_analysis.dart';
import '../core/security/account_comparison.dart';
import '../core/data_import/custom_field_companion.dart';
import '../core/security/subscription_metadata_migration.dart';
import '../features/subscriptions/domain/subscription_management_actions.dart'
    as management_actions;
import 'dart:async';
import '../core/security/vault_trash.dart';

import '../core/security/editor_draft.dart';
import '../core/security/device_backup_config.dart';
import '../core/storage/auto_backup_controller.dart';
import '../core/storage/readable_export.dart';
import '../core/storage/vault_rebuild_service.dart';
import '../core/storage/document_storage.dart';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/entitlements/entitlement_guard.dart';
import '../core/entitlements/entitlement_model.dart';
import '../core/data_import/data_import.dart' hide parseSubscriptionDate;
import '../core/security/offline_password_advisor.dart';
import '../core/security/recovery_device_secret.dart';
import '../core/security/unlock_throttle.dart';
import '../core/security/vault_contract.dart';
import '../core/security/vault_recovery.dart';
import '../core/notifications/reminder_scheduler.dart';
import '../core/notifications/notification_reconciliation_state.dart';
import '../core/platform/notification_reliability.dart';
import '../core/platform/screen_protection.dart';
import '../core/storage/backup_health_store.dart';
import '../core/storage/layered_vault_store.dart';
import '../core/storage/portable_backup_codec.dart';
import '../core/storage/vault_recovery_journal.dart';
import '../features/accounts/domain/account_record.dart';
import '../features/subscriptions/domain/subscription_record.dart';
import '../features/subscriptions/domain/pending_subscription_draft.dart';
import '../features/subscriptions/domain/subscription_expense_record.dart';
import '../features/subscriptions/domain/subscription_expense_automation.dart';

enum VaultPhase { initializing, needsSetup, locked, unlocked, error }

enum VaultActionResult { success, rejected, failed }

enum NotificationSettingResult {
  enabled,
  disabled,
  applicationNotificationsDisabled,
  reminderChannelDisabled,
  permissionCheckFailed,
  saveFailed,
  initializationFailed,
  scheduleFailed,
  cancelFailed,
  rejected,
}

enum NotificationTestResult {
  immediateAndScheduled,
  immediateSent,
  scheduled,
  notificationsDisabled,
  applicationNotificationsDisabled,
  reminderChannelDisabled,
  permissionCheckFailed,
  initializationFailed,
  immediateFailed,
  scheduleFailed,
  rejected,
}

enum RecordCreationStatus {
  saved,
  unavailable,
  limitReached,
  failed,
  duplicateConfirmationRequired,
}

final class RecordCreationResult {
  const RecordCreationResult._({
    required this.status,
    this.limit,
    this.duplicates = const [],
    this.expectedRevision,
  });

  const RecordCreationResult.duplicateConfirmationRequired(
    List<AccountDuplicateCandidate> duplicates,
    int revision,
  ) : this._(
        status: RecordCreationStatus.duplicateConfirmationRequired,
        duplicates: duplicates,
        expectedRevision: revision,
      );

  final List<AccountDuplicateCandidate> duplicates;
  final int? expectedRevision;

  const RecordCreationResult.saved()
    : this._(status: RecordCreationStatus.saved);

  const RecordCreationResult.unavailable()
    : this._(status: RecordCreationStatus.unavailable);

  const RecordCreationResult.limitReached(EntitlementLimitDecision limit)
    : this._(status: RecordCreationStatus.limitReached, limit: limit);

  const RecordCreationResult.failed()
    : this._(status: RecordCreationStatus.failed);

  final RecordCreationStatus status;
  final EntitlementLimitDecision? limit;

  bool get saved => status == RecordCreationStatus.saved;
}

final class EncryptedBackupPreview {
  const EncryptedBackupPreview({
    required this.accountCount,
    required this.subscriptionCount,
    required this.formatVersion,
    required this.sourceSchemaVersion,
    this.backupId,
    this.createdAtUtc,
  });

  final int accountCount;
  final int subscriptionCount;
  final int formatVersion;
  final int sourceSchemaVersion;
  final String? backupId;
  final DateTime? createdAtUtc;
}

final class BatchRollbackImpact {
  const BatchRollbackImpact({
    required this.addedAccountCount,
    required this.updatedAccountCount,
    required this.formalSubscriptionCount,
    required this.pendingSubscriptionDraftCount,
  });

  final int addedAccountCount;
  final int updatedAccountCount;
  final int formalSubscriptionCount;
  final int pendingSubscriptionDraftCount;

  int get affectedRecordCount =>
      addedAccountCount +
      updatedAccountCount +
      formalSubscriptionCount +
      pendingSubscriptionDraftCount;
}

final class AccountBatchImpact {
  const AccountBatchImpact(
    this.accountCount,
    this.subscriptionCount,
    this.pendingDraftCount,
  );
  final int accountCount, subscriptionCount, pendingDraftCount;
}

final class AppState extends ChangeNotifier {
  AppState({
    VaultStore? vaultStore,
    DateTime Function()? now,
    ReminderScheduler? reminderScheduler,
    NotificationPrivacyStore? notificationPrivacyStore,
    PortableBackupCodec? backupCodec,
    AutoBackupController? autoBackupController,
    VaultRebuildService? rebuildService,
    VaultRecoveryJournal? recoveryJournal,
    BackupHealthStore? backupHealthStore,
    NotificationReliabilityService? notificationReliabilityService,
    ScreenProtectionService? screenProtectionService,
    ValueListenable<ProductEntitlement>? entitlementListenable,
    UnlockThrottleController? unlockThrottleController,
  }) : _now = now ?? DateTime.now,
       _vaultStore = vaultStore ?? LayeredVaultStore.appSupport(),
       _unlockThrottleController =
           unlockThrottleController ??
           (vaultStore == null
               ? UnlockThrottleController.appSupport()
               : UnlockThrottleController.memory()),
       _notificationPrivacyStore =
           notificationPrivacyStore ??
           (vaultStore == null
               ? FileNotificationPrivacyStore.appSupport()
               : MemoryNotificationPrivacyStore()),
       _reminderScheduler = reminderScheduler ?? const NoopReminderScheduler(),
       _backupCodec = backupCodec ?? PortableBackupCodec(),
       _rebuildService =
           rebuildService ??
           (vaultStore == null
               ? VaultRebuildService.appSupport(
                   reminderScheduler ?? const NoopReminderScheduler(),
                 )
               : null),
       _notificationReliabilityService =
           notificationReliabilityService ??
           MemoryNotificationReliabilityService(),
       _screenProtectionService =
           screenProtectionService ?? MemoryScreenProtectionService(),
       _entitlementListenable =
           entitlementListenable ?? const _FreeEntitlementListenable(),
       _recoveryJournal =
           recoveryJournal ??
           (vaultStore == null
               ? FileVaultRecoveryJournal.appSupport()
               : const NoopVaultRecoveryJournal()),
       _backupHealthStore =
           backupHealthStore ??
           (vaultStore == null
               ? FileBackupHealthStore.appSupport()
               : const NoopBackupHealthStore()),
       autoBackup =
           autoBackupController ??
           AutoBackupController(codec: backupCodec, now: now) {
    autoBackup.addListener(_notify);
  }

  List<PasswordHealthIgnoreRule> _passwordHealthIgnoreRules = [];
  List<BindingRetirementPlan> _bindingRetirementPlans = [];
  AccountAnalysisSnapshot? _accountAnalysis;
  String? _accountAnalysisKey;
  List<PasswordHealthIgnoreRule> get passwordHealthIgnoreRules =>
      isUnlocked && hasFullVaultAccess
      ? List.unmodifiable(_passwordHealthIgnoreRules)
      : const [];
  List<BindingRetirementPlan> get bindingRetirementPlans =>
      isUnlocked && hasFullVaultAccess
      ? List.unmodifiable(_bindingRetirementPlans)
      : const [];
  AccountAnalysisSnapshot get accountAnalysis {
    if (!isUnlocked || !hasFullVaultAccess || _session == null) {
      return AccountAnalysisSnapshot.empty();
    }
    final now = _now();
    final utcNow = now.toUtc();
    final key =
        '$localWebRevision:${AccountComparison.catalogRevision}:${now.year}-${now.month}-${now.day}:${now.timeZoneOffset.inMinutes}';
    final previous = _accountAnalysis;
    final expired =
        previous?.nextRefreshAtUtc != null &&
        !utcNow.isBefore(previous!.nextRefreshAtUtc!);
    final clockMovedBack =
        previous?.computedAtUtc != null &&
        utcNow.isBefore(previous!.computedAtUtc!);
    if (previous == null ||
        key != _accountAnalysisKey ||
        expired ||
        clockMovedBack) {
      _invalidateAccountAnalysis();
      _accountAnalysis = AccountAnalysisSnapshot.fromSnapshot(
        _snapshot(),
        now: now,
      );
      _accountAnalysisKey = key;
    }
    return _accountAnalysis!;
  }

  void _invalidateAccountAnalysis() {
    _accountAnalysis?.dispose();
    _accountAnalysis = null;
    _accountAnalysisKey = null;
  }

  List<AccountDuplicateCandidate> findAccountDuplicates(
    AccountDraft draft, {
    String? excludeAccountId,
  }) =>
      accountAnalysis.duplicatesFor(draft, excludeAccountId: excludeAccountId);

  bool _backupWarningDismissed = false;
  void dismissBackupWarning() {
    _backupWarningDismissed = true;
    _notify();
  }

  String? get backupWarning {
    if (!isUnlocked ||
        !hasFullVaultAccess ||
        !_canManageSecurity ||
        _backupWarningDismissed ||
        (_accounts.isEmpty &&
            _subscriptions.isEmpty &&
            _subscriptionExpenses.isEmpty &&
            _trashAccounts.isEmpty &&
            _trashSubscriptions.isEmpty &&
            _pendingSubscriptionDrafts.isEmpty)) {
      return null;
    }
    final status = autoBackup.status;
    if (status.enabled && status.permission == false) {
      return '备份目录权限失效，请到数据安全与备份重新授权。';
    }
    if (status.failures >= 2) return '自动备份连续失败，请到数据安全与备份检查。';
    if (status.enabled) {
      if (status.cleanupPending) return '旧自动备份清理未完成，请到数据安全与备份检查。';
      if (status.validCount == 0) return '没有可用的自动备份，请到数据安全与备份检查。';
      final due = status.nextDueAt;
      if (due != null &&
          _now().toUtc().difference(due) >= const Duration(days: 1)) {
        return '自动备份已超过计划时间，请到数据安全与备份检查。';
      }
      return null;
    }
    final verified = [lastBackupVerifiedAtUtc, status.lastVerified]
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    if (verified == null) return '尚无已验证的加密备份，建议到数据安全与备份准备。';
    if (_now().toUtc().difference(verified) > const Duration(days: 7)) {
      return '超过 7 天未验证备份，建议检查备份可用性。';
    }
    return null;
  }

  static String _similarName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  bool hasSimilarTrashAccount(String name) =>
      isUnlocked &&
      hasFullVaultAccess &&
      name.trim().isNotEmpty &&
      _trashAccounts.any(
        (item) => _similarName(item.record.platformName) == _similarName(name),
      );
  bool hasSimilarTrashSubscription(String name) =>
      isUnlocked &&
      hasFullVaultAccess &&
      name.trim().isNotEmpty &&
      _trashSubscriptions.any(
        (item) =>
            _similarName(item.record.serviceName) == _similarName(name) ||
            (item.record.planName != null &&
                _similarName(item.record.planName!) == _similarName(name)),
      );
  final AutoBackupController autoBackup;
  final VaultRebuildService? _rebuildService;
  final VaultStore _vaultStore;
  final DateTime Function() _now;
  final List<TrashAccount> _trashAccounts = [];
  final List<TrashSubscription> _trashSubscriptions = [];
  bool _trashCleanupPending = false;
  List<TrashAccount> get trashAccounts => List.unmodifiable(_trashAccounts);
  List<TrashSubscription> get trashSubscriptions =>
      List.unmodifiable(_trashSubscriptions);
  final UnlockThrottleController _unlockThrottleController;
  final ReminderScheduler _reminderScheduler;
  bool _pendingReminderOpen = false;
  void _requestReminderOpen() {
    _pendingReminderOpen = true;
    _notify();
  }

  bool consumeReminderOpenRequest() {
    if (!isUnlocked || isBusy || !_pendingReminderOpen) return false;
    _pendingReminderOpen = false;
    return true;
  }

  final NotificationPrivacyStore _notificationPrivacyStore;
  NotificationPrivacy _notificationPrivacy = NotificationPrivacy.privacy;
  NotificationPrivacy get notificationPrivacy => _notificationPrivacy;
  bool get canChangeNotificationPrivacy =>
      isUnlocked && hasFullVaultAccess && canManageSecurity && !isBusy;

  Future<bool> setNotificationPrivacy(
    NotificationPrivacy value, {
    bool riskConfirmed = false,
  }) async {
    if (!canChangeNotificationPrivacy) return false;
    if (value == _notificationPrivacy) return true;
    if (value.index > _notificationPrivacy.index && !riskConfirmed) {
      return false;
    }
    final session = _session!;
    final epoch = _operationEpoch;
    _beginOperation(epoch);
    _notify();
    try {
      await _prepareNotificationReconciliation(
        session,
        targetGeneration: session.generation,
      );
      if (!_isCurrent(epoch) || !isUnlocked) return false;
      await _notificationPrivacyStore.write(value);
      _notificationPrivacy = value;
      if (_reminderScheduler
          case final PrivacyAwareReminderScheduler scheduler) {
        scheduler.updatePrivacy(value);
      }
      if (!_isCurrent(epoch) || !isUnlocked) return true;
      await _syncReminders(
        _snapshot(),
        previousNotificationsEnabled: true,
        preserveOtherNotifications: true,
      );
      return true;
    } on Object {
      if (_isCurrent(epoch)) _warningMessage = '通知隐私设置未完成，请重试；业务数据未改变。';
      return false;
    } finally {
      _finishOperation(epoch);
    }
  }

  final PortableBackupCodec _backupCodec;
  final VaultRecoveryJournal _recoveryJournal;
  final BackupHealthStore _backupHealthStore;
  final NotificationReliabilityService _notificationReliabilityService;
  final ScreenProtectionService _screenProtectionService;
  final ValueListenable<ProductEntitlement> _entitlementListenable;
  static const EntitlementGuard entitlementGuard = EntitlementGuard();
  final List<AccountRecord> _accounts = <AccountRecord>[];
  final List<SubscriptionRecord> _subscriptions = <SubscriptionRecord>[];
  final List<SubscriptionExpenseRecord> _subscriptionExpenses =
      <SubscriptionExpenseRecord>[];
  final List<PendingSubscriptionDraft> _pendingSubscriptionDrafts =
      <PendingSubscriptionDraft>[];
  final List<String> _recentAccountIds = <String>[];

  VaultSession? _session;
  VaultPhase _vaultPhase = VaultPhase.initializing;
  int _nextAccountId = 1;
  int _nextSubscriptionId = 1;
  int _nextExpenseId = 1;
  VaultPreferences _preferences = const VaultPreferences();
  int _externalInteractionDepth = 0;
  int _operationEpoch = 0;
  int _recoveryRefreshToken = 0;
  String? _handledSystemTimeRecoveryToken;
  bool _systemTimeRecoveryRefreshInProgress = false;
  int? _busyEpoch;
  bool _busy = false;
  bool _hasVault = false;
  bool _quickUnlockEnabled = false;
  bool _screenProtectionEnabled = true;
  QuickUnlockScope? _quickUnlockScope;
  VaultAccessLevel _accessLevel = VaultAccessLevel.full;
  bool _canManageSecurity = true;
  bool _decoyVaultConfigured = false;
  VaultRecoveryConfiguration _vaultRecoveryConfiguration =
      const VaultRecoveryConfiguration();
  VaultRecoveryState? _recoveryState;
  BackupHealthRecord _backupHealth = const BackupHealthRecord();
  QuickUnlockFailureReason? _quickUnlockFailureReason;
  bool _disposed = false;
  String? _errorMessage;
  String? _warningMessage;
  String? _importVaultScopeId;
  BatchRollbackImpact? _lastBatchRollbackImpact;
  UnlockThrottleSnapshot _unlockThrottle = const UnlockThrottleSnapshot.clear();
  bool _unlockThrottleAvailable = true;

  static const int maximumUnlockAttemptsPerRound =
      UnlockThrottlePolicy.maximumFailedAttempts;
  static const Duration unlockCooldown = UnlockThrottlePolicy.maximumCooldown;
  static const String _unlockThrottleUnavailableMessage =
      '无法验证本机安全计时状态；主密码输入已暂停，可继续使用已配置的生物识别。';

  UnmodifiableListView<AccountRecord> get accounts =>
      UnmodifiableListView<AccountRecord>(_accounts);

  UnmodifiableListView<SubscriptionRecord> get subscriptions =>
      UnmodifiableListView<SubscriptionRecord>(_subscriptions);

  UnmodifiableListView<SubscriptionExpenseRecord> get subscriptionExpenses =>
      UnmodifiableListView<SubscriptionExpenseRecord>(
        _subscriptionExpenses.where((expense) => !expense.isDeleted).toList(),
      );

  UnmodifiableListView<SubscriptionExpenseRecord>
  get subscriptionExpenseLedger =>
      UnmodifiableListView<SubscriptionExpenseRecord>(_subscriptionExpenses);

  UnmodifiableListView<PendingSubscriptionDraft>
  get pendingSubscriptionDrafts =>
      UnmodifiableListView<PendingSubscriptionDraft>(
        _pendingSubscriptionDrafts,
      );

  BatchRollbackAvailability get lastBatchRollbackAvailability {
    if (_session is! BatchRollbackVaultSession) {
      return BatchRollbackAvailability.none;
    }
    return (_session! as BatchRollbackVaultSession).batchRollbackAvailability;
  }

  bool get canUndoLastBatchImport =>
      _session is BatchRollbackVaultSession &&
      (_session! as BatchRollbackVaultSession).canUndoLastBatch;

  bool get hasLastBatchRollbackArtifact =>
      lastBatchRollbackAvailability != BatchRollbackAvailability.none;

  BatchRollbackImpact? get lastBatchRollbackImpact {
    if (!canUndoLastBatchImport) return null;
    final inMemory = _lastBatchRollbackImpact;
    if (inMemory != null) return inMemory;
    final summary =
        (_session! as BatchRollbackVaultSession).lastBatchRollbackSummary;
    if (summary == null) return null;
    return BatchRollbackImpact(
      addedAccountCount: summary.addedAccountCount,
      updatedAccountCount: summary.updatedAccountCount,
      formalSubscriptionCount: summary.formalSubscriptionCount,
      pendingSubscriptionDraftCount: summary.pendingSubscriptionDraftCount,
    );
  }

  static bool isFormalSubscriptionImportValid(
    SubscriptionImportDraft imported,
  ) {
    if (!imported.isSyntacticallyComplete) return false;
    try {
      _formalSubscriptionFromImport(
        imported,
        id: 'import-validation-subscription',
        account: AccountRecord.fromDraft(
          id: 'import-validation-account',
          draft: AccountDraft(platformName: 'import-validation-service'),
        ),
      );
      return true;
    } on ArgumentError {
      return false;
    } on FormatException {
      return false;
    }
  }

  VaultPhase get vaultPhase => _vaultPhase;
  bool get isBusy => _busy;
  bool get isUnlocked => _vaultPhase == VaultPhase.unlocked;
  bool get hasVault => _hasVault;
  bool get quickUnlockEnabled => _quickUnlockEnabled;
  bool get screenProtectionEnabled => _screenProtectionEnabled;
  QuickUnlockScope? get quickUnlockScope => _quickUnlockScope;
  bool get hasFullVaultAccess => _accessLevel == VaultAccessLevel.full;
  bool get hasSubscriptionOnlyAccess =>
      _accessLevel == VaultAccessLevel.subscriptionsOnly;
  bool get canManageSecurity => _canManageSecurity;
  bool get isEligibleForTemporaryWebSession =>
      isUnlocked &&
      hasFullVaultAccess &&
      canManageSecurity &&
      !_busy &&
      _session != null;
  int get localWebRevision => _session?.generation ?? -1;
  String? get temporaryWebVaultBindingId {
    final session = _session;
    if (!isEligibleForTemporaryWebSession || session is! VaultBoundSession) {
      return null;
    }
    return session.vaultBindingId;
  }

  /// Bound to the authenticated vault and access level, not its display data.
  String? get navigationVaultScope {
    final session = _session;
    if (!isUnlocked || session is! VaultBoundSession) return null;
    return '${session.vaultBindingId}:${_accessLevel.name}:$_canManageSecurity';
  }

  String? get subscriptionQueryScope => _importVaultScopeId;

  String? get importVaultScopeId =>
      _hasWritableSession && _canManageSecurity ? _importVaultScopeId : null;
  bool get decoyVaultConfigured => _decoyVaultConfigured;
  VaultRecoveryConfiguration get vaultRecoveryConfiguration =>
      _vaultRecoveryConfiguration;
  VaultRecoveryChallenge? get primaryRecoveryChallenge =>
      _vaultRecoveryConfiguration.primaryChallenge;
  VaultRecoveryChallenge? get decoyRecoveryChallenge =>
      _vaultRecoveryConfiguration.decoyChallenge;
  VaultRecoveryChallenge? get vaultRecoveryChallenge =>
      primaryRecoveryChallenge;
  bool get primaryRecoveryConfigured => primaryRecoveryChallenge != null;
  bool get decoyRecoveryConfigured => decoyRecoveryChallenge != null;
  // 兼容旧调用：recoveryConfigured 仍只表示真实库恢复配置。
  bool get recoveryConfigured => primaryRecoveryConfigured;
  bool get anyRecoveryConfigured => _vaultRecoveryConfiguration.anyConfigured;
  VaultRecoveryChallenge? recoveryChallengeFor(VaultRecoveryScope scope) =>
      _vaultRecoveryConfiguration.challengeFor(scope);
  List<List<String>> recoveryQuestionSetsForEntryMode(
    VaultRecoveryEntryMode mode,
  ) {
    final questionSets = <List<String>>[
      if (primaryRecoveryChallenge?.entryMode == mode)
        List<String>.unmodifiable(primaryRecoveryChallenge!.questionIds),
      if (decoyRecoveryChallenge?.entryMode == mode)
        List<String>.unmodifiable(decoyRecoveryChallenge!.questionIds),
    ];
    questionSets.sort(
      (first, second) => first.join('\u0000').compareTo(second.join('\u0000')),
    );
    return List<List<String>>.unmodifiable(questionSets);
  }

  bool hasRecoveryEntryMode(VaultRecoveryEntryMode mode) =>
      primaryRecoveryChallenge?.entryMode == mode ||
      decoyRecoveryChallenge?.entryMode == mode;
  bool get hasRecoveryRollback =>
      _recoveryState == VaultRecoveryState.committed ||
      _recoveryState == VaultRecoveryState.prepared;
  bool get hasUncertainRecoveryTransaction =>
      _recoveryState == VaultRecoveryState.prepared;
  DateTime? get lastBackupExportedAtUtc =>
      _canManageSecurity ? _backupHealth.lastExportedAtUtc : null;
  DateTime? get lastBackupVerifiedAtUtc =>
      _canManageSecurity ? _backupHealth.lastVerifiedAtUtc : null;
  int? get lastVerifiedBackupFormatVersion =>
      _backupHealth.lastVerifiedFormatVersion;
  QuickUnlockFailureReason? get quickUnlockFailureReason =>
      _quickUnlockFailureReason;
  String? get errorMessage => _errorMessage;
  String? get warningMessage => _warningMessage;

  Future<Map<String, Object?>?> readEditorDraft() async {
    final session = _session;
    if (!isUnlocked ||
        !hasFullVaultAccess ||
        session is! EditorDraftVaultSession) {
      return null;
    }
    try {
      final draft = await session.readEditorDraft();
      return identical(session, _session) && isUnlocked ? draft : null;
    } on Object {
      if (identical(session, _session) && isUnlocked) {
        _warningMessage = '未完成表单暂时无法读取，已保存的记录不受影响。';
        notifyListeners();
      }
      return null;
    }
  }

  Future<void> Function(Map<String, Object?>?) editorDraftWriter() {
    final session = _session;
    return (draft) async {
      if (!identical(session, _session) ||
          !isUnlocked ||
          !hasFullVaultAccess ||
          session is! EditorDraftVaultSession) {
        return;
      }
      try {
        await session.writeEditorDraft(draft);
      } on Object {
        if (identical(session, _session) && isUnlocked) {
          _warningMessage = '未完成表单暂时无法加密保存，请保持此页面并重试。';
          notifyListeners();
        }
      }
    };
  }

  VaultPreferences get preferences => _preferences;
  ProductEntitlement get productEntitlement => _entitlementListenable.value;
  EntitlementLimitDecision get accountCreationDecision =>
      entitlementGuard.accountCreation(
        entitlement: productEntitlement,
        currentAccounts: _accounts.length,
      );
  EntitlementLimitDecision get subscriptionCreationDecision =>
      entitlementGuard.subscriptionCreation(
        entitlement: productEntitlement,
        currentSubscriptions: _subscriptions.length,
      );
  bool get externalInteractionInProgress => _externalInteractionDepth > 0;
  int get autoLockSeconds => _preferences.autoLockSeconds;
  Duration get unlockCooldownRemaining => _unlockThrottle.cooldownRemaining;

  int get failedUnlockAttempts => _unlockThrottle.failedAttempts;

  bool get passwordUnlockBlocked =>
      !_unlockThrottleAvailable || _unlockThrottle.isBlocked;

  int get unlockAttemptsRemaining => _unlockThrottle.attemptsRemaining;

  bool get _hasWritableSession =>
      _vaultPhase == VaultPhase.unlocked &&
      _session != null &&
      _accessLevel == VaultAccessLevel.full &&
      !_busy;

  UnmodifiableListView<AccountRecord> get recentAccounts {
    final byId = <String, AccountRecord>{
      for (final account in _accounts) account.id: account,
    };
    return UnmodifiableListView<AccountRecord>(
      _recentAccountIds.map((id) => byId[id]).whereType<AccountRecord>(),
    );
  }

  Future<void> refreshUnlockThrottle() async {
    if (_vaultPhase != VaultPhase.locked || _disposed) return;
    final previous = _unlockThrottle;
    final wasAvailable = _unlockThrottleAvailable;
    try {
      _unlockThrottle = _unlockThrottleAvailable
          ? await _unlockThrottleController.refresh()
          : await _unlockThrottleController.initialize();
      _unlockThrottleAvailable = true;
      if (_errorMessage == _unlockThrottleUnavailableMessage) {
        _errorMessage = null;
      }
    } on Object {
      _unlockThrottleAvailable = false;
      _errorMessage = _unlockThrottleUnavailableMessage;
    }
    if (previous != _unlockThrottle ||
        wasAvailable != _unlockThrottleAvailable ||
        !_unlockThrottleAvailable) {
      _notify();
    }
  }

  Future<void> initialize() async {
    final epoch = ++_operationEpoch;
    _beginOperation(epoch);
    _vaultPhase = VaultPhase.initializing;
    _errorMessage = null;
    _warningMessage = null;
    _quickUnlockFailureReason = null;
    _notify();

    try {
      try {
        _unlockThrottle = await _unlockThrottleController.initialize();
        _unlockThrottleAvailable = true;
      } on Object {
        _unlockThrottle = const UnlockThrottleSnapshot.clear();
        _unlockThrottleAvailable = false;
      }
      // Android has already applied the default-on flag before Flutter's first
      // frame. Reading here only synchronizes the settings UI with the
      // non-sensitive native preference.
      try {
        _screenProtectionEnabled = await _screenProtectionService.readEnabled();
      } on Object {
        _screenProtectionEnabled = true;
      }
      await _rebuildService?.resumeIfNeeded();
      _notificationPrivacy = await _notificationPrivacyStore.read();
      if (_reminderScheduler
          case final PrivacyAwareReminderScheduler scheduler) {
        scheduler.updatePrivacy(_notificationPrivacy);
      }
      if (_reminderScheduler case final LocalReminderScheduler scheduler) {
        try {
          await scheduler.prepareNavigation(_requestReminderOpen);
        } on Object {
          /* Retried on unlock. */
        }
      }
      final exists = await _vaultStore.exists();
      if (!_isCurrent(epoch)) {
        return;
      }
      _hasVault = exists;
      _quickUnlockEnabled = exists
          ? await _vaultStore.isQuickUnlockEnabled()
          : false;
      final securityController = _vaultStore is LayeredVaultSecurityController
          ? _vaultStore as LayeredVaultSecurityController
          : null;
      _quickUnlockScope = _quickUnlockEnabled
          ? await securityController?.configuredQuickUnlockScope() ??
                QuickUnlockScope.fullVault
          : null;
      _decoyVaultConfigured = exists
          ? await securityController?.isDecoyVaultConfigured() ?? false
          : false;
      if (exists && securityController != null) {
        try {
          _vaultRecoveryConfiguration = await securityController
              .recoveryConfiguration();
        } on Object {
          // Recovery metadata is optional. A corrupt or conflicting recovery
          // configuration must not block normal primary-password access.
          _vaultRecoveryConfiguration = const VaultRecoveryConfiguration();
        }
      } else {
        _vaultRecoveryConfiguration = const VaultRecoveryConfiguration();
      }
      try {
        _backupHealth = await _backupHealthStore.read();
      } on Object {
        _backupHealth = const BackupHealthRecord();
      }
      if (!_isCurrent(epoch)) {
        return;
      }
      _vaultPhase = exists ? VaultPhase.locked : VaultPhase.needsSetup;
      if (exists && !_unlockThrottleAvailable) {
        _errorMessage = _unlockThrottleUnavailableMessage;
      }
    } on Object {
      if (_isCurrent(epoch)) {
        _vaultPhase = VaultPhase.error;
        _errorMessage = '无法访问本机加密存储。';
      }
    } finally {
      _finishOperation(epoch);
    }
  }

  Future<bool> setScreenProtectionEnabled(bool enabled) async {
    if (_screenProtectionEnabled == enabled) return true;
    try {
      await _screenProtectionService.setEnabled(enabled);
      _screenProtectionEnabled = enabled;
      _notify();
      return true;
    } on Object {
      return false;
    }
  }

  Future<VaultActionResult> createVault(String masterPassword) async {
    if (_vaultPhase != VaultPhase.needsSetup || _busy) {
      return VaultActionResult.rejected;
    }

    final assessment = OfflinePasswordAdvisor.assess(masterPassword);
    if (!assessment.accepted) {
      _errorMessage = assessment.message;
      _notify();
      return VaultActionResult.rejected;
    }

    final epoch = ++_operationEpoch;
    _beginOperation(epoch);
    _errorMessage = null;
    _warningMessage = null;
    _notify();
    VaultOpenResult? openResult;

    try {
      openResult = await _vaultStore.create(masterPassword: masterPassword);
      _hasVault = true;
      if (!_isCurrent(epoch)) {
        openResult.session.close();
        if (_ownsOperation(epoch)) {
          _hasVault = true;
          _vaultPhase = VaultPhase.locked;
          _errorMessage = null;
        }
        return VaultActionResult.rejected;
      }
      _applyOpenResult(openResult);
      return VaultActionResult.success;
    } on VaultAlreadyExistsException {
      if (_isCurrent(epoch)) {
        _hasVault = true;
        _vaultPhase = VaultPhase.locked;
        _errorMessage = '本机已存在加密库，请使用主密码解锁。';
      }
      return VaultActionResult.rejected;
    } on ArgumentError {
      if (_isCurrent(epoch)) {
        _errorMessage = '主密码长度必须为12到128个字符。';
      }
      return VaultActionResult.rejected;
    } on Object {
      if (_isCurrent(epoch)) {
        _errorMessage = '无法创建本机加密库，请稍后重试。';
      }
      return VaultActionResult.failed;
    } finally {
      _finishOperation(epoch);
    }
  }

  Future<VaultOpenResult> _upgradeLegacyOpenResult(
    VaultOpenResult result,
  ) async {
    final session = result.session;
    if (!result.snapshot.requiresSchemaUpgrade ||
        (session is ScopedVaultSession &&
            session.accessLevel != VaultAccessLevel.full)) {
      return result;
    }
    final upgraded = result.snapshot.copyWith(requiresSchemaUpgrade: false);
    try {
      // One authenticated atomic save, never a sequence of per-record writes.
      // No new payment is inferred and no backup retention setting is changed.
      await session.save(upgraded);
    } on Object {
      session.close();
      rethrow;
    }
    return VaultOpenResult(
      session: session,
      snapshot: upgraded,
      recoveredFromFallback: result.recoveredFromFallback,
    );
  }

  Future<VaultActionResult> unlock(String masterPassword) async {
    if (_vaultPhase != VaultPhase.locked || _busy) {
      return VaultActionResult.rejected;
    }
    await refreshUnlockThrottle();
    if (_vaultPhase != VaultPhase.locked || _busy) {
      return VaultActionResult.rejected;
    }
    if (!_unlockThrottleAvailable) {
      _errorMessage = _unlockThrottleUnavailableMessage;
      _notify();
      return VaultActionResult.failed;
    }
    final cooldownRemaining = unlockCooldownRemaining;
    if (cooldownRemaining > Duration.zero) {
      _errorMessage =
          '主密码输入正在冷却，请等待${_formatUnlockCooldown(cooldownRemaining)}后继续尝试；'
          '本机数据不会清空、锁死或删除。';
      _notify();
      return VaultActionResult.rejected;
    }

    final epoch = ++_operationEpoch;
    _beginOperation(epoch);
    _errorMessage = null;
    _warningMessage = null;
    _notify();
    VaultOpenResult? openResult;

    try {
      openResult = await _vaultStore.unlock(masterPassword: masterPassword);
      if (!_isCurrent(epoch)) {
        openResult.session.close();
        return VaultActionResult.rejected;
      }
      await _refreshQuickUnlockConfiguration();
      if (!_isCurrent(epoch)) {
        openResult.session.close();
        return VaultActionResult.rejected;
      }
      final primaryPasswordAccepted =
          openResult.session is! ScopedVaultSession ||
          (openResult.session as ScopedVaultSession).canManageSecurity;
      var throttleReset = true;
      if (primaryPasswordAccepted) {
        throttleReset = await _resetUnlockFailures();
        if (!_isCurrent(epoch)) {
          openResult.session.close();
          return VaultActionResult.rejected;
        }
      }
      openResult = await _upgradeLegacyOpenResult(openResult);
      if (!_isCurrent(epoch)) {
        openResult.session.close();
        return VaultActionResult.rejected;
      }
      _applyOpenResult(openResult);
      if (!throttleReset) {
        _warningMessage = '主密码已验证，但安全计数状态暂时无法持久化；重新锁定后请优先使用生物识别。';
      }
      return VaultActionResult.success;
    } on VaultIntegrityException {
      if (_isCurrent(epoch)) {
        _errorMessage = '加密数据完整性验证失败；本次不计入密码错误次数。';
      }
      return VaultActionResult.rejected;
    } on VaultUnlockException {
      final recorded = await _recordUnlockFailure(
        reportError: _isCurrent(epoch),
      );
      return recorded ? VaultActionResult.rejected : VaultActionResult.failed;
    } on VaultUnsupportedEnvelopeVersionException {
      if (_isCurrent(epoch)) {
        _errorMessage = '该加密库由更高版本应用创建；为防止数据降级覆盖，本版本已停止打开。';
      }
      return VaultActionResult.rejected;
    } on VaultUnsupportedSchemaVersionException {
      if (_isCurrent(epoch)) {
        _errorMessage = '该数据由更高版本应用写入；为防止数据降级覆盖，本版本已停止打开。';
      }
      return VaultActionResult.rejected;
    } on VaultUnsupportedKdfProfileException {
      if (_isCurrent(epoch)) {
        _errorMessage = '该加密库使用本版本不支持的密钥派生参数；为防止降级覆盖，本版本已停止打开。';
      }
      return VaultActionResult.rejected;
    } on VaultFormatException {
      if (_isCurrent(epoch)) {
        _errorMessage = '加密数据格式或完整性验证失败；本次不计入密码错误次数。';
      }
      return VaultActionResult.rejected;
    } on Object {
      if (_isCurrent(epoch)) {
        _errorMessage = '无法读取本机加密库。';
      }
      return VaultActionResult.failed;
    } finally {
      _finishOperation(epoch);
    }
  }

  Future<bool> _recordUnlockFailure({required bool reportError}) async {
    try {
      _unlockThrottle = await _unlockThrottleController
          .recordCredentialFailure();
      _unlockThrottleAvailable = true;
      if (reportError) {
        final cooldown = _unlockThrottle.cooldownRemaining;
        _errorMessage = cooldown > Duration.zero
            ? '主密码已连续输错${_unlockThrottle.failedAttempts}次，请等待'
                  '${_formatUnlockCooldown(cooldown)}后继续尝试；本机数据不会清空、锁死或删除。'
            : '主密码不正确，本轮还可尝试${_unlockThrottle.attemptsRemaining}次；'
                  '连续输错5次后将开始30秒冷却，本机数据不会被删除。';
      }
      return true;
    } on Object {
      _unlockThrottleAvailable = false;
      if (reportError) {
        _errorMessage = _unlockThrottleUnavailableMessage;
      }
      return false;
    }
  }

  Future<bool> _resetUnlockFailures() async {
    try {
      _unlockThrottle = await _unlockThrottleController
          .clearAfterPrimaryAuthentication();
      _unlockThrottleAvailable = true;
      return true;
    } on Object {
      _unlockThrottleAvailable = false;
      return false;
    }
  }

  static String _formatUnlockCooldown(Duration duration) {
    final seconds = (duration.inMilliseconds / 1000).ceil().clamp(1, 1800);
    if (seconds < 60) return '$seconds秒';
    return '${(seconds / 60).ceil()}分钟';
  }

  Future<bool> addAccount(
    AccountDraft draft, {
    SubscriptionDetailsDraft? initialSubscription,
    int? duplicateApprovedRevision,
  }) async => (await createAccount(
    draft,
    initialSubscription: initialSubscription,
    duplicateApprovedRevision: duplicateApprovedRevision,
  )).saved;

  Future<RecordCreationResult> createAccount(
    AccountDraft draft, {
    SubscriptionDetailsDraft? initialSubscription,
    int? duplicateApprovedRevision,
  }) async {
    if (!_hasWritableSession) {
      return const RecordCreationResult.unavailable();
    }
    final duplicates = findAccountDuplicates(draft);
    if (duplicates.isNotEmpty &&
        duplicateApprovedRevision != localWebRevision) {
      return RecordCreationResult.duplicateConfirmationRequired(
        duplicates,
        localWebRevision,
      );
    }
    final accountLimit = accountCreationDecision;
    if (!accountLimit.allowed) {
      return RecordCreationResult.limitReached(accountLimit);
    }
    if (initialSubscription != null) {
      final subscriptionLimit = subscriptionCreationDecision;
      if (!subscriptionLimit.allowed) {
        return RecordCreationResult.limitReached(subscriptionLimit);
      }
    }

    try {
      final now = DateTime.now().toUtc();
      final account = AccountRecord.fromDraft(
        id: 'account-$_nextAccountId',
        draft: draft,
        passwordStoredAtUtc: draft.password == null ? null : now,
        passwordSyncState: draft.password == null
            ? PasswordSyncState.unknown
            : PasswordSyncState.needsReview,
      );
      final nextAccounts = <AccountRecord>[..._accounts, account];
      final nextSubscriptions = <SubscriptionRecord>[..._subscriptions];
      var nextSubscriptionId = _nextSubscriptionId;
      if (initialSubscription != null) {
        nextSubscriptions.add(
          SubscriptionRecord.fromDraft(
            id: 'subscription-$nextSubscriptionId',
            draft: SubscriptionDraft(
              accountId: account.id,
              details: initialSubscription.withExpenseCategory(
                account.category,
              ),
            ),
          ),
        );
        nextSubscriptionId += 1;
      }

      final saved = await _persistSnapshot(
        _snapshot(
          nextAccountId: _nextAccountId + 1,
          accounts: nextAccounts,
          nextSubscriptionId: nextSubscriptionId,
          subscriptions: nextSubscriptions,
        ),
        failureMessage: '账号及订阅记录未能写入本机加密库。',
      );
      return saved
          ? const RecordCreationResult.saved()
          : const RecordCreationResult.failed();
    } on ArgumentError {
      _setContentError('账号或订阅内容无效，请检查后重试。');
      return const RecordCreationResult.failed();
    } on VaultFormatException {
      _setContentError('账号或订阅内容无效，请检查后重试。');
      return const RecordCreationResult.failed();
    }
  }

  Future<bool> addSubscription(SubscriptionDraft draft) async =>
      (await createSubscription(draft)).saved;

  Future<RecordCreationResult> createSubscription(
    SubscriptionDraft draft,
  ) async {
    if (!_hasWritableSession) {
      return const RecordCreationResult.unavailable();
    }
    final subscriptionLimit = subscriptionCreationDecision;
    if (!subscriptionLimit.allowed) {
      return RecordCreationResult.limitReached(subscriptionLimit);
    }
    if (draft.accountId != null &&
        !_accounts.any((account) => account.id == draft.accountId)) {
      _setContentError('关联账号不存在，订阅记录未保存。');
      return const RecordCreationResult.failed();
    }

    try {
      final linkedAccount = draft.accountId == null
          ? null
          : _accounts.firstWhere((account) => account.id == draft.accountId);
      final subscription = SubscriptionRecord.fromDraft(
        id: 'subscription-$_nextSubscriptionId',
        draft: SubscriptionDraft(
          accountId: draft.accountId,
          details: draft.details.withExpenseCategory(linkedAccount?.category),
        ),
      );
      final saved = await _persistSnapshot(
        _snapshot(
          nextSubscriptionId: _nextSubscriptionId + 1,
          subscriptions: <SubscriptionRecord>[..._subscriptions, subscription],
        ),
        failureMessage: '订阅记录未能写入本机加密库。',
      );
      return saved
          ? const RecordCreationResult.saved()
          : const RecordCreationResult.failed();
    } on ArgumentError {
      _setContentError('订阅内容无效，请检查后重试。');
      return const RecordCreationResult.failed();
    } on VaultFormatException {
      _setContentError('订阅内容无效，请检查后重试。');
      return const RecordCreationResult.failed();
    }
  }

  Future<bool> saveSharedTextPendingSubscriptionDraft({
    required String accountId,
    String? planName,
    String? amount,
    String? currency,
    int? billingCycleCount,
    SubscriptionCycleUnit? billingCycleUnit,
    DateTime? nextRenewalDate,
    bool? autoRenew,
  }) async {
    final session = _session;
    if (!_hasWritableSession ||
        session == null ||
        !_accounts.any((account) => account.id == accountId)) {
      _setContentError('请选择当前保险库中的已有账号；分享草稿未保存。');
      return false;
    }
    if ((billingCycleCount == null) != (billingCycleUnit == null)) {
      _setContentError('计费周期数量和单位必须同时填写或同时留空。');
      return false;
    }
    try {
      final now = DateTime.now().toUtc();
      final draft = PendingSubscriptionDraft(
        draftId:
            'pending-${session.generation}-${now.microsecondsSinceEpoch}-0',
        accountId: accountId,
        planName: planName,
        amount: amount,
        currency: currency,
        billingCycle: billingCycleCount == null
            ? null
            : PendingSubscriptionBillingCycle(
                count: billingCycleCount,
                unit: billingCycleUnit!,
              ),
        nextRenewalDate: nextRenewalDate,
        autoRenew: autoRenew,
        createdAt: now,
        updatedAt: now,
      );
      return _persistSnapshot(
        _snapshot(
          pendingSubscriptionDrafts: <PendingSubscriptionDraft>[
            ..._pendingSubscriptionDrafts,
            draft,
          ],
        ),
        failureMessage: '待完善订阅草稿未能写入当前本机加密库。',
      );
    } on ArgumentError {
      _setContentError('分享中的订阅字段无效；原文未保存。');
      return false;
    } on VaultFormatException {
      _setContentError('分享中的订阅字段无效；原文未保存。');
      return false;
    }
  }

  Future<RecordCreationResult> completePendingSubscriptionDraft({
    required String draftId,
    required SubscriptionDetailsDraft details,
  }) async {
    if (!_hasWritableSession) {
      return const RecordCreationResult.unavailable();
    }
    final draftIndex = _pendingSubscriptionDrafts.indexWhere(
      (draft) => draft.draftId == draftId,
    );
    if (draftIndex < 0) return const RecordCreationResult.failed();
    final limit = subscriptionCreationDecision;
    if (!limit.allowed) return RecordCreationResult.limitReached(limit);
    final pending = _pendingSubscriptionDrafts[draftIndex];
    if (!_accounts.any((account) => account.id == pending.accountId)) {
      _setContentError('待完善订阅的关联账号不存在。');
      return const RecordCreationResult.failed();
    }
    if (details.planName == null ||
        details.planName!.trim().isEmpty ||
        details.amount == null ||
        details.amount!.trim().isEmpty ||
        !RegExp(
          r'^[A-Z]{3}$',
        ).hasMatch(details.currency.trim().toUpperCase()) ||
        details.paymentMethod == null ||
        details.paymentMethod!.trim().isEmpty) {
      _setContentError('订阅内容仍不完整或无效；原草稿已保留。');
      return const RecordCreationResult.failed();
    }
    try {
      // 先运行现有正式订阅验证器；只有构造成功后才创建“移除草稿”的快照。
      final formal = SubscriptionRecord.fromDraft(
        id: 'subscription-$_nextSubscriptionId',
        draft: SubscriptionDraft(
          accountId: pending.accountId,
          // AppState 只使用调用方已经明确构造的正式字段；不从缺失草稿猜测
          // 周期、提醒天数或自动续订。导入备注在现有 UI 尚不可编辑时仍须保留。
          details: details
              .withFallbackNotes(pending.notes)
              .withExpenseCategory(
                _accounts
                    .firstWhere((account) => account.id == pending.accountId)
                    .category,
              ),
        ),
      );
      final saved = await _persistSnapshot(
        _snapshot(
          nextSubscriptionId: _nextSubscriptionId + 1,
          subscriptions: <SubscriptionRecord>[..._subscriptions, formal],
          pendingSubscriptionDrafts: _pendingSubscriptionDrafts
              .where((draft) => draft.draftId != draftId)
              .toList(growable: false),
        ),
        failureMessage: '待完善订阅未能写入正式订阅；原草稿已保留。',
      );
      return saved
          ? const RecordCreationResult.saved()
          : const RecordCreationResult.failed();
    } on ArgumentError {
      _setContentError('订阅内容仍不完整或无效；原草稿已保留。');
      return const RecordCreationResult.failed();
    } on VaultFormatException {
      _setContentError('订阅内容仍不完整或无效；原草稿已保留。');
      return const RecordCreationResult.failed();
    }
  }

  Future<bool> updateSubscription({
    required String subscriptionId,
    required SubscriptionDraft draft,
  }) async {
    if (!_hasWritableSession) {
      return false;
    }
    final index = _subscriptions.indexWhere(
      (subscription) => subscription.id == subscriptionId,
    );
    if (index < 0 ||
        (draft.accountId != null &&
            !_accounts.any((account) => account.id == draft.accountId))) {
      _setContentError('订阅记录或关联账号不存在。');
      return false;
    }

    try {
      final oldTrial = _subscriptions[index].management?.trial;
      final newTrial = draft.details.management?.trial;
      if (oldTrial != null &&
          newTrial != null &&
          oldTrial.outcome != newTrial.outcome) {
        _setContentError('试用状态已变化，请重新打开记录。');
        return false;
      }
      final nextSubscriptions = <SubscriptionRecord>[..._subscriptions];
      nextSubscriptions[index] = _subscriptions[index].applyDraft(draft);
      return _persistSnapshot(
        _snapshot(subscriptions: nextSubscriptions),
        failureMessage: '订阅修改未能写入本机加密库。',
      );
    } on ArgumentError {
      _setContentError('订阅内容无效，请检查后重试。');
      return false;
    } on VaultFormatException {
      _setContentError('订阅内容无效，请检查后重试。');
      return false;
    }
  }

  Future<bool> deleteSubscription(String subscriptionId) =>
      _moveToTrash(subscriptionId: subscriptionId);

  Future<bool> recordSubscriptionExpense(SubscriptionExpenseDraft draft) async {
    if (!_hasWritableSession) return false;
    if (_subscriptionExpenses.length >= maximumConfirmedSubscriptionExpenses) {
      _setContentError('已确认订阅费用记录已达到本机安全上限。');
      return false;
    }
    if (draft.subscriptionId != null &&
        !_subscriptions.any(
          (subscription) => subscription.id == draft.subscriptionId,
        )) {
      _setContentError('关联订阅不存在，费用记录未保存。');
      return false;
    }
    try {
      final subscription = _subscriptions
          .where((sub) => sub.id == draft.subscriptionId)
          .firstOrNull;
      final accountId = subscription?.accountId ?? draft.accountId;
      if (draft.accountId != null &&
          subscription != null &&
          draft.accountId != subscription.accountId) {
        _setContentError('订阅与关联账号不一致。');
        return false;
      }
      final account = _accounts
          .where((account) => account.id == accountId)
          .firstOrNull;
      if (accountId != null && account == null) {
        _setContentError('关联账号不存在。');
        return false;
      }
      final expense =
          SubscriptionExpenseRecord.fromDraft(
                id: 'expense-$_nextExpenseId',
                draft: draft,
              )
              .withPaymentMethod(
                id:
                    draft.paymentMethodId ??
                    subscription?.management?.paymentMethodId,
                name: draft.paymentMethodName ?? subscription?.paymentMethod,
              )
              .withAccountContext(
                accountId: accountId,
                accountLabel: account == null
                    ? null
                    : subscriptionExpenseAccountLabel(account),
              );
      return _persistSnapshot(
        _snapshot(
          nextExpenseId: _nextExpenseId + 1,
          subscriptionExpenses: <SubscriptionExpenseRecord>[
            ..._subscriptionExpenses,
            expense,
          ],
        ),
        failureMessage: '订阅费用记录未能写入本机加密库。',
      );
    } on ArgumentError {
      _setContentError('费用内容无效，请检查后重试。');
      return false;
    }
  }

  /// Correct a displayed ledger row or save an override for an inferred period.
  /// Keeping a deleted billing identity prevents automatic historical refill.
  Future<bool> correctSubscriptionCost(
    SubscriptionCostLine line,
    SubscriptionExpenseDraft? correction,
  ) async {
    if (!_hasWritableSession || line.basis != SubscriptionCostBasis.confirmed) {
      return false;
    }
    final expenses = [..._subscriptionExpenses];
    final index = expenses.indexWhere((e) => e.id == line.expenseId);
    try {
      if (line.expenseId != null) {
        if (index < 0 || expenses[index].isDeleted) return false;
        final current = expenses[index];
        if (current.amount != line.amount ||
            current.currency != line.currency ||
            current.occurredOn != line.date) {
          return false;
        }
        expenses[index] = current.corrected(
          correction ?? current.draft,
          deleted: correction == null,
        );
      } else {
        final current =
            SubscriptionCostAnalysis.build(
                  subscriptions: _subscriptions,
                  accounts: _accounts,
                  expenses: expenses,
                  range: SubscriptionCostRange(
                    startMonth: line.date,
                    endMonth: line.date,
                  ),
                  today: _now(),
                )
                .forBasis(SubscriptionCostBasis.confirmed)
                .where(
                  (candidate) =>
                      candidate.fromSchedule &&
                      candidate.subscriptionId == line.subscriptionId &&
                      candidate.scheduledOn == line.scheduledOn &&
                      candidate.date == line.date &&
                      candidate.amount == line.amount &&
                      candidate.currency == line.currency,
                )
                .firstOrNull;
        if (current == null ||
            expenses.length >= maximumConfirmedSubscriptionExpenses) {
          return false;
        }
        final sub = _subscriptions
            .where((s) => s.id == current.subscriptionId)
            .firstOrNull;
        if (sub == null) return false;
        final draft =
            correction ??
            SubscriptionExpenseDraft(
              subscriptionId: sub.id,
              serviceName: current.serviceName,
              occurredOn: current.date,
              amount: current.amount ?? '0',
              currency: current.currency,
              kind: SubscriptionExpenseKind.payment,
              expenseCategory: current.expenseCategory,
            );
        final original = SubscriptionExpenseRecord.fromDraft(
          id: 'expense-$_nextExpenseId',
          draft: SubscriptionExpenseDraft(
            subscriptionId: sub.id,
            accountId: sub.accountId,
            serviceName: current.serviceName,
            occurredOn: current.date,
            amount: current.amount ?? '0',
            currency: current.currency,
            kind: SubscriptionExpenseKind.payment,
            expenseCategory: current.expenseCategory,
            scheduledRenewalOn: current.scheduledOn,
            paymentMethodId: sub.management?.paymentMethodId,
            paymentMethodName: sub.paymentMethod,
          ),
          accountLabel: current.accountLabel,
          source: current.scheduledOn == sub.firstSubscribedOn
              ? SubscriptionExpenseSource.subscriptionEntry
              : SubscriptionExpenseSource.renewal,
        );
        expenses.add(original.corrected(draft, deleted: correction == null));
      }
      return _persistSnapshot(
        _snapshot(
          subscriptionExpenses: expenses,
          nextExpenseId: line.expenseId == null
              ? _nextExpenseId + 1
              : _nextExpenseId,
        ),
        failureMessage: '订阅费用记录未能写入本机加密库。',
      );
    } on Object {
      _setContentError('费用内容无效，请检查后重试。');
      return false;
    }
  }

  Future<bool> deleteSubscriptionExpense(String expenseId) async {
    if (!_hasWritableSession) return false;
    if (!_subscriptionExpenses.any((expense) => expense.id == expenseId)) {
      _setContentError('费用记录不存在。');
      return false;
    }
    return _persistSnapshot(
      _snapshot(
        subscriptionExpenses: [
          for (final expense in _subscriptionExpenses)
            expense.id == expenseId
                ? expense.corrected(expense.draft, deleted: true)
                : expense,
        ],
      ),
      failureMessage: '订阅费用记录未能删除。',
    );
  }

  Future<bool> markSubscriptionRenewed(
    SubscriptionRecord subscription, {
    SubscriptionExpenseDraft? expense,
  }) async {
    if (!_hasWritableSession) return false;
    final index = _subscriptions.indexWhere(
      (current) => current.id == subscription.id,
    );
    if (index < 0) {
      _setContentError('订阅记录不存在。');
      return false;
    }
    if (expense != null &&
        _subscriptionExpenses.length >= maximumConfirmedSubscriptionExpenses) {
      _setContentError('已确认订阅费用记录已达到本机安全上限。');
      return false;
    }
    try {
      final current = _subscriptions[index];
      if (current.isUnresolvedTrial) {
        _setContentError('请先在详情确认试用结果。');
        return false;
      }
      final nextSubscriptions = <SubscriptionRecord>[..._subscriptions];
      if (current.nextRenewalOn != subscription.nextRenewalOn ||
          current.renewalHistory.length != subscription.renewalHistory.length) {
        _setContentError('订阅已变化，请重新打开记录。');
        return false;
      }
      nextSubscriptions[index] = current.markRenewed(recordedOn: _now());
      if (expense == null) {
        return _persistSnapshot(
          _snapshot(subscriptions: nextSubscriptions),
          failureMessage: '续费日期未能写入本机加密库。',
        );
      }
      if (expense.kind != SubscriptionExpenseKind.payment) {
        _setContentError('续费必须记录为支付。');
        return false;
      }
      final account = _accounts
          .where((account) => account.id == current.accountId)
          .firstOrNull;
      final alreadyPaid = _subscriptionExpenses.any(
        (entry) =>
            entry.kind == SubscriptionExpenseKind.payment &&
            entry.subscriptionId == current.id &&
            entry.scheduledRenewalOn == current.nextRenewalOn,
      );
      if (alreadyPaid) {
        return _persistSnapshot(
          _snapshot(subscriptions: nextSubscriptions),
          failureMessage: '续费日期未能写入本机加密库。',
        );
      }
      final normalizedExpense = SubscriptionExpenseRecord.fromDraft(
        source: SubscriptionExpenseSource.renewal,
        accountLabel: account == null
            ? null
            : subscriptionExpenseAccountLabel(account),
        id: 'expense-$_nextExpenseId',
        draft: SubscriptionExpenseDraft(
          subscriptionId: current.id,
          accountId: current.accountId,
          serviceName: current.serviceName,
          occurredOn: expense.occurredOn,
          amount: expense.amount,
          currency: expense.currency,
          kind: expense.kind,
          expenseCategory: expense.expenseCategory ?? current.expenseCategory,
          scheduledRenewalOn: current.nextRenewalOn,
        ),
      );
      return _persistSnapshot(
        _snapshot(
          subscriptions: nextSubscriptions,
          nextExpenseId: _nextExpenseId + 1,
          subscriptionExpenses: <SubscriptionExpenseRecord>[
            ..._subscriptionExpenses,
            normalizedExpense,
          ],
        ),
        failureMessage: '续费日期和确认费用未能写入本机加密库。',
      );
    } on Object {
      _setContentError('续费信息无效，请检查后重试。');
      return false;
    }
  }

  Future<bool> snoozeSubscriptionReminder(
    SubscriptionRecord subscription,
    SubscriptionSnoozeTarget target,
  ) => _replaceSubscription(
    subscription.id,
    (current) => current.snoozeReminder(target),
    failureMessage: '延后提醒未能写入本机加密库。',
  );

  Future<bool> cancelSubscription(
    SubscriptionRecord subscription, {
    DateTime? accessEndsOn,
  }) => _replaceSubscription(
    subscription.id,
    (current) => current.cancel(accessEndsOn: accessEndsOn),
    failureMessage: '取消状态未能写入本机加密库。',
  );

  Future<bool> restoreSubscription(SubscriptionRecord subscription) =>
      _replaceSubscription(
        subscription.id,
        (current) => current.restore(),
        failureMessage: '订阅恢复状态未能写入本机加密库。',
      );

  Future<bool> _replaceSubscription(
    String subscriptionId,
    SubscriptionRecord Function(SubscriptionRecord current) transform, {
    required String failureMessage,
  }) async {
    if (!_hasWritableSession) {
      return false;
    }
    final index = _subscriptions.indexWhere(
      (subscription) => subscription.id == subscriptionId,
    );
    if (index < 0) {
      _setContentError('订阅记录不存在。');
      return false;
    }
    try {
      final nextSubscriptions = <SubscriptionRecord>[..._subscriptions];
      nextSubscriptions[index] = transform(_subscriptions[index]);
      return _persistSnapshot(
        _snapshot(subscriptions: nextSubscriptions),
        failureMessage: failureMessage,
      );
    } on Object {
      _setContentError('订阅操作无效，请检查记录状态。');
      return false;
    }
  }

  Future<bool> updateAccount({
    required String accountId,
    required AccountDraft draft,
    required AccountPasswordUpdateMode passwordMode,
  }) async {
    if (!_hasWritableSession) {
      return false;
    }
    final index = _accounts.indexWhere((account) => account.id == accountId);
    if (index < 0) {
      _setContentError('账号记录不存在。');
      return false;
    }
    final existing = _accounts[index];
    final password = switch (passwordMode) {
      AccountPasswordUpdateMode.preserve => existing.password,
      AccountPasswordUpdateMode.replace => draft.password,
      AccountPasswordUpdateMode.clear => null,
    };
    if (passwordMode == AccountPasswordUpdateMode.replace && password == null) {
      _setContentError('请输入要替换的新密码。');
      return false;
    }
    try {
      final normalizedDraft = AccountDraft(
        platformName: draft.platformName,
        category: draft.category,
        loginAccount: draft.loginAccount,
        username: draft.username,
        boundPhone: draft.boundPhone,
        boundEmail: draft.boundEmail,
        password: password,
        website: draft.website,
        notes: draft.notes,
        customFields: draft.customFields,
      );
      final nextAccounts = <AccountRecord>[..._accounts];
      final passwordChanged =
          passwordMode == AccountPasswordUpdateMode.replace &&
          password != existing.password;
      final passwordCleared = passwordMode == AccountPasswordUpdateMode.clear;
      final now = DateTime.now().toUtc();
      nextAccounts[index] = AccountRecord.fromDraft(
        id: accountId,
        draft: normalizedDraft,
        passwordValueRevision: existing.revisionAfterPasswordSave(password),
        passwordChangeHistory: existing.historyAfterPasswordSave(password, now),
        passwordStoredAtUtc: passwordCleared
            ? null
            : passwordChanged
            ? now
            : existing.passwordStoredAtUtc,
        passwordSyncState: passwordCleared
            ? PasswordSyncState.unknown
            : passwordChanged
            ? PasswordSyncState.needsReview
            : existing.passwordSyncState,
        passwordVerifiedAtUtc: passwordCleared
            ? null
            : existing.passwordVerifiedAtUtc,
        platformPasswordChangedAtUtc: passwordCleared
            ? null
            : existing.platformPasswordChangedAtUtc,
        passwordReviewIntervalDays: passwordCleared
            ? null
            : existing.passwordReviewIntervalDays,
        passwordReviewSnoozedUntilUtc: passwordCleared || passwordChanged
            ? null
            : existing.passwordReviewSnoozedUntilUtc,
      );
      return _persistSnapshot(
        _snapshot(accounts: nextAccounts),
        failureMessage: '账号修改未能写入本机加密库。',
      );
    } on ArgumentError {
      _setContentError('账号内容无效，请检查后重试。');
      return false;
    }
  }

  Future<bool> confirmPasswordCurrent(String accountId) => _replaceAccount(
    accountId,
    (account) => _accountWithPasswordReview(
      account,
      passwordStoredAtUtc: account.passwordStoredAtUtc,
      passwordSyncState: PasswordSyncState.verified,
      passwordVerifiedAtUtc: DateTime.now().toUtc(),
      platformPasswordChangedAtUtc: account.platformPasswordChangedAtUtc,
      passwordReviewIntervalDays: account.passwordReviewIntervalDays,
      passwordReviewSnoozedUntilUtc: null,
    ),
    failureMessage: '密码核对状态未能写入本机加密库。',
  );

  Future<bool> markPasswordNeedsReview(String accountId) => _replaceAccount(
    accountId,
    (account) => _accountWithPasswordReview(
      account,
      passwordStoredAtUtc: account.passwordStoredAtUtc,
      passwordSyncState: PasswordSyncState.needsReview,
      passwordVerifiedAtUtc: account.passwordVerifiedAtUtc,
      platformPasswordChangedAtUtc: account.platformPasswordChangedAtUtc,
      passwordReviewIntervalDays: account.passwordReviewIntervalDays,
      passwordReviewSnoozedUntilUtc: null,
    ),
    failureMessage: '密码核对状态未能写入本机加密库。',
  );

  Future<bool> markPlatformPasswordChanged(String accountId) => _replaceAccount(
    accountId,
    (account) => _accountWithPasswordReview(
      account,
      passwordStoredAtUtc: account.passwordStoredAtUtc,
      passwordSyncState: PasswordSyncState.externalChangePendingSync,
      passwordVerifiedAtUtc: account.passwordVerifiedAtUtc,
      platformPasswordChangedAtUtc: DateTime.now().toUtc(),
      passwordReviewIntervalDays: account.passwordReviewIntervalDays,
      passwordReviewSnoozedUntilUtc: null,
    ),
    failureMessage: '平台改密状态未能写入本机加密库。',
  );

  Future<bool> setPasswordReviewInterval(String accountId, int? intervalDays) =>
      _replaceAccount(
        accountId,
        (account) => _accountWithPasswordReview(
          account,
          passwordStoredAtUtc: account.passwordStoredAtUtc,
          passwordSyncState: account.passwordSyncState,
          passwordVerifiedAtUtc: account.passwordVerifiedAtUtc,
          platformPasswordChangedAtUtc: account.platformPasswordChangedAtUtc,
          passwordReviewIntervalDays: intervalDays,
          passwordReviewSnoozedUntilUtc: intervalDays == null
              ? null
              : account.passwordReviewSnoozedUntilUtc,
        ),
        failureMessage: '密码复核周期未能写入本机加密库。',
      );

  Future<bool> snoozePasswordReview(String accountId, int days) {
    if (days != 7 && days != 30) {
      _setContentError('密码复核稍后提醒天数无效。');
      return Future<bool>.value(false);
    }
    return _replaceAccount(
      accountId,
      (account) => _accountWithPasswordReview(
        account,
        passwordStoredAtUtc: account.passwordStoredAtUtc,
        passwordSyncState: account.passwordSyncState,
        passwordVerifiedAtUtc: account.passwordVerifiedAtUtc,
        platformPasswordChangedAtUtc: account.platformPasswordChangedAtUtc,
        passwordReviewIntervalDays: account.passwordReviewIntervalDays,
        passwordReviewSnoozedUntilUtc: DateTime.now().toUtc().add(
          Duration(days: days),
        ),
      ),
      failureMessage: '密码复核稍后提醒未能写入本机加密库。',
    );
  }

  Future<bool> _replaceAccount(
    String accountId,
    AccountRecord Function(AccountRecord current) transform, {
    required String failureMessage,
  }) async {
    if (!_hasWritableSession) return false;
    final index = _accounts.indexWhere((account) => account.id == accountId);
    if (index < 0) {
      _setContentError('账号记录不存在。');
      return false;
    }
    if (_accounts[index].password == null) {
      _setContentError('当前账号未保存密码。');
      return false;
    }
    try {
      final nextAccounts = <AccountRecord>[..._accounts];
      nextAccounts[index] = transform(_accounts[index]);
      return _persistSnapshot(
        _snapshot(accounts: nextAccounts),
        failureMessage: failureMessage,
      );
    } on ArgumentError {
      _setContentError('密码复核内容无效，请检查后重试。');
      return false;
    }
  }

  static AccountRecord _accountWithPasswordReview(
    AccountRecord account, {
    required DateTime? passwordStoredAtUtc,
    required PasswordSyncState passwordSyncState,
    required DateTime? passwordVerifiedAtUtc,
    required DateTime? platformPasswordChangedAtUtc,
    required int? passwordReviewIntervalDays,
    required DateTime? passwordReviewSnoozedUntilUtc,
  }) => AccountRecord.fromDraft(
    id: account.id,
    draft: AccountDraft(
      platformName: account.platformName,
      category: account.category,
      loginAccount: account.loginAccount,
      username: account.username,
      boundPhone: account.boundPhone,
      boundEmail: account.boundEmail,
      password: account.password,
      website: account.website,
      notes: account.notes,
      customFields: account.customFields,
    ),
    passwordValueRevision: account.passwordValueRevision,
    passwordChangeHistory: account.passwordChangeHistory,
    passwordStoredAtUtc: passwordStoredAtUtc,
    passwordSyncState: passwordSyncState,
    passwordVerifiedAtUtc: passwordVerifiedAtUtc,
    platformPasswordChangedAtUtc: platformPasswordChangedAtUtc,
    passwordReviewIntervalDays: passwordReviewIntervalDays,
    passwordReviewSnoozedUntilUtc: passwordReviewSnoozedUntilUtc,
  );

  Future<bool> deleteAccount(String accountId) =>
      _moveToTrash(accountId: accountId);

  Future<bool> _moveToTrash({String? accountId, String? subscriptionId}) async {
    if (!_hasWritableSession) return false;
    try {
      final next = VaultTrash.move(
        _snapshot(),
        accountId: accountId,
        subscriptionId: subscriptionId,
        now: _now(),
        batchId: _newImportVaultScopeId(),
      );
      return _persistSnapshot(next, failureMessage: '移入回收站失败，原记录保持不变。');
    } on Object {
      _setContentError('移入回收站失败，原记录保持不变。');
      return false;
    }
  }

  Future<bool> restoreTrash({
    String? accountId,
    String? subscriptionId,
    bool wholeBatch = false,
  }) async {
    if (!_hasWritableSession) return false;
    try {
      final next = VaultTrash.restore(
        _snapshot(),
        accountId: accountId,
        subscriptionId: subscriptionId,
        wholeBatch: wholeBatch,
      );
      return _persistSnapshot(next, failureMessage: '恢复失败，回收站记录保持不变。');
    } on Object {
      _setContentError('无法恢复，请先恢复关联账号或选择恢复整个删除组合。');
      return false;
    }
  }

  Future<bool> permanentlyDeleteTrash({
    required String currentPassword,
    Set<String> accountIds = const {},
    Set<String> subscriptionIds = const {},
    bool emptyAll = false,
    String confirmation = '',
  }) async {
    if (!_hasWritableSession || (emptyAll && confirmation != '清空回收站')) {
      return false;
    }
    final session = _session;
    if (!await verifyCurrentVaultPassword(currentPassword) ||
        !identical(session, _session) ||
        !_hasWritableSession) {
      return false;
    }
    final next = VaultTrash.remove(
      _snapshot(),
      accountIds: emptyAll
          ? _trashAccounts.map((item) => item.record.id).toSet()
          : accountIds,
      subscriptionIds: emptyAll
          ? _trashSubscriptions.map((item) => item.record.id).toSet()
          : subscriptionIds,
    );
    return _persistSnapshot(next, failureMessage: '永久删除失败，回收站记录保持不变。');
  }

  Future<bool> purgeExpiredTrash() async {
    if (!_hasWritableSession) return false;
    final now = _now();
    if (!_trashAccounts.any((item) => item.expired(now)) &&
        !_trashSubscriptions.any((item) => item.expired(now))) {
      return true;
    }
    try {
      final saved = await _persistSnapshot(
        VaultTrash.purgeExpired(_snapshot(), now),
        failureMessage: '回收站自动清理未完成，可稍后重试。',
      );
      if (!saved && isUnlocked) {
        _errorMessage = null;
        _warningMessage = '回收站自动清理未完成，可稍后重试。';
        _notify();
      }
      return saved;
    } on Object {
      return false;
    }
  }

  Future<bool> markAccountViewed(String accountId) async {
    if (!_hasWritableSession) {
      return false;
    }
    if (!_accounts.any((account) => account.id == accountId)) {
      return false;
    }
    if (_recentAccountIds.isNotEmpty && _recentAccountIds.first == accountId) {
      return true;
    }
    final next = <String>[
      accountId,
      ..._recentAccountIds.where((id) => id != accountId),
    ].take(10).toList(growable: false);
    return _persistSnapshot(
      _snapshot(recentAccountIds: next),
      failureMessage: '最近查看记录未能写入本机加密库。',
    );
  }

  Future<bool> updatePreferences(VaultPreferences preferences) async {
    if (!_hasWritableSession) {
      return false;
    }
    try {
      preferences.validate();
      return _persistSnapshot(
        _snapshot(preferences: preferences),
        failureMessage: '设置未能写入本机加密库。',
      );
    } on VaultFormatException {
      _setContentError('设置内容无效。');
      return false;
    }
  }

  Future<bool> requestNotificationPermission() async {
    if (_vaultPhase != VaultPhase.unlocked || _busy) {
      return false;
    }
    try {
      return await _requestNotificationPermissionStatus() ==
          ReminderPermissionStatus.allowed;
    } on Object {
      _setContentError('无法取得系统通知权限。');
      return false;
    }
  }

  Future<NotificationSettingResult> setNotificationsEnabled(
    bool enabled,
  ) async {
    final session = _session;
    if (!_hasWritableSession || session == null) {
      return NotificationSettingResult.rejected;
    }

    if (enabled) {
      ReminderPermissionStatus permissionStatus;
      try {
        permissionStatus = await _requestNotificationPermissionStatus();
      } on Object {
        _setContentError('无法检查系统通知状态。');
        return NotificationSettingResult.permissionCheckFailed;
      }
      switch (permissionStatus) {
        case ReminderPermissionStatus.applicationNotificationsDisabled:
          return NotificationSettingResult.applicationNotificationsDisabled;
        case ReminderPermissionStatus.reminderChannelDisabled:
          return NotificationSettingResult.reminderChannelDisabled;
        case ReminderPermissionStatus.allowed:
          break;
      }
    }

    if (!_hasWritableSession || _session != session) {
      return NotificationSettingResult.rejected;
    }
    final preferences = _preferences.copyWith(notificationsEnabled: enabled);
    try {
      preferences.validate();
    } on VaultFormatException {
      _setContentError('通知设置内容无效。');
      return NotificationSettingResult.saveFailed;
    }
    final snapshot = _snapshot(preferences: preferences);
    final epoch = _operationEpoch;
    final reminderPlanChanged = _reminderPlanChanged(snapshot);
    _beginOperation(epoch);
    _errorMessage = null;
    _warningMessage = null;
    _notify();
    NotificationReconciliationState? reconciliation;
    try {
      var companionSyncFailed = false;
      try {
        if (reminderPlanChanged) {
          reconciliation = await _prepareNotificationReconciliation(
            session,
            targetGeneration: session.generation + 1,
          );
        }
        await session.save(snapshot);
      } on VaultCompanionSyncException {
        companionSyncFailed = true;
        _quickUnlockEnabled = false;
        _quickUnlockScope = null;
      }
      if (!_isCurrent(epoch) || _vaultPhase != VaultPhase.unlocked) {
        return NotificationSettingResult.rejected;
      }
      _replaceSnapshot(snapshot);
      if (companionSyncFailed) {
        _warningMessage = '设置已保存，但订阅快捷视图未能同步；生物识别已安全停用，请用主密码重新启用。';
      }

      // 诱饵库和订阅只读视图与真实库共用同一个 Android 通知队列。
      // 它们可以保存各自的界面偏好，但绝不得清理或重排真实库提醒。
      if (!_canManageSecurity) {
        return enabled
            ? NotificationSettingResult.enabled
            : NotificationSettingResult.disabled;
      }

      try {
        if (_anyNotificationsEnabled(snapshot.preferences)) {
          await _reminderScheduler.rescheduleAll(
            snapshot.preferences.notificationsEnabled
                ? snapshot.subscriptions
                : const <SubscriptionRecord>[],
            reminderTimeMinutes:
                snapshot.preferences.defaultReminderTimeMinutes,
            secondReminderTimeMinutes:
                snapshot.preferences.secondReminderTimeMinutes,
            passwordReviewAtUtc:
                snapshot.preferences.passwordReviewNotificationsEnabled
                ? _passwordReviewReminderAtUtc(snapshot)
                : null,
          );
        } else {
          await _reminderScheduler.cancelAll();
        }
      } on ReminderSchedulingException catch (error) {
        await _recordNotificationReconciliationFailureBestEffort(
          session,
          reconciliation,
        );
        if (enabled && error.stages.contains(ReminderFailureStage.initialize)) {
          _warningMessage = '通知设置已保存为开启，但系统通知初始化失败；请使用设置页测试功能重试。';
          return NotificationSettingResult.initializationFailed;
        }
        _warningMessage = enabled
            ? '通知设置已保存为开启，但部分提醒重排失败；下次解锁会重试。'
            : '通知设置已保存为关闭，但旧提醒清理失败；下次解锁会重试。';
        return enabled
            ? NotificationSettingResult.scheduleFailed
            : NotificationSettingResult.cancelFailed;
      } on Object {
        await _recordNotificationReconciliationFailureBestEffort(
          session,
          reconciliation,
        );
        _warningMessage = enabled
            ? '通知设置已保存为开启，但部分提醒重排失败；下次解锁会重试。'
            : '通知设置已保存为关闭，但旧提醒清理失败；下次解锁会重试。';
        return enabled
            ? NotificationSettingResult.scheduleFailed
            : NotificationSettingResult.cancelFailed;
      }

      if (reconciliation != null &&
          session is NotificationReconciliationVaultSession) {
        try {
          await session.completeNotificationReconciliation(
            operationId: reconciliation.operationId,
          );
        } on Object {
          _warningMessage = '系统提醒已同步，但待协调状态未能清除；后续重试使用固定提醒编号，不会创建重复提醒。';
          return enabled
              ? NotificationSettingResult.scheduleFailed
              : NotificationSettingResult.cancelFailed;
        }
      }

      return enabled
          ? NotificationSettingResult.enabled
          : NotificationSettingResult.disabled;
    } on Object {
      if (_isCurrent(epoch) && _vaultPhase == VaultPhase.unlocked) {
        _errorMessage = '通知设置未能写入本机加密库。';
      }
      return NotificationSettingResult.saveFailed;
    } finally {
      _finishOperation(epoch);
    }
  }

  Future<bool> setPasswordReviewNotificationsEnabled(bool enabled) async {
    final session = _session;
    if (!_hasWritableSession || session == null || !_canManageSecurity) {
      return false;
    }
    if (enabled) {
      try {
        final permission = await _requestNotificationPermissionStatus();
        if (permission != ReminderPermissionStatus.allowed) {
          _setContentError('系统通知当前不可用，密码复核提醒未开启。');
          return false;
        }
      } on Object {
        _setContentError('无法检查系统通知状态。');
        return false;
      }
    }
    if (!_hasWritableSession || _session != session) return false;
    return _persistSnapshot(
      _snapshot(
        preferences: _preferences.copyWith(
          passwordReviewNotificationsEnabled: enabled,
        ),
      ),
      failureMessage: '密码复核通知设置未能写入本机加密库。',
    );
  }

  Future<NotificationTestResult> testLocalNotifications() async {
    final session = _session;
    if (_vaultPhase != VaultPhase.unlocked || session == null || _busy) {
      return NotificationTestResult.rejected;
    }
    if (!_preferences.notificationsEnabled) {
      return NotificationTestResult.notificationsDisabled;
    }

    ReminderPermissionStatus permissionStatus;
    try {
      permissionStatus = await _requestNotificationPermissionStatus();
    } on Object {
      return NotificationTestResult.permissionCheckFailed;
    }
    switch (permissionStatus) {
      case ReminderPermissionStatus.applicationNotificationsDisabled:
        return NotificationTestResult.applicationNotificationsDisabled;
      case ReminderPermissionStatus.reminderChannelDisabled:
        return NotificationTestResult.reminderChannelDisabled;
      case ReminderPermissionStatus.allowed:
        break;
    }

    if (_vaultPhase != VaultPhase.unlocked || _session != session || _busy) {
      return NotificationTestResult.rejected;
    }
    final epoch = _operationEpoch;
    _beginOperation(epoch);
    _errorMessage = null;
    _warningMessage = null;
    _notify();
    try {
      try {
        await _reminderScheduler.showTestNotification();
      } on ReminderSchedulingException catch (error) {
        return error.stages.contains(ReminderFailureStage.initialize)
            ? NotificationTestResult.initializationFailed
            : NotificationTestResult.immediateFailed;
      } on Object {
        return NotificationTestResult.immediateFailed;
      }

      try {
        await _reminderScheduler.scheduleTestReminder();
      } on ReminderSchedulingException catch (error) {
        return error.stages.contains(ReminderFailureStage.initialize)
            ? NotificationTestResult.initializationFailed
            : NotificationTestResult.scheduleFailed;
      } on Object {
        return NotificationTestResult.scheduleFailed;
      }
      return NotificationTestResult.immediateAndScheduled;
    } finally {
      _finishOperation(epoch);
    }
  }

  Future<NotificationTestResult> testImmediateNotification() =>
      _runSingleNotificationTest(
        operation: _reminderScheduler.showTestNotification,
        success: NotificationTestResult.immediateSent,
        failure: NotificationTestResult.immediateFailed,
      );

  Future<NotificationTestResult> testOneMinuteReminder() =>
      _runSingleNotificationTest(
        operation: _reminderScheduler.scheduleTestReminder,
        success: NotificationTestResult.scheduled,
        failure: NotificationTestResult.scheduleFailed,
      );

  Future<NotificationTestResult> _runSingleNotificationTest({
    required Future<void> Function() operation,
    required NotificationTestResult success,
    required NotificationTestResult failure,
  }) async {
    final session = _session;
    if (_vaultPhase != VaultPhase.unlocked || session == null || _busy) {
      return NotificationTestResult.rejected;
    }
    if (!_preferences.notificationsEnabled) {
      return NotificationTestResult.notificationsDisabled;
    }

    ReminderPermissionStatus permissionStatus;
    try {
      permissionStatus = await _requestNotificationPermissionStatus();
    } on Object {
      return NotificationTestResult.permissionCheckFailed;
    }
    switch (permissionStatus) {
      case ReminderPermissionStatus.applicationNotificationsDisabled:
        return NotificationTestResult.applicationNotificationsDisabled;
      case ReminderPermissionStatus.reminderChannelDisabled:
        return NotificationTestResult.reminderChannelDisabled;
      case ReminderPermissionStatus.allowed:
        break;
    }

    if (_vaultPhase != VaultPhase.unlocked || _session != session || _busy) {
      return NotificationTestResult.rejected;
    }
    final epoch = _operationEpoch;
    _beginOperation(epoch);
    _errorMessage = null;
    _warningMessage = null;
    _notify();
    try {
      await operation();
      return success;
    } on ReminderSchedulingException catch (error) {
      return error.stages.contains(ReminderFailureStage.initialize)
          ? NotificationTestResult.initializationFailed
          : failure;
    } on Object {
      return failure;
    } finally {
      _finishOperation(epoch);
    }
  }

  Future<NotificationReliabilityReport> inspectNotificationReliability() async {
    if (_vaultPhase != VaultPhase.unlocked ||
        _session == null ||
        !_canManageSecurity ||
        _busy) {
      return const NotificationReliabilityReport(
        platform: PlatformNotificationReliabilityStatus.unavailable(),
        pendingReminderCount: null,
        reconciliation: NotificationReconciliationStatus.unavailable(),
      );
    }
    PlatformNotificationReliabilityStatus platform;
    int? pendingCount;
    var reconciliation = const NotificationReconciliationStatus.unavailable();
    try {
      platform = await _notificationReliabilityService.inspect();
    } on Object {
      platform = const PlatformNotificationReliabilityStatus.unavailable();
    }
    try {
      pendingCount = await _reminderScheduler.pendingReminderCount();
    } on Object {
      pendingCount = null;
    }
    final session = _session;
    if (_vaultPhase == VaultPhase.unlocked &&
        _canManageSecurity &&
        session is NotificationReconciliationVaultSession) {
      try {
        final pending = await session.readNotificationReconciliation();
        reconciliation = pending == null
            ? const NotificationReconciliationStatus.upToDate()
            : NotificationReconciliationStatus.pending(
                attemptCount: pending.attemptCount,
                pendingSinceUtc: pending.createdAtUtc,
                lastAttemptAtUtc: pending.lastAttemptAtUtc,
              );
      } on Object {
        reconciliation = const NotificationReconciliationStatus.unavailable();
      }
    }
    return NotificationReliabilityReport(
      platform: platform,
      pendingReminderCount: pendingCount,
      reconciliation: reconciliation,
    );
  }

  /// 从系统设置返回后，在保险库仍解锁且提醒开启时重新提交当前提醒。
  ///
  /// 这会把此前因精确闹钟权限不足而降级的待发项升级为精确调度；不读取、
  /// 不记录也不返回订阅内容。失败只影响本次可靠性刷新，业务数据保持不变。
  Future<bool> refreshReminderScheduleForReliability({
    bool contentOnly = false,
  }) async {
    final session = _session;
    if (_vaultPhase != VaultPhase.unlocked ||
        session == null ||
        !_canManageSecurity ||
        _busy) {
      return false;
    }
    try {
      await _prepareNotificationReconciliation(
        session,
        targetGeneration: session.generation,
      );
      return _syncReminders(
        _snapshot(),
        previousNotificationsEnabled: true,
        preserveOtherNotifications: contentOnly,
      );
    } on Object {
      if (_vaultPhase == VaultPhase.unlocked && !_disposed) {
        _warningMessage = '无法保存提醒待协调状态；业务数据未改变，请稍后重试。';
        _notify();
      }
      return false;
    }
  }

  /// 前台恢复时，仅为新的系统时区/时间变更记录执行一次真实库全量重排。
  ///
  /// 普通 resume、开机/升级记录和已处理记录都不会触发重排。锁定、诱饵/
  /// 只读会话或业务写入进行中时不消费记录，留待下一次安全的前台机会。
  Future<bool> refreshReminderScheduleForSystemTimeRecovery() async {
    if (_vaultPhase != VaultPhase.unlocked ||
        _session == null ||
        !_canManageSecurity ||
        _busy ||
        _disposed ||
        !_preferences.notificationsEnabled ||
        _systemTimeRecoveryRefreshInProgress) {
      return false;
    }

    _systemTimeRecoveryRefreshInProgress = true;
    try {
      final PlatformNotificationReliabilityStatus platform;
      try {
        platform = await _notificationReliabilityService.inspect();
      } on Object {
        return false;
      }
      final record = platform.lastRecovery;
      if (record == null || !_isSystemTimeRecovery(record.trigger)) {
        return false;
      }
      final token =
          '${record.occurredAtUtc.millisecondsSinceEpoch}:${record.trigger}';
      if (_handledSystemTimeRecoveryToken == token) {
        return false;
      }

      // 状态可能在平台查询期间变化。只有仍处于空闲真实主库会话时才
      // 读取订阅快照并调度；否则不得把该恢复记录标记为已处理。
      if (_vaultPhase != VaultPhase.unlocked ||
          _session == null ||
          !_canManageSecurity ||
          _busy ||
          _disposed ||
          !_preferences.notificationsEnabled) {
        return false;
      }
      try {
        final session = _session!;
        await _prepareNotificationReconciliation(
          session,
          targetGeneration: session.generation,
        );
        if (!await _syncReminders(_snapshot())) return false;
      } on Object {
        return false;
      }
      _handledSystemTimeRecoveryToken = token;
      return true;
    } finally {
      _systemTimeRecoveryRefreshInProgress = false;
    }
  }

  Future<bool> openNotificationReliabilitySettings(
    NotificationSettingsTarget target,
  ) async {
    if (_vaultPhase != VaultPhase.unlocked ||
        _session == null ||
        !_canManageSecurity ||
        _busy) {
      return false;
    }
    beginExternalInteraction();
    try {
      return await _notificationReliabilityService.openSettings(target);
    } on Object {
      return false;
    } finally {
      endExternalInteraction();
    }
  }

  bool _isSystemTimeRecovery(String trigger) =>
      trigger == 'android.intent.action.TIMEZONE_CHANGED' ||
      trigger == 'android.intent.action.TIME_SET';

  Future<ReminderPermissionStatus>
  _requestNotificationPermissionStatus() async {
    beginExternalInteraction();
    try {
      return await _reminderScheduler.requestPermission();
    } finally {
      endExternalInteraction();
    }
  }

  Future<bool> verifyMasterPassword(String masterPassword) => _canManageSecurity
      ? verifyCurrentVaultPassword(masterPassword)
      : Future.value(false);

  Future<bool> verifyCurrentVaultPassword(String masterPassword) async {
    final session = _session;
    if (_vaultPhase != VaultPhase.unlocked ||
        session == null ||
        !hasFullVaultAccess ||
        _busy) {
      return false;
    }
    final epoch = _operationEpoch;
    _beginOperation(epoch);
    _errorMessage = null;
    _notify();
    Uint8List? currentEnvelopeBytes;
    try {
      currentEnvelopeBytes = await session.exportEncryptedBackup();
      await _vaultStore.readEncryptedBackup(
        bytes: currentEnvelopeBytes,
        masterPassword: masterPassword,
      );
      return _isCurrent(epoch) && _vaultPhase == VaultPhase.unlocked;
    } on VaultUnlockException {
      if (_isCurrent(epoch)) {
        _errorMessage = '当前保险库密码不正确。';
      }
      return false;
    } on Object {
      if (_isCurrent(epoch)) {
        _errorMessage = '无法验证当前保险库密码。';
      }
      return false;
    } finally {
      currentEnvelopeBytes?.fillRange(0, currentEnvelopeBytes.length, 0);
      _finishOperation(epoch);
    }
  }

  Future<bool> enableQuickUnlock(
    String currentMasterPassword, {
    QuickUnlockScope scope = QuickUnlockScope.fullVault,
  }) async {
    final session = _session;
    if (_vaultPhase != VaultPhase.unlocked ||
        session == null ||
        !_canManageSecurity ||
        _busy) {
      return false;
    }
    final epoch = _operationEpoch;
    beginExternalInteraction();
    _beginOperation(epoch);
    _errorMessage = null;
    _quickUnlockFailureReason = null;
    _notify();
    VaultOpenResult? verification;
    try {
      final securityController = _vaultStore is LayeredVaultSecurityController
          ? _vaultStore as LayeredVaultSecurityController
          : null;
      if (securityController != null) {
        await securityController.configureQuickUnlock(
          currentMasterPassword: currentMasterPassword,
          scope: scope,
        );
      } else {
        if (scope != QuickUnlockScope.fullVault) {
          throw const QuickUnlockException(
            QuickUnlockFailureReason.unsupported,
            platformCode: 'scope_unsupported',
          );
        }
        verification = await _vaultStore.unlock(
          masterPassword: currentMasterPassword,
        );
        await verification.session.enableQuickUnlock();
      }
      if (!_isCurrent(epoch) || _vaultPhase != VaultPhase.unlocked) {
        return false;
      }
      _quickUnlockEnabled = true;
      _quickUnlockScope = scope;
      _quickUnlockFailureReason = null;
      return true;
    } on QuickUnlockException catch (error) {
      await _recordQuickUnlockFailure(error, epoch, enabling: true);
      return false;
    } on VaultUnlockException {
      if (_isCurrent(epoch)) {
        _errorMessage = '当前主密码不正确。';
      }
      return false;
    } on Object {
      if (_isCurrent(epoch)) {
        _errorMessage = '未能启用生物识别，请确认已录入可用的指纹或人脸。';
      }
      return false;
    } finally {
      verification?.session.close();
      _finishOperation(epoch);
      endExternalInteraction();
    }
  }

  Future<bool> disableQuickUnlock() async {
    if (_vaultPhase != VaultPhase.unlocked || !_canManageSecurity || _busy) {
      return false;
    }
    final epoch = _operationEpoch;
    beginExternalInteraction();
    _beginOperation(epoch);
    _errorMessage = null;
    _quickUnlockFailureReason = null;
    _notify();
    try {
      await _vaultStore.disableQuickUnlock();
      if (!_isCurrent(epoch) || _vaultPhase != VaultPhase.unlocked) {
        return false;
      }
      _quickUnlockEnabled = false;
      _quickUnlockScope = null;
      _quickUnlockFailureReason = null;
      return true;
    } on QuickUnlockException catch (error) {
      if (_isCurrent(epoch)) {
        _quickUnlockFailureReason = error.reason;
        _errorMessage = '未能关闭生物识别快速解锁。';
      }
      return false;
    } on Object {
      if (_isCurrent(epoch)) {
        _errorMessage = '未能关闭生物识别快速解锁。';
      }
      return false;
    } finally {
      _finishOperation(epoch);
      endExternalInteraction();
    }
  }

  Future<bool> createDecoyVault({
    required String currentMasterPassword,
    required String decoyPassword,
  }) async {
    if (!_hasWritableSession || !_canManageSecurity) {
      return false;
    }
    final controller = _vaultStore is LayeredVaultSecurityController
        ? _vaultStore as LayeredVaultSecurityController
        : null;
    if (controller == null) {
      _setContentError('当前存储环境不支持诱饵保险库。');
      return false;
    }
    final assessment = OfflinePasswordAdvisor.assess(
      decoyPassword,
      purpose: NewPasswordPurpose.decoy,
    );
    if (!assessment.accepted) {
      _setContentError(assessment.message);
      return false;
    }

    final epoch = _operationEpoch;
    _beginOperation(epoch);
    _errorMessage = null;
    _warningMessage = null;
    _notify();
    try {
      await controller.createDecoyVault(
        currentMasterPassword: currentMasterPassword,
        decoyPassword: decoyPassword,
      );
      if (!_isCurrent(epoch) || _vaultPhase != VaultPhase.unlocked) {
        return false;
      }
      _decoyVaultConfigured = true;
      _warningMessage = '诱饵保险库已创建。请立即锁定并用诱饵密码进入，亲自添加可信但不敏感的内容。';
      return true;
    } on DecoyPasswordConflictException {
      if (_isCurrent(epoch)) {
        _errorMessage = '诱饵密码不能与当前主密码相同。';
      }
      return false;
    } on DecoyVaultAlreadyConfiguredException {
      if (_isCurrent(epoch)) {
        _decoyVaultConfigured = true;
        _errorMessage = '本机已配置诱饵保险库；为避免误删数据，本版本不会覆盖它。';
      }
      return false;
    } on VaultUnlockException {
      if (_isCurrent(epoch)) {
        _errorMessage = '当前主密码不正确。';
      }
      return false;
    } on Object {
      if (_isCurrent(epoch)) {
        _errorMessage = '诱饵保险库创建失败，真实保险库未被修改。';
      }
      return false;
    } finally {
      _finishOperation(epoch);
    }
  }

  Future<bool> configurePasswordRecovery({
    required String currentMasterPassword,
    required List<String> questionIds,
    required List<String> answers,
    required VaultRecoveryEntryMode entryMode,
    VaultRecoveryScope scope = VaultRecoveryScope.primary,
    String? currentDecoyPassword,
  }) async {
    if (!_hasWritableSession || !_canManageSecurity || _busy) return false;
    if (scope == VaultRecoveryScope.decoy && !_decoyVaultConfigured) {
      _setContentError('本机尚未配置诱饵保险库。');
      return false;
    }
    if (recoveryChallengeFor(scope) != null) {
      _setContentError('该保险库已配置密码恢复；如需更换问题，请先验证密码并关闭原配置。');
      return false;
    }
    final controller = _vaultStore is LayeredVaultSecurityController
        ? _vaultStore as LayeredVaultSecurityController
        : null;
    if (controller == null) {
      _setContentError('当前存储环境不支持本机双因子密码恢复。');
      return false;
    }

    final epoch = _operationEpoch;
    beginExternalInteraction();
    _beginOperation(epoch);
    _errorMessage = null;
    _warningMessage = null;
    _notify();
    VaultOpenResult? refreshed;
    VaultRecoveryChallenge? configuredChallenge;
    var committed = false;
    try {
      configuredChallenge = await controller.configureRecovery(
        currentMasterPassword: currentMasterPassword,
        currentDecoyPassword: currentDecoyPassword,
        questionIds: questionIds,
        answers: answers,
        entryMode: entryMode,
        scope: scope,
      );
      committed = true;
      refreshed = await _vaultStore.unlock(
        masterPassword: currentMasterPassword,
      );
      if (!_isCurrent(epoch) || _vaultPhase != VaultPhase.unlocked) {
        refreshed.session.close();
        refreshed = null;
        return false;
      }
      _vaultRecoveryConfiguration = VaultRecoveryConfiguration(
        primaryChallenge: scope == VaultRecoveryScope.primary
            ? configuredChallenge
            : primaryRecoveryChallenge,
        decoyChallenge: scope == VaultRecoveryScope.decoy
            ? configuredChallenge
            : decoyRecoveryChallenge,
      );
      if (scope == VaultRecoveryScope.primary) {
        _quickUnlockEnabled = false;
        _quickUnlockScope = null;
      }
      final result = refreshed;
      refreshed = null;
      _applyOpenResult(result);
      _warningMessage = scope == VaultRecoveryScope.primary
          ? '真实保险库密码恢复已启用，生物识别快速解锁已安全停用；请锁定后亲自验证恢复入口。'
          : '诱饵保险库密码恢复已启用；请锁定后亲自验证恢复入口。';
      return true;
    } on RecoveryDeviceSecretException catch (error) {
      if (_isCurrent(epoch)) {
        _errorMessage = _recoveryDeviceErrorMessage(error);
      }
      return false;
    } on VaultRecoveryQuestionSetConflictException {
      if (_isCurrent(epoch)) {
        _errorMessage = '两套保险库不能使用完全相同的三道密保问题；请至少更换一道。';
      }
      return false;
    } on VaultCredentialRejectedException {
      if (_isCurrent(epoch)) {
        _errorMessage = scope == VaultRecoveryScope.primary
            ? '当前真实主密码不正确。'
            : '当前真实主密码或诱饵密码不正确。';
      }
      return false;
    } on ArgumentError {
      if (_isCurrent(epoch)) {
        _errorMessage = '请选择三道不同的内置问题，并完整填写三组答案。';
      }
      return false;
    } on Object {
      if (_isCurrent(epoch)) {
        if (committed) {
          _vaultRecoveryConfiguration = VaultRecoveryConfiguration(
            primaryChallenge: scope == VaultRecoveryScope.primary
                ? configuredChallenge
                : primaryRecoveryChallenge,
            decoyChallenge: scope == VaultRecoveryScope.decoy
                ? configuredChallenge
                : decoyRecoveryChallenge,
          );
          if (scope == VaultRecoveryScope.primary) {
            _quickUnlockEnabled = false;
            _quickUnlockScope = null;
          }
          _session?.close();
          _session = null;
          _vaultPhase = VaultPhase.locked;
          _errorMessage = '密码恢复已提交，但当前会话无法刷新；请用真实主密码重新解锁。';
          return true;
        }
        _errorMessage = '密码恢复设置未完成，当前主密码和保险库数据未改变。';
      }
      return false;
    } finally {
      refreshed?.session.close();
      if (!committed) await _refreshQuickUnlockConfiguration();
      _finishOperation(epoch);
      endExternalInteraction();
    }
  }

  Future<bool> disablePasswordRecovery({
    required String currentMasterPassword,
    VaultRecoveryScope scope = VaultRecoveryScope.primary,
    String? currentDecoyPassword,
  }) async {
    if (!_hasWritableSession ||
        !_canManageSecurity ||
        _busy ||
        recoveryChallengeFor(scope) == null) {
      return false;
    }
    final controller = _vaultStore is LayeredVaultSecurityController
        ? _vaultStore as LayeredVaultSecurityController
        : null;
    if (controller == null) return false;

    final epoch = _operationEpoch;
    beginExternalInteraction();
    _beginOperation(epoch);
    _errorMessage = null;
    _warningMessage = null;
    _notify();
    VaultOpenResult? refreshed;
    var committed = false;
    try {
      await controller.disableRecovery(
        currentMasterPassword: currentMasterPassword,
        currentDecoyPassword: currentDecoyPassword,
        scope: scope,
      );
      committed = true;
      _vaultRecoveryConfiguration = VaultRecoveryConfiguration(
        primaryChallenge: scope == VaultRecoveryScope.primary
            ? null
            : primaryRecoveryChallenge,
        decoyChallenge: scope == VaultRecoveryScope.decoy
            ? null
            : decoyRecoveryChallenge,
      );
      refreshed = await _vaultStore.unlock(
        masterPassword: currentMasterPassword,
      );
      if (!_isCurrent(epoch) || _vaultPhase != VaultPhase.unlocked) {
        refreshed.session.close();
        refreshed = null;
        return false;
      }
      final result = refreshed;
      refreshed = null;
      _applyOpenResult(result);
      _warningMessage = scope == VaultRecoveryScope.primary
          ? '真实保险库密码恢复已关闭；当前密码和业务数据未改变。'
          : '诱饵保险库密码恢复已关闭；当前密码和业务数据未改变。';
      return true;
    } on VaultCredentialRejectedException {
      if (_isCurrent(epoch)) {
        _errorMessage = scope == VaultRecoveryScope.primary
            ? '当前真实主密码不正确。'
            : '当前真实主密码或诱饵密码不正确。';
      }
      return false;
    } on VaultRecoveryNotConfiguredException {
      if (_isCurrent(epoch)) {
        _vaultRecoveryConfiguration = VaultRecoveryConfiguration(
          primaryChallenge: scope == VaultRecoveryScope.primary
              ? null
              : primaryRecoveryChallenge,
          decoyChallenge: scope == VaultRecoveryScope.decoy
              ? null
              : decoyRecoveryChallenge,
        );
        _errorMessage = '本机密码恢复已经处于关闭状态。';
      }
      return false;
    } on Object {
      if (_isCurrent(epoch)) {
        if (committed) {
          _vaultRecoveryConfiguration = VaultRecoveryConfiguration(
            primaryChallenge: scope == VaultRecoveryScope.primary
                ? null
                : primaryRecoveryChallenge,
            decoyChallenge: scope == VaultRecoveryScope.decoy
                ? null
                : decoyRecoveryChallenge,
          );
          _session?.close();
          _session = null;
          _vaultPhase = VaultPhase.locked;
          _errorMessage = '密码恢复已关闭，但当前会话无法刷新；请用主密码重新解锁。';
          return true;
        }
        _errorMessage = '未能关闭密码恢复，原配置保持不变。';
      }
      return false;
    } finally {
      refreshed?.session.close();
      _finishOperation(epoch);
      endExternalInteraction();
    }
  }

  Future<bool> recoverMasterPassword({
    required List<String> questionIds,
    required List<String> answers,
    required String newMasterPassword,
    required VaultRecoveryEntryMode requestEntryMode,
  }) async {
    if (_vaultPhase != VaultPhase.locked ||
        _busy ||
        !hasRecoveryEntryMode(requestEntryMode)) {
      return false;
    }
    final recoveryPasswordLength = newMasterPassword.runes.length;
    if (recoveryPasswordLength < 16 || recoveryPasswordLength > 32) {
      _errorMessage = '密码恢复时，新密码统一为16–32个字符；建议使用大小写字母、数字和符号。';
      _notify();
      return false;
    }
    final assessment = OfflinePasswordAdvisor.assess(newMasterPassword);
    if (!assessment.accepted) {
      _errorMessage = assessment.message;
      _notify();
      return false;
    }
    final controller = _vaultStore is LayeredVaultSecurityController
        ? _vaultStore as LayeredVaultSecurityController
        : null;
    if (controller == null) return false;

    VaultRecoveryEntry? pendingImportRecovery;
    var allowPrimaryRecovery = true;
    var discardCompletedRecoveryRollback = false;
    try {
      pendingImportRecovery = await _recoveryJournal.read();
      if (pendingImportRecovery != null) {
        _recoveryState = pendingImportRecovery.state;
        if (pendingImportRecovery.state == VaultRecoveryState.prepared) {
          // 只有未确认提交结果的回滚事务会阻断真实库换密。目标仍由核心层
          // 在密保与强认证通过后判定，AppState 不提前泄露命中对象。
          allowPrimaryRecovery = false;
        } else {
          // committed/rolledBack 只是已完成事务留下的旧密码回滚凭据。
          // 正确恢复凭据通过后、换密提交前必须废弃它，不能永久误伤恢复。
          discardCompletedRecoveryRollback = true;
        }
      }
    } on Object {
      // 回滚日志无法可信读取时，真实库必须保守拒绝改密；但目标身份仍只由
      // 核心层在密保与强认证通过后中性判定，不能连带阻断独立诱饵库恢复。
      _recoveryState = VaultRecoveryState.prepared;
      allowPrimaryRecovery = false;
    } finally {
      pendingImportRecovery?.destroy();
    }

    final epoch = ++_operationEpoch;
    beginExternalInteraction();
    _beginOperation(epoch);
    _errorMessage = null;
    _warningMessage = null;
    _notify();
    VaultOpenResult? recovered;
    try {
      recovered = await controller.recoverMasterPassword(
        questionIds: questionIds,
        answers: answers,
        newMasterPassword: newMasterPassword,
        requestEntryMode: requestEntryMode,
        allowPrimaryRecovery: allowPrimaryRecovery,
        beforePrimaryCommit: discardCompletedRecoveryRollback
            ? () async {
                await _recoveryJournal.clear();
                _recoveryRefreshToken += 1;
                _recoveryState = null;
              }
            : null,
      );
      if (!_isCurrent(epoch)) {
        recovered.session.close();
        recovered = null;
        return false;
      }
      final recoveredPrimary =
          recovered.session is! ScopedVaultSession ||
          (recovered.session as ScopedVaultSession).canManageSecurity;
      final throttleReset = recoveredPrimary
          ? await _resetUnlockFailures()
          : true;
      _quickUnlockEnabled = false;
      _quickUnlockScope = null;
      final result = recovered;
      recovered = null;
      _applyOpenResult(result);
      _warningMessage = throttleReset
          ? '保险库密码已安全重设并生成全新数据密钥。'
          : '保险库密码已重设，但安全计数状态暂时无法更新；请稍后重新锁定并核对。';
      return true;
    } on RecoveryDeviceSecretException catch (error) {
      if (_isCurrent(epoch)) _errorMessage = _recoveryDeviceErrorMessage(error);
      return false;
    } on VaultRecoveryRejectedException {
      if (_isCurrent(epoch)) {
        _errorMessage = '无法完成恢复；请核对当前显示的三道问题及对应答案，并通过本机系统强认证。';
      }
      return false;
    } on VaultIntegrityException {
      if (_isCurrent(epoch)) {
        _errorMessage = '保险库完整性验证失败，密码和数据均未修改。';
      }
      return false;
    } on VaultUnsupportedEnvelopeVersionException {
      if (_isCurrent(epoch)) {
        _errorMessage = '该保险库来自更高版本应用，本版本不能安全恢复。';
      }
      return false;
    } on Object {
      if (_isCurrent(epoch)) {
        _errorMessage = '密码恢复未完成；请不要卸载应用。请重新核对恢复信息，或在确认有可用加密备份后再选择重新开始。';
      }
      return false;
    } finally {
      recovered?.session.close();
      _finishOperation(epoch);
      endExternalInteraction();
    }
  }

  Future<bool> changeMasterPassword({
    required String currentMasterPassword,
    required String newMasterPassword,
    bool discardRecoveryRollback = false,
  }) async {
    final session = _session;
    if (!_hasWritableSession || !_canManageSecurity || session == null) {
      return false;
    }
    if (primaryRecoveryChallenge != null) {
      _setContentError('请先关闭真实保险库密码恢复，再修改真实主密码；完成后可重新设置三道密保。');
      return false;
    }
    final controller = _vaultStore is LayeredVaultSecurityController
        ? _vaultStore as LayeredVaultSecurityController
        : null;
    if (controller == null) {
      _setContentError('当前存储环境不支持安全修改主密码。');
      return false;
    }
    final assessment = OfflinePasswordAdvisor.assess(newMasterPassword);
    if (!assessment.accepted) {
      _setContentError(assessment.message);
      return false;
    }

    final epoch = _operationEpoch;
    _beginOperation(epoch);
    _errorMessage = null;
    _warningMessage = null;
    _notify();
    Uint8List? currentEnvelopeBytes;
    VaultRecoveryEntry? recovery;
    VaultOpenResult? changed;
    var recoveryDiscarded = false;
    var rotationRequested = false;

    Future<void> refreshSecurityStateAfterFailure() async {
      if (rotationRequested) await _refreshQuickUnlockConfiguration();
      if (recoveryDiscarded && _isCurrent(epoch)) {
        _warningMessage = '本机恢复前回滚副本已按你的确认永久废弃，但主密码未修改；当前保险库仍使用原主密码。';
      }
    }

    try {
      // 在废弃旧密码保护的 recovery journal 前，先独立验证当前真实主密码。
      currentEnvelopeBytes = await session.exportEncryptedBackup();
      await _vaultStore.readEncryptedBackup(
        bytes: currentEnvelopeBytes,
        masterPassword: currentMasterPassword,
      );
      recovery = await _recoveryJournal.read();
      if (recovery?.state == VaultRecoveryState.prepared) {
        _recoveryState = VaultRecoveryState.prepared;
        _errorMessage = '检测到尚未确认的恢复事务；为避免失去唯一回退点，已停止修改主密码。';
        return false;
      }
      if (recovery?.state == VaultRecoveryState.committed &&
          !discardRecoveryRollback) {
        _recoveryState = VaultRecoveryState.committed;
        _errorMessage = '本机仍有“上次导入前”回滚副本；确认永久放弃该副本后才能修改主密码。';
        return false;
      }
      if (recovery != null) {
        await _recoveryJournal.clear();
        recoveryDiscarded = true;
        _recoveryRefreshToken += 1;
        _recoveryState = null;
      }

      rotationRequested = true;
      changed = await controller.changeMasterPassword(
        currentMasterPassword: currentMasterPassword,
        newMasterPassword: newMasterPassword,
      );
      if (!_isCurrent(epoch) || _vaultPhase != VaultPhase.unlocked) {
        changed.session.close();
        changed = null;
        return false;
      }
      _quickUnlockEnabled = false;
      _quickUnlockScope = null;
      final throttleReset = await _resetUnlockFailures();
      if (!_isCurrent(epoch) || _vaultPhase != VaultPhase.unlocked) {
        changed.session.close();
        changed = null;
        return false;
      }
      final result = changed;
      changed = null;
      _applyOpenResult(result);
      final passwordChangedMessage = recoveryDiscarded
          ? '主密码已修改；旧的本机恢复前回滚副本已废弃，生物识别已安全停用。'
          : '主密码已修改；生物识别已安全停用，请按需用新主密码重新开启。';
      _warningMessage = throttleReset
          ? passwordChangedMessage
          : '$passwordChangedMessage 安全计数状态暂时无法持久化。';
      return true;
    } on VaultPasswordUnchangedException {
      if (_isCurrent(epoch)) _errorMessage = '新主密码不能与当前主密码相同。';
      await refreshSecurityStateAfterFailure();
      return false;
    } on DecoyPasswordConflictException {
      if (_isCurrent(epoch)) _errorMessage = '新主密码不能与当前诱饵密码相同。';
      await refreshSecurityStateAfterFailure();
      return false;
    } on VaultCredentialRejectedException {
      if (_isCurrent(epoch)) _errorMessage = '当前真实主密码不正确。';
      await refreshSecurityStateAfterFailure();
      return false;
    } on VaultIntegrityException {
      if (_isCurrent(epoch)) {
        _errorMessage = '保险库完整性验证失败；为避免破坏数据，主密码未修改。';
      }
      await refreshSecurityStateAfterFailure();
      return false;
    } on VaultUnlockException {
      if (_isCurrent(epoch)) _errorMessage = '当前真实主密码无法验证。';
      await refreshSecurityStateAfterFailure();
      return false;
    } on VaultStorageException {
      if (_isCurrent(epoch)) {
        _errorMessage = rotationRequested
            ? '主密码轮换未完成；当前主库仍使用原主密码，生物识别可能已安全停用，请重试。'
            : '无法安全确认或废弃本机恢复回滚副本；主密码未修改。';
      }
      await refreshSecurityStateAfterFailure();
      return false;
    } on Object {
      if (_isCurrent(epoch)) {
        _errorMessage = rotationRequested
            ? '主密码修改未完成；当前主库仍使用原主密码，请不要卸载应用并稍后重试。'
            : '无法开始修改主密码；当前数据未被修改。';
      }
      await refreshSecurityStateAfterFailure();
      return false;
    } finally {
      changed?.session.close();
      recovery?.destroy();
      currentEnvelopeBytes?.fillRange(0, currentEnvelopeBytes.length, 0);
      _finishOperation(epoch);
    }
  }

  Future<bool> changeDecoyPassword({
    required String currentMasterPassword,
    required String currentDecoyPassword,
    required String newDecoyPassword,
  }) async {
    if (!_hasWritableSession || !_canManageSecurity || !_decoyVaultConfigured) {
      return false;
    }
    if (decoyRecoveryConfigured) {
      _setContentError('请先关闭诱饵保险库密码恢复，再修改诱饵密码；完成后可重新设置三道密保。');
      return false;
    }
    final controller = _vaultStore is LayeredVaultSecurityController
        ? _vaultStore as LayeredVaultSecurityController
        : null;
    if (controller == null) {
      _setContentError('当前存储环境不支持修改诱饵密码。');
      return false;
    }
    final assessment = OfflinePasswordAdvisor.assess(
      newDecoyPassword,
      purpose: NewPasswordPurpose.decoy,
    );
    if (!assessment.accepted) {
      _setContentError(assessment.message);
      return false;
    }

    final epoch = _operationEpoch;
    _beginOperation(epoch);
    _errorMessage = null;
    _warningMessage = null;
    _notify();
    try {
      await controller.changeDecoyPassword(
        currentMasterPassword: currentMasterPassword,
        currentDecoyPassword: currentDecoyPassword,
        newDecoyPassword: newDecoyPassword,
      );
      if (!_isCurrent(epoch) || _vaultPhase != VaultPhase.unlocked) {
        return false;
      }
      _warningMessage = '诱饵密码已修改；原有诱饵内容保留，生物识别配置未改变。';
      return true;
    } on VaultPasswordUnchangedException {
      if (_isCurrent(epoch)) _errorMessage = '新诱饵密码不能与当前诱饵密码相同。';
      return false;
    } on DecoyPasswordConflictException {
      if (_isCurrent(epoch)) _errorMessage = '新诱饵密码不能与真实主密码相同。';
      return false;
    } on VaultCredentialRejectedException {
      if (_isCurrent(epoch)) {
        _errorMessage = '当前真实主密码或当前诱饵密码不正确。';
      }
      return false;
    } on VaultIntegrityException {
      if (_isCurrent(epoch)) {
        _errorMessage = '诱饵库完整性验证失败；原诱饵密码和真实数据均未被修改。';
      }
      return false;
    } on VaultUnlockException {
      if (_isCurrent(epoch)) _errorMessage = '无法验证当前诱饵库凭据。';
      return false;
    } on Object {
      if (_isCurrent(epoch)) {
        _errorMessage = '诱饵密码修改失败；原诱饵密码仍然有效，真实保险库未被修改。';
      }
      return false;
    } finally {
      _finishOperation(epoch);
    }
  }

  Future<VaultActionResult> unlockWithQuickUnlock() async {
    if (_vaultPhase != VaultPhase.locked || _busy || !_quickUnlockEnabled) {
      return VaultActionResult.rejected;
    }
    final epoch = ++_operationEpoch;
    beginExternalInteraction();
    _beginOperation(epoch);
    _errorMessage = null;
    _warningMessage = null;
    _quickUnlockFailureReason = null;
    _notify();
    VaultOpenResult? result;
    try {
      result = await _vaultStore.unlockWithQuickUnlock();
      if (!_isCurrent(epoch)) {
        result.session.close();
        return VaultActionResult.rejected;
      }
      result = await _upgradeLegacyOpenResult(result);
      if (!_isCurrent(epoch)) {
        result.session.close();
        return VaultActionResult.rejected;
      }
      _applyOpenResult(result);
      return VaultActionResult.success;
    } on QuickUnlockException catch (error) {
      await _recordQuickUnlockFailure(error, epoch, enabling: false);
      return VaultActionResult.rejected;
    } on VaultUnsupportedEnvelopeVersionException {
      if (_isCurrent(epoch)) {
        _errorMessage = '该加密库由更高版本应用创建；本版本已停止生物识别解锁，请升级应用。';
      }
      return VaultActionResult.rejected;
    } on VaultUnsupportedSchemaVersionException {
      if (_isCurrent(epoch)) {
        _errorMessage = '该数据由更高版本应用写入；本版本已停止生物识别解锁，请升级应用。';
      }
      return VaultActionResult.rejected;
    } on VaultUnsupportedKdfProfileException {
      if (_isCurrent(epoch)) {
        _errorMessage = '该加密库使用本版本不支持的密钥派生参数；本版本已停止生物识别解锁。';
      }
      return VaultActionResult.rejected;
    } on Object {
      if (_isCurrent(epoch)) {
        _quickUnlockFailureReason = QuickUnlockFailureReason.unknown;
        _errorMessage = '生物识别未完成或密钥已失效，请使用主密码解锁。';
      }
      return VaultActionResult.rejected;
    } finally {
      _finishOperation(epoch);
      endExternalInteraction();
    }
  }

  Future<Uint8List?> exportEncryptedBackup({
    required String backupMasterPassword,
  }) async {
    final session = _session;
    if (!_hasWritableSession || !_canManageSecurity || session == null) {
      return null;
    }
    try {
      return await _backupCodec.encryptV2(
        snapshot: _snapshot(),
        backupMasterPassword: backupMasterPassword,
        sourceSchemaVersion: VaultSnapshot.currentSchemaVersion,
      );
    } on ArgumentError catch (error) {
      _setContentError(error.message?.toString() ?? '备份密码强度不足。');
      return null;
    } on Object {
      _setContentError('无法生成加密备份文件。');
      return null;
    }
  }

  Future<EncryptedBackupPreview?> inspectEncryptedBackup({
    required List<int> bytes,
    required String backupMasterPassword,
  }) async {
    if (!hasFullVaultAccess ||
        !_canManageSecurity ||
        _vaultPhase != VaultPhase.unlocked ||
        _busy) {
      return null;
    }
    final epoch = _operationEpoch;
    _beginOperation(epoch);
    _errorMessage = null;
    _notify();
    try {
      final result = await _backupCodec.read(
        bytes: bytes,
        backupMasterPassword: backupMasterPassword,
      );
      if (!_isCurrent(epoch) || _vaultPhase != VaultPhase.unlocked) {
        return null;
      }
      final verifiedAt = DateTime.now().toUtc();
      final nextHealth = _backupHealth.copyWith(
        lastVerifiedAtUtc: verifiedAt,
        lastVerifiedFormatVersion: result.inspection.formatVersion,
      );
      try {
        await _backupHealthStore.write(nextHealth);
        _backupHealth = nextHealth;
      } on Object {
        // 备份本身已验证；健康时间写入失败不改变只读验证结果。
      }
      return EncryptedBackupPreview(
        accountCount: result.inspection.accountCount,
        subscriptionCount: result.inspection.subscriptionCount,
        formatVersion: result.inspection.formatVersion,
        sourceSchemaVersion: result.inspection.sourceSchemaVersion,
        backupId: result.inspection.backupId,
        createdAtUtc: result.inspection.createdAtUtc,
      );
    } on PortableBackupAuthenticationException {
      if (_isCurrent(epoch)) {
        _errorMessage = '备份密码错误，或文件已经损坏、被篡改。';
      }
      return null;
    } on PortableBackupFormatException {
      if (_isCurrent(epoch)) {
        _errorMessage = '备份文件格式无效、损坏或来自未来版本。';
      }
      return null;
    } on Object {
      if (_isCurrent(epoch)) {
        _errorMessage = '无法读取加密备份。';
      }
      return null;
    } finally {
      _finishOperation(epoch);
    }
  }

  Future<RebuildAuthorization?> authorizeRebuild(
    String title,
    String message,
  ) async {
    if (_vaultPhase != VaultPhase.locked || _busy) return null;
    try {
      return await _rebuildService?.platform.authorize(title, message);
    } on Object {
      _setContentError('系统身份验证未完成。');
      return null;
    }
  }

  Future<void> beginRebuildHold(RebuildAuthorization value) async {
    if (_vaultPhase == VaultPhase.locked) {
      await _rebuildService?.platform.beginHold(value.token);
    }
  }

  Future<void> cancelRebuildHold(RebuildAuthorization value) async {
    await _rebuildService?.platform.cancelHold(value.token);
  }

  Future<bool> rebuildLocalVault({
    required RebuildAuthorization authorization,
    required String phrase,
    String secondPhrase = '',
  }) async {
    final service = _rebuildService;
    if (_vaultPhase != VaultPhase.locked || _busy || service == null) {
      return false;
    }
    final epoch = _operationEpoch;
    _beginOperation(epoch);
    _notify();
    try {
      final committed = await service.commit(
        authorization: authorization,
        phrase: phrase,
        secondPhrase: secondPhrase,
      );
      if (!committed) return false;
      _clearSession();
      await initialize();
      return _vaultPhase == VaultPhase.needsSetup;
    } on Object {
      _vaultPhase = VaultPhase.error;
      _errorMessage = '重建未完成；若清理已开始，请重新打开应用继续完成。';
      return false;
    } finally {
      _finishOperation(epoch);
    }
  }

  Future<bool> configureAutoBackup({
    required String tree,
    required String backupPassword,
    required String confirmation,
    required String currentPassword,
    int intervalDays = 15,
  }) async {
    if (!isUnlocked ||
        !_canManageSecurity ||
        !hasFullVaultAccess ||
        _session is! DeviceBackupConfigSession ||
        backupPassword != confirmation) {
      return false;
    }
    final session = _session;
    if (!await verifyMasterPassword(currentPassword) ||
        !identical(session, _session)) {
      return false;
    }
    return autoBackup.configure(
      tree: tree,
      password: backupPassword,
      intervalDays: intervalDays,
    );
  }

  bool get canOpenCalendar =>
      isUnlocked &&
      hasFullVaultAccess &&
      !_busy &&
      _session is VaultBoundSession;
  CalendarReminderPlan? projectCalendar({required String singleRecordId}) {
    final session = _session;
    if (!canOpenCalendar || session is! VaultBoundSession) return null;
    return CalendarReminderPlan.build(
      records: _subscriptions,
      vaultBindingId: session.vaultBindingId,
      revision: session.generation,
      today: _now(),
      singleRecordId: singleRecordId,
    );
  }

  bool _calendarPlanCurrent(CalendarReminderPlan plan, VaultSession? session) =>
      isUnlocked &&
      hasFullVaultAccess &&
      identical(session, _session) &&
      session is VaultBoundSession &&
      session.vaultBindingId == plan.vaultBindingId &&
      session.generation == plan.revision &&
      subscriptionDateOnly(_now()) == plan.today;

  Future<CalendarInsertResult> insertCalendar(
    CalendarReminderPlan plan, {
    required NotificationPrivacy privacy,
    required CardockLanguage language,
    CalendarAlarm alarm = CalendarAlarm.oneDay,
    required bool disclosureConfirmed,
    CalendarBridge bridge = const AndroidCalendarBridge(),
  }) async {
    final session = _session;
    if (!disclosureConfirmed ||
        !canOpenCalendar ||
        !_calendarPlanCurrent(plan, session) ||
        plan.events.length != 1) {
      return CalendarInsertResult.failed;
    }
    return bridge.insert(
      plan.events.single,
      privacy: privacy,
      language: language,
      alarm: alarm,
    );
  }

  Future<bool> exportReadable({
    required ReadableExportOptions options,
    required String currentPassword,
    bool passwordDisclosureConfirmed = false,
    bool sensitiveFieldsDisclosureConfirmed = false,
    DocumentStorage storage = const AndroidDocumentStorage(),
  }) async {
    if (!isUnlocked ||
        !hasFullVaultAccess ||
        !_canManageSecurity ||
        _busy ||
        (options.includePasswords && !passwordDisclosureConfirmed) ||
        (options.includeSensitiveCustomFields &&
            !sensitiveFieldsDisclosureConfirmed)) {
      return false;
    }
    final session = _session;
    if (!await verifyCurrentVaultPassword(currentPassword) ||
        !identical(session, _session)) {
      return false;
    }
    final export = ReadableExport(_snapshot(), options);
    String? handle;
    var complete = false;
    try {
      final json = options.format == ReadableExportFormat.json;
      handle = await storage.beginExport(
        'Cardock-${export.exportedAt.millisecondsSinceEpoch}.${json ? 'json' : 'zip'}',
        json ? 'application/json' : 'application/zip',
      );
      if (handle == null) return false;
      if (!isUnlocked || !identical(session, _session)) return false;
      await for (final chunk in export.bytes()) {
        if (!isUnlocked || !identical(session, _session)) return false;
        for (var offset = 0; offset < chunk.length; offset += 65536) {
          if (!isUnlocked || !identical(session, _session)) return false;
          await storage.appendExport(
            handle,
            chunk.sublist(offset, min(offset + 65536, chunk.length)),
          );
        }
      }
      if (!isUnlocked || !identical(session, _session)) return false;
      await storage.finishExport(handle);
      complete = true;
      return true;
    } on Object {
      if (isUnlocked && identical(session, _session)) {
        _setContentError('可读导出未完成，请检查保存位置。');
      }
      return false;
    } finally {
      if (handle != null && !complete) {
        try {
          await storage.abortExport(handle);
        } on Object {
          /* provider may retain partial chosen document */
        }
      }
    }
  }

  Future<void> recordBackupExported() async {
    if (_vaultPhase != VaultPhase.unlocked ||
        !_canManageSecurity ||
        _disposed) {
      return;
    }
    final next = _backupHealth.copyWith(
      lastExportedAtUtc: DateTime.now().toUtc(),
    );
    try {
      await _backupHealthStore.write(next);
      _backupHealth = next;
      _notify();
    } on Object {
      // 文件保存结果仍由系统文件选择器决定；这里只是不记录健康时间。
    }
  }

  Future<bool> restoreEncryptedBackup({
    required List<int> bytes,
    required String backupMasterPassword,
    required String currentMasterPassword,
  }) async {
    final session = _session;
    if (!_hasWritableSession || session == null || !_canManageSecurity) {
      return false;
    }
    _recoveryRefreshToken += 1;
    final epoch = _operationEpoch;
    _beginOperation(epoch);
    _errorMessage = null;
    _notify();
    Uint8List? rollbackBytes;
    String? transactionId;
    try {
      rollbackBytes = await session.exportEncryptedBackup();
      await _vaultStore.readEncryptedBackup(
        bytes: rollbackBytes,
        masterPassword: currentMasterPassword,
      );
      if (!_isCurrent(epoch) || _vaultPhase != VaultPhase.unlocked) {
        return false;
      }
      final importedResult = await _backupCodec.read(
        bytes: bytes,
        backupMasterPassword: backupMasterPassword,
      );
      if (!_isCurrent(epoch) || _vaultPhase != VaultPhase.unlocked) {
        return false;
      }
      final imported = importedResult.snapshot.copyWith(
        preferences: importedResult.snapshot.preferences.copyWith(
          autoLockSeconds: _preferences.autoLockSeconds,
          notificationsEnabled: _preferences.notificationsEnabled,
        ),
      );
      final previousNotificationsEnabled = _anyNotificationsEnabled(
        _preferences,
      );
      final reminderPlanChanged = _reminderPlanChanged(imported);
      if (reminderPlanChanged) {
        await _prepareNotificationReconciliation(
          session,
          targetGeneration: session.generation + 1,
        );
      }

      transactionId = await _recoveryJournal.stage(
        encryptedVaultBytes: rollbackBytes,
        sourceGeneration: session.generation,
      );
      _recoveryState = VaultRecoveryState.prepared;

      var companionSyncFailed = false;
      try {
        await session.save(imported);
      } on VaultCompanionSyncException {
        companionSyncFailed = true;
        _quickUnlockEnabled = false;
        _quickUnlockScope = null;
      }
      if (!_isCurrent(epoch) || _vaultPhase != VaultPhase.unlocked) {
        return false;
      }
      var journalCommitted = false;
      try {
        await _recoveryJournal.markCommitted(transactionId);
        _recoveryState = VaultRecoveryState.committed;
        journalCommitted = true;
      } on Object {
        _recoveryState = VaultRecoveryState.prepared;
      }
      _replaceSnapshot(imported);
      final remindersSynced =
          !reminderPlanChanged ||
          await _syncReminders(
            imported,
            previousNotificationsEnabled: previousNotificationsEnabled,
          );
      _warningMessage = !journalCommitted
          ? '数据已写入，但恢复事务状态未能确认；加密回滚副本仍保留，请重新解锁核对。'
          : companionSyncFailed
          ? '加密备份已恢复，当前主密码和本机安全设置保持不变；订阅快捷视图同步失败，生物识别已停用。'
          : remindersSynced
          ? '加密备份已恢复；当前主密码和本机安全设置保持不变，并已保留恢复前加密回滚副本。'
          : '加密备份已恢复；当前主密码和本机安全设置保持不变。系统提醒同步失败，应用内日期仍为准。';
      return true;
    } on VaultUnlockException {
      if (_isCurrent(epoch)) {
        _errorMessage = '当前本机主密码不正确。';
      }
      return false;
    } on PortableBackupAuthenticationException {
      if (_isCurrent(epoch)) {
        _errorMessage = '备份密码错误，或文件已经损坏、被篡改。';
      }
      return false;
    } on PortableBackupFormatException {
      if (_isCurrent(epoch)) {
        _errorMessage = '备份文件格式无效、损坏或来自未来版本。';
      }
      return false;
    } on Object {
      if (_isCurrent(epoch)) {
        _errorMessage = transactionId == null
            ? '恢复失败；尚未开始替换本机数据。'
            : '恢复结果未能确认；恢复前加密回滚副本已保留，请重新解锁核对。';
      }
      return false;
    } finally {
      rollbackBytes?.fillRange(0, rollbackBytes.length, 0);
      _finishOperation(epoch);
    }
  }

  Future<bool> restoreLastRecoveryRollback({
    required String currentMasterPassword,
  }) async {
    final session = _session;
    if (!_hasWritableSession ||
        session == null ||
        !_canManageSecurity ||
        !hasRecoveryRollback) {
      return false;
    }
    _recoveryRefreshToken += 1;
    final epoch = _operationEpoch;
    _beginOperation(epoch);
    _errorMessage = null;
    _warningMessage = null;
    _notify();
    Uint8List? currentEnvelopeBytes;
    VaultRecoveryEntry? recovery;
    try {
      currentEnvelopeBytes = await session.exportEncryptedBackup();
      await _vaultStore.readEncryptedBackup(
        bytes: currentEnvelopeBytes,
        masterPassword: currentMasterPassword,
      );
      recovery = await _recoveryJournal.read();
      if (recovery == null) {
        _recoveryState = null;
        _errorMessage = '没有可用的恢复前回滚副本。';
        return false;
      }
      final previous = await _vaultStore.readEncryptedBackup(
        bytes: recovery.encryptedVaultBytes,
        masterPassword: currentMasterPassword,
      );
      final previousNotificationsEnabled = _anyNotificationsEnabled(
        _preferences,
      );
      final reminderPlanChanged = _reminderPlanChanged(previous);
      if (reminderPlanChanged) {
        await _prepareNotificationReconciliation(
          session,
          targetGeneration: session.generation + 1,
        );
      }
      var companionSyncFailed = false;
      try {
        await session.save(previous);
      } on VaultCompanionSyncException {
        companionSyncFailed = true;
        _quickUnlockEnabled = false;
        _quickUnlockScope = null;
      }
      if (!_isCurrent(epoch) || _vaultPhase != VaultPhase.unlocked) {
        return false;
      }
      // 主保险库已经完成原子写入后，先让可写内存状态与磁盘一致。
      // journal 只是恢复事务凭据；其状态更新失败不得留下旧 UI 快照，
      // 否则下一次编辑会把刚完成的回滚再次覆盖。
      _replaceSnapshot(previous);
      var journalRolledBack = false;
      try {
        await _recoveryJournal.markRolledBack(recovery.transactionId);
        _recoveryState = VaultRecoveryState.rolledBack;
        journalRolledBack = true;
      } on Object {
        _recoveryState = recovery.state;
      }
      if (reminderPlanChanged) {
        await _syncReminders(
          previous,
          previousNotificationsEnabled: previousNotificationsEnabled,
        );
      }
      _warningMessage = !journalRolledBack
          ? '已恢复到上次导入前的数据，但回滚事务状态未能确认；当前数据已生效，请重新解锁核对。'
          : companionSyncFailed
          ? '已恢复到上次导入前的数据；订阅快捷视图同步失败，生物识别已安全停用。'
          : '已恢复到上次导入前的数据。';
      return true;
    } on VaultUnlockException {
      if (_isCurrent(epoch)) _errorMessage = '当前本机主密码不正确。';
      return false;
    } on Object {
      if (_isCurrent(epoch)) {
        _errorMessage = '无法使用恢复前回滚副本；当前数据未被确认替换。';
      }
      return false;
    } finally {
      recovery?.destroy();
      currentEnvelopeBytes?.fillRange(0, currentEnvelopeBytes.length, 0);
      _finishOperation(epoch);
    }
  }

  void beginExternalInteraction() {
    _externalInteractionDepth += 1;
    _notify();
  }

  void endExternalInteraction() {
    if (_externalInteractionDepth > 0) {
      _externalInteractionDepth -= 1;
      _notify();
    }
  }

  Future<ImportCommitResult> commitBatchImport(ImportPlan plan) async {
    final session = _session;
    final scopeId = _importVaultScopeId;
    if (!_hasWritableSession ||
        !_canManageSecurity ||
        session is! BatchRollbackVaultSession ||
        scopeId == null) {
      return _failedImportCommit(plan, 'vault_not_writable');
    }
    if (plan.vaultScopeId != scopeId ||
        plan.expectedVaultRevision != session.generation) {
      return _failedImportCommit(plan, 'stale_preview');
    }
    if (!plan.canCommit ||
        !plan.hasWriteOperations ||
        plan.quota.requestedAccounts != plan.newAccounts.length ||
        plan.quota.requestedSubscriptions != plan.formalSubscriptions.length) {
      return _failedImportCommit(plan, 'plan_not_committable');
    }
    final finalAccountCount = _accounts.length + plan.newAccounts.length;
    final finalSubscriptionCount =
        _subscriptions.length + plan.formalSubscriptions.length;
    if (!productEntitlement.hasFullVersion &&
        (finalAccountCount > EntitlementGuard.maxAccounts ||
            finalSubscriptionCount > EntitlementGuard.maxSubscriptions)) {
      return _failedImportCommit(plan, 'quota_changed');
    }

    try {
      final before = _snapshot();
      final now = DateTime.now().toUtc();
      final nextAccounts = <AccountRecord>[..._accounts];
      final accountAliases = <String, String>{
        for (final account in _accounts) account.id: account.id,
      };
      final uniquelyNamedAccounts = <String, List<AccountRecord>>{};
      for (final account in _accounts) {
        uniquelyNamedAccounts
            .putIfAbsent(_importKey(account.platformName), () => [])
            .add(account);
      }
      for (final entry in uniquelyNamedAccounts.entries) {
        if (entry.value.length == 1) {
          accountAliases[entry.key] = entry.value.single.id;
        }
      }

      final updatedIds = <String>{};
      for (final update in plan.accountUpdates) {
        final existingId = update.existingAccountId;
        if (existingId == null || !updatedIds.add(existingId)) {
          throw const FormatException('重复更新决议无效');
        }
        final index = nextAccounts.indexWhere(
          (account) => account.id == existingId,
        );
        if (index < 0 ||
            (update.resolution !=
                    ImportDuplicateResolution.fillEmptyFieldsOnly &&
                update.resolution != ImportDuplicateResolution.fieldByField)) {
          throw const FormatException('重复更新决议无效');
        }
        final existing = nextAccounts[index];
        nextAccounts[index] = _mergeImportedAccount(
          existing,
          update,
          nowUtc: now,
        );
        _registerAccountAliases(accountAliases, update.draft, existingId);
      }

      var nextAccountId = _nextAccountId;
      final newSourceIds = <String>{};
      final newAccountKeys = <String>{};
      for (final imported in plan.newAccounts) {
        if (!newSourceIds.add(imported.sourceId) ||
            (imported.accountKey != null &&
                !newAccountKeys.add(_importKey(imported.accountKey!)))) {
          throw const FormatException('批量账号标识重复');
        }
        final importedDraft = _accountDraftFromImport(imported);
        final record = AccountRecord.fromDraft(
          id: 'account-$nextAccountId',
          draft: importedDraft,
          passwordStoredAtUtc: importedDraft.password == null ? null : now,
          passwordSyncState: importedDraft.password == null
              ? PasswordSyncState.unknown
              : PasswordSyncState.needsReview,
        );
        nextAccountId += 1;
        nextAccounts.add(record);
        _registerAccountAliases(accountAliases, imported, record.id);
      }
      for (final skipped in plan.skippedAccounts) {
        final match = _matchingExistingAccount(skipped, nextAccounts);
        if (match != null) {
          _registerAccountAliases(accountAliases, skipped, match.id);
        }
      }

      final nextSubscriptions = <SubscriptionRecord>[..._subscriptions];
      var nextSubscriptionId = _nextSubscriptionId;
      final subscriptionSourceIds = <String>{};
      for (final imported in plan.formalSubscriptions) {
        if (!subscriptionSourceIds.add(imported.sourceId) ||
            !imported.isSyntacticallyComplete) {
          throw const FormatException('正式订阅计划无效');
        }
        final account = _resolveSubscriptionImportAccount(
          imported,
          accounts: nextAccounts,
          aliases: accountAliases,
        );
        if (account == null) throw const FormatException('订阅关联账号不存在');
        nextSubscriptions.add(
          _formalSubscriptionFromImport(
            imported,
            id: 'subscription-$nextSubscriptionId',
            account: account,
          ),
        );
        nextSubscriptionId += 1;
      }

      final nextPending = <PendingSubscriptionDraft>[
        ..._pendingSubscriptionDrafts,
      ];
      var pendingOrdinal = 0;
      for (final imported in plan.pendingSubscriptionDrafts) {
        if (!subscriptionSourceIds.add(imported.sourceId)) {
          throw const FormatException('订阅导入标识重复');
        }
        final account = _resolveSubscriptionImportAccount(
          imported,
          accounts: nextAccounts,
          aliases: accountAliases,
        );
        if (account == null) {
          throw const FormatException('待完善订阅关联账号不存在');
        }
        nextPending.add(
          _pendingDraftFromImport(
            imported,
            draftId:
                'pending-${session.generation}-${now.microsecondsSinceEpoch}-${pendingOrdinal++}',
            accountId: account.id,
            now: now,
          ),
        );
      }

      final after = _snapshot(
        nextAccountId: nextAccountId,
        accounts: nextAccounts,
        nextSubscriptionId: nextSubscriptionId,
        subscriptions: nextSubscriptions,
        pendingSubscriptionDrafts: nextPending,
      );
      if (session.generation != plan.expectedVaultRevision ||
          plan.vaultScopeId != _importVaultScopeId) {
        return _failedImportCommit(plan, 'stale_preview');
      }
      final saved = await _persistSnapshot(
        after,
        batchRollbackBefore: before,
        failureMessage: '批量导入未能原子写入本机加密库。',
      );
      if (!saved) return _failedImportCommit(plan, 'storage_failed');
      if (_vaultPhase == VaultPhase.unlocked && identical(_session, session)) {
        _lastBatchRollbackImpact = BatchRollbackImpact(
          addedAccountCount: plan.newAccounts.length,
          updatedAccountCount: plan.accountUpdates.length,
          formalSubscriptionCount: plan.formalSubscriptions.length,
          pendingSubscriptionDraftCount: plan.pendingSubscriptionDrafts.length,
        );
      }
      return ImportCommitResult(
        success: true,
        addedAccountCount: plan.newAccounts.length,
        updatedAccountCount: plan.accountUpdates.length,
        skippedCount: plan.skippedAccounts.length,
        formalSubscriptionCount: plan.formalSubscriptions.length,
        pendingSubscriptionDraftCount: plan.pendingSubscriptionDrafts.length,
        unsupportedItemCount: plan.unsupportedItemCount,
        resultingVaultRevision: session.generation,
        rollbackAvailable: session.canUndoLastBatch,
      );
    } on ArgumentError {
      return _failedImportCommit(plan, 'validation_failed');
    } on FormatException {
      return _failedImportCommit(plan, 'validation_failed');
    } on VaultFormatException {
      return _failedImportCommit(plan, 'validation_failed');
    }
  }

  Future<bool> undoLastBatchImport() async {
    final session = _session;
    if (!_hasWritableSession ||
        session is! BatchRollbackVaultSession ||
        !session.canUndoLastBatch) {
      return false;
    }
    final epoch = _operationEpoch;
    _beginOperation(epoch);
    _errorMessage = null;
    _notify();
    try {
      final previousNotificationsEnabled = _anyNotificationsEnabled(
        _preferences,
      );
      final rollbackImpact = lastBatchRollbackImpact;
      // 撤销真正会影响启用中的提醒类型时才预写 outbox；账号-only 导入且
      // 仅开启订阅提醒时不得制造虚假的待协调状态。
      final rollbackMayChangeReminderPlan = rollbackImpact == null
          ? previousNotificationsEnabled
          : (_preferences.notificationsEnabled &&
                    rollbackImpact.formalSubscriptionCount > 0) ||
                (_preferences.passwordReviewNotificationsEnabled &&
                    (rollbackImpact.addedAccountCount > 0 ||
                        rollbackImpact.updatedAccountCount > 0));
      if (rollbackMayChangeReminderPlan) {
        await _prepareNotificationReconciliation(
          session,
          targetGeneration: session.generation + 1,
        );
      }
      final previous = await session.undoLastBatch();
      if (!_isCurrent(epoch) || _vaultPhase != VaultPhase.unlocked) {
        return false;
      }
      final reminderPlanChanged = _reminderPlanChanged(previous);
      _replaceSnapshot(previous);
      _lastBatchRollbackImpact = null;
      if (reminderPlanChanged) {
        await _syncReminders(
          previous,
          previousNotificationsEnabled: previousNotificationsEnabled,
        );
      }
      return true;
    } on Object {
      if (_isCurrent(epoch) && _vaultPhase == VaultPhase.unlocked) {
        _errorMessage = '最近一次批量导入无法撤销；当前加密库未被改写。';
      }
      return false;
    } finally {
      _finishOperation(epoch);
    }
  }

  Future<bool> discardLastBatchImportRollback() async {
    final session = _session;
    if (!_hasWritableSession ||
        session is! BatchRollbackVaultSession ||
        session.batchRollbackAvailability == BatchRollbackAvailability.none) {
      return false;
    }
    final epoch = _operationEpoch;
    _beginOperation(epoch);
    _errorMessage = null;
    _notify();
    try {
      await session.discardLastBatchRollback();
      if (!_isCurrent(epoch) || _vaultPhase != VaultPhase.unlocked) {
        return true;
      }
      _lastBatchRollbackImpact = null;
      _warningMessage = '最近一次批量导入回滚点已丢弃；当前业务数据未改变。';
      return true;
    } on Object {
      if (_isCurrent(epoch) && _vaultPhase == VaultPhase.unlocked) {
        _errorMessage = '批量导入回滚点未能安全丢弃；当前业务数据未改变。';
      }
      return false;
    } finally {
      _finishOperation(epoch);
    }
  }

  static ImportCommitResult _failedImportCommit(ImportPlan plan, String code) =>
      ImportCommitResult(
        success: false,
        addedAccountCount: 0,
        updatedAccountCount: 0,
        skippedCount: 0,
        formalSubscriptionCount: 0,
        pendingSubscriptionDraftCount: 0,
        unsupportedItemCount: plan.unsupportedItemCount,
        failureCode: code,
      );

  static AccountDraft _accountDraftFromImport(AccountImportDraft imported) =>
      AccountDraft(
        platformName: imported.platformName,
        loginAccount: imported.loginAccount,
        boundPhone: imported.phone,
        boundEmail: imported.email,
        password: imported.password,
        website: imported.url,
        notes: imported.notes,
        customFields: mergeImportedCustomFields(const [], imported),
      );

  static AccountRecord _mergeImportedAccount(
    AccountRecord existing,
    AccountUpdatePlan update, {
    required DateTime nowUtc,
  }) {
    final imported = update.draft;
    final fillEmpty =
        update.resolution == ImportDuplicateResolution.fillEmptyFieldsOnly;

    String? choose(String field, String? current, String incoming) {
      final normalized = incoming.trim();
      if (fillEmpty) {
        return current == null || current.trim().isEmpty
            ? (normalized.isEmpty ? null : normalized)
            : current;
      }
      if (update.useImportedField[field] != true || normalized.isEmpty) {
        return current;
      }
      return normalized;
    }

    final platformName =
        fillEmpty ||
            update.useImportedField['platformName'] != true ||
            imported.platformName.trim().isEmpty
        ? existing.platformName
        : imported.platformName;
    final password =
        fillEmpty ||
            update.useImportedField['password'] != true ||
            imported.password.isEmpty
        ? existing.password
        : imported.password;
    final passwordChanged = password != existing.password;
    final importedNotes = imported.notes.trim();
    final notes = fillEmpty
        ? choose('notes', existing.notes, imported.notes)
        : update.useImportedField['notes'] == true && importedNotes.isNotEmpty
        ? existing.notes == null || existing.notes!.trim().isEmpty
              ? importedNotes
              : '${existing.notes}\n$importedNotes'
        : existing.notes;
    return AccountRecord.fromDraft(
      id: existing.id,
      draft: AccountDraft(
        platformName: platformName,
        category: existing.category,
        loginAccount: choose(
          'loginAccount',
          existing.loginAccount,
          imported.loginAccount,
        ),
        username: existing.username,
        boundPhone: choose('phone', existing.boundPhone, imported.phone),
        boundEmail: choose('email', existing.boundEmail, imported.email),
        password: password,
        website: choose('url', existing.website, imported.url),
        notes: notes,
        customFields: mergeImportedCustomFields(
          existing.customFields,
          imported,
        ),
      ),
      passwordValueRevision: existing.revisionAfterPasswordSave(password),
      passwordChangeHistory: existing.historyAfterPasswordSave(
        password,
        nowUtc,
      ),
      passwordStoredAtUtc: passwordChanged
          ? nowUtc
          : existing.passwordStoredAtUtc,
      passwordSyncState: passwordChanged
          ? PasswordSyncState.needsReview
          : existing.passwordSyncState,
      passwordVerifiedAtUtc: existing.passwordVerifiedAtUtc,
      platformPasswordChangedAtUtc: existing.platformPasswordChangedAtUtc,
      passwordReviewIntervalDays: existing.passwordReviewIntervalDays,
      passwordReviewSnoozedUntilUtc: passwordChanged
          ? null
          : existing.passwordReviewSnoozedUntilUtc,
    );
  }

  static void _registerAccountAliases(
    Map<String, String> aliases,
    AccountImportDraft draft,
    String accountId,
  ) {
    aliases[_importKey(draft.sourceId)] = accountId;
    final key = draft.accountKey;
    if (key != null && key.trim().isNotEmpty) {
      aliases[_importKey(key)] = accountId;
    }
  }

  static AccountRecord? _matchingExistingAccount(
    AccountImportDraft draft,
    List<AccountRecord> accounts,
  ) {
    final platform = _importKey(draft.platformName);
    final login = _importKey(draft.loginAccount);
    final matches = accounts
        .where((account) {
          if (_importKey(account.platformName) != platform) return false;
          return login.isEmpty ||
              _importKey(account.loginAccount ?? '') == login;
        })
        .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }

  static String _importKey(String value) => value.trim().toLowerCase();

  static AccountRecord? _resolveSubscriptionImportAccount(
    SubscriptionImportDraft imported, {
    required List<AccountRecord> accounts,
    required Map<String, String> aliases,
  }) {
    final explicitTarget = imported.targetExistingAccountId;
    final accountId = explicitTarget != null && explicitTarget.isNotEmpty
        ? explicitTarget
        : aliases[_importKey(imported.accountKey)];
    return accounts.where((candidate) => candidate.id == accountId).firstOrNull;
  }

  static SubscriptionRecord _formalSubscriptionFromImport(
    SubscriptionImportDraft imported, {
    required String id,
    required AccountRecord account,
  }) {
    final cycle = _parseBillingCycle(imported.billingCycle);
    final start = parseSubscriptionDate(imported.subscriptionStartDate.trim());
    final renewal = parseSubscriptionDate(imported.nextRenewalDate.trim());
    final autoRenew = _parseImportBool(imported.autoRenew);
    final payment = imported.paymentMethod.trim();
    final amount = imported.amount.trim();
    final currency = imported.currency.trim().toUpperCase();
    if (cycle == null ||
        autoRenew == null ||
        imported.planName.trim().isEmpty ||
        payment.isEmpty ||
        amount.isEmpty ||
        !RegExp(r'^\d+(?:\.\d+)?$').hasMatch(amount) ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const FormatException('正式订阅字段不完整');
    }
    final reminder = int.tryParse(imported.reminderDays.trim());
    if (reminder == null || reminder < 0 || reminder > 365) {
      throw const FormatException('提醒天数无效');
    }
    return SubscriptionRecord.fromDraft(
      id: id,
      draft: SubscriptionDraft(
        accountId: account.id,
        details: SubscriptionDetailsDraft(
          serviceName: account.platformName,
          planName: imported.planName,
          amount: amount,
          currency: currency,
          firstSubscribedOn: start,
          nextRenewalOn: renewal,
          cycleCount: cycle.count,
          cycleUnit: cycle.unit,
          autoRenew: autoRenew,
          paymentMethod: payment,
          notes: imported.notes,
          expenseCategory: account.category,
          reminderDaysBefore: reminder,
        ),
      ),
    );
  }

  static PendingSubscriptionDraft _pendingDraftFromImport(
    SubscriptionImportDraft imported, {
    required String draftId,
    required String accountId,
    required DateTime now,
  }) {
    final currency = imported.currency.trim().toUpperCase();
    final reminder = int.tryParse(imported.reminderDays.trim());
    DateTime? parseOptionalImportDate(String raw) {
      final value = raw.trim();
      if (value.isEmpty) return null;
      try {
        return parseSubscriptionDate(value);
      } on FormatException {
        return null;
      }
    }

    final start = parseOptionalImportDate(imported.subscriptionStartDate);
    final renewal = parseOptionalImportDate(imported.nextRenewalDate);
    return PendingSubscriptionDraft(
      draftId: draftId,
      accountId: accountId,
      planName: imported.planName,
      amount: imported.amount,
      currency: RegExp(r'^[A-Z]{3}$').hasMatch(currency) ? currency : null,
      billingCycle: _parseBillingCycle(imported.billingCycle),
      subscriptionStartDate: start,
      nextRenewalDate: renewal,
      autoRenew: _parseImportBool(imported.autoRenew),
      paymentMethod: imported.paymentMethod,
      reminderDays: reminder != null && reminder >= 0 && reminder <= 365
          ? reminder
          : null,
      notes: imported.notes,
      createdAt: now,
      updatedAt: now,
    );
  }

  static PendingSubscriptionBillingCycle? _parseBillingCycle(String raw) {
    final value = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (value.isEmpty) return null;
    final canonical = normalizeSubscriptionBillingCycle(value);
    final stableCycle = switch (canonical) {
      'monthly' => const PendingSubscriptionBillingCycle(
        count: 1,
        unit: SubscriptionCycleUnit.month,
      ),
      'quarterly' => const PendingSubscriptionBillingCycle(
        count: 3,
        unit: SubscriptionCycleUnit.month,
      ),
      'semiannual' => const PendingSubscriptionBillingCycle(
        count: 6,
        unit: SubscriptionCycleUnit.month,
      ),
      'annual' => const PendingSubscriptionBillingCycle(
        count: 1,
        unit: SubscriptionCycleUnit.year,
      ),
      // custom 不包含明确 count/unit，权威提交不得猜值。
      'custom' || null => null,
      _ => null,
    };
    if (stableCycle != null || canonical == 'custom') return stableCycle;
    final match = RegExp(
      r'^(\d+)?\s*(day|days|daily|天|week|weeks|weekly|周|month|months|monthly|月|year|years|yearly|annual|年)$',
    ).firstMatch(value);
    if (match == null) return null;
    final count = int.tryParse(match.group(1) ?? '1');
    if (count == null || count < 1 || count > 120) return null;
    final unit = switch (match.group(2)) {
      'day' || 'days' || 'daily' || '天' => SubscriptionCycleUnit.day,
      'week' || 'weeks' || 'weekly' || '周' => SubscriptionCycleUnit.week,
      'month' || 'months' || 'monthly' || '月' => SubscriptionCycleUnit.month,
      'year' ||
      'years' ||
      'yearly' ||
      'annual' ||
      '年' => SubscriptionCycleUnit.year,
      _ => null,
    };
    return unit == null
        ? null
        : PendingSubscriptionBillingCycle(count: count, unit: unit);
  }

  static bool? _parseImportBool(String raw) =>
      parseSubscriptionAutoRenew(raw) ??
      switch (raw.trim().toLowerCase()) {
        'y' => true,
        'n' => false,
        _ => null,
      };

  List<PaymentMethodRecord> _paymentMethods = [];
  List<PaymentMethodRecord> get paymentMethods =>
      List.unmodifiable(_paymentMethods);

  Future<bool> saveSubscriptionManagement(
    String id,
    SubscriptionManagement management,
  ) async {
    if (!_hasWritableSession) return false;
    final sub = _subscriptions.where((s) => s.id == id).firstOrNull;
    if (sub == null) return false;
    return updateSubscription(
      subscriptionId: id,
      draft: SubscriptionDraft(
        accountId: sub.accountId,
        details: sub.details.copyWith(management: management),
      ),
    );
  }

  Future<bool> resolveTrial({
    required String subscriptionId,
    required TrialOutcome outcome,
    DateTime? actualPaidOn,
    String? actualAmount,
    String? actualCurrency,
    bool paymentConfirmed = false,
  }) => _managementTransaction(
    (s) => management_actions.resolveSubscriptionTrial(
      s,
      subscriptionId: subscriptionId,
      outcome: outcome,
      now: DateTime.now(),
      actualPaidOn: actualPaidOn,
      actualAmount: actualAmount,
      actualCurrency: actualCurrency,
      paymentConfirmed: paymentConfirmed,
    ),
  );

  Future<bool> confirmTrialPayment(String id, DateTime paidOn) =>
      _managementTransaction(
        (s) => management_actions.confirmTrialCharge(
          s,
          subscriptionId: id,
          paidOn: paidOn,
          now: DateTime.now(),
        ),
      );
  Future<bool> savePaymentMethod(PaymentMethodRecord method) =>
      _managementTransaction(
        (s) => management_actions.savePaymentMethod(s, method),
      );
  Future<bool> mergePaymentMethods(String fromId, String intoId) =>
      _managementTransaction(
        (s) => management_actions.mergePaymentMethods(
          s,
          fromId: fromId,
          intoId: intoId,
        ),
      );
  Future<bool> deletePaymentMethod(String id) => _managementTransaction(
    (s) => management_actions.deletePaymentMethod(s, id),
  );

  Future<bool> _managementTransaction(
    VaultSnapshot Function(VaultSnapshot) change,
  ) async {
    if (!_hasWritableSession) return false;
    try {
      return await _persistSnapshot(
        change(_snapshot()),
        failureMessage: '订阅管理修改未能保存，原记录保持不变。',
      );
    } on Object {
      _setContentError('订阅管理内容无效或已处理，请检查后重试。');
      return false;
    }
  }

  Future<bool> ignorePasswordHealth(PasswordHealthFinding requested) async {
    if (!_hasWritableSession) return false;
    final current = accountAnalysis.healthFindings
        .where((f) => f.key == requested.key)
        .firstOrNull;
    if (current == null ||
        current.passwordValueRevision != requested.passwordValueRevision ||
        current.basis != requested.basis ||
        !mapEquals(current.memberRevisions, requested.memberRevisions)) {
      return false;
    }
    if (current.ignored) return true;
    return _persistSnapshot(
      _snapshot(
        passwordHealthIgnoreRules: [
          ..._passwordHealthIgnoreRules.where(
            (rule) => rule.key != current.key,
          ),
          current.toIgnoreRule(),
        ],
      ),
      failureMessage: '健康提示忽略未能保存，原状态保持不变。',
    );
  }

  Future<bool> restorePasswordHealthHint(
    String accountId,
    String issueType,
  ) async {
    if (!_hasWritableSession) return false;
    final key = '$accountId:$issueType';
    if (!_passwordHealthIgnoreRules.any((rule) => rule.key == key)) return true;
    return _persistSnapshot(
      _snapshot(
        passwordHealthIgnoreRules: _passwordHealthIgnoreRules
            .where((rule) => rule.key != key)
            .toList(),
      ),
      failureMessage: '恢复健康提示失败，原状态保持不变。',
    );
  }

  Future<bool> createBindingRetirementPlan(BindingGroup requested) async {
    if (!_hasWritableSession) return false;
    final group = accountAnalysis.bindingGroups
        .where((g) => g.key == requested.key)
        .firstOrNull;
    if (group == null ||
        _bindingRetirementPlans.any(
          (p) =>
              !p.isClosed &&
              p.type == group.type &&
              p.normalizedValue == group.normalizedValue,
        )) {
      return false;
    }
    final plan = BindingRetirementPlan(
      id: _newImportVaultScopeId(),
      type: group.type,
      targetValue: group.targetValue,
      normalizedValue: group.normalizedValue,
      createdAtUtc: _now().toUtc(),
      accountIds: {...group.activeAccountIds, ...group.trashAccountIds},
    );
    return _persistSnapshot(
      _snapshot(bindingRetirementPlans: [..._bindingRetirementPlans, plan]),
      failureMessage: '停用计划未能保存，原记录保持不变。',
    );
  }

  Future<bool> closeBindingRetirementPlan(
    String planId, {
    bool delete = false,
  }) async {
    if (!_hasWritableSession) return false;
    final progress = accountAnalysis.bindingPlans
        .where((p) => p.plan.id == planId)
        .firstOrNull;
    if (progress == null || progress.pendingAccountIds.isNotEmpty) return false;
    return _persistSnapshot(
      _snapshot(
        bindingRetirementPlans: [
          for (final plan in _bindingRetirementPlans)
            if (plan.id != planId)
              plan
            else if (!delete)
              plan.copyWith(closedAtUtc: _now().toUtc()),
        ],
      ),
      failureMessage: '停用计划更新失败，原状态保持不变。',
    );
  }

  AccountBatchImpact previewAccountBatchImpact(Set<String> accountIds) {
    if (!isUnlocked || !hasFullVaultAccess) {
      return const AccountBatchImpact(0, 0, 0);
    }
    return AccountBatchImpact(
      _accounts.where((a) => accountIds.contains(a.id)).length,
      _subscriptions.where((s) => accountIds.contains(s.accountId)).length,
      _pendingSubscriptionDrafts
          .where((d) => accountIds.contains(d.accountId))
          .length,
    );
  }

  Future<bool> batchUpdateAccountCategory(
    Set<String> accountIds,
    String? category, {
    int? expectedRevision,
  }) async {
    if (!_hasWritableSession ||
        accountIds.isEmpty ||
        expectedRevision != null && expectedRevision != localWebRevision ||
        previewAccountBatchImpact(accountIds).accountCount !=
            accountIds.length) {
      return false;
    }
    try {
      var normalized = AccountDraft(
        platformName: 'category-validation',
        category: category,
      ).category;
      normalized =
          accountCategoryOptions(_accounts)
              .where((c) => c.toLowerCase() == normalized?.toLowerCase())
              .firstOrNull ??
          normalized;
      final accounts = _accounts.map((a) {
        if (!accountIds.contains(a.id)) return a;
        final json = a.toEncryptedPayloadJson()..['category'] = normalized;
        return AccountRecord.fromEncryptedPayloadJson(json);
      }).toList();
      final session = _session;
      final saved = await _persistSnapshot(
        _snapshot(accounts: accounts),
        failureMessage: '批量分类失败，所有原记录保持不变。',
      );
      if (saved) await _backupAfterAccountBatch(session);
      return saved;
    } on Object {
      _setContentError('批量分类失败，所有原记录保持不变。');
      return false;
    }
  }

  Future<bool> batchMoveAccountsToTrash(
    Set<String> accountIds, {
    int? expectedRevision,
  }) async {
    if (!_hasWritableSession ||
        accountIds.isEmpty ||
        expectedRevision != null && expectedRevision != localWebRevision ||
        previewAccountBatchImpact(accountIds).accountCount !=
            accountIds.length) {
      return false;
    }
    try {
      final next = VaultTrash.moveAccounts(
        _snapshot(),
        accountIds: accountIds,
        now: _now(),
        batchId: _newImportVaultScopeId(),
      );
      final session = _session;
      final saved = await _persistSnapshot(
        next,
        failureMessage: '批量回收失败，所有原记录保持不变。',
      );
      if (saved) await _backupAfterAccountBatch(session);
      return saved;
    } on Object {
      _setContentError('批量回收失败，所有原记录保持不变。');
      return false;
    }
  }

  Future<void> _backupAfterAccountBatch(VaultSession? session) async {
    if (!identical(session, _session) ||
        !isUnlocked ||
        !_canManageSecurity ||
        !autoBackup.status.enabled) {
      return;
    }
    try {
      await autoBackup.observe(_snapshot());
      if (!identical(session, _session) || !isUnlocked || !_canManageSecurity) {
        return;
      }
      final success = await autoBackup.requestImmediate();
      if (!success && identical(session, _session) && isUnlocked) {
        _warningMessage = '批量操作已保存，但立即自动备份未完成，请在数据安全与备份核对。';
        _notify();
      }
    } on Object {
      if (identical(session, _session) && isUnlocked) {
        _warningMessage = '批量操作已保存，但立即自动备份未完成，请在数据安全与备份核对。';
        _notify();
      }
    }
  }

  VaultSnapshot _snapshot({
    int? nextAccountId,
    List<AccountRecord>? accounts,
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
    nextAccountId: nextAccountId ?? _nextAccountId,
    accounts: accounts ?? _accounts,
    passwordHealthIgnoreRules:
        passwordHealthIgnoreRules ?? _passwordHealthIgnoreRules,
    bindingRetirementPlans: bindingRetirementPlans ?? _bindingRetirementPlans,
    paymentMethods: _paymentMethods,
    trashAccounts: trashAccounts ?? _trashAccounts,
    trashSubscriptions: trashSubscriptions ?? _trashSubscriptions,
    nextSubscriptionId: nextSubscriptionId ?? _nextSubscriptionId,
    subscriptions: subscriptions ?? _subscriptions,
    nextExpenseId: nextExpenseId ?? _nextExpenseId,
    subscriptionExpenses: subscriptionExpenses ?? _subscriptionExpenses,
    pendingSubscriptionDrafts:
        pendingSubscriptionDrafts ?? _pendingSubscriptionDrafts,
    preferences: preferences ?? _preferences,
    recentAccountIds: recentAccountIds ?? _recentAccountIds,
  );

  Future<bool> _persistSnapshot(
    VaultSnapshot snapshot, {
    required String failureMessage,
    VaultSnapshot? batchRollbackBefore,
  }) async {
    final session = _session;
    if (!_hasWritableSession || session == null) {
      return false;
    }

    try {
      snapshot = normalizeAccountSecurityMetadata(snapshot, _now());
      snapshot = normalizeSubscriptionMetadata(snapshot);
      final ledger = recordSubscriptionActions(
        previousSubscriptions: [
          ..._subscriptions,
          ..._trashSubscriptions.map((e) => e.record),
        ],
        subscriptions: snapshot.subscriptions,
        accounts: snapshot.accounts,
        expenses: snapshot.subscriptionExpenses,
        nextExpenseId: snapshot.nextExpenseId,
      );
      snapshot = snapshot.copyWith(
        nextExpenseId: ledger.nextExpenseId,
        subscriptionExpenses: ledger.expenses,
      );
    } on Object {
      _setContentError('费用记录未能保存，原订阅保持不变。');
      return false;
    }
    final previousNotificationsEnabled = _anyNotificationsEnabled(_preferences);
    final reminderPlanChanged = _reminderPlanChanged(snapshot);
    final epoch = _operationEpoch;
    _beginOperation(epoch);
    _errorMessage = null;
    _notify();
    try {
      if (reminderPlanChanged) {
        await _prepareNotificationReconciliation(
          session,
          targetGeneration: session.generation + 1,
        );
      }
      if (batchRollbackBefore == null) {
        await session.save(snapshot);
      } else if (session is BatchRollbackVaultSession) {
        await session.saveBatchWithRollback(
          before: batchRollbackBefore,
          after: snapshot,
        );
      } else {
        throw const VaultBatchRollbackUnavailableException();
      }
      if (!_isCurrent(epoch) || _vaultPhase != VaultPhase.unlocked) {
        // save Future 已正常返回，主加密快照已经提交。锁定只阻止 UI 回填与
        // 提醒同步，不能把 durable success 反向误报为零写入。
        return true;
      }
      _replaceSnapshot(snapshot);
      if (batchRollbackBefore == null) _lastBatchRollbackImpact = null;
      if (reminderPlanChanged) {
        await _syncReminders(
          snapshot,
          previousNotificationsEnabled: previousNotificationsEnabled,
        );
      }
      return true;
    } on VaultCompanionSyncException {
      if (_isCurrent(epoch) && _vaultPhase == VaultPhase.unlocked) {
        _replaceSnapshot(snapshot);
        if (batchRollbackBefore == null) _lastBatchRollbackImpact = null;
        _quickUnlockEnabled = false;
        _quickUnlockScope = null;
        _warningMessage = '记录已保存，但订阅快捷视图未能同步；生物识别已安全停用，请用主密码重新启用。';
        if (reminderPlanChanged) {
          await _syncReminders(
            snapshot,
            previousNotificationsEnabled: previousNotificationsEnabled,
          );
        }
        return true;
      }
      // VaultCompanionSyncException 只会在主库提交后发生；若锁定已使 epoch
      // 失效，保持敏感内存为空，同时仍准确报告主库持久化成功。
      return true;
    } on Object {
      if (_isCurrent(epoch) && _vaultPhase == VaultPhase.unlocked) {
        _errorMessage = failureMessage;
      }
      return false;
    } finally {
      _finishOperation(epoch);
    }
  }

  Future<bool> _syncReminders(
    VaultSnapshot snapshot, {
    bool previousNotificationsEnabled = false,
    bool preserveOtherNotifications = false,
  }) async {
    final session = _session;
    if (_vaultPhase != VaultPhase.unlocked ||
        session == null ||
        !_canManageSecurity) {
      // 设备级通知队列只由真实主库会话管理。
      return true;
    }

    // Submit while the real-vault session is authorized, before the first
    // storage await. Background locking must not abandon a saved schedule.
    // The scheduler serializes submissions, so later edits/cancellations win.
    final Future<bool>? submitted =
        _anyNotificationsEnabled(snapshot.preferences)
        ? (() async {
            try {
              await _reminderScheduler.rescheduleAll(
                snapshot.preferences.notificationsEnabled
                    ? snapshot.subscriptions
                    : const <SubscriptionRecord>[],
                reminderTimeMinutes:
                    snapshot.preferences.defaultReminderTimeMinutes,
                secondReminderTimeMinutes:
                    snapshot.preferences.secondReminderTimeMinutes,
                passwordReviewAtUtc:
                    snapshot.preferences.passwordReviewNotificationsEnabled
                    ? _passwordReviewReminderAtUtc(snapshot)
                    : null,
              );
              return true;
            } on Object {
              return false;
            }
          })()
        : null;
    NotificationReconciliationState? pending;
    if (session is NotificationReconciliationVaultSession) {
      try {
        pending = await session.readNotificationReconciliation();
      } on Object {
        try {
          // 主密码/恢复凭据轮换会更换 DEK，旧 outbox 随之不可认证。当前
          // 保险库快照仍是唯一权威来源，因此用当前 DEK 重建一份待协调状态，
          // 随后执行相同的幂等全量重排；损坏文件也不会造成永久卡死。
          pending = await session.prepareNotificationReconciliation(
            targetGeneration: session.generation,
          );
        } on Object {
          if (_vaultPhase == VaultPhase.unlocked &&
              identical(_session, session) &&
              !_disposed) {
            _warningMessage = '记录已安全保存，但提醒协调状态无法确认；请在通知可靠性页面重新同步。';
            _notify();
          }
          return false;
        }
      }
    }
    if (_vaultPhase != VaultPhase.unlocked ||
        !identical(_session, session) ||
        !_canManageSecurity) {
      return false;
    }
    try {
      if (submitted != null) {
        if (!await submitted) throw StateError('Reminder scheduling failed');
      } else if (previousNotificationsEnabled || pending != null) {
        if (preserveOtherNotifications) {
          await _reminderScheduler.rescheduleAll(const <SubscriptionRecord>[]);
        } else {
          await _reminderScheduler.cancelAll();
        }
      }
      if (pending != null &&
          session is NotificationReconciliationVaultSession) {
        try {
          await session.completeNotificationReconciliation(
            operationId: pending.operationId,
          );
        } on Object {
          if (_vaultPhase == VaultPhase.unlocked &&
              identical(_session, session) &&
              !_disposed) {
            _warningMessage = '系统提醒已同步，但待协调状态未能清除；后续重试使用固定提醒编号，不会创建重复提醒。';
            _notify();
          }
          return false;
        }
      }
      return true;
    } on Object {
      if (pending != null &&
          session is NotificationReconciliationVaultSession) {
        try {
          await session.recordNotificationReconciliationFailure(
            operationId: pending.operationId,
          );
        } on Object {
          // 原 pending 认证密文仍然保留；失败次数写入失败不得清掉待办。
        }
      }
      if (_vaultPhase == VaultPhase.unlocked && !_disposed) {
        _warningMessage = '记录已安全保存，但系统提醒同步失败；应用内日期仍为准。';
        _notify();
      }
      return false;
    }
  }

  Future<NotificationReconciliationState?> _prepareNotificationReconciliation(
    VaultSession session, {
    required int targetGeneration,
  }) {
    if (!_canManageSecurity) {
      return Future<NotificationReconciliationState?>.value();
    }
    if (session is! NotificationReconciliationVaultSession) {
      // 旧的可注入测试/平台会话仍可执行幂等调度；正式 Encrypted/
      // Layered 会话均实现持久 outbox，可靠性页会把缺失能力显示为不可用。
      return Future<NotificationReconciliationState?>.value();
    }
    return session.prepareNotificationReconciliation(
      targetGeneration: targetGeneration,
    );
  }

  Future<void> _recordNotificationReconciliationFailureBestEffort(
    VaultSession session,
    NotificationReconciliationState? pending,
  ) async {
    if (pending == null || session is! NotificationReconciliationVaultSession) {
      return;
    }
    try {
      await session.recordNotificationReconciliationFailure(
        operationId: pending.operationId,
      );
    } on Object {
      // 原 pending 认证密文仍在；不能因更新计数失败而清除待协调状态。
    }
  }

  bool _reminderPlanChanged(VaultSnapshot snapshot) {
    final nextPreferences = snapshot.preferences;
    if (_preferences.notificationsEnabled !=
            nextPreferences.notificationsEnabled ||
        _preferences.passwordReviewNotificationsEnabled !=
            nextPreferences.passwordReviewNotificationsEnabled ||
        _preferences.defaultReminderTimeMinutes !=
            nextPreferences.defaultReminderTimeMinutes ||
        _preferences.secondReminderTimeMinutes !=
            nextPreferences.secondReminderTimeMinutes) {
      return true;
    }
    if (!_anyNotificationsEnabled(nextPreferences)) {
      return false;
    }
    if (nextPreferences.notificationsEnabled) {
      if (_subscriptions.length != snapshot.subscriptions.length) {
        return true;
      }
      for (var index = 0; index < _subscriptions.length; index += 1) {
        final current = _subscriptions[index];
        final next = snapshot.subscriptions[index];
        if (current.id != next.id ||
            current.status != next.status ||
            jsonEncode(current.management?.toJson()) !=
                jsonEncode(next.management?.toJson()) ||
            current.reminderEnabled != next.reminderEnabled ||
            current.reminderDaysBefore != next.reminderDaysBefore ||
            current.nextRenewalOn != next.nextRenewalOn ||
            current.snoozedUntil != next.snoozedUntil ||
            current.snoozedUntilUtc != next.snoozedUntilUtc) {
          return true;
        }
      }
    }
    if (nextPreferences.passwordReviewNotificationsEnabled) {
      if (_accounts.length != snapshot.accounts.length) return true;
      for (var index = 0; index < _accounts.length; index += 1) {
        final current = _accounts[index];
        final next = snapshot.accounts[index];
        if (current.id != next.id ||
            (current.password != null) != (next.password != null) ||
            current.passwordSyncState != next.passwordSyncState ||
            current.passwordVerifiedAtUtc != next.passwordVerifiedAtUtc ||
            current.passwordReviewIntervalDays !=
                next.passwordReviewIntervalDays ||
            current.passwordReviewSnoozedUntilUtc !=
                next.passwordReviewSnoozedUntilUtc) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _anyNotificationsEnabled(VaultPreferences preferences) =>
      preferences.notificationsEnabled ||
      preferences.passwordReviewNotificationsEnabled;

  // Retired review reminders are canceled by the normal scoped reconciliation.
  static DateTime? _passwordReviewReminderAtUtc(VaultSnapshot snapshot) => null;

  void _setContentError(String message) {
    if (_vaultPhase != VaultPhase.unlocked || _disposed) {
      return;
    }
    _errorMessage = message;
    _notify();
  }

  Future<void> _recordQuickUnlockFailure(
    QuickUnlockException error,
    int epoch, {
    required bool enabling,
  }) async {
    final invalidatesConfiguration = error.reason.invalidatesConfiguration;
    if (invalidatesConfiguration) {
      try {
        await _vaultStore.disableQuickUnlock();
      } on Object {
        // The v2 marker is treated as disabled even if best-effort cleanup
        // reports an error. A later enable starts by clearing all v2 remnants.
      }
    }
    if (!_isCurrent(epoch)) {
      return;
    }
    _quickUnlockFailureReason = error.reason;
    if (invalidatesConfiguration) {
      _quickUnlockEnabled = false;
      _quickUnlockScope = null;
    }
    _errorMessage = _quickUnlockFailureMessage(
      error.reason,
      enabling: enabling,
    );
  }

  Future<void> _refreshQuickUnlockConfiguration() async {
    try {
      _quickUnlockEnabled = await _vaultStore.isQuickUnlockEnabled();
      final controller = _vaultStore is LayeredVaultSecurityController
          ? _vaultStore as LayeredVaultSecurityController
          : null;
      _quickUnlockScope = _quickUnlockEnabled
          ? await controller?.configuredQuickUnlockScope() ??
                QuickUnlockScope.fullVault
          : null;
    } on Object {
      _quickUnlockEnabled = false;
      _quickUnlockScope = null;
    }
  }

  String _quickUnlockFailureMessage(
    QuickUnlockFailureReason reason, {
    required bool enabling,
  }) => switch (reason) {
    QuickUnlockFailureReason.userCanceled => '已取消生物识别。',
    QuickUnlockFailureReason.timeout => '生物识别已超时，请重试。',
    QuickUnlockFailureReason.temporaryLockout => '生物识别暂时锁定，请稍后重试。',
    QuickUnlockFailureReason.biometricLockout => '生物识别已锁定，请先解锁手机后重试。',
    QuickUnlockFailureReason.hardwareUnavailable => '生物识别硬件暂时不可用，请稍后重试。',
    QuickUnlockFailureReason.notEnrolled => '系统中没有可用的强生物识别。',
    QuickUnlockFailureReason.securityUpdateRequired =>
      '系统已暂时停用生物识别传感器，请先完成手机系统安全更新。',
    QuickUnlockFailureReason.unsupported => '本机系统不支持当前强生物识别配置。',
    QuickUnlockFailureReason.statusUnknown => '系统暂时无法确认指纹状态，请保持手机解锁后重试。',
    QuickUnlockFailureReason.lifecycleCanceled => '应用状态发生变化，生物识别已取消，请重试。',
    QuickUnlockFailureReason.activityUnavailable ||
    QuickUnlockFailureReason.promptStartFailed ||
    QuickUnlockFailureReason.uiUnavailable => '系统指纹验证界面暂时无法启动，请保持应用在前台后重试。',
    QuickUnlockFailureReason.keySetupFailed => '本机安全密钥初始化失败，请先用手机锁屏密码解锁设备后重试。',
    QuickUnlockFailureReason.keyInvalidated ||
    QuickUnlockFailureReason.keyMissing ||
    QuickUnlockFailureReason.corruptedSecret ||
    QuickUnlockFailureReason.notConfigured => '快速解锁密钥已失效，请使用主密码重新启用。',
    _ => enabling ? '未能启用生物识别，请确认系统生物识别可用。' : '生物识别未完成，请使用主密码解锁。',
  };

  void lock() {
    if (_vaultPhase == VaultPhase.initializing) {
      return;
    }
    if (_vaultPhase != VaultPhase.unlocked && !_busy) {
      return;
    }
    _operationEpoch += 1;
    _clearSession();
    _errorMessage = null;
    _warningMessage = null;
    _busy = _busyEpoch != null;
    _vaultPhase = _hasVault ? VaultPhase.locked : VaultPhase.needsSetup;
    _notify();
  }

  void dismissWarning() {
    if (_warningMessage == null) {
      return;
    }
    _warningMessage = null;
    _notify();
  }

  void _applyOpenResult(VaultOpenResult result) {
    _clearSession();
    _session = result.session;
    _importVaultScopeId = _newImportVaultScopeId();
    final scopedSession = result.session is ScopedVaultSession
        ? result.session as ScopedVaultSession
        : null;
    _accessLevel = scopedSession?.accessLevel ?? VaultAccessLevel.full;
    _canManageSecurity = scopedSession?.canManageSecurity ?? true;
    _replaceSnapshot(result.snapshot);
    _hasVault = true;
    _trashCleanupPending = hasFullVaultAccess;
    _vaultPhase = VaultPhase.unlocked;
    final backupSession = _session;
    if (_canManageSecurity && backupSession is DeviceBackupConfigSession) {
      unawaited(autoBackup.attach(backupSession, result.snapshot));
    }
    _errorMessage = null;
    _quickUnlockFailureReason = null;
    _warningMessage = result.recoveredFromFallback
        ? '已从上一份有效数据恢复，最近一次更改可能未保留。'
        : null;
    if (_canManageSecurity) {
      // 真实主库每次解锁都重放持久 outbox；提醒关闭时同样要完成旧队列清理。
      // 应用/进程/设备重启均会回到此入口，锁定态不读取业务快照。
      unawaited(
        _syncReminders(result.snapshot, previousNotificationsEnabled: true),
      );
    }
    final recoveryEpoch = _operationEpoch;
    final recoverySession = _session;
    final recoveryRefreshToken = ++_recoveryRefreshToken;
    if (_canManageSecurity && recoverySession != null) {
      unawaited(
        _refreshRecoveryState(
          epoch: recoveryEpoch,
          session: recoverySession,
          refreshToken: recoveryRefreshToken,
        ),
      );
    } else {
      // 诱饵库和订阅只读视图不得读取或暴露真实库的全局恢复凭据。
      _recoveryState = null;
    }
  }

  Future<void> _refreshRecoveryState({
    required int epoch,
    required VaultSession session,
    required int refreshToken,
  }) async {
    if (!_isCurrentPrimarySession(
      epoch: epoch,
      session: session,
      refreshToken: refreshToken,
    )) {
      return;
    }
    VaultRecoveryEntry? entry;
    try {
      entry = await _recoveryJournal.read();
      if (!_isCurrentPrimarySession(
        epoch: epoch,
        session: session,
        refreshToken: refreshToken,
      )) {
        return;
      }
      _recoveryState = entry?.state;
      if (entry?.state == VaultRecoveryState.prepared) {
        _warningMessage ??= '检测到上次恢复事务可能中断；结果尚未确认，加密回滚副本仍保留。请先核对当前数据。';
      }
      _notify();
    } on Object {
      if (_isCurrentPrimarySession(
        epoch: epoch,
        session: session,
        refreshToken: refreshToken,
      )) {
        _recoveryState = null;
        _warningMessage ??= '恢复回滚状态无法验证；在核对数据前请勿再次导入备份。';
        _notify();
      }
    } finally {
      entry?.destroy();
    }
  }

  bool _isCurrentPrimarySession({
    required int epoch,
    required VaultSession session,
    required int refreshToken,
  }) =>
      _isCurrent(epoch) &&
      refreshToken == _recoveryRefreshToken &&
      _vaultPhase == VaultPhase.unlocked &&
      _canManageSecurity &&
      identical(_session, session);

  void _clearSession() {
    _invalidateAccountAnalysis();
    _passwordHealthIgnoreRules.clear();
    _bindingRetirementPlans.clear();
    _paymentMethods.clear();
    autoBackup.detach();
    _backupWarningDismissed = false;
    _recoveryRefreshToken += 1;
    _session?.close();
    _session = null;
    _importVaultScopeId = null;
    _lastBatchRollbackImpact = null;
    _accounts.clear();
    _trashAccounts.clear();
    _trashSubscriptions.clear();
    _trashCleanupPending = false;
    _subscriptions.clear();
    _subscriptionExpenses.clear();
    _pendingSubscriptionDrafts.clear();
    _recentAccountIds.clear();
    _nextAccountId = 1;
    _nextSubscriptionId = 1;
    _nextExpenseId = 1;
    _preferences = const VaultPreferences();
    _accessLevel = VaultAccessLevel.full;
    _canManageSecurity = true;
    _recoveryState = null;
  }

  void _replaceSnapshot(VaultSnapshot snapshot) {
    _invalidateAccountAnalysis();
    _passwordHealthIgnoreRules = List.of(snapshot.passwordHealthIgnoreRules);
    _bindingRetirementPlans = List.of(snapshot.bindingRetirementPlans);
    _paymentMethods = List.of(snapshot.paymentMethods);
    _trashAccounts
      ..clear()
      ..addAll(snapshot.trashAccounts);
    _trashSubscriptions
      ..clear()
      ..addAll(snapshot.trashSubscriptions);
    _accounts
      ..clear()
      ..addAll(snapshot.accounts);
    _subscriptions
      ..clear()
      ..addAll(snapshot.subscriptions);
    _subscriptionExpenses
      ..clear()
      ..addAll(snapshot.subscriptionExpenses);
    _pendingSubscriptionDrafts
      ..clear()
      ..addAll(snapshot.pendingSubscriptionDrafts);
    _nextAccountId = snapshot.nextAccountId;
    _nextSubscriptionId = snapshot.nextSubscriptionId;
    _nextExpenseId = snapshot.nextExpenseId;
    _recentAccountIds
      ..clear()
      ..addAll(snapshot.recentAccountIds);
    _preferences = snapshot.preferences;
    if (isUnlocked && _canManageSecurity) {
      unawaited(autoBackup.observe(snapshot));
    }
  }

  bool _isCurrent(int epoch) => !_disposed && epoch == _operationEpoch;

  static String _newImportVaultScopeId() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  bool _ownsOperation(int epoch) => !_disposed && _busyEpoch == epoch;

  void _beginOperation(int epoch) {
    _busyEpoch = epoch;
    _busy = true;
  }

  void _finishOperation(int epoch) {
    if (_busyEpoch != epoch) {
      return;
    }
    _busyEpoch = null;
    _busy = false;
    _notify();
    if (_trashCleanupPending && isUnlocked && hasFullVaultAccess) {
      _trashCleanupPending = false;
      unawaited(purgeExpiredTrash());
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _operationEpoch += 1;
    _busyEpoch = null;
    _busy = false;
    _clearSession();
    autoBackup.removeListener(_notify);
    autoBackup.dispose();
    super.dispose();
  }
}

String _recoveryDeviceErrorMessage(RecoveryDeviceSecretException error) =>
    switch (error.reason) {
      RecoveryDeviceSecretFailureReason.userCanceled => '已取消本机系统强认证，密码恢复未执行。',
      RecoveryDeviceSecretFailureReason.notEnrolled =>
        '本机尚未录入可用的强指纹或安全级人脸，不能启用或使用密码恢复。',
      RecoveryDeviceSecretFailureReason.temporaryLockout ||
      RecoveryDeviceSecretFailureReason.biometricLockout =>
        '系统生物识别暂时锁定，请按系统提示稍后重试；不会降级为只验证密保答案。',
      RecoveryDeviceSecretFailureReason.hardwareUnavailable ||
      RecoveryDeviceSecretFailureReason.unsupported =>
        '本机没有可用的强生物识别能力，密码恢复无法继续；你仍可尝试原密码，或在确认有可用加密备份后选择重新开始。',
      RecoveryDeviceSecretFailureReason.keyInvalidated ||
      RecoveryDeviceSecretFailureReason.keyMissing ||
      RecoveryDeviceSecretFailureReason.corruptedSecret ||
      RecoveryDeviceSecretFailureReason.notConfigured =>
        '本机恢复设备密钥已失效或不存在，不能只靠三道密保答案恢复。',
      _ => '系统强认证未完成，密码恢复未执行。',
    };

final class _FreeEntitlementListenable
    implements ValueListenable<ProductEntitlement> {
  const _FreeEntitlementListenable();

  @override
  ProductEntitlement get value => ProductEntitlement.free;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
