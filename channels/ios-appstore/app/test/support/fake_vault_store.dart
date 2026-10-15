import 'dart:async';

import 'package:account_subscription_manager/core/security/editor_draft.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/notifications/notification_reconciliation_state.dart';
import 'package:account_subscription_manager/core/security/vault_recovery.dart';
import 'package:account_subscription_manager/core/storage/layered_vault_store.dart';

final class FakeVaultStore
    implements VaultStore, LayeredVaultSecurityController {
  factory FakeVaultStore({
    bool configured = false,
    String? acceptedPassword,
    VaultSnapshot? snapshot,
    bool recoveredFromFallback = false,
  }) => FakeVaultStore._(
    configured,
    acceptedPassword,
    snapshot ?? VaultSnapshot.empty(),
    recoveredFromFallback,
  );

  FakeVaultStore._(
    this.configured,
    this._acceptedPassword,
    this.snapshot,
    this.recoveredFromFallback,
  );

  Map<String, Object?>? editorDraft;
  int? editorDraftGeneration;
  bool configured;
  bool failSaves = false;
  bool failAccess = false;
  bool recoveredFromFallback;
  Completer<void>? createGate;
  Completer<void>? unlockGate;
  Completer<void>? saveGate;
  Completer<void>? notificationReadGate;
  int createCalls = 0;
  int unlockCalls = 0;
  int saveCalls = 0;
  int disableQuickUnlockCalls = 0;
  int changeMasterPasswordCalls = 0;
  int changeDecoyPasswordCalls = 0;
  VaultSnapshot snapshot;
  String? _acceptedPassword;
  String? _acceptedDecoyPassword;
  int _generation = 0;
  int _notificationReconciliationRevision = 0;
  int _notificationReconciliationOrdinal = 0;
  NotificationReconciliationState? notificationReconciliation;
  bool quickUnlockEnabled = false;
  QuickUnlockScope? quickUnlockScope;
  bool decoyConfigured = false;
  VaultRecoveryChallenge? configuredRecoveryChallenge;
  VaultRecoveryChallenge? configuredDecoyRecoveryChallenge;
  List<String>? _acceptedRecoveryAnswers;
  List<String>? _acceptedDecoyRecoveryAnswers;
  QuickUnlockException? quickUnlockFailure;
  QuickUnlockException? quickUnlockEnableFailure;

  String? get acceptedDecoyPassword => _acceptedDecoyPassword;

  @override
  Future<bool> exists() async {
    if (failAccess) {
      throw const VaultStorageException();
    }
    return configured;
  }

  @override
  Future<VaultOpenResult> create({required String masterPassword}) async {
    createCalls += 1;
    await createGate?.future;
    if (failAccess) {
      throw const VaultStorageException();
    }
    if (configured) {
      throw const VaultAlreadyExistsException();
    }
    configured = true;
    _acceptedPassword = masterPassword;
    snapshot = VaultSnapshot.empty();
    _generation = 1;
    return _openResult();
  }

  @override
  Future<VaultOpenResult> unlock({required String masterPassword}) async {
    unlockCalls += 1;
    await unlockGate?.future;
    if (failAccess) {
      throw const VaultStorageException();
    }
    if (!configured) {
      throw const VaultNotFoundException();
    }
    if (masterPassword == _acceptedPassword) {
      return _openResult(recoveredFromFallback: recoveredFromFallback);
    }
    if (decoyConfigured && masterPassword == _acceptedDecoyPassword) {
      quickUnlockEnabled = false;
      quickUnlockScope = null;
      return _openResult(canManageSecurity: false);
    }
    throw const VaultUnlockException();
  }

  @override
  Future<bool> isQuickUnlockEnabled() async => quickUnlockEnabled;

  @override
  Future<VaultOpenResult> unlockWithQuickUnlock() async {
    final failure = quickUnlockFailure;
    if (failure != null) {
      throw failure;
    }
    if (!quickUnlockEnabled) {
      throw const VaultUnlockException();
    }
    return _openResult();
  }

  @override
  Future<void> disableQuickUnlock() async {
    disableQuickUnlockCalls += 1;
    quickUnlockEnabled = false;
  }

  @override
  Future<QuickUnlockScope?> configuredQuickUnlockScope() async =>
      quickUnlockEnabled
      ? quickUnlockScope ?? QuickUnlockScope.fullVault
      : null;

  @override
  Future<void> configureQuickUnlock({
    required String currentMasterPassword,
    required QuickUnlockScope scope,
  }) async {
    if (currentMasterPassword != _acceptedPassword) {
      throw const VaultCredentialRejectedException();
    }
    final failure = quickUnlockEnableFailure;
    if (failure != null) throw failure;
    quickUnlockEnabled = true;
    quickUnlockScope = scope;
  }

  @override
  Future<bool> isDecoyVaultConfigured() async => decoyConfigured;

  @override
  Future<VaultRecoveryChallenge?> recoveryChallenge() async =>
      configuredRecoveryChallenge;

  @override
  Future<VaultRecoveryConfiguration> recoveryConfiguration() async =>
      VaultRecoveryConfiguration(
        primaryChallenge: configuredRecoveryChallenge,
        decoyChallenge: configuredDecoyRecoveryChallenge,
      );

  @override
  Future<VaultRecoveryChallenge> configureRecovery({
    required String currentMasterPassword,
    String? currentDecoyPassword,
    required List<String> questionIds,
    required List<String> answers,
    required VaultRecoveryEntryMode entryMode,
    VaultRecoveryScope scope = VaultRecoveryScope.primary,
  }) async {
    if (currentMasterPassword != _acceptedPassword) {
      throw const VaultCredentialRejectedException();
    }
    if (scope == VaultRecoveryScope.decoy &&
        (!decoyConfigured || currentDecoyPassword != _acceptedDecoyPassword)) {
      throw const VaultCredentialRejectedException();
    }
    final other = scope == VaultRecoveryScope.primary
        ? configuredDecoyRecoveryChallenge
        : configuredRecoveryChallenge;
    if (other != null && _sameQuestionSet(questionIds, other.questionIds)) {
      throw const VaultRecoveryQuestionSetConflictException();
    }
    final challenge = VaultRecoveryChallenge(
      binding: VaultRecoveryBinding.random(),
      questionIds: questionIds,
      entryMode: entryMode,
    );
    final normalized = answers
        .map(normalizeVaultRecoveryAnswer)
        .toList(growable: false);
    if (scope == VaultRecoveryScope.primary) {
      configuredRecoveryChallenge = challenge;
      _acceptedRecoveryAnswers = normalized;
      quickUnlockEnabled = false;
      quickUnlockScope = null;
    } else {
      configuredDecoyRecoveryChallenge = challenge;
      _acceptedDecoyRecoveryAnswers = normalized;
    }
    return challenge;
  }

  @override
  Future<void> disableRecovery({
    required String currentMasterPassword,
    String? currentDecoyPassword,
    VaultRecoveryScope scope = VaultRecoveryScope.primary,
  }) async {
    if (currentMasterPassword != _acceptedPassword) {
      throw const VaultCredentialRejectedException();
    }
    if (scope == VaultRecoveryScope.decoy &&
        (!decoyConfigured || currentDecoyPassword != _acceptedDecoyPassword)) {
      throw const VaultCredentialRejectedException();
    }
    if (scope == VaultRecoveryScope.primary) {
      if (configuredRecoveryChallenge == null) {
        throw const VaultRecoveryNotConfiguredException();
      }
      configuredRecoveryChallenge = null;
      _acceptedRecoveryAnswers = null;
    } else {
      if (configuredDecoyRecoveryChallenge == null) {
        throw const VaultRecoveryNotConfiguredException();
      }
      configuredDecoyRecoveryChallenge = null;
      _acceptedDecoyRecoveryAnswers = null;
    }
  }

  @override
  Future<VaultOpenResult> recoverMasterPassword({
    required List<String> questionIds,
    required List<String> answers,
    required String newMasterPassword,
    required VaultRecoveryEntryMode requestEntryMode,
    bool allowPrimaryRecovery = true,
    Future<void> Function()? beforePrimaryCommit,
  }) async {
    final normalized = answers
        .map(normalizeVaultRecoveryAnswer)
        .toList(growable: false);
    final primaryMatch = _matchesRecovery(
      configuredRecoveryChallenge,
      _acceptedRecoveryAnswers,
      questionIds,
      normalized,
      requestEntryMode,
    );
    final decoyMatch = _matchesRecovery(
      configuredDecoyRecoveryChallenge,
      _acceptedDecoyRecoveryAnswers,
      questionIds,
      normalized,
      requestEntryMode,
    );
    if ((!allowPrimaryRecovery && primaryMatch) || primaryMatch == decoyMatch) {
      throw const VaultRecoveryRejectedException();
    }
    if (primaryMatch) {
      if (newMasterPassword == _acceptedDecoyPassword) {
        throw const VaultRecoveryRejectedException();
      }
      await beforePrimaryCommit?.call();
      _acceptedPassword = newMasterPassword;
    } else {
      if (newMasterPassword == _acceptedPassword) {
        throw const VaultRecoveryRejectedException();
      }
      _acceptedDecoyPassword = newMasterPassword;
    }
    quickUnlockEnabled = false;
    quickUnlockScope = null;
    _generation += 1;
    return _openResult(canManageSecurity: primaryMatch);
  }

  @override
  Future<void> createDecoyVault({
    required String currentMasterPassword,
    required String decoyPassword,
  }) async {
    if (currentMasterPassword != _acceptedPassword) {
      throw const VaultCredentialRejectedException();
    }
    if (decoyConfigured) throw const DecoyVaultAlreadyConfiguredException();
    if (decoyPassword == _acceptedPassword) {
      throw const DecoyPasswordConflictException();
    }
    decoyConfigured = true;
    _acceptedDecoyPassword = decoyPassword;
  }

  @override
  Future<VaultOpenResult> changeMasterPassword({
    required String currentMasterPassword,
    required String newMasterPassword,
  }) async {
    changeMasterPasswordCalls += 1;
    if (currentMasterPassword != _acceptedPassword) {
      throw const VaultCredentialRejectedException();
    }
    if (currentMasterPassword == newMasterPassword) {
      throw const VaultPasswordUnchangedException();
    }
    if (newMasterPassword == _acceptedDecoyPassword) {
      throw const DecoyPasswordConflictException();
    }
    _acceptedPassword = newMasterPassword;
    quickUnlockEnabled = false;
    quickUnlockScope = null;
    _generation += 1;
    return _openResult();
  }

  @override
  Future<void> changeDecoyPassword({
    required String currentMasterPassword,
    required String currentDecoyPassword,
    required String newDecoyPassword,
  }) async {
    changeDecoyPasswordCalls += 1;
    if (currentMasterPassword != _acceptedPassword ||
        currentDecoyPassword != _acceptedDecoyPassword) {
      throw const VaultCredentialRejectedException();
    }
    if (currentDecoyPassword == newDecoyPassword) {
      throw const VaultPasswordUnchangedException();
    }
    if (newDecoyPassword == _acceptedPassword) {
      throw const DecoyPasswordConflictException();
    }
    _acceptedDecoyPassword = newDecoyPassword;
  }

  @override
  Future<VaultSnapshot> readEncryptedBackup({
    required List<int> bytes,
    required String masterPassword,
  }) async {
    if (masterPassword != _acceptedPassword) {
      throw const VaultUnlockException();
    }
    return VaultSnapshot.fromEncryptedPayloadJson(
      jsonDecode(utf8.decode(bytes)),
    );
  }

  static bool _sameQuestionSet(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    final firstSet = first.toSet();
    final secondSet = second.toSet();
    return firstSet.length == first.length &&
        secondSet.length == second.length &&
        firstSet.containsAll(secondSet);
  }

  static bool _matchesRecovery(
    VaultRecoveryChallenge? challenge,
    List<String>? expectedAnswers,
    List<String> suppliedQuestionIds,
    List<String> suppliedAnswers,
    VaultRecoveryEntryMode requestEntryMode,
  ) {
    if (challenge == null ||
        expectedAnswers == null ||
        challenge.entryMode != requestEntryMode ||
        suppliedQuestionIds.length != suppliedAnswers.length ||
        !_sameQuestionSet(challenge.questionIds, suppliedQuestionIds)) {
      return false;
    }
    for (var index = 0; index < challenge.questionIds.length; index++) {
      final suppliedIndex = suppliedQuestionIds.indexOf(
        challenge.questionIds[index],
      );
      if (suppliedIndex < 0 ||
          suppliedAnswers[suppliedIndex] != expectedAnswers[index]) {
        return false;
      }
    }
    return true;
  }

  VaultOpenResult _openResult({
    bool recoveredFromFallback = false,
    bool canManageSecurity = true,
  }) => VaultOpenResult(
    session: _FakeVaultSession(this, canManageSecurity: canManageSecurity),
    snapshot: snapshot,
    recoveredFromFallback: recoveredFromFallback,
  );
}

final class _FakeVaultSession
    implements
        VaultSession,
        VaultBoundSession,
        ScopedVaultSession,
        NotificationReconciliationVaultSession,
        EditorDraftVaultSession {
  _FakeVaultSession(this._store, {required this.canManageSecurity});

  @override
  String get vaultBindingId =>
      'test-${identityHashCode(_store)}-$canManageSecurity';

  final FakeVaultStore _store;
  bool _closed = false;

  @override
  VaultAccessLevel get accessLevel => VaultAccessLevel.full;

  @override
  final bool canManageSecurity;

  @override
  Future<Map<String, Object?>?> readEditorDraft() async {
    if (_closed) throw const VaultClosedException();
    return _store.editorDraftGeneration == generation
        ? _store.editorDraft
        : null;
  }

  @override
  Future<void> writeEditorDraft(Map<String, Object?>? draft) async {
    if (_closed) throw const VaultClosedException();
    _store.editorDraft = draft == null
        ? null
        : Map<String, Object?>.from(jsonDecode(jsonEncode(draft)) as Map);
    _store.editorDraftGeneration = generation;
  }

  @override
  int get generation => _store._generation;

  @override
  Future<void> save(VaultSnapshot snapshot) async {
    if (_closed) {
      throw const VaultClosedException();
    }
    if (_store.failSaves) {
      throw const VaultStorageException();
    }
    _store.saveCalls += 1;
    await _store.saveGate?.future;
    _store.snapshot = snapshot;
    _store._generation += 1;
  }

  @override
  Future<NotificationReconciliationState?>
  readNotificationReconciliation() async {
    await _store.notificationReadGate?.future;
    if (_closed) throw const VaultClosedException();
    final pending = _store.notificationReconciliation;
    if (pending != null && pending.targetGeneration > generation) {
      _store.notificationReconciliation = null;
      _store._notificationReconciliationRevision += 1;
      return null;
    }
    return pending;
  }

  @override
  Future<NotificationReconciliationState> prepareNotificationReconciliation({
    required int targetGeneration,
  }) async {
    if (_closed) throw const VaultClosedException();
    if (targetGeneration != generation && targetGeneration != generation + 1) {
      throw const VaultStorageException();
    }
    _store._notificationReconciliationRevision += 1;
    _store._notificationReconciliationOrdinal += 1;
    final state = NotificationReconciliationState(
      operationId:
          'test-notification-operation-${_store._notificationReconciliationOrdinal}',
      targetGeneration: targetGeneration,
      stateRevision: _store._notificationReconciliationRevision,
      createdAtUtc: DateTime.utc(2026, 8, 30),
      attemptCount: 0,
    );
    _store.notificationReconciliation = state;
    return state;
  }

  @override
  Future<void> recordNotificationReconciliationFailure({
    required String operationId,
  }) async {
    if (_closed) throw const VaultClosedException();
    final pending = _store.notificationReconciliation;
    if (pending == null || pending.operationId != operationId) return;
    _store._notificationReconciliationRevision += 1;
    _store.notificationReconciliation = pending.copyWith(
      stateRevision: _store._notificationReconciliationRevision,
      attemptCount: pending.attemptCount + 1,
      lastAttemptAtUtc: DateTime.utc(2026, 8, 30, 0, 1),
    );
  }

  @override
  Future<void> completeNotificationReconciliation({
    required String operationId,
  }) async {
    if (_closed) throw const VaultClosedException();
    final pending = _store.notificationReconciliation;
    if (pending == null || pending.operationId != operationId) return;
    _store._notificationReconciliationRevision += 1;
    _store.notificationReconciliation = null;
  }

  @override
  Future<Uint8List> exportEncryptedBackup() async => Uint8List.fromList(
    utf8.encode(jsonEncode(_store.snapshot.toEncryptedPayloadJson())),
  );

  @override
  Future<void> enableQuickUnlock() async {
    if (_closed) {
      throw const VaultClosedException();
    }
    final failure = _store.quickUnlockEnableFailure;
    if (failure != null) {
      throw failure;
    }
    _store.quickUnlockEnabled = true;
  }

  @override
  void close() {
    _closed = true;
  }
}
