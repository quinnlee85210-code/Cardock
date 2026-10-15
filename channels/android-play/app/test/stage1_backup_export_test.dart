import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:account_subscription_manager/core/security/device_backup_config.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/security/vault_trash.dart';
import 'package:account_subscription_manager/core/storage/auto_backup_controller.dart';
import 'package:account_subscription_manager/core/storage/document_storage.dart';
import 'package:account_subscription_manager/core/storage/encrypted_vault_store.dart';
import 'package:account_subscription_manager/core/storage/portable_backup_codec.dart';
import 'package:account_subscription_manager/core/storage/readable_export.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const testPassword = 'TEST-ONLY-Backup-2026-Strong!';
VaultSnapshot exportFixture([String notes = '备注,"quoted"\nnew line']) =>
    VaultSnapshot(
      nextAccountId: 2,
      accounts: [
        AccountRecord.fromDraft(
          id: 'account-1',
          draft: AccountDraft(
            platformName: '=FORMULA()',
            password: 'TEST-ONLY-CURRENT',
            notes: notes,
          ),
          passwordChangeHistory: [
            PasswordChangeRecord(changedAtUtc: DateTime.utc(2026, 9, 3)),
          ],
        ),
      ],
    );
Future<List<int>> collect(Stream<List<int>> stream) =>
    stream.fold(<int>[], (a, b) => a..addAll(b));

class ConfigSession implements DeviceBackupConfigSession {
  Map<String, Object?>? value;
  bool closed = false, fail = false;
  @override
  int get generation => 1;
  @override
  Future<Map<String, Object?>?> readDeviceBackupConfig() async => value;
  @override
  Future<void> writeDeviceBackupConfig(Map<String, Object?>? data) async {
    if (closed || fail) throw const VaultStorageException();
    value = data == null
        ? null
        : Map<String, Object?>.from(jsonDecode(jsonEncode(data)) as Map);
  }

  @override
  void close() {
    closed = true;
  }

  @override
  Future<void> enableQuickUnlock() async {}
  @override
  Future<Uint8List> exportEncryptedBackup() async => Uint8List(0);
  @override
  Future<void> save(VaultSnapshot snapshot) async {}
}

class MemoryDocuments implements DocumentStorage {
  final files = <String, Uint8List>{};
  final deleted = <String>[];
  bool permission = true, failWrite = false, corruptRead = false;
  final missingOnDelete = <String>{};
  int creates = 0, reads = 0;
  Future<void> Function()? afterWrite;
  @override
  Future<String?> pickDirectory() async => 'tree';
  @override
  Future<bool> hasPermission(String tree) async => permission;
  @override
  Future<String> createBackup(String tree, String name) async =>
      'owned-${++creates}';
  @override
  Future<void> write(String uri, Uint8List bytes) async {
    if (failWrite) throw PlatformException(code: 'storage_full');
    files[uri] = Uint8List.fromList(bytes);
    await afterWrite?.call();
  }

  @override
  Future<Uint8List> read(String uri) async {
    reads++;
    if (!files.containsKey(uri)) {
      throw PlatformException(code: 'directory_missing');
    }
    return corruptRead ? Uint8List.fromList([123]) : files[uri]!;
  }

  @override
  Future<void> deleteOwned(String tree, String uri) async {
    deleted.add(uri);
    if (missingOnDelete.contains(uri)) {
      throw PlatformException(code: 'directory_missing');
    }
    files.remove(uri);
  }

  @override
  Future<String?> beginExport(String name, String mime) async => 'export';
  @override
  Future<void> appendExport(String handle, List<int> bytes) async {
    files[handle] = Uint8List.fromList([...files[handle] ?? [], ...bytes]);
  }

  @override
  Future<void> finishExport(String handle) async {}
  @override
  Future<void> abortExport(String handle) async {
    files.remove(handle);
  }
}

void main() {
  test(
    'JSON explicit allowlist excludes passwords by default; amounts and IDs stay strings',
    () async {
      final output = utf8.decode(
        await collect(
          ReadableExport(
            exportFixture(),
            const ReadableExportOptions(format: ReadableExportFormat.json),
          ).bytes(),
        ),
      );
      final data = jsonDecode(output) as Map;
      expect(data['schema_version'], 2);
      expect(data['accounts'][0]['id'], 'account-1');
      expect(output, isNot(contains('TEST-ONLY-CURRENT')));
      expect(data['accounts'][0].containsKey('password'), false);
      expect(
        data['password_change_history'][0].keys,
        unorderedEquals(['accountId', 'changedAtUtc', 'previousStoredAtUtc']),
      );
      for (final key in [
        'masterPassword',
        'backupPassword',
        'deviceSecret',
        'installationId',
        'preferences',
        'recovery',
      ]) {
        expect(data.containsKey(key), false);
      }
    },
  );
  test(
    'streamed CSV ZIP verifies CRC, BOM, formula neutralization, quotes and newlines',
    () async {
      final bytes = await collect(
        ReadableExport(exportFixture(), const ReadableExportOptions()).bytes(),
      );
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      expect(
        archive.files.map((e) => e.name),
        unorderedEquals([
          'accounts.csv',
          'account_custom_fields.csv',
          'binding_retirement_plans.csv',
          'subscriptions.csv',
          'expense_records.csv',
          'password_change_history.csv',
          'subscription_trials.csv',
          'subscription_reminders.csv',
          'subscription_price_history.csv',
          'payment_methods.csv',
          'metadata.json',
          'README.txt',
        ]),
      );
      final csv = archive.findFile('accounts.csv')!.content as List<int>;
      expect(csv.take(3), [239, 187, 191]);
      final text = utf8.decode(csv);
      expect(text, contains('"\'=FORMULA()"'));
      expect(text, contains('"备注,""quoted""\nnew line"'));
      expect(text, isNot(contains('TEST-ONLY-CURRENT')));
      for (final value in ['=1', '+1', '-1', '@SUM(A1)', ' \t=evil']) {
        expect(ReadableExport.csvCell(value), startsWith('"\''));
      }
    },
  );
  test(
    'trash opt-in retains deletion metadata and only explicitly selected current password',
    () async {
      final source = VaultTrash.move(
        exportFixture(),
        accountId: 'account-1',
        now: DateTime.utc(2026, 9, 3),
        batchId: 'batch',
      );
      final defaults = jsonDecode(
        utf8.decode(
          await collect(
            ReadableExport(
              source,
              const ReadableExportOptions(format: ReadableExportFormat.json),
            ).bytes(),
          ),
        ),
      );
      expect(defaults['accounts'], isEmpty);
      final expanded = jsonDecode(
        utf8.decode(
          await collect(
            ReadableExport(
              source,
              const ReadableExportOptions(
                format: ReadableExportFormat.json,
                includeTrash: true,
                includePasswords: true,
              ),
            ).bytes(),
          ),
        ),
      );
      expect(expanded['accounts'][0]['password'], 'TEST-ONLY-CURRENT');
      expect(expanded['accounts'][0]['deletion_batch_id'], 'batch');
    },
  );
  test(
    'device config encrypted, separate from backup payload, survives business saves and lock',
    () async {
      final dir = await Directory.systemTemp.createTemp('stage1-config-test-');
      addTearDown(() => dir.delete(recursive: true));
      final store = EncryptedVaultStore(
        directoryProvider: () async => dir,
        creationKdf: const VaultKdfParameters(
          memoryKiB: 64,
          iterations: 1,
          parallelism: 1,
        ),
      );
      final opened = await store.create(masterPassword: testPassword);
      final session = opened.session as DeviceBackupConfigSession;
      await session.writeDeviceBackupConfig({
        'version': 1,
        'password': testPassword,
      });
      await session.save(exportFixture());
      expect(
        (await session.readDeviceBackupConfig())!['password'],
        testPassword,
      );
      for (final file in dir.listSync().whereType<File>()) {
        expect(await file.readAsString(), isNot(contains(testPassword)));
      }
      final business = await store.readEncryptedBackup(
        bytes: await session.exportEncryptedBackup(),
        masterPassword: testPassword,
      );
      expect(
        jsonEncode(business.toEncryptedPayloadJson()),
        isNot(contains(testPassword)),
      );
      session.close();
      await expectLater(
        session.readDeviceBackupConfig(),
        throwsA(isA<VaultClosedException>()),
      );
      final reopened = await store.unlock(masterPassword: testPassword);
      expect(
        (await (reopened.session as DeviceBackupConfigSession)
            .readDeviceBackupConfig())!['password'],
        testPassword,
      );
      reopened.session.close();
    },
  );

  late MemoryDocuments documents;
  late ConfigSession session;
  late AutoBackupController controller;
  setUp(() {
    documents = MemoryDocuments();
    session = ConfigSession();
    controller = AutoBackupController(storage: documents);
  });
  tearDown(() {
    controller.dispose();
  });
  Future<bool> configure() => controller.configure(
    tree: 'tree',
    password: testPassword,
    intervalDays: 15,
  );
  test(
    'default off, first full reread verification required before enabling',
    () async {
      await controller.attach(session, exportFixture());
      expect(controller.status.enabled, false);
      expect(documents.creates, 0);
      expect(await configure(), true);
      expect(documents.reads, greaterThanOrEqualTo(1));
      expect(controller.status.validCount, 1);
      expect(controller.status.enabled, true);
      final decoded = await PortableBackupCodec().read(
        bytes: documents.files.values.single,
        backupMasterPassword: testPassword,
      );
      expect(
        decoded.snapshot.accounts.single.notes,
        exportFixture().accounts.single.notes,
      );
      expect(
        jsonEncode(decoded.snapshot.toEncryptedPayloadJson()),
        isNot(contains(testPassword)),
      );
    },
  );
  test('initial corrupt reread never enables, no old file deletion', () async {
    documents.corruptRead = true;
    await controller.attach(session, exportFixture());
    expect(await configure(), false);
    expect(controller.status.enabled, false);
    expect(session.value, isNull);
    expect(documents.deleted, ['owned-1']);
    expect(documents.files, isEmpty);
  });
  test('rotation touches only registered files after verification', () async {
    documents.files['unrelated.asmbackup'] = Uint8List.fromList([1, 2, 3]);
    await controller.attach(session, exportFixture());
    expect(await configure(), true);
    for (var i = 0; i < 4; i++) {
      expect(await controller.runNow(), true);
    }
    expect(controller.status.validCount, 3);
    expect(documents.deleted, ['owned-1', 'owned-2']);
    expect(documents.files['unrelated.asmbackup'], [1, 2, 3]);
  });
  test(
    'rotation resumes when an exact registered old URI is already absent',
    () async {
      await controller.attach(session, exportFixture());
      expect(await configure(), true);
      documents.files.remove('owned-1');
      documents.missingOnDelete.add('owned-1');
      for (var i = 0; i < 3; i++) {
        expect(await controller.runNow(), true);
      }
      expect(controller.status.validCount, 3);
      expect((session.value!['files'] as List).length, 3);
      expect(documents.deleted, contains('owned-1'));
      expect(
        documents.files.keys.where((e) => e.startsWith('owned-')).length,
        3,
      );
    },
  );
  test(
    'failed new write preserves valid old backup, dirty survives reattachment',
    () async {
      await controller.attach(session, exportFixture());
      await configure();
      documents.failWrite = true;
      await controller.observe(exportFixture('new'));
      expect(await controller.runNow(), false);
      expect(controller.status.failureCode, 'storage_full');
      expect(documents.deleted, isNot(contains('owned-1')));
      expect(documents.files.containsKey('owned-1'), true);
      controller.detach();
      await controller.attach(session, exportFixture('new'));
      expect(controller.status.dirtySince, isNotNull);
    },
  );
  test(
    'lock after write prevents further reread/decryption and does not mark valid',
    () async {
      await controller.attach(session, exportFixture());
      documents.afterWrite = () async {
        controller.detach();
      };
      expect(await configure(), false);
      expect(documents.reads, 0);
      expect(session.value, isNull);
      expect(controller.status.validCount, 0);
      expect(controller.status.enabled, false);
    },
  );
  test(
    'revoked directory is shown accurately, no writes or deletions',
    () async {
      documents.permission = false;
      await controller.attach(session, exportFixture());
      expect(await configure(), false);
      expect(controller.status.failureCode, 'permission_revoked');
      expect(documents.creates, 0);
      expect(documents.deleted, isEmpty);
    },
  );
  test('preference and business changes wait for scheduled backup', () async {
    await controller.attach(session, exportFixture());
    await configure();
    final before = documents.creates;
    await controller.observe(
      exportFixture().copyWith(
        recentAccountIds: ['account-1'],
        preferences: const VaultPreferences(autoLockSeconds: 30),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(documents.creates, before);
    await controller.observe(exportFixture('business changed'));
    await controller.observe(exportFixture('business changed again'));
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(documents.creates, before);
    expect(controller.status.dirtySince, isNotNull);
  });
  test(
    'new process detects commit even without persisting dirty flag',
    () async {
      await controller.attach(session, exportFixture());
      await configure();
      expect(session.value!['dirtySince'], isNull);
      controller.detach();
      await controller.attach(session, exportFixture('committed before crash'));
      expect(controller.status.dirtySince, isNotNull);
    },
  );
  test(
    'missing registered files are excluded from current valid count',
    () async {
      await controller.attach(session, exportFixture());
      await configure();
      documents.files.clear();
      await controller.refreshPermission();
      expect(controller.status.validCount, 0);
    },
  );
  test(
    'backup includes trash while device-only password and directory remain excluded',
    () async {
      final trash = VaultTrash.move(
        exportFixture(),
        accountId: 'account-1',
        now: DateTime.utc(2026, 9, 3),
        batchId: 'batch',
      );
      await controller.attach(session, trash);
      expect(await configure(), true);
      final read = await PortableBackupCodec().read(
        bytes: documents.files.values.single,
        backupMasterPassword: testPassword,
      );
      expect(read.snapshot.trashAccounts.single.batchId, 'batch');
      expect(read.snapshot.accounts, isEmpty);
      expect(read.snapshot.toEncryptedPayloadJson().containsKey('tree'), false);
    },
  );
}
