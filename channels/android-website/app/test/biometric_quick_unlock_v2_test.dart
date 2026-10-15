import 'dart:io';

import 'package:account_subscription_manager/core/security/biometric_unlock.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android v2 配置检测只读取标记，不读取或解密密钥', () async {
    final bridge = _RecordingAndroidQuickUnlockV2Bridge()..configured = true;
    final store = BiometricQuickUnlockSecretStore(
      androidBridge: bridge,
      useAndroidV2: true,
    );

    expect(await store.containsSecret(), isTrue);
    expect(bridge.isConfiguredCalls, 1);
    expect(bridge.readCalls, 0);
    expect(bridge.writeCalls, 0);
  });

  test('Android v2 写入和每次读取都经过独立原生认证边界', () async {
    final bridge = _RecordingAndroidQuickUnlockV2Bridge();
    final store = BiometricQuickUnlockSecretStore(
      androidBridge: bridge,
      useAndroidV2: true,
    );
    final sourceKey = Uint8List.fromList(
      List<int>.generate(32, (index) => index),
    );
    final secret = QuickUnlockSecret(
      vaultId: 'vault-v2-test',
      dataKey: sourceKey,
    );
    addTearDown(secret.destroy);

    await store.writeSecret(secret);
    final first = await store.readSecret();
    final second = await store.readSecret();
    if (first != null) addTearDown(first.destroy);
    if (second != null) addTearDown(second.destroy);

    expect(bridge.writeCalls, 1);
    expect(bridge.readCalls, 2);
    expect(first?.vaultId, 'vault-v2-test');
    expect(second?.dataKey, orderedEquals(sourceKey));
    expect(bridge.encodedSecret, contains('"version":2'));
  });

  test('Android v2 拒绝旧版或损坏的快速解锁载荷', () async {
    final bridge = _RecordingAndroidQuickUnlockV2Bridge()
      ..configured = true
      ..encodedSecret =
          '{"version":1,"vaultId":"legacy",'
          '"dataKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="}';
    final store = BiometricQuickUnlockSecretStore(
      androidBridge: bridge,
      useAndroidV2: true,
    );

    await expectLater(
      store.readSecret(),
      throwsA(
        isA<QuickUnlockException>().having(
          (error) => error.reason,
          'reason',
          QuickUnlockFailureReason.corruptedSecret,
        ),
      ),
    );
  });

  test('Android v2 保留原生错误原因且仅四类错误判定配置失效', () async {
    const permanentCodes = <String, QuickUnlockFailureReason>{
      'key_invalidated': QuickUnlockFailureReason.keyInvalidated,
      'key_missing': QuickUnlockFailureReason.keyMissing,
      'corrupted_secret': QuickUnlockFailureReason.corruptedSecret,
      'not_configured': QuickUnlockFailureReason.notConfigured,
    };
    const transientCodes = <String, QuickUnlockFailureReason>{
      'user_canceled': QuickUnlockFailureReason.userCanceled,
      'timeout': QuickUnlockFailureReason.timeout,
      'prompt_timeout': QuickUnlockFailureReason.timeout,
      'temporary_lockout': QuickUnlockFailureReason.temporaryLockout,
      'hardware_unavailable': QuickUnlockFailureReason.hardwareUnavailable,
      'system_canceled': QuickUnlockFailureReason.systemCanceled,
      'lifecycle_canceled': QuickUnlockFailureReason.lifecycleCanceled,
      'activity_not_resumed': QuickUnlockFailureReason.activityUnavailable,
      'prompt_start_failed': QuickUnlockFailureReason.promptStartFailed,
      'key_cleanup_failed': QuickUnlockFailureReason.keySetupFailed,
      'key_generation_failed': QuickUnlockFailureReason.keySetupFailed,
      'key_load_failed': QuickUnlockFailureReason.keySetupFailed,
      'cipher_init_failed': QuickUnlockFailureReason.keySetupFailed,
      'biometric_security_update_required':
          QuickUnlockFailureReason.securityUpdateRequired,
      'biometric_unsupported': QuickUnlockFailureReason.unsupported,
      'biometric_status_unknown': QuickUnlockFailureReason.statusUnknown,
    };

    for (final entry in <String, QuickUnlockFailureReason>{
      ...permanentCodes,
      ...transientCodes,
    }.entries) {
      final bridge = _RecordingAndroidQuickUnlockV2Bridge()
        ..readError = PlatformException(
          code: entry.key,
          details: const <String, Object?>{
            'stage': 'TEST-ONLY-STAGE',
            'exceptionType': 'TestOnlyException',
          },
        );
      final store = BiometricQuickUnlockSecretStore(
        androidBridge: bridge,
        useAndroidV2: true,
      );

      await expectLater(
        store.readSecret(),
        throwsA(
          isA<QuickUnlockException>()
              .having((error) => error.reason, 'reason', entry.value)
              .having((error) => error.platformCode, 'platformCode', entry.key)
              .having(
                (error) => error.diagnosticStage,
                'diagnosticStage',
                'TEST-ONLY-STAGE',
              )
              .having(
                (error) => error.diagnosticType,
                'diagnosticType',
                'TestOnlyException',
              ),
        ),
      );
      expect(
        entry.value.invalidatesConfiguration,
        permanentCodes.containsKey(entry.key),
        reason: entry.key,
      );
    }
  });

  test('Android v2 删除不读取旧密钥且可清除不可读状态', () async {
    final bridge = _RecordingAndroidQuickUnlockV2Bridge()
      ..configured = true
      ..failReads = true;
    final store = BiometricQuickUnlockSecretStore(
      androidBridge: bridge,
      useAndroidV2: true,
    );

    await store.deleteSecret();

    expect(bridge.deleteCalls, 1);
    expect(bridge.readCalls, 0);
    expect(await store.containsSecret(), isFalse);
  });

  test('Android 原生 v2 使用 Keystore CryptoObject 强认证且不引用 v1', () async {
    final activity = await File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/MainActivity.kt',
    ).readAsString();
    final gradle = await File('android/app/build.gradle.kts').readAsString();

    expect(activity, contains('account_subscription_manager/quick_unlock_v2'));
    expect(activity, contains('KeyStore.getInstance("AndroidKeyStore")'));
    expect(activity, contains('Cipher.getInstance("AES/GCM/NoPadding")'));
    expect(activity, contains('BiometricPrompt.CryptoObject(cipher)'));
    expect(
      activity,
      contains('BiometricManager.Authenticators.BIOMETRIC_STRONG'),
    );
    expect(activity, contains('KeyProperties.AUTH_BIOMETRIC_STRONG'));
    expect(activity, contains('setUserAuthenticationParameters('));
    expect(activity, contains('setInvalidatedByBiometricEnrollment(true)'));
    expect(activity, isNot(contains('setUnlockedDeviceRequired')));
    expect(activity, contains('keyStore.deleteEntry(QUICK_UNLOCK_KEY_ALIAS)'));
    expect(activity, isNot(contains('asm_biometric_quick_unlock_v1')));
    expect(activity, isNot(contains('Log.')));
    expect(gradle, contains('androidx.biometric:biometric:1.1.0'));

    final authenticationCallCount = RegExp(
      r'authenticateWithCipher\(',
    ).allMatches(activity).length;
    expect(authenticationCallCount, 3); // write + read + method declaration

    final markerMethod = activity.substring(
      activity.indexOf('private fun isQuickUnlockV2Configured'),
      activity.indexOf('private fun writeQuickUnlockV2'),
    );
    expect(markerMethod, contains('PREF_CONFIGURED'));
    expect(markerMethod, isNot(contains('KeyStore')));
    expect(markerMethod, isNot(contains('Cipher')));
    expect(markerMethod, isNot(contains('authenticate')));

    final deleteMethod = activity.substring(
      activity.indexOf('private fun deleteQuickUnlockV2'),
      activity.indexOf('private fun clearQuickUnlockV2State'),
    );
    expect(deleteMethod, contains('clearQuickUnlockV2State()'));
    expect(deleteMethod, isNot(contains('authenticateWithCipher')));

    final writeMethod = activity.substring(
      activity.indexOf('private fun writeQuickUnlockV2'),
      activity.indexOf('private fun readQuickUnlockV2'),
    );
    expect(
      writeMethod.indexOf('clearQuickUnlockV2State()'),
      lessThan(writeMethod.indexOf('createFreshQuickUnlockV2Key()')),
    );
    expect(writeMethod, contains('var writeCommitted = false'));
    expect(writeMethod, contains('if (!writeCommitted)'));
    expect(writeMethod, contains('writeCommitted = true'));
    expect(writeMethod, contains('clearQuickUnlockV2State()'));
    expect(activity, contains('cleanupBeforeCompletion = true'));

    final freshKeyMethod = activity.substring(
      activity.indexOf('private fun createFreshQuickUnlockV2Key'),
      activity.indexOf('private fun getExistingQuickUnlockV2Key'),
    );
    expect(freshKeyMethod, contains('deleteEntry(QUICK_UNLOCK_KEY_ALIAS)'));
    expect(freshKeyMethod, contains('generateKey()'));

    final promptStartMethod = activity.substring(
      activity.indexOf('private fun startBiometricPromptWhenReady'),
      activity.indexOf('private fun completeQuickUnlockOperation'),
    );
    expect(promptStartMethod, contains('Lifecycle.State.RESUMED'));
    expect(promptStartMethod, contains('!supportFragmentManager.isStateSaved'));
    expect(activity, contains('PROMPT_READY_MAX_ATTEMPTS = 40'));
    expect(promptStartMethod, contains('PROMPT_TIMEOUT_MS'));
    expect(promptStartMethod, contains('activity_not_resumed'));
    expect(promptStartMethod, contains('prompt_start_failed'));
    expect(promptStartMethod, contains('prompt_timeout'));

    final completionMethod = activity.substring(
      activity.indexOf('private fun completeQuickUnlockOperation'),
      activity.indexOf('private fun mapBiometricError'),
    );
    expect(
      completionMethod,
      contains(
        'activeQuickUnlockLaunchRunnable?.let(mainHandler::removeCallbacks)',
      ),
    );
    expect(
      completionMethod,
      contains(
        'activeQuickUnlockTimeoutRunnable?.let(mainHandler::removeCallbacks)',
      ),
    );
    expect(activity, contains('override fun onStop()'));
    expect(
      activity,
      contains('cancelActiveQuickUnlockForLifecycle("activity_stopped")'),
    );
    expect(activity, contains('"key_generation_failed"'));
    expect(activity, contains('"cipher_init_failed"'));
    expect(activity, contains('"biometric_security_update_required"'));
  });
}

final class _RecordingAndroidQuickUnlockV2Bridge
    implements AndroidQuickUnlockV2Bridge {
  bool configured = false;
  bool failReads = false;
  Object? readError;
  Object? writeError;
  String? encodedSecret;
  int isConfiguredCalls = 0;
  int writeCalls = 0;
  int readCalls = 0;
  int deleteCalls = 0;

  @override
  Future<bool> isConfigured() async {
    isConfiguredCalls += 1;
    return configured;
  }

  @override
  Future<void> write(String encodedSecret) async {
    writeCalls += 1;
    final error = writeError;
    if (error != null) {
      throw error;
    }
    configured = true;
    this.encodedSecret = encodedSecret;
  }

  @override
  Future<String?> read() async {
    readCalls += 1;
    final error = readError;
    if (error != null) {
      throw error;
    }
    if (failReads) {
      throw StateError('simulated inaccessible biometric key');
    }
    return encodedSecret;
  }

  @override
  Future<void> delete() async {
    deleteCalls += 1;
    configured = false;
    encodedSecret = null;
  }
}
