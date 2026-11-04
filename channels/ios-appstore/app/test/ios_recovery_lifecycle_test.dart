import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/security/biometric_unlock.dart';
import 'package:account_subscription_manager/core/security/recovery_device_secret.dart';
import 'package:account_subscription_manager/core/security/unlock_throttle.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/security/vault_crypto.dart';
import 'package:account_subscription_manager/core/security/vault_recovery.dart';
import 'package:account_subscription_manager/core/storage/layered_vault_store.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/vault/presentation/vault_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

// Unit tests use real encrypted synthetic vaults. Widget tests use FakeVaultStore
// and the real Dart iOS adapter with a mocked channel, not iOS authentication.
const _original = 'Synthetic-Original-91!Harbor';
const _replacement = 'Synthetic-Recovered-91!Meadow';
const _decoy = 'Synthetic-Decoy-91!Grove';
const _questions = ['childhood_city', 'first_school', 'first_teacher'];
const _answers = ['synthetic city', 'synthetic school', 'synthetic teacher'];
const _channel = MethodChannel('cardock/ios_biometric_secret_v1');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _NativeRecovery native;

  setUp(() {
    native = _NativeRecovery();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, native.handle);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test(
    'locking during recovery throttle reset cannot reopen the vault',
    () async {
      final throttle = _PausedThrottleStore();
      final fixture = await _Fixture.create(throttle: throttle);
      addTearDown(fixture.dispose);
      final state = fixture.state;
      expect(
        await state.unlock('Synthetic-Wrong-91!'),
        VaultActionResult.rejected,
      );
      expect(state.failedUnlockAttempts, 1);
      throttle.pauseClear = true;
      final recovery = state.recoverMasterPassword(
        questionIds: _questions,
        answers: _answers,
        newMasterPassword: _replacement,
        requestEntryMode: VaultRecoveryEntryMode.visible,
      );
      await throttle.clearStarted.future.timeout(const Duration(seconds: 10));
      expect(state.externalInteractionInProgress, isTrue);
      state.lock();
      throttle.releaseClear.complete();
      expect(await recovery, isFalse);
      expect(state.vaultPhase, VaultPhase.locked);
      expect(state.accounts, isEmpty);
      expect(state.externalInteractionInProgress, isFalse);
      expect(state.isBusy, isFalse);
      // Credential commit already completed. A fresh, explicit unlock is needed.
      expect(await state.unlock(_replacement), VaultActionResult.success);
      expect(state.accounts.single.platformName, 'Synthetic recovery record');
    },
  );

  for (final failure in {
    'auth_in_progress': '上一次系统验证仍在结束，请稍后重试；原密码和保险库数据未修改。',
    'storage_error': '本机恢复密钥暂时无法访问，密保操作未完成；原密码和保险库数据未修改。',
    'lifecycle_canceled': '系统验证已中断，密保操作未完成。请保持应用在前台重试。',
    'system_canceled': '系统验证已中断，密保操作未完成。请保持应用在前台重试。',
    'activity_not_resumed': '系统验证已中断，密保操作未完成。请保持应用在前台重试。',
    'timeout': '系统验证已超时，密保操作未完成。请重新发起验证。',
  }.entries) {
    test(
      'iOS recovery ${failure.key} preserves credentials and data',
      () async {
        final fixture = await _Fixture.create();
        addTearDown(fixture.dispose);
        await fixture.store.createDecoyVault(
          currentMasterPassword: _original,
          decoyPassword: _decoy,
        );
        expect(await fixture.state.unlock(_decoy), VaultActionResult.success);
        await fixture.state.addAccount(
          AccountDraft(platformName: 'Synthetic decoy record'),
        );
        fixture.state.lock();
        final primaryBefore = await _encryptedFilesSnapshot(
          Directory('${fixture.directory.path}/encrypted_vault_v1'),
        );
        final decoyBefore = await _encryptedFilesSnapshot(
          Directory('${fixture.directory.path}/encrypted_vault_secondary_v1'),
        );
        final payloadBefore = native.payload;
        native.readFailure = failure.key;
        expect(
          await fixture.state.recoverMasterPassword(
            questionIds: _questions,
            answers: _answers,
            newMasterPassword: _replacement,
            requestEntryMode: VaultRecoveryEntryMode.visible,
          ),
          isFalse,
        );
        expect(fixture.state.errorMessage, failure.value);
        expect(fixture.state.vaultPhase, VaultPhase.locked);
        expect(fixture.state.primaryRecoveryConfigured, isTrue);
        expect(fixture.state.isBusy, isFalse);
        expect(fixture.state.externalInteractionInProgress, isFalse);
        expect(native.payload == payloadBefore, isTrue);
        expect(
          await _encryptedFilesSnapshot(
                Directory('${fixture.directory.path}/encrypted_vault_v1'),
              ) ==
              primaryBefore,
          isTrue,
        );
        expect(
          await _encryptedFilesSnapshot(
                Directory(
                  '${fixture.directory.path}/encrypted_vault_secondary_v1',
                ),
              ) ==
              decoyBefore,
          isTrue,
        );
        final decoyUnchanged = await fixture.store.unlock(
          masterPassword: _decoy,
        );
        expect(
          decoyUnchanged.snapshot.accounts.single.platformName,
          'Synthetic decoy record',
        );
        decoyUnchanged.session.close();
        final unchanged = await fixture.store.unlock(masterPassword: _original);
        expect(
          unchanged.snapshot.accounts.single.platformName,
          'Synthetic recovery record',
        );
        unchanged.session.close();
        await expectLater(
          fixture.store.unlock(masterPassword: _replacement),
          throwsA(isA<VaultUnlockException>()),
        );
      },
    );
  }

  for (final background in [false, true]) {
    testWidgets(
      background
          ? 'iOS recovery background and late native success leave the vault locked'
          : 'iOS recovery submission survives inactive and resumed',
      (tester) async {
        final store = await _widgetStore();
        await tester.pumpWidget(AccountSubscriptionApp(vaultStore: store));
        await _pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('vault-unlock-page'))
              .evaluate()
              .isNotEmpty,
        );
        final state = tester.widget<VaultGate>(find.byType(VaultGate)).appState;
        final entry = find.byKey(
          const ValueKey('visible-vault-recovery-entry'),
        );
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        for (var i = 0; i < _answers.length; i++) {
          await tester.enterText(
            find.byKey(ValueKey('recovery-answer-${i + 1}')),
            _answers[i],
          );
        }
        await tester.enterText(
          find.byKey(const ValueKey('recovery-new-master-password')),
          _replacement,
        );
        await tester.enterText(
          find.byKey(const ValueKey('recovery-confirm-master-password')),
          _replacement,
        );
        native.pauseRead = true;
        final submit = find.byKey(const ValueKey('submit-vault-recovery'));
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await _pumpUntil(tester, () => native.readStarted.isCompleted);
        expect(state.isBusy, isTrue);
        expect(state.externalInteractionInProgress, isTrue);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(find.byKey(const ValueKey('privacy-shield')), findsOneWidget);
        if (background) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        native.releaseRead.complete();
        await _pumpUntil(tester, () => !state.isBusy);
        expect(state.externalInteractionInProgress, isFalse);
        expect(native.readCalls, 1);
        if (background) {
          expect(state.vaultPhase, VaultPhase.locked);
          expect(state.accounts, isEmpty);
          expect(
            find.byKey(const ValueKey('vault-unlock-page')),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('home-page')), findsNothing);
        } else {
          expect(state.isUnlocked, isTrue);
          expect(
            state.accounts.single.platformName,
            'Synthetic recovery record',
          );
          expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
          await tester.runAsync(() async {
            await expectLater(
              store.unlock(masterPassword: _original),
              throwsA(isA<VaultUnlockException>()),
            );
            final reopened = await store.unlock(masterPassword: _replacement);
            expect(
              reopened.snapshot.accounts.single.platformName,
              'Synthetic recovery record',
            );
            reopened.session.close();
          });
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  fail('Synthetic recovery did not reach the expected state');
}

Future<FakeVaultStore> _widgetStore() async {
  final store = FakeVaultStore();
  final seed = AppState(vaultStore: store);
  await seed.initialize();
  expect(await seed.createVault(_original), VaultActionResult.success);
  await seed.addAccount(
    AccountDraft(platformName: 'Synthetic recovery record'),
  );
  expect(
    await seed.configurePasswordRecovery(
      currentMasterPassword: _original,
      questionIds: _questions,
      answers: _answers,
      entryMode: VaultRecoveryEntryMode.visible,
    ),
    isTrue,
  );
  seed.dispose();
  final deviceStore = BiometricRecoveryDeviceSecretStore(
    useAndroidV1: false,
    useIOSBridge: true,
  );
  final material = RecoveryDeviceSecretMaterial(
    vaultInstanceId: 'synthetic-vault',
    slotId: 'synthetic-slot',
    deviceBindingId: 'synthetic-binding',
    deviceSecret: List<int>.filled(32, 7),
  );
  try {
    await deviceStore.write(material);
  } finally {
    material.destroy();
  }
  store.beforeRecoveryForTesting = () async {
    final restored = await deviceStore.read();
    expect(restored, isNotNull);
    restored?.destroy();
  };
  return store;
}

Future<String> _encryptedFilesSnapshot(Directory directory) async {
  final files = await directory
      .list(recursive: true)
      .where((entry) => entry is File)
      .cast<File>()
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  return jsonEncode({
    for (final file in files) file.path: base64Encode(await file.readAsBytes()),
  });
}

final class _NativeRecovery {
  String? payload;
  bool pauseRead = false;
  String? readFailure;
  int readCalls = 0;
  final readStarted = Completer<void>();
  final releaseRead = Completer<void>();

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments as Map<Object?, Object?>;
    if (args['kind'] == 'quickUnlock') {
      if (call.method == 'availability') return 'not_enrolled';
      return false;
    }
    expect(args['kind'], 'recovery');
    switch (call.method) {
      case 'isConfigured':
        return payload != null;
      case 'write':
        payload = args['payload']! as String;
        return null;
      case 'read':
        readCalls++;
        if (readFailure != null) throw PlatformException(code: readFailure!);
        if (!readStarted.isCompleted) readStarted.complete();
        if (pauseRead) await releaseRead.future;
        return payload;
      case 'delete':
        payload = null;
        return null;
      default:
        fail('Unexpected recovery method ${call.method}');
    }
  }
}

final class _Fixture {
  _Fixture(this.directory, this.store, this.state);
  final Directory directory;
  final LayeredVaultStore store;
  final AppState state;

  static Future<_Fixture> create({UnlockThrottleStore? throttle}) async {
    final directory = await Directory.systemTemp.createTemp(
      'cardock-synthetic-ios-recovery-',
    );
    final store = LayeredVaultStore.forDirectory(
      directory: directory,
      creationKdf: const VaultKdfParameters(
        memoryKiB: 64,
        iterations: 1,
        parallelism: 1,
      ),
      quickUnlockSecretStore: BiometricQuickUnlockSecretStore(
        useAndroidV2: false,
        useIOSBridge: true,
      ),
      recoveryDeviceSecretStore: BiometricRecoveryDeviceSecretStore(
        useAndroidV1: false,
        useIOSBridge: true,
      ),
    );
    final setup = AppState(vaultStore: store);
    await setup.initialize();
    expect(await setup.createVault(_original), VaultActionResult.success);
    await setup.addAccount(
      AccountDraft(platformName: 'Synthetic recovery record'),
    );
    expect(
      await setup.configurePasswordRecovery(
        currentMasterPassword: _original,
        questionIds: _questions,
        answers: _answers,
        entryMode: VaultRecoveryEntryMode.visible,
      ),
      isTrue,
    );
    setup.dispose();
    final state = AppState(
      vaultStore: store,
      unlockThrottleController: UnlockThrottleController(
        throttle ?? MemoryUnlockThrottleStore(),
        MemoryUnlockThrottleClock(),
      ),
    );
    await state.initialize();
    expect(state.vaultPhase, VaultPhase.locked);
    return _Fixture(directory, store, state);
  }

  Future<void> dispose() async {
    state.dispose();
    // Directory.systemTemp creates this isolated synthetic vault only.
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

final class _PausedThrottleStore implements UnlockThrottleStore {
  final _delegate = MemoryUnlockThrottleStore();
  bool pauseClear = false;
  final clearStarted = Completer<void>();
  final releaseClear = Completer<void>();

  @override
  Future<UnlockThrottleRecord?> read() => _delegate.read();

  @override
  Future<void> write(UnlockThrottleRecord record) async {
    if (pauseClear && record.state == UnlockThrottleRecordState.cleared) {
      if (!clearStarted.isCompleted) clearStarted.complete();
      await releaseClear.future;
    }
    await _delegate.write(record);
  }
}
