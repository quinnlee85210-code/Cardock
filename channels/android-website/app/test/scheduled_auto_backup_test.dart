import 'dart:async';
import 'dart:convert';

import 'package:account_subscription_manager/core/storage/auto_backup_controller.dart';
import 'package:account_subscription_manager/core/storage/portable_backup_codec.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stage1_backup_export_test.dart'
    show ConfigSession, MemoryDocuments, exportFixture, testPassword;

class FailingCleanupDocuments extends MemoryDocuments {
  bool failDelete = false;
  @override
  Future<void> deleteOwned(String tree, String uri) async {
    if (failDelete) throw PlatformException(code: 'provider_refused');
    await super.deleteOwned(tree, uri);
  }
}

void main() {
  late DateTime current;
  late ConfigSession session;
  late FailingCleanupDocuments documents;
  late AutoBackupController controller;
  setUp(() {
    current = DateTime.utc(2026, 9, 4);
    session = ConfigSession();
    documents = FailingCleanupDocuments();
    controller = AutoBackupController(storage: documents, now: () => current);
  });
  tearDown(() => controller.dispose());

  Future<void> configured([int days = 15]) async {
    await controller.attach(session, exportFixture());
    expect(
      await controller.configure(
        tree: 'tree',
        password: testPassword,
        intervalDays: days,
      ),
      true,
    );
  }

  for (final days in [7, 15, 30]) {
    test('$days day schedule writes unchanged data only when due', () async {
      await configured(days);
      final due = current.add(Duration(days: days));
      expect(controller.status.nextDueAt, due);
      expect(controller.status.intervalDays, days);
      expect(controller.status.retention, 3);
      current = due.subtract(const Duration(milliseconds: 1));
      expect(await controller.runIfDue(), false);
      expect(documents.creates, 1);
      current = due;
      expect(await controller.runIfDue(), true);
      expect(documents.creates, 2);
      expect(controller.status.nextDueAt, due.add(Duration(days: days)));
      expect(await controller.runIfDue(), false);
      final recovered = await PortableBackupCodec().read(
        bytes: documents.files['owned-2']!,
        backupMasterPassword: testPassword,
      );
      expect(
        recovered.snapshot.toEncryptedPayloadJson(),
        exportFixture().toEncryptedPayloadJson(),
      );
    });
  }

  test(
    'edits wait until due and the scheduled file has the latest data',
    () async {
      await configured();
      await controller.observe(exportFixture('first change'));
      await controller.observe(exportFixture('latest change'));
      expect(await controller.runIfDue(), false);
      expect(documents.creates, 1);
      expect(controller.status.dirtySince, isNotNull);
      current = current.add(const Duration(days: 15));
      expect(await controller.runIfDue(), true);
      final decoded = await PortableBackupCodec().read(
        bytes: documents.files['owned-2']!,
        backupMasterPassword: testPassword,
      );
      expect(decoded.snapshot.accounts.single.notes, 'latest change');
      expect(controller.status.dirtySince, isNull);
    },
  );

  test(
    'unlock after multiple missed periods catches up once and persists',
    () async {
      await configured();
      controller.detach();
      current = current.add(const Duration(days: 95));
      expect(await controller.runIfDue(), false);
      expect(documents.creates, 1);
      await controller.attach(session, exportFixture());
      expect(await controller.runIfDue(), true);
      expect(documents.creates, 2);
      final next = current.add(const Duration(days: 15));
      controller.dispose();
      controller = AutoBackupController(storage: documents, now: () => current);
      await controller.attach(session, exportFixture());
      expect(controller.status.nextDueAt, next);
      expect(await controller.runIfDue(), false);
      expect(documents.creates, 2);
    },
  );

  test(
    'unchanged periodic files rotate to the newest three, preserving unrelated files',
    () async {
      await configured(7);
      documents.files['manual-backup'] = Uint8List.fromList([1, 2, 3]);
      for (var i = 0; i < 5; i++) {
        current = current.add(const Duration(days: 7));
        expect(await controller.runIfDue(), true);
      }
      expect(
        documents.files.keys,
        unorderedEquals(['manual-backup', 'owned-4', 'owned-5', 'owned-6']),
      );
      expect(documents.deleted, ['owned-1', 'owned-2', 'owned-3']);
      expect(controller.status.validCount, 3);
      expect(controller.status.cleanupPending, false);
    },
  );

  test(
    'corrupt replacement never evicts the previous three or advances the deadline',
    () async {
      await configured();
      await controller.runNow();
      await controller.runNow();
      final due = controller.status.nextDueAt;
      current = due!;
      documents.corruptRead = true;
      expect(await controller.runIfDue(), false);
      expect(
        documents.files.keys,
        unorderedEquals(['owned-1', 'owned-2', 'owned-3']),
      );
      expect(documents.deleted, ['owned-4']);
      expect(controller.status.nextDueAt, due);
      documents.corruptRead = false;
      expect(await controller.runIfDue(), true);
      expect(
        documents.files.keys,
        unorderedEquals(['owned-2', 'owned-3', 'owned-5']),
      );
    },
  );

  test(
    'failed cleanup is retried without accumulating new files, including after restart',
    () async {
      await configured();
      await controller.runNow();
      await controller.runNow();
      current = controller.status.nextDueAt!;
      documents.failDelete = true;
      expect(await controller.runIfDue(), false);
      expect(controller.status.cleanupPending, true);
      expect(controller.status.failureCode, 'cleanup_failed');
      expect(documents.creates, 4);
      expect(await controller.runIfDue(), false);
      expect(documents.creates, 4);
      controller.detach();
      await controller.attach(session, exportFixture());
      expect(await controller.runIfDue(), false);
      expect(documents.creates, 4);
      documents.failDelete = false;
      expect(await controller.runIfDue(), true);
      expect(documents.creates, 4);
      expect(
        documents.files.keys,
        unorderedEquals(['owned-2', 'owned-3', 'owned-4']),
      );
      expect(controller.status.cleanupPending, false);
      expect(controller.status.failureCode, isNull);
      expect(await controller.runIfDue(), false);
    },
  );

  test(
    'cleanup retry revalidates replacement before deleting old recovery points',
    () async {
      await configured();
      await controller.runNow();
      await controller.runNow();
      documents.failDelete = true;
      expect(await controller.runNow(), false);
      documents.failDelete = false;
      documents.files['owned-4'] = Uint8List.fromList([1]);
      expect(await controller.runIfDue(), false);
      expect(documents.deleted, isEmpty);
      expect(documents.creates, 4);
      expect(controller.status.failureCode, 'verification_failed');
    },
  );

  test(
    'interval updates save immediately without asking for or rewriting credentials',
    () async {
      await configured();
      final previous = jsonDecode(jsonEncode(session.value)) as Map;
      current = current.add(const Duration(days: 10));
      expect(await controller.updateInterval(30), true);
      expect(controller.status.nextDueAt, DateTime.utc(2026, 10, 4));
      expect(session.value!['password'], previous['password']);
      expect(session.value!['tree'], previous['tree']);
      expect(session.value!['files'], previous['files']);
      expect(documents.creates, 1);
      session.fail = true;
      expect(await controller.updateInterval(7), false);
      expect(controller.status.intervalDays, 30);
      expect(session.value!['intervalDays'], 30);
      session.fail = false;
      expect(await controller.updateInterval(7), true);
      expect(await controller.runIfDue(), true);
      expect(controller.status.nextDueAt, current.add(const Duration(days: 7)));
    },
  );

  test(
    'unsupported intervals do not change configuration or create files',
    () async {
      await configured();
      final before = jsonEncode(session.value);
      for (final days in [0, 14, 31]) {
        expect(await controller.updateInterval(days), false);
        expect(
          await controller.configure(
            tree: 'tree',
            password: testPassword,
            intervalDays: days,
          ),
          false,
        );
      }
      expect(jsonEncode(session.value), before);
      expect(documents.creates, 1);
    },
  );

  test(
    'legacy settings migrate without deleting backups before a new verified file',
    () async {
      await configured();
      final files = <Map<String, Object?>>[];
      final original = Map<String, Object?>.from(
        (session.value!['files'] as List).single as Map,
      );
      for (var n = 1; n <= 5; n++) {
        final uri = 'legacy-$n';
        documents.files[uri] = Uint8List.fromList(documents.files['owned-1']!);
        files.add({...original, 'uri': uri});
      }
      documents.files.remove('owned-1');
      controller.detach();
      session.value =
          {...session.value!, 'version': 1, 'retention': 5, 'files': files}
            ..remove('intervalDays')
            ..remove('nextDueAt')
            ..remove('cleanupPending');
      await controller.attach(session, exportFixture());
      expect(session.value!['version'], 2);
      expect(controller.status.intervalDays, 15);
      expect(controller.status.retention, 3);
      expect(session.value!['files'], files);
      expect(session.value!['password'], testPassword);
      expect(documents.deleted, isEmpty);
      documents.failWrite = true;
      expect(await controller.runNow(), false);
      expect(documents.files.keys, containsAll(files.map((e) => e['uri'])));
      documents.failWrite = false;
      expect(await controller.runNow(), true);
      expect(
        documents.files.keys,
        unorderedEquals(['legacy-4', 'legacy-5', 'owned-3']),
      );
    },
  );

  test(
    'future or malformed configuration is rejected without overwrite or deletion',
    () async {
      await configured();
      final valid = Map<String, Object?>.from(session.value!);
      for (final bad in [
        {...valid, 'version': 3},
        {...valid, 'intervalDays': 0},
        {...valid, 'nextDueAt': 'invalid'},
        {...valid, 'retention': 5},
      ]) {
        controller.detach();
        session.value = bad;
        final before = jsonEncode(bad);
        await controller.attach(session, exportFixture());
        expect(controller.status.enabled, false);
        expect(controller.status.failureCode, 'config_unreadable');
        expect(
          await controller.configure(tree: 'tree', password: testPassword),
          false,
        );
        expect(await controller.runIfDue(), false);
        expect(jsonEncode(session.value), before);
        expect(documents.deleted, isEmpty);
        expect(documents.creates, 1);
      }
    },
  );

  test(
    'failed migration retains the old config and cannot silently replace it',
    () async {
      await configured();
      controller.detach();
      session.value = {...session.value!, 'version': 1, 'retention': 10}
        ..remove('intervalDays')
        ..remove('nextDueAt');
      final before = jsonEncode(session.value);
      session.fail = true;
      await controller.attach(session, exportFixture());
      expect(controller.status.failureCode, 'config_unreadable');
      expect(jsonEncode(session.value), before);
      session.fail = false;
      expect(
        await controller.configure(tree: 'tree', password: testPassword),
        false,
      );
      expect(documents.creates, 1);
      expect(documents.deleted, isEmpty);
    },
  );

  test(
    'disabled schedule stays disabled across deadline and reattachment',
    () async {
      await configured();
      expect(await controller.disable(), true);
      current = current.add(const Duration(days: 100));
      controller.detach();
      await controller.attach(session, exportFixture());
      expect(controller.status.enabled, false);
      expect(await controller.runIfDue(), false);
      expect(documents.creates, 1);
      expect(documents.deleted, isEmpty);
    },
  );

  test('clock moving backward does not cause an early backup', () async {
    await configured(7);
    current = current.subtract(const Duration(days: 100));
    expect(await controller.runIfDue(), false);
    expect(documents.creates, 1);
  });

  test(
    'deadline timer triggers while unlocked without a user action or edit',
    () async {
      await configured(7);
      final due = controller.status.nextDueAt!;
      current = due.subtract(const Duration(milliseconds: 50));
      final wrote = Completer<void>();
      documents.afterWrite = () async {
        if (!wrote.isCompleted) wrote.complete();
      };
      expect(await controller.updateInterval(7), true);
      current = due;
      await wrote.future.timeout(const Duration(seconds: 5));
      for (var n = 0; n < 500 && controller.status.busy; n++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(controller.status.busy, false);
      expect(documents.creates, 2);
      expect(controller.status.nextDueAt, due.add(const Duration(days: 7)));
    },
  );
}
