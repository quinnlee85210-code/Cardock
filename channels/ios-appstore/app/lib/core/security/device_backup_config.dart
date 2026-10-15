import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'vault_contract.dart';

/// Device-only, authenticated sidecar. Never part of VaultSnapshot or backups.
/// The unique vault DEK binds the ciphertext to its vault; fixed purpose AAD
/// remains stable when credential-envelope identifiers change during rotation.
abstract interface class DeviceBackupConfigSession implements VaultSession {
  Future<Map<String, Object?>?> readDeviceBackupConfig();
  Future<void> writeDeviceBackupConfig(Map<String, Object?>? value);
}

final class DeviceBackupConfigCodec {
  static const maximumBytes = 256 * 1024;
  final _cipher = AesGcm.with256bits();

  Future<Uint8List> encode(
    Map<String, Object?>? value,
    SecretKey key,
    String binding,
  ) async {
    final clear = Uint8List.fromList(utf8.encode(jsonEncode(value)));
    try {
      if (clear.length > maximumBytes ~/ 2) {
        throw const VaultFormatException();
      }
      final box = await _cipher.encrypt(
        clear,
        secretKey: key,
        nonce: _cipher.newNonce(),
        aad: utf8.encode('cardock-device-backup-v1'),
      );
      return Uint8List.fromList(
        utf8.encode(
          jsonEncode({'version': 1, 'box': base64Encode(box.concatenation())}),
        ),
      );
    } finally {
      clear.fillRange(0, clear.length, 0);
    }
  }

  Future<Map<String, Object?>?> decode(
    List<int> bytes,
    SecretKey key,
    String binding,
  ) async {
    if (bytes.length > maximumBytes) throw const VaultFormatException();
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map || value['version'] != 1 || value['box'] is! String) {
      throw const VaultFormatException();
    }
    final box = base64Decode(value['box'] as String);
    if (box.length < 28) throw const VaultFormatException();
    final clear = await _cipher.decrypt(
      SecretBox.fromConcatenation(box, nonceLength: 12, macLength: 16),
      secretKey: key,
      aad: utf8.encode('cardock-device-backup-v1'),
    );
    try {
      final decoded = jsonDecode(utf8.decode(clear));
      if (decoded == null) return null;
      if (decoded is! Map<String, dynamic>) throw const VaultFormatException();
      return Map<String, Object?>.from(decoded);
    } finally {
      clear.fillRange(0, clear.length, 0);
    }
  }
}
