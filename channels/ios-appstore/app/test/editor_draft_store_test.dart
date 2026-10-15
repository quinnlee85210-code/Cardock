import 'dart:convert';
import 'dart:io';
import 'package:account_subscription_manager/core/security/editor_draft.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/storage/encrypted_vault_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _password = 'TEST-ONLY-EDITOR-1234';
const _draft = <String, Object?>{
  'kind': 'account',
  'existingId': null,
  'fields': {
    'texts': ['TEST-ONLY-PARTIAL-PRIVATE-PASSWORD', 'unfinished'],
  },
};
EncryptedVaultStore _store(Directory directory) => EncryptedVaultStore(
  directoryProvider: () async => directory,
  creationKdf: const VaultKdfParameters(
    memoryKiB: 64,
    iterations: 1,
    parallelism: 1,
  ),
);
void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('asm-editor-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'master password rotation discards old encrypted form and admits a new one',
    () async {
      final store = _store(directory);
      final opened = await store.create(masterPassword: _password);
      final session = opened.session as EditorDraftVaultSession;
      await session.writeEditorDraft(_draft);
      session.close();
      final changed = await store.changeMasterPassword(
        currentMasterPassword: _password,
        newMasterPassword: 'TEST-ONLY-ROTATED-5678',
      );
      final current = changed.session as EditorDraftVaultSession;
      expect(await current.readEditorDraft(), isNull);
      await current.writeEditorDraft(_draft);
      expect(await current.readEditorDraft(), _draft);
      current.close();
    },
  );

  test(
    'interrupted staging write recovers previous committed input and permits later edits',
    () async {
      final opened = await _store(directory).create(masterPassword: _password);
      final session = opened.session as EditorDraftVaultSession;
      await session.writeEditorDraft(_draft);
      await File(
        '${directory.path}/editor_draft_v1.json.prepared',
      ).writeAsString('{"version":1,');
      expect(await session.readEditorDraft(), _draft);
      await session.writeEditorDraft({
        ..._draft,
        'fields': {'partial': 'newer'},
      });
      expect((await session.readEditorDraft())!['fields'], {
        'partial': 'newer',
      });
      session.close();
    },
  );

  test(
    'future staged format cannot fall back to old data or be silently overwritten',
    () async {
      final opened = await _store(directory).create(masterPassword: _password);
      final session = opened.session as EditorDraftVaultSession;
      await session.writeEditorDraft(_draft);
      await File(
        '${directory.path}/editor_draft_v1.json.prepared',
      ).writeAsString('{"version":99}');
      await expectLater(
        session.readEditorDraft(),
        throwsA(isA<UnsupportedEditorDraftVersion>()),
      );
      await expectLater(
        session.writeEditorDraft(_draft),
        throwsA(isA<UnsupportedEditorDraftVersion>()),
      );
      session.close();
    },
  );

  test(
    'unfinished invalid form survives a new process, encrypted and outside business backup',
    () async {
      final opened = await _store(directory).create(masterPassword: _password);
      final session = opened.session as EditorDraftVaultSession;
      final generation = session.generation;
      await session.writeEditorDraft(_draft);
      expect(session.generation, generation);
      for (final file in directory.listSync().whereType<File>()) {
        expect(
          utf8.decode(await file.readAsBytes(), allowMalformed: true),
          isNot(contains('TEST-ONLY-PARTIAL-PRIVATE-PASSWORD')),
        );
      }
      final backup = await session.exportEncryptedBackup();
      expect(
        (await _store(directory).readEncryptedBackup(
          bytes: backup,
          masterPassword: _password,
        )).accounts,
        isEmpty,
      );
      session.close();
      final reopened = await _store(
        directory,
      ).unlock(masterPassword: _password);
      expect(
        await (reopened.session as EditorDraftVaultSession).readEditorDraft(),
        _draft,
      );
      expect(reopened.snapshot.accounts, isEmpty);
      reopened.session.close();
    },
  );

  test(
    'write admitted immediately before lock completes, locked session cannot read or write',
    () async {
      final opened = await _store(directory).create(masterPassword: _password);
      final session = opened.session as EditorDraftVaultSession;
      final saving = session.writeEditorDraft(_draft);
      session.close();
      await saving;
      await expectLater(
        session.readEditorDraft(),
        throwsA(isA<VaultClosedException>()),
      );
      await expectLater(
        session.writeEditorDraft(null),
        throwsA(isA<VaultClosedException>()),
      );
      final reopened = await _store(
        directory,
      ).unlock(masterPassword: _password);
      expect(
        await (reopened.session as EditorDraftVaultSession).readEditorDraft(),
        _draft,
      );
      reopened.session.close();
    },
  );

  test(
    'rapid edits retain newest value and explicit cancellation stays cancelled',
    () async {
      final opened = await _store(directory).create(masterPassword: _password);
      final session = opened.session as EditorDraftVaultSession;
      final writes = [
        for (var i = 0; i < 15; i++)
          session.writeEditorDraft({
            ..._draft,
            'fields': {'value': i},
          }),
      ];
      await Future.wait(writes);
      expect((await session.readEditorDraft())!['fields'], {'value': 14});
      await session.writeEditorDraft(null);
      session.close();
      final reopened = await _store(
        directory,
      ).unlock(masterPassword: _password);
      expect(
        await (reopened.session as EditorDraftVaultSession).readEditorDraft(),
        isNull,
      );
      reopened.session.close();
    },
  );

  test(
    'successful business commit invalidates old form without changing records',
    () async {
      final opened = await _store(directory).create(masterPassword: _password);
      final session = opened.session as EditorDraftVaultSession;
      await session.writeEditorDraft(_draft);
      await session.save(opened.snapshot);
      expect(await session.readEditorDraft(), isNull);
      session.close();
    },
  );

  test(
    'tampered and future draft formats are rejected without blocking vault unlock',
    () async {
      final opened = await _store(directory).create(masterPassword: _password);
      final session = opened.session as EditorDraftVaultSession;
      await session.writeEditorDraft(_draft);
      session.close();
      final file = File('${directory.path}/editor_draft_v1.json');
      final original =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      for (final bad in [
        {...original, 'version': 99},
        {...original, 'mac': base64Encode(List<int>.filled(16, 0))},
      ]) {
        await file.writeAsString(jsonEncode(bad), flush: true);
        final reopened = await _store(
          directory,
        ).unlock(masterPassword: _password);
        await expectLater(
          (reopened.session as EditorDraftVaultSession).readEditorDraft(),
          throwsA(anything),
        );
        expect(reopened.snapshot.accounts, isEmpty);
        reopened.session.close();
      }
    },
  );

  test(
    'copying draft ciphertext into another vault never reveals its fields',
    () async {
      final first = await _store(directory).create(masterPassword: _password);
      await (first.session as EditorDraftVaultSession).writeEditorDraft(_draft);
      first.session.close();
      final other = await Directory('${directory.path}/other').create();
      final second = await _store(other).create(masterPassword: _password);
      await File(
        '${directory.path}/editor_draft_v1.json',
      ).copy('${other.path}/editor_draft_v1.json');
      await expectLater(
        (second.session as EditorDraftVaultSession).readEditorDraft(),
        throwsA(anything),
      );
      second.session.close();
    },
  );
}
