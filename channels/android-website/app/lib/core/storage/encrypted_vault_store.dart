import 'dart:async';

import '../security/editor_draft.dart';
import '../security/device_backup_config.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import '../notifications/notification_reconciliation_state.dart';
import '../security/vault_contract.dart';
import '../security/vault_crypto.dart';
import '../security/biometric_unlock.dart';
import '../security/vault_recovery.dart';

typedef VaultDirectoryProvider = Future<Directory> Function();

final class EncryptedVaultStore implements VaultStore {
  factory EncryptedVaultStore({
    required VaultDirectoryProvider directoryProvider,
    VaultKdfParameters creationKdf = VaultKdfParameters.production,
    VaultCrypto? crypto,
    QuickUnlockSecretStore? quickUnlockSecretStore,
    int creationPasswordMinimumLength = 12,
    int creationPasswordMaximumLength = 128,
    int unlockPasswordMinimumLength = 12,
    int unlockPasswordMaximumLength = 128,
    Future<void> Function(bool isCommitted)?
    beforePasswordStateFinalRenameForTesting,
    Future<void> Function(int committedGeneration)?
    afterEnvelopeCommitRenameForTesting,
    Future<void> Function(String artifactPath)?
    beforeCommittedBatchCleanupForTesting,
  }) {
    _validatePasswordPolicy(
      minimum: creationPasswordMinimumLength,
      maximum: creationPasswordMaximumLength,
    );
    _validatePasswordPolicy(
      minimum: unlockPasswordMinimumLength,
      maximum: unlockPasswordMaximumLength,
    );
    return EncryptedVaultStore._(
      directoryProvider,
      creationKdf,
      crypto ?? VaultCrypto(),
      quickUnlockSecretStore ?? BiometricQuickUnlockSecretStore(),
      creationPasswordMinimumLength,
      creationPasswordMaximumLength,
      unlockPasswordMinimumLength,
      unlockPasswordMaximumLength,
      beforePasswordStateFinalRenameForTesting,
      afterEnvelopeCommitRenameForTesting,
      beforeCommittedBatchCleanupForTesting,
    );
  }

  EncryptedVaultStore._(
    this._directoryProvider,
    this._creationKdf,
    this._crypto,
    this._quickUnlockSecretStore,
    this._creationPasswordMinimumLength,
    this._creationPasswordMaximumLength,
    this._unlockPasswordMinimumLength,
    this._unlockPasswordMaximumLength,
    this._beforePasswordStateFinalRenameForTesting,
    this._afterEnvelopeCommitRenameForTesting,
    this._beforeCommittedBatchCleanupForTesting,
  );

  factory EncryptedVaultStore.appSupport() => EncryptedVaultStore(
    directoryProvider: () async {
      final supportDirectory = await getApplicationSupportDirectory();
      return Directory(
        '${supportDirectory.path}${Platform.pathSeparator}encrypted_vault_v1',
      );
    },
  );

  static const _slotNames = <String>['vault_a.json', 'vault_b.json'];
  static const _maximumEnvelopeBytes = 16 * 1024 * 1024;
  static const _batchRollbackName = 'batch_import_rollback_v1.envelope';
  static const _notificationReconciliationName =
      'notification_reconciliation_v1.json';
  static const _passwordStateName = 'password_change_state_v1.json';
  static const _passwordStateMagic = 'ASM_VAULT_PASSWORD_CHANGE';
  static const _passwordStateVersion = 1;
  static const _maximumPasswordStateBytes = 16 * 1024;

  final VaultDirectoryProvider _directoryProvider;
  final VaultKdfParameters _creationKdf;
  final VaultCrypto _crypto;
  final QuickUnlockSecretStore _quickUnlockSecretStore;
  final int _creationPasswordMinimumLength;
  final int _creationPasswordMaximumLength;
  final int _unlockPasswordMinimumLength;
  final int _unlockPasswordMaximumLength;
  final Future<void> Function(bool isCommitted)?
  _beforePasswordStateFinalRenameForTesting;
  final Future<void> Function(int committedGeneration)?
  _afterEnvelopeCommitRenameForTesting;
  final Future<void> Function(String artifactPath)?
  _beforeCommittedBatchCleanupForTesting;
  Future<void> _operationTail = Future<void>.value();

  Iterable<VaultKdfParameters> get _supportedKdfProfiles =>
      <VaultKdfParameters>[VaultKdfParameters.production, _creationKdf];

  @override
  Future<bool> exists() => _runExclusive(_exists);

  Future<bool> _exists() async {
    try {
      final directory = await _directoryProvider();
      for (final name in _slotNames) {
        if (await File(_join(directory.path, name)).exists()) {
          return true;
        }
      }
      return false;
    } on Object {
      throw const VaultStorageException();
    }
  }

  @override
  Future<VaultOpenResult> create({required String masterPassword}) =>
      _runExclusive(() => _create(masterPassword: masterPassword));

  Future<VaultOpenResult> _create({required String masterPassword}) async {
    if (await _exists()) {
      throw const VaultAlreadyExistsException();
    }

    VaultCryptoMaterial? material;
    try {
      final directory = await _directoryProvider();
      await directory.create(recursive: true);
      material = await _crypto.create(
        masterPassword: masterPassword,
        snapshot: VaultSnapshot.empty(),
        kdf: _creationKdf,
        minimumPasswordLength: _creationPasswordMinimumLength,
        maximumPasswordLength: _creationPasswordMaximumLength,
      );
      await _commitEnvelope(
        directory: directory,
        slotIndex: 0,
        envelope: material.envelope,
        dataKey: material.dataKey,
      );
      return VaultOpenResult(
        session: await _openSession(
          directory: directory,
          activeSlotIndex: 0,
          envelope: material.envelope,
          dataKey: material.dataKey,
          snapshot: material.snapshot,
        ),
        snapshot: material.snapshot,
      );
    } on VaultException {
      material?.dataKey.destroy();
      rethrow;
    } on ArgumentError {
      material?.dataKey.destroy();
      rethrow;
    } on Object {
      material?.dataKey.destroy();
      throw const VaultStorageException();
    }
  }

  @override
  Future<VaultOpenResult> unlock({required String masterPassword}) =>
      _runExclusive(() => _unlock(masterPassword: masterPassword));

  Future<VaultOpenResult> _unlock({required String masterPassword}) async {
    try {
      final directory = await _directoryProvider();
      final passwordState = await _readPasswordChangeState(directory);
      final candidates = <_SlotEnvelope>[];
      var foundSlotFile = false;
      var encounteredInvalidSlot = false;
      var encounteredAccessFailure = false;
      var encounteredCredentialRejection = false;
      var encounteredIntegrityFailure = false;

      for (var index = 0; index < _slotNames.length; index++) {
        final file = File(_join(directory.path, _slotNames[index]));
        if (!await file.exists()) {
          continue;
        }
        foundSlotFile = true;
        try {
          candidates.add(await _readSlotEnvelope(file, index));
        } on VaultUnsupportedEnvelopeVersionException {
          rethrow;
        } on VaultUnsupportedKdfProfileException {
          rethrow;
        } on VaultFormatException {
          encounteredInvalidSlot = true;
          // The other slot may still contain the last valid generation.
        } on FileSystemException {
          encounteredAccessFailure = true;
          // The other slot may still be readable.
        }
      }

      if (!foundSlotFile) {
        throw const VaultNotFoundException();
      }
      if (candidates.isEmpty && encounteredAccessFailure) {
        throw const VaultStorageException();
      }
      candidates.sort(
        (left, right) =>
            right.envelope.generation.compareTo(left.envelope.generation),
      );
      final eligibleCandidates = candidates
          .where(
            (candidate) =>
                _isPasswordCandidateEligible(candidate, passwordState),
          )
          .toList(growable: false);

      if (eligibleCandidates.isEmpty && passwordState?.isCommitted == true) {
        // 密码切换已提交时绝不得回退到 floor 以下的旧包装。
        throw const VaultStorageException();
      }

      for (var index = 0; index < eligibleCandidates.length; index++) {
        final candidate = eligibleCandidates[index];
        try {
          final material = await _crypto.open(
            masterPassword: masterPassword,
            envelope: candidate.envelope,
            minimumPasswordLength: _unlockPasswordMinimumLength,
            maximumPasswordLength: _unlockPasswordMaximumLength,
          );
          return VaultOpenResult(
            session: await _openSession(
              directory: directory,
              activeSlotIndex: candidate.slotIndex,
              envelope: material.envelope,
              dataKey: material.dataKey,
              snapshot: material.snapshot,
            ),
            snapshot: material.snapshot,
            recoveredFromFallback:
                encounteredInvalidSlot || encounteredAccessFailure || index > 0,
          );
        } on VaultCredentialRejectedException {
          encounteredCredentialRejection = true;
          // Try the previous valid generation before reporting a generic error.
        } on VaultIntegrityException {
          encounteredIntegrityFailure = true;
          // 当前代的 payload 损坏时仍可尝试上一个合格槽。
        } on VaultUnsupportedSchemaVersionException {
          rethrow;
        } on VaultFormatException {
          encounteredIntegrityFailure = true;
          // Try the previous valid generation.
        }
      }
      if (encounteredIntegrityFailure || encounteredInvalidSlot) {
        throw const VaultIntegrityException();
      }
      if (encounteredCredentialRejection) {
        throw const VaultCredentialRejectedException();
      }
      throw const VaultUnlockException();
    } on VaultException {
      rethrow;
    } on ArgumentError {
      throw const VaultCredentialRejectedException();
    } on Object {
      throw const VaultStorageException();
    }
  }

  Future<VaultRecoveryChallenge?> recoveryChallenge() =>
      _runExclusive(_recoveryChallenge);

  Future<VaultRecoveryChallenge?> _recoveryChallenge() async {
    final directory = await _directoryProvider();
    final candidate = await _readCurrentEligibleCandidate(directory);
    return _crypto.getRecoveryChallenge(candidate.envelope);
  }

  Future<VaultRecoveryBinding> prepareRecoveryProvisioning({
    required String currentMasterPassword,
  }) => _runExclusive(() async {
    VaultOpenResult? current;
    try {
      current = await _unlock(masterPassword: currentMasterPassword);
      final session = current.session;
      if (session is! _EncryptedVaultSession) {
        throw const VaultStorageException();
      }
      if (_crypto.getRecoveryChallenge(session._envelope) != null) {
        throw const VaultRecoveryRefreshRequiredException();
      }
      return _crypto.createRecoveryProvisioning(previous: session._envelope);
    } finally {
      current?.session.close();
    }
  });

  Future<VaultOpenResult> configureRecovery({
    required String currentMasterPassword,
    required VaultRecoveryBinding binding,
    required List<String> questionIds,
    required List<String> answers,
    required Uint8List deviceSecret,
    required VaultRecoveryEntryMode entryMode,
  }) => _runExclusive(() async {
    final directory = await _directoryProvider();
    await _rollbackInterruptedPasswordChange(directory);
    VaultOpenResult? current;
    try {
      current = await _unlock(masterPassword: currentMasterPassword);
      final session = current.session;
      if (session is! _EncryptedVaultSession) {
        throw const VaultStorageException();
      }
      if (_crypto.getRecoveryChallenge(session._envelope) != null) {
        throw const VaultRecoveryRefreshRequiredException();
      }
      final nextEnvelope = await _crypto.enableRecoveryNext(
        previous: session._envelope,
        dataKey: session._dataKey,
        snapshot: current.snapshot,
        currentMasterPassword: currentMasterPassword,
        binding: binding,
        questionIds: questionIds,
        answers: answers,
        deviceSecret: deviceSecret,
        entryMode: entryMode,
        minimumPasswordLength: _unlockPasswordMinimumLength,
        maximumPasswordLength: _unlockPasswordMaximumLength,
      );
      final result = await _commitCredentialTransition(
        directory: directory,
        current: current,
        nextEnvelope: nextEnvelope,
        verify: () async {
          VaultCryptoMaterial? passwordVerification;
          VaultCryptoMaterial? recoveryVerification;
          try {
            passwordVerification = await _crypto.open(
              masterPassword: currentMasterPassword,
              envelope: nextEnvelope,
              minimumPasswordLength: _unlockPasswordMinimumLength,
              maximumPasswordLength: _unlockPasswordMaximumLength,
            );
            recoveryVerification = await _crypto.openWithRecovery(
              envelope: nextEnvelope,
              answers: answers,
              deviceSecret: deviceSecret,
            );
          } finally {
            passwordVerification?.dataKey.destroy();
            recoveryVerification?.dataKey.destroy();
          }
        },
      );
      current = null;
      return result;
    } finally {
      current?.session.close();
    }
  });

  Future<VaultOpenResult> disableRecovery({
    required String currentMasterPassword,
  }) => _runExclusive(() async {
    final directory = await _directoryProvider();
    await _rollbackInterruptedPasswordChange(directory);
    VaultOpenResult? current;
    try {
      current = await _unlock(masterPassword: currentMasterPassword);
      final session = current.session;
      if (session is! _EncryptedVaultSession) {
        throw const VaultStorageException();
      }
      final nextEnvelope = await _crypto.disableRecoveryNext(
        previous: session._envelope,
        dataKey: session._dataKey,
        snapshot: current.snapshot,
      );
      final result = await _commitCredentialTransition(
        directory: directory,
        current: current,
        nextEnvelope: nextEnvelope,
        verify: () async {
          VaultCryptoMaterial? verification;
          try {
            verification = await _crypto.open(
              masterPassword: currentMasterPassword,
              envelope: nextEnvelope,
              minimumPasswordLength: _unlockPasswordMinimumLength,
              maximumPasswordLength: _unlockPasswordMaximumLength,
            );
          } finally {
            verification?.dataKey.destroy();
          }
        },
      );
      current = null;
      return result;
    } finally {
      current?.session.close();
    }
  });

  Future<VaultOpenResult> recoverMasterPassword({
    required List<String> answers,
    required Uint8List deviceSecret,
    required String newMasterPassword,
    Future<void> Function()? beforeCredentialCommit,
  }) => _runExclusive(() async {
    _validatePasswordValue(
      newMasterPassword,
      minimum: _creationPasswordMinimumLength,
      maximum: _creationPasswordMaximumLength,
    );
    final directory = await _directoryProvider();
    await _rollbackInterruptedPasswordChange(directory);
    VaultOpenResult? current;
    VaultCryptoMaterial? rotated;
    final credentials = VaultRecoveryCredentials(
      answers: answers,
      deviceSecret: deviceSecret,
    );
    try {
      current = await _unlockWithRecovery(
        directory: directory,
        answers: answers,
        deviceSecret: deviceSecret,
      );
      final session = current.session;
      if (session is! _EncryptedVaultSession) {
        throw const VaultStorageException();
      }
      await beforeCredentialCommit?.call();
      rotated = await _crypto.rotateDataKeyNext(
        previous: session._envelope,
        snapshot: current.snapshot,
        newPassword: newMasterPassword,
        kdf: _creationKdf,
        recoveryCredentials: credentials,
        minimumPasswordLength: _creationPasswordMinimumLength,
        maximumPasswordLength: _creationPasswordMaximumLength,
      );
      final nextEnvelope = rotated.envelope;
      final result = await _commitCredentialTransition(
        directory: directory,
        current: current,
        nextEnvelope: nextEnvelope,
        replacementDataKey: rotated.dataKey,
        verify: () async {
          VaultCryptoMaterial? passwordVerification;
          VaultCryptoMaterial? recoveryVerification;
          try {
            passwordVerification = await _crypto.open(
              masterPassword: newMasterPassword,
              envelope: nextEnvelope,
              minimumPasswordLength: _creationPasswordMinimumLength,
              maximumPasswordLength: _creationPasswordMaximumLength,
            );
            recoveryVerification = await _crypto.openWithRecovery(
              envelope: nextEnvelope,
              answers: answers,
              deviceSecret: deviceSecret,
            );
          } finally {
            passwordVerification?.dataKey.destroy();
            recoveryVerification?.dataKey.destroy();
          }
        },
      );
      rotated = null;
      current = null;
      return result;
    } finally {
      rotated?.dataKey.destroy();
      current?.session.close();
      credentials.destroy();
    }
  });

  /// 生成全新随机 256-bit DEK，原子更换密码并重新加密快照。
  ///
  /// 不可逆提交点是第一份 committed/floor 状态成功替换主状态文件：
  /// 在此之前任何失败都只允许旧槽；在此之后解锁必须拒绝 floor 以下的旧包装。
  Future<VaultOpenResult> changeMasterPassword({
    required String currentMasterPassword,
    required String newMasterPassword,
  }) => _runExclusive(
    () => _changeMasterPassword(
      currentMasterPassword: currentMasterPassword,
      newMasterPassword: newMasterPassword,
    ),
  );

  Future<VaultOpenResult> _changeMasterPassword({
    required String currentMasterPassword,
    required String newMasterPassword,
  }) async {
    if (currentMasterPassword == newMasterPassword) {
      throw const VaultPasswordUnchangedException();
    }
    _validatePasswordValue(
      newMasterPassword,
      minimum: _creationPasswordMinimumLength,
      maximum: _creationPasswordMaximumLength,
    );

    final directory = await _directoryProvider();
    await _rollbackInterruptedPasswordChange(directory);
    VaultOpenResult? current;
    VaultCryptoMaterial? rotated;
    var committed = false;
    try {
      current = await _unlock(masterPassword: currentMasterPassword);
      final session = current.session;
      if (session is! _EncryptedVaultSession) {
        throw const VaultStorageException();
      }

      final previousState = await _readPasswordChangeState(directory);
      final previousFloor = previousState?.minimumAcceptedGeneration ?? 1;
      rotated = await _crypto.rotateDataKeyNext(
        previous: session._envelope,
        snapshot: current.snapshot,
        newPassword: newMasterPassword,
        kdf: _creationKdf,
        minimumPasswordLength: _creationPasswordMinimumLength,
        maximumPasswordLength: _creationPasswordMaximumLength,
      );
      final nextEnvelope = rotated.envelope;
      final nextSlotIndex = session._activeSlotIndex == 0 ? 1 : 0;
      final nextBytes = nextEnvelope.toBytes();
      final nextDigest = await _sha256Base64(nextBytes);
      final prepared = _PasswordChangeState(
        revision: 0,
        phase: _PasswordChangePhase.prepared,
        minimumAcceptedGeneration: previousFloor,
        sourceGeneration: session._envelope.generation,
        targetGeneration: nextEnvelope.generation,
        targetSlotIndex: nextSlotIndex,
        targetEnvelopeDigest: nextDigest,
      );

      await session._stageDeviceConfigRekey(rotated.dataKey);
      // 在写入新槽前先固化两代 prepared；任何中断都会排除目标槽。
      await _writePasswordChangeState(directory, prepared);
      await _writePasswordChangeState(directory, prepared);
      await _commitEnvelope(
        directory: directory,
        slotIndex: nextSlotIndex,
        envelope: nextEnvelope,
        dataKey: rotated.dataKey,
      );

      VaultCryptoMaterial? verification;
      try {
        verification = await _crypto.open(
          masterPassword: newMasterPassword,
          envelope: nextEnvelope,
          minimumPasswordLength: _creationPasswordMinimumLength,
          maximumPasswordLength: _creationPasswordMaximumLength,
        );
        if (verification.envelope.generation != nextEnvelope.generation) {
          throw const VaultStorageException();
        }
      } finally {
        verification?.dataKey.destroy();
      }

      final committedState = prepared.copyWith(
        phase: _PasswordChangePhase.committed,
        minimumAcceptedGeneration: nextEnvelope.generation,
      );
      // 已验证的临时状态也会被读取逻辑视为候选。因此 final rename 抛错
      // 不一定表示提交失败：先重读并确认同一事务的 committed/floor，
      // 一旦可见就必须按成功接管新 DEK，不能把旧会话留给调用方。
      try {
        await _writePasswordChangeState(directory, committedState);
      } on Object catch (error, stackTrace) {
        var confirmedCommitted = false;
        try {
          final durableState = await _readPasswordChangeState(directory);
          confirmedCommitted =
              durableState?.isCommitted == true &&
              durableState!.minimumAcceptedGeneration ==
                  nextEnvelope.generation &&
              durableState.hasSameTransactionAs(committedState);
        } on Object {
          // 保留首次写入异常；无法确认 commit 时仍按未提交失败关闭。
        }
        if (!confirmedCommitted) {
          Error.throwWithStackTrace(error, stackTrace);
        }
      }
      committed = true;
      final retiredDataKey = session._dataKey;
      session._dataKey = rotated.dataKey;
      rotated = null;
      session
        .._activeSlotIndex = nextSlotIndex
        .._envelope = nextEnvelope;
      try {
        retiredDataKey.destroy();
      } on Object {
        // 活动会话已切换到新 DEK；旧缓冲的销毁为尽力内存清理。
      }

      // 再固化一代 committed，使主状态损坏时上一代仍是 fail-closed floor。
      try {
        await _writePasswordChangeState(directory, committedState);
      } on Object {
        // 首份 committed 已生效；后续解锁会尝试修复冗余，不可回退旧密码。
      }

      final retiredSlot = File(
        _join(directory.path, _slotNames[nextSlotIndex == 0 ? 1 : 0]),
      );
      try {
        if (await retiredSlot.exists()) {
          await retiredSlot.delete();
        }
      } on Object {
        // floor 已使旧槽不可被打开；文件清理只是第二道防线。
      }

      return VaultOpenResult(
        session: session,
        snapshot: current.snapshot,
        recoveredFromFallback: current.recoveredFromFallback,
      );
    } on Object {
      if (!committed) {
        rotated?.dataKey.destroy();
        current?.session.close();
      }
      rethrow;
    }
  }

  Future<_SlotEnvelope> _readCurrentEligibleCandidate(
    Directory directory,
  ) async {
    final passwordState = await _readPasswordChangeState(directory);
    final candidates = <_SlotEnvelope>[];
    var foundSlotFile = false;
    var encounteredInvalidSlot = false;
    var encounteredAccessFailure = false;
    for (var index = 0; index < _slotNames.length; index++) {
      final file = File(_join(directory.path, _slotNames[index]));
      if (!await file.exists()) continue;
      foundSlotFile = true;
      try {
        candidates.add(await _readSlotEnvelope(file, index));
      } on VaultUnsupportedEnvelopeVersionException {
        rethrow;
      } on VaultUnsupportedKdfProfileException {
        rethrow;
      } on VaultFormatException {
        encounteredInvalidSlot = true;
      } on FileSystemException {
        encounteredAccessFailure = true;
      }
    }
    if (!foundSlotFile) throw const VaultNotFoundException();
    if (candidates.isEmpty) {
      if (encounteredAccessFailure) throw const VaultStorageException();
      throw const VaultIntegrityException();
    }
    candidates.sort(
      (left, right) =>
          right.envelope.generation.compareTo(left.envelope.generation),
    );
    final eligible = candidates
        .where(
          (candidate) => _isPasswordCandidateEligible(candidate, passwordState),
        )
        .toList(growable: false);
    if (eligible.isEmpty) {
      if (passwordState?.isCommitted == true) {
        throw const VaultStorageException();
      }
      if (encounteredInvalidSlot) throw const VaultIntegrityException();
      throw const VaultNotFoundException();
    }
    return eligible.first;
  }

  Future<VaultOpenResult> _unlockWithRecovery({
    required Directory directory,
    required List<String> answers,
    required Uint8List deviceSecret,
  }) async {
    final passwordState = await _readPasswordChangeState(directory);
    final candidates = <_SlotEnvelope>[];
    var foundSlotFile = false;
    var encounteredInvalidSlot = false;
    var encounteredAccessFailure = false;
    var encounteredRejection = false;
    var encounteredIntegrityFailure = false;
    var encounteredConfiguredSlot = false;
    for (var index = 0; index < _slotNames.length; index++) {
      final file = File(_join(directory.path, _slotNames[index]));
      if (!await file.exists()) continue;
      foundSlotFile = true;
      try {
        candidates.add(await _readSlotEnvelope(file, index));
      } on VaultUnsupportedEnvelopeVersionException {
        rethrow;
      } on VaultUnsupportedKdfProfileException {
        rethrow;
      } on VaultFormatException {
        encounteredInvalidSlot = true;
      } on FileSystemException {
        encounteredAccessFailure = true;
      }
    }
    if (!foundSlotFile) throw const VaultNotFoundException();
    if (candidates.isEmpty && encounteredAccessFailure) {
      throw const VaultStorageException();
    }
    candidates.sort(
      (left, right) =>
          right.envelope.generation.compareTo(left.envelope.generation),
    );
    final eligible = candidates
        .where(
          (candidate) => _isPasswordCandidateEligible(candidate, passwordState),
        )
        .toList(growable: false);
    if (eligible.isEmpty && passwordState?.isCommitted == true) {
      throw const VaultStorageException();
    }
    for (var index = 0; index < eligible.length; index++) {
      final candidate = eligible[index];
      if (_crypto.getRecoveryChallenge(candidate.envelope) == null) continue;
      encounteredConfiguredSlot = true;
      try {
        final material = await _crypto.openWithRecovery(
          envelope: candidate.envelope,
          answers: answers,
          deviceSecret: deviceSecret,
        );
        return VaultOpenResult(
          session: await _openSession(
            directory: directory,
            activeSlotIndex: candidate.slotIndex,
            envelope: material.envelope,
            dataKey: material.dataKey,
            snapshot: material.snapshot,
          ),
          snapshot: material.snapshot,
          recoveredFromFallback:
              encounteredInvalidSlot || encounteredAccessFailure || index > 0,
        );
      } on VaultRecoveryRejectedException {
        encounteredRejection = true;
      } on VaultIntegrityException {
        encounteredIntegrityFailure = true;
      } on VaultUnsupportedSchemaVersionException {
        rethrow;
      } on VaultFormatException {
        encounteredIntegrityFailure = true;
      }
    }
    if (encounteredIntegrityFailure || encounteredInvalidSlot) {
      throw const VaultIntegrityException();
    }
    if (encounteredRejection) {
      throw const VaultRecoveryRejectedException();
    }
    if (!encounteredConfiguredSlot) {
      throw const VaultRecoveryNotConfiguredException();
    }
    throw const VaultRecoveryRejectedException();
  }

  Future<VaultOpenResult> _commitCredentialTransition({
    required Directory directory,
    required VaultOpenResult current,
    required VaultEnvelope nextEnvelope,
    required Future<void> Function() verify,
    SecretKeyData? replacementDataKey,
  }) async {
    final session = current.session;
    if (session is! _EncryptedVaultSession) {
      throw const VaultStorageException();
    }
    final previousState = await _readPasswordChangeState(directory);
    final previousFloor = previousState?.minimumAcceptedGeneration ?? 1;
    final nextSlotIndex = session._activeSlotIndex == 0 ? 1 : 0;
    final nextBytes = nextEnvelope.toBytes();
    final nextDigest = await _sha256Base64(nextBytes);
    final prepared = _PasswordChangeState(
      revision: 0,
      phase: _PasswordChangePhase.prepared,
      minimumAcceptedGeneration: previousFloor,
      sourceGeneration: session._envelope.generation,
      targetGeneration: nextEnvelope.generation,
      targetSlotIndex: nextSlotIndex,
      targetEnvelopeDigest: nextDigest,
    );
    if (replacementDataKey != null) {
      await session._stageDeviceConfigRekey(replacementDataKey);
    }
    await _writePasswordChangeState(directory, prepared);
    await _writePasswordChangeState(directory, prepared);
    await _commitEnvelope(
      directory: directory,
      slotIndex: nextSlotIndex,
      envelope: nextEnvelope,
      dataKey: replacementDataKey ?? session._dataKey,
    );
    await verify();

    final committedState = prepared.copyWith(
      phase: _PasswordChangePhase.committed,
      minimumAcceptedGeneration: nextEnvelope.generation,
    );
    try {
      await _writePasswordChangeState(directory, committedState);
    } on Object catch (error, stackTrace) {
      var confirmedCommitted = false;
      try {
        final durableState = await _readPasswordChangeState(directory);
        confirmedCommitted =
            durableState?.isCommitted == true &&
            durableState!.minimumAcceptedGeneration ==
                nextEnvelope.generation &&
            durableState.hasSameTransactionAs(committedState);
      } on Object {
        // Preserve the first failure when no authoritative floor is visible.
      }
      if (!confirmedCommitted) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    if (replacementDataKey != null) {
      final retiredDataKey = session._dataKey;
      session._dataKey = replacementDataKey;
      try {
        retiredDataKey.destroy();
      } on Object {
        // The authoritative session already owns the replacement DEK.
      }
    }
    session
      .._activeSlotIndex = nextSlotIndex
      .._envelope = nextEnvelope;

    try {
      await _writePasswordChangeState(directory, committedState);
    } on Object {
      // The first committed floor is already authoritative.
    }
    final retiredSlot = File(
      _join(directory.path, _slotNames[nextSlotIndex == 0 ? 1 : 0]),
    );
    try {
      if (await retiredSlot.exists()) await retiredSlot.delete();
    } on Object {
      // The committed floor permanently excludes this best-effort residue.
    }
    return VaultOpenResult(
      session: session,
      snapshot: current.snapshot,
      recoveredFromFallback: current.recoveredFromFallback,
    );
  }

  /// Atomically replaces a non-authoritative derived vault without deleting
  /// the previous encrypted directory. The old directory is retained under a
  /// random retired name so a failed final rename can be rolled back.
  Future<void> replaceDerivedSnapshotAtomically({
    required String masterPassword,
    required VaultSnapshot snapshot,
  }) => _runExclusive(() async {
    final activeDirectory = await _directoryProvider();
    final suffixSource = SecretKeyData.random(length: 12);
    final suffix = base64UrlEncode(suffixSource.bytes).replaceAll('=', '');
    suffixSource.destroy();
    final stagingDirectory = Directory(
      '${activeDirectory.path}.rebuild.$suffix',
    );
    final retiredDirectory = Directory(
      '${activeDirectory.path}.retired.$suffix',
    );
    final stagingStore = EncryptedVaultStore(
      directoryProvider: () async => stagingDirectory,
      creationKdf: _creationKdf,
      quickUnlockSecretStore: _quickUnlockSecretStore,
      creationPasswordMinimumLength: _creationPasswordMinimumLength,
      creationPasswordMaximumLength: _creationPasswordMaximumLength,
      unlockPasswordMinimumLength: _unlockPasswordMinimumLength,
      unlockPasswordMaximumLength: _unlockPasswordMaximumLength,
    );
    VaultOpenResult? staged;
    try {
      staged = await stagingStore.create(masterPassword: masterPassword);
      await staged.session.save(snapshot);
      staged.session.close();
      staged = null;

      var retiredActive = false;
      if (await activeDirectory.exists()) {
        await activeDirectory.rename(retiredDirectory.path);
        retiredActive = true;
      }
      try {
        await stagingDirectory.rename(activeDirectory.path);
      } on Object {
        if (retiredActive &&
            !await activeDirectory.exists() &&
            await retiredDirectory.exists()) {
          await retiredDirectory.rename(activeDirectory.path);
        }
        rethrow;
      }
    } on VaultException {
      rethrow;
    } on Object {
      throw const VaultStorageException();
    } finally {
      staged?.session.close();
    }
  });

  @override
  Future<VaultSnapshot> readEncryptedBackup({
    required List<int> bytes,
    required String masterPassword,
  }) async {
    if (bytes.isEmpty || bytes.length > _maximumEnvelopeBytes) {
      throw const VaultFormatException();
    }
    VaultCryptoMaterial? material;
    try {
      material = await _crypto.open(
        masterPassword: masterPassword,
        envelope: VaultEnvelope.fromBytes(
          bytes,
          supportedKdfProfiles: _supportedKdfProfiles,
        ),
        minimumPasswordLength: _unlockPasswordMinimumLength,
        maximumPasswordLength: _unlockPasswordMaximumLength,
      );
      return material.snapshot;
    } on VaultException {
      rethrow;
    } on Object {
      throw const VaultUnlockException();
    } finally {
      material?.dataKey.destroy();
    }
  }

  @override
  Future<bool> isQuickUnlockEnabled() =>
      _quickUnlockSecretStore.containsSecret();

  @override
  Future<void> disableQuickUnlock() => _quickUnlockSecretStore.deleteSecret();

  @override
  Future<VaultOpenResult> unlockWithQuickUnlock() =>
      _runExclusive(_unlockWithQuickUnlock);

  Future<VaultOpenResult> _unlockWithQuickUnlock() async {
    QuickUnlockSecret? secret;
    SecretKeyData? dataKey;
    try {
      secret = await _quickUnlockSecretStore.readSecret();
      if (secret == null || secret.dataKey.length != 32) {
        throw const QuickUnlockException(
          QuickUnlockFailureReason.notConfigured,
          platformCode: 'not_configured',
        );
      }
      dataKey = SecretKeyData(
        Uint8List.fromList(secret.dataKey),
        overwriteWhenDestroyed: true,
      );
      final directory = await _directoryProvider();
      final passwordState = await _readPasswordChangeState(directory);
      final candidates = <_SlotEnvelope>[];
      var foundSlotFile = false;
      var encounteredInvalidSlot = false;
      for (var index = 0; index < _slotNames.length; index++) {
        final file = File(_join(directory.path, _slotNames[index]));
        if (!await file.exists()) {
          continue;
        }
        foundSlotFile = true;
        try {
          candidates.add(await _readSlotEnvelope(file, index));
        } on VaultUnsupportedEnvelopeVersionException {
          rethrow;
        } on VaultUnsupportedKdfProfileException {
          rethrow;
        } on VaultFormatException {
          encounteredInvalidSlot = true;
        }
      }
      if (!foundSlotFile) {
        throw const VaultNotFoundException();
      }
      candidates.sort(
        (left, right) =>
            right.envelope.generation.compareTo(left.envelope.generation),
      );
      final eligibleCandidates = candidates
          .where(
            (candidate) =>
                _isPasswordCandidateEligible(candidate, passwordState),
          )
          .toList(growable: false);
      if (eligibleCandidates.isEmpty && passwordState?.isCommitted == true) {
        throw const VaultStorageException();
      }
      for (var index = 0; index < eligibleCandidates.length; index++) {
        final candidate = eligibleCandidates[index];
        if (await _vaultId(candidate.envelope) != secret.vaultId) {
          continue;
        }
        try {
          final candidateDataKey = dataKey;
          if (candidateDataKey == null) {
            throw const VaultUnlockException();
          }
          final snapshot = await _crypto.decryptSnapshot(
            envelope: candidate.envelope,
            dataKey: candidateDataKey,
          );
          final ownedDataKey = candidateDataKey;
          dataKey = null;
          return VaultOpenResult(
            session: await _openSession(
              directory: directory,
              activeSlotIndex: candidate.slotIndex,
              envelope: candidate.envelope,
              dataKey: ownedDataKey,
              snapshot: snapshot,
            ),
            snapshot: snapshot,
            recoveredFromFallback: encounteredInvalidSlot || index > 0,
          );
        } on SecretBoxAuthenticationError {
          // A stale biometric key must not open an unrelated vault.
        } on VaultUnsupportedSchemaVersionException {
          rethrow;
        } on VaultFormatException {
          // Try the previous valid encrypted generation.
        }
      }
      throw const QuickUnlockException(
        QuickUnlockFailureReason.corruptedSecret,
        platformCode: 'corrupted_secret',
      );
    } on VaultException {
      rethrow;
    } on Object {
      throw const VaultUnlockException();
    } finally {
      secret?.destroy();
      dataKey?.destroy();
    }
  }

  Future<_EncryptedVaultSession> _openSession({
    required Directory directory,
    required int activeSlotIndex,
    required VaultEnvelope envelope,
    required SecretKeyData dataKey,
    required VaultSnapshot snapshot,
  }) async {
    final vaultBindingId = await _vaultId(envelope);
    final session = _EncryptedVaultSession(
      this,
      directory,
      activeSlotIndex,
      envelope,
      dataKey,
      vaultBindingId,
    );
    try {
      await session._restoreBatchRollbackState(snapshot);
      return session;
    } on Object {
      session.close();
      rethrow;
    }
  }

  Future<String> _vaultId(VaultEnvelope envelope) async {
    final stableId = envelope.vaultInstanceId;
    if (stableId != null) {
      return base64UrlEncode(stableId);
    }
    final digest = await Sha256().hash(<int>[
      ...envelope.salt,
      ...envelope.wrappedDataKey.concatenation(),
    ]);
    return base64UrlEncode(digest.bytes);
  }

  Future<void> _commitEnvelope({
    required Directory directory,
    required int slotIndex,
    required VaultEnvelope envelope,
    required SecretKeyData dataKey,
  }) async {
    final target = File(_join(directory.path, _slotNames[slotIndex]));
    final temporary = File('${target.path}.tmp');

    try {
      if (await temporary.exists()) {
        await temporary.delete();
      }
      await temporary.writeAsBytes(envelope.toBytes(), flush: true);

      final writtenEnvelope = await _readEnvelope(temporary);
      if (!_sameEnvelope(writtenEnvelope, envelope)) {
        throw const VaultStorageException();
      }
      await _crypto.decryptSnapshot(
        envelope: writtenEnvelope,
        dataKey: dataKey,
      );

      if (await target.exists()) {
        await target.delete();
      }
      await temporary.rename(target.path);
      await _afterEnvelopeCommitRenameForTesting?.call(envelope.generation);
    } on VaultException {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const VaultStorageException();
    } on Object {
      throw const VaultStorageException();
    }
  }

  Future<_SlotEnvelope> _readSlotEnvelope(File file, int slotIndex) async {
    final bytes = await _readEnvelopeBytes(file);
    return _SlotEnvelope(
      slotIndex: slotIndex,
      envelope: VaultEnvelope.fromBytes(
        bytes,
        supportedKdfProfiles: _supportedKdfProfiles,
      ),
      digest: await _sha256Base64(bytes),
    );
  }

  Future<VaultEnvelope> _readEnvelope(File file) async {
    return VaultEnvelope.fromBytes(
      await _readEnvelopeBytes(file),
      supportedKdfProfiles: _supportedKdfProfiles,
    );
  }

  Future<Uint8List> _readEnvelopeBytes(File file) async {
    final length = await file.length();
    if (length < 1 || length > _maximumEnvelopeBytes) {
      throw const VaultFormatException();
    }
    return file.readAsBytes();
  }

  bool _isPasswordCandidateEligible(
    _SlotEnvelope candidate,
    _PasswordChangeState? state,
  ) {
    if (state == null) return true;
    if (candidate.envelope.generation < state.minimumAcceptedGeneration) {
      return false;
    }
    if (state.isCommitted &&
        candidate.envelope.generation == state.targetGeneration &&
        candidate.digest != state.targetEnvelopeDigest) {
      // floor 所在目标代必须是提交时验证过的精确封套。否则旧 DEK
      // 会话可伪造同代 generation 并混入候选，导致旧密码复活。
      return false;
    }
    if (!state.isCommitted &&
        candidate.slotIndex == state.targetSlotIndex &&
        candidate.envelope.generation == state.targetGeneration &&
        candidate.digest == state.targetEnvelopeDigest) {
      return false;
    }
    return true;
  }

  Future<void> _rollbackInterruptedPasswordChange(Directory directory) async {
    final state = await _readPasswordChangeState(directory);
    if (state == null || state.isCommitted) return;

    final target = File(
      _join(directory.path, _slotNames[state.targetSlotIndex]),
    );
    if (await target.exists()) {
      final length = await target.length();
      final bytes = length > _maximumEnvelopeBytes
          ? Uint8List(0)
          : await target.readAsBytes();
      final digest = await _sha256Base64(bytes);
      if (digest == state.targetEnvelopeDigest) {
        await target.delete();
      } else {
        try {
          final envelope = VaultEnvelope.fromBytes(
            bytes,
            supportedKdfProfiles: _supportedKdfProfiles,
          );
          if (envelope.generation >= state.targetGeneration) {
            throw const VaultStorageException();
          }
        } on VaultStorageException {
          rethrow;
        } on Object {
          // 不完整的目标写入也不得成为后续候选槽。
          await target.delete();
        }
      }
    }

    final rolledBack = state.copyWith(phase: _PasswordChangePhase.rolledBack);
    await _writePasswordChangeState(directory, rolledBack);
    await _writePasswordChangeState(directory, rolledBack);
  }

  Future<_PasswordChangeState?> _readPasswordChangeState(
    Directory directory,
  ) async {
    final base = File(_join(directory.path, _passwordStateName));
    final locations = <File>[
      base,
      File('${base.path}.bak'),
      File('${base.path}.tmp.0'),
      File('${base.path}.tmp.1'),
    ];
    final candidates = <_PasswordChangeState>[];
    var found = false;
    var invalidDurableCandidate = false;
    for (final location in locations) {
      if (!await location.exists()) continue;
      found = true;
      try {
        candidates.add(await _readPasswordChangeCandidate(location));
      } on Object {
        if (!location.path.contains('.tmp.')) {
          invalidDurableCandidate = true;
        }
      }
    }
    if (!found) return null;
    if (candidates.isEmpty) {
      throw const VaultStorageException();
    }
    candidates.sort((left, right) => right.revision.compareTo(left.revision));
    final latest = candidates.first;
    // 损坏的更高代无法识别 revision。只有已提交 floor 才允许
    // 在其他状态候选损坏时继续，避免回退到 prepared 后复活旧密码。
    if (invalidDurableCandidate && !latest.isCommitted) {
      throw const VaultStorageException();
    }
    return latest;
  }

  Future<_PasswordChangeState> _readPasswordChangeCandidate(File file) async {
    final length = await file.length();
    if (length < 1 || length > _maximumPasswordStateBytes) {
      throw const VaultStorageException();
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<Object?, Object?> ||
        decoded['magic'] != _passwordStateMagic ||
        decoded['version'] != _passwordStateVersion) {
      throw const VaultStorageException();
    }
    final revision = decoded['revision'];
    final phaseName = decoded['phase'];
    final minimumAcceptedGeneration = decoded['minimumAcceptedGeneration'];
    final sourceGeneration = decoded['sourceGeneration'];
    final targetGeneration = decoded['targetGeneration'];
    final targetSlotIndex = decoded['targetSlotIndex'];
    final targetEnvelopeDigest = decoded['targetEnvelopeDigest'];
    _PasswordChangePhase? phase;
    if (phaseName is String) {
      for (final candidate in _PasswordChangePhase.values) {
        if (candidate.name == phaseName) {
          phase = candidate;
          break;
        }
      }
    }
    if (revision is! int ||
        revision < 1 ||
        revision > 1000000000 ||
        phase == null ||
        minimumAcceptedGeneration is! int ||
        minimumAcceptedGeneration < 1 ||
        sourceGeneration is! int ||
        targetGeneration is! int ||
        targetGeneration != sourceGeneration + 1 ||
        targetSlotIndex is! int ||
        targetSlotIndex < 0 ||
        targetSlotIndex >= _slotNames.length ||
        targetEnvelopeDigest is! String ||
        targetEnvelopeDigest.length < 40 ||
        targetEnvelopeDigest.length > 64) {
      throw const VaultStorageException();
    }
    if (phase != _PasswordChangePhase.committed &&
        sourceGeneration < minimumAcceptedGeneration) {
      throw const VaultStorageException();
    }
    if (phase == _PasswordChangePhase.committed &&
        minimumAcceptedGeneration != targetGeneration) {
      throw const VaultStorageException();
    }
    return _PasswordChangeState(
      revision: revision,
      phase: phase,
      minimumAcceptedGeneration: minimumAcceptedGeneration,
      sourceGeneration: sourceGeneration,
      targetGeneration: targetGeneration,
      targetSlotIndex: targetSlotIndex,
      targetEnvelopeDigest: targetEnvelopeDigest,
    );
  }

  Future<void> _writePasswordChangeState(
    Directory directory,
    _PasswordChangeState requested,
  ) async {
    await directory.create(recursive: true);
    final current = await _readPasswordChangeState(directory);
    final revision = current == null ? 1 : current.revision + 1;
    if (revision > 1000000000) {
      throw const VaultStorageException();
    }
    final next = requested.copyWith(revision: revision);
    final file = File(_join(directory.path, _passwordStateName));
    final backup = File('${file.path}.bak');
    final temporary = File('${file.path}.tmp.${revision & 1}');
    if (await temporary.exists()) await temporary.delete();
    await temporary.writeAsString(jsonEncode(next.toJson()), flush: true);
    final verified = await _readPasswordChangeCandidate(temporary);
    if (!verified.hasSameTransactionAs(next) ||
        verified.revision != next.revision ||
        verified.phase != next.phase ||
        verified.minimumAcceptedGeneration != next.minimumAcceptedGeneration) {
      throw const VaultStorageException();
    }
    if (await backup.exists()) await backup.delete();
    if (await file.exists()) await file.rename(backup.path);
    await _beforePasswordStateFinalRenameForTesting?.call(next.isCommitted);
    // 已验证 temporary 已是可恢复候选；rename 负责把它规范化为主文件。
    await temporary.rename(file.path);
  }

  static Future<String> _sha256Base64(List<int> bytes) async {
    final digest = await Sha256().hash(bytes);
    return base64UrlEncode(digest.bytes);
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) {
    final previous = _operationTail;
    final release = Completer<void>();
    _operationTail = release.future;

    return (() async {
      await previous;
      try {
        return await operation();
      } finally {
        release.complete();
      }
    })();
  }

  static bool _sameEnvelope(VaultEnvelope left, VaultEnvelope right) =>
      left.formatVersion == right.formatVersion &&
      _nullableBytesEqual(left.vaultInstanceId, right.vaultInstanceId) &&
      left.generation == right.generation &&
      left.kdf.memoryKiB == right.kdf.memoryKiB &&
      left.kdf.iterations == right.kdf.iterations &&
      left.kdf.parallelism == right.kdf.parallelism &&
      left.kdf.hashLength == right.kdf.hashLength &&
      _bytesEqual(left.salt, right.salt) &&
      _bytesEqual(
        left.wrappedDataKey.concatenation(),
        right.wrappedDataKey.concatenation(),
      ) &&
      _bytesEqual(
        left.payload.concatenation(),
        right.payload.concatenation(),
      ) &&
      jsonEncode(left.recoverySlot?.toJson()) ==
          jsonEncode(right.recoverySlot?.toJson());

  static bool _nullableBytesEqual(List<int>? left, List<int>? right) {
    if (left == null || right == null) return left == null && right == null;
    return _bytesEqual(left, right);
  }

  static bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  static void _validatePasswordPolicy({
    required int minimum,
    required int maximum,
  }) {
    if (minimum < 1 || maximum < minimum || maximum > 128) {
      throw ArgumentError('invalid password length policy');
    }
  }

  static void _validatePasswordValue(
    String password, {
    required int minimum,
    required int maximum,
  }) {
    _validatePasswordPolicy(minimum: minimum, maximum: maximum);
    final length = password.runes.length;
    if (length < minimum || length > maximum) {
      throw ArgumentError('密码长度不符合当前保险库策略');
    }
  }

  static String _join(String directory, String name) =>
      '$directory${Platform.pathSeparator}$name';
}

enum _PasswordChangePhase { prepared, committed, rolledBack }

final class _PasswordChangeState {
  const _PasswordChangeState({
    required this.revision,
    required this.phase,
    required this.minimumAcceptedGeneration,
    required this.sourceGeneration,
    required this.targetGeneration,
    required this.targetSlotIndex,
    required this.targetEnvelopeDigest,
  });

  final int revision;
  final _PasswordChangePhase phase;
  final int minimumAcceptedGeneration;
  final int sourceGeneration;
  final int targetGeneration;
  final int targetSlotIndex;
  final String targetEnvelopeDigest;

  bool get isCommitted => phase == _PasswordChangePhase.committed;

  _PasswordChangeState copyWith({
    int? revision,
    _PasswordChangePhase? phase,
    int? minimumAcceptedGeneration,
  }) => _PasswordChangeState(
    revision: revision ?? this.revision,
    phase: phase ?? this.phase,
    minimumAcceptedGeneration:
        minimumAcceptedGeneration ?? this.minimumAcceptedGeneration,
    sourceGeneration: sourceGeneration,
    targetGeneration: targetGeneration,
    targetSlotIndex: targetSlotIndex,
    targetEnvelopeDigest: targetEnvelopeDigest,
  );

  bool hasSameTransactionAs(_PasswordChangeState other) =>
      sourceGeneration == other.sourceGeneration &&
      targetGeneration == other.targetGeneration &&
      targetSlotIndex == other.targetSlotIndex &&
      targetEnvelopeDigest == other.targetEnvelopeDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'magic': EncryptedVaultStore._passwordStateMagic,
    'version': EncryptedVaultStore._passwordStateVersion,
    'revision': revision,
    'phase': phase.name,
    'minimumAcceptedGeneration': minimumAcceptedGeneration,
    'sourceGeneration': sourceGeneration,
    'targetGeneration': targetGeneration,
    'targetSlotIndex': targetSlotIndex,
    'targetEnvelopeDigest': targetEnvelopeDigest,
  };
}

final class _SlotEnvelope {
  const _SlotEnvelope({
    required this.slotIndex,
    required this.envelope,
    required this.digest,
  });

  final int slotIndex;
  final VaultEnvelope envelope;
  final String digest;
}

final class _EncryptedVaultSession
    implements
        VaultBoundSession,
        BatchRollbackVaultSession,
        NotificationReconciliationVaultSession,
        EditorDraftVaultSession,
        DeviceBackupConfigSession {
  _EncryptedVaultSession(
    this._store,
    this._directory,
    this._activeSlotIndex,
    this._envelope,
    this._dataKey,
    this.vaultBindingId,
  );

  final EncryptedVaultStore _store;
  final Directory _directory;
  @override
  final String vaultBindingId;
  SecretKeyData _dataKey;
  int _activeSlotIndex;
  VaultEnvelope _envelope;
  bool _closed = false;
  bool _saving = false;
  _BatchRollbackState? _batchRollback;
  BatchRollbackAvailability _batchRollbackAvailability =
      BatchRollbackAvailability.none;
  BatchRollbackSummary? _batchRollbackSummary;
  final NotificationReconciliationCodec _notificationReconciliationCodec =
      NotificationReconciliationCodec();

  File get _deviceBackupFile => File(
    EncryptedVaultStore._join(_directory.path, 'device_backup_config_v1.json'),
  );

  Future<Map<String, Object?>?> _readDeviceConfig() async {
    final next = File('${_deviceBackupFile.path}.next');
    for (final file in [next, _deviceBackupFile]) {
      if (!await file.exists()) continue;
      if (await file.length() > DeviceBackupConfigCodec.maximumBytes) {
        throw const VaultFormatException();
      }
      final bytes = await file.readAsBytes();
      final header = jsonDecode(utf8.decode(bytes));
      if (header is! Map || header['version'] != 1) {
        throw const VaultFormatException();
      }
      try {
        final result = await DeviceBackupConfigCodec().decode(
          bytes,
          _dataKey,
          vaultBindingId,
        );
        if (_closed) throw const VaultClosedException();
        // The new sidecar was staged before the password floor commit. Only
        // the committed new DEK can authenticate and promote it. Old sessions
        // retain the old file if that password transition was interrupted.
        if (file.path == next.path) await next.rename(_deviceBackupFile.path);
        return result;
      } on SecretBoxAuthenticationError {
        if (file.path != next.path) rethrow;
      }
    }
    return null;
  }

  Future<void> _stageDeviceConfigRekey(SecretKeyData replacement) async {
    final value = await _readDeviceConfig();
    if (value == null) return;
    final codec = DeviceBackupConfigCodec();
    final bytes = await codec.encode(value, replacement, vaultBindingId);
    final temporary = File('${_deviceBackupFile.path}.next.prepared');
    await temporary.writeAsBytes(bytes, flush: true);
    await codec.decode(
      await temporary.readAsBytes(),
      replacement,
      vaultBindingId,
    );
    await temporary.rename('${_deviceBackupFile.path}.next');
  }

  @override
  Future<Map<String, Object?>?> readDeviceBackupConfig() =>
      _store._runExclusive(() async {
        await _ensureOpenAndCurrentPasswordFloor();
        return _readDeviceConfig();
      });

  @override
  Future<void> writeDeviceBackupConfig(Map<String, Object?>? value) =>
      _store._runExclusive(() async {
        await _ensureOpenAndCurrentPasswordFloor();
        // Validate any existing version before replacing. Corrupt/future config
        // fails closed and cannot silently re-enable automatic file operations.
        await _readDeviceConfig();
        final codec = DeviceBackupConfigCodec();
        final bytes = await codec.encode(value, _dataKey, vaultBindingId);
        if (_closed) throw const VaultClosedException();
        final prepared = File('${_deviceBackupFile.path}.prepared');
        await prepared.writeAsBytes(bytes, flush: true);
        await codec.decode(
          await prepared.readAsBytes(),
          _dataKey,
          vaultBindingId,
        );
        if (_closed) throw const VaultClosedException();
        await prepared.rename(_deviceBackupFile.path);
      });

  File get _editorDraftFile =>
      File(EncryptedVaultStore._join(_directory.path, 'editor_draft_v1.json'));

  @override
  Future<Map<String, Object?>?> readEditorDraft() async {
    if (_closed || _dataKey.hasBeenDestroyed) {
      throw const VaultClosedException();
    }
    final key = SecretKeyData(Uint8List.fromList(_dataKey.bytes));
    try {
      return await _store._runExclusive(() async {
        await _ensureOpenAndCurrentPasswordFloor();
        final prepared = File('${_editorDraftFile.path}.prepared');
        for (final file in [prepared, _editorDraftFile]) {
          if (!await file.exists()) continue;
          try {
            if (await file.length() > EditorDraftCodec.maximumBytes) {
              throw const VaultFormatException();
            }
            final result = await EditorDraftCodec().decode(
              bytes: await file.readAsBytes(),
              key: key,
              binding: vaultBindingId,
              generation: generation,
            );
            if (_closed) throw const VaultClosedException();
            return result;
          } on UnsupportedEditorDraftVersion {
            rethrow;
          } on VaultClosedException {
            rethrow;
          } on Object {
            // A process can end during the staging write. The active file is
            // still the last authenticated, complete snapshot.
            if (file.path != prepared.path ||
                !await _editorDraftFile.exists()) {
              rethrow;
            }
          }
        }
        return null;
      });
    } finally {
      key.destroy();
    }
  }

  @override
  Future<void> writeEditorDraft(Map<String, Object?>? draft) async {
    if (_closed || _dataKey.hasBeenDestroyed) {
      throw const VaultClosedException();
    }
    // Admit the write before the first await. Locking may destroy the session
    // key while this small, already-authorized write finishes; the copy is
    // destroyed below and is never available to a subsequent locked caller.
    final key = SecretKeyData(Uint8List.fromList(_dataKey.bytes));
    final sourceGeneration = generation;
    try {
      final copied = draft == null
          ? null
          : Map<String, Object?>.from(jsonDecode(jsonEncode(draft)) as Map);
      await _store._runExclusive(() async {
        final passwordState = await _store._readPasswordChangeState(_directory);
        if (passwordState?.isCommitted == true &&
            sourceGeneration < passwordState!.minimumAcceptedGeneration) {
          throw const VaultClosedException();
        }
        for (final artifact in [
          _editorDraftFile,
          File('${_editorDraftFile.path}.prepared'),
        ]) {
          if (!await artifact.exists()) continue;
          if (await artifact.length() > EditorDraftCodec.maximumBytes) {
            throw const VaultFormatException();
          }
          Object? header;
          try {
            header = jsonDecode(await artifact.readAsString());
          } on FormatException {
            // Replace an interrupted current-format write, never a future format.
            continue;
          }
          if (header is Map &&
              header['version'] is int &&
              header['version'] != 1) {
            throw const UnsupportedEditorDraftVersion();
          }
        }
        final codec = EditorDraftCodec();
        final bytes = await codec.encode(
          draft: copied,
          key: key,
          binding: vaultBindingId,
          generation: sourceGeneration,
        );
        final prepared = File('${_editorDraftFile.path}.prepared');
        await prepared.writeAsBytes(bytes, flush: true);
        await codec.decode(
          bytes: await prepared.readAsBytes(),
          key: key,
          binding: vaultBindingId,
          generation: sourceGeneration,
        );
        await prepared.rename(_editorDraftFile.path);
      });
    } finally {
      key.destroy();
    }
  }

  @override
  int get generation => _envelope.generation;

  @override
  BatchRollbackAvailability get batchRollbackAvailability =>
      _closed ? BatchRollbackAvailability.none : _batchRollbackAvailability;

  @override
  BatchRollbackSummary? get lastBatchRollbackSummary =>
      canUndoLastBatch ? _batchRollbackSummary : null;

  @override
  bool get canUndoLastBatch {
    final rollback = _batchRollback;
    return !_closed &&
        !_saving &&
        _batchRollbackAvailability == BatchRollbackAvailability.available &&
        rollback != null &&
        rollback.committedGeneration == _envelope.generation;
  }

  @override
  Future<void> save(VaultSnapshot snapshot) async {
    if (_closed || _dataKey.hasBeenDestroyed) {
      throw const VaultClosedException();
    }
    if (_saving) {
      throw const VaultStorageException();
    }

    _saving = true;
    try {
      await _store._runExclusive(
        () => _saveSnapshotLocked(snapshot, invalidateBatchRollback: true),
      );
    } finally {
      _finishSaving();
    }
  }

  @override
  Future<void> saveBatchWithRollback({
    required VaultSnapshot before,
    required VaultSnapshot after,
  }) async {
    if (_closed || _dataKey.hasBeenDestroyed) {
      throw const VaultClosedException();
    }
    if (_saving) throw const VaultStorageException();
    _saving = true;
    try {
      await _store._runExclusive(() async {
        await _ensureOpenAndCurrentPasswordFloor();
        final current = await _store._crypto.decryptSnapshot(
          envelope: _envelope,
          dataKey: _dataKey,
        );
        if (jsonEncode(current.toEncryptedPayloadJson()) !=
            jsonEncode(before.toEncryptedPayloadJson())) {
          throw const VaultStorageException();
        }

        final rollbackEnvelope = await _store._crypto.encryptNext(
          previous: _envelope,
          dataKey: _dataKey,
          snapshot: before,
        );
        final active = _batchRollbackFile();
        final prepared = File('${active.path}.prepared');
        final superseded = File('${active.path}.superseded');
        await _writeVerifiedRollbackEnvelope(prepared, rollbackEnvelope);
        var mainSnapshotCommitted = false;
        try {
          if (await superseded.exists()) await superseded.delete();
          if (await active.exists()) await active.rename(superseded.path);
          await prepared.rename(active.path);
          try {
            await _saveSnapshotLocked(after, invalidateBatchRollback: false);
            mainSnapshotCommitted = true;
          } on Object {
            if (await active.exists()) await active.delete();
            if (await superseded.exists()) {
              await superseded.rename(active.path);
            }
            rethrow;
          }
          _batchRollback = _closed
              ? null
              : _BatchRollbackState(
                  committedGeneration: _envelope.generation,
                  envelope: rollbackEnvelope,
                );
          _batchRollbackAvailability = _closed
              ? BatchRollbackAvailability.none
              : BatchRollbackAvailability.available;
          _batchRollbackSummary = _closed
              ? null
              : _summarizeBatchRollback(before: before, after: after);
          await _deleteCommittedBatchArtifactBestEffort(superseded);
        } on Object {
          // prepared 尚未成为活动文件时，下一次批量导入并未成功；必须
          // 恢复上一份活动回滚点，不能仅因一次失败尝试使其失效。
          if (!mainSnapshotCommitted &&
              !await active.exists() &&
              await superseded.exists()) {
            await superseded.rename(active.path);
          }
          rethrow;
        } finally {
          if (mainSnapshotCommitted) {
            await _deleteCommittedBatchArtifactBestEffort(prepared);
          } else if (await prepared.exists()) {
            await prepared.delete();
          }
        }
      });
    } finally {
      _finishSaving();
    }
  }

  @override
  Future<VaultSnapshot> undoLastBatch() async {
    if (_closed || _dataKey.hasBeenDestroyed) {
      throw const VaultClosedException();
    }
    if (_saving) throw const VaultStorageException();
    _saving = true;
    try {
      return await _store._runExclusive(() async {
        final state = _batchRollback;
        if (state == null ||
            state.committedGeneration != _envelope.generation) {
          throw const VaultBatchRollbackUnavailableException();
        }
        await _ensureOpenAndCurrentPasswordFloor();
        final persistedMain = await _store._readCurrentEligibleCandidate(
          _directory,
        );
        if (!EncryptedVaultStore._sameEnvelope(
          persistedMain.envelope,
          _envelope,
        )) {
          // 另一已认证会话若已经推进主库 revision，本会话内存中的旧
          // generation 也不得成为覆盖新数据的依据。
          _batchRollback = null;
          _batchRollbackAvailability =
              BatchRollbackAvailability.revisionChanged;
          _batchRollbackSummary = null;
          throw const VaultBatchRollbackUnavailableException();
        }
        final active = _batchRollbackFile();
        final consuming = File('${active.path}.consuming');
        if (!await active.exists()) {
          _batchRollback = null;
          _batchRollbackAvailability = BatchRollbackAvailability.none;
          _batchRollbackSummary = null;
          throw const VaultBatchRollbackUnavailableException();
        }
        final writtenEnvelope = await _store._readEnvelope(active);
        if (!EncryptedVaultStore._sameEnvelope(
          writtenEnvelope,
          state.envelope,
        )) {
          _batchRollback = null;
          _batchRollbackAvailability = BatchRollbackAvailability.unreadable;
          _batchRollbackSummary = null;
          throw const VaultStorageException();
        }
        final previous = await _store._crypto.decryptSnapshot(
          envelope: writtenEnvelope,
          dataKey: _dataKey,
        );
        if (await consuming.exists()) await consuming.delete();
        await active.rename(consuming.path);
        try {
          await _saveSnapshotLocked(previous, invalidateBatchRollback: false);
        } on Object {
          if (await active.exists()) await active.delete();
          if (await consuming.exists()) await consuming.rename(active.path);
          rethrow;
        }
        // 固定活动路径已在主快照提交前移走；即使清理失败也无法重复撤销。
        _batchRollback = null;
        _batchRollbackAvailability = BatchRollbackAvailability.none;
        _batchRollbackSummary = null;
        try {
          if (await consuming.exists()) await consuming.delete();
        } on Object {
          // 仅留下不可再次访问的加密孤儿文件，不改变撤销结果。
        }
        return previous;
      });
    } finally {
      _finishSaving();
    }
  }

  @override
  Future<void> discardLastBatchRollback() async {
    if (_closed || _dataKey.hasBeenDestroyed) {
      throw const VaultClosedException();
    }
    if (_saving) throw const VaultStorageException();
    _saving = true;
    try {
      await _store._runExclusive(() async {
        await _ensureOpenAndCurrentPasswordFloor();
        final active = _batchRollbackFile();
        final artifacts = <File>[
          active,
          File('${active.path}.prepared'),
          File('${active.path}.superseded'),
          File('${active.path}.consuming'),
          File('${active.path}.recovered'),
        ];
        for (final artifact in artifacts) {
          if (await artifact.exists()) await artifact.delete();
        }
        final remaining = await Future.wait(
          artifacts.map((file) => file.exists()),
        );
        if (remaining.any((exists) => exists)) {
          throw const VaultStorageException();
        }
        _batchRollback = null;
        _batchRollbackAvailability = BatchRollbackAvailability.none;
        _batchRollbackSummary = null;
      });
    } finally {
      _finishSaving();
    }
  }

  @override
  Future<NotificationReconciliationState?>
  readNotificationReconciliation() => _store._runExclusive(() async {
    await _ensureOpenAndCurrentPasswordFloor();
    final decoded = await _readNotificationReconciliationState();
    final pending = decoded?.pending;
    if (pending == null) return null;
    if (pending.targetGeneration <= _envelope.generation) return pending;

    // A future-bound prepared item means the process stopped before the main
    // vault generation committed. Persist a tombstone so it can never attach
    // itself to an unrelated later write.
    await _writeNotificationReconciliationCleared(
      stateRevision: decoded!.stateRevision + 1,
    );
    return null;
  });

  @override
  Future<NotificationReconciliationState> prepareNotificationReconciliation({
    required int targetGeneration,
  }) => _store._runExclusive(() async {
    await _ensureOpenAndCurrentPasswordFloor();
    if (targetGeneration != _envelope.generation &&
        targetGeneration != _envelope.generation + 1) {
      throw const VaultStorageException();
    }
    DecodedNotificationReconciliationState? current;
    try {
      current = await _readNotificationReconciliationState();
    } on VaultStorageException {
      // 密码恢复/主密码轮换会生成全新 DEK；旧 companion 因而必须被视为
      // 不可继续消费，而不是让提醒协调永久卡死。当前业务快照仍是唯一权威
      // 来源，prepare 会用当前 DEK 和 vault binding 原子写入一份新的全量
      // 协调意图；损坏或跨库复制的 companion 也只能走同一安全重建路径。
      current = null;
    }
    final nextRevision = (current?.stateRevision ?? 0) + 1;
    if (nextRevision > 1000000000) {
      throw const VaultStorageException();
    }
    final randomId = SecretKeyData.random(length: 16);
    final operationId = base64UrlEncode(randomId.bytes);
    randomId.destroy();
    final state = NotificationReconciliationState(
      operationId: operationId,
      targetGeneration: targetGeneration,
      stateRevision: nextRevision,
      createdAtUtc: DateTime.now().toUtc(),
      attemptCount: 0,
    );
    await _writeNotificationReconciliationPending(state);
    return state;
  });

  @override
  Future<void> recordNotificationReconciliationFailure({
    required String operationId,
  }) => _store._runExclusive(() async {
    await _ensureOpenAndCurrentPasswordFloor();
    final decoded = await _readNotificationReconciliationState();
    final pending = decoded?.pending;
    if (pending == null || pending.operationId != operationId) return;
    if (pending.targetGeneration > _envelope.generation) {
      await _writeNotificationReconciliationCleared(
        stateRevision: decoded!.stateRevision + 1,
      );
      return;
    }
    final nextRevision = decoded!.stateRevision + 1;
    if (nextRevision > 1000000000 || pending.attemptCount >= 1000000) {
      throw const VaultStorageException();
    }
    await _writeNotificationReconciliationPending(
      pending.copyWith(
        stateRevision: nextRevision,
        attemptCount: pending.attemptCount + 1,
        lastAttemptAtUtc: DateTime.now().toUtc(),
      ),
    );
  });

  @override
  Future<void> completeNotificationReconciliation({
    required String operationId,
  }) => _store._runExclusive(() async {
    await _ensureOpenAndCurrentPasswordFloor();
    final decoded = await _readNotificationReconciliationState();
    final pending = decoded?.pending;
    if (pending == null || pending.operationId != operationId) return;
    await _writeNotificationReconciliationCleared(
      stateRevision: decoded!.stateRevision + 1,
    );
  });

  Future<DecodedNotificationReconciliationState?>
  _readNotificationReconciliationState() async {
    final active = _notificationReconciliationFile();
    final prepared = File('${active.path}.prepared');
    final previous = File('${active.path}.previous');
    final candidate = await active.exists()
        ? active
        : await prepared.exists()
        ? prepared
        : await previous.exists()
        ? previous
        : null;
    if (candidate == null) return null;
    try {
      final length = await candidate.length();
      if (length < 1 ||
          length > NotificationReconciliationCodec.maximumEncodedBytes) {
        throw const NotificationReconciliationFormatException();
      }
      return await _notificationReconciliationCodec.decode(
        encoded: await candidate.readAsBytes(),
        dataKey: _dataKey,
        vaultInstanceId: await _notificationReconciliationVaultBinding(),
      );
    } on NotificationReconciliationFormatException {
      throw const VaultStorageException();
    } on Object {
      throw const VaultStorageException();
    }
  }

  Future<void> _writeNotificationReconciliationPending(
    NotificationReconciliationState state,
  ) async {
    final encoded = await _notificationReconciliationCodec.encodePending(
      state: state,
      dataKey: _dataKey,
      vaultInstanceId: await _notificationReconciliationVaultBinding(),
    );
    await _commitNotificationReconciliationState(
      encoded: encoded,
      expectedRevision: state.stateRevision,
    );
  }

  Future<void> _writeNotificationReconciliationCleared({
    required int stateRevision,
  }) async {
    if (stateRevision < 1 || stateRevision > 1000000000) {
      throw const VaultStorageException();
    }
    final encoded = await _notificationReconciliationCodec.encodeCleared(
      stateRevision: stateRevision,
      dataKey: _dataKey,
      vaultInstanceId: await _notificationReconciliationVaultBinding(),
    );
    await _commitNotificationReconciliationState(
      encoded: encoded,
      expectedRevision: stateRevision,
    );
  }

  Future<void> _commitNotificationReconciliationState({
    required Uint8List encoded,
    required int expectedRevision,
  }) async {
    final active = _notificationReconciliationFile();
    final prepared = File('${active.path}.prepared');
    final previous = File('${active.path}.previous');
    if (await prepared.exists()) await prepared.delete();
    await prepared.writeAsBytes(encoded, flush: true);
    final verified = await _notificationReconciliationCodec.decode(
      encoded: await prepared.readAsBytes(),
      dataKey: _dataKey,
      vaultInstanceId: await _notificationReconciliationVaultBinding(),
    );
    if (verified.stateRevision != expectedRevision) {
      throw const VaultStorageException();
    }
    if (await previous.exists()) await previous.delete();
    if (await active.exists()) await active.rename(previous.path);
    await prepared.rename(active.path);
  }

  Future<Uint8List> _notificationReconciliationVaultBinding() async =>
      Uint8List.fromList(base64Url.decode(await _store._vaultId(_envelope)));

  File _notificationReconciliationFile() => File(
    EncryptedVaultStore._join(
      _directory.path,
      EncryptedVaultStore._notificationReconciliationName,
    ),
  );

  Future<void> _saveSnapshotLocked(
    VaultSnapshot snapshot, {
    required bool invalidateBatchRollback,
  }) async {
    await _ensureOpenAndCurrentPasswordFloor();
    final nextEnvelope = await _store._crypto.encryptNext(
      previous: _envelope,
      dataKey: _dataKey,
      snapshot: snapshot,
    );
    final nextSlotIndex = _activeSlotIndex == 0 ? 1 : 0;
    await _store._commitEnvelope(
      directory: _directory,
      slotIndex: nextSlotIndex,
      envelope: nextEnvelope,
      dataKey: _dataKey,
    );
    _activeSlotIndex = nextSlotIndex;
    _envelope = nextEnvelope;
    if (invalidateBatchRollback) {
      if (_batchRollbackAvailability == BatchRollbackAvailability.available ||
          _batchRollbackAvailability ==
              BatchRollbackAvailability.revisionChanged) {
        // 保留当前 DEK 下的认证密文，只撤销覆盖能力。这样锁定、进程结束或
        // 设备重启后仍能解释“导入后数据已变化”，而不会应用旧快照。
        _batchRollbackAvailability = BatchRollbackAvailability.revisionChanged;
      }
      _batchRollback = null;
      _batchRollbackSummary = null;
    }
  }

  Future<void> _restoreBatchRollbackState(VaultSnapshot current) async {
    _batchRollback = null;
    _batchRollbackAvailability = BatchRollbackAvailability.none;
    _batchRollbackSummary = null;

    final active = _batchRollbackFile();
    final artifacts = <File>[
      active,
      File('${active.path}.superseded'),
      File('${active.path}.consuming'),
      File('${active.path}.prepared'),
    ];
    final currentVaultId = await _store._vaultId(_envelope);
    final candidates = <_PersistedBatchRollback>[];
    var unreadableArtifactFound = false;
    for (final artifact in artifacts) {
      if (!await artifact.exists()) continue;
      try {
        final envelope = await _store._readEnvelope(artifact);
        if (await _store._vaultId(envelope) != currentVaultId) {
          unreadableArtifactFound = true;
          continue;
        }
        final previous = await _store._crypto.decryptSnapshot(
          envelope: envelope,
          dataKey: _dataKey,
        );
        candidates.add(
          _PersistedBatchRollback(
            file: artifact,
            envelope: envelope,
            previousSnapshot: previous,
          ),
        );
      } on Object {
        // 回滚旁路损坏或属于旧数据密钥时不得阻断主保险库解锁，也绝不
        // 因文件名存在而恢复覆盖能力。
        unreadableArtifactFound = true;
      }
    }

    _PersistedBatchRollback? matching;
    for (final candidate in candidates) {
      if (candidate.envelope.generation == _envelope.generation) {
        matching = candidate;
        break;
      }
    }
    if (matching != null) {
      VaultEnvelope promotedEnvelope;
      try {
        promotedEnvelope = await _promoteBatchRollbackCandidate(
          candidate: matching,
          active: active,
        );
      } on Object {
        // 回滚伴随文件的修复失败不得阻断主保险库解锁；在无法确认固定
        // 活动路径之前只暴露不可读状态，绝不授予覆盖能力。
        _batchRollbackAvailability = BatchRollbackAvailability.unreadable;
        return;
      }
      _batchRollback = _BatchRollbackState(
        committedGeneration: _envelope.generation,
        envelope: promotedEnvelope,
      );
      _batchRollbackAvailability = BatchRollbackAvailability.available;
      _batchRollbackSummary = _summarizeBatchRollback(
        before: matching.previousSnapshot,
        after: current,
      );
      await _cleanupInactiveBatchArtifactsBestEffort(active);
      return;
    }

    _PersistedBatchRollback? activeCandidate;
    for (final candidate in candidates) {
      if (candidate.file.path == active.path) {
        activeCandidate = candidate;
        break;
      }
    }
    if (activeCandidate != null &&
        activeCandidate.envelope.generation < _envelope.generation) {
      _batchRollbackAvailability = BatchRollbackAvailability.revisionChanged;
      await _cleanupInactiveBatchArtifactsBestEffort(active);
      return;
    }

    // consuming 的 generation 落后于主库，表示 undo 的主快照已经提交；
    // generation 超前则表示批量提交在主快照提交前中断。两者都不授予能力。
    await _cleanupInactiveBatchArtifactsBestEffort(active);
    if (unreadableArtifactFound) {
      _batchRollbackAvailability = BatchRollbackAvailability.unreadable;
    }
  }

  Future<VaultEnvelope> _promoteBatchRollbackCandidate({
    required _PersistedBatchRollback candidate,
    required File active,
  }) async {
    if (candidate.file.path == active.path) return candidate.envelope;
    final recovered = File('${active.path}.recovered');
    await _writeVerifiedRollbackEnvelope(recovered, candidate.envelope);
    if (await active.exists()) await active.delete();
    await recovered.rename(active.path);
    final promoted = await _store._readEnvelope(active);
    if (!EncryptedVaultStore._sameEnvelope(promoted, candidate.envelope)) {
      throw const VaultStorageException();
    }
    return promoted;
  }

  Future<void> _cleanupInactiveBatchArtifactsBestEffort(File active) async {
    for (final artifact in <File>[
      File('${active.path}.prepared'),
      File('${active.path}.superseded'),
      File('${active.path}.consuming'),
      File('${active.path}.recovered'),
    ]) {
      try {
        if (await artifact.exists()) await artifact.delete();
      } on Object {
        // 活动回滚点已经通过 DEK、vault id 和 generation 三重校验；
        // 非活动密文清理失败不会扩大其能力。
      }
    }
  }

  static BatchRollbackSummary _summarizeBatchRollback({
    required VaultSnapshot before,
    required VaultSnapshot after,
  }) {
    final beforeAccounts = <String, Map<String, Object?>>{
      for (final account in before.accounts)
        account.id: account.toEncryptedPayloadJson(),
    };
    var addedAccounts = 0;
    var updatedAccounts = 0;
    for (final account in after.accounts) {
      final previous = beforeAccounts[account.id];
      if (previous == null) {
        addedAccounts += 1;
      } else if (jsonEncode(previous) !=
          jsonEncode(account.toEncryptedPayloadJson())) {
        updatedAccounts += 1;
      }
    }
    final previousSubscriptionIds = before.subscriptions
        .map((item) => item.id)
        .toSet();
    final previousDraftIds = before.pendingSubscriptionDrafts
        .map((item) => item.draftId)
        .toSet();
    return BatchRollbackSummary(
      addedAccountCount: addedAccounts,
      updatedAccountCount: updatedAccounts,
      formalSubscriptionCount: after.subscriptions
          .where((item) => !previousSubscriptionIds.contains(item.id))
          .length,
      pendingSubscriptionDraftCount: after.pendingSubscriptionDrafts
          .where((item) => !previousDraftIds.contains(item.draftId))
          .length,
    );
  }

  Future<void> _ensureOpenAndCurrentPasswordFloor() async {
    if (_closed || _dataKey.hasBeenDestroyed) {
      throw const VaultClosedException();
    }
    final passwordState = await _store._readPasswordChangeState(_directory);
    if (passwordState?.isCommitted == true &&
        _envelope.generation < passwordState!.minimumAcceptedGeneration) {
      throw const VaultClosedException();
    }
  }

  File _batchRollbackFile() => File(
    EncryptedVaultStore._join(
      _directory.path,
      EncryptedVaultStore._batchRollbackName,
    ),
  );

  Future<void> _writeVerifiedRollbackEnvelope(
    File file,
    VaultEnvelope envelope,
  ) async {
    if (await file.exists()) await file.delete();
    await file.writeAsBytes(envelope.toBytes(), flush: true);
    final writtenEnvelope = await _store._readEnvelope(file);
    if (!EncryptedVaultStore._sameEnvelope(writtenEnvelope, envelope)) {
      throw const VaultStorageException();
    }
    await _store._crypto.decryptSnapshot(
      envelope: writtenEnvelope,
      dataKey: _dataKey,
    );
  }

  Future<void> _deleteCommittedBatchArtifactBestEffort(File file) async {
    try {
      if (!await file.exists()) return;
      await _store._beforeCommittedBatchCleanupForTesting?.call(file.path);
      await file.delete();
    } on Object {
      // 主快照提交点已经越过；清理失败只会留下当前 DEK 下的认证密文，
      // 不得把已落盘的批量提交反向误报为失败；新会话会按 vault id、
      // DEK 与精确 generation 重新鉴别活动回滚点并清理非活动残留。
    }
  }

  void _finishSaving() {
    _saving = false;
    if (!_closed) return;
    _batchRollback = null;
    _batchRollbackAvailability = BatchRollbackAvailability.none;
    _batchRollbackSummary = null;
    if (!_dataKey.hasBeenDestroyed) _dataKey.destroy();
  }

  @override
  Future<Uint8List> exportEncryptedBackup() async {
    if (_closed || _dataKey.hasBeenDestroyed || _saving) {
      throw const VaultClosedException();
    }
    return Uint8List.fromList(_envelope.toBytes());
  }

  @override
  Future<void> enableQuickUnlock() async {
    if (_closed || _dataKey.hasBeenDestroyed || _saving) {
      throw const VaultClosedException();
    }
    final secret = QuickUnlockSecret(
      vaultId: await _store._vaultId(_envelope),
      dataKey: _dataKey.bytes,
    );
    try {
      await _store._quickUnlockSecretStore.writeSecret(secret);
    } finally {
      secret.destroy();
    }
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _batchRollback = null;
    _batchRollbackAvailability = BatchRollbackAvailability.none;
    _batchRollbackSummary = null;
    if (!_saving && !_dataKey.hasBeenDestroyed) _dataKey.destroy();
  }
}

final class _PersistedBatchRollback {
  const _PersistedBatchRollback({
    required this.file,
    required this.envelope,
    required this.previousSnapshot,
  });

  final File file;
  final VaultEnvelope envelope;
  final VaultSnapshot previousSnapshot;
}

final class _BatchRollbackState {
  const _BatchRollbackState({
    required this.committedGeneration,
    required this.envelope,
  });

  final int committedGeneration;
  final VaultEnvelope envelope;
}
