import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'vault_contract.dart';
import 'vault_recovery.dart';

const _vaultMagic = 'ASM_LOCAL_VAULT';
const _vaultFormatVersion = 1;
const _vaultFormatVersionV2 = 2;
const _latestVaultFormatVersion = _vaultFormatVersionV2;
const _aesName = 'aes-256-gcm';
const _argon2Name = 'argon2id';
const _saltLength = 16;
const _dataKeyLength = 32;
const _nonceLength = 12;
const _macLength = 16;
const _vaultInstanceIdLength = 16;
const _maximumPayloadBoxLength = 16 * 1024 * 1024;

final class VaultKdfParameters {
  const VaultKdfParameters({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    this.hashLength = 32,
  });

  static const production = VaultKdfParameters(
    memoryKiB: 19 * 1024,
    iterations: 2,
    parallelism: 1,
  );

  factory VaultKdfParameters.fromJson(
    Object? value, {
    Iterable<VaultKdfParameters>? supportedProfiles,
  }) {
    if (value is! Map<Object?, Object?> ||
        value['name'] != _argon2Name ||
        value['version'] != 19) {
      throw const VaultFormatException();
    }
    final memoryKiB = value['memoryKiB'];
    final iterations = value['iterations'];
    final parallelism = value['parallelism'];
    final hashLength = value['hashLength'];
    if (memoryKiB is! int ||
        iterations is! int ||
        parallelism is! int ||
        hashLength is! int) {
      throw const VaultFormatException();
    }
    final parameters = VaultKdfParameters(
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: hashLength,
    );
    parameters.validate();
    if (supportedProfiles != null &&
        !supportedProfiles.any(parameters.hasSameProfileAs)) {
      throw const VaultUnsupportedKdfProfileException();
    }
    return parameters;
  }

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final int hashLength;

  bool hasSameProfileAs(VaultKdfParameters other) =>
      memoryKiB == other.memoryKiB &&
      iterations == other.iterations &&
      parallelism == other.parallelism &&
      hashLength == other.hashLength;

  void validate() {
    if (parallelism < 1 ||
        parallelism > 8 ||
        memoryKiB < 8 * parallelism ||
        memoryKiB > 128 * 1024 ||
        iterations < 1 ||
        iterations > 10 ||
        hashLength != 32) {
      throw const VaultFormatException();
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'name': _argon2Name,
    'version': 19,
    'memoryKiB': memoryKiB,
    'iterations': iterations,
    'parallelism': parallelism,
    'hashLength': hashLength,
  };
}

final class VaultEnvelope {
  VaultEnvelope({
    this.formatVersion = _vaultFormatVersion,
    List<int>? vaultInstanceId,
    required this.generation,
    required this.kdf,
    required this.salt,
    required this.wrappedDataKey,
    required this.payload,
    this.recoverySlot,
  }) : _vaultInstanceId = vaultInstanceId == null
           ? null
           : Uint8List.fromList(vaultInstanceId);

  factory VaultEnvelope.fromBytes(
    List<int> bytes, {
    Iterable<VaultKdfParameters> supportedKdfProfiles =
        const <VaultKdfParameters>[VaultKdfParameters.production],
    Iterable<VaultRecoveryKdfParameters> supportedRecoveryKdfProfiles =
        const <VaultRecoveryKdfParameters>[
          VaultRecoveryKdfParameters.production,
        ],
  }) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<Object?, Object?> ||
          decoded['magic'] != _vaultMagic) {
        throw const VaultFormatException();
      }

      final rawFormatVersion = decoded['formatVersion'];
      if (rawFormatVersion is int &&
          rawFormatVersion > _latestVaultFormatVersion) {
        throw VaultUnsupportedEnvelopeVersionException(rawFormatVersion);
      }
      if (rawFormatVersion != _vaultFormatVersion &&
          rawFormatVersion != _vaultFormatVersionV2) {
        throw const VaultFormatException();
      }
      final formatVersion = rawFormatVersion as int;

      final generation = decoded['generation'];
      final kdf = VaultKdfParameters.fromJson(
        decoded['kdf'],
        supportedProfiles: supportedKdfProfiles,
      );
      final saltValue = decoded['salt'];
      if (generation is! int ||
          generation < 1 ||
          generation > 1000000000 ||
          saltValue is! String ||
          saltValue.length > 128) {
        throw const VaultFormatException();
      }
      final salt = Uint8List.fromList(base64Decode(saltValue));
      if (salt.length != _saltLength) {
        throw const VaultFormatException();
      }

      Uint8List? vaultInstanceId;
      VaultRecoverySlot? recoverySlot;
      if (formatVersion == _vaultFormatVersion) {
        if (decoded['vaultInstanceId'] != null ||
            decoded['recoverySlot'] != null) {
          throw const VaultFormatException();
        }
      } else {
        vaultInstanceId = _decodeFixedBytes(
          decoded['vaultInstanceId'],
          _vaultInstanceIdLength,
        );
        final recoveryValue = decoded['recoverySlot'];
        if (recoveryValue != null) {
          recoverySlot = VaultRecoverySlot.fromJson(
            recoveryValue,
            supportedKdfProfiles: supportedRecoveryKdfProfiles,
          );
          if (!_bytesEqual(
            recoverySlot.binding.vaultInstanceId,
            vaultInstanceId,
          )) {
            throw const VaultFormatException();
          }
        }
      }

      return VaultEnvelope(
        formatVersion: formatVersion,
        vaultInstanceId: vaultInstanceId,
        generation: generation,
        kdf: kdf,
        salt: salt,
        wrappedDataKey: _decodeBox(
          decoded['wrappedDataKey'],
          expectedCipherTextLength: _dataKeyLength,
        ),
        payload: _decodeBox(
          decoded['payload'],
          maximumConcatenatedLength: _maximumPayloadBoxLength,
        ),
        recoverySlot: recoverySlot,
      );
    } on VaultUnsupportedEnvelopeVersionException {
      rethrow;
    } on VaultUnsupportedKdfProfileException {
      rethrow;
    } on VaultFormatException {
      rethrow;
    } on Object {
      throw const VaultFormatException();
    }
  }

  final int formatVersion;
  final Uint8List? _vaultInstanceId;
  final int generation;
  final VaultKdfParameters kdf;
  final Uint8List salt;
  final SecretBox wrappedDataKey;
  final SecretBox payload;
  final VaultRecoverySlot? recoverySlot;

  Uint8List? get vaultInstanceId =>
      _vaultInstanceId == null ? null : Uint8List.fromList(_vaultInstanceId);

  Uint8List toBytes() {
    final document = formatVersion == _vaultFormatVersion
        ? <String, Object?>{
            'magic': _vaultMagic,
            'formatVersion': _vaultFormatVersion,
            'generation': generation,
            'kdf': kdf.toJson(),
            'salt': base64Encode(salt),
            'wrappedDataKey': _encodeBox(wrappedDataKey),
            'payload': _encodeBox(payload),
          }
        : <String, Object?>{
            'magic': _vaultMagic,
            'formatVersion': _vaultFormatVersionV2,
            'vaultInstanceId': base64Encode(_requireVaultInstanceId()),
            'generation': generation,
            'kdf': kdf.toJson(),
            'salt': base64Encode(salt),
            'wrappedDataKey': _encodeBox(wrappedDataKey),
            'payload': _encodeBox(payload),
            'recoverySlot': recoverySlot?.toJson(),
          };
    return Uint8List.fromList(utf8.encode(jsonEncode(document)));
  }

  List<int> wrappingAad() => formatVersion == _vaultFormatVersion
      ? wrappingAadFor(kdf: kdf, salt: salt)
      : wrappingAadV2For(
          vaultInstanceId: _requireVaultInstanceId(),
          kdf: kdf,
          salt: salt,
        );

  List<int> payloadAad() => formatVersion == _vaultFormatVersion
      ? payloadAadFor(generation)
      : payloadAadV2For(
          vaultInstanceId: _requireVaultInstanceId(),
          generation: generation,
        );

  static List<int> wrappingAadFor({
    required VaultKdfParameters kdf,
    required List<int> salt,
  }) => utf8.encode(
    '$_vaultMagic|$_vaultFormatVersion|$_argon2Name|19|'
    '${kdf.memoryKiB}|${kdf.iterations}|${kdf.parallelism}|'
    '${kdf.hashLength}|${base64Encode(salt)}|$_aesName|wrapped-data-key',
  );

  static List<int> payloadAadFor(int generation) => utf8.encode(
    '$_vaultMagic|$_vaultFormatVersion|$generation|$_aesName|payload',
  );

  static List<int> wrappingAadV2For({
    required List<int> vaultInstanceId,
    required VaultKdfParameters kdf,
    required List<int> salt,
  }) => utf8.encode(
    '$_vaultMagic|$_vaultFormatVersionV2|${base64Encode(vaultInstanceId)}|'
    '$_argon2Name|19|${kdf.memoryKiB}|${kdf.iterations}|'
    '${kdf.parallelism}|${kdf.hashLength}|${base64Encode(salt)}|'
    '$_aesName|wrapped-data-key',
  );

  static List<int> payloadAadV2For({
    required List<int> vaultInstanceId,
    required int generation,
  }) => utf8.encode(
    '$_vaultMagic|$_vaultFormatVersionV2|${base64Encode(vaultInstanceId)}|'
    '$generation|$_aesName|payload',
  );

  Uint8List _requireVaultInstanceId() {
    final value = _vaultInstanceId;
    if (formatVersion != _vaultFormatVersionV2 ||
        value == null ||
        value.length != _vaultInstanceIdLength) {
      throw const VaultFormatException();
    }
    return value;
  }

  static Uint8List _decodeFixedBytes(Object? value, int expectedLength) {
    if (value is! String || value.length > 128) {
      throw const VaultFormatException();
    }
    final decoded = Uint8List.fromList(base64Decode(value));
    if (decoded.length != expectedLength) {
      throw const VaultFormatException();
    }
    return decoded;
  }

  static bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  static SecretBox _decodeBox(
    Object? value, {
    int? expectedCipherTextLength,
    int maximumConcatenatedLength = 1024,
  }) {
    if (value is! Map<Object?, Object?> ||
        value['cipher'] != _aesName ||
        value['box'] is! String) {
      throw const VaultFormatException();
    }
    final encoded = value['box']! as String;
    if (encoded.length > maximumConcatenatedLength * 2) {
      throw const VaultFormatException();
    }
    final concatenated = base64Decode(encoded);
    if (concatenated.length < _nonceLength + _macLength ||
        concatenated.length > maximumConcatenatedLength) {
      throw const VaultFormatException();
    }
    final box = SecretBox.fromConcatenation(
      concatenated,
      nonceLength: _nonceLength,
      macLength: _macLength,
      copy: true,
    );
    if (box.nonce.length != _nonceLength ||
        box.mac.bytes.length != _macLength ||
        (expectedCipherTextLength != null &&
            box.cipherText.length != expectedCipherTextLength)) {
      throw const VaultFormatException();
    }
    return box;
  }

  static Map<String, Object?> _encodeBox(SecretBox box) => <String, Object?>{
    'cipher': _aesName,
    'box': base64Encode(box.concatenation()),
  };
}

final class VaultCryptoMaterial {
  const VaultCryptoMaterial({
    required this.envelope,
    required this.dataKey,
    required this.snapshot,
  });

  final VaultEnvelope envelope;
  final SecretKeyData dataKey;
  final VaultSnapshot snapshot;
}

final class VaultCrypto {
  VaultCrypto({AesGcm? cipher, VaultRecoveryCrypto? recoveryCrypto})
    : _cipher = cipher ?? AesGcm.with256bits(),
      _recoveryCrypto = recoveryCrypto ?? VaultRecoveryCrypto();

  final AesGcm _cipher;
  final VaultRecoveryCrypto _recoveryCrypto;

  Future<VaultCryptoMaterial> create({
    required String masterPassword,
    required VaultSnapshot snapshot,
    required VaultKdfParameters kdf,
    int minimumPasswordLength = 12,
    int maximumPasswordLength = 128,
  }) async {
    _validatePasswordLength(
      masterPassword,
      minimum: minimumPasswordLength,
      maximum: maximumPasswordLength,
    );
    kdf.validate();

    final saltSource = SecretKeyData.random(length: _saltLength);
    final salt = Uint8List.fromList(saltSource.bytes);
    saltSource.destroy();
    final dataKey = SecretKeyData.random(length: _dataKeyLength);
    SecretKeyData? wrappingKey;

    try {
      wrappingKey = await _deriveWrappingKey(
        masterPassword: masterPassword,
        salt: salt,
        kdf: kdf,
      );
      final wrappedDataKey = await _cipher.encrypt(
        dataKey.bytes,
        secretKey: wrappingKey,
        nonce: _cipher.newNonce(),
        aad: VaultEnvelope.wrappingAadFor(kdf: kdf, salt: salt),
      );
      final payload = await _encryptSnapshot(
        snapshot: snapshot,
        dataKey: dataKey,
        aad: VaultEnvelope.payloadAadFor(1),
      );
      final envelope = VaultEnvelope(
        generation: 1,
        kdf: kdf,
        salt: salt,
        wrappedDataKey: wrappedDataKey,
        payload: payload,
      );
      return VaultCryptoMaterial(
        envelope: envelope,
        dataKey: dataKey,
        snapshot: snapshot,
      );
    } on Object {
      dataKey.destroy();
      rethrow;
    } finally {
      wrappingKey?.destroy();
    }
  }

  Future<VaultCryptoMaterial> open({
    required String masterPassword,
    required VaultEnvelope envelope,
    int minimumPasswordLength = 12,
    int maximumPasswordLength = 128,
  }) async {
    _validatePasswordLength(
      masterPassword,
      minimum: minimumPasswordLength,
      maximum: maximumPasswordLength,
    );
    envelope.kdf.validate();
    SecretKeyData? wrappingKey;
    SecretKeyData? dataKey;
    List<int>? unwrappedDataKey;

    try {
      wrappingKey = await _deriveWrappingKey(
        masterPassword: masterPassword,
        salt: envelope.salt,
        kdf: envelope.kdf,
      );
      try {
        unwrappedDataKey = await _cipher.decrypt(
          envelope.wrappedDataKey,
          secretKey: wrappingKey,
          aad: envelope.wrappingAad(),
        );
      } on SecretBoxAuthenticationError {
        throw const VaultCredentialRejectedException();
      }
      if (unwrappedDataKey.length != _dataKeyLength) {
        throw const VaultUnlockException();
      }
      dataKey = SecretKeyData(
        Uint8List.fromList(unwrappedDataKey),
        overwriteWhenDestroyed: true,
      );
      final VaultSnapshot snapshot;
      try {
        snapshot = await decryptSnapshot(envelope: envelope, dataKey: dataKey);
      } on SecretBoxAuthenticationError {
        throw const VaultIntegrityException();
      } on VaultUnsupportedSchemaVersionException {
        rethrow;
      } on VaultFormatException {
        throw const VaultIntegrityException();
      }
      return VaultCryptoMaterial(
        envelope: envelope,
        dataKey: dataKey,
        snapshot: snapshot,
      );
    } on VaultCredentialRejectedException {
      dataKey?.destroy();
      rethrow;
    } on VaultIntegrityException {
      dataKey?.destroy();
      rethrow;
    } on VaultUnsupportedSchemaVersionException {
      dataKey?.destroy();
      rethrow;
    } on VaultFormatException {
      dataKey?.destroy();
      rethrow;
    } finally {
      wrappingKey?.destroy();
      _erase(unwrappedDataKey);
    }
  }

  VaultRecoveryBinding createRecoveryProvisioning({
    required VaultEnvelope previous,
  }) => VaultRecoveryBinding.random(
    vaultInstanceId: previous.formatVersion == _vaultFormatVersionV2
        ? previous.vaultInstanceId
        : null,
  );

  VaultRecoveryChallenge? getRecoveryChallenge(VaultEnvelope envelope) =>
      envelope.recoverySlot?.challenge;

  Future<VaultEnvelope> enableRecoveryNext({
    required VaultEnvelope previous,
    required SecretKeyData dataKey,
    required VaultSnapshot snapshot,
    required String currentMasterPassword,
    required VaultRecoveryBinding binding,
    required List<String> questionIds,
    required List<String> answers,
    required Uint8List deviceSecret,
    required VaultRecoveryEntryMode entryMode,
    VaultRecoveryKdfParameters recoveryKdf =
        VaultRecoveryKdfParameters.production,
    int minimumPasswordLength = 12,
    int maximumPasswordLength = 128,
  }) async {
    if (previous.recoverySlot != null) {
      throw const VaultRecoveryRefreshRequiredException();
    }
    if (dataKey.hasBeenDestroyed || dataKey.bytes.length != _dataKeyLength) {
      throw const VaultClosedException();
    }
    final existingVaultId = previous.vaultInstanceId;
    if (previous.formatVersion == _vaultFormatVersionV2 &&
        (existingVaultId == null ||
            !_constantTimeBytesEqual(
              existingVaultId,
              binding.vaultInstanceId,
            ))) {
      throw const VaultFormatException();
    }

    VaultCryptoMaterial? verification;
    SecretKeyData? wrappingKey;
    try {
      verification = await open(
        masterPassword: currentMasterPassword,
        envelope: previous,
        minimumPasswordLength: minimumPasswordLength,
        maximumPasswordLength: maximumPasswordLength,
      );
      if (!_constantTimeBytesEqual(verification.dataKey.bytes, dataKey.bytes)) {
        throw const VaultIntegrityException();
      }

      final generation = previous.generation + 1;
      if (generation > 1000000000) {
        throw const VaultFormatException();
      }
      final saltSource = SecretKeyData.random(length: _saltLength);
      final salt = Uint8List.fromList(saltSource.bytes);
      saltSource.destroy();
      wrappingKey = await _deriveWrappingKey(
        masterPassword: currentMasterPassword,
        salt: salt,
        kdf: previous.kdf,
      );
      final vaultInstanceId = binding.vaultInstanceId;
      final wrappedDataKey = await _cipher.encrypt(
        dataKey.bytes,
        secretKey: wrappingKey,
        nonce: _cipher.newNonce(),
        aad: VaultEnvelope.wrappingAadV2For(
          vaultInstanceId: vaultInstanceId,
          kdf: previous.kdf,
          salt: salt,
        ),
      );
      final payload = await _encryptSnapshot(
        snapshot: snapshot,
        dataKey: dataKey,
        aad: VaultEnvelope.payloadAadV2For(
          vaultInstanceId: vaultInstanceId,
          generation: generation,
        ),
      );
      final recoverySlot = await _recoveryCrypto.createSlot(
        binding: binding,
        dataKey: dataKey,
        questionIds: questionIds,
        answers: answers,
        deviceSecret: deviceSecret,
        entryMode: entryMode,
        kdf: recoveryKdf,
      );
      return VaultEnvelope(
        formatVersion: _vaultFormatVersionV2,
        vaultInstanceId: vaultInstanceId,
        generation: generation,
        kdf: previous.kdf,
        salt: salt,
        wrappedDataKey: wrappedDataKey,
        payload: payload,
        recoverySlot: recoverySlot,
      );
    } finally {
      verification?.dataKey.destroy();
      wrappingKey?.destroy();
    }
  }

  Future<VaultEnvelope> disableRecoveryNext({
    required VaultEnvelope previous,
    required SecretKeyData dataKey,
    required VaultSnapshot snapshot,
  }) async {
    if (previous.formatVersion != _vaultFormatVersionV2 ||
        previous.recoverySlot == null ||
        previous.vaultInstanceId == null) {
      throw const VaultRecoveryNotConfiguredException();
    }
    if (dataKey.hasBeenDestroyed || dataKey.bytes.length != _dataKeyLength) {
      throw const VaultClosedException();
    }
    final generation = previous.generation + 1;
    if (generation > 1000000000) {
      throw const VaultFormatException();
    }
    final vaultInstanceId = previous.vaultInstanceId!;
    final payload = await _encryptSnapshot(
      snapshot: snapshot,
      dataKey: dataKey,
      aad: VaultEnvelope.payloadAadV2For(
        vaultInstanceId: vaultInstanceId,
        generation: generation,
      ),
    );
    return VaultEnvelope(
      formatVersion: _vaultFormatVersionV2,
      vaultInstanceId: vaultInstanceId,
      generation: generation,
      kdf: previous.kdf,
      salt: previous.salt,
      wrappedDataKey: previous.wrappedDataKey,
      payload: payload,
    );
  }

  Future<VaultCryptoMaterial> openWithRecovery({
    required VaultEnvelope envelope,
    required List<String> answers,
    required Uint8List deviceSecret,
  }) async {
    final slot = envelope.recoverySlot;
    if (envelope.formatVersion != _vaultFormatVersionV2 || slot == null) {
      throw const VaultRecoveryNotConfiguredException();
    }
    SecretKeyData? dataKey;
    try {
      dataKey = await _recoveryCrypto.unwrapDataKey(
        slot: slot,
        answers: answers,
        deviceSecret: deviceSecret,
      );
      final VaultSnapshot snapshot;
      try {
        snapshot = await decryptSnapshot(envelope: envelope, dataKey: dataKey);
      } on SecretBoxAuthenticationError {
        throw const VaultIntegrityException();
      } on VaultUnsupportedSchemaVersionException {
        rethrow;
      } on VaultFormatException {
        throw const VaultIntegrityException();
      }
      final ownedDataKey = dataKey;
      dataKey = null;
      return VaultCryptoMaterial(
        envelope: envelope,
        dataKey: ownedDataKey,
        snapshot: snapshot,
      );
    } on VaultRecoveryRejectedException {
      dataKey?.destroy();
      rethrow;
    } on VaultIntegrityException {
      dataKey?.destroy();
      rethrow;
    } on VaultUnsupportedSchemaVersionException {
      dataKey?.destroy();
      rethrow;
    }
  }

  /// 密码轮换时生成全新随机 256-bit DEK，并用新 DEK 重新加密快照。
  ///
  /// 这使旧密码、旧包装或旧 DEK 日后泄露时，仍无法解密换密后的
  /// 当前代与未来代。调用方只能在 committed floor 持久化后接管返回的 DEK。
  Future<VaultCryptoMaterial> rotateDataKeyNext({
    required VaultEnvelope previous,
    required VaultSnapshot snapshot,
    required String newPassword,
    required VaultKdfParameters kdf,
    VaultRecoveryCredentials? recoveryCredentials,
    bool explicitlyDisableRecovery = false,
    int minimumPasswordLength = 12,
    int maximumPasswordLength = 128,
  }) async {
    _validatePasswordLength(
      newPassword,
      minimum: minimumPasswordLength,
      maximum: maximumPasswordLength,
    );
    kdf.validate();
    final previousRecoverySlot = previous.recoverySlot;
    if (previousRecoverySlot != null) {
      if (recoveryCredentials != null && explicitlyDisableRecovery) {
        throw ArgumentError(
          'cannot refresh and disable recovery in the same rotation',
        );
      }
      if (recoveryCredentials == null && !explicitlyDisableRecovery) {
        throw const VaultRecoveryRefreshRequiredException();
      }
    } else if (recoveryCredentials != null) {
      throw ArgumentError('recovery is not configured');
    }
    final generation = previous.generation + 1;
    if (generation > 1000000000) {
      throw const VaultFormatException();
    }

    final saltSource = SecretKeyData.random(length: _saltLength);
    final salt = Uint8List.fromList(saltSource.bytes);
    saltSource.destroy();
    final newDataKey = SecretKeyData.random(length: _dataKeyLength);
    SecretKeyData? wrappingKey;
    try {
      wrappingKey = await _deriveWrappingKey(
        masterPassword: newPassword,
        salt: salt,
        kdf: kdf,
      );
      final wrappedDataKey = await _cipher.encrypt(
        newDataKey.bytes,
        secretKey: wrappingKey,
        nonce: _cipher.newNonce(),
        aad: previous.formatVersion == _vaultFormatVersionV2
            ? VaultEnvelope.wrappingAadV2For(
                vaultInstanceId: previous.vaultInstanceId!,
                kdf: kdf,
                salt: salt,
              )
            : VaultEnvelope.wrappingAadFor(kdf: kdf, salt: salt),
      );
      final payload = await _encryptSnapshot(
        snapshot: snapshot,
        dataKey: newDataKey,
        aad: previous.formatVersion == _vaultFormatVersionV2
            ? VaultEnvelope.payloadAadV2For(
                vaultInstanceId: previous.vaultInstanceId!,
                generation: generation,
              )
            : VaultEnvelope.payloadAadFor(generation),
      );
      final VaultRecoverySlot? recoverySlot;
      if (previousRecoverySlot != null && recoveryCredentials != null) {
        recoverySlot = await _recoveryCrypto.rewrapDataKey(
          previous: previousRecoverySlot,
          newDataKey: newDataKey,
          answers: recoveryCredentials.answers,
          deviceSecret: recoveryCredentials.deviceSecret,
        );
      } else {
        recoverySlot = null;
      }
      return VaultCryptoMaterial(
        envelope: VaultEnvelope(
          formatVersion: previous.formatVersion,
          vaultInstanceId: previous.vaultInstanceId,
          generation: generation,
          kdf: kdf,
          salt: salt,
          wrappedDataKey: wrappedDataKey,
          payload: payload,
          recoverySlot: recoverySlot,
        ),
        dataKey: newDataKey,
        snapshot: snapshot,
      );
    } on Object {
      newDataKey.destroy();
      rethrow;
    } finally {
      wrappingKey?.destroy();
    }
  }

  Future<VaultEnvelope> encryptNext({
    required VaultEnvelope previous,
    required SecretKeyData dataKey,
    required VaultSnapshot snapshot,
  }) async {
    if (dataKey.hasBeenDestroyed) {
      throw const VaultClosedException();
    }
    final generation = previous.generation + 1;
    if (generation > 1000000000) {
      throw const VaultFormatException();
    }
    final header = VaultEnvelope(
      formatVersion: previous.formatVersion,
      vaultInstanceId: previous.vaultInstanceId,
      generation: generation,
      kdf: previous.kdf,
      salt: previous.salt,
      wrappedDataKey: previous.wrappedDataKey,
      payload: previous.payload,
      recoverySlot: previous.recoverySlot,
    );
    final payload = await _encryptSnapshot(
      snapshot: snapshot,
      dataKey: dataKey,
      aad: header.payloadAad(),
    );
    return VaultEnvelope(
      formatVersion: previous.formatVersion,
      vaultInstanceId: previous.vaultInstanceId,
      generation: generation,
      kdf: previous.kdf,
      salt: previous.salt,
      wrappedDataKey: previous.wrappedDataKey,
      payload: payload,
      recoverySlot: previous.recoverySlot,
    );
  }

  Future<VaultSnapshot> decryptSnapshot({
    required VaultEnvelope envelope,
    required SecretKeyData dataKey,
  }) async {
    List<int>? clearText;
    try {
      clearText = await _cipher.decrypt(
        envelope.payload,
        secretKey: dataKey,
        aad: envelope.payloadAad(),
      );
      final decoded = jsonDecode(utf8.decode(clearText));
      return VaultSnapshot.fromEncryptedPayloadJson(decoded);
    } on SecretBoxAuthenticationError {
      rethrow;
    } on VaultUnsupportedSchemaVersionException {
      rethrow;
    } on VaultFormatException {
      rethrow;
    } on Object {
      throw const VaultFormatException();
    } finally {
      _erase(clearText);
    }
  }

  Future<SecretBox> _encryptSnapshot({
    required VaultSnapshot snapshot,
    required SecretKeyData dataKey,
    required List<int> aad,
  }) async {
    final clearText = Uint8List.fromList(
      utf8.encode(jsonEncode(snapshot.toEncryptedPayloadJson())),
    );
    try {
      return await _cipher.encrypt(
        clearText,
        secretKey: dataKey,
        nonce: _cipher.newNonce(),
        aad: aad,
      );
    } finally {
      _erase(clearText);
    }
  }

  Future<SecretKeyData> _deriveWrappingKey({
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
        if (!identical(extracted, derivedKey)) {
          extracted.destroy();
        }
      }
    } finally {
      passwordKey.destroy();
      derivedKey?.destroy();
    }
  }

  static void _validatePasswordLength(
    String password, {
    required int minimum,
    required int maximum,
  }) {
    if (minimum < 1 || maximum < minimum || maximum > 128) {
      throw ArgumentError('invalid password length policy');
    }
    final length = password.runes.length;
    if (length < minimum || length > maximum) {
      throw ArgumentError('密码长度不符合当前保险库策略');
    }
  }

  static bool _constantTimeBytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  static void _erase(List<int>? bytes) {
    if (bytes == null) {
      return;
    }
    try {
      bytes.fillRange(0, bytes.length, 0);
    } on UnsupportedError {
      // Some platform implementations return immutable buffers.
    }
  }
}
