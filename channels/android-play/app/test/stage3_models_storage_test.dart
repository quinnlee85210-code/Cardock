import 'dart:convert';
import 'dart:io';
import 'package:account_subscription_manager/app/app_state.dart';
import 'support/fake_vault_store.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/core/security/biometric_unlock.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/security/vault_trash.dart';
import 'package:account_subscription_manager/core/storage/layered_vault_store.dart';
import 'package:account_subscription_manager/core/storage/portable_backup_codec.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/pending_subscription_draft.dart';

const _password = 'SYNTHETIC-TEST-ONLY-Stage3!';
const _decoyPassword = 'SYNTHETIC-TEST-ONLY-Decoy3!';
final _now = DateTime.utc(2026, 9, 4);

AccountCustomField _field({
  String id = 'f1',
  String name = 'Label',
  AccountCustomFieldType type = AccountCustomFieldType.text,
  String value = '',
  int order = 0,
}) => AccountCustomField(
  id: id,
  name: name,
  type: type,
  value: value,
  order: order,
);

AccountRecord _account({
  String id = 'account-1',
  String? password = 'SYNTHETIC-PASSWORD',
  List<AccountCustomField> fields = const [],
}) => AccountRecord.fromDraft(
  id: id,
  draft: AccountDraft(
    platformName: 'Synthetic platform',
    password: password,
    boundEmail: 'Synthetic@EXAMPLE.invalid',
    notes: 'Legacy note remains intact',
    customFields: fields,
  ),
);

VaultSnapshot _fixture() {
  final account = _account(
    fields: [
      _field(value: '  Original text  '),
      _field(
        id: 'f2',
        name: 'Private field',
        type: AccountCustomFieldType.sensitiveText,
        value: 'SYNTHETIC-SENSITIVE-FIELD',
        order: 1,
      ),
      _field(
        id: 'f3',
        name: 'Precise',
        type: AccountCustomFieldType.number,
        value: '9007199254740993.12345678901234567890',
        order: 2,
      ),
    ],
  );
  return VaultSnapshot(
    nextAccountId: 2,
    accounts: [account],
    nextSubscriptionId: 2,
    subscriptions: [
      SubscriptionRecord.fromDraft(
        id: 'subscription-1',
        draft: SubscriptionDraft(
          accountId: account.id,
          details: SubscriptionDetailsDraft(
            serviceName: 'Synthetic service',
            amount: '1.2345',
            firstSubscribedOn: DateTime(2026, 9, 1),
            nextRenewalOn: DateTime(2026, 10, 1),
          ),
        ),
      ),
    ],
    passwordHealthIgnoreRules: [
      PasswordHealthIgnoreRule(
        accountId: account.id,
        issueType: 'unknownChangeDate',
        passwordValueRevision: 1,
      ),
    ],
    bindingRetirementPlans: [
      BindingRetirementPlan(
        id: 'plan-1',
        type: BindingType.email,
        targetValue: 'Synthetic@EXAMPLE.invalid',
        normalizedValue: 'synthetic@example.invalid',
        createdAtUtc: _now,
        accountIds: {account.id},
      ),
    ],
  );
}

class _QuickUnlock implements QuickUnlockSecretStore {
  QuickUnlockSecret? value;
  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.available;
  @override
  Future<bool> containsSecret() async => value != null;
  @override
  Future<void> deleteSecret() async {
    value?.destroy();
    value = null;
  }

  @override
  Future<QuickUnlockSecret?> readSecret() async => value == null
      ? null
      : QuickUnlockSecret(vaultId: value!.vaultId, dataKey: value!.dataKey);
  @override
  Future<void> writeSecret(QuickUnlockSecret secret) async {
    value?.destroy();
    value = QuickUnlockSecret(vaultId: secret.vaultId, dataKey: secret.dataKey);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('typed custom fields', () {
    test('values and precise decimals roundtrip without conversion', () {
      final source = _fixture();
      final result = VaultSnapshot.fromEncryptedPayloadJson(
        jsonDecode(jsonEncode(source.toEncryptedPayloadJson())),
      );
      expect(result.toEncryptedPayloadJson(), source.toEncryptedPayloadJson());
      expect(
        result.accounts.single.customFields.first.value,
        '  Original text  ',
      );
      expect(
        result.accounts.single.customFields.last.value,
        '9007199254740993.12345678901234567890',
      );
    });
    test('ten empty values count as fields and eleventh is rejected', () {
      final fields = [
        for (var i = 0; i < 10; i++)
          _field(id: 'f$i', name: 'Field $i', order: i),
      ];
      expect(
        AccountDraft(platformName: 'Test', customFields: fields).customFields,
        hasLength(10),
      );
      expect(
        () => AccountDraft(
          platformName: 'Test',
          customFields: [
            ...fields,
            _field(id: 'f10', name: 'Field 10', order: 10),
          ],
        ),
        throwsArgumentError,
      );
    });
    test(
      'name normalization detects fullwidth case and collapsed whitespace',
      () {
        expect(normalizeCustomFieldName('  Ｍｙ　 Ｆｉｅｌｄ  '), 'my field');
        expect(
          () => validateAccountCustomFields([
            _field(name: '  Ｍｙ　 Ｆｉｅｌｄ  '),
            _field(id: 'f2', name: 'my field', order: 1),
          ]),
          throwsArgumentError,
        );
        expect(() => _field(name: '　 '), throwsArgumentError);
      },
    );
    test(
      'duplicate identifiers or order are rejected, user order is stable',
      () {
        expect(
          () => validateAccountCustomFields([
            _field(),
            _field(name: 'Second', order: 1),
          ]),
          throwsArgumentError,
        );
        expect(
          () => validateAccountCustomFields([
            _field(),
            _field(id: 'f2', name: 'Second'),
          ]),
          throwsArgumentError,
        );
        expect(
          validateAccountCustomFields([
            _field(id: 'f2', name: 'Second', order: 8),
            _field(order: 2),
          ]).map((field) => field.id),
          ['f1', 'f2'],
        );
      },
    );
    test('dates and decimals reject invalid loss-prone encodings', () {
      for (final invalid in [
        '2026-02-30',
        '2026-2-2',
        '2026-09-04T00:00:00Z',
      ]) {
        expect(
          () => _field(type: AccountCustomFieldType.date, value: invalid),
          throwsArgumentError,
        );
      }
      expect(
        _field(type: AccountCustomFieldType.date, value: '2024-02-29').value,
        '2024-02-29',
      );
      for (final invalid in ['NaN', 'Infinity', '1e20', '1.2.3', ' 2 ']) {
        expect(
          () => _field(type: AccountCustomFieldType.number, value: invalid),
          throwsArgumentError,
        );
      }
      expect(
        _field(type: AccountCustomFieldType.number, value: '-0001.2300').value,
        '-0001.2300',
      );
    });
    test('unknown type and invalid json reject without reinterpretation', () {
      final raw = _field().toJson()..['type'] = 'future';
      expect(() => AccountCustomField.fromJson(raw), throwsFormatException);
      expect(
        () => AccountCustomField.fromJson(_field().toJson()..['value'] = 1.5),
        throwsFormatException,
      );
    });
    test(
      'search includes names and safe values but excludes sensitive values and password',
      () {
        final account = _fixture().accounts.single;
        expect(account.matches('Private field'), isTrue);
        expect(account.matches('Original text'), isTrue);
        expect(account.matches('SYNTHETIC-SENSITIVE-FIELD'), isFalse);
        expect(account.matches('SYNTHETIC-PASSWORD'), isFalse);
      },
    );
  });
  group('password revisions and legacy schema', () {
    test('initial baseline and unchanged saves never fabricate history', () {
      final stored = _account(), empty = _account(password: null);
      expect(stored.passwordValueRevision, 1);
      expect(empty.passwordValueRevision, 0);
      expect(stored.revisionAfterPasswordSave(stored.password), 1);
      expect(stored.revisionAfterPasswordSave('DIFFERENT-SYNTHETIC'), 2);
      expect(stored.revisionAfterPasswordSave(null), 2);
      expect(empty.revisionAfterPasswordSave('FIRST-SYNTHETIC'), 1);
      expect(stored.passwordChangeHistory, isEmpty);
      expect(stored.historyAfterPasswordSave(null, _now), isEmpty);
    });
    for (var schema = 1; schema <= 12; schema++) {
      test('schema $schema migrates new data to safe empty defaults', () {
        final old = _fixture().toEncryptedPayloadJson()
          ..['schemaVersion'] = schema;
        final restored = VaultSnapshot.fromEncryptedPayloadJson(old);
        expect(restored.requiresSchemaUpgrade, isTrue);
        expect(restored.accounts.single.customFields, isEmpty);
        expect(restored.accounts.single.passwordValueRevision, 1);
        expect(restored.accounts.single.passwordChangeHistory, isEmpty);
        expect(restored.accounts.single.notes, 'Legacy note remains intact');
        expect(restored.passwordHealthIgnoreRules, isEmpty);
        expect(restored.bindingRetirementPlans, isEmpty);
        if (schema > 1) {
          expect(restored.subscriptions.single.id, 'subscription-1');
          expect(restored.subscriptions.single.amount, '1.2345');
        }
        expect(
          VaultSnapshot.fromEncryptedPayloadJson(
            restored.toEncryptedPayloadJson(),
          ).requiresSchemaUpgrade,
          isFalse,
        );
      });
    }
    test('schema 12 empty current password receives zero revision', () {
      final old = VaultSnapshot(
        nextAccountId: 2,
        accounts: [_account(password: null)],
      ).toEncryptedPayloadJson()..['schemaVersion'] = 12;
      expect(
        VaultSnapshot.fromEncryptedPayloadJson(
          old,
        ).accounts.single.passwordValueRevision,
        0,
      );
    });
    test('future schema refuses before any payload interpretation', () {
      expect(
        () => VaultSnapshot.fromEncryptedPayloadJson({
          'schemaVersion': VaultSnapshot.currentSchemaVersion + 1,
        }),
        throwsA(isA<VaultUnsupportedSchemaVersionException>()),
      );
    });
  });
  group('scope relationships and trash', () {
    test(
      'copyWith preserves metadata and empty snapshot clears all metadata',
      () {
        final source = _fixture();
        expect(
          source.copyWith().toEncryptedPayloadJson(),
          source.toEncryptedPayloadJson(),
        );
        expect(VaultSnapshot.empty().passwordHealthIgnoreRules, isEmpty);
        expect(VaultSnapshot.empty().bindingRetirementPlans, isEmpty);
      },
    );
    test('reject dangling ignore owner, group member, and plan scope', () {
      final source = _fixture();
      for (final rule in [
        PasswordHealthIgnoreRule(
          accountId: 'missing',
          issueType: 'short',
          passwordValueRevision: 0,
        ),
        PasswordHealthIgnoreRule(
          accountId: 'account-1',
          issueType: 'reuse',
          passwordValueRevision: 1,
          memberRevisions: {'missing': 0},
        ),
      ]) {
        expect(
          () => source.copyWith(passwordHealthIgnoreRules: [rule]),
          throwsA(isA<VaultFormatException>()),
        );
      }
      expect(
        () => source.copyWith(
          bindingRetirementPlans: [
            source.bindingRetirementPlans.single.copyWith(
              accountIds: {'missing'},
            ),
          ],
        ),
        throwsA(isA<VaultFormatException>()),
      );
    });
    test(
      'reject duplicate active plan target and mismatched normalized value',
      () {
        final source = _fixture(),
            plan = _fixture().bindingRetirementPlans.single;
        expect(
          () => source.copyWith(
            bindingRetirementPlans: [
              plan,
              BindingRetirementPlan(
                id: 'plan-2',
                type: plan.type,
                targetValue: plan.targetValue,
                normalizedValue: plan.normalizedValue,
                createdAtUtc: _now,
                accountIds: plan.accountIds,
              ),
            ],
          ),
          throwsA(isA<VaultFormatException>()),
        );
        expect(
          () => BindingRetirementPlan(
            id: 'bad',
            type: BindingType.email,
            targetValue: 'a@example.invalid',
            normalizedValue: 'b@example.invalid',
            createdAtUtc: _now,
            accountIds: {'account-1'},
          ),
          throwsArgumentError,
        );
        expect(
          () => PasswordHealthIgnoreRule(
            accountId: 'account-1',
            issueType: 'short',
            passwordValueRevision: -1,
          ),
          throwsArgumentError,
        );
      },
    );
    test(
      'trash roundtrip restores fields and rules; permanent deletion clears references',
      () {
        final source = _fixture();
        final moved = VaultTrash.move(
          source,
          accountId: 'account-1',
          now: _now,
          batchId: 'batch-1',
        );
        final decoded = VaultSnapshot.fromEncryptedPayloadJson(
          jsonDecode(jsonEncode(moved.toEncryptedPayloadJson())),
        );
        expect(
          decoded.trashAccounts.single.record.customFields[1].isSensitive,
          isTrue,
        );
        final restored = VaultTrash.restore(
          decoded,
          accountId: 'account-1',
          wholeBatch: true,
        );
        expect(
          restored.accounts.single.toEncryptedPayloadJson(),
          source.accounts.single.toEncryptedPayloadJson(),
        );
        expect(
          restored.passwordHealthIgnoreRules.single.toJson(),
          source.passwordHealthIgnoreRules.single.toJson(),
        );
        final removed = VaultTrash.remove(decoded, accountIds: {'account-1'});
        expect(removed.passwordHealthIgnoreRules, isEmpty);
        expect(removed.bindingRetirementPlans, isEmpty);
        expect(removed.trashAccounts, isEmpty);
      },
    );
  });
  test(
    'portable V2 encrypts and restores every new field without changing envelope',
    () async {
      final source = _fixture(), codec = PortableBackupCodec();
      final bytes = await codec.encryptV2(
        snapshot: source,
        backupMasterPassword: _password,
      );
      expect(utf8.decode(bytes), isNot(contains('SYNTHETIC-SENSITIVE-FIELD')));
      final restored = await codec.read(
        bytes: bytes,
        backupMasterPassword: _password,
      );
      expect(
        restored.snapshot.toEncryptedPayloadJson(),
        source.toEncryptedPayloadJson(),
      );
      await expectLater(
        codec.read(bytes: bytes, backupMasterPassword: 'SYNTHETIC-WRONG'),
        throwsA(isA<PortableBackupAuthenticationException>()),
      );
    },
  );
  test(
    'encrypted batch rollback and subscription-only/decoy projection preserve isolation',
    () async {
      final parent = Directory('../backups/testdata/stage3-models');
      await parent.create(recursive: true);
      final directory = await parent.createTemp('synthetic-'),
          quick = _QuickUnlock();
      addTearDown(quick.deleteSecret);
      final store = LayeredVaultStore.forDirectory(
        directory: directory,
        creationKdf: const VaultKdfParameters(
          memoryKiB: 64,
          iterations: 1,
          parallelism: 1,
        ),
        quickUnlockSecretStore: quick,
      );
      final source = _fixture(),
          created = await store.create(masterPassword: _password);
      await created.session.save(source);
      final batch = created.session as BatchRollbackVaultSession;
      await batch.saveBatchWithRollback(
        before: source,
        after: source.copyWith(
          passwordHealthIgnoreRules: [],
          bindingRetirementPlans: [],
        ),
      );
      final undone = await batch.undoLastBatch();
      expect(undone.toEncryptedPayloadJson(), source.toEncryptedPayloadJson());
      created.session.close();
      await store.configureQuickUnlock(
        currentMasterPassword: _password,
        scope: QuickUnlockScope.subscriptionsOnly,
      );
      final view = await store.unlockWithQuickUnlock();
      expect(view.snapshot.passwordHealthIgnoreRules, isEmpty);
      expect(view.snapshot.bindingRetirementPlans, isEmpty);
      expect(
        view.snapshot.accounts.every((account) => account.customFields.isEmpty),
        isTrue,
      );
      final projected = jsonEncode(view.snapshot.toEncryptedPayloadJson());
      expect(projected, isNot(contains('SYNTHETIC-SENSITIVE-FIELD')));
      expect(projected, isNot(contains('Synthetic@EXAMPLE.invalid')));
      await expectLater(
        view.session.save(source),
        throwsA(isA<VaultClosedException>()),
      );
      view.session.close();
      await store.createDecoyVault(
        currentMasterPassword: _password,
        decoyPassword: _decoyPassword,
      );
      final decoy = await store.unlock(masterPassword: _decoyPassword);
      expect(decoy.snapshot.accounts, isEmpty);
      expect(decoy.snapshot.passwordHealthIgnoreRules, isEmpty);
      expect(decoy.snapshot.bindingRetirementPlans, isEmpty);
      decoy.session.close();
      final real = await store.unlock(masterPassword: _password);
      expect(
        real.snapshot.toEncryptedPayloadJson(),
        source.toEncryptedPayloadJson(),
      );
      real.session.close();
      // Only encrypted synthetic fixtures remain in the project testdata directory.
    },
  );
  test(
    'bulk trash moves selected accounts, subscriptions and drafts in one snapshot',
    () {
      final source = _fixture().copyWith(
        nextAccountId: 3,
        accounts: [
          ..._fixture().accounts,
          _account(id: 'account-2'),
        ],
        pendingSubscriptionDrafts: [
          PendingSubscriptionDraft(
            draftId: 'draft-1',
            accountId: 'account-1',
            createdAt: _now,
            updatedAt: _now,
          ),
          PendingSubscriptionDraft(
            draftId: 'draft-2',
            accountId: 'account-2',
            createdAt: _now,
            updatedAt: _now,
          ),
        ],
      );
      final moved = VaultTrash.moveAccounts(
        source,
        accountIds: {'account-1', 'account-2'},
        now: _now,
        batchId: 'bulk-1',
      );
      expect(moved.accounts, isEmpty);
      expect(moved.subscriptions, isEmpty);
      expect(moved.pendingSubscriptionDrafts, isEmpty);
      expect(moved.trashAccounts, hasLength(2));
      expect(moved.trashSubscriptions, hasLength(1));
      expect(
        moved.trashAccounts.map((a) => a.pendingDrafts.single.draftId).toSet(),
        {'draft-1', 'draft-2'},
      );
      expect(
        moved.trashAccounts.first.record.customFields[1].isSensitive,
        isTrue,
      );
      final restored = VaultTrash.restore(
        moved,
        accountId: 'account-1',
        wholeBatch: true,
      );
      expect(restored.accounts, hasLength(2));
      expect(restored.pendingSubscriptionDrafts, hasLength(2));
      expect(restored.subscriptions, hasLength(1));
      expect(
        () => VaultTrash.moveAccounts(
          source,
          accountIds: {'account-1', 'missing'},
          now: _now,
          batchId: 'invalid',
        ),
        throwsA(isA<VaultFormatException>()),
      );
      expect(source.accounts, hasLength(2));
    },
  );
  test(
    'bulk trash processes 5000 synthetic account scopes without changing identifiers',
    () {
      final source = VaultSnapshot(
        nextAccountId: 5001,
        accounts: [
          for (var index = 1; index <= 5000; index++)
            _account(id: 'account-$index'),
        ],
      );
      final moved = VaultTrash.moveAccounts(
        source,
        accountIds: source.accounts.map((a) => a.id).toSet(),
        now: _now,
        batchId: 'bulk-5000',
      );
      expect(moved.trashAccounts, hasLength(5000));
      expect(moved.accounts, isEmpty);
      expect(moved.nextAccountId, 5001);
      expect(moved.trashAccounts.last.record.id, 'account-5000');
    },
  );

  test(
    'schema12 full unlock is atomic, failure keeps old snapshot, second unlock skips migration',
    () async {
      final raw = _fixture().toEncryptedPayloadJson()..['schemaVersion'] = 12;
      final old = VaultSnapshot.fromEncryptedPayloadJson(raw);
      final store = FakeVaultStore(
        configured: true,
        acceptedPassword: _password,
        snapshot: old,
      )..failSaves = true;
      final state = AppState(vaultStore: store);
      addTearDown(state.dispose);
      await state.initialize();
      expect(await state.unlock(_password), isNot(VaultActionResult.success));
      expect(state.isUnlocked, isFalse);
      expect(
        store.snapshot.toEncryptedPayloadJson(),
        old.toEncryptedPayloadJson(),
      );
      expect(store.snapshot.requiresSchemaUpgrade, isTrue);
      expect(store.saveCalls, 0);
      store.failSaves = false;
      expect(await state.unlock(_password), VaultActionResult.success);
      expect(store.saveCalls, 1);
      expect(store.snapshot.requiresSchemaUpgrade, isFalse);
      expect(store.snapshot.accounts.single.customFields, isEmpty);
      expect(store.snapshot.accounts.single.passwordValueRevision, 1);
      state.lock();
      expect(await state.unlock(_password), VaultActionResult.success);
      expect(store.saveCalls, 1);
    },
  );
}
