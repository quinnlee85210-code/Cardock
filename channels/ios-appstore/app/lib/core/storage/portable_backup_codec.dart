import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../security/offline_password_advisor.dart';
import '../security/vault_contract.dart';
import '../security/vault_crypto.dart';

const maximumPortableBackupBytes = 16 * 1024 * 1024;

const _portableBackupMagic = 'ASM_PORTABLE_BACKUP';
const _portableBackupFormatVersion = 2;
const _portablePayloadVersion = 1;
const _aesName = 'aes-256-gcm';
const _saltLength = 16;
const _nonceLength = 12;
const _macLength = 16;
const _maximumCipherBoxBytes = 12 * 1024 * 1024;

enum PortableBackupContainerKind { legacyVaultV1, portableV2 }

final class PortableBackupInspection {
  const PortableBackupInspection({
    required this.containerKind,
    required this.sourceSchemaVersion,
    required this.accountCount,
    required this.subscriptionCount,
    this.backupId,
    this.createdAtUtc,
  });

  final PortableBackupContainerKind containerKind;
  final int sourceSchemaVersion;
  final int accountCount;
  final int subscriptionCount;
  final String? backupId;
  final DateTime? createdAtUtc;

  int get formatVersion => switch (containerKind) {
    PortableBackupContainerKind.legacyVaultV1 => 1,
    PortableBackupContainerKind.portableV2 => 2,
  };
}

final class PortableBackupReadResult {
  const PortableBackupReadResult({
    required this.snapshot,
    required this.inspection,
  });

  final VaultSnapshot snapshot;
  final PortableBackupInspection inspection;
}

sealed class PortableBackupException implements Exception {
  const PortableBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class PortableBackupCancelledException extends PortableBackupException {
  const PortableBackupCancelledException() : super('备份操作已停止');
}

void _requireBackupAuthorization(bool Function()? authorized) {
  if (authorized != null && !authorized()) {
    throw const PortableBackupCancelledException();
  }
}

final class PortableBackupAuthenticationException
    extends PortableBackupException {
  const PortableBackupAuthenticationException() : super('备份密码错误或文件损坏');
}

final class PortableBackupFormatException extends PortableBackupException {
  const PortableBackupFormatException() : super('备份文件格式无效、损坏或来自未来版本');
}

/// Encodes a stable, Keystore-independent portable backup container.
///
/// Version 2 encrypts both the vault snapshot and all identifying metadata.
/// Version 1 raw [VaultEnvelope] files remain readable for migration.
final class PortableBackupCodec {
  PortableBackupCodec({AesGcm? cipher, VaultCrypto? legacyCrypto})
    : _cipher = cipher ?? AesGcm.with256bits(),
      _legacyCrypto = legacyCrypto ?? VaultCrypto();

  static const creationKdf = VaultKdfParameters.production;

  final AesGcm _cipher;
  final VaultCrypto _legacyCrypto;

  Future<Uint8List> encryptV2({
    required VaultSnapshot snapshot,
    required String backupMasterPassword,
    int sourceSchemaVersion = VaultSnapshot.currentSchemaVersion,
    DateTime? createdAtUtc,
    bool Function()? isAuthorized,
  }) async {
    _requireBackupAuthorization(isAuthorized);
    _validatePasswordForCreation(backupMasterPassword);
    _validateSourceSchemaVersion(sourceSchemaVersion);
    _validatePortableKdf(creationKdf);

    final createdAt = (createdAtUtc ?? DateTime.now()).toUtc();
    final backupId = _newUuidV4();
    final clearText = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'payloadVersion': _portablePayloadVersion,
          'backupId': backupId,
          'createdAtUtc': createdAt.toIso8601String(),
          'sourceSchemaVersion': sourceSchemaVersion,
          'accountCount': snapshot.accounts.length,
          'subscriptionCount': snapshot.subscriptions.length,
          'snapshot': snapshot.toEncryptedPayloadJson(),
        }),
      ),
    );
    if (clearText.length > _maximumCipherBoxBytes - _nonceLength - _macLength) {
      _erase(clearText);
      throw const PortableBackupFormatException();
    }

    final salt = _randomBytes(_saltLength);
    SecretKeyData? encryptionKey;
    try {
      encryptionKey = await _deriveKey(
        masterPassword: backupMasterPassword,
        salt: salt,
        kdf: creationKdf,
      );
      _requireBackupAuthorization(isAuthorized);
      final encrypted = await _cipher.encrypt(
        clearText,
        secretKey: encryptionKey,
        nonce: _cipher.newNonce(),
        aad: _aad(kdf: creationKdf, salt: salt),
      );
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'magic': _portableBackupMagic,
            'formatVersion': _portableBackupFormatVersion,
            'kdf': creationKdf.toJson(),
            'salt': base64Encode(salt),
            'payload': <String, Object?>{
              'cipher': _aesName,
              'box': base64Encode(encrypted.concatenation()),
            },
          }),
        ),
      );
      if (bytes.isEmpty || bytes.length > maximumPortableBackupBytes) {
        _erase(bytes);
        throw const PortableBackupFormatException();
      }
      return bytes;
    } finally {
      encryptionKey?.destroy();
      _erase(clearText);
      _erase(salt);
    }
  }

  Future<Uint8List> reencryptAsV2({
    required List<int> sourceBytes,
    required String sourceMasterPassword,
    required String backupMasterPassword,
    DateTime? createdAtUtc,
  }) async {
    final source = await read(
      bytes: sourceBytes,
      backupMasterPassword: sourceMasterPassword,
    );
    return encryptV2(
      snapshot: source.snapshot,
      backupMasterPassword: backupMasterPassword,
      sourceSchemaVersion: source.inspection.sourceSchemaVersion,
      createdAtUtc: createdAtUtc,
    );
  }

  Future<PortableBackupInspection> inspect({
    required List<int> bytes,
    required String backupMasterPassword,
  }) async => (await read(
    bytes: bytes,
    backupMasterPassword: backupMasterPassword,
  )).inspection;

  Future<PortableBackupReadResult> read({
    required List<int> bytes,
    required String backupMasterPassword,
    bool Function()? isAuthorized,
  }) async {
    _requireBackupAuthorization(isAuthorized);
    if (bytes.isEmpty || bytes.length > maximumPortableBackupBytes) {
      throw const PortableBackupFormatException();
    }
    final outer = _decodeJsonMap(bytes);
    if (outer['magic'] == _portableBackupMagic) {
      return _readV2(
        outer: outer,
        backupMasterPassword: backupMasterPassword,
        isAuthorized: isAuthorized,
      );
    }
    return _readLegacyV1(
      bytes: bytes,
      backupMasterPassword: backupMasterPassword,
    );
  }

  Future<PortableBackupReadResult> _readV2({
    required Map<Object?, Object?> outer,
    required String backupMasterPassword,
    bool Function()? isAuthorized,
  }) async {
    _validatePasswordForReading(backupMasterPassword);
    if (outer['formatVersion'] != _portableBackupFormatVersion) {
      throw const PortableBackupFormatException();
    }

    final kdf = _parsePortableKdf(outer['kdf']);
    final salt = _decodeSalt(outer['salt']);
    final encrypted = _decodeSecretBox(outer['payload']);
    SecretKeyData? encryptionKey;
    List<int>? clearText;
    try {
      encryptionKey = await _deriveKey(
        masterPassword: backupMasterPassword,
        salt: salt,
        kdf: kdf,
      );
      _requireBackupAuthorization(isAuthorized);
      try {
        clearText = await _cipher.decrypt(
          encrypted,
          secretKey: encryptionKey,
          aad: _aad(kdf: kdf, salt: salt),
        );
      } on SecretBoxAuthenticationError {
        throw const PortableBackupAuthenticationException();
      }
      _requireBackupAuthorization(isAuthorized);
      return _parseV2Payload(clearText);
    } on PortableBackupException {
      rethrow;
    } on Object {
      throw const PortableBackupFormatException();
    } finally {
      encryptionKey?.destroy();
      _erase(clearText);
      _erase(salt);
    }
  }

  Future<PortableBackupReadResult> _readLegacyV1({
    required List<int> bytes,
    required String backupMasterPassword,
  }) async {
    _validatePasswordForReading(backupMasterPassword);
    VaultCryptoMaterial? material;
    try {
      final envelope = VaultEnvelope.fromBytes(bytes);
      material = await _legacyCrypto.open(
        masterPassword: backupMasterPassword,
        envelope: envelope,
      );
      final sourceSchemaVersion = await _readLegacySchemaVersion(material);
      return PortableBackupReadResult(
        snapshot: material.snapshot,
        inspection: PortableBackupInspection(
          containerKind: PortableBackupContainerKind.legacyVaultV1,
          sourceSchemaVersion: sourceSchemaVersion,
          accountCount: material.snapshot.accounts.length,
          subscriptionCount: material.snapshot.subscriptions.length,
        ),
      );
    } on VaultUnlockException {
      throw const PortableBackupAuthenticationException();
    } on SecretBoxAuthenticationError {
      throw const PortableBackupAuthenticationException();
    } on VaultFormatException {
      throw const PortableBackupFormatException();
    } on PortableBackupException {
      rethrow;
    } on ArgumentError {
      throw const PortableBackupAuthenticationException();
    } on Object {
      throw const PortableBackupFormatException();
    } finally {
      material?.dataKey.destroy();
    }
  }

  PortableBackupReadResult _parseV2Payload(List<int> clearText) {
    final payload = _decodeJsonMap(clearText);
    final payloadVersion = payload['payloadVersion'];
    final backupId = payload['backupId'];
    final createdAtValue = payload['createdAtUtc'];
    final sourceSchemaVersion = payload['sourceSchemaVersion'];
    final accountCount = payload['accountCount'];
    final subscriptionCount = payload['subscriptionCount'];
    final rawSnapshot = payload['snapshot'];
    if (payloadVersion != _portablePayloadVersion ||
        backupId is! String ||
        !_uuidV4Pattern.hasMatch(backupId) ||
        createdAtValue is! String ||
        createdAtValue.length > 64 ||
        sourceSchemaVersion is! int ||
        accountCount is! int ||
        subscriptionCount is! int ||
        rawSnapshot is! Map<Object?, Object?>) {
      throw const PortableBackupFormatException();
    }
    _validateSourceSchemaVersion(sourceSchemaVersion);
    final createdAt = DateTime.tryParse(createdAtValue);
    if (createdAt == null || !createdAt.isUtc) {
      throw const PortableBackupFormatException();
    }

    try {
      final snapshot = VaultSnapshot.fromEncryptedPayloadJson(rawSnapshot);
      if (accountCount != snapshot.accounts.length ||
          subscriptionCount != snapshot.subscriptions.length) {
        throw const PortableBackupFormatException();
      }
      return PortableBackupReadResult(
        snapshot: snapshot,
        inspection: PortableBackupInspection(
          containerKind: PortableBackupContainerKind.portableV2,
          sourceSchemaVersion: sourceSchemaVersion,
          accountCount: accountCount,
          subscriptionCount: subscriptionCount,
          backupId: backupId,
          createdAtUtc: createdAt,
        ),
      );
    } on VaultFormatException {
      throw const PortableBackupFormatException();
    }
  }

  Future<int> _readLegacySchemaVersion(VaultCryptoMaterial material) async {
    List<int>? clearText;
    try {
      clearText = await _cipher.decrypt(
        material.envelope.payload,
        secretKey: material.dataKey,
        aad: material.envelope.payloadAad(),
      );
      final payload = _decodeJsonMap(clearText);
      final schemaVersion = payload['schemaVersion'];
      if (schemaVersion is! int) {
        throw const PortableBackupFormatException();
      }
      _validateSourceSchemaVersion(schemaVersion);
      return schemaVersion;
    } on SecretBoxAuthenticationError {
      throw const PortableBackupAuthenticationException();
    } finally {
      _erase(clearText);
    }
  }

  Future<SecretKeyData> _deriveKey({
    required String masterPassword,
    required List<int> salt,
    required VaultKdfParameters kdf,
  }) async {
    final passwordBytes = Uint8List.fromList(utf8.encode(masterPassword));
    final passwordKey = SecretKeyData(
      passwordBytes,
      overwriteWhenDestroyed: true,
    );
    SecretKey? derivedKey;
    try {
      derivedKey = await Argon2id(
        memory: kdf.memoryKiB,
        iterations: kdf.iterations,
        parallelism: kdf.parallelism,
        hashLength: kdf.hashLength,
      ).deriveKey(secretKey: passwordKey, nonce: salt);
      final extracted = await derivedKey.extract();
      try {
        return SecretKeyData(
          Uint8List.fromList(extracted.bytes),
          overwriteWhenDestroyed: true,
        );
      } finally {
        extracted.destroy();
      }
    } finally {
      passwordKey.destroy();
      derivedKey?.destroy();
    }
  }

  static VaultKdfParameters _parsePortableKdf(Object? value) {
    try {
      final kdf = VaultKdfParameters.fromJson(
        value,
        supportedProfiles: const <VaultKdfParameters>[
          VaultKdfParameters.production,
        ],
      );
      _validatePortableKdf(kdf);
      return kdf;
    } on VaultFormatException {
      throw const PortableBackupFormatException();
    }
  }

  static void _validatePortableKdf(VaultKdfParameters kdf) {
    kdf.validate();
    if (kdf.memoryKiB < VaultKdfParameters.production.memoryKiB ||
        kdf.memoryKiB > 64 * 1024 ||
        kdf.iterations < VaultKdfParameters.production.iterations ||
        kdf.iterations > 6 ||
        kdf.parallelism < 1 ||
        kdf.parallelism > 4 ||
        kdf.hashLength != 32) {
      throw const PortableBackupFormatException();
    }
  }

  static Uint8List _decodeSalt(Object? value) {
    if (value is! String || value.length > 128) {
      throw const PortableBackupFormatException();
    }
    try {
      final salt = Uint8List.fromList(base64Decode(value));
      if (salt.length != _saltLength) {
        _erase(salt);
        throw const PortableBackupFormatException();
      }
      return salt;
    } on PortableBackupException {
      rethrow;
    } on Object {
      throw const PortableBackupFormatException();
    }
  }

  static SecretBox _decodeSecretBox(Object? value) {
    if (value is! Map<Object?, Object?> ||
        value['cipher'] != _aesName ||
        value['box'] is! String) {
      throw const PortableBackupFormatException();
    }
    final encoded = value['box']! as String;
    if (encoded.length > _maximumCipherBoxBytes * 2) {
      throw const PortableBackupFormatException();
    }
    try {
      final concatenated = base64Decode(encoded);
      if (concatenated.length < _nonceLength + _macLength ||
          concatenated.length > _maximumCipherBoxBytes) {
        _erase(concatenated);
        throw const PortableBackupFormatException();
      }
      final box = SecretBox.fromConcatenation(
        concatenated,
        nonceLength: _nonceLength,
        macLength: _macLength,
        copy: true,
      );
      _erase(concatenated);
      return box;
    } on PortableBackupException {
      rethrow;
    } on Object {
      throw const PortableBackupFormatException();
    }
  }

  static Map<Object?, Object?> _decodeJsonMap(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<Object?, Object?>) {
        throw const PortableBackupFormatException();
      }
      return decoded;
    } on PortableBackupException {
      rethrow;
    } on Object {
      throw const PortableBackupFormatException();
    }
  }

  static List<int> _aad({
    required VaultKdfParameters kdf,
    required List<int> salt,
  }) => utf8.encode(
    '$_portableBackupMagic|$_portableBackupFormatVersion|argon2id|19|'
    '${kdf.memoryKiB}|${kdf.iterations}|${kdf.parallelism}|'
    '${kdf.hashLength}|${base64Encode(salt)}|$_aesName|payload',
  );

  static void _validatePasswordForCreation(String password) {
    final assessment = OfflinePasswordAdvisor.assess(password);
    if (!assessment.accepted) {
      throw ArgumentError(assessment.message);
    }
  }

  static void _validatePasswordForReading(String password) {
    final length = password.runes.length;
    if (length < 12 || length > 128) {
      throw const PortableBackupAuthenticationException();
    }
  }

  static void _validateSourceSchemaVersion(int value) {
    if (value < 1 || value > VaultSnapshot.currentSchemaVersion) {
      throw const PortableBackupFormatException();
    }
  }

  static Uint8List _randomBytes(int length) {
    final source = SecretKeyData.random(length: length);
    try {
      return Uint8List.fromList(source.bytes);
    } finally {
      source.destroy();
    }
  }

  static String _newUuidV4() {
    final bytes = _randomBytes(16);
    try {
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      final hex = bytes
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
          '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
          '${hex.substring(20)}';
    } finally {
      _erase(bytes);
    }
  }

  static final RegExp _uuidV4Pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  static void _erase(List<int>? bytes) {
    if (bytes == null) {
      return;
    }
    try {
      bytes.fillRange(0, bytes.length, 0);
    } on UnsupportedError {
      // Some cryptography implementations may return immutable buffers.
    }
  }
}
