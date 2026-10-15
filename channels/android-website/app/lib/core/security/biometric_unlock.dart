import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'vault_contract.dart';

enum BiometricAvailability { available, unavailable, notEnrolled, error }

abstract interface class QuickUnlockSecretStore {
  Future<BiometricAvailability> availability();

  Future<bool> containsSecret();

  Future<void> writeSecret(QuickUnlockSecret secret);

  Future<QuickUnlockSecret?> readSecret();

  Future<void> deleteSecret();
}

final class QuickUnlockSecret {
  QuickUnlockSecret({required this.vaultId, required List<int> dataKey})
    : dataKey = Uint8List.fromList(dataKey);

  final String vaultId;
  final Uint8List dataKey;

  void destroy() => dataKey.fillRange(0, dataKey.length, 0);
}

/// Android v2 bridge. The native side owns the Android Keystore key and binds
/// every read and write to a fresh BiometricPrompt CryptoObject operation.
abstract interface class AndroidQuickUnlockV2Bridge {
  Future<bool> isConfigured();

  Future<void> write(String encodedSecret);

  Future<String?> read();

  Future<void> delete();
}

final class MethodChannelAndroidQuickUnlockV2Bridge
    implements AndroidQuickUnlockV2Bridge {
  const MethodChannelAndroidQuickUnlockV2Bridge();

  static const MethodChannel _channel = MethodChannel(
    'account_subscription_manager/quick_unlock_v2',
  );

  @override
  Future<bool> isConfigured() async =>
      await _channel.invokeMethod<bool>('isConfigured') ?? false;

  @override
  Future<void> write(String encodedSecret) => _channel.invokeMethod<void>(
    'write',
    <String, Object?>{'secret': encodedSecret},
  );

  @override
  Future<String?> read() => _channel.invokeMethod<String>('read');

  @override
  Future<void> delete() => _channel.invokeMethod<void>('delete');
}

final class BiometricQuickUnlockSecretStore implements QuickUnlockSecretStore {
  BiometricQuickUnlockSecretStore({
    LocalAuthentication? localAuthentication,
    FlutterSecureStorage? secureStorage,
    AndroidQuickUnlockV2Bridge? androidBridge,
    bool? useAndroidV2,
  }) : _localAuthentication = localAuthentication ?? LocalAuthentication(),
       _secureStorage = secureStorage ?? _defaultSecureStorage,
       _androidBridge =
           androidBridge ?? const MethodChannelAndroidQuickUnlockV2Bridge(),
       _useAndroidV2 = useAndroidV2 ?? Platform.isAndroid;

  // The legacy v1 Android namespace is deliberately not referenced here.
  // Existing v1 data never counts as a configured v2 quick-unlock binding.
  static const _iosSecretKey = 'vault_data_key_v2';
  static const _payloadVersion = 2;
  static const _defaultSecureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'asm_quick_unlock_non_android_v2',
    ),
    iOptions: IOSOptions(
      accountName: 'asm_biometric_quick_unlock_v2',
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
      accessControlFlags: <AccessControlFlag>[
        AccessControlFlag.biometryCurrentSet,
      ],
      useSecureEnclave: true,
    ),
  );

  final LocalAuthentication _localAuthentication;
  final FlutterSecureStorage _secureStorage;
  final AndroidQuickUnlockV2Bridge _androidBridge;
  final bool _useAndroidV2;

  @override
  Future<BiometricAvailability> availability() async {
    try {
      if (!await _localAuthentication.isDeviceSupported() ||
          !await _localAuthentication.canCheckBiometrics) {
        return BiometricAvailability.unavailable;
      }
      final enrolled = await _localAuthentication.getAvailableBiometrics();
      return enrolled.isEmpty
          ? BiometricAvailability.notEnrolled
          : BiometricAvailability.available;
    } on Object {
      return BiometricAvailability.error;
    }
  }

  @override
  Future<bool> containsSecret() async {
    try {
      if (_useAndroidV2) {
        // Native isConfigured reads only a non-sensitive marker. It must never
        // initialize a Cipher, access the Keystore, or show authentication UI.
        return await _androidBridge.isConfigured();
      }
      return await _secureStorage.containsKey(key: _iosSecretKey);
    } on Object {
      return false;
    }
  }

  @override
  Future<void> writeSecret(QuickUnlockSecret secret) async {
    if (secret.dataKey.length != 32 || secret.vaultId.isEmpty) {
      throw StateError('invalid quick unlock secret');
    }
    final encoded = jsonEncode(<String, Object?>{
      'version': _payloadVersion,
      'vaultId': secret.vaultId,
      'dataKey': base64Encode(secret.dataKey),
    });
    if (_useAndroidV2) {
      try {
        await _androidBridge.write(encoded);
      } on PlatformException catch (error) {
        throw _quickUnlockException(error);
      }
      return;
    }
    try {
      await _secureStorage.write(key: _iosSecretKey, value: encoded);
    } on PlatformException catch (error) {
      throw _quickUnlockException(error);
    }
  }

  @override
  Future<QuickUnlockSecret?> readSecret() async {
    final String? encoded;
    try {
      encoded = _useAndroidV2
          ? await _androidBridge.read()
          : await _secureStorage.read(key: _iosSecretKey);
    } on PlatformException catch (error) {
      throw _quickUnlockException(error);
    }
    if (encoded == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<Object?, Object?> ||
          decoded['version'] != _payloadVersion ||
          decoded['vaultId'] is! String ||
          decoded['dataKey'] is! String) {
        throw const FormatException();
      }
      final vaultId = decoded['vaultId']! as String;
      final dataKey = base64Decode(decoded['dataKey']! as String);
      if (vaultId.isEmpty || dataKey.length != 32) {
        dataKey.fillRange(0, dataKey.length, 0);
        throw const FormatException();
      }
      return QuickUnlockSecret(vaultId: vaultId, dataKey: dataKey);
    } on Object {
      throw const QuickUnlockException(
        QuickUnlockFailureReason.corruptedSecret,
        platformCode: 'corrupted_secret',
      );
    }
  }

  @override
  Future<void> deleteSecret() async {
    if (_useAndroidV2) {
      // Native deletion removes the v2 marker, ciphertext and Keystore alias
      // directly. It deliberately does not require the old biometric key.
      try {
        await _androidBridge.delete();
      } on PlatformException catch (error) {
        throw _quickUnlockException(error);
      }
      return;
    }
    try {
      await _secureStorage.delete(key: _iosSecretKey);
    } on PlatformException catch (error) {
      throw _quickUnlockException(error);
    }
  }
}

QuickUnlockException _quickUnlockException(PlatformException error) {
  final details = error.details;
  final diagnosticDetails = details is Map<Object?, Object?> ? details : null;
  final rawDiagnosticStage = diagnosticDetails?['stage'];
  final rawDiagnosticType = diagnosticDetails?['exceptionType'];
  return QuickUnlockException(
    switch (error.code) {
      'user_canceled' => QuickUnlockFailureReason.userCanceled,
      'timeout' || 'prompt_timeout' => QuickUnlockFailureReason.timeout,
      'temporary_lockout' => QuickUnlockFailureReason.temporaryLockout,
      'biometric_lockout' => QuickUnlockFailureReason.biometricLockout,
      'hardware_unavailable' => QuickUnlockFailureReason.hardwareUnavailable,
      'unavailable' ||
      'biometric_unavailable' ||
      'biometric_unable_to_process' ||
      'biometric_no_space' ||
      'biometric_vendor_error' => QuickUnlockFailureReason.unavailable,
      'not_enrolled' => QuickUnlockFailureReason.notEnrolled,
      'biometric_security_update_required' =>
        QuickUnlockFailureReason.securityUpdateRequired,
      'biometric_unsupported' => QuickUnlockFailureReason.unsupported,
      'biometric_status_unknown' => QuickUnlockFailureReason.statusUnknown,
      'system_canceled' => QuickUnlockFailureReason.systemCanceled,
      'lifecycle_canceled' => QuickUnlockFailureReason.lifecycleCanceled,
      'ui_unavailable' => QuickUnlockFailureReason.uiUnavailable,
      'activity_not_resumed' => QuickUnlockFailureReason.activityUnavailable,
      'prompt_start_failed' => QuickUnlockFailureReason.promptStartFailed,
      'auth_in_progress' => QuickUnlockFailureReason.authInProgress,
      'key_cleanup_failed' ||
      'key_generation_failed' ||
      'key_load_failed' ||
      'cipher_init_failed' => QuickUnlockFailureReason.keySetupFailed,
      'key_invalidated' => QuickUnlockFailureReason.keyInvalidated,
      'key_missing' => QuickUnlockFailureReason.keyMissing,
      'corrupted_secret' ||
      'invalid_secret' => QuickUnlockFailureReason.corruptedSecret,
      'not_configured' => QuickUnlockFailureReason.notConfigured,
      'storage_error' => QuickUnlockFailureReason.storageError,
      'crypto_error' => QuickUnlockFailureReason.cryptoError,
      _ => QuickUnlockFailureReason.unknown,
    },
    platformCode: error.code,
    diagnosticStage: rawDiagnosticStage is String ? rawDiagnosticStage : null,
    diagnosticType: rawDiagnosticType is String ? rawDiagnosticType : null,
  );
}
