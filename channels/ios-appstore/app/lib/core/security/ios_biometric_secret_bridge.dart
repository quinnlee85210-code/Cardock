import 'package:flutter/services.dart';

/// Separate Keychain items share one native authentication implementation.
final class IOSBiometricSecretBridge {
  const IOSBiometricSecretBridge(this.kind);

  static const channel = MethodChannel('cardock/ios_biometric_secret_v1');
  final String kind;

  Future<String?> availability() =>
      channel.invokeMethod<String>('availability', {'kind': kind});

  Future<bool> isConfigured() async =>
      await channel.invokeMethod<bool>('isConfigured', {'kind': kind}) ?? false;

  Future<void> write(String payload) =>
      channel.invokeMethod<void>('write', {'kind': kind, 'payload': payload});

  Future<String?> read() =>
      channel.invokeMethod<String>('read', {'kind': kind});

  Future<void> delete() => channel.invokeMethod<void>('delete', {'kind': kind});
}
