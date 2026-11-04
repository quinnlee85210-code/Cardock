import 'dart:convert';

import 'package:account_subscription_manager/core/security/biometric_unlock.dart';
import 'package:account_subscription_manager/core/security/ios_biometric_secret_bridge.dart';
import 'package:account_subscription_manager/core/security/recovery_device_secret.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_address_provider_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = IOSBiometricSecretBridge.channel;
  const network = MethodChannel('cardock/ios_local_network_v1');
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(network, null);
  });

  test(
    'recovery enrollment and read do not consult biometric availability',
    () async {
      final stored = <String, String>{};
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        final args = Map<String, Object?>.from(call.arguments as Map);
        final kind = args['kind']! as String;
        calls.add('$kind:${call.method}');
        if (call.method == 'availability') return 'not_enrolled';
        if (call.method == 'write') {
          expect(kind, 'recovery');
          stored[kind] = args['payload']! as String;
          return null;
        }
        if (call.method == 'read') return stored[kind];
        return stored.containsKey(kind);
      });
      final quick = BiometricQuickUnlockSecretStore(
        useAndroidV2: false,
        useIOSBridge: true,
      );
      expect(await quick.availability(), BiometricAvailability.notEnrolled);
      calls.clear();
      final recovery = BiometricRecoveryDeviceSecretStore(
        useAndroidV1: false,
        useIOSBridge: true,
      );
      final material = RecoveryDeviceSecretMaterial(
        vaultInstanceId: 'test-vault',
        slotId: 'test-slot',
        deviceBindingId: 'test-binding',
        deviceSecret: List.filled(32, 7),
      );
      addTearDown(material.destroy);
      await recovery.write(material);
      final restored = (await recovery.read())!;
      addTearDown(restored.destroy);
      expect(restored.deviceSecret, material.deviceSecret);
      expect(restored.deviceBindingId, material.deviceBindingId);
      expect(calls, ['recovery:write', 'recovery:read']);
    },
  );

  for (final entry in {
    'passcode_not_set': RecoveryDeviceSecretFailureReason.devicePasscodeNotSet,
    'device_authentication_unavailable':
        RecoveryDeviceSecretFailureReason.deviceAuthenticationUnavailable,
    'legacy_recovery_unavailable':
        RecoveryDeviceSecretFailureReason.legacyRecoveryUnavailable,
  }.entries) {
    test(
      'iOS recovery ${entry.key} preserves configuration and maps the cause',
      () async {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: entry.key),
        );
        final recovery = BiometricRecoveryDeviceSecretStore(
          useAndroidV1: false,
          useIOSBridge: true,
        );
        await expectLater(
          recovery.read(),
          throwsA(
            isA<RecoveryDeviceSecretException>()
                .having((error) => error.reason, 'reason', entry.value)
                .having(
                  (error) => error.reason.invalidatesConfiguration,
                  'preserve configuration',
                  false,
                ),
          ),
        );
      },
    );
  }

  test(
    'iOS quick unlock and recovery use separate native kinds and payloads',
    () async {
      final stored = <String, String>{};
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        final args = Map<String, Object?>.from(call.arguments as Map);
        final kind = args['kind']! as String;
        calls.add('$kind:${call.method}');
        return switch (call.method) {
          'availability' => 'available',
          'isConfigured' => stored.containsKey(kind),
          'write' => () {
            stored[kind] = args['payload']! as String;
            return null;
          }(),
          'read' => stored[kind],
          'delete' => () {
            stored.remove(kind);
            return null;
          }(),
          _ => throw StateError('unexpected method'),
        };
      });
      final quick = BiometricQuickUnlockSecretStore(
        useAndroidV2: false,
        useIOSBridge: true,
      );
      final recovery = BiometricRecoveryDeviceSecretStore(
        useAndroidV1: false,
        useIOSBridge: true,
      );
      expect(await quick.availability(), BiometricAvailability.available);
      expect(await quick.containsSecret(), false);
      expect(await recovery.isConfigured(), false);
      expect(calls, [
        'quickUnlock:availability',
        'quickUnlock:isConfigured',
        'recovery:isConfigured',
      ]);
      final secret = QuickUnlockSecret(
        vaultId: 'fictional-vault',
        dataKey: List.filled(32, 1),
      );
      final material = RecoveryDeviceSecretMaterial(
        vaultInstanceId: 'fictional-vault',
        slotId: 'slot',
        deviceBindingId: 'binding',
        deviceSecret: List.filled(32, 2),
      );
      addTearDown(secret.destroy);
      addTearDown(material.destroy);
      await quick.writeSecret(secret);
      await recovery.write(material);
      final readQuick = (await quick.readSecret())!;
      final readRecovery = (await recovery.read())!;
      addTearDown(readQuick.destroy);
      addTearDown(readRecovery.destroy);
      expect(readQuick.dataKey, secret.dataKey);
      expect(readRecovery.deviceSecret, material.deviceSecret);
      expect(jsonDecode(stored['recovery']!).keys, isNot(contains('dataKey')));
      await quick.deleteSecret();
      expect(await quick.containsSecret(), false);
      expect(await recovery.isConfigured(), true);
      await recovery.delete();
      expect(stored, isEmpty);
    },
  );

  for (final code in [
    'user_canceled',
    'biometric_lockout',
    'lifecycle_canceled',
    'key_missing',
    'storage_error',
  ]) {
    test(
      'iOS $code does not return a secret or fall back to unprotected storage',
      () async {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: code),
        );
        final quick = BiometricQuickUnlockSecretStore(
          useAndroidV2: false,
          useIOSBridge: true,
        );
        final recovery = BiometricRecoveryDeviceSecretStore(
          useAndroidV1: false,
          useIOSBridge: true,
        );
        await expectLater(
          quick.readSecret(),
          throwsA(
            isA<QuickUnlockException>().having(
              (e) => e.platformCode,
              'code',
              code,
            ),
          ),
        );
        await expectLater(
          recovery.read(),
          throwsA(
            isA<RecoveryDeviceSecretException>().having(
              (e) => e.platformCode,
              'code',
              code,
            ),
          ),
        );
        expect(await quick.containsSecret(), false);
        expect(await recovery.isConfigured(), false);
      },
    );
  }
  test('cross-kind and malformed payloads fail closed', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => jsonEncode({
        'version': 2,
        'vaultId': 'fictional',
        'dataKey': base64Encode(List.filled(32, 1)),
      }),
    );
    await expectLater(
      BiometricRecoveryDeviceSecretStore(
        useAndroidV1: false,
        useIOSBridge: true,
      ).read(),
      throwsA(isA<RecoveryDeviceSecretException>()),
    );
    messenger.setMockMethodCallHandler(channel, (_) async => '{broken');
    await expectLater(
      BiometricQuickUnlockSecretStore(
        useAndroidV2: false,
        useIOSBridge: true,
      ).readSecret(),
      throwsA(isA<QuickUnlockException>()),
    );
  });
  test(
    'iOS uses native Wi-Fi classification and rejects invalid/nonprivate addresses',
    () async {
      messenger.setMockMethodCallHandler(network, (call) async {
        expect(call.method, 'listAddresses');
        return [
          {'address': '192.168.1.12', 'interfaceName': 'en0'},
          {'address': '192.168.1.12', 'interfaceName': 'en0'},
          {'address': '8.8.8.8', 'interfaceName': 'en0'},
          {'address': '127.0.0.1', 'interfaceName': 'lo0'},
          {'address': '::1', 'interfaceName': 'en0'},
          {'address': 'invalid', 'interfaceName': 'en0'},
        ];
      });
      const provider = IoTemporaryWebAddressProvider(isIOS: true);
      final values = await provider.listPrivateIpv4Addresses();
      expect(values.map((a) => a.address), ['192.168.1.12']);
      expect(await provider.isStillAvailable('192.168.1.12'), true);
      expect(await provider.isStillAvailable('10.0.0.1'), false);
      expect(
        TemporaryWebAddressPolicy.isTrustedWirelessInterfaceName('en0'),
        false,
      );
    },
  );
}
