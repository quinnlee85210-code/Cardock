import 'dart:convert';
import 'dart:io';

import 'package:account_subscription_manager/core/notifications/notification_reconciliation_state.dart';
import 'package:account_subscription_manager/core/security/biometric_unlock.dart';
import 'package:account_subscription_manager/core/security/recovery_device_secret.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/security/vault_recovery.dart';
import 'package:account_subscription_manager/core/storage/encrypted_vault_store.dart';
import 'package:account_subscription_manager/core/storage/layered_vault_store.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_expense_record.dart';
import 'package:flutter_test/flutter_test.dart';

const _realPassword = 'Real-Master-Password-2026!Safe';
const _decoyPassword = 'Decoy-Story-Password-2026!Safe';
const _testKdf = VaultKdfParameters(
  memoryKiB: 64,
  iterations: 1,
  parallelism: 1,
);

void main() {
  late Directory directory;
  late _MemoryQuickUnlockStore quickUnlock;
  late _MemoryRecoveryDeviceSecretStore recoveryDeviceSecret;
  late LayeredVaultStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('asm-layered-vault-');
    quickUnlock = _MemoryQuickUnlockStore();
    recoveryDeviceSecret = _MemoryRecoveryDeviceSecretStore();
    store = LayeredVaultStore.forDirectory(
      directory: directory,
      creationKdf: _testKdf,
      quickUnlockSecretStore: quickUnlock,
      recoveryDeviceSecretStore: recoveryDeviceSecret,
    );
  });

  tearDown(() async {
    quickUnlock.destroy();
    recoveryDeviceSecret.destroy();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('仅订阅生物识别不能取得任何账号秘密且会话只读', () async {
    final created = await store.create(masterPassword: _realPassword);
    final full = _snapshot(serviceName: '视频会员').copyWith(
      nextExpenseId: 2,
      subscriptionExpenses: [
        SubscriptionExpenseRecord.fromDraft(
          id: 'expense-1',
          recordedAtUtc: DateTime.utc(2026, 9, 3),
          draft: SubscriptionExpenseDraft(
            subscriptionId: 'subscription-1',
            accountId: 'account-1',
            serviceName: '视频会员',
            occurredOn: DateTime(2026, 9, 3),
            amount: '25',
            currency: 'CNY',
            kind: SubscriptionExpenseKind.payment,
          ),
        ).withAccountContext(
          accountId: 'account-1',
          accountLabel: 'real-login@example.test',
        ),
      ],
    );
    await created.session.save(full);
    created.session.close();

    await store.configureQuickUnlock(
      currentMasterPassword: _realPassword,
      scope: QuickUnlockScope.subscriptionsOnly,
    );
    final opened = await store.unlockWithQuickUnlock();
    final scoped = opened.session as ScopedVaultSession;

    expect(scoped.accessLevel, VaultAccessLevel.subscriptionsOnly);
    expect(scoped.canManageSecurity, isFalse);
    expect(opened.snapshot.subscriptions.single.serviceName, '视频会员');
    expect(opened.snapshot.accounts.single.platformName, '账号信息需主密码解锁');
    expect(opened.snapshot.accounts.single.loginAccount, isNull);
    expect(opened.snapshot.accounts.single.username, isNull);
    expect(opened.snapshot.accounts.single.boundPhone, isNull);
    expect(opened.snapshot.accounts.single.boundEmail, isNull);
    expect(opened.snapshot.accounts.single.password, isNull);
    expect(opened.snapshot.accounts.single.website, isNull);
    expect(opened.snapshot.accounts.single.notes, isNull);
    expect(opened.snapshot.accounts.single.passwordChangeHistory, isEmpty);
    expect(opened.snapshot.subscriptionExpenses.single.amount, '25');
    expect(opened.snapshot.subscriptionExpenses.single.accountId, isNull);
    expect(opened.snapshot.subscriptionExpenses.single.accountLabel, isNull);
    await expectLater(
      () => opened.session.save(opened.snapshot),
      throwsA(isA<VaultClosedException>()),
    );
    opened.session.close();

    final viewFiles = await Directory(
      '${directory.path}${Platform.pathSeparator}encrypted_subscription_view_v1',
    ).list().where((entry) => entry is File).cast<File>().toList();
    final joined = <int>[];
    for (final file in viewFiles) {
      joined.addAll(await file.readAsBytes());
    }
    final raw = String.fromCharCodes(joined);
    expect(raw, isNot(contains('real-login@example.test')));
    expect(raw, isNot(contains('REAL-ACCOUNT-PASSWORD')));
  });

  test('仅订阅生物识别保留独立订阅且不生成遮罩账号', () async {
    final created = await store.create(masterPassword: _realPassword);
    final standalone = SubscriptionRecord.fromDraft(
      id: 'subscription-standalone',
      draft: SubscriptionDraft(
        accountId: null,
        details: SubscriptionDetailsDraft(
          serviceName: '独立会员',
          firstSubscribedOn: DateTime(2026, 1, 1),
          nextRenewalOn: DateTime(2026, 9, 1),
        ),
      ),
    );
    await created.session.save(
      VaultSnapshot(
        nextAccountId: 1,
        accounts: const <AccountRecord>[],
        nextSubscriptionId: 2,
        subscriptions: <SubscriptionRecord>[standalone],
      ),
    );
    created.session.close();

    await store.configureQuickUnlock(
      currentMasterPassword: _realPassword,
      scope: QuickUnlockScope.subscriptionsOnly,
    );
    final opened = await store.unlockWithQuickUnlock();
    expect(opened.snapshot.accounts, isEmpty);
    expect(opened.snapshot.subscriptions.single.accountId, isNull);
    expect(opened.snapshot.subscriptions.single.serviceName, '独立会员');
    opened.session.close();
  });

  test('完整生物识别仍可由用户明确选择', () async {
    final created = await store.create(masterPassword: _realPassword);
    await created.session.save(_snapshot(serviceName: '完整模式'));
    created.session.close();

    await store.configureQuickUnlock(
      currentMasterPassword: _realPassword,
      scope: QuickUnlockScope.fullVault,
    );
    final opened = await store.unlockWithQuickUnlock();
    final scoped = opened.session as ScopedVaultSession;

    expect(scoped.accessLevel, VaultAccessLevel.full);
    expect(scoped.canManageSecurity, isTrue);
    expect(opened.snapshot.accounts.single.loginAccount, isNotNull);
    expect(
      await store.configuredQuickUnlockScope(),
      QuickUnlockScope.fullVault,
    );
    opened.session.close();
  });

  test('诱饵密码先持久停用生物识别且绝不修改真实库', () async {
    final created = await store.create(masterPassword: _realPassword);
    await created.session.save(_snapshot(serviceName: '真实订阅'));
    created.session.close();
    await store.configureQuickUnlock(
      currentMasterPassword: _realPassword,
      scope: QuickUnlockScope.fullVault,
    );
    await store.createDecoyVault(
      currentMasterPassword: _realPassword,
      decoyPassword: _decoyPassword,
    );

    final decoy = await store.unlock(masterPassword: _decoyPassword);
    final scoped = decoy.session as ScopedVaultSession;
    expect(scoped.accessLevel, VaultAccessLevel.full);
    expect(scoped.canManageSecurity, isFalse);
    expect(await store.isQuickUnlockEnabled(), isFalse);
    expect(quickUnlock.hasSecret, isFalse);
    await decoy.session.save(_snapshot(serviceName: '日常软件'));
    decoy.session.close();

    final real = await store.unlock(masterPassword: _realPassword);
    expect(real.snapshot.subscriptions.single.serviceName, '真实订阅');
    expect(await store.isQuickUnlockEnabled(), isFalse);
    real.session.close();

    await store.configureQuickUnlock(
      currentMasterPassword: _realPassword,
      scope: QuickUnlockScope.subscriptionsOnly,
    );
    expect(await store.isQuickUnlockEnabled(), isTrue);
  });

  test('诱饵停用闸门保留两代且 Keystore 删除失败也不重新放行', () async {
    final created = await store.create(masterPassword: _realPassword);
    created.session.close();
    await store.configureQuickUnlock(
      currentMasterPassword: _realPassword,
      scope: QuickUnlockScope.fullVault,
    );
    await store.createDecoyVault(
      currentMasterPassword: _realPassword,
      decoyPassword: _decoyPassword,
    );
    quickUnlock.failDelete = true;

    final decoy = await store.unlock(masterPassword: _decoyPassword);
    decoy.session.close();
    expect(quickUnlock.hasSecret, isTrue);
    expect(await store.isQuickUnlockEnabled(), isFalse);

    final stateFile = File(
      '${directory.path}${Platform.pathSeparator}vault_access_state_v1.json',
    );
    final backupFile = File('${stateFile.path}.bak');
    expect(await stateFile.exists(), isTrue);
    expect(await backupFile.exists(), isTrue);
    await stateFile.delete();

    expect(await store.isQuickUnlockEnabled(), isFalse);
    await expectLater(
      store.unlockWithQuickUnlock(),
      throwsA(isA<QuickUnlockException>()),
    );
  });

  test('状态替换中断时优先采用更高代临时停用闸门', () async {
    final created = await store.create(masterPassword: _realPassword);
    created.session.close();
    await store.configureQuickUnlock(
      currentMasterPassword: _realPassword,
      scope: QuickUnlockScope.fullVault,
    );

    final stateFile = File(
      '${directory.path}${Platform.pathSeparator}vault_access_state_v1.json',
    );
    final backupFile = File('${stateFile.path}.bak');
    final decoded = jsonDecode(await stateFile.readAsString()) as Map;
    final nextGeneration = (decoded['generation'] as int) + 1;
    decoded['generation'] = nextGeneration;
    decoded['suspended'] = true;
    final pending = File('${stateFile.path}.tmp.${nextGeneration & 1}');
    await pending.writeAsString(jsonEncode(decoded), flush: true);

    if (await backupFile.exists()) await backupFile.delete();
    await stateFile.rename(backupFile.path);

    expect(quickUnlock.hasSecret, isTrue);
    expect(await store.isQuickUnlockEnabled(), isFalse);
    await expectLater(
      store.unlockWithQuickUnlock(),
      throwsA(isA<QuickUnlockException>()),
    );
  });

  test('订阅视图随真实主密码会话更新且不会漏出账号字段', () async {
    final created = await store.create(masterPassword: _realPassword);
    await created.session.save(_snapshot(serviceName: '旧名称'));
    created.session.close();
    await store.configureQuickUnlock(
      currentMasterPassword: _realPassword,
      scope: QuickUnlockScope.subscriptionsOnly,
    );

    final real = await store.unlock(masterPassword: _realPassword);
    await real.session.save(_snapshot(serviceName: '新名称'));
    real.session.close();

    final limited = await store.unlockWithQuickUnlock();
    expect(limited.snapshot.subscriptions.single.serviceName, '新名称');
    expect(limited.snapshot.accounts.single.password, isNull);
    limited.session.close();
  });

  test('诱饵密码不能与真实主密码相同', () async {
    final created = await store.create(masterPassword: _realPassword);
    created.session.close();

    await expectLater(
      store.createDecoyVault(
        currentMasterPassword: _realPassword,
        decoyPassword: _realPassword,
      ),
      throwsA(isA<DecoyPasswordConflictException>()),
    );
  });

  test('真实主密码轮换同步订阅视图、停用快速解锁且不改诱饵库', () async {
    const newRealPassword = 'New-Real-Master-Password-2026!Safe';
    final created = await store.create(masterPassword: _realPassword);
    await created.session.save(_snapshot(serviceName: '真实订阅'));
    created.session.close();
    await store.createDecoyVault(
      currentMasterPassword: _realPassword,
      decoyPassword: _decoyPassword,
    );
    final decoy = await store.unlock(masterPassword: _decoyPassword);
    await decoy.session.save(_snapshot(serviceName: '诱饵订阅'));
    decoy.session.close();
    await store.configureQuickUnlock(
      currentMasterPassword: _realPassword,
      scope: QuickUnlockScope.subscriptionsOnly,
    );
    expect(await store.isQuickUnlockEnabled(), isTrue);
    expect(quickUnlock.hasSecret, isTrue);

    final changed = await store.changeMasterPassword(
      currentMasterPassword: _realPassword,
      newMasterPassword: newRealPassword,
    );
    expect(changed.snapshot.subscriptions.single.serviceName, '真实订阅');
    changed.session.close();
    expect(await store.isQuickUnlockEnabled(), isFalse);
    expect(quickUnlock.hasSecret, isFalse);

    await expectLater(
      store.unlock(masterPassword: _realPassword),
      throwsA(isA<VaultCredentialRejectedException>()),
    );
    final real = await store.unlock(masterPassword: newRealPassword);
    expect(real.snapshot.subscriptions.single.serviceName, '真实订阅');
    real.session.close();
    final unchangedDecoy = await store.unlock(masterPassword: _decoyPassword);
    expect(unchangedDecoy.snapshot.subscriptions.single.serviceName, '诱饵订阅');
    unchangedDecoy.session.close();

    // 只有用新真实主密码手动重新启用后，订阅视图才再次可用。
    await store.configureQuickUnlock(
      currentMasterPassword: newRealPassword,
      scope: QuickUnlockScope.subscriptionsOnly,
    );
    final limited = await store.unlockWithQuickUnlock();
    expect(limited.snapshot.subscriptions.single.serviceName, '真实订阅');
    limited.session.close();
  });

  test('诱饵密码修改要求真实与当前诱饵双授权，失败保留旧密码且不动主库', () async {
    const newDecoyPassword = '864209';
    final created = await store.create(masterPassword: _realPassword);
    await created.session.save(_snapshot(serviceName: '主库不变'));
    created.session.close();
    await store.createDecoyVault(
      currentMasterPassword: _realPassword,
      decoyPassword: _decoyPassword,
    );
    final decoy = await store.unlock(masterPassword: _decoyPassword);
    await decoy.session.save(_snapshot(serviceName: '诱饵数据保留'));
    decoy.session.close();
    await expectLater(
      store.changeDecoyPassword(
        currentMasterPassword: 'Wrong-Real-Master-Password-2026!',
        currentDecoyPassword: _decoyPassword,
        newDecoyPassword: newDecoyPassword,
      ),
      throwsA(isA<VaultCredentialRejectedException>()),
    );
    await expectLater(
      store.changeDecoyPassword(
        currentMasterPassword: _realPassword,
        currentDecoyPassword: 'Wrong-Decoy-Password-2026!',
        newDecoyPassword: newDecoyPassword,
      ),
      throwsA(isA<VaultCredentialRejectedException>()),
    );
    final oldAfterFailures = await store.unlock(masterPassword: _decoyPassword);
    oldAfterFailures.session.close();

    await store.configureQuickUnlock(
      currentMasterPassword: _realPassword,
      scope: QuickUnlockScope.fullVault,
    );
    final primaryDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}encrypted_vault_v1',
    );
    final primaryBefore = <String, List<int>>{
      for (final file in primaryDirectory.listSync().whereType<File>())
        file.path: await file.readAsBytes(),
    };

    await store.changeDecoyPassword(
      currentMasterPassword: _realPassword,
      currentDecoyPassword: _decoyPassword,
      newDecoyPassword: newDecoyPassword,
    );
    expect(await store.isQuickUnlockEnabled(), isTrue);
    expect(quickUnlock.hasSecret, isTrue);
    final primaryAfter = <String, List<int>>{
      for (final file in primaryDirectory.listSync().whereType<File>())
        file.path: await file.readAsBytes(),
    };
    expect(primaryAfter, equals(primaryBefore));

    await expectLater(
      store.unlock(masterPassword: _decoyPassword),
      throwsA(isA<VaultCredentialRejectedException>()),
    );
    final changedDecoy = await store.unlock(masterPassword: newDecoyPassword);
    expect(changedDecoy.snapshot.subscriptions.single.serviceName, '诱饵数据保留');
    changedDecoy.session.close();
    final real = await store.unlock(masterPassword: _realPassword);
    expect(real.snapshot.subscriptions.single.serviceName, '主库不变');
    real.session.close();
  });

  test('三问与设备因子共同恢复真实库并生成新密码和新 DEK', () async {
    final created = await store.create(masterPassword: _realPassword);
    await created.session.save(_snapshot(serviceName: '恢复前业务数据'));
    created.session.close();
    await store.configureQuickUnlock(
      currentMasterPassword: _realPassword,
      scope: QuickUnlockScope.subscriptionsOnly,
    );
    expect(await store.isQuickUnlockEnabled(), isTrue);

    final questionIds = vaultRecoveryQuestionCatalog
        .take(3)
        .map((question) => question.id)
        .toList(growable: false);
    const answers = <String>['杭州', '实验小学', '王老师'];
    final challenge = await store.configureRecovery(
      currentMasterPassword: _realPassword,
      questionIds: questionIds,
      answers: answers,
      entryMode: VaultRecoveryEntryMode.visible,
    );
    expect(challenge.questionIds, questionIds);
    expect(await store.isQuickUnlockEnabled(), isFalse);
    expect(recoveryDeviceSecret.isConfiguredValue, isTrue);
    var beforePrimaryCommitCalls = 0;
    await store.createDecoyVault(
      currentMasterPassword: _realPassword,
      decoyPassword: _decoyPassword,
    );
    final decoyDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}encrypted_vault_secondary_v1',
    );
    final decoyBeforeRecovery = await _encryptedDirectorySnapshot(
      decoyDirectory,
    );
    await expectLater(
      store.recoverMasterPassword(
        questionIds: questionIds,
        answers: const <String>['错误', '实验小学', '王老师'],
        newMasterPassword: 'Recovered-Master-26!Safe',
        requestEntryMode: VaultRecoveryEntryMode.visible,
        beforePrimaryCommit: () async {
          beforePrimaryCommitCalls += 1;
        },
      ),
      throwsA(isA<VaultRecoveryRejectedException>()),
    );
    expect(beforePrimaryCommitCalls, 0, reason: '错误答案不得进入预提交边界');

    await expectLater(
      store.recoverMasterPassword(
        questionIds: questionIds,
        answers: answers,
        newMasterPassword: 'Interrupted-Recovery-26!Safe',
        requestEntryMode: VaultRecoveryEntryMode.visible,
        beforePrimaryCommit: () async {
          beforePrimaryCommitCalls += 1;
          throw StateError('test-only rollback cleanup failure');
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(beforePrimaryCommitCalls, 1);
    final unchangedAfterCleanupFailure = await store.unlock(
      masterPassword: _realPassword,
    );
    unchangedAfterCleanupFailure.session.close();
    await expectLater(
      store.unlock(masterPassword: 'Interrupted-Recovery-26!Safe'),
      throwsA(isA<VaultCredentialRejectedException>()),
    );

    final recovered = await store.recoverMasterPassword(
      questionIds: questionIds,
      answers: answers,
      newMasterPassword: 'Recovered-Master-26!Safe',
      requestEntryMode: VaultRecoveryEntryMode.visible,
      beforePrimaryCommit: () async {
        beforePrimaryCommitCalls += 1;
      },
    );
    expect(beforePrimaryCommitCalls, 2);
    expect(recovered.snapshot.subscriptions.single.serviceName, '恢复前业务数据');
    recovered.session.close();
    await expectLater(
      store.unlock(masterPassword: _realPassword),
      throwsA(isA<VaultCredentialRejectedException>()),
    );
    final reopened = await store.unlock(
      masterPassword: 'Recovered-Master-26!Safe',
    );
    expect(
      reopened.snapshot.accounts.single.loginAccount,
      'real-login@example.test',
    );
    reopened.session.close();
    final unchangedDecoy = await store.unlock(masterPassword: _decoyPassword);
    unchangedDecoy.session.close();
    expect(
      await _encryptedDirectorySnapshot(decoyDirectory),
      decoyBeforeRecovery,
      reason: '真实库恢复不得改写诱饵库目录',
    );
    final configuration = await store.recoveryConfiguration();
    expect(configuration.primaryChallenge, isNotNull);
    expect(configuration.decoyChallenge, isNull);

    final viewStore = EncryptedVaultStore(
      directoryProvider: () async => Directory(
        '${directory.path}${Platform.pathSeparator}'
        'encrypted_subscription_view_v1',
      ),
      creationKdf: _testKdf,
      quickUnlockSecretStore: quickUnlock,
    );
    await expectLater(
      viewStore.unlock(masterPassword: _realPassword),
      throwsA(isA<VaultCredentialRejectedException>()),
    );
    final rebuiltView = await viewStore.unlock(
      masterPassword: 'Recovered-Master-26!Safe',
    );
    expect(rebuiltView.snapshot.accounts.single.loginAccount, isNull);
    rebuiltView.session.close();
  });

  test('已有诱饵库时仍可配置真实库密码恢复', () async {
    final created = await store.create(masterPassword: _realPassword);
    created.session.close();
    await store.createDecoyVault(
      currentMasterPassword: _realPassword,
      decoyPassword: _decoyPassword,
    );
    final challenge = await store.configureRecovery(
      currentMasterPassword: _realPassword,
      questionIds: vaultRecoveryQuestionCatalog
          .take(3)
          .map((question) => question.id)
          .toList(growable: false),
      answers: const <String>['杭州', '实验小学', '王老师'],
      entryMode: VaultRecoveryEntryMode.visible,
    );
    expect(challenge.questionIds, hasLength(3));
    expect(recoveryDeviceSecret.isConfiguredValue, isTrue);
  });

  test('双库恢复按题组与入口中性路由，诱饵恢复可连续使用且不改真实库', () async {
    final created = await store.create(masterPassword: _realPassword);
    await created.session.save(_snapshot(serviceName: '真实恢复隔离'));
    created.session.close();
    await store.createDecoyVault(
      currentMasterPassword: _realPassword,
      decoyPassword: _decoyPassword,
    );
    final decoy = await store.unlock(masterPassword: _decoyPassword);
    await decoy.session.save(_snapshot(serviceName: '诱饵恢复数据'));
    decoy.session.close();

    final primaryQuestionIds = vaultRecoveryQuestionCatalog
        .take(3)
        .map((question) => question.id)
        .toList(growable: false);
    final decoyQuestionIds = vaultRecoveryQuestionCatalog
        .skip(3)
        .take(3)
        .map((question) => question.id)
        .toList(growable: false);
    const primaryAnswers = <String>['杭州', '实验小学', '王老师'];
    const decoyAnswers = <String>['小李', '豆豆', '小王子'];
    await store.configureRecovery(
      currentMasterPassword: _realPassword,
      questionIds: primaryQuestionIds,
      answers: primaryAnswers,
      entryMode: VaultRecoveryEntryMode.visible,
    );
    expect(recoveryDeviceSecret.writeCount, 1);

    await expectLater(
      store.configureRecovery(
        currentMasterPassword: _realPassword,
        currentDecoyPassword: _decoyPassword,
        scope: VaultRecoveryScope.decoy,
        questionIds: primaryQuestionIds.reversed.toList(growable: false),
        answers: primaryAnswers.reversed.toList(growable: false),
        entryMode: VaultRecoveryEntryMode.logoFiveTap,
      ),
      throwsA(isA<VaultRecoveryQuestionSetConflictException>()),
    );
    expect(recoveryDeviceSecret.writeCount, 1);
    expect(recoveryDeviceSecret.readCount, 0);

    await store.configureRecovery(
      currentMasterPassword: _realPassword,
      currentDecoyPassword: _decoyPassword,
      scope: VaultRecoveryScope.decoy,
      questionIds: decoyQuestionIds,
      answers: decoyAnswers,
      entryMode: VaultRecoveryEntryMode.logoFiveTap,
    );
    expect(recoveryDeviceSecret.writeCount, 1);
    expect(recoveryDeviceSecret.readCount, 1);
    final configured = await store.recoveryConfiguration();
    expect(configured.primaryChallenge, isNotNull);
    expect(configured.decoyChallenge, isNotNull);

    await expectLater(
      store.recoverMasterPassword(
        questionIds: decoyQuestionIds,
        answers: decoyAnswers,
        newMasterPassword: 'Recovered-Decoy-26!Safe',
        requestEntryMode: VaultRecoveryEntryMode.visible,
      ),
      throwsA(isA<VaultRecoveryRejectedException>()),
    );
    await expectLater(
      store.recoverMasterPassword(
        questionIds: primaryQuestionIds,
        answers: primaryAnswers,
        newMasterPassword: 'Blocked-Primary-26!Safe',
        requestEntryMode: VaultRecoveryEntryMode.visible,
        allowPrimaryRecovery: false,
      ),
      throwsA(isA<VaultRecoveryRejectedException>()),
    );

    final primaryDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}encrypted_vault_v1',
    );
    final primaryBeforeRecovery = await _encryptedDirectorySnapshot(
      primaryDirectory,
    );
    final recoveredDecoy = await store.recoverMasterPassword(
      questionIds: <String>[
        decoyQuestionIds[2],
        decoyQuestionIds[0],
        decoyQuestionIds[1],
      ],
      answers: const <String>['小王子', '小李', '豆豆'],
      newMasterPassword: 'Recovered-Decoy-26!Safe',
      requestEntryMode: VaultRecoveryEntryMode.logoFiveTap,
      allowPrimaryRecovery: false,
    );
    expect(
      (recoveredDecoy.session as ScopedVaultSession).canManageSecurity,
      isFalse,
    );
    expect(recoveredDecoy.snapshot.subscriptions.single.serviceName, '诱饵恢复数据');
    recoveredDecoy.session.close();
    expect(
      await _encryptedDirectorySnapshot(primaryDirectory),
      primaryBeforeRecovery,
      reason: '诱饵恢复不得改写真实库目录',
    );

    final recoveredAgain = await store.recoverMasterPassword(
      questionIds: decoyQuestionIds,
      answers: decoyAnswers,
      newMasterPassword: 'Again-Decoy-26!Safe',
      requestEntryMode: VaultRecoveryEntryMode.logoFiveTap,
    );
    expect(recoveredAgain.snapshot.subscriptions.single.serviceName, '诱饵恢复数据');
    recoveredAgain.session.close();
    await expectLater(
      store.unlock(masterPassword: 'Recovered-Decoy-26!Safe'),
      throwsA(isA<VaultCredentialRejectedException>()),
    );
    final decoyAgain = await store.unlock(
      masterPassword: 'Again-Decoy-26!Safe',
    );
    decoyAgain.session.close();
    final afterSecondRecovery = await store.recoveryConfiguration();
    expect(
      afterSecondRecovery.decoyChallenge?.entryMode,
      VaultRecoveryEntryMode.logoFiveTap,
    );
    expect(afterSecondRecovery.decoyChallenge?.questionIds, decoyQuestionIds);

    await expectLater(
      store.changeDecoyPassword(
        currentMasterPassword: _realPassword,
        currentDecoyPassword: 'Again-Decoy-26!Safe',
        newDecoyPassword: 'Changed-Decoy-26!Safe',
      ),
      throwsA(isA<VaultRecoveryRefreshRequiredException>()),
    );
    final primaryStillOld = await store.unlock(masterPassword: _realPassword);
    primaryStillOld.session.close();
  });

  test('诱饵恢复可先配置且两槽共用公开入口时仍按不同题组中性路由', () async {
    final created = await store.create(masterPassword: _realPassword);
    await created.session.save(_snapshot(serviceName: '真实库同入口数据'));
    created.session.close();
    await store.createDecoyVault(
      currentMasterPassword: _realPassword,
      decoyPassword: _decoyPassword,
    );
    final decoy = await store.unlock(masterPassword: _decoyPassword);
    await decoy.session.save(_snapshot(serviceName: '诱饵库同入口数据'));
    decoy.session.close();

    final primaryQuestionIds = vaultRecoveryQuestionCatalog
        .take(3)
        .map((question) => question.id)
        .toList(growable: false);
    final decoyQuestionIds = vaultRecoveryQuestionCatalog
        .skip(3)
        .take(3)
        .map((question) => question.id)
        .toList(growable: false);
    const primaryAnswers = <String>['南京', '第二小学', '陈老师'];
    const decoyAnswers = <String>['阿明', '橘子', '星空'];

    await store.configureRecovery(
      currentMasterPassword: _realPassword,
      currentDecoyPassword: _decoyPassword,
      scope: VaultRecoveryScope.decoy,
      questionIds: decoyQuestionIds,
      answers: decoyAnswers,
      entryMode: VaultRecoveryEntryMode.visible,
    );
    expect(recoveryDeviceSecret.writeCount, 1);
    expect(recoveryDeviceSecret.readCount, 0);

    await store.configureRecovery(
      currentMasterPassword: _realPassword,
      questionIds: primaryQuestionIds,
      answers: primaryAnswers,
      entryMode: VaultRecoveryEntryMode.visible,
    );
    expect(recoveryDeviceSecret.writeCount, 1);
    expect(recoveryDeviceSecret.readCount, 1);

    final recoveredDecoy = await store.recoverMasterPassword(
      questionIds: decoyQuestionIds,
      answers: decoyAnswers,
      newMasterPassword: 'Visible-Decoy-26!Safe',
      requestEntryMode: VaultRecoveryEntryMode.visible,
    );
    expect(
      (recoveredDecoy.session as ScopedVaultSession).canManageSecurity,
      isFalse,
    );
    expect(
      recoveredDecoy.snapshot.subscriptions.single.serviceName,
      '诱饵库同入口数据',
    );
    recoveredDecoy.session.close();

    final recoveredPrimary = await store.recoverMasterPassword(
      questionIds: primaryQuestionIds,
      answers: primaryAnswers,
      newMasterPassword: 'Visible-Primary-26!Safe',
      requestEntryMode: VaultRecoveryEntryMode.visible,
    );
    expect(
      (recoveredPrimary.session as ScopedVaultSession).canManageSecurity,
      isTrue,
    );
    expect(
      recoveredPrimary.snapshot.subscriptions.single.serviceName,
      '真实库同入口数据',
    );
    recoveredPrimary.session.close();

    final reopenedDecoy = await store.unlock(
      masterPassword: 'Visible-Decoy-26!Safe',
    );
    reopenedDecoy.session.close();
    final reopenedPrimary = await store.unlock(
      masterPassword: 'Visible-Primary-26!Safe',
    );
    reopenedPrimary.session.close();
  });

  test('恢复新密码碰撞统一拒绝且关闭最后一槽才删除共享设备根因子', () async {
    final created = await store.create(masterPassword: _realPassword);
    created.session.close();
    await store.createDecoyVault(
      currentMasterPassword: _realPassword,
      decoyPassword: _decoyPassword,
    );
    final primaryQuestionIds = vaultRecoveryQuestionCatalog
        .take(3)
        .map((question) => question.id)
        .toList(growable: false);
    final decoyQuestionIds = vaultRecoveryQuestionCatalog
        .skip(3)
        .take(3)
        .map((question) => question.id)
        .toList(growable: false);
    const primaryAnswers = <String>['杭州', '实验小学', '王老师'];
    const decoyAnswers = <String>['小李', '豆豆', '小王子'];
    await store.configureRecovery(
      currentMasterPassword: _realPassword,
      questionIds: primaryQuestionIds,
      answers: primaryAnswers,
      entryMode: VaultRecoveryEntryMode.visible,
    );
    await store.configureRecovery(
      currentMasterPassword: _realPassword,
      currentDecoyPassword: _decoyPassword,
      scope: VaultRecoveryScope.decoy,
      questionIds: decoyQuestionIds,
      answers: decoyAnswers,
      entryMode: VaultRecoveryEntryMode.logoFiveTap,
    );

    await expectLater(
      store.recoverMasterPassword(
        questionIds: primaryQuestionIds,
        answers: primaryAnswers,
        newMasterPassword: _decoyPassword,
        requestEntryMode: VaultRecoveryEntryMode.visible,
      ),
      throwsA(isA<VaultRecoveryRejectedException>()),
    );
    await expectLater(
      store.recoverMasterPassword(
        questionIds: decoyQuestionIds,
        answers: decoyAnswers,
        newMasterPassword: _realPassword,
        requestEntryMode: VaultRecoveryEntryMode.logoFiveTap,
      ),
      throwsA(isA<VaultRecoveryRejectedException>()),
    );

    await store.disableRecovery(
      currentMasterPassword: _realPassword,
      scope: VaultRecoveryScope.primary,
    );
    expect(recoveryDeviceSecret.isConfiguredValue, isTrue);
    var remaining = await store.recoveryConfiguration();
    expect(remaining.primaryChallenge, isNull);
    expect(remaining.decoyChallenge, isNotNull);

    final recoveredDecoy = await store.recoverMasterPassword(
      questionIds: decoyQuestionIds,
      answers: decoyAnswers,
      newMasterPassword: 'Recovered-Decoy-26!Safe',
      requestEntryMode: VaultRecoveryEntryMode.logoFiveTap,
    );
    recoveredDecoy.session.close();
    expect(recoveryDeviceSecret.isConfiguredValue, isTrue);
    await expectLater(
      store.disableRecovery(
        currentMasterPassword: 'Wrong-Real-Master-26!Safe',
        currentDecoyPassword: 'Recovered-Decoy-26!Safe',
        scope: VaultRecoveryScope.decoy,
      ),
      throwsA(isA<VaultCredentialRejectedException>()),
    );
    expect(recoveryDeviceSecret.isConfiguredValue, isTrue);
    await store.disableRecovery(
      currentMasterPassword: _realPassword,
      currentDecoyPassword: 'Recovered-Decoy-26!Safe',
      scope: VaultRecoveryScope.decoy,
    );
    remaining = await store.recoveryConfiguration();
    expect(remaining.anyConfigured, isFalse);
    expect(recoveryDeviceSecret.isConfiguredValue, isFalse);
    expect(recoveryDeviceSecret.deleteCount, 1);
  });

  test('真实库与诱饵库回滚点按独立目录和 DEK 双向隔离且各自可恢复', () async {
    final realCreated = await store.create(masterPassword: _realPassword);
    final realSession = realCreated.session as BatchRollbackVaultSession;
    await realSession.saveBatchWithRollback(
      before: realCreated.snapshot,
      after: _snapshot(serviceName: '真实库批量'),
    );
    realSession.close();

    await store.createDecoyVault(
      currentMasterPassword: _realPassword,
      decoyPassword: _decoyPassword,
    );
    final decoyOpened = await store.unlock(masterPassword: _decoyPassword);
    final decoySession = decoyOpened.session as BatchRollbackVaultSession;
    expect(
      decoySession.batchRollbackAvailability,
      BatchRollbackAvailability.none,
    );
    await decoySession.saveBatchWithRollback(
      before: decoyOpened.snapshot,
      after: _snapshot(serviceName: '诱饵库批量'),
    );
    decoySession.close();

    final realRollbackFile = File(
      '${directory.path}${Platform.pathSeparator}encrypted_vault_v1'
      '${Platform.pathSeparator}batch_import_rollback_v1.envelope',
    );
    final decoyRollbackFile = File(
      '${directory.path}${Platform.pathSeparator}'
      'encrypted_vault_secondary_v1'
      '${Platform.pathSeparator}batch_import_rollback_v1.envelope',
    );
    expect(await realRollbackFile.exists(), isTrue);
    expect(await decoyRollbackFile.exists(), isTrue);
    expect(
      await realRollbackFile.readAsBytes(),
      isNot(orderedEquals(await decoyRollbackFile.readAsBytes())),
    );

    final reopenedReal = await store.unlock(masterPassword: _realPassword);
    final reopenedRealSession =
        reopenedReal.session as BatchRollbackVaultSession;
    expect(reopenedReal.snapshot.subscriptions.single.serviceName, '真实库批量');
    expect(reopenedRealSession.canUndoLastBatch, isTrue);
    final restoredReal = await reopenedRealSession.undoLastBatch();
    expect(restoredReal.accounts, isEmpty);
    reopenedRealSession.close();

    final reopenedDecoy = await store.unlock(masterPassword: _decoyPassword);
    final reopenedDecoySession =
        reopenedDecoy.session as BatchRollbackVaultSession;
    expect(reopenedDecoy.snapshot.subscriptions.single.serviceName, '诱饵库批量');
    expect(reopenedDecoySession.canUndoLastBatch, isTrue);
    final restoredDecoy = await reopenedDecoySession.undoLastBatch();
    expect(restoredDecoy.accounts, isEmpty);
    reopenedDecoySession.close();

    final finalReal = await store.unlock(masterPassword: _realPassword);
    expect(finalReal.snapshot.accounts, isEmpty);
    expect(
      (finalReal.session as BatchRollbackVaultSession).canUndoLastBatch,
      isFalse,
    );
    finalReal.session.close();
    final finalDecoy = await store.unlock(masterPassword: _decoyPassword);
    expect(finalDecoy.snapshot.accounts, isEmpty);
    expect(
      (finalDecoy.session as BatchRollbackVaultSession).canUndoLastBatch,
      isFalse,
    );
    finalDecoy.session.close();
  });

  test('提醒 outbox 只属于真实主库且诱饵会话无法读取或写入', () async {
    final realCreated = await store.create(masterPassword: _realPassword);
    final realSession =
        realCreated.session as NotificationReconciliationVaultSession;
    final pending = await realSession.prepareNotificationReconciliation(
      targetGeneration: realSession.generation,
    );
    realSession.close();

    await store.createDecoyVault(
      currentMasterPassword: _realPassword,
      decoyPassword: _decoyPassword,
    );
    final realOutbox = File(
      '${directory.path}${Platform.pathSeparator}encrypted_vault_v1'
      '${Platform.pathSeparator}notification_reconciliation_v1.json',
    );
    final decoyOutbox = File(
      '${directory.path}${Platform.pathSeparator}encrypted_vault_secondary_v1'
      '${Platform.pathSeparator}notification_reconciliation_v1.json',
    );
    expect(await realOutbox.exists(), isTrue);
    expect(await decoyOutbox.exists(), isFalse);

    final decoyOpened = await store.unlock(masterPassword: _decoyPassword);
    final decoySession =
        decoyOpened.session as NotificationReconciliationVaultSession;
    await expectLater(
      () async => decoySession.readNotificationReconciliation(),
      throwsA(isA<VaultClosedException>()),
    );
    await expectLater(
      () async => decoySession.prepareNotificationReconciliation(
        targetGeneration: decoySession.generation,
      ),
      throwsA(isA<VaultClosedException>()),
    );
    decoySession.close();
    expect(await decoyOutbox.exists(), isFalse);

    final reopenedReal = await store.unlock(masterPassword: _realPassword);
    final reopenedRealSession =
        reopenedReal.session as NotificationReconciliationVaultSession;
    expect(
      (await reopenedRealSession.readNotificationReconciliation())?.operationId,
      pending.operationId,
    );
    reopenedRealSession.close();
  });
}

VaultSnapshot _snapshot({required String serviceName}) {
  final account = AccountRecord.fromDraft(
    id: 'account-1',
    draft: AccountDraft(
      platformName: '真实平台',
      loginAccount: 'real-login@example.test',
      username: '真实用户名',
      boundPhone: '18800000000',
      boundEmail: 'bound@example.test',
      password: 'REAL-ACCOUNT-PASSWORD',
      website: 'https://example.test',
      notes: '真实账号备注',
    ),
  );
  final subscription = SubscriptionRecord.fromDraft(
    id: 'subscription-1',
    draft: SubscriptionDraft(
      accountId: account.id,
      details: SubscriptionDetailsDraft(
        serviceName: serviceName,
        firstSubscribedOn: DateTime(2026, 1, 1),
        nextRenewalOn: DateTime(2026, 9, 1),
        amount: '25.00',
      ),
    ),
  );
  return VaultSnapshot(
    nextAccountId: 2,
    accounts: <AccountRecord>[account],
    nextSubscriptionId: 2,
    subscriptions: <SubscriptionRecord>[subscription],
  );
}

Future<Map<String, String>> _encryptedDirectorySnapshot(
  Directory directory,
) async {
  final files = await directory
      .list(recursive: true, followLinks: false)
      .where((entity) => entity is File)
      .cast<File>()
      .toList();
  files.sort((left, right) => left.path.compareTo(right.path));
  return <String, String>{
    for (final file in files)
      file.path.substring(directory.path.length + 1): base64Encode(
        await file.readAsBytes(),
      ),
  };
}

final class _MemoryQuickUnlockStore implements QuickUnlockSecretStore {
  QuickUnlockSecret? _secret;
  bool failDelete = false;

  bool get hasSecret => _secret != null;

  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.available;

  @override
  Future<bool> containsSecret() async => _secret != null;

  @override
  Future<void> deleteSecret() async {
    if (failDelete) {
      throw const QuickUnlockException(
        QuickUnlockFailureReason.statusUnknown,
        platformCode: 'test_delete_failed',
      );
    }
    _secret?.destroy();
    _secret = null;
  }

  @override
  Future<QuickUnlockSecret?> readSecret() async {
    final secret = _secret;
    if (secret == null) return null;
    return QuickUnlockSecret(vaultId: secret.vaultId, dataKey: secret.dataKey);
  }

  @override
  Future<void> writeSecret(QuickUnlockSecret secret) async {
    _secret?.destroy();
    _secret = QuickUnlockSecret(
      vaultId: secret.vaultId,
      dataKey: secret.dataKey,
    );
  }

  void destroy() {
    _secret?.destroy();
    _secret = null;
  }
}

final class _MemoryRecoveryDeviceSecretStore
    implements RecoveryDeviceSecretStore {
  RecoveryDeviceSecretMaterial? _material;
  int writeCount = 0;
  int readCount = 0;
  int deleteCount = 0;

  bool get isConfiguredValue => _material != null;

  @override
  Future<bool> isConfigured() async => _material != null;

  @override
  Future<void> write(RecoveryDeviceSecretMaterial material) async {
    writeCount += 1;
    _material?.destroy();
    _material = RecoveryDeviceSecretMaterial(
      vaultInstanceId: material.vaultInstanceId,
      slotId: material.slotId,
      deviceBindingId: material.deviceBindingId,
      deviceSecret: material.deviceSecret,
    );
  }

  @override
  Future<RecoveryDeviceSecretMaterial?> read() async {
    readCount += 1;
    final material = _material;
    if (material == null) return null;
    return RecoveryDeviceSecretMaterial(
      vaultInstanceId: material.vaultInstanceId,
      slotId: material.slotId,
      deviceBindingId: material.deviceBindingId,
      deviceSecret: material.deviceSecret,
    );
  }

  @override
  Future<void> delete() async {
    deleteCount += 1;
    _material?.destroy();
    _material = null;
  }

  void destroy() {
    _material?.destroy();
    _material = null;
  }
}
