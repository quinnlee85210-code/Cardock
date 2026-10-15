import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/storage/auto_backup_controller.dart';
import 'package:account_subscription_manager/core/storage/portable_backup_codec.dart';
import 'package:account_subscription_manager/core/storage/readable_export.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_analysis.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'stage3_account_analysis_test.dart' show account, vault;
import 'stage1_backup_export_test.dart'
    show ConfigSession, MemoryDocuments, exportFixture, testPassword;
import 'support/fake_vault_store.dart';

const master = 'TEST-ONLY-Stage3-Master!';
Future<({AppState state, FakeVaultStore store})> opened(
  VaultSnapshot snapshot, {
  AutoBackupController? backup,
}) async {
  final store = FakeVaultStore(
    configured: true,
    acceptedPassword: master,
    snapshot: snapshot,
  );
  final state = AppState(
    vaultStore: store,
    now: () => DateTime.utc(2026, 9, 4),
    autoBackupController: backup,
  );
  addTearDown(state.dispose);
  await state.initialize();
  expect(await state.unlock(master), VaultActionResult.success);
  return (state: state, store: store);
}

AccountDraft edited(AccountRecord a, {String? password, String? phone}) =>
    AccountDraft(
      platformName: a.platformName,
      loginAccount: a.loginAccount,
      password: password ?? a.password,
      boundPhone: phone ?? a.boundPhone,
      boundEmail: a.boundEmail,
      category: a.category,
      customFields: a.customFields,
    );

void main() {
  test(
    'stale health consent cannot ignore a changed password or reuse group',
    () async {
      final f = await opened(
        vault([account(1, password: 'short'), account(2, password: 'short')]),
      );
      final old = f.state.accountAnalysis.healthFindings.firstWhere(
        (i) => i.accountId == 'account-1' && i.issueType == 'reusedPassword',
      );
      final second = f.state.accounts.last;
      expect(
        await f.state.updateAccount(
          accountId: second.id,
          draft: edited(second, password: 'other'),
          passwordMode: AccountPasswordUpdateMode.replace,
        ),
        isTrue,
      );
      final saves = f.store.saveCalls;
      expect(await f.state.ignorePasswordHealth(old), isFalse);
      expect(f.store.saveCalls, saves);
      final first = f.state.accounts.first;
      final oldShort = f.state.accountAnalysis.healthFindings.firstWhere(
        (i) => i.accountId == first.id && i.issueType == 'shortPassword',
      );
      expect(
        await f.state.updateAccount(
          accountId: first.id,
          draft: edited(first, password: 'new'),
          passwordMode: AccountPasswordUpdateMode.replace,
        ),
        isTrue,
      );
      expect(await f.state.ignorePasswordHealth(oldShort), isFalse);
      expect(f.state.passwordHealthIgnoreRules, isEmpty);
    },
  );
  test(
    'queries, filters and analysis do not write and lock clears cached results',
    () async {
      final f = await opened(
        vault([account(1, password: 'weak'), account(2, password: 'weak')]),
      );
      final saves = f.store.saveCalls,
          rev = f.state.localWebRevision,
          analysis = f.state.accountAnalysis;
      for (var i = 0; i < 50; i++) {
        expect(
          f.state.accountAnalysis.matches(f.state.accounts.first, '', {
            AccountFilter.hasPasswordHealth,
          }),
          isTrue,
        );
      }
      expect(f.store.saveCalls, saves);
      expect(f.state.localWebRevision, rev);
      f.state.lock();
      expect(analysis.healthFindings, isEmpty);
      expect(f.state.accountAnalysis.healthFindings, isEmpty);
      expect(f.state.passwordHealthIgnoreRules, isEmpty);
      expect(f.state.bindingRetirementPlans, isEmpty);
      expect(await f.state.batchMoveAccountsToTrash({'account-1'}), isFalse);
    },
  );
  test(
    'new duplicate needs a one-save revision approval and stale approval is rejected',
    () async {
      final f = await opened(vault([account(1, password: 'weak')]));
      final draft = AccountDraft(
        platformName: 'Fictional Cloud',
        loginAccount: 'fixture-user',
        password: 'different',
      );
      final first = await f.state.createAccount(draft);
      expect(first.status, RecordCreationStatus.duplicateConfirmationRequired);
      expect(f.store.saveCalls, 0);
      final issue = f.state.accountAnalysis.healthFindings.first;
      expect(await f.state.ignorePasswordHealth(issue), isTrue);
      expect(
        (await f.state.createAccount(
          draft,
          duplicateApprovedRevision: first.expectedRevision,
        )).status,
        RecordCreationStatus.duplicateConfirmationRequired,
      );
      final approved = await f.state.createAccount(
        draft,
        duplicateApprovedRevision: f.state.localWebRevision,
      );
      expect(approved.saved, isTrue);
      expect(f.state.accounts, hasLength(2));
      expect(
        (await f.state.createAccount(draft)).status,
        RecordCreationStatus.duplicateConfirmationRequired,
      );
    },
  );
  test(
    'failed duplicate save leaves no new record and preserves source snapshot',
    () async {
      final f = await opened(vault([account(1)]));
      final before = jsonEncode(f.store.snapshot.toEncryptedPayloadJson());
      f.store.failSaves = true;
      final outcome = await f.state.createAccount(
        AccountDraft(
          platformName: 'Fictional Cloud',
          loginAccount: 'fixture-user',
        ),
        duplicateApprovedRevision: f.state.localWebRevision,
      );
      expect(outcome.saved, isFalse);
      expect(jsonEncode(f.store.snapshot.toEncryptedPayloadJson()), before);
    },
  );
  test(
    'ignore is preserved by category edits and invalidated only after successful password change',
    () async {
      final f = await opened(vault([account(1, password: 'short')]));
      final issue = f.state.accountAnalysis.healthFindings.firstWhere(
        (i) => i.issueType == 'shortPassword',
      );
      expect(await f.state.ignorePasswordHealth(issue), isTrue);
      expect(
        await f.state.batchUpdateAccountCategory({
          'account-1',
        }, 'Custom Category'),
        isTrue,
      );
      expect(
        f.state.accountAnalysis.healthFindings
            .firstWhere((i) => i.issueType == 'shortPassword')
            .ignored,
        isTrue,
      );
      final before = f.state.accounts.single;
      f.store.failSaves = true;
      expect(
        await f.state.updateAccount(
          accountId: before.id,
          draft: edited(before, password: 'other'),
          passwordMode: AccountPasswordUpdateMode.replace,
        ),
        isFalse,
      );
      expect(f.state.passwordHealthIgnoreRules, hasLength(1));
      expect(
        f.state.accounts.single.passwordValueRevision,
        before.passwordValueRevision,
      );
      f.store.failSaves = false;
      expect(
        await f.state.updateAccount(
          accountId: before.id,
          draft: edited(before, password: 'other'),
          passwordMode: AccountPasswordUpdateMode.replace,
        ),
        isTrue,
      );
      expect(f.state.passwordHealthIgnoreRules, isEmpty);
      expect(
        f.state.accounts.single.passwordValueRevision,
        before.passwordValueRevision + 1,
      );
      expect(f.state.accounts.single.passwordChangeHistory, hasLength(1));
    },
  );
  test(
    'initial password, same-value save, clear and later first entry preserve history semantics',
    () async {
      final f = await opened(vault([account(1)]));
      for (final p in ['first-fixture', 'first-fixture']) {
        final a = f.state.accounts.single;
        expect(
          await f.state.updateAccount(
            accountId: a.id,
            draft: edited(a, password: p),
            passwordMode: AccountPasswordUpdateMode.replace,
          ),
          isTrue,
        );
      }
      expect(f.state.accounts.single.passwordValueRevision, 1);
      expect(f.state.accounts.single.passwordChangeHistory, isEmpty);
      var a = f.state.accounts.single;
      expect(
        await f.state.updateAccount(
          accountId: a.id,
          draft: edited(a),
          passwordMode: AccountPasswordUpdateMode.clear,
        ),
        isTrue,
      );
      expect(f.state.accounts.single.passwordValueRevision, 2);
      expect(f.state.accounts.single.passwordChangeHistory, isEmpty);
      a = f.state.accounts.single;
      expect(
        await f.state.updateAccount(
          accountId: a.id,
          draft: edited(a, password: 'second-fixture'),
          passwordMode: AccountPasswordUpdateMode.replace,
        ),
        isTrue,
      );
      expect(f.state.accounts.single.passwordValueRevision, 3);
      expect(f.state.accounts.single.passwordChangeHistory, isEmpty);
    },
  );
  test(
    'custom fields survive password-review metadata and batch category changes',
    () async {
      final record = AccountRecord.fromDraft(
        id: 'account-1',
        draft: AccountDraft(
          platformName: 'Fixture',
          password: 'first-fixture',
          customFields: [
            AccountCustomField(
              id: 'f1',
              name: 'Hidden',
              type: AccountCustomFieldType.sensitiveText,
              value: 'SYNTHETIC-SECRET',
              order: 0,
            ),
          ],
        ),
      );
      final f = await opened(vault([record]));
      expect(await f.state.confirmPasswordCurrent('account-1'), isTrue);
      expect(
        await f.state.batchUpdateAccountCategory({'account-1'}, 'Insurance'),
        isTrue,
      );
      expect(
        f.state.accounts.single.customFields.single.value,
        'SYNTHETIC-SECRET',
      );
      expect(
        f.state.accounts.single.passwordValueRevision,
        record.passwordValueRevision,
      );
    },
  );
  test(
    'binding plan uses current groups and actual edits, reverts and restores drive progress',
    () async {
      final f = await opened(
        vault([
          account(1, phone: '13800000000'),
          account(2, phone: '138 0000-0000'),
        ]),
      );
      final group = f.state.accountAnalysis.bindingGroups.single;
      expect(await f.state.createBindingRetirementPlan(group), isTrue);
      expect(await f.state.createBindingRetirementPlan(group), isFalse);
      final planId = f.state.bindingRetirementPlans.single.id;
      expect(await f.state.closeBindingRetirementPlan(planId), isFalse);
      final a = f.state.accounts.first;
      expect(
        await f.state.updateAccount(
          accountId: a.id,
          draft: edited(a, phone: '13900000000'),
          passwordMode: AccountPasswordUpdateMode.preserve,
        ),
        isTrue,
      );
      expect(f.state.accountAnalysis.bindingPlans.single.completedAccountIds, {
        'account-1',
      });
      expect(await f.state.deleteAccount('account-2'), isTrue);
      expect(
        f.state.accountAnalysis.bindingPlans.single.pendingAccountIds,
        isEmpty,
      );
      expect(f.state.accountAnalysis.bindingPlans.single.trashAccountIds, {
        'account-2',
      });
      expect(await f.state.restoreTrash(accountId: 'account-2'), isTrue);
      expect(f.state.accountAnalysis.bindingPlans.single.pendingAccountIds, {
        'account-2',
      });
    },
  );
  test(
    'batch categories commit once and failure or stale confirmation writes none',
    () async {
      final f = await opened(vault([account(1), account(2), account(3)]));
      final revision = f.state.localWebRevision;
      expect(
        await f.state.batchUpdateAccountCategory({
          'account-1',
          'account-2',
        }, 'Custom'),
        isTrue,
      );
      expect(f.store.saveCalls, 1);
      expect(f.state.localWebRevision, revision + 1);
      expect(f.state.accounts.last.category, isNull);
      final before = jsonEncode(f.store.snapshot.toEncryptedPayloadJson());
      f.store.failSaves = true;
      expect(
        await f.state.batchUpdateAccountCategory({
          'account-1',
          'account-2',
        }, 'Other'),
        isFalse,
      );
      expect(jsonEncode(f.store.snapshot.toEncryptedPayloadJson()), before);
      f.store.failSaves = false;
      expect(
        await f.state.batchMoveAccountsToTrash({
          'account-1',
        }, expectedRevision: revision),
        isFalse,
      );
      expect(jsonEncode(f.store.snapshot.toEncryptedPayloadJson()), before);
    },
  );
  test(
    'free over-limit existing data can be organized but duplicate approval cannot add',
    () async {
      final f = await opened(vault(List.generate(16, (i) => account(i + 1))));
      expect(
        await f.state.batchUpdateAccountCategory({
          'account-1',
          'account-16',
        }, 'Existing'),
        isTrue,
      );
      final result = await f.state.createAccount(
        AccountDraft(
          platformName: 'Fictional Cloud',
          loginAccount: 'fixture-user',
        ),
        duplicateApprovedRevision: f.state.localWebRevision,
      );
      expect(result.status, RecordCreationStatus.limitReached);
      expect(
        await f.state.batchMoveAccountsToTrash({'account-1', 'account-16'}),
        isTrue,
      );
      expect(f.state.accounts, hasLength(14));
      expect(f.state.trashAccounts, hasLength(2));
    },
  );
  test(
    'sensitive custom export requires its own confirmation and password',
    () async {
      final f = await opened(
        vault([
          AccountRecord.fromDraft(
            id: 'account-1',
            draft: AccountDraft(
              platformName: 'Fixture',
              password: 'ACCOUNT-FIXTURE',
              customFields: [
                AccountCustomField(
                  id: 'f',
                  name: 'Private',
                  type: AccountCustomFieldType.sensitiveText,
                  value: 'CUSTOM-FIXTURE',
                  order: 0,
                ),
              ],
            ),
          ),
        ]),
      );
      final docs = MemoryDocuments();
      const options = ReadableExportOptions(
        format: ReadableExportFormat.json,
        includePasswords: true,
        includeSensitiveCustomFields: true,
      );
      expect(
        await f.state.exportReadable(
          options: options,
          currentPassword: master,
          passwordDisclosureConfirmed: true,
          storage: docs,
        ),
        isFalse,
      );
      expect(docs.files, isEmpty);
      expect(
        await f.state.exportReadable(
          options: options,
          currentPassword: 'wrong',
          passwordDisclosureConfirmed: true,
          sensitiveFieldsDisclosureConfirmed: true,
          storage: docs,
        ),
        isFalse,
      );
      expect(docs.files, isEmpty);
      expect(
        await f.state.exportReadable(
          options: options,
          currentPassword: master,
          passwordDisclosureConfirmed: true,
          sensitiveFieldsDisclosureConfirmed: true,
          storage: docs,
        ),
        isTrue,
      );
      expect(utf8.decode(docs.files['export']!), contains('CUSTOM-FIXTURE'));
    },
  );
  test(
    'successful batch triggers one immediate backup and backup failure does not roll back business',
    () async {
      final docs = MemoryDocuments(),
          backup = AutoBackupController(
            storage: MemoryDocuments(),
            now: () => DateTime.utc(2026, 9, 4),
          );
      backup.dispose();
      final controller = AutoBackupController(
        storage: docs,
        now: () => DateTime.utc(2026, 9, 4),
      );
      final f = await opened(
        vault([account(1), account(2)]),
        backup: controller,
      );
      await controller.attach(ConfigSession(), f.store.snapshot);
      expect(
        await controller.configure(tree: 'tree', password: testPassword),
        isTrue,
      );
      expect(docs.creates, 1);
      expect(
        await f.state.batchUpdateAccountCategory({
          'account-1',
          'account-2',
        }, 'Sorted'),
        isTrue,
      );
      expect(docs.creates, 2);
      expect(f.store.saveCalls, 1);
      final restored = await PortableBackupCodec().read(
        bytes: docs.files['owned-2']!,
        backupMasterPassword: testPassword,
      );
      expect(
        restored.snapshot.accounts.every((a) => a.category == 'Sorted'),
        isTrue,
      );
      docs.failWrite = true;
      expect(
        await f.state.batchMoveAccountsToTrash({'account-1', 'account-2'}),
        isTrue,
      );
      expect(f.state.accounts, isEmpty);
      expect(f.state.trashAccounts, hasLength(2));
      expect(f.store.saveCalls, 2);
      expect(controller.status.failureCode, isNotNull);
      expect(f.state.warningMessage, contains('已保存'));
    },
  );
  test(
    'queued immediate backups coalesce during an existing writer and use latest snapshot',
    () async {
      final docs = MemoryDocuments(),
          controller = AutoBackupController(storage: MemoryDocuments());
      controller.dispose();
      final backup = AutoBackupController(
        storage: docs,
        now: () => DateTime.utc(2026, 9, 4),
      );
      addTearDown(backup.dispose);
      await backup.attach(ConfigSession(), exportFixture());
      expect(
        await backup.configure(tree: 'tree', password: testPassword),
        isTrue,
      );
      final gate = Completer<void>(), entered = Completer<void>();
      docs.afterWrite = () async {
        if (!entered.isCompleted) entered.complete();
        await gate.future;
      };
      final first = backup.runNow();
      await entered.future;
      await backup.observe(exportFixture('latest fictional value'));
      final queued = backup.requestImmediate(),
          second = backup.requestImmediate();
      expect(identical(queued, second), isTrue);
      gate.complete();
      expect(await first, isTrue);
      expect(await queued, isTrue);
      expect(docs.creates, 3);
      final restored = await PortableBackupCodec().read(
        bytes: docs.files['owned-3']!,
        backupMasterPassword: testPassword,
      );
      expect(restored.snapshot.accounts.single.notes, 'latest fictional value');
    },
  );
}
