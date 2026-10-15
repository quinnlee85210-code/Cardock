import 'dart:convert';
import 'dart:io';

import 'package:account_subscription_manager/core/security/recovery_device_secret.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MethodChannel bridge 使用冻结的 v1 方法与 payload 参数', () async {
    const channel = MethodChannel(
      'account_subscription_manager/recovery_device_secret_v1',
    );
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'isConfigured' => true,
            'read' => '{"version":1}',
            _ => null,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    const bridge = MethodChannelAndroidRecoveryDeviceSecretBridge();

    expect(await bridge.isConfigured(), isTrue);
    await bridge.write('payload-json');
    expect(await bridge.read(), '{"version":1}');
    await bridge.delete();

    expect(
      calls.map((call) => call.method),
      orderedEquals(<String>['isConfigured', 'write', 'read', 'delete']),
    );
    expect(calls[1].arguments, <String, Object?>{'payload': 'payload-json'});
  });

  test('配置检测只读取独立非敏感 marker', () async {
    final bridge = _RecordingRecoveryDeviceSecretBridge()..configured = true;
    final store = BiometricRecoveryDeviceSecretStore(
      androidBridge: bridge,
      useAndroidV1: true,
    );

    expect(await store.isConfigured(), isTrue);
    expect(bridge.isConfiguredCalls, 1);
    expect(bridge.readCalls, 0);
    expect(bridge.writeCalls, 0);
  });

  test('仅保存32字节设备秘密及三项绑定元数据', () async {
    final bridge = _RecordingRecoveryDeviceSecretBridge();
    final store = BiometricRecoveryDeviceSecretStore(
      androidBridge: bridge,
      useAndroidV1: true,
    );
    final sourceBytes = List<int>.generate(32, (index) => index + 1);
    final material = RecoveryDeviceSecretMaterial(
      vaultInstanceId: 'vault-2026',
      slotId: 'recovery-slot-a',
      deviceBindingId: 'vault-envelope-sha256-binding',
      deviceSecret: sourceBytes,
    );
    addTearDown(material.destroy);

    await store.write(material);
    final decoded = jsonDecode(bridge.encodedPayload!) as Map<String, Object?>;
    expect(decoded.keys.toSet(), <String>{
      'version',
      'vaultInstanceId',
      'slotId',
      'deviceBindingId',
      'deviceSecret',
    });
    expect(decoded['version'], 1);
    expect(base64Decode(decoded['deviceSecret']! as String), sourceBytes);
    expect(bridge.writeCalls, 1);

    final first = await store.read();
    final second = await store.read();
    if (first != null) addTearDown(first.destroy);
    if (second != null) addTearDown(second.destroy);
    expect(bridge.readCalls, 2, reason: '每次读取都必须进入一次独立原生强认证调用');
    expect(first?.vaultInstanceId, 'vault-2026');
    expect(first?.slotId, 'recovery-slot-a');
    expect(first?.deviceBindingId, 'vault-envelope-sha256-binding');
    expect(first?.deviceSecret, orderedEquals(sourceBytes));
    expect(second?.deviceSecret, orderedEquals(sourceBytes));
  });

  test('拒绝非32字节设备秘密、空元数据和未知载荷字段', () async {
    expect(
      () => RecoveryDeviceSecretMaterial(
        vaultInstanceId: 'vault',
        slotId: 'slot',
        deviceBindingId: 'binding',
        deviceSecret: List<int>.filled(31, 7),
      ),
      throwsArgumentError,
    );
    expect(
      () => RecoveryDeviceSecretMaterial(
        vaultInstanceId: '',
        slotId: 'slot',
        deviceBindingId: 'binding',
        deviceSecret: List<int>.filled(32, 7),
      ),
      throwsArgumentError,
    );

    final bridge = _RecordingRecoveryDeviceSecretBridge()
      ..configured = true
      ..encodedPayload = jsonEncode(<String, Object?>{
        'version': 1,
        'vaultInstanceId': 'vault',
        'slotId': 'slot',
        'deviceBindingId': 'binding',
        'deviceSecret': base64Encode(List<int>.filled(32, 7)),
        'unexpected': 'must-fail-closed',
      });
    final store = BiometricRecoveryDeviceSecretStore(
      androidBridge: bridge,
      useAndroidV1: true,
    );
    await expectLater(
      store.read(),
      throwsA(
        isA<RecoveryDeviceSecretException>()
            .having(
              (error) => error.reason,
              'reason',
              RecoveryDeviceSecretFailureReason.corruptedSecret,
            )
            .having(
              (error) => error.platformCode,
              'platformCode',
              'corrupted_secret',
            ),
      ),
    );
  });

  test('原生错误保留非敏感诊断且永久错误才使配置失效', () async {
    const permanentCodes = <String, RecoveryDeviceSecretFailureReason>{
      'key_invalidated': RecoveryDeviceSecretFailureReason.keyInvalidated,
      'key_missing': RecoveryDeviceSecretFailureReason.keyMissing,
      'corrupted_secret': RecoveryDeviceSecretFailureReason.corruptedSecret,
      'not_configured': RecoveryDeviceSecretFailureReason.notConfigured,
    };
    const transientCodes = <String, RecoveryDeviceSecretFailureReason>{
      'user_canceled': RecoveryDeviceSecretFailureReason.userCanceled,
      'prompt_timeout': RecoveryDeviceSecretFailureReason.timeout,
      'temporary_lockout': RecoveryDeviceSecretFailureReason.temporaryLockout,
      'hardware_unavailable':
          RecoveryDeviceSecretFailureReason.hardwareUnavailable,
      'lifecycle_canceled': RecoveryDeviceSecretFailureReason.lifecycleCanceled,
      'activity_not_resumed':
          RecoveryDeviceSecretFailureReason.activityUnavailable,
      'prompt_start_failed':
          RecoveryDeviceSecretFailureReason.promptStartFailed,
      'key_generation_failed': RecoveryDeviceSecretFailureReason.keySetupFailed,
    };

    for (final entry in <String, RecoveryDeviceSecretFailureReason>{
      ...permanentCodes,
      ...transientCodes,
    }.entries) {
      final bridge = _RecordingRecoveryDeviceSecretBridge()
        ..readError = PlatformException(
          code: entry.key,
          details: const <String, Object?>{
            'stage': 'TEST-ONLY-STAGE',
            'exceptionType': 'TestOnlyException',
          },
        );
      final store = BiometricRecoveryDeviceSecretStore(
        androidBridge: bridge,
        useAndroidV1: true,
      );

      await expectLater(
        store.read(),
        throwsA(
          isA<RecoveryDeviceSecretException>()
              .having((error) => error.reason, 'reason', entry.value)
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

  test('删除不读取设备秘密且非Android不做软件认证降级', () async {
    final bridge = _RecordingRecoveryDeviceSecretBridge()
      ..configured = true
      ..failReads = true;
    final store = BiometricRecoveryDeviceSecretStore(
      androidBridge: bridge,
      useAndroidV1: true,
    );

    await store.delete();
    expect(bridge.deleteCalls, 1);
    expect(bridge.readCalls, 0);
    expect(await store.isConfigured(), isFalse);

    final unsupported = BiometricRecoveryDeviceSecretStore(
      androidBridge: bridge,
      useAndroidV1: false,
    );
    expect(await unsupported.isConfigured(), isFalse);
    await expectLater(
      unsupported.read(),
      throwsA(
        isA<RecoveryDeviceSecretException>().having(
          (error) => error.reason,
          'reason',
          RecoveryDeviceSecretFailureReason.unsupported,
        ),
      ),
    );
  });

  test('Android 恢复设备秘密使用完全隔离的Keystore强认证边界', () async {
    final activity = await File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/MainActivity.kt',
    ).readAsString();
    final dartSource = await File(
      'lib/core/security/recovery_device_secret.dart',
    ).readAsString();

    expect(
      activity,
      contains('account_subscription_manager/recovery_device_secret_v1'),
    );
    expect(activity, contains('asm_recovery_device_secret_v1'));
    expect(
      activity,
      contains(
        'com.localaccount.account_subscription_manager.recovery_device_secret_v1',
      ),
    );
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
    expect(activity, contains('"vaultInstanceId"'));
    expect(activity, contains('"slotId"'));
    expect(activity, contains('"deviceBindingId"'));
    expect(activity, contains('decodedSecret.size == 32'));
    expect(activity, isNot(contains('AUTH_DEVICE_CREDENTIAL')));
    expect(activity, isNot(contains('DEVICE_CREDENTIAL')));
    expect(activity, isNot(contains('setUnlockedDeviceRequired')));
    expect(dartSource, isNot(contains('local_auth')));
    expect(dartSource, isNot(contains('LocalAuthentication')));

    final markerMethod = activity.substring(
      activity.indexOf('private fun isRecoveryDeviceSecretV1Configured'),
      activity.indexOf('private fun writeRecoveryDeviceSecretV1'),
    );
    expect(markerMethod, contains('RECOVERY_DEVICE_SECRET_PREF_CONFIGURED'));
    expect(markerMethod, isNot(contains('KeyStore')));
    expect(markerMethod, isNot(contains('Cipher')));
    expect(markerMethod, isNot(contains('authenticate')));

    final writeMethod = activity.substring(
      activity.indexOf('private fun writeRecoveryDeviceSecretV1'),
      activity.indexOf('private fun readRecoveryDeviceSecretV1'),
    );
    final readMethod = activity.substring(
      activity.indexOf('private fun readRecoveryDeviceSecretV1'),
      activity.indexOf('private fun deleteRecoveryDeviceSecretV1'),
    );
    expect(
      writeMethod,
      contains('authenticateRecoveryDeviceSecretWithCipher('),
    );
    expect(readMethod, contains('authenticateRecoveryDeviceSecretWithCipher('));
    expect(writeMethod, contains('var writeCommitted = false'));
    expect(writeMethod, contains('clearRecoveryDeviceSecretV1State()'));
    expect(
      writeMethod,
      contains('val replacingConfiguredSecret ='),
      reason: '轮换失败时必须保留旧密文和旧绑定',
    );

    final deleteMethod = activity.substring(
      activity.indexOf('private fun deleteRecoveryDeviceSecretV1'),
      activity.indexOf('private fun clearRecoveryDeviceSecretV1State'),
    );
    expect(
      deleteMethod,
      contains('authenticateRecoveryDeviceSecretWithCipher('),
      reason: '防止未认证本地调用对恢复因子造成拒绝服务',
    );

    final keyMethod = activity.substring(
      activity.indexOf('private fun createFreshRecoveryDeviceSecretV1Key'),
      activity.indexOf('private fun getExistingRecoveryDeviceSecretV1Key'),
    );
    expect(keyMethod, contains('RECOVERY_DEVICE_SECRET_KEY_ALIAS'));
    expect(keyMethod, isNot(contains('QUICK_UNLOCK_KEY_ALIAS')));
    expect(keyMethod, contains('setUserAuthenticationParameters('));
    expect(keyMethod, contains('0,'), reason: '每次使用都需要新鲜认证');

    expect(activity, contains('activeRecoveryDeviceSecretOperationId'));
    expect(activity, contains('activeRecoveryDeviceSecretPrompt'));
    expect(activity, contains('cancelActiveRecoveryDeviceSecretForLifecycle'));
    expect(
      activity,
      contains(
        'cancelActiveRecoveryDeviceSecretForLifecycle("activity_stopped")',
      ),
    );
    expect(
      activity,
      contains(
        'cancelActiveRecoveryDeviceSecretForLifecycle("activity_destroyed")',
      ),
    );
  });

  test('Android 解锁时钟通道只返回启动计数与单调时钟', () async {
    final activity = await File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/MainActivity.kt',
    ).readAsString();

    expect(activity, contains('account_subscription_manager/unlock_clock_v1'));
    final clockMethod = activity.substring(
      activity.indexOf('private fun configureUnlockClockChannel'),
      activity.indexOf(
        '/** Reads only a non-sensitive marker. This method never touches KeyStore. */',
        activity.indexOf('private fun configureUnlockClockChannel'),
      ),
    );
    expect(clockMethod, contains('"read" -> result.success('));
    expect(clockMethod, contains('Settings.Global.BOOT_COUNT'));
    expect(clockMethod, contains('SystemClock.elapsedRealtime()'));
    expect(clockMethod, contains('"bootCount"'));
    expect(clockMethod, contains('"elapsedRealtimeMilliseconds"'));
    expect(clockMethod, isNot(contains('"write"')));
    expect(clockMethod, isNot(contains('System.currentTimeMillis')));
  });
}

final class _RecordingRecoveryDeviceSecretBridge
    implements AndroidRecoveryDeviceSecretBridge {
  bool configured = false;
  bool failReads = false;
  Object? readError;
  Object? writeError;
  String? encodedPayload;
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
  Future<void> write(String encodedPayload) async {
    writeCalls += 1;
    final error = writeError;
    if (error != null) throw error;
    configured = true;
    this.encodedPayload = encodedPayload;
  }

  @override
  Future<String?> read() async {
    readCalls += 1;
    final error = readError;
    if (error != null) throw error;
    if (failReads) {
      throw StateError('simulated inaccessible recovery device secret');
    }
    return encodedPayload;
  }

  @override
  Future<void> delete() async {
    deleteCalls += 1;
    configured = false;
    encodedPayload = null;
  }
}
