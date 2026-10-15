import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'vault_contract.dart';

/// An unfinished form is separate from business records and portable backups.
/// Only a full session for the originating vault may read or replace it.
abstract interface class EditorDraftVaultSession implements VaultSession {
  Future<Map<String, Object?>?> readEditorDraft();
  Future<void> writeEditorDraft(Map<String, Object?>? draft);
}

final class UnsupportedEditorDraftVersion implements Exception {
  const UnsupportedEditorDraftVersion();
}

final class EditorDraftCodec {
  static const maximumBytes = 256 * 1024;
  final _cipher = AesGcm.with256bits();

  Future<Uint8List> encode({
    required Map<String, Object?>? draft,
    required SecretKey key,
    required String binding,
    required int generation,
  }) async {
    final clear = Uint8List.fromList(
      utf8.encode(jsonEncode({'generation': generation, 'draft': draft})),
    );
    try {
      if (clear.length > maximumBytes ~/ 2) {
        throw const VaultFormatException();
      }
      final box = await _cipher.encrypt(
        clear,
        secretKey: key,
        nonce: _cipher.newNonce(),
        aad: utf8.encode('cardock-editor-draft-v1:$binding'),
      );
      return Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'generation': generation,
            'nonce': base64Encode(box.nonce),
            'cipherText': base64Encode(box.cipherText),
            'mac': base64Encode(box.mac.bytes),
          }),
        ),
      );
    } finally {
      clear.fillRange(0, clear.length, 0);
    }
  }

  Future<Map<String, Object?>?> decode({
    required List<int> bytes,
    required SecretKey key,
    required String binding,
    required int generation,
  }) async {
    if (bytes.length > maximumBytes) throw const VaultFormatException();
    final envelope = jsonDecode(utf8.decode(bytes));
    if (envelope is! Map<String, dynamic> || envelope['version'] is! int) {
      throw const VaultFormatException();
    }
    if (envelope['version'] != 1) throw const UnsupportedEditorDraftVersion();
    if (envelope['generation'] is! int) throw const VaultFormatException();
    // A committed business change (including DEK rotation) invalidates this
    // form. The generation is also authenticated inside the ciphertext.
    if (envelope['generation'] != generation) return null;
    final clear = await _cipher.decrypt(
      SecretBox(
        base64Decode(envelope['cipherText'] as String),
        nonce: base64Decode(envelope['nonce'] as String),
        mac: Mac(base64Decode(envelope['mac'] as String)),
      ),
      secretKey: key,
      aad: utf8.encode('cardock-editor-draft-v1:$binding'),
    );
    try {
      final payload = jsonDecode(utf8.decode(clear));
      if (payload is! Map<String, dynamic> || payload['generation'] is! int) {
        throw const VaultFormatException();
      }
      // Changed business data must never be overwritten by a stale editor.
      if (payload['generation'] != generation) return null;
      final draft = payload['draft'];
      if (draft == null) return null;
      if (draft is! Map<String, dynamic> ||
          (draft['kind'] != 'account' && draft['kind'] != 'subscription') ||
          draft['fields'] is! Map<String, dynamic>) {
        throw const VaultFormatException();
      }
      return Map<String, Object?>.from(draft);
    } finally {
      clear.fillRange(0, clear.length, 0);
    }
  }
}
