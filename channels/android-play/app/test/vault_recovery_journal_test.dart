import 'dart:convert';
import 'dart:io';

import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/storage/vault_recovery_journal.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;
  late FileVaultRecoveryJournal journal;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('asm-recovery-journal-');
    file = File('${directory.path}${Platform.pathSeparator}rollback.json');
    journal = FileVaultRecoveryJournal(fileProvider: () async => file);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('恢复前快照可验证保存并标记提交和回滚', () async {
    final transactionId = await journal.stage(
      encryptedVaultBytes: <int>[1, 2, 3, 4, 5],
      sourceGeneration: 7,
    );
    var entry = await journal.read();
    expect(entry?.transactionId, transactionId);
    expect(entry?.state, VaultRecoveryState.prepared);
    expect(entry?.revision, 1);
    expect(entry?.encryptedVaultBytes, <int>[1, 2, 3, 4, 5]);
    entry?.destroy();

    await journal.markCommitted(transactionId);
    entry = await journal.read();
    expect(entry?.state, VaultRecoveryState.committed);
    expect(entry?.revision, 2);
    entry?.destroy();

    await journal.markRolledBack(transactionId);
    entry = await journal.read();
    expect(entry?.state, VaultRecoveryState.rolledBack);
    expect(entry?.revision, 3);
    entry?.destroy();
  });

  test('清除回滚副本会提交两份无密文 tombstone 并尽力清理旧凭据', () async {
    await journal.stage(
      encryptedVaultBytes: <int>[1, 2, 3, 4],
      sourceGeneration: 1,
    );
    await File('${file.path}.tmp').writeAsString('legacy-temp');
    await File('${file.path}.a.tmp').writeAsString('slot-a-temp');
    await File('${file.path}.b.tmp').writeAsString('slot-b-temp');

    await journal.clear();

    expect(await journal.read(), isNull);
    final slotA = File('${file.path}.a');
    final slotB = File('${file.path}.b');
    expect(await slotA.exists(), isTrue);
    expect(await slotB.exists(), isTrue);
    for (final slot in <File>[slotA, slotB]) {
      final decoded =
          jsonDecode(await slot.readAsString()) as Map<String, dynamic>;
      expect(decoded['version'], 3);
      expect(decoded['state'], 'discarded');
      expect(decoded.containsKey('encryptedVault'), isFalse);
    }
    expect(await file.exists(), isFalse);
    expect(await File('${file.path}.tmp').exists(), isFalse);
    expect(await File('${file.path}.a.tmp').exists(), isFalse);
    expect(await File('${file.path}.b.tmp').exists(), isFalse);

    final transactionId = await journal.stage(
      encryptedVaultBytes: <int>[9, 8, 7],
      sourceGeneration: 2,
    );
    final staged = await journal.read();
    expect(staged?.transactionId, transactionId);
    expect(staged?.revision, 4);
    expect(staged?.state, VaultRecoveryState.prepared);
    staged?.destroy();
  });

  test('第二份 tombstone 写入失败时第一份仍完成逻辑清除', () async {
    await journal.stage(
      encryptedVaultBytes: <int>[10, 20, 30],
      sourceGeneration: 1,
    );
    final legacyCopy = await File('${file.path}.a').readAsString();
    await file.writeAsString(legacyCopy, flush: true);
    await File('${file.path}.a').delete();
    final blockedSecondTemporary = Directory('${file.path}.a.tmp');
    await blockedSecondTemporary.create();

    await journal.clear();

    expect(await journal.read(), isNull);
    final firstTombstone =
        jsonDecode(await File('${file.path}.b').readAsString())
            as Map<String, dynamic>;
    expect(firstTombstone['revision'], 2);
    expect(firstTombstone['state'], 'discarded');
    expect(firstTombstone.containsKey('encryptedVault'), isFalse);

    await blockedSecondTemporary.delete();
    final transactionId = await journal.stage(
      encryptedVaultBytes: <int>[40, 50, 60],
      sourceGeneration: 2,
    );
    final staged = await journal.read();
    expect(staged?.transactionId, transactionId);
    expect(staged?.revision, 3);
    staged?.destroy();
  });

  test('最新 tombstone 损坏时上一份 tombstone 仍阻止旧槽复活', () async {
    await journal.stage(
      encryptedVaultBytes: <int>[61, 62, 63],
      sourceGeneration: 3,
    );
    final retiredEntry = await File('${file.path}.a').readAsString();
    await journal.clear();
    await file.writeAsString(retiredEntry, flush: true);
    await File('${file.path}.a').writeAsString('corrupt', flush: true);

    expect(await journal.read(), isNull);
    final surviving =
        jsonDecode(await File('${file.path}.b').readAsString())
            as Map<String, dynamic>;
    expect(surviving['revision'], 2);
    expect(surviving['state'], 'discarded');
  });

  test('位翻转后的回滚文件被安全拒绝', () async {
    await journal.stage(
      encryptedVaultBytes: <int>[7, 8, 9, 10],
      sourceGeneration: 1,
    );
    final slot = File('${file.path}.a');
    final decoded =
        jsonDecode(await slot.readAsString()) as Map<String, dynamic>;
    decoded['encryptedVault'] = base64Encode(<int>[7, 8, 9, 11]);
    await slot.writeAsString(jsonEncode(decoded), flush: true);

    await expectLater(journal.read(), throwsA(isA<VaultStorageException>()));
  });

  test('旧版 v1 主文件可读且下一次写入升级为带 revision 的双槽', () async {
    final encrypted = <int>[11, 12, 13, 14];
    final digest = await Sha256().hash(encrypted);
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'magic': 'ASM_LOCAL_RESTORE_ROLLBACK',
        'version': 1,
        'transactionId': 'legacy-transaction',
        'createdAtUtc': DateTime.utc(2026, 8, 1).toIso8601String(),
        'sourceGeneration': 3,
        'state': VaultRecoveryState.committed.name,
        'encryptedVault': base64Encode(encrypted),
        'sha256': base64UrlEncode(digest.bytes),
      }),
      flush: true,
    );

    var entry = await journal.read();
    expect(entry?.revision, 1);
    expect(entry?.state, VaultRecoveryState.committed);
    entry?.destroy();

    await journal.stage(
      encryptedVaultBytes: <int>[21, 22, 23],
      sourceGeneration: 4,
    );
    entry = await journal.read();
    expect(entry?.revision, 2);
    expect(entry?.state, VaultRecoveryState.prepared);
    expect(await file.exists(), isTrue);
    expect(await File('${file.path}.b').exists(), isTrue);
    entry?.destroy();
  });

  test('v2 双槽继续可读且后续清除升级为 v3 tombstone', () async {
    final encrypted = <int>[71, 72, 73, 74];
    final record = <String, Object?>{
      'magic': 'ASM_LOCAL_RESTORE_ROLLBACK',
      'version': 2,
      'revision': 8,
      'transactionId': 'version-two-transaction',
      'createdAtUtc': DateTime.utc(2026, 8, 1).toIso8601String(),
      'sourceGeneration': 4,
      'state': VaultRecoveryState.committed.name,
      'encryptedVault': base64Encode(encrypted),
    };
    final digest = await Sha256().hash(utf8.encode(jsonEncode(record)));
    await File('${file.path}.b').writeAsString(
      jsonEncode(<String, Object?>{
        ...record,
        'sha256': base64UrlEncode(digest.bytes),
      }),
      flush: true,
    );

    var entry = await journal.read();
    expect(entry?.revision, 8);
    expect(entry?.encryptedVaultBytes, encrypted);
    entry?.destroy();

    await journal.clear();
    expect(await journal.read(), isNull);
    entry = await journal.read();
    expect(entry, isNull);
    final revisions = <int>[];
    for (final path in <String>['${file.path}.a', '${file.path}.b']) {
      final decoded =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      expect(decoded['version'], 3);
      expect(decoded['state'], 'discarded');
      expect(decoded.containsKey('encryptedVault'), isFalse);
      revisions.add(decoded['revision'] as int);
    }
    expect(revisions.toSet(), <int>{9, 10});
  });

  test('槽位最终 rename 失败时仍从有效 tmp 选择最新 revision', () async {
    await journal.stage(
      encryptedVaultBytes: <int>[31, 32, 33],
      sourceGeneration: 5,
    );
    final slotA = File('${file.path}.a');
    final blockedSlotB = Directory('${file.path}.b');
    await blockedSlotB.create();
    final prepared = await journal.read();
    final transactionId = prepared!.transactionId;
    prepared.destroy();

    await expectLater(
      journal.markCommitted(transactionId),
      throwsA(isA<VaultStorageException>()),
    );

    final recovered = await journal.read();
    expect(recovered?.revision, 2);
    expect(recovered?.state, VaultRecoveryState.committed);
    expect(await slotA.exists(), isTrue);
    expect(await File('${file.path}.b.tmp').exists(), isTrue);
    recovered?.destroy();
  });

  test('最新槽损坏时回退到上一份有效 revision', () async {
    final transactionId = await journal.stage(
      encryptedVaultBytes: <int>[41, 42, 43],
      sourceGeneration: 6,
    );
    await journal.markCommitted(transactionId);
    await File('${file.path}.b').writeAsString('corrupt', flush: true);

    final recovered = await journal.read();
    expect(recovered?.revision, 1);
    expect(recovered?.state, VaultRecoveryState.prepared);
    recovered?.destroy();
  });
}
