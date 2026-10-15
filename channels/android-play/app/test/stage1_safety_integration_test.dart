import 'dart:convert';
import 'dart:io';
import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/notifications/reminder_scheduler.dart';
import 'package:account_subscription_manager/core/security/biometric_unlock.dart';
import 'package:account_subscription_manager/core/security/device_backup_config.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/security/vault_trash.dart';
import 'package:account_subscription_manager/core/storage/encrypted_vault_store.dart';
import 'package:account_subscription_manager/core/storage/layered_vault_store.dart';
import 'package:account_subscription_manager/core/storage/readable_export.dart';
import 'package:account_subscription_manager/core/storage/vault_rebuild_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'stage1_backup_export_test.dart' show exportFixture, MemoryDocuments;
import 'support/fake_vault_store.dart';

const primary = 'TEST-ONLY-Primary-2026!';
const secondary = 'TEST-ONLY-Decoy-2026!';
const kdf = VaultKdfParameters(memoryKiB: 64, iterations: 1, parallelism: 1);

class QuickStore implements QuickUnlockSecretStore {
  QuickUnlockSecret? secret;
  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.available;
  @override
  Future<bool> containsSecret() async => secret != null;
  @override
  Future<void> deleteSecret() async {
    secret?.destroy();
    secret = null;
  }

  @override
  Future<QuickUnlockSecret?> readSecret() async => secret == null
      ? null
      : QuickUnlockSecret(vaultId: secret!.vaultId, dataKey: secret!.dataKey);
  @override
  Future<void> writeSecret(QuickUnlockSecret value) async {
    secret = QuickUnlockSecret(vaultId: value.vaultId, dataKey: value.dataKey);
  }
}

class RebuildNative implements RebuildPlatform {
  bool allowed = true, cleared = false;
  int consumed = 0;
  @override
  Future<RebuildAuthorization?> authorize(String title, String message) async =>
      allowed
      ? const RebuildAuthorization('test-only', unsecured: false)
      : null;
  @override
  Future<void> beginHold(String token) async {}
  @override
  Future<void> cancelHold(String token) async {}
  @override
  Future<bool> consume(
    RebuildAuthorization authorization,
    String phrase,
    String second,
  ) async {
    consumed++;
    return allowed;
  }

  @override
  Future<void> clearForCommittedRebuild() async {
    cleared = true;
  }
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('stage1-isolated-');
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  test(
    'real and decoy trash independent; decoy cannot read device backup config',
    () async {
      final store = LayeredVaultStore.forDirectory(
        directory: directory,
        creationKdf: kdf,
        quickUnlockSecretStore: QuickStore(),
      );
      final real = await store.create(masterPassword: primary);
      await real.session.save(
        VaultTrash.move(
          exportFixture(),
          accountId: 'account-1',
          now: DateTime.now(),
          batchId: 'real-batch',
        ),
      );
      await (real.session as DeviceBackupConfigSession).writeDeviceBackupConfig(
        {'version': 1, 'password': 'TEST-ONLY-AUTO-SECRET'},
      );
      real.session.close();
      await store.createDecoyVault(
        currentMasterPassword: primary,
        decoyPassword: secondary,
      );
      final state = AppState(vaultStore: store);
      addTearDown(state.dispose);
      await state.initialize();
      expect(await state.unlock(secondary), VaultActionResult.success);
      expect(state.trashAccounts, isEmpty);
      expect(state.autoBackup.status.enabled, false);
      expect(state.importVaultScopeId, isNull);
      expect(
        await state.exportEncryptedBackup(
          backupMasterPassword: 'TEST-ONLY-Decoy-Backup-2026!',
        ),
        isNull,
      );
      final decoyExportDocuments = MemoryDocuments();
      expect(
        await state.exportReadable(
          options: const ReadableExportOptions(
            format: ReadableExportFormat.json,
          ),
          currentPassword: secondary,
          storage: decoyExportDocuments,
        ),
        isFalse,
      );
      expect(decoyExportDocuments.files, isEmpty);
      expect(
        await state.createAccount(
          AccountDraft(platformName: 'TEST-ONLY-DECOY'),
        ),
        isNotNull,
      );
      final id = state.accounts.single.id;
      expect(await state.deleteAccount(id), true);
      expect(
        await state.permanentlyDeleteTrash(
          currentPassword: primary,
          accountIds: {id},
        ),
        false,
      );
      expect(
        await state.permanentlyDeleteTrash(
          currentPassword: secondary,
          accountIds: {id},
        ),
        true,
      );
      state.lock();
      final decoy = await store.unlock(masterPassword: secondary);
      await expectLater(
        () async => (decoy.session as DeviceBackupConfigSession)
            .readDeviceBackupConfig(),
        throwsA(isA<VaultClosedException>()),
      );
      decoy.session.close();
      final reopened = await store.unlock(masterPassword: primary);
      expect(reopened.snapshot.trashAccounts.single.batchId, 'real-batch');
      expect(
        (await (reopened.session as DeviceBackupConfigSession)
            .readDeviceBackupConfig())!['password'],
        'TEST-ONLY-AUTO-SECRET',
      );
      reopened.session.close();
    },
  );
  test(
    'subscription-only session receives no trash and rejects configuration/export/mutation',
    () async {
      final store = LayeredVaultStore.forDirectory(
        directory: directory,
        creationKdf: kdf,
        quickUnlockSecretStore: QuickStore(),
      );
      final real = await store.create(masterPassword: primary);
      await real.session.save(
        VaultTrash.move(
          exportFixture(),
          accountId: 'account-1',
          now: DateTime.now(),
          batchId: 'real',
        ),
      );
      real.session.close();
      await store.configureQuickUnlock(
        currentMasterPassword: primary,
        scope: QuickUnlockScope.subscriptionsOnly,
      );
      final opened = await store.unlockWithQuickUnlock();
      expect(opened.snapshot.trashAccounts, isEmpty);
      await expectLater(
        () async => (opened.session as DeviceBackupConfigSession)
            .writeDeviceBackupConfig({}),
        throwsA(isA<VaultClosedException>()),
      );
      await expectLater(
        opened.session.save(VaultSnapshot.empty()),
        throwsA(isA<VaultClosedException>()),
      );
      opened.session.close();
    },
  );
  test(
    'device backup config survives master DEK rotation; old key and password rejected',
    () async {
      final store = EncryptedVaultStore(
        directoryProvider: () async => directory,
        creationKdf: kdf,
      );
      final real = await store.create(masterPassword: primary);
      final config = real.session as DeviceBackupConfigSession;
      await config.writeDeviceBackupConfig({
        'version': 1,
        'password': 'TEST-ONLY-INDEPENDENT',
      });
      final changed = await store.changeMasterPassword(
        currentMasterPassword: primary,
        newMasterPassword: secondary,
      );
      expect(
        (await (changed.session as DeviceBackupConfigSession)
            .readDeviceBackupConfig())!['password'],
        'TEST-ONLY-INDEPENDENT',
      );
      await expectLater(
        config.readDeviceBackupConfig(),
        throwsA(isA<VaultClosedException>()),
      );
      await expectLater(
        store.unlock(masterPassword: primary),
        throwsA(isA<VaultCredentialRejectedException>()),
      );
      changed.session.close();
      real.session.close();
      final reopened = await store.unlock(masterPassword: secondary);
      expect(
        (await (reopened.session as DeviceBackupConfigSession)
            .readDeviceBackupConfig())!['password'],
        'TEST-ONLY-INDEPENDENT',
      );
      reopened.session.close();
    },
  );
  test('future config rejects reading and writing without overwrite', () async {
    final store = EncryptedVaultStore(
      directoryProvider: () async => directory,
      creationKdf: kdf,
    );
    final real = await store.create(masterPassword: primary);
    final file = File('${directory.path}/device_backup_config_v1.json');
    await file.writeAsString('{"version":99}');
    final config = real.session as DeviceBackupConfigSession;
    await expectLater(
      config.readDeviceBackupConfig(),
      throwsA(isA<VaultFormatException>()),
    );
    await expectLater(
      config.writeDeviceBackupConfig({}),
      throwsA(isA<VaultFormatException>()),
    );
    expect(await file.readAsString(), '{"version":99}');
    real.session.close();
  });
  test(
    'readable export rejects wrong password and missing extra confirmation before output',
    () async {
      final store = FakeVaultStore(
        configured: true,
        acceptedPassword: primary,
        snapshot: exportFixture(),
      );
      final state = AppState(vaultStore: store);
      addTearDown(state.dispose);
      final docs = MemoryDocuments();
      await state.initialize();
      await state.unlock(primary);
      expect(
        await state.exportReadable(
          options: const ReadableExportOptions(),
          currentPassword: 'wrong',
          storage: docs,
        ),
        false,
      );
      expect(
        await state.exportReadable(
          options: const ReadableExportOptions(includePasswords: true),
          currentPassword: primary,
          storage: docs,
        ),
        false,
      );
      expect(docs.files, isEmpty);
      expect(
        await state.exportReadable(
          options: const ReadableExportOptions(
            format: ReadableExportFormat.json,
          ),
          currentPassword: primary,
          storage: docs,
        ),
        true,
      );
      expect(
        utf8.decode(docs.files['export']!),
        isNot(contains('TEST-ONLY-CURRENT')),
      );
      state.lock();
      expect(
        await state.exportReadable(
          options: const ReadableExportOptions(),
          currentPassword: primary,
          storage: docs,
        ),
        false,
      );
    },
  );

  Future<void> seed() async {
    for (final name in [
      'encrypted_vault_v1',
      'encrypted_subscription_view_v1',
      'encrypted_vault_secondary_v1',
    ]) {
      await Directory('${directory.path}/$name').create();
      await File(
        '${directory.path}/$name/test-only.data',
      ).writeAsString('TEST-ONLY-ENCRYPTED');
    }
    for (final name in [
      'vault_access_state_v1.json',
      'last_restore_rollback_v1.json.a',
      'backup_health_v1.json',
      'unlock_throttle_v1.json.tmp.1',
      'cardock_promo_activation_v1.json',
      'language_preferences_v1.json',
      'appearance_preferences_v1.json',
      'outside.asmbackup',
    ]) {
      await File(
        '${directory.path}/$name',
      ).writeAsString('TEST-ONLY-PRESERVE-CHECK');
    }
  }

  VaultRebuildService service(
    RebuildNative platform, {
    Future<void> Function(String)? after,
  }) => VaultRebuildService(
    directory: () async => directory,
    platform: platform,
    reminders: const NoopReminderScheduler(),
    afterStep: after,
  );
  test(
    'cancelled auth or wrong phrase writes nothing and retains every item',
    () async {
      await seed();
      final before = directory.listSync().map((e) => e.path).toSet();
      final native = RebuildNative()..allowed = false;
      expect(
        await service(native).commit(
          authorization: const RebuildAuthorization('x', unsecured: false),
          phrase: '删除本机卡坞数据',
        ),
        false,
      );
      native.allowed = true;
      expect(
        await service(native).commit(
          authorization: const RebuildAuthorization('x', unsecured: false),
          phrase: 'wrong',
        ),
        false,
      );
      expect(directory.listSync().map((e) => e.path).toSet(), before);
      expect(native.cleared, false);
    },
  );
  test(
    'rebuild clears exact local data and preserves external backup, appearance and activation bytes',
    () async {
      await seed();
      final native = RebuildNative();
      expect(
        await service(native).commit(
          authorization: const RebuildAuthorization('x', unsecured: false),
          phrase: '删除本机卡坞数据',
        ),
        true,
      );
      expect(native.cleared, true);
      for (final name in [
        'cardock_promo_activation_v1.json',
        'language_preferences_v1.json',
        'appearance_preferences_v1.json',
        'outside.asmbackup',
      ]) {
        expect(
          await File('${directory.path}/$name').readAsString(),
          'TEST-ONLY-PRESERVE-CHECK',
        );
      }
      expect(directory.listSync(), hasLength(4));
    },
  );
  for (final boundary in ['committed', 'native', 'file', 'clean']) {
    test(
      'interrupted rebuild at $boundary resumes before vault startup; idempotent',
      () async {
        await seed();
        final native = RebuildNative();
        var failed = false;
        final interrupted = service(
          native,
          after: (step) async {
            if (step == boundary && !failed) {
              failed = true;
              throw StateError('injected interruption');
            }
          },
        );
        await expectLater(
          interrupted.commit(
            authorization: const RebuildAuthorization('x', unsecured: false),
            phrase: '删除本机卡坞数据',
          ),
          throwsStateError,
        );
        expect(
          await File(
            '${directory.path}/${VaultRebuildService.journalName}',
          ).exists(),
          true,
        );
        await service(native).resumeIfNeeded();
        await service(native).resumeIfNeeded();
        expect(directory.listSync(), hasLength(4));
      },
    );
  }
  test('future rebuild intent fails closed and does not delete data', () async {
    await seed();
    await File(
      '${directory.path}/${VaultRebuildService.journalName}',
    ).writeAsString('{"version":99,"phase":"committed"}');
    final native = RebuildNative();
    await expectLater(service(native).resumeIfNeeded(), throwsFormatException);
    expect(
      await Directory('${directory.path}/encrypted_vault_v1').exists(),
      true,
    );
    expect(native.cleared, false);
  });
  test(
    'unsecured device requires second phrase and platform hold authorization',
    () async {
      await seed();
      final native = RebuildNative();
      expect(
        await service(native).commit(
          authorization: const RebuildAuthorization('x', unsecured: true),
          phrase: '删除本机卡坞数据',
        ),
        false,
      );
      expect(native.consumed, 0);
      expect(native.cleared, false);
    },
  );
  test(
    'cleanup allowlist never matches external paths or similarly named data',
    () {
      for (final name in [
        '../encrypted_vault_v1',
        'encrypted_vault_v1_other',
        'outside.asmbackup',
        'encrypted_vault_v1.rebuild.bad/escape',
        'cardock_promo_activation_v1.json',
        'secret.txt',
      ]) {
        expect(VaultRebuildService.removableName(name), false);
      }
    },
  );
}
