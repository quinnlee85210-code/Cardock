import 'dart:convert';
import 'dart:io';

import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/storage/encrypted_vault_store.dart';
import 'package:account_subscription_manager/core/storage/portable_backup_codec.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/pending_subscription_draft.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter_test/flutter_test.dart';

const _sourcePassword = 'Source-Master-Password-2026!';
const _backupPassword = 'Cobalt-River-Quartz-74!Archive';
const _targetPassword = 'Target-Current-Password-2026!';

void main() {
  final codec = PortableBackupCodec();
  final snapshot = VaultSnapshot(
    nextAccountId: 2,
    accounts: <AccountRecord>[
      AccountRecord.fromDraft(
        id: 'account-1',
        draft: AccountDraft(
          platformName: '离线备份账号',
          loginAccount: 'backup@example.test',
          password: 'NEVER-PLAINTEXT-IN-CONTAINER',
        ),
      ),
    ],
  );

  late List<int> validBackup;

  setUpAll(() async {
    validBackup = await codec.encryptV2(
      snapshot: snapshot,
      backupMasterPassword: _backupPassword,
      createdAtUtc: DateTime.utc(2026, 8, 1, 5, 30),
    );
  });

  test('v2 元数据在认证密文内且预览与内容一致', () async {
    final outerText = utf8.decode(validBackup);
    expect(outerText, isNot(contains('离线备份账号')));
    expect(outerText, isNot(contains('backup@example.test')));
    expect(outerText, isNot(contains('NEVER-PLAINTEXT-IN-CONTAINER')));
    expect(outerText, isNot(contains('2026-08-01T05:30')));

    final result = await codec.read(
      bytes: validBackup,
      backupMasterPassword: _backupPassword,
    );
    expect(result.inspection.formatVersion, 2);
    expect(
      result.inspection.sourceSchemaVersion,
      VaultSnapshot.currentSchemaVersion,
    );
    expect(result.inspection.accountCount, 1);
    expect(result.inspection.subscriptionCount, 0);
    expect(result.inspection.createdAtUtc, DateTime.utc(2026, 8, 1, 5, 30));
    expect(result.inspection.backupId, isNotEmpty);
    expect(result.snapshot.accounts.single.platformName, '离线备份账号');
  });

  test('同一快照重复导出得到不同容器和 UUID', () async {
    final second = await codec.encryptV2(
      snapshot: snapshot,
      backupMasterPassword: _backupPassword,
    );
    final firstInspection = await codec.inspect(
      bytes: validBackup,
      backupMasterPassword: _backupPassword,
    );
    final secondInspection = await codec.inspect(
      bytes: second,
      backupMasterPassword: _backupPassword,
    );

    expect(second, isNot(orderedEquals(validBackup)));
    expect(secondInspection.backupId, isNot(firstInspection.backupId));
  });

  test('v2新备份把待完善草稿保存在认证密文内并无损恢复', () async {
    final account = AccountRecord.fromDraft(
      id: 'account-draft',
      draft: AccountDraft(platformName: '草稿备份平台'),
    );
    final draftSnapshot = VaultSnapshot(
      nextAccountId: 2,
      accounts: <AccountRecord>[account],
      pendingSubscriptionDrafts: <PendingSubscriptionDraft>[
        PendingSubscriptionDraft(
          draftId: 'pending-backup',
          accountId: account.id,
          planName: 'BACKUP-DRAFT-SENTINEL',
          subscriptionStartDate: DateTime(2026, 8, 15),
          nextRenewalDate: DateTime(2026, 9, 15),
          notes: '只应出现在认证密文解密后',
          createdAt: DateTime.utc(2026, 8, 30),
          updatedAt: DateTime.utc(2026, 8, 30),
        ),
      ],
    );
    final bytes = await codec.encryptV2(
      snapshot: draftSnapshot,
      backupMasterPassword: _backupPassword,
    );
    expect(utf8.decode(bytes), isNot(contains('BACKUP-DRAFT-SENTINEL')));

    final restored = await codec.read(
      bytes: bytes,
      backupMasterPassword: _backupPassword,
    );
    expect(
      restored.snapshot.pendingSubscriptionDrafts.single.planName,
      'BACKUP-DRAFT-SENTINEL',
    );
    expect(
      restored.snapshot.pendingSubscriptionDrafts.single.accountId,
      account.id,
    );
    expect(
      restored.snapshot.pendingSubscriptionDrafts.single.subscriptionStartDate,
      DateTime(2026, 8, 15),
    );
    expect(
      restored.snapshot.pendingSubscriptionDrafts.single.nextRenewalDate,
      DateTime(2026, 9, 15),
    );
  });

  test('错密码与认证标签位翻转使用同一安全失败边界', () async {
    await expectLater(
      codec.read(
        bytes: validBackup,
        backupMasterPassword: 'Wrong-Backup-Password-2026!',
      ),
      throwsA(isA<PortableBackupAuthenticationException>()),
    );

    final outer = jsonDecode(utf8.decode(validBackup)) as Map<String, dynamic>;
    final payload = outer['payload'] as Map<String, dynamic>;
    final box = payload['box'] as String;
    final index = box.length ~/ 2;
    payload['box'] =
        '${box.substring(0, index)}'
        '${box[index] == 'A' ? 'B' : 'A'}${box.substring(index + 1)}';
    await expectLater(
      codec.read(
        bytes: utf8.encode(jsonEncode(outer)),
        backupMasterPassword: _backupPassword,
      ),
      throwsA(isA<PortableBackupAuthenticationException>()),
    );
  });

  test('截断、未来格式、弱 KDF 和超限文件均在派生前拒绝', () async {
    await expectLater(
      codec.read(
        bytes: validBackup.sublist(0, validBackup.length ~/ 2),
        backupMasterPassword: _backupPassword,
      ),
      throwsA(isA<PortableBackupFormatException>()),
    );

    final future = jsonDecode(utf8.decode(validBackup)) as Map<String, dynamic>;
    future['formatVersion'] = 3;
    await expectLater(
      codec.read(
        bytes: utf8.encode(jsonEncode(future)),
        backupMasterPassword: _backupPassword,
      ),
      throwsA(isA<PortableBackupFormatException>()),
    );

    final weak = jsonDecode(utf8.decode(validBackup)) as Map<String, dynamic>;
    (weak['kdf'] as Map<String, dynamic>)['memoryKiB'] = 64;
    await expectLater(
      codec.read(
        bytes: utf8.encode(jsonEncode(weak)),
        backupMasterPassword: _backupPassword,
      ),
      throwsA(isA<PortableBackupFormatException>()),
    );

    await expectLater(
      codec.read(
        bytes: List<int>.filled(maximumPortableBackupBytes + 1, 0),
        backupMasterPassword: _backupPassword,
      ),
      throwsA(isA<PortableBackupFormatException>()),
    );
  });

  test('空库可导出并恢复', () async {
    final bytes = await codec.encryptV2(
      snapshot: VaultSnapshot.empty(),
      backupMasterPassword: _backupPassword,
    );
    final restored = await codec.read(
      bytes: bytes,
      backupMasterPassword: _backupPassword,
    );
    expect(restored.snapshot.accounts, isEmpty);
    expect(restored.snapshot.subscriptions, isEmpty);
  });

  test('v2备份严格保留独立订阅与精确延后且不补写账号', () async {
    final standalone =
        SubscriptionRecord.fromDraft(
          id: 'subscription-standalone',
          draft: SubscriptionDraft(
            accountId: null,
            details: SubscriptionDetailsDraft(
              serviceName: '备份内独立订阅',
              notes: '正式订阅备注只应存在于认证密文内',
              firstSubscribedOn: DateTime(2026, 8, 1),
              nextRenewalOn: DateTime(2026, 9, 1),
            ),
          ),
        ).snoozeReminder(
          SubscriptionSnoozeTarget.exactInstant(
            DateTime.utc(2026, 8, 30, 4, 30),
          ),
        );
    final bytes = await codec.encryptV2(
      snapshot: VaultSnapshot(
        nextAccountId: 1,
        accounts: const <AccountRecord>[],
        nextSubscriptionId: 2,
        subscriptions: <SubscriptionRecord>[standalone],
      ),
      backupMasterPassword: _backupPassword,
    );
    expect(utf8.decode(bytes), isNot(contains('正式订阅备注只应存在于认证密文内')));

    final restored = await codec.read(
      bytes: bytes,
      backupMasterPassword: _backupPassword,
    );
    expect(
      restored.inspection.sourceSchemaVersion,
      VaultSnapshot.currentSchemaVersion,
    );
    expect(restored.inspection.accountCount, 0);
    expect(restored.inspection.subscriptionCount, 1);
    expect(restored.snapshot.accounts, isEmpty);
    expect(restored.snapshot.subscriptions.single.accountId, isNull);
    expect(restored.snapshot.subscriptions.single.notes, '正式订阅备注只应存在于认证密文内');
    expect(
      restored.snapshot.subscriptions.single.snoozedUntilUtc,
      DateTime.utc(2026, 8, 30, 4, 30),
    );
  });

  test('便携备份拒绝未来sourceSchemaVersion', () async {
    await expectLater(
      codec.encryptV2(
        snapshot: snapshot,
        backupMasterPassword: _backupPassword,
        sourceSchemaVersion: VaultSnapshot.currentSchemaVersion + 1,
      ),
      throwsA(isA<PortableBackupFormatException>()),
    );
  });

  test('v1 可读取并可换成独立密码 v2 后写入另一当前密码库', () async {
    final sourceDirectory = await Directory.systemTemp.createTemp(
      'asm-backup-source-',
    );
    final targetDirectory = await Directory.systemTemp.createTemp(
      'asm-backup-target-',
    );
    addTearDown(() async {
      await sourceDirectory.delete(recursive: true);
      await targetDirectory.delete(recursive: true);
    });
    final sourceStore = EncryptedVaultStore(
      directoryProvider: () async => sourceDirectory,
    );
    final source = await sourceStore.create(masterPassword: _sourcePassword);
    await source.session.save(snapshot);
    final legacyBytes = await source.session.exportEncryptedBackup();
    source.session.close();

    final legacy = await codec.read(
      bytes: legacyBytes,
      backupMasterPassword: _sourcePassword,
    );
    expect(
      legacy.inspection.containerKind,
      PortableBackupContainerKind.legacyVaultV1,
    );

    final portable = await codec.reencryptAsV2(
      sourceBytes: legacyBytes,
      sourceMasterPassword: _sourcePassword,
      backupMasterPassword: _backupPassword,
    );
    final imported = await codec.read(
      bytes: portable,
      backupMasterPassword: _backupPassword,
    );
    final targetStore = EncryptedVaultStore(
      directoryProvider: () async => targetDirectory,
    );
    final target = await targetStore.create(masterPassword: _targetPassword);
    await target.session.save(imported.snapshot);
    target.session.close();

    final reopened = await targetStore.unlock(masterPassword: _targetPassword);
    expect(reopened.snapshot.accounts.single.platformName, '离线备份账号');
    reopened.session.close();
    await expectLater(
      targetStore.unlock(masterPassword: _sourcePassword),
      throwsA(isA<VaultUnlockException>()),
    );
  });
}
