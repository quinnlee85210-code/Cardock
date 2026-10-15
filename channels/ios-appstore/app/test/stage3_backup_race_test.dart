import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/core/storage/auto_backup_controller.dart';
import 'package:account_subscription_manager/core/storage/portable_backup_codec.dart';
import 'stage1_backup_export_test.dart'
    show ConfigSession, MemoryDocuments, exportFixture, testPassword;

class _DisableGateSession extends ConfigSession {
  Completer<void>? disableEntered;
  Completer<void>? disableGate;
  @override
  Future<void> writeDeviceBackupConfig(Map<String, Object?>? data) async {
    if (data?['enabled'] == false && disableGate != null) {
      disableEntered?.complete();
      await disableGate!.future;
    }
    await super.writeDeviceBackupConfig(data);
  }
}

class _RotationDocuments extends MemoryDocuments {
  bool failDelete = false;
  Completer<void>? deleteEntered;
  Completer<void>? deleteGate;
  @override
  Future<void> deleteOwned(String tree, String uri) async {
    if (failDelete) throw StateError('Synthetic provider delete failure');
    if (deleteGate != null) {
      if (!deleteEntered!.isCompleted) deleteEntered!.complete();
      await deleteGate!.future;
    }
    await super.deleteOwned(tree, uri);
  }
}

Future<AutoBackupController> _configured(
  MemoryDocuments documents, {
  ConfigSession? session,
}) async {
  final controller = AutoBackupController(
    storage: documents,
    now: () => DateTime.utc(2026, 9, 4),
  );
  addTearDown(controller.dispose);
  await controller.attach(session ?? ConfigSession(), exportFixture());
  expect(
    await controller.configure(tree: 'tree', password: testPassword),
    isTrue,
  );
  return controller;
}

void main() {
  test(
    'immediate request queued while disabling completes false without a later unlock',
    () async {
      final documents = MemoryDocuments(), session = _DisableGateSession();
      final controller = await _configured(documents, session: session);
      session.disableGate = Completer<void>();
      session.disableEntered = Completer<void>();
      final disabling = controller.disable();
      await session.disableEntered!.future;
      final request = controller.requestImmediate();
      session.disableGate!.complete();
      expect(await disabling, isTrue);
      expect(await request.timeout(const Duration(seconds: 2)), isFalse);
      expect(controller.status.enabled, isFalse);
      expect(documents.creates, 1);
    },
  );

  test(
    'two immediate requests through interrupted rotation share one successful write',
    () async {
      final documents = _RotationDocuments();
      final controller = await _configured(documents);
      expect(await controller.runNow(), isTrue);
      expect(await controller.runNow(), isTrue);
      documents.failDelete = true;
      expect(await controller.runNow(), isFalse);
      expect(controller.status.cleanupPending, isTrue);
      expect(documents.creates, 4);
      documents.failDelete = false;
      documents.deleteEntered = Completer<void>();
      documents.deleteGate = Completer<void>();
      final first = controller.requestImmediate();
      await documents.deleteEntered!.future;
      final second = controller.requestImmediate();
      expect(identical(first, second), isTrue);
      documents.deleteGate!.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(documents.creates, 5);
      expect(controller.status.cleanupPending, isFalse);
      expect(controller.status.validCount, 3);
    },
  );

  test(
    'new revision during an immediate write is included before shared requests complete',
    () async {
      final documents = MemoryDocuments();
      final controller = await _configured(documents);
      final entered = Completer<void>(), gate = Completer<void>();
      documents.afterWrite = () async {
        if (!entered.isCompleted) entered.complete();
        await gate.future;
      };
      final first = controller.requestImmediate();
      await entered.future;
      await controller.observe(exportFixture('LATEST-SYNTHETIC-REVISION'));
      final second = controller.requestImmediate();
      expect(identical(first, second), isTrue);
      gate.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(documents.creates, 3);
      final restored = await PortableBackupCodec().read(
        bytes: documents.files['owned-3']!,
        backupMasterPassword: testPassword,
      );
      expect(
        restored.snapshot.accounts.single.notes,
        'LATEST-SYNTHETIC-REVISION',
      );
    },
  );

  test(
    'lock cancels an active immediate request once and late completion cannot republish',
    () async {
      final documents = MemoryDocuments();
      final controller = await _configured(documents);
      final entered = Completer<void>(), gate = Completer<void>();
      documents.afterWrite = () async {
        if (!entered.isCompleted) entered.complete();
        await gate.future;
      };
      final request = controller.requestImmediate();
      await entered.future;
      controller.detach();
      expect(await request.timeout(const Duration(seconds: 2)), isFalse);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.status.enabled, isFalse);
      expect(controller.status.lastWritten, isNull);
      expect(await controller.requestImmediate(), isFalse);
    },
  );

  test(
    'failed immediate writer resolves every coalesced request without looping',
    () async {
      final documents = MemoryDocuments();
      final controller = await _configured(documents);
      documents.failWrite = true;
      final first = controller.requestImmediate(),
          second = controller.requestImmediate();
      expect(identical(first, second), isTrue);
      expect(await first, isFalse);
      expect(await second, isFalse);
      expect(documents.creates, 2);
      expect(controller.status.failureCode, isNotNull);
    },
  );
}
