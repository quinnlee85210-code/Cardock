// Dedicated iOS simulator diagnostic. Never used by the production entry point.
// Run with --debug --dart-define=CARDOCK_IOS_SMOKE_TEST=true.
import 'dart:convert';
import 'dart:io';

import 'package:account_subscription_manager/core/platform/ios_core.dart';
import 'package:account_subscription_manager/core/security/unlock_throttle.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/storage/layered_vault_store.dart';
import 'package:account_subscription_manager/core/storage/portable_backup_codec.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_expense_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

const _sourcePassword = 'TEST-ONLY-Maple-84!Local';
const _targetPassword = 'TEST-ONLY-Fjord-62!Target';
const _backupPassword = 'TEST-ONLY-Cobalt-73!Archive';

void _require(bool condition, String check) {
  if (!condition) throw StateError(check);
}

Future<void> main() async {
  if (!kDebugMode ||
      !Platform.isIOS ||
      !const bool.fromEnvironment('CARDOCK_IOS_SMOKE_TEST')) {
    throw StateError(
      'This diagnostic requires an explicitly enabled iOS debug build.',
    );
  }
  WidgetsFlutterBinding.ensureInitialized();
  final checks = <String>[];
  final resumed = File(
    '${Directory.systemTemp.path}/cardock-native-smoke-resume.request',
  ).existsSync();
  final result = <String, Object?>{
    'status': 'failed',
    'phase': resumed ? 'process-restart' : 'create-restore',
    'schema': VaultSnapshot.currentSchemaVersion,
    'checks': checks,
    'fictionalDataOnly': true,
  };
  final watch = Stopwatch()..start();
  try {
    await prepareIOSPrivateStorage();
    checks.add('native-private-storage');
    final support = await getApplicationSupportDirectory();
    _require(support.isAbsolute && await support.exists(), 'foundation-path');
    checks.add('foundation-native-assets');
    const clock = MethodChannelUnlockThrottleClock();
    final before = await clock.read();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final after = await clock.read();
    _require(
      before.bootCount == after.bootCount &&
          after.elapsedRealtimeMilliseconds >
              before.elapsedRealtimeMilliseconds,
      'native-monotonic-clock',
    );
    checks.add('native-monotonic-clock');
    final root = Directory('${support.path}/cardock-native-smoke-fixture');
    LayeredVaultStore store(String name) => LayeredVaultStore.forDirectory(
      directory: Directory('${root.path}/$name'),
    );
    void verify(VaultSnapshot snapshot) {
      _require(
        snapshot.accounts.single.platformName == 'TEST-ONLY edited',
        'account-reopened',
      );
      _require(
        snapshot.subscriptions.single.serviceName == 'TEST-ONLY subscription',
        'subscription-reopened',
      );
      _require(
        snapshot.subscriptionExpenses.single.isDeleted,
        'schema15-tombstone',
      );
    }

    if (!resumed) {
      _require(
        !await root.exists(),
        'refuse-overwriting-existing-test-fixture',
      );
      await root.create();
      final created = await store(
        'source',
      ).create(masterPassword: _sourcePassword);
      final snapshot = VaultSnapshot(
        nextAccountId: 2,
        accounts: [
          AccountRecord.fromDraft(
            id: 'account-1',
            draft: AccountDraft(
              platformName: 'TEST-ONLY initial',
              password: 'TEST-ONLY record',
            ),
          ),
        ],
        nextSubscriptionId: 2,
        subscriptions: [
          SubscriptionRecord.fromDraft(
            id: 'subscription-1',
            draft: SubscriptionDraft(
              accountId: 'account-1',
              details: SubscriptionDetailsDraft(
                serviceName: 'TEST-ONLY subscription',
                firstSubscribedOn: DateTime(2026, 9, 1),
                nextRenewalOn: DateTime(2026, 10, 1),
              ),
            ),
          ),
        ],
        nextExpenseId: 2,
        subscriptionExpenses: [
          SubscriptionExpenseRecord.fromDraft(
            id: 'expense-1',
            isDeleted: true,
            draft: SubscriptionExpenseDraft(
              subscriptionId: 'subscription-1',
              accountId: 'account-1',
              serviceName: 'TEST-ONLY subscription',
              occurredOn: DateTime(2026, 9, 1),
              amount: '20.00',
              currency: 'CNY',
              kind: SubscriptionExpenseKind.payment,
            ),
          ),
        ],
      );
      await created.session.save(snapshot);
      await created.session.save(
        snapshot.copyWith(
          accounts: [
            AccountRecord.fromDraft(
              id: 'account-1',
              draft: AccountDraft(
                platformName: 'TEST-ONLY edited',
                password: 'TEST-ONLY record',
              ),
            ),
          ],
        ),
      );
      created.session.close();
      final opened = await store(
        'source',
      ).unlock(masterPassword: _sourcePassword);
      verify(opened.snapshot);
      checks.add('argon2-aes-create-edit-reopen-schema15');
      final codec = PortableBackupCodec();
      final bytes = await codec.encryptV2(
        snapshot: opened.snapshot,
        backupMasterPassword: _backupPassword,
      );
      opened.session.close();
      _require(
        !utf8.decode(bytes).contains('TEST-ONLY edited'),
        'backup-is-encrypted',
      );
      var wrongBackupRejected = false;
      try {
        await codec.read(bytes: bytes, backupMasterPassword: _sourcePassword);
      } on PortableBackupAuthenticationException {
        wrongBackupRejected = true;
      }
      _require(wrongBackupRejected, 'wrong-backup-password-rejected');
      final decoded = await codec.read(
        bytes: bytes,
        backupMasterPassword: _backupPassword,
      );
      verify(decoded.snapshot);
      final target = await store(
        'target',
      ).create(masterPassword: _targetPassword);
      await target.session.save(decoded.snapshot);
      target.session.close();
      checks.add('encrypted-backup-restore-retains-tombstone');
    }
    final source = await store(
      'source',
    ).unlock(masterPassword: _sourcePassword);
    verify(source.snapshot);
    source.session.close();
    final target = await store(
      'target',
    ).unlock(masterPassword: _targetPassword);
    verify(target.snapshot);
    target.session.close();
    var wrongTargetRejected = false;
    try {
      final unexpected = await store(
        'target',
      ).unlock(masterPassword: _sourcePassword);
      unexpected.session.close();
    } on VaultUnlockException {
      wrongTargetRejected = true;
    }
    _require(wrongTargetRejected, 'restore-must-preserve-target-password');
    checks.add('independent-master-passwords-and-source-preserved');
    if (resumed) checks.add('encrypted-data-retained-after-process-restart');
    result['status'] = 'passed';
  } catch (error) {
    // Do not write passwords, keys, vault data, or exception payloads to logs.
    result['errorType'] = error.runtimeType.toString();
  }
  result['elapsedMilliseconds'] = watch.elapsedMilliseconds;
  final output = File(
    '${Directory.systemTemp.path}/cardock-native-smoke-result.json',
  );
  await output.writeAsString(jsonEncode(result), flush: true);
  debugPrint('CARDOCK_NATIVE_SMOKE ${jsonEncode(result)}');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Text(
              'Cardock native smoke: ${result['status']}\n${checks.join('\n')}',
            ),
          ),
        ),
      ),
    ),
  );
  acknowledgeIOSForegroundFrame();
}
