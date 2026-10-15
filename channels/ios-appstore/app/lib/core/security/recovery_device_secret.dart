import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'ios_biometric_secret_bridge.dart';

enum RecoveryDeviceSecretFailureReason {
  userCanceled,
  timeout,
  temporaryLockout,
  biometricLockout,
  hardwareUnavailable,
  notEnrolled,
  securityUpdateRequired,
  unsupported,
  statusUnknown,
  lifecycleCanceled,
  activityUnavailable,
  promptStartFailed,
  authInProgress,
  keySetupFailed,
  keyInvalidated,
  keyMissing,
  corruptedSecret,
  notConfigured,
  storageError,
  cryptoError,
  unknown,
}

extension RecoveryDeviceSecretFailureReasonX
    on RecoveryDeviceSecretFailureReason {
  bool get invalidatesConfiguration => switch (this) {
    RecoveryDeviceSecretFailureReason.keyInvalidated ||
    RecoveryDeviceSecretFailureReason.keyMissing ||
    RecoveryDeviceSecretFailureReason.corruptedSecret ||
    RecoveryDeviceSecretFailureReason.notConfigured => true,
    _ => false,
  };
}

final class RecoveryDeviceSecretException implements Exception {
  const RecoveryDeviceSecretException(
    this.reason, {
    this.platformCode,
    this.diagnosticStage,
    this.diagnosticType,
  });

  final RecoveryDeviceSecretFailureReason reason;
  final String? platformCode;
  final String? diagnosticStage;
  final String? diagnosticType;
}

final class RecoveryDeviceSecretMaterial {
  RecoveryDeviceSecretMaterial({
    required this.vaultInstanceId,
    required this.slotId,
    required this.deviceBindingId,
    required List<int> deviceSecret,
  }) : deviceSecret = Uint8List.fromList(deviceSecret) {
    _validateMetadata('vaultInstanceId', vaultInstanceId);
    _validateMetadata('slotId', slotId);
    _validateMetadata('deviceBindingId', deviceBindingId);
    if (this.deviceSecret.length != 32) {
      this.deviceSecret.fillRange(0, this.deviceSecret.length, 0);
      throw ArgumentError.value(
        deviceSecret.length,
        'deviceSecret',
        'must contain exactly 32 bytes',
      );
    }
  }

  static const int _maximumMetadataBytes = 512;

  final String vaultInstanceId;
  final String slotId;
  final String deviceBindingId;
  final Uint8List deviceSecret;

  void destroy() => deviceSecret.fillRange(0, deviceSecret.length, 0);

  static void _validateMetadata(String name, String value) {
    final encodedLength = utf8.encode(value).length;
    if (value.isEmpty || encodedLength > _maximumMetadataBytes) {
      throw ArgumentError.value(value, name, 'invalid recovery metadata');
    }
  }
}

abstract interface class AndroidRecoveryDeviceSecretBridge {
  Future<bool> isConfigured();

  Future<void> write(String encodedPayload);

  Future<String?> read();

  Future<void> delete();
}

final class MethodChannelAndroidRecoveryDeviceSecretBridge
    implements AndroidRecoveryDeviceSecretBridge {
  const MethodChannelAndroidRecoveryDeviceSecretBridge();

  static const MethodChannel _channel = MethodChannel(
    'account_subscription_manager/recovery_device_secret_v1',
  );

  @override
  Future<bool> isConfigured() async =>
      await _channel.invokeMethod<bool>('isConfigured') ?? false;

  @override
  Future<void> write(String encodedPayload) => _channel.invokeMethod<void>(
    'write',
    <String, Object?>{'payload': encodedPayload},
  );

  @override
  Future<String?> read() => _channel.invokeMethod<String>('read');

  @override
  Future<void> delete() => _channel.invokeMethod<void>('delete');
}

abstract interface class RecoveryDeviceSecretStore {
  Future<bool> isConfigured();

  Future<void> write(RecoveryDeviceSecretMaterial material);

  Future<RecoveryDeviceSecretMaterial?> read();

  Future<void> delete();
}

/// Device-local outer factor for vault recovery.
///
/// Android keeps this opaque payload behind a dedicated Android Keystore key.
/// Every write and read is authorized by a fresh BIOMETRIC_STRONG CryptoObject
/// operation. The payload deliberately contains only a random device secret
/// and non-secret binding metadata; it never contains vault encryption keys or
/// human recovery answers.
final class BiometricRecoveryDeviceSecretStore
    implements RecoveryDeviceSecretStore {
  BiometricRecoveryDeviceSecretStore({
    AndroidRecoveryDeviceSecretBridge? androidBridge,
    bool? useAndroidV1,
    bool? useIOSBridge,
  }) : _androidBridge =
           androidBridge ??
           const MethodChannelAndroidRecoveryDeviceSecretBridge(),
       _useAndroidV1 = useAndroidV1 ?? Platform.isAndroid,
       _useIOSBridge = useIOSBridge ?? Platform.isIOS;

  static const int _payloadVersion = 1;
  static const int _maximumEncodedPayloadBytes = 4096;
  static const Set<String> _payloadKeys = <String>{
    'version',
    'vaultInstanceId',
    'slotId',
    'deviceBindingId',
    'deviceSecret',
  };

  final AndroidRecoveryDeviceSecretBridge _androidBridge;
  final bool _useAndroidV1;
  final bool _useIOSBridge;
  static const _iosBridge = IOSBiometricSecretBridge('recovery');

  @override
  Future<bool> isConfigured() async {
    if (!_useAndroidV1 && !_useIOSBridge) return false;
    try {
      return _useIOSBridge
          ? await _iosBridge.isConfigured()
          : await _androidBridge.isConfigured();
    } on Object {
      return false;
    }
  }

  @override
  Future<void> write(RecoveryDeviceSecretMaterial material) async {
    _requireSupportedPlatform();
    final encoded = jsonEncode(<String, Object?>{
      'version': _payloadVersion,
      'vaultInstanceId': material.vaultInstanceId,
      'slotId': material.slotId,
      'deviceBindingId': material.deviceBindingId,
      'deviceSecret': base64Encode(material.deviceSecret),
    });
    if (utf8.encode(encoded).length > _maximumEncodedPayloadBytes) {
      throw ArgumentError('recovery device payload is too large');
    }
    try {
      if (_useIOSBridge) {
        await _iosBridge.write(encoded);
      } else {
        await _androidBridge.write(encoded);
      }
    } on PlatformException catch (error) {
      throw _recoveryDeviceSecretException(error);
    }
  }

  @override
  Future<RecoveryDeviceSecretMaterial?> read() async {
    _requireSupportedPlatform();
    final String? encoded;
    try {
      encoded = _useIOSBridge
          ? await _iosBridge.read()
          : await _androidBridge.read();
    } on PlatformException catch (error) {
      throw _recoveryDeviceSecretException(error);
    }
    if (encoded == null) return null;
    if (utf8.encode(encoded).length > _maximumEncodedPayloadBytes) {
      throw const RecoveryDeviceSecretException(
        RecoveryDeviceSecretFailureReason.corruptedSecret,
        platformCode: 'corrupted_secret',
      );
    }

    Uint8List? decodedSecret;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<Object?, Object?> ||
          decoded.length != _payloadKeys.length ||
          !decoded.keys.every(_payloadKeys.contains) ||
          decoded['version'] != _payloadVersion ||
          decoded['vaultInstanceId'] is! String ||
          decoded['slotId'] is! String ||
          decoded['deviceBindingId'] is! String ||
          decoded['deviceSecret'] is! String) {
        throw const FormatException();
      }
      decodedSecret = base64Decode(decoded['deviceSecret']! as String);
      if (decodedSecret.length != 32) {
        throw const FormatException();
      }
      return RecoveryDeviceSecretMaterial(
        vaultInstanceId: decoded['vaultInstanceId']! as String,
        slotId: decoded['slotId']! as String,
        deviceBindingId: decoded['deviceBindingId']! as String,
        deviceSecret: decodedSecret,
      );
    } on RecoveryDeviceSecretException {
      rethrow;
    } on Object {
      throw const RecoveryDeviceSecretException(
        RecoveryDeviceSecretFailureReason.corruptedSecret,
        platformCode: 'corrupted_secret',
      );
    } finally {
      decodedSecret?.fillRange(0, decodedSecret.length, 0);
    }
  }

  @override
  Future<void> delete() async {
    _requireSupportedPlatform();
    try {
      if (_useIOSBridge) {
        await _iosBridge.delete();
      } else {
        await _androidBridge.delete();
      }
    } on PlatformException catch (error) {
      throw _recoveryDeviceSecretException(error);
    }
  }

  void _requireSupportedPlatform() {
    if (_useAndroidV1 || _useIOSBridge) return;
    throw const RecoveryDeviceSecretException(
      RecoveryDeviceSecretFailureReason.unsupported,
      platformCode: 'unsupported_platform',
    );
  }
}

RecoveryDeviceSecretException _recoveryDeviceSecretException(
  PlatformException error,
) {
  final details = error.details;
  final diagnosticDetails = details is Map<Object?, Object?> ? details : null;
  final rawDiagnosticStage = diagnosticDetails?['stage'];
  final rawDiagnosticType = diagnosticDetails?['exceptionType'];
  return RecoveryDeviceSecretException(
    switch (error.code) {
      'user_canceled' => RecoveryDeviceSecretFailureReason.userCanceled,
      'timeout' ||
      'prompt_timeout' => RecoveryDeviceSecretFailureReason.timeout,
      'temporary_lockout' => RecoveryDeviceSecretFailureReason.temporaryLockout,
      'biometric_lockout' => RecoveryDeviceSecretFailureReason.biometricLockout,
      'hardware_unavailable' =>
        RecoveryDeviceSecretFailureReason.hardwareUnavailable,
      'unavailable' ||
      'biometric_unavailable' ||
      'biometric_unable_to_process' ||
      'biometric_no_space' ||
      'biometric_vendor_error' =>
        RecoveryDeviceSecretFailureReason.hardwareUnavailable,
      'not_enrolled' => RecoveryDeviceSecretFailureReason.notEnrolled,
      'biometric_security_update_required' =>
        RecoveryDeviceSecretFailureReason.securityUpdateRequired,
      'biometric_unsupported' => RecoveryDeviceSecretFailureReason.unsupported,
      'biometric_status_unknown' =>
        RecoveryDeviceSecretFailureReason.statusUnknown,
      'system_canceled' || 'lifecycle_canceled' =>
        RecoveryDeviceSecretFailureReason.lifecycleCanceled,
      'ui_unavailable' => RecoveryDeviceSecretFailureReason.activityUnavailable,
      'activity_not_resumed' =>
        RecoveryDeviceSecretFailureReason.activityUnavailable,
      'prompt_start_failed' =>
        RecoveryDeviceSecretFailureReason.promptStartFailed,
      'auth_in_progress' => RecoveryDeviceSecretFailureReason.authInProgress,
      'key_cleanup_failed' ||
      'key_generation_failed' ||
      'key_load_failed' ||
      'cipher_init_failed' => RecoveryDeviceSecretFailureReason.keySetupFailed,
      'key_invalidated' => RecoveryDeviceSecretFailureReason.keyInvalidated,
      'key_missing' => RecoveryDeviceSecretFailureReason.keyMissing,
      'corrupted_secret' ||
      'invalid_secret' => RecoveryDeviceSecretFailureReason.corruptedSecret,
      'not_configured' => RecoveryDeviceSecretFailureReason.notConfigured,
      'storage_error' => RecoveryDeviceSecretFailureReason.storageError,
      'crypto_error' => RecoveryDeviceSecretFailureReason.cryptoError,
      _ => RecoveryDeviceSecretFailureReason.unknown,
    },
    platformCode: error.code,
    diagnosticStage: rawDiagnosticStage is String ? rawDiagnosticStage : null,
    diagnosticType: rawDiagnosticType is String ? rawDiagnosticType : null,
  );
}
