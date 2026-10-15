import 'dart:io';

import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/storage/backup_health_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('备份健康记录只保存非敏感时间和格式状态', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-backup-health-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}health.json');
    final store = FileBackupHealthStore(fileProvider: () async => file);
    final exported = DateTime.utc(2026, 8, 1, 1, 2);
    final verified = DateTime.utc(2026, 8, 2, 3, 4);

    await store.write(
      BackupHealthRecord(
        lastExportedAtUtc: exported,
        lastVerifiedAtUtc: verified,
        lastVerifiedFormatVersion: 2,
      ),
    );
    final result = await store.read();

    expect(result.lastExportedAtUtc, exported);
    expect(result.lastVerifiedAtUtc, verified);
    expect(result.lastVerifiedFormatVersion, 2);
    final text = await file.readAsString();
    expect(text, isNot(contains('password')));
    expect(text, isNot(contains('.asmbackup')));
  });

  test('损坏健康记录不会被猜测接受', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asm-backup-health-corrupt-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}health.json');
    await file.writeAsString('{"version":999}', flush: true);
    final store = FileBackupHealthStore(fileProvider: () async => file);

    await expectLater(store.read(), throwsA(isA<VaultStorageException>()));
  });
}
