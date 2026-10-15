import 'dart:io';

import 'package:account_subscription_manager/core/notifications/notification_reconciliation_state.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/storage/encrypted_vault_store.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:flutter_test/flutter_test.dart';

const _testKdf = VaultKdfParameters(
  memoryKiB: 64,
  iterations: 1,
  parallelism: 1,
);
const _password = 'TEST-ONLY-NOTIFICATION-OUTBOX-1234';
const _rotatedPassword = 'TEST-ONLY-NOTIFICATION-OUTBOX-5678';

void main() {
  test('outbox 与业务 generation 分离并跨进程重开保留', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-notification-outbox-reopen-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final store = _store(directory);
    final opened = await store.create(masterPassword: _password);
    final session = opened.session as NotificationReconciliationVaultSession;
    final beforeGeneration = session.generation;
    final prepared = await session.prepareNotificationReconciliation(
      targetGeneration: beforeGeneration + 1,
    );
    expect(session.generation, beforeGeneration);

    await session.save(_snapshot('TEST-ONLY-OUTBOX-BUSINESS-SENTINEL'));
    expect(session.generation, beforeGeneration + 1);
    session.close();

    final reopened = await store.unlock(masterPassword: _password);
    final reopenedSession =
        reopened.session as NotificationReconciliationVaultSession;
    final pending = await reopenedSession.readNotificationReconciliation();
    expect(pending?.operationId, prepared.operationId);
    expect(pending?.attemptCount, 0);
    expect(reopenedSession.generation, beforeGeneration + 1);

    final outbox = File(
      '${directory.path}${Platform.pathSeparator}notification_reconciliation_v1.json',
    );
    final raw = await outbox.readAsString();
    expect(raw, isNot(contains('TEST-ONLY-OUTBOX-BUSINESS-SENTINEL')));
    expect(raw, isNot(contains(prepared.operationId)));
    reopenedSession.close();
  });

  test('失败次数跨应用与模拟设备重启持久化且成功后不可重复消费', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-notification-outbox-retry-',
    );
    addTearDown(() => _deleteDirectory(directory));
    var store = _store(directory);
    var opened = await store.create(masterPassword: _password);
    var session = opened.session as NotificationReconciliationVaultSession;
    final item = await session.prepareNotificationReconciliation(
      targetGeneration: session.generation,
    );
    await session.recordNotificationReconciliationFailure(
      operationId: item.operationId,
    );
    session.close();

    // A new store object models a new process after app/device restart.
    store = _store(directory);
    opened = await store.unlock(masterPassword: _password);
    session = opened.session as NotificationReconciliationVaultSession;
    var pending = await session.readNotificationReconciliation();
    expect(pending?.attemptCount, 1);
    await session.recordNotificationReconciliationFailure(
      operationId: item.operationId,
    );
    session.close();

    store = _store(directory);
    opened = await store.unlock(masterPassword: _password);
    session = opened.session as NotificationReconciliationVaultSession;
    pending = await session.readNotificationReconciliation();
    expect(pending?.attemptCount, 2);
    final generation = session.generation;
    await session.completeNotificationReconciliation(
      operationId: item.operationId,
    );
    expect(await session.readNotificationReconciliation(), isNull);
    expect(session.generation, generation);
    await session.completeNotificationReconciliation(
      operationId: item.operationId,
    );
    expect(await session.readNotificationReconciliation(), isNull);
    session.close();
  });

  test('未提交的 future 预备项会被墓碑化且不会粘到下一次业务写入', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-notification-outbox-abandoned-',
    );
    addTearDown(() => _deleteDirectory(directory));
    var store = _store(directory);
    var opened = await store.create(masterPassword: _password);
    var session = opened.session as NotificationReconciliationVaultSession;
    await session.prepareNotificationReconciliation(
      targetGeneration: session.generation + 1,
    );
    session.close();

    store = _store(directory);
    opened = await store.unlock(masterPassword: _password);
    session = opened.session as NotificationReconciliationVaultSession;
    expect(await session.readNotificationReconciliation(), isNull);
    await session.save(_snapshot('后续不相关业务写入'));
    expect(await session.readNotificationReconciliation(), isNull);
    session.close();
  });

  test('通知清账不改变 generation 且不使批量回滚失效', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-notification-outbox-batch-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final store = _store(directory);
    final opened = await store.create(masterPassword: _password);
    final session = opened.session as BatchRollbackVaultSession;
    final notificationSession =
        opened.session as NotificationReconciliationVaultSession;
    final pending = await notificationSession.prepareNotificationReconciliation(
      targetGeneration: session.generation + 1,
    );
    await session.saveBatchWithRollback(
      before: opened.snapshot,
      after: _snapshot('批量导入后'),
    );
    final generation = session.generation;
    expect(session.canUndoLastBatch, isTrue);

    await notificationSession.completeNotificationReconciliation(
      operationId: pending.operationId,
    );
    expect(session.generation, generation);
    expect(session.canUndoLastBatch, isTrue);
    session.close();
  });

  test('DEK 轮换后旧 outbox 可由当前快照安全重建而不会永久卡死', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-notification-outbox-dek-rotation-',
    );
    addTearDown(() => _deleteDirectory(directory));
    final store = _store(directory);
    final opened = await store.create(masterPassword: _password);
    final original = opened.session as NotificationReconciliationVaultSession;
    final oldPending = await original.prepareNotificationReconciliation(
      targetGeneration: original.generation,
    );
    original.close();

    final changed = await store.changeMasterPassword(
      currentMasterPassword: _password,
      newMasterPassword: _rotatedPassword,
    );
    final current = changed.session as NotificationReconciliationVaultSession;
    final rebuilt = await current.prepareNotificationReconciliation(
      targetGeneration: current.generation,
    );
    expect(rebuilt.operationId, isNot(oldPending.operationId));
    expect(
      (await current.readNotificationReconciliation())?.operationId,
      rebuilt.operationId,
    );
    await current.completeNotificationReconciliation(
      operationId: rebuilt.operationId,
    );
    current.close();

    final reopened = await store.unlock(masterPassword: _rotatedPassword);
    final reopenedSession =
        reopened.session as NotificationReconciliationVaultSession;
    expect(await reopenedSession.readNotificationReconciliation(), isNull);
    reopenedSession.close();
  });
}

EncryptedVaultStore _store(Directory directory) => EncryptedVaultStore(
  directoryProvider: () async => directory,
  creationKdf: _testKdf,
);

VaultSnapshot _snapshot(String platformName) => VaultSnapshot(
  nextAccountId: 2,
  accounts: <AccountRecord>[
    AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: platformName),
    ),
  ],
);

Future<void> _deleteDirectory(Directory directory) async {
  if (await directory.exists()) await directory.delete(recursive: true);
}
