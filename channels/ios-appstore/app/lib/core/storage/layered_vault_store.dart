import '../../features/subscriptions/domain/subscription_record.dart';
import 'dart:async';

import '../security/editor_draft.dart';
import '../security/device_backup_config.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/accounts/domain/account_record.dart';
import '../security/biometric_unlock.dart';
import '../notifications/notification_reconciliation_state.dart';
import '../security/recovery_device_secret.dart';
import '../security/vault_contract.dart';
import '../security/vault_crypto.dart';
import '../security/vault_recovery.dart';
import 'encrypted_vault_store.dart';

enum QuickUnlockScope { subscriptionsOnly, fullVault }

enum VaultAccessLevel { subscriptionsOnly, full }

abstract interface class ScopedVaultSession implements VaultSession {
  VaultAccessLevel get accessLevel;

  bool get canManageSecurity;
}

abstract interface class LayeredVaultSecurityController {
  Future<QuickUnlockScope?> configuredQuickUnlockScope();

  Future<void> configureQuickUnlock({
    required String currentMasterPassword,
    required QuickUnlockScope scope,
  });

  Future<bool> isDecoyVaultConfigured();

  Future<VaultRecoveryConfiguration> recoveryConfiguration();

  Future<VaultRecoveryChallenge?> recoveryChallenge();

  Future<VaultRecoveryChallenge> configureRecovery({
    required String currentMasterPassword,
    required List<String> questionIds,
    required List<String> answers,
    required VaultRecoveryEntryMode entryMode,
    VaultRecoveryScope scope = VaultRecoveryScope.primary,
    String? currentDecoyPassword,
  });

  Future<void> disableRecovery({
    required String currentMasterPassword,
    VaultRecoveryScope scope = VaultRecoveryScope.primary,
    String? currentDecoyPassword,
  });

  Future<VaultOpenResult> recoverMasterPassword({
    required List<String> questionIds,
    required List<String> answers,
    required String newMasterPassword,
    required VaultRecoveryEntryMode requestEntryMode,
    bool allowPrimaryRecovery = true,
    Future<void> Function()? beforePrimaryCommit,
  });

  Future<void> createDecoyVault({
    required String currentMasterPassword,
    required String decoyPassword,
  });

  Future<VaultOpenResult> changeMasterPassword({
    required String currentMasterPassword,
    required String newMasterPassword,
  });

  Future<void> changeDecoyPassword({
    required String currentMasterPassword,
    required String currentDecoyPassword,
    required String newDecoyPassword,
  });
}

/// 在不改写现有真实保险库格式的前提下增加两条严格隔离的能力：
///
/// 1. 生物识别“仅订阅”只打开独立加密、只读且去敏的订阅视图；
/// 2. 诱饵密码只打开独立保险库，并在返回诱饵会话前持久停用快速解锁。
///
/// 真实主库始终是业务权威。订阅视图从不包含登录账号、用户名、手机号、
/// 邮箱、网址、备注或账号密码。
final class LayeredVaultStore
    implements VaultStore, LayeredVaultSecurityController {
  factory LayeredVaultStore.appSupport() {
    final quickUnlockStore = BiometricQuickUnlockSecretStore();
    final recoveryDeviceSecretStore = BiometricRecoveryDeviceSecretStore();
    Future<Directory> child(String name) async {
      final support = await getApplicationSupportDirectory();
      return Directory('${support.path}${Platform.pathSeparator}$name');
    }

    return LayeredVaultStore._(
      primary: EncryptedVaultStore(
        directoryProvider: () => child('encrypted_vault_v1'),
        quickUnlockSecretStore: quickUnlockStore,
      ),
      subscriptionView: EncryptedVaultStore(
        directoryProvider: () => child('encrypted_subscription_view_v1'),
        quickUnlockSecretStore: quickUnlockStore,
      ),
      decoy: EncryptedVaultStore(
        directoryProvider: () => child('encrypted_vault_secondary_v1'),
        quickUnlockSecretStore: quickUnlockStore,
        creationPasswordMinimumLength: 6,
        creationPasswordMaximumLength: 32,
        unlockPasswordMinimumLength: 6,
        unlockPasswordMaximumLength: 128,
      ),
      stateFileProvider: () async {
        final support = await getApplicationSupportDirectory();
        return File(
          '${support.path}${Platform.pathSeparator}vault_access_state_v1.json',
        );
      },
      recoveryDeviceSecretStore: recoveryDeviceSecretStore,
    );
  }

  factory LayeredVaultStore.forDirectory({
    required Directory directory,
    VaultKdfParameters creationKdf = VaultKdfParameters.production,
    QuickUnlockSecretStore? quickUnlockSecretStore,
    RecoveryDeviceSecretStore? recoveryDeviceSecretStore,
  }) {
    final quickUnlockStore =
        quickUnlockSecretStore ?? BiometricQuickUnlockSecretStore();
    Directory child(String name) =>
        Directory('${directory.path}${Platform.pathSeparator}$name');

    return LayeredVaultStore._(
      primary: EncryptedVaultStore(
        directoryProvider: () async => child('encrypted_vault_v1'),
        creationKdf: creationKdf,
        quickUnlockSecretStore: quickUnlockStore,
      ),
      subscriptionView: EncryptedVaultStore(
        directoryProvider: () async => child('encrypted_subscription_view_v1'),
        creationKdf: creationKdf,
        quickUnlockSecretStore: quickUnlockStore,
      ),
      decoy: EncryptedVaultStore(
        directoryProvider: () async => child('encrypted_vault_secondary_v1'),
        creationKdf: creationKdf,
        quickUnlockSecretStore: quickUnlockStore,
        creationPasswordMinimumLength: 6,
        creationPasswordMaximumLength: 32,
        unlockPasswordMinimumLength: 6,
        unlockPasswordMaximumLength: 128,
      ),
      stateFileProvider: () async => File(
        '${directory.path}${Platform.pathSeparator}vault_access_state_v1.json',
      ),
      recoveryDeviceSecretStore:
          recoveryDeviceSecretStore ?? BiometricRecoveryDeviceSecretStore(),
    );
  }

  LayeredVaultStore._({
    required this._primary,
    required this._subscriptionView,
    required this._decoy,
    required this._stateFileProvider,
    required this._recoveryDeviceSecretStore,
  });

  static const _stateMagic = 'ASM_VAULT_ACCESS_STATE';
  static const _stateVersion = 1;
  static const _decoyRecoveryDeviceSecretInfo =
      'ASM_LOCAL_VAULT|decoy-recovery-device-secret|1';

  final EncryptedVaultStore _primary;
  final EncryptedVaultStore _subscriptionView;
  final EncryptedVaultStore _decoy;
  final Future<File> Function() _stateFileProvider;
  final RecoveryDeviceSecretStore _recoveryDeviceSecretStore;
  Future<void> _operationTail = Future<void>.value();

  @override
  Future<bool> exists() => _runExclusive(_primary.exists);

  @override
  Future<VaultOpenResult> create({required String masterPassword}) =>
      _runExclusive(() async {
        final result = await _primary.create(masterPassword: masterPassword);
        return VaultOpenResult(
          session: _LayeredVaultSession.primary(
            owner: this,
            primary: result.session,
          ),
          snapshot: result.snapshot,
          recoveredFromFallback: result.recoveredFromFallback,
        );
      });

  @override
  Future<VaultOpenResult> unlock({required String masterPassword}) =>
      _runExclusive(() => _unlock(masterPassword));

  Future<VaultOpenResult> _unlock(String masterPassword) async {
    try {
      final primary = await _primary.unlock(masterPassword: masterPassword);
      VaultOpenResult? subscriptionView;
      final state = await _effectiveState();
      if (state.scope == QuickUnlockScope.subscriptionsOnly &&
          !state.suspended) {
        await _writeState(state.copyWith(suspended: true));
        try {
          subscriptionView = await _openAndRefreshSubscriptionView(
            masterPassword: masterPassword,
            source: primary.snapshot,
          );
          await _writeState(state.copyWith(suspended: false));
        } on Object {
          await _disableQuickUnlockBestEffort(state.copyWith(suspended: true));
          subscriptionView?.session.close();
          subscriptionView = null;
        }
      }
      return VaultOpenResult(
        session: _LayeredVaultSession.primary(
          owner: this,
          primary: primary.session,
          subscriptionView: subscriptionView?.session,
        ),
        snapshot: primary.snapshot,
        recoveredFromFallback:
            primary.recoveredFromFallback ||
            (subscriptionView?.recoveredFromFallback ?? false),
      );
    } on VaultCredentialRejectedException {
      try {
        return await _unlockDecoy(masterPassword);
      } on VaultNotFoundException {
        throw const VaultUnlockException();
      }
    }
  }

  Future<VaultOpenResult> _unlockDecoy(String password) async {
    final decoy = await _decoy.unlock(masterPassword: password);
    final current = await _effectiveState();
    final suspended = current.copyWith(suspended: true);

    // 顺序是安全边界：先把软件停用状态持久化，再删除 Keystore 绑定，
    // 最后才允许诱饵界面出现。任一步无法确认时均不打开诱饵库。
    await _writeState(suspended);
    // 连续固化两代停用状态；即使最新主文件随后损坏，上一代也不会
    // 回退成可用的完整库生物识别配置。
    await _writeState(suspended);
    try {
      await _primary.disableQuickUnlock();
    } on Object {
      // 持久软件闸门已经关闭快速解锁。物理删除失败不会重新放行。
    }

    return VaultOpenResult(
      session: _LayeredVaultSession.decoy(owner: this, primary: decoy.session),
      snapshot: decoy.snapshot,
      recoveredFromFallback: decoy.recoveredFromFallback,
    );
  }

  @override
  Future<bool> isQuickUnlockEnabled() => _runExclusive(() async {
    final state = await _effectiveState();
    return !state.suspended &&
        state.scope != null &&
        await _primary.isQuickUnlockEnabled();
  });

  @override
  Future<QuickUnlockScope?> configuredQuickUnlockScope() =>
      _runExclusive(() async {
        final state = await _effectiveState();
        if (state.suspended || !await _primary.isQuickUnlockEnabled()) {
          return null;
        }
        return state.scope;
      });

  @override
  Future<VaultOpenResult> unlockWithQuickUnlock() => _runExclusive(() async {
    final state = await _effectiveState();
    if (state.suspended || state.scope == null) {
      throw const QuickUnlockException(
        QuickUnlockFailureReason.notConfigured,
        platformCode: 'software_suspended',
      );
    }
    if (state.scope == QuickUnlockScope.subscriptionsOnly) {
      final result = await _subscriptionView.unlockWithQuickUnlock();
      return VaultOpenResult(
        session: _LayeredVaultSession.subscriptionView(
          owner: this,
          primary: result.session,
        ),
        snapshot: result.snapshot,
        recoveredFromFallback: result.recoveredFromFallback,
      );
    }

    final result = await _primary.unlockWithQuickUnlock();
    return VaultOpenResult(
      session: _LayeredVaultSession.primary(
        owner: this,
        primary: result.session,
      ),
      snapshot: result.snapshot,
      recoveredFromFallback: result.recoveredFromFallback,
    );
  });

  @override
  Future<void> configureQuickUnlock({
    required String currentMasterPassword,
    required QuickUnlockScope scope,
  }) => _runExclusive(() async {
    VaultOpenResult? primary;
    VaultOpenResult? subscriptionView;
    _VaultAccessState? suspended;
    try {
      primary = await _primary.unlock(masterPassword: currentMasterPassword);
      suspended = (await _effectiveState()).copyWith(
        scope: scope,
        suspended: true,
      );
      await _writeState(suspended);
      if (scope == QuickUnlockScope.fullVault) {
        await primary.session.enableQuickUnlock();
      } else {
        subscriptionView = await _openAndRefreshSubscriptionView(
          masterPassword: currentMasterPassword,
          source: primary.snapshot,
        );
        await subscriptionView.session.enableQuickUnlock();
      }
      await _writeState(suspended.copyWith(suspended: false));
    } on Object {
      if (suspended != null) {
        await _disableQuickUnlockBestEffort(suspended);
      }
      rethrow;
    } finally {
      subscriptionView?.session.close();
      primary?.session.close();
    }
  });

  @override
  Future<void> disableQuickUnlock() => _runExclusive(() async {
    final current = await _effectiveState();
    await _primary.disableQuickUnlock();
    await _writeState(current.copyWith(clearScope: true, suspended: false));
  });

  @override
  Future<bool> isDecoyVaultConfigured() => _runExclusive(_decoy.exists);

  @override
  Future<VaultRecoveryConfiguration> recoveryConfiguration() =>
      _runExclusive(_recoveryConfiguration);

  @override
  Future<VaultRecoveryChallenge?> recoveryChallenge() => _runExclusive(
    () async => (await _recoveryConfiguration()).primaryChallenge,
  );

  @override
  Future<VaultRecoveryChallenge> configureRecovery({
    required String currentMasterPassword,
    required List<String> questionIds,
    required List<String> answers,
    required VaultRecoveryEntryMode entryMode,
    VaultRecoveryScope scope = VaultRecoveryScope.primary,
    String? currentDecoyPassword,
  }) => _runExclusive(() async {
    final before = await _recoveryConfiguration();
    if (before.challengeFor(scope) != null) {
      throw const VaultRecoveryRefreshRequiredException();
    }

    final target = _recoveryStoreFor(scope);
    final targetPassword = scope == VaultRecoveryScope.primary
        ? currentMasterPassword
        : currentDecoyPassword;
    if (targetPassword == null) {
      throw const VaultCredentialRejectedException();
    }

    VaultOpenResult? primaryVerification;
    RecoveryDeviceSecretMaterial? rootMaterial;
    Uint8List? scopedDeviceSecret;
    var rootWritten = false;
    VaultOpenResult? configured;
    try {
      if (scope == VaultRecoveryScope.decoy) {
        primaryVerification = await _primary.unlock(
          masterPassword: currentMasterPassword,
        );
      }

      final binding = await target.prepareRecoveryProvisioning(
        currentMasterPassword: targetPassword,
      );
      final otherChallenge = before.challengeFor(
        scope == VaultRecoveryScope.primary
            ? VaultRecoveryScope.decoy
            : VaultRecoveryScope.primary,
      );
      if (otherChallenge != null &&
          _sameRecoveryQuestionSet(otherChallenge.questionIds, questionIds)) {
        throw const VaultRecoveryQuestionSetConflictException();
      }

      if (otherChallenge == null) {
        final rootSource = SecretKeyData.random(length: 32);
        try {
          final bindingJson = binding.toJson();
          rootMaterial = RecoveryDeviceSecretMaterial(
            vaultInstanceId: bindingJson['vaultInstanceId']! as String,
            slotId: bindingJson['slotId']! as String,
            deviceBindingId: bindingJson['deviceBindingId']! as String,
            deviceSecret: rootSource.bytes,
          );
        } finally {
          rootSource.destroy();
        }
        await _recoveryDeviceSecretStore.write(rootMaterial);
        rootWritten = true;
      } else {
        // Adding slot two performs one strong-auth read and deliberately leaves
        // the legacy v1 native payload/alias/preferences untouched.
        rootMaterial = await _recoveryDeviceSecretStore.read();
        if (rootMaterial == null) {
          throw const VaultRecoveryRejectedException();
        }
      }

      scopedDeviceSecret = await _deviceSecretForRecoveryScope(
        scope: scope,
        binding: binding,
        deviceRoot: rootMaterial.deviceSecret,
      );
      if (scope == VaultRecoveryScope.primary) {
        await _suspendQuickUnlockForRecovery();
      }
      configured = await target.configureRecovery(
        currentMasterPassword: targetPassword,
        binding: binding,
        questionIds: questionIds,
        answers: answers,
        deviceSecret: scopedDeviceSecret,
        entryMode: entryMode,
      );
      configured.session.close();
      configured = null;
      return VaultRecoveryChallenge(
        binding: binding,
        questionIds: questionIds,
        entryMode: entryMode,
      );
    } on Object {
      var anyRecoveryWasCommitted = true;
      try {
        anyRecoveryWasCommitted =
            (await _recoveryConfiguration()).anyConfigured;
      } on Object {
        // Unknown durable state preserves the only possible device root.
      }
      if (rootWritten && !anyRecoveryWasCommitted) {
        try {
          await _recoveryDeviceSecretStore.delete();
        } on Object {
          // An orphaned random root cannot open an unconfigured envelope.
        }
      }
      rethrow;
    } finally {
      configured?.session.close();
      scopedDeviceSecret?.fillRange(0, scopedDeviceSecret.length, 0);
      rootMaterial?.destroy();
      primaryVerification?.session.close();
    }
  });

  @override
  Future<void> disableRecovery({
    required String currentMasterPassword,
    VaultRecoveryScope scope = VaultRecoveryScope.primary,
    String? currentDecoyPassword,
  }) => _runExclusive(() async {
    final before = await _recoveryConfiguration();
    final targetPassword = scope == VaultRecoveryScope.primary
        ? currentMasterPassword
        : currentDecoyPassword;
    if (targetPassword == null) {
      throw const VaultCredentialRejectedException();
    }
    VaultOpenResult? primaryVerification;
    VaultOpenResult? disabled;
    try {
      if (scope == VaultRecoveryScope.decoy) {
        primaryVerification = await _primary.unlock(
          masterPassword: currentMasterPassword,
        );
      }
      disabled = await _recoveryStoreFor(
        scope,
      ).disableRecovery(currentMasterPassword: targetPassword);
    } finally {
      disabled?.session.close();
      primaryVerification?.session.close();
    }

    final otherScope = scope == VaultRecoveryScope.primary
        ? VaultRecoveryScope.decoy
        : VaultRecoveryScope.primary;
    if (before.challengeFor(otherScope) == null) {
      try {
        await _recoveryDeviceSecretStore.delete();
      } on Object {
        // The last committed slot is gone; an orphan root opens no envelope.
      }
    }
  });

  @override
  Future<VaultOpenResult> recoverMasterPassword({
    required List<String> questionIds,
    required List<String> answers,
    required String newMasterPassword,
    required VaultRecoveryEntryMode requestEntryMode,
    bool allowPrimaryRecovery = true,
    Future<void> Function()? beforePrimaryCommit,
  }) => _runExclusive(() async {
    final replacementLength = newMasterPassword.runes.length;
    if (replacementLength < 8 || replacementLength > 128) {
      throw ArgumentError(
        'recovery replacement password must contain 8 to 128 characters',
      );
    }
    final material = await _recoveryDeviceSecretStore.read();
    Uint8List? dummyDeviceSecret;
    Uint8List? scopedDeviceSecret;
    VaultOpenResult? collision;
    VaultOpenResult? recovered;
    try {
      final configuration = await _recoveryConfiguration();
      final globallyAmbiguous =
          configuration.primaryChallenge != null &&
          configuration.decoyChallenge != null &&
          _sameRecoveryQuestionSet(
            configuration.primaryChallenge!.questionIds,
            configuration.decoyChallenge!.questionIds,
          );
      final candidates = <_ScopedRecoveryChallenge>[
        if (_matchesRecoveryRequest(
          configuration.primaryChallenge,
          questionIds,
          requestEntryMode,
        ))
          _ScopedRecoveryChallenge(
            VaultRecoveryScope.primary,
            configuration.primaryChallenge!,
          ),
        if (_matchesRecoveryRequest(
          configuration.decoyChallenge,
          questionIds,
          requestEntryMode,
        ))
          _ScopedRecoveryChallenge(
            VaultRecoveryScope.decoy,
            configuration.decoyChallenge!,
          ),
      ];
      if (material == null || globallyAmbiguous || candidates.length != 1) {
        dummyDeviceSecret = material == null
            ? _randomRecoveryDeviceSecret()
            : Uint8List.fromList(material.deviceSecret);
        await _performDummyPasswordWork(newMasterPassword);
        await _performDummyRecoveryWork(
          questionIds: questionIds,
          answers: answers,
          deviceSecret: dummyDeviceSecret,
        );
        throw const VaultRecoveryRejectedException();
      }

      final candidate = candidates.single;
      final candidateDeviceSecret = await _deviceSecretForRecoveryScope(
        scope: candidate.scope,
        binding: candidate.challenge.binding,
        deviceRoot: material.deviceSecret,
      );
      scopedDeviceSecret = candidateDeviceSecret;
      final orderedAnswers = _answersInChallengeOrder(
        selectedQuestionIds: questionIds,
        selectedAnswers: answers,
        challengeQuestionIds: candidate.challenge.questionIds,
      );
      if (orderedAnswers == null ||
          (candidate.scope == VaultRecoveryScope.primary &&
              !allowPrimaryRecovery)) {
        await _performDummyPasswordWork(newMasterPassword);
        await _performDummyRecoveryWork(
          questionIds: questionIds,
          answers: answers,
          deviceSecret: candidateDeviceSecret,
        );
        throw const VaultRecoveryRejectedException();
      }

      final otherStore = candidate.scope == VaultRecoveryScope.primary
          ? _decoy
          : _primary;
      var passwordCollision = false;
      try {
        if (await otherStore.exists()) {
          collision = await otherStore.unlock(
            masterPassword: newMasterPassword,
          );
          passwordCollision = true;
        } else {
          await _performDummyPasswordWork(newMasterPassword);
        }
      } on VaultCredentialRejectedException {
        // The new password does not route to the other vault.
      } on Object {
        // Before the recovery material is authenticated, storage and
        // integrity failures are deliberately folded into the same response.
        await _performDummyPasswordWork(newMasterPassword);
        await _performDummyRecoveryWork(
          questionIds: questionIds,
          answers: answers,
          deviceSecret: candidateDeviceSecret,
        );
        throw const VaultRecoveryRejectedException();
      } finally {
        collision?.session.close();
        collision = null;
      }
      if (passwordCollision) {
        await _performDummyRecoveryWork(
          questionIds: questionIds,
          answers: answers,
          deviceSecret: candidateDeviceSecret,
        );
        throw const VaultRecoveryRejectedException();
      }

      // Both scopes fail closed before any recovery password commit. This also
      // preserves the invariant that no decoy session is visible while a
      // primary quick-unlock key can still be used.
      await _suspendQuickUnlockForRecovery();
      recovered = await _recoveryStoreFor(candidate.scope)
          .recoverMasterPassword(
            answers: orderedAnswers,
            deviceSecret: candidateDeviceSecret,
            newMasterPassword: newMasterPassword,
            beforeCredentialCommit:
                candidate.scope == VaultRecoveryScope.primary
                ? beforePrimaryCommit
                : null,
          );

      if (candidate.scope == VaultRecoveryScope.primary) {
        try {
          await _subscriptionView.replaceDerivedSnapshotAtomically(
            masterPassword: newMasterPassword,
            snapshot: _subscriptionProjection(recovered.snapshot),
          );
        } on Object {
          // The primary commit is authoritative. Quick unlock stays suspended;
          // a later explicit enable will retry rebuilding this derived view.
        }
      }

      final result = VaultOpenResult(
        session: candidate.scope == VaultRecoveryScope.primary
            ? _LayeredVaultSession.primary(
                owner: this,
                primary: recovered.session,
              )
            : _LayeredVaultSession.decoy(
                owner: this,
                primary: recovered.session,
              ),
        snapshot: recovered.snapshot,
        recoveredFromFallback: recovered.recoveredFromFallback,
      );
      recovered = null;
      return result;
    } finally {
      recovered?.session.close();
      collision?.session.close();
      scopedDeviceSecret?.fillRange(0, scopedDeviceSecret.length, 0);
      dummyDeviceSecret?.fillRange(0, dummyDeviceSecret.length, 0);
      material?.destroy();
    }
  });

  @override
  Future<void> createDecoyVault({
    required String currentMasterPassword,
    required String decoyPassword,
  }) => _runExclusive(() async {
    if (currentMasterPassword == decoyPassword) {
      throw const DecoyPasswordConflictException();
    }
    VaultOpenResult? verification;
    VaultOpenResult? created;
    try {
      verification = await _primary.unlock(
        masterPassword: currentMasterPassword,
      );
      if (await _decoy.exists()) {
        throw const DecoyVaultAlreadyConfiguredException();
      }
      created = await _decoy.create(masterPassword: decoyPassword);
    } finally {
      created?.session.close();
      verification?.session.close();
    }
  });

  @override
  Future<VaultOpenResult> changeMasterPassword({
    required String currentMasterPassword,
    required String newMasterPassword,
  }) => _runExclusive(() async {
    if (currentMasterPassword == newMasterPassword) {
      throw const VaultPasswordUnchangedException();
    }

    VaultOpenResult? verification;
    VaultOpenResult? collision;
    try {
      // 先独立重新认证真实主密码，不依赖已解锁的 UI 会话。
      verification = await _primary.unlock(
        masterPassword: currentMasterPassword,
      );
      if (await _primary.recoveryChallenge() != null) {
        throw const VaultRecoveryRefreshRequiredException();
      }
      if (await _decoy.exists()) {
        try {
          collision = await _decoy.unlock(masterPassword: newMasterPassword);
          throw const DecoyPasswordConflictException();
        } on VaultCredentialRejectedException {
          // 新真实主密码没有命中诱饵库，可继续。
        }
      }
    } finally {
      collision?.session.close();
      verification?.session.close();
    }

    // 真实密码轮换前先把软件闸门连续固化两代。
    // 即使后续轮换失败，也只会安全降级为重新手动启用生物识别。
    final currentState = await _effectiveState();
    final suspended = currentState.copyWith(suspended: true);
    await _writeState(suspended);
    await _writeState(suspended);
    try {
      await _primary.disableQuickUnlock();
    } on Object {
      // 持久软件闸门已 fail-closed；Keystore 删除是第二道尽力防线。
    }

    // 订阅视图是派生库，但仍不得把旧主密码包装留在活动槽。
    // 先完成视图，再把真实主库作为最后的用户可见 commit point。
    if (await _subscriptionView.exists()) {
      VaultOpenResult? changedView;
      try {
        changedView = await _subscriptionView.changeMasterPassword(
          currentMasterPassword: currentMasterPassword,
          newMasterPassword: newMasterPassword,
        );
      } on VaultCredentialRejectedException {
        // 进程可能在上一次“视图已换、主库未换”后中断。
        // 若新密码已能打开视图，则将其视为可幂等续做的 prepared 结果。
        changedView = await _subscriptionView.unlock(
          masterPassword: newMasterPassword,
        );
      } finally {
        changedView?.session.close();
      }
    }

    final changedPrimary = await _primary.changeMasterPassword(
      currentMasterPassword: currentMasterPassword,
      newMasterPassword: newMasterPassword,
    );
    // 主库提交后不再执行可失败的外部操作。
    return VaultOpenResult(
      session: _LayeredVaultSession.primary(
        owner: this,
        primary: changedPrimary.session,
      ),
      snapshot: changedPrimary.snapshot,
      recoveredFromFallback: changedPrimary.recoveredFromFallback,
    );
  });

  @override
  Future<void> changeDecoyPassword({
    required String currentMasterPassword,
    required String currentDecoyPassword,
    required String newDecoyPassword,
  }) => _runExclusive(() async {
    if (currentDecoyPassword == newDecoyPassword) {
      throw const VaultPasswordUnchangedException();
    }

    VaultOpenResult? primaryVerification;
    VaultOpenResult? decoyVerification;
    VaultOpenResult? collision;
    VaultOpenResult? changedDecoy;
    try {
      // 双授权的第一部分：真实主密码必须当场重新认证。
      primaryVerification = await _primary.unlock(
        masterPassword: currentMasterPassword,
      );
      decoyVerification = await _decoy.unlock(
        masterPassword: currentDecoyPassword,
      );
      if (await _decoy.recoveryChallenge() != null) {
        throw const VaultRecoveryRefreshRequiredException();
      }
      try {
        collision = await _primary.unlock(masterPassword: newDecoyPassword);
        throw const DecoyPasswordConflictException();
      } on VaultCredentialRejectedException {
        // 新诱饵密码不能同时打开真实主库。
      }

      // 第二部分在 EncryptedVaultStore 中完成：当前诱饵密码
      // 必须能认证旧槽，然后生成全新诱饵 DEK 并重新加密快照。
      changedDecoy = await _decoy.changeMasterPassword(
        currentMasterPassword: currentDecoyPassword,
        newMasterPassword: newDecoyPassword,
      );
    } finally {
      changedDecoy?.session.close();
      collision?.session.close();
      decoyVerification?.session.close();
      primaryVerification?.session.close();
    }
    // 刻意不读写 vault_access_state，也不删除/重建快速解锁密钥。
  });

  @override
  Future<VaultSnapshot> readEncryptedBackup({
    required List<int> bytes,
    required String masterPassword,
  }) => _primary.readEncryptedBackup(
    bytes: bytes,
    masterPassword: masterPassword,
  );

  Future<VaultRecoveryConfiguration> _recoveryConfiguration() async =>
      VaultRecoveryConfiguration(
        primaryChallenge: await _optionalRecoveryChallenge(_primary),
        decoyChallenge: await _optionalRecoveryChallenge(_decoy),
      );

  static Future<VaultRecoveryChallenge?> _optionalRecoveryChallenge(
    EncryptedVaultStore store,
  ) async {
    try {
      return await store.recoveryChallenge();
    } on VaultNotFoundException {
      return null;
    }
  }

  EncryptedVaultStore _recoveryStoreFor(VaultRecoveryScope scope) =>
      switch (scope) {
        VaultRecoveryScope.primary => _primary,
        VaultRecoveryScope.decoy => _decoy,
      };

  Future<void> _suspendQuickUnlockForRecovery() async {
    final currentState = await _effectiveState();
    final suspended = currentState.copyWith(suspended: true);
    await _writeState(suspended);
    await _writeState(suspended);
    try {
      await _primary.disableQuickUnlock();
    } on Object {
      // The durable software gate is authoritative; key deletion is best effort.
    }
  }

  static bool _sameRecoveryQuestionSet(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    final leftSet = left.toSet();
    final rightSet = right.toSet();
    return leftSet.length == left.length &&
        rightSet.length == right.length &&
        leftSet.containsAll(rightSet);
  }

  static bool _matchesRecoveryRequest(
    VaultRecoveryChallenge? challenge,
    List<String> questionIds,
    VaultRecoveryEntryMode entryMode,
  ) =>
      challenge != null &&
      challenge.entryMode == entryMode &&
      _sameRecoveryQuestionSet(challenge.questionIds, questionIds);

  static List<String>? _answersInChallengeOrder({
    required List<String> selectedQuestionIds,
    required List<String> selectedAnswers,
    required List<String> challengeQuestionIds,
  }) {
    if (selectedQuestionIds.length != selectedAnswers.length ||
        selectedQuestionIds.length != challengeQuestionIds.length) {
      return null;
    }
    final byQuestion = <String, String>{};
    for (var index = 0; index < selectedQuestionIds.length; index++) {
      if (byQuestion.containsKey(selectedQuestionIds[index])) return null;
      byQuestion[selectedQuestionIds[index]] = selectedAnswers[index];
    }
    if (!challengeQuestionIds.every(byQuestion.containsKey)) return null;
    return <String>[
      for (final questionId in challengeQuestionIds) byQuestion[questionId]!,
    ];
  }

  static Uint8List _randomRecoveryDeviceSecret() {
    final source = SecretKeyData.random(length: 32);
    try {
      return Uint8List.fromList(source.bytes);
    } finally {
      source.destroy();
    }
  }

  Future<void> _performDummyPasswordWork(String password) async {
    VaultOpenResult? opened;
    try {
      opened = await _primary.unlock(masterPassword: password);
    } on Object {
      // Every outcome is intentionally ignored; this is only work equalization.
    } finally {
      opened?.session.close();
    }
  }

  static Future<void> _performDummyRecoveryWork({
    required List<String> questionIds,
    required List<String> answers,
    required Uint8List deviceSecret,
  }) async {
    Uint8List? replacementSecret;
    final safeSecret = deviceSecret.length == 32
        ? deviceSecret
        : (replacementSecret = _randomRecoveryDeviceSecret());
    try {
      try {
        await VaultRecoveryCrypto().performDummyVerification(
          questionIds: questionIds,
          answers: answers,
          deviceSecret: safeSecret,
        );
      } on ArgumentError {
        // Invalid caller-controlled shapes still pay one full KDF/AEAD path and
        // are converted by the caller to the same neutral rejection.
        await VaultRecoveryCrypto().performDummyVerification(
          questionIds: const <String>[
            'childhood_city',
            'first_school',
            'first_teacher',
          ],
          answers: const <String>['invalid-1', 'invalid-2', 'invalid-3'],
          deviceSecret: safeSecret,
        );
      }
    } finally {
      replacementSecret?.fillRange(0, replacementSecret.length, 0);
    }
  }

  static Future<Uint8List> _deviceSecretForRecoveryScope({
    required VaultRecoveryScope scope,
    required VaultRecoveryBinding binding,
    required Uint8List deviceRoot,
  }) async {
    if (deviceRoot.length != 32) {
      throw const VaultRecoveryRejectedException();
    }
    if (scope == VaultRecoveryScope.primary) {
      // Exact compatibility with every existing primary recovery slot.
      return Uint8List.fromList(deviceRoot);
    }

    final salt = binding.hkdfSalt();
    final rootKey = SecretKeyData(
      Uint8List.fromList(deviceRoot),
      overwriteWhenDestroyed: true,
    );
    SecretKey? derivedKey;
    SecretKeyData? extractedKey;
    try {
      derivedKey = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: rootKey,
        nonce: salt,
        info: utf8.encode(_decoyRecoveryDeviceSecretInfo),
      );
      extractedKey = await derivedKey.extract();
      return Uint8List.fromList(extractedKey.bytes);
    } finally {
      rootKey.destroy();
      if (!identical(extractedKey, derivedKey)) extractedKey?.destroy();
      derivedKey?.destroy();
      salt.fillRange(0, salt.length, 0);
    }
  }

  Future<VaultOpenResult> _openAndRefreshSubscriptionView({
    required String masterPassword,
    required VaultSnapshot source,
  }) async {
    final projection = _subscriptionProjection(source);
    late VaultOpenResult view;
    if (await _subscriptionView.exists()) {
      try {
        view = await _subscriptionView.unlock(masterPassword: masterPassword);
      } on VaultCredentialRejectedException {
        await _subscriptionView.replaceDerivedSnapshotAtomically(
          masterPassword: masterPassword,
          snapshot: projection,
        );
        view = await _subscriptionView.unlock(masterPassword: masterPassword);
      }
    } else {
      view = await _subscriptionView.create(masterPassword: masterPassword);
    }
    try {
      if (!_sameSnapshot(view.snapshot, projection)) {
        await view.session.save(projection);
      }
      return VaultOpenResult(
        session: view.session,
        snapshot: projection,
        recoveredFromFallback: view.recoveredFromFallback,
      );
    } on Object {
      view.session.close();
      rethrow;
    }
  }

  static VaultSnapshot _subscriptionProjection(VaultSnapshot source) {
    final subscriptionIds = source.subscriptions
        .map((subscription) => subscription.id)
        .toSet();
    final referencedIds = source.subscriptions
        .map((subscription) => subscription.accountId)
        .whereType<String>()
        .toSet();
    return VaultSnapshot(
      nextAccountId: source.nextAccountId,
      accounts: <AccountRecord>[
        for (final accountId in referencedIds)
          AccountRecord.fromDraft(
            id: accountId,
            draft: AccountDraft(platformName: '账号信息需主密码解锁'),
          ),
      ],
      nextSubscriptionId: source.nextSubscriptionId,
      paymentMethods: [
        for (final p in source.paymentMethods)
          PaymentMethodRecord(
            id: p.id,
            name: p.name,
            type: p.type,
            archived: p.archived,
          ),
      ],
      subscriptions: [
        for (final s in source.subscriptions)
          if (s.management == null)
            s
          else
            s.withManagement(
              SubscriptionManagement(
                trial: s.management!.trial,
                reminderRules: s.management!.reminderRules,
                priceHistory: [
                  for (final p in s.management!.priceHistory)
                    SubscriptionPricePoint(
                      id: p.id,
                      effectiveOn: p.effectiveOn,
                      amount: p.amount,
                      currency: p.currency,
                      cycleCount: p.cycleCount,
                      cycleUnit: p.cycleUnit,
                      kind: p.kind,
                      createdAt: p.createdAt,
                    ),
                ],
                historyIncomplete: s.management!.historyIncomplete,
                compatibilityBaseline:
                    s.management!.compatibilityBaseline == null
                    ? null
                    : SubscriptionPricePoint.fromJson({
                        ...s.management!.compatibilityBaseline!.toJson(),
                        'note': null,
                      }),
                paymentMethodId: s.management!.paymentMethodId,
              ),
            ),
      ],
      nextExpenseId: source.nextExpenseId,
      subscriptionExpenses: source.subscriptionExpenses
          .where(
            (expense) =>
                expense.subscriptionId != null &&
                subscriptionIds.contains(expense.subscriptionId),
          )
          .map(
            (expense) =>
                expense.withAccountContext(accountId: null, accountLabel: null),
          )
          .toList(growable: false),
      pendingSubscriptionDrafts: const [],
      preferences: source.preferences.copyWith(
        passwordReviewNotificationsEnabled: false,
      ),
      recentAccountIds: const <String>[],
    );
  }

  static bool _sameSnapshot(VaultSnapshot left, VaultSnapshot right) =>
      jsonEncode(left.toEncryptedPayloadJson()) ==
      jsonEncode(right.toEncryptedPayloadJson());

  Future<_VaultAccessState> _effectiveState() async {
    final state = await _readState();
    if (state.initialized) {
      return state;
    }
    // 0.5.1 及更早版本没有状态文件；已有 Keystore 绑定只能是完整库。
    if (await _primary.isQuickUnlockEnabled()) {
      final migrated = state.copyWith(
        scope: QuickUnlockScope.fullVault,
        suspended: false,
      );
      // 第一次由旧版本进入时立即落盘，后续写入不再依赖遗留推断。
      await _writeState(migrated);
      await _writeState(migrated);
      return _readState();
    }
    return state;
  }

  Future<_VaultAccessState> _readState() async {
    final file = await _stateFileProvider();
    final backup = File('${file.path}.bak');
    final legacyTemporary = File('${file.path}.tmp');
    final temporary0 = File('${file.path}.tmp.0');
    final temporary1 = File('${file.path}.tmp.1');
    final candidates = <_VaultAccessState>[];
    var foundFile = false;
    var foundInvalid = false;
    for (final candidateFile in <File>[
      file,
      backup,
      legacyTemporary,
      temporary0,
      temporary1,
    ]) {
      if (!await candidateFile.exists()) continue;
      foundFile = true;
      try {
        candidates.add(await _readStateFile(candidateFile));
      } on Object {
        foundInvalid = true;
      }
    }
    if (!foundFile) {
      return const _VaultAccessState();
    }
    if (candidates.isEmpty) {
      return const _VaultAccessState(
        generation: 1,
        suspended: true,
        initialized: true,
      );
    }
    candidates.sort(
      (left, right) => right.generation.compareTo(left.generation),
    );
    final latest = candidates.first;
    if (foundInvalid) {
      // 任一持久副本损坏都按停用处理，避免猜测哪个作用域仍可信。
      return latest.copyWith(suspended: true);
    }
    return latest;
  }

  Future<_VaultAccessState> _readStateFile(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<Object?, Object?> ||
        decoded['magic'] != _stateMagic ||
        decoded['version'] != _stateVersion ||
        decoded['generation'] is! int ||
        decoded['suspended'] is! bool) {
      throw const FormatException();
    }
    final generation = decoded['generation']! as int;
    final rawScope = decoded['quickUnlockScope'];
    final scope = switch (rawScope) {
      null => null,
      'subscriptionsOnly' => QuickUnlockScope.subscriptionsOnly,
      'fullVault' => QuickUnlockScope.fullVault,
      _ => throw const FormatException(),
    };
    if (generation < 1 || generation > 1000000000) {
      throw const FormatException();
    }
    return _VaultAccessState(
      generation: generation,
      scope: scope,
      suspended: decoded['suspended']! as bool,
      initialized: true,
    );
  }

  Future<void> _writeState(_VaultAccessState requested) async {
    final file = await _stateFileProvider();
    await file.parent.create(recursive: true);
    final current = await _readState();
    final generation = current.initialized ? current.generation + 1 : 1;
    if (generation > 1000000000) {
      throw const VaultStorageException();
    }
    final next = requested.copyWith(generation: generation, initialized: true);
    final temporary = File('${file.path}.tmp.${generation & 1}');
    final backup = File('${file.path}.bak');
    final staleTemporaries = <File>[
      File('${file.path}.tmp'),
      File('${file.path}.tmp.${(generation & 1) ^ 1}'),
    ];
    try {
      // 目标临时槽与上一代 generation 奇偶相反，删除它时至少仍保留
      // 当前最高有效代；写成并校验后，它会被读取逻辑视为最新安全状态。
      if (await temporary.exists()) await temporary.delete();
      await temporary.writeAsString(
        jsonEncode(<String, Object?>{
          'magic': _stateMagic,
          'version': _stateVersion,
          'generation': next.generation,
          'quickUnlockScope': next.scope?.name,
          'suspended': next.suspended,
        }),
        flush: true,
      );
      final decoded = jsonDecode(await temporary.readAsString());
      if (decoded is! Map<Object?, Object?> ||
          decoded['generation'] != next.generation ||
          decoded['quickUnlockScope'] != next.scope?.name ||
          decoded['suspended'] != next.suspended) {
        throw const VaultStorageException();
      }
      if (await backup.exists()) {
        await backup.delete();
      }
      if (await file.exists()) {
        await file.rename(backup.path);
      }
      await temporary.rename(file.path);
      for (final stale in staleTemporaries) {
        if (await stale.exists()) await stale.delete();
      }
    } on VaultException {
      rethrow;
    } on Object {
      throw const VaultStorageException();
    }
  }

  Future<void> _disableQuickUnlockBestEffort(
    _VaultAccessState suspended,
  ) async {
    try {
      await _writeState(suspended.copyWith(suspended: true));
    } on Object {
      // 调用方原本的失败仍需返回；下一次状态读取也会安全失败关闭。
    }
    try {
      await _primary.disableQuickUnlock();
    } on Object {
      // 软件状态优先；物理删除是第二道尽力防线。
    }
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
}

final class _ScopedRecoveryChallenge {
  const _ScopedRecoveryChallenge(this.scope, this.challenge);

  final VaultRecoveryScope scope;
  final VaultRecoveryChallenge challenge;
}

final class _LayeredVaultSession
    implements
        VaultBoundSession,
        ScopedVaultSession,
        BatchRollbackVaultSession,
        NotificationReconciliationVaultSession,
        EditorDraftVaultSession,
        DeviceBackupConfigSession {
  _LayeredVaultSession.primary({
    required this._owner,
    required this._primary,
    this._subscriptionView,
  }) : accessLevel = VaultAccessLevel.full,
       canManageSecurity = true,
       _isDecoy = false;

  _LayeredVaultSession.subscriptionView({
    required this._owner,
    required this._primary,
  }) : _subscriptionView = null,
       accessLevel = VaultAccessLevel.subscriptionsOnly,
       canManageSecurity = false,
       _isDecoy = false;

  _LayeredVaultSession.decoy({required this._owner, required this._primary})
    : _subscriptionView = null,
      accessLevel = VaultAccessLevel.full,
      canManageSecurity = false,
      _isDecoy = true;

  final LayeredVaultStore _owner;
  final VaultSession _primary;
  final VaultSession? _subscriptionView;
  final bool _isDecoy;
  bool _closed = false;

  @override
  final VaultAccessLevel accessLevel;

  @override
  final bool canManageSecurity;

  DeviceBackupConfigSession get _deviceBackupSession {
    final primary = _primary;
    if (_closed ||
        !canManageSecurity ||
        _isDecoy ||
        accessLevel != VaultAccessLevel.full ||
        primary is! DeviceBackupConfigSession) {
      throw const VaultClosedException();
    }
    return primary;
  }

  @override
  Future<Map<String, Object?>?> readDeviceBackupConfig() =>
      _deviceBackupSession.readDeviceBackupConfig();

  @override
  Future<void> writeDeviceBackupConfig(Map<String, Object?>? value) =>
      _deviceBackupSession.writeDeviceBackupConfig(value);

  EditorDraftVaultSession get _editorSession {
    final primary = _primary;
    if (_closed ||
        accessLevel != VaultAccessLevel.full ||
        primary is! EditorDraftVaultSession) {
      throw const VaultClosedException();
    }
    return primary;
  }

  @override
  Future<Map<String, Object?>?> readEditorDraft() =>
      _editorSession.readEditorDraft();

  @override
  Future<void> writeEditorDraft(Map<String, Object?>? draft) =>
      _editorSession.writeEditorDraft(draft);

  @override
  int get generation => _primary.generation;

  @override
  String get vaultBindingId {
    final primary = _primary;
    if (primary is! VaultBoundSession) {
      throw const VaultStorageException();
    }
    final scope = _isDecoy ? 'decoy' : 'primary';
    return '$scope:${primary.vaultBindingId}';
  }

  @override
  BatchRollbackAvailability get batchRollbackAvailability {
    if (_closed || accessLevel != VaultAccessLevel.full) {
      return BatchRollbackAvailability.none;
    }
    final primary = _primary;
    return primary is BatchRollbackVaultSession
        ? primary.batchRollbackAvailability
        : BatchRollbackAvailability.none;
  }

  @override
  BatchRollbackSummary? get lastBatchRollbackSummary {
    if (_closed || accessLevel != VaultAccessLevel.full) return null;
    final primary = _primary;
    return primary is BatchRollbackVaultSession
        ? primary.lastBatchRollbackSummary
        : null;
  }

  @override
  bool get canUndoLastBatch =>
      !_closed &&
      accessLevel == VaultAccessLevel.full &&
      _primary is BatchRollbackVaultSession &&
      _primary.canUndoLastBatch;

  @override
  Future<void> saveBatchWithRollback({
    required VaultSnapshot before,
    required VaultSnapshot after,
  }) async {
    if (_closed || accessLevel == VaultAccessLevel.subscriptionsOnly) {
      throw const VaultClosedException();
    }
    final primary = _primary;
    if (primary is! BatchRollbackVaultSession) {
      throw const VaultBatchRollbackUnavailableException();
    }
    if (_isDecoy) {
      await primary.saveBatchWithRollback(before: before, after: after);
      return;
    }

    final state = await _owner._effectiveState();
    final protectsSubscriptionView =
        state.scope == QuickUnlockScope.subscriptionsOnly && !state.suspended;
    if (protectsSubscriptionView) {
      await _owner._writeState(state.copyWith(suspended: true));
    }
    await primary.saveBatchWithRollback(before: before, after: after);
    if (!protectsSubscriptionView) return;
    final view = _subscriptionView;
    if (view == null) {
      await _owner._disableQuickUnlockBestEffort(
        state.copyWith(suspended: true),
      );
      throw const VaultCompanionSyncException();
    }
    try {
      await view.save(LayeredVaultStore._subscriptionProjection(after));
      await _owner._writeState(state.copyWith(suspended: false));
    } on Object {
      await _owner._disableQuickUnlockBestEffort(
        state.copyWith(suspended: true),
      );
      throw const VaultCompanionSyncException();
    }
  }

  @override
  Future<VaultSnapshot> undoLastBatch() async {
    if (!canUndoLastBatch) {
      throw const VaultBatchRollbackUnavailableException();
    }
    final primary = _primary as BatchRollbackVaultSession;
    if (_isDecoy) return primary.undoLastBatch();

    final state = await _owner._effectiveState();
    final protectsSubscriptionView =
        state.scope == QuickUnlockScope.subscriptionsOnly && !state.suspended;
    if (protectsSubscriptionView) {
      await _owner._writeState(state.copyWith(suspended: true));
    }
    final previous = await primary.undoLastBatch();
    if (!protectsSubscriptionView) return previous;
    final view = _subscriptionView;
    if (view == null) {
      await _owner._disableQuickUnlockBestEffort(
        state.copyWith(suspended: true),
      );
      return previous;
    }
    try {
      await view.save(LayeredVaultStore._subscriptionProjection(previous));
      await _owner._writeState(state.copyWith(suspended: false));
    } on Object {
      await _owner._disableQuickUnlockBestEffort(
        state.copyWith(suspended: true),
      );
    }
    return previous;
  }

  @override
  Future<void> discardLastBatchRollback() async {
    if (_closed || accessLevel != VaultAccessLevel.full) {
      throw const VaultClosedException();
    }
    final primary = _primary;
    if (primary is! BatchRollbackVaultSession) {
      throw const VaultBatchRollbackUnavailableException();
    }
    await primary.discardLastBatchRollback();
  }

  @override
  Future<NotificationReconciliationState?> readNotificationReconciliation() {
    final primary = _notificationReconciliationPrimary();
    return primary.readNotificationReconciliation();
  }

  @override
  Future<NotificationReconciliationState> prepareNotificationReconciliation({
    required int targetGeneration,
  }) {
    final primary = _notificationReconciliationPrimary();
    return primary.prepareNotificationReconciliation(
      targetGeneration: targetGeneration,
    );
  }

  @override
  Future<void> recordNotificationReconciliationFailure({
    required String operationId,
  }) {
    final primary = _notificationReconciliationPrimary();
    return primary.recordNotificationReconciliationFailure(
      operationId: operationId,
    );
  }

  @override
  Future<void> completeNotificationReconciliation({
    required String operationId,
  }) {
    final primary = _notificationReconciliationPrimary();
    return primary.completeNotificationReconciliation(operationId: operationId);
  }

  NotificationReconciliationVaultSession _notificationReconciliationPrimary() {
    if (_closed || !canManageSecurity || _isDecoy) {
      throw const VaultClosedException();
    }
    final primary = _primary;
    if (primary is! NotificationReconciliationVaultSession) {
      throw const VaultStorageException();
    }
    return primary;
  }

  @override
  Future<void> save(VaultSnapshot snapshot) async {
    if (_closed) {
      throw const VaultClosedException();
    }
    if (accessLevel == VaultAccessLevel.subscriptionsOnly) {
      throw const VaultClosedException();
    }
    if (_isDecoy) {
      await _primary.save(snapshot);
      return;
    }

    final state = await _owner._effectiveState();
    final protectsSubscriptionView =
        state.scope == QuickUnlockScope.subscriptionsOnly && !state.suspended;
    if (protectsSubscriptionView) {
      await _owner._writeState(state.copyWith(suspended: true));
    }
    await _primary.save(snapshot);
    if (!protectsSubscriptionView) {
      return;
    }

    final view = _subscriptionView;
    if (view == null) {
      await _owner._disableQuickUnlockBestEffort(
        state.copyWith(suspended: true),
      );
      throw const VaultCompanionSyncException();
    }
    try {
      await view.save(LayeredVaultStore._subscriptionProjection(snapshot));
      await _owner._writeState(state.copyWith(suspended: false));
    } on Object {
      await _owner._disableQuickUnlockBestEffort(
        state.copyWith(suspended: true),
      );
      throw const VaultCompanionSyncException();
    }
  }

  @override
  Future<Uint8List> exportEncryptedBackup() {
    if (_closed || accessLevel == VaultAccessLevel.subscriptionsOnly) {
      throw const VaultClosedException();
    }
    return _primary.exportEncryptedBackup();
  }

  @override
  Future<void> enableQuickUnlock() {
    if (_closed || !canManageSecurity || _isDecoy) {
      throw const QuickUnlockException(
        QuickUnlockFailureReason.notConfigured,
        platformCode: 'primary_password_required',
      );
    }
    return _primary.enableQuickUnlock();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _subscriptionView?.close();
    _primary.close();
  }
}

final class _VaultAccessState {
  const _VaultAccessState({
    this.generation = 0,
    this.scope,
    this.suspended = false,
    this.initialized = false,
  });

  final int generation;
  final QuickUnlockScope? scope;
  final bool suspended;
  final bool initialized;

  _VaultAccessState copyWith({
    int? generation,
    QuickUnlockScope? scope,
    bool clearScope = false,
    bool? suspended,
    bool? initialized,
  }) => _VaultAccessState(
    generation: generation ?? this.generation,
    scope: clearScope ? null : scope ?? this.scope,
    suspended: suspended ?? this.suspended,
    initialized: initialized ?? this.initialized,
  );
}
