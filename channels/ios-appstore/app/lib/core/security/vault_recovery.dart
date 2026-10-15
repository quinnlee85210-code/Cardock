import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'vault_contract.dart';

const _recoverySlotVersion = 1;
const _recoveryNormalization = 'nfkc-trim-collapse-lower-v1';
const _recoveryAesName = 'aes-256-gcm';
const _recoveryArgon2Name = 'argon2id';
const _recoverySaltLength = 16;
const _recoveryBindingPartLength = 16;
const _recoveryDeviceSecretLength = 32;
const _recoveryDataKeyLength = 32;
const _recoveryNonceLength = 12;
const _recoveryMacLength = 16;
const _recoveryHkdfInfo = 'ASM_LOCAL_VAULT|recovery-key|1';

enum VaultRecoveryEntryMode {
  visible('visible'),
  logoFiveTap('logoFiveTap');

  const VaultRecoveryEntryMode(this.storageValue);

  final String storageValue;

  static VaultRecoveryEntryMode fromStorage(Object? value) {
    for (final mode in values) {
      if (mode.storageValue == value) {
        return mode;
      }
    }
    throw const VaultFormatException();
  }
}

enum VaultRecoveryScope { primary, decoy }

final class VaultRecoveryConfiguration {
  const VaultRecoveryConfiguration({
    this.primaryChallenge,
    this.decoyChallenge,
  });

  final VaultRecoveryChallenge? primaryChallenge;
  final VaultRecoveryChallenge? decoyChallenge;

  bool get anyConfigured => primaryChallenge != null || decoyChallenge != null;

  VaultRecoveryChallenge? challengeFor(VaultRecoveryScope scope) =>
      switch (scope) {
        VaultRecoveryScope.primary => primaryChallenge,
        VaultRecoveryScope.decoy => decoyChallenge,
      };
}

final class VaultRecoveryQuestion {
  const VaultRecoveryQuestion({required this.id, required this.label});

  final String id;
  final String label;
}

abstract final class VaultRecoveryQuestionCatalog {
  static const questions = <VaultRecoveryQuestion>[
    VaultRecoveryQuestion(id: 'childhood_city', label: '你童年生活时间最长的城市是？'),
    VaultRecoveryQuestion(id: 'first_school', label: '你就读的第一所学校叫什么？'),
    VaultRecoveryQuestion(id: 'first_teacher', label: '你的第一位老师姓什么？'),
    VaultRecoveryQuestion(id: 'childhood_friend', label: '你童年好友的名字是？'),
    VaultRecoveryQuestion(id: 'first_pet', label: '你的第一只宠物叫什么？'),
    VaultRecoveryQuestion(id: 'favorite_book', label: '你最难忘的一本书是？'),
    VaultRecoveryQuestion(id: 'favorite_food', label: '你童年最喜欢的食物是？'),
    VaultRecoveryQuestion(id: 'first_trip', label: '你第一次远行的目的地是？'),
  ];

  static const _ids = <String>{
    'childhood_city',
    'first_school',
    'first_teacher',
    'childhood_friend',
    'first_pet',
    'favorite_book',
    'favorite_food',
    'first_trip',
  };

  static bool contains(String id) => _ids.contains(id);
}

const List<VaultRecoveryQuestion> vaultRecoveryQuestionCatalog =
    VaultRecoveryQuestionCatalog.questions;

String vaultRecoveryQuestionLabel(String id) {
  for (final question in vaultRecoveryQuestionCatalog) {
    if (question.id == id) {
      return question.label;
    }
  }
  throw ArgumentError.value(id, 'id', 'unknown recovery question ID');
}

final class VaultRecoveryKdfParameters {
  const VaultRecoveryKdfParameters({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    this.hashLength = 32,
  });

  static const production = VaultRecoveryKdfParameters(
    memoryKiB: 19 * 1024,
    iterations: 2,
    parallelism: 1,
  );

  factory VaultRecoveryKdfParameters.fromJson(
    Object? value, {
    Iterable<VaultRecoveryKdfParameters> supportedProfiles =
        const <VaultRecoveryKdfParameters>[
          VaultRecoveryKdfParameters.production,
        ],
  }) {
    if (value is! Map<Object?, Object?> ||
        value['name'] != _recoveryArgon2Name ||
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
    final parameters = VaultRecoveryKdfParameters(
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: hashLength,
    );
    parameters.validate();
    if (!supportedProfiles.any(parameters.hasSameProfileAs)) {
      throw const VaultUnsupportedKdfProfileException();
    }
    return parameters;
  }

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final int hashLength;

  bool hasSameProfileAs(VaultRecoveryKdfParameters other) =>
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
    'name': _recoveryArgon2Name,
    'version': 19,
    'memoryKiB': memoryKiB,
    'iterations': iterations,
    'parallelism': parallelism,
    'hashLength': hashLength,
  };
}

/// 将设备 Keystore 记录与恢复槽绑定的非敏感随机标识。
final class VaultRecoveryBinding {
  VaultRecoveryBinding({
    required List<int> vaultInstanceId,
    required List<int> slotId,
    required List<int> deviceBindingId,
  }) : _vaultInstanceId = Uint8List.fromList(vaultInstanceId),
       _slotId = Uint8List.fromList(slotId),
       _deviceBindingId = Uint8List.fromList(deviceBindingId) {
    validate();
  }

  factory VaultRecoveryBinding.random({List<int>? vaultInstanceId}) {
    final generatedVaultId = vaultInstanceId == null
        ? _randomBytes(_recoveryBindingPartLength)
        : Uint8List.fromList(vaultInstanceId);
    return VaultRecoveryBinding(
      vaultInstanceId: generatedVaultId,
      slotId: _randomBytes(_recoveryBindingPartLength),
      deviceBindingId: _randomBytes(_recoveryBindingPartLength),
    );
  }

  factory VaultRecoveryBinding.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const VaultFormatException();
    }
    return VaultRecoveryBinding(
      vaultInstanceId: _decodeFixedBytes(
        value['vaultInstanceId'],
        _recoveryBindingPartLength,
      ),
      slotId: _decodeFixedBytes(value['slotId'], _recoveryBindingPartLength),
      deviceBindingId: _decodeFixedBytes(
        value['deviceBindingId'],
        _recoveryBindingPartLength,
      ),
    );
  }

  final Uint8List _vaultInstanceId;
  final Uint8List _slotId;
  final Uint8List _deviceBindingId;

  Uint8List get vaultInstanceId => Uint8List.fromList(_vaultInstanceId);

  Uint8List get slotId => Uint8List.fromList(_slotId);

  Uint8List get deviceBindingId => Uint8List.fromList(_deviceBindingId);

  void validate() {
    if (_vaultInstanceId.length != _recoveryBindingPartLength ||
        _slotId.length != _recoveryBindingPartLength ||
        _deviceBindingId.length != _recoveryBindingPartLength) {
      throw const VaultFormatException();
    }
  }

  bool hasSameValuesAs(VaultRecoveryBinding other) =>
      _bytesEqual(_vaultInstanceId, other._vaultInstanceId) &&
      _bytesEqual(_slotId, other._slotId) &&
      _bytesEqual(_deviceBindingId, other._deviceBindingId);

  Map<String, Object?> toJson() => <String, Object?>{
    'vaultInstanceId': base64Encode(_vaultInstanceId),
    'slotId': base64Encode(_slotId),
    'deviceBindingId': base64Encode(_deviceBindingId),
  };

  Uint8List hkdfSalt() => Uint8List.fromList(<int>[
    ..._vaultInstanceId,
    ..._slotId,
    ..._deviceBindingId,
  ]);
}

final class VaultRecoveryChallenge {
  VaultRecoveryChallenge({
    required VaultRecoveryBinding binding,
    required List<String> questionIds,
    required this.entryMode,
  }) : binding = VaultRecoveryBinding(
         vaultInstanceId: binding.vaultInstanceId,
         slotId: binding.slotId,
         deviceBindingId: binding.deviceBindingId,
       ),
       questionIds = List<String>.unmodifiable(questionIds);

  final VaultRecoveryBinding binding;
  final List<String> questionIds;
  final VaultRecoveryEntryMode entryMode;
  String get normalization => _recoveryNormalization;
}

/// 仅作为一次密码轮换调用的输入；调用方用毕后应调用 [destroy]。
final class VaultRecoveryCredentials {
  VaultRecoveryCredentials({
    required List<String> answers,
    required List<int> deviceSecret,
  }) : answers = List<String>.unmodifiable(answers),
       deviceSecret = Uint8List.fromList(deviceSecret) {
    if (this.deviceSecret.length != _recoveryDeviceSecretLength) {
      throw ArgumentError('deviceSecret must contain exactly 32 bytes');
    }
  }

  final List<String> answers;
  final Uint8List deviceSecret;

  void destroy() => _erase(deviceSecret);
}

final class VaultRecoverySlot {
  VaultRecoverySlot({
    required VaultRecoveryBinding binding,
    required List<String> questionIds,
    required this.entryMode,
    required this.kdf,
    required List<int> salt,
    required this.wrappedDataKey,
  }) : binding = VaultRecoveryBinding(
         vaultInstanceId: binding.vaultInstanceId,
         slotId: binding.slotId,
         deviceBindingId: binding.deviceBindingId,
       ),
       questionIds = List<String>.unmodifiable(questionIds),
       _salt = Uint8List.fromList(salt) {
    validate();
  }

  factory VaultRecoverySlot.fromJson(
    Object? value, {
    Iterable<VaultRecoveryKdfParameters> supportedKdfProfiles =
        const <VaultRecoveryKdfParameters>[
          VaultRecoveryKdfParameters.production,
        ],
  }) {
    try {
      if (value is! Map<Object?, Object?> ||
          value['version'] != _recoverySlotVersion ||
          value['normalization'] != _recoveryNormalization ||
          value['questionIds'] is! List<Object?>) {
        throw const VaultFormatException();
      }
      final rawQuestionIds = value['questionIds']! as List<Object?>;
      if (rawQuestionIds.any((item) => item is! String)) {
        throw const VaultFormatException();
      }
      _validateQuestionIds(rawQuestionIds.cast<String>(), formatFailure: true);
      return VaultRecoverySlot(
        binding: VaultRecoveryBinding.fromJson(value['binding']),
        questionIds: rawQuestionIds.cast<String>(),
        entryMode: VaultRecoveryEntryMode.fromStorage(value['entryMode']),
        kdf: VaultRecoveryKdfParameters.fromJson(
          value['kdf'],
          supportedProfiles: supportedKdfProfiles,
        ),
        salt: _decodeFixedBytes(value['salt'], _recoverySaltLength),
        wrappedDataKey: _decodeBox(value['wrappedDataKey']),
      );
    } on VaultUnsupportedKdfProfileException {
      rethrow;
    } on VaultFormatException {
      rethrow;
    } on Object {
      throw const VaultFormatException();
    }
  }

  final VaultRecoveryBinding binding;
  final List<String> questionIds;
  final VaultRecoveryEntryMode entryMode;
  final VaultRecoveryKdfParameters kdf;
  final Uint8List _salt;
  final SecretBox wrappedDataKey;

  Uint8List get salt => Uint8List.fromList(_salt);

  VaultRecoveryChallenge get challenge => VaultRecoveryChallenge(
    binding: binding,
    questionIds: questionIds,
    entryMode: entryMode,
  );

  void validate() {
    binding.validate();
    kdf.validate();
    _validateQuestionIds(questionIds);
    if (_salt.length != _recoverySaltLength ||
        wrappedDataKey.cipherText.length != _recoveryDataKeyLength ||
        wrappedDataKey.nonce.length != _recoveryNonceLength ||
        wrappedDataKey.mac.bytes.length != _recoveryMacLength) {
      throw const VaultFormatException();
    }
  }

  List<int> wrappingAad() {
    final encodedQuestionIds = base64Encode(
      _serializeLengthPrefixed(questionIds),
    );
    return utf8.encode(
      'ASM_LOCAL_VAULT|2|recovery-slot|$_recoverySlotVersion|'
      '${base64Encode(binding._vaultInstanceId)}|'
      '${base64Encode(binding._slotId)}|'
      '${base64Encode(binding._deviceBindingId)}|'
      '${entryMode.storageValue}|$_recoveryNormalization|'
      '$encodedQuestionIds|$_recoveryArgon2Name|19|${kdf.memoryKiB}|'
      '${kdf.iterations}|${kdf.parallelism}|${kdf.hashLength}|'
      '${base64Encode(_salt)}|$_recoveryAesName|wrapped-data-key',
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': _recoverySlotVersion,
    'binding': binding.toJson(),
    'entryMode': entryMode.storageValue,
    'normalization': _recoveryNormalization,
    'questionIds': questionIds,
    'kdf': kdf.toJson(),
    'salt': base64Encode(_salt),
    'wrappedDataKey': _encodeBox(wrappedDataKey),
  };
}

final class VaultRecoveryCrypto {
  VaultRecoveryCrypto({AesGcm? cipher})
    : _cipher = cipher ?? AesGcm.with256bits();

  final AesGcm _cipher;

  Future<VaultRecoverySlot> createSlot({
    required VaultRecoveryBinding binding,
    required SecretKeyData dataKey,
    required List<String> questionIds,
    required List<String> answers,
    required Uint8List deviceSecret,
    required VaultRecoveryEntryMode entryMode,
    VaultRecoveryKdfParameters kdf = VaultRecoveryKdfParameters.production,
  }) async {
    binding.validate();
    kdf.validate();
    _validateQuestionIds(questionIds);
    _validateAnswers(answers);
    _validateDeviceSecret(deviceSecret);
    if (dataKey.hasBeenDestroyed ||
        dataKey.bytes.length != _recoveryDataKeyLength) {
      throw const VaultClosedException();
    }

    final salt = _randomBytes(_recoverySaltLength);
    final header = VaultRecoverySlot(
      binding: binding,
      questionIds: questionIds,
      entryMode: entryMode,
      kdf: kdf,
      salt: salt,
      wrappedDataKey: SecretBox(
        Uint8List(_recoveryDataKeyLength),
        nonce: Uint8List(_recoveryNonceLength),
        mac: Mac(Uint8List(_recoveryMacLength)),
      ),
    );
    SecretKeyData? recoveryKey;
    try {
      recoveryKey = await _deriveRecoveryKey(
        binding: binding,
        questionIds: questionIds,
        answers: answers,
        deviceSecret: deviceSecret,
        salt: salt,
        kdf: kdf,
      );
      final wrappedDataKey = await _cipher.encrypt(
        dataKey.bytes,
        secretKey: recoveryKey,
        nonce: _cipher.newNonce(),
        aad: header.wrappingAad(),
      );
      return VaultRecoverySlot(
        binding: binding,
        questionIds: questionIds,
        entryMode: entryMode,
        kdf: kdf,
        salt: salt,
        wrappedDataKey: wrappedDataKey,
      );
    } finally {
      recoveryKey?.destroy();
    }
  }

  Future<SecretKeyData> unwrapDataKey({
    required VaultRecoverySlot slot,
    required List<String> answers,
    required Uint8List deviceSecret,
  }) async {
    slot.validate();
    try {
      _validateAnswers(answers);
      _validateDeviceSecret(deviceSecret);
    } on ArgumentError {
      throw const VaultRecoveryRejectedException();
    }
    SecretKeyData? recoveryKey;
    List<int>? clearDataKey;
    try {
      recoveryKey = await _deriveRecoveryKey(
        binding: slot.binding,
        questionIds: slot.questionIds,
        answers: answers,
        deviceSecret: deviceSecret,
        salt: slot._salt,
        kdf: slot.kdf,
      );
      try {
        clearDataKey = await _cipher.decrypt(
          slot.wrappedDataKey,
          secretKey: recoveryKey,
          aad: slot.wrappingAad(),
        );
      } on SecretBoxAuthenticationError {
        throw const VaultRecoveryRejectedException();
      }
      if (clearDataKey.length != _recoveryDataKeyLength) {
        throw const VaultRecoveryRejectedException();
      }
      return SecretKeyData(
        Uint8List.fromList(clearDataKey),
        overwriteWhenDestroyed: true,
      );
    } finally {
      recoveryKey?.destroy();
      _erase(clearDataKey);
    }
  }

  /// 为不存在或不符合入口条件的路由分支执行一次等价 Argon2id + AEAD 路径。
  /// 该操作永远拒绝且不写入任何持久状态。
  Future<void> performDummyVerification({
    required List<String> questionIds,
    required List<String> answers,
    required Uint8List deviceSecret,
    VaultRecoveryKdfParameters kdf = VaultRecoveryKdfParameters.production,
  }) async {
    _validateQuestionIds(questionIds);
    _validateAnswers(answers);
    _validateDeviceSecret(deviceSecret);
    final dummySlot = VaultRecoverySlot(
      binding: VaultRecoveryBinding.random(),
      questionIds: questionIds,
      entryMode: VaultRecoveryEntryMode.visible,
      kdf: kdf,
      salt: _randomBytes(_recoverySaltLength),
      wrappedDataKey: SecretBox(
        _randomBytes(_recoveryDataKeyLength),
        nonce: _randomBytes(_recoveryNonceLength),
        mac: Mac(_randomBytes(_recoveryMacLength)),
      ),
    );
    try {
      final unexpected = await unwrapDataKey(
        slot: dummySlot,
        answers: answers,
        deviceSecret: deviceSecret,
      );
      unexpected.destroy();
      throw StateError('dummy recovery authentication unexpectedly succeeded');
    } on VaultRecoveryRejectedException {
      // 随机认证标签必然拒绝。
    }
  }

  Future<VaultRecoverySlot> rewrapDataKey({
    required VaultRecoverySlot previous,
    required SecretKeyData newDataKey,
    required List<String> answers,
    required Uint8List deviceSecret,
  }) async {
    final verifiedOldDataKey = await unwrapDataKey(
      slot: previous,
      answers: answers,
      deviceSecret: deviceSecret,
    );
    verifiedOldDataKey.destroy();
    return createSlot(
      binding: previous.binding,
      dataKey: newDataKey,
      questionIds: previous.questionIds,
      answers: answers,
      deviceSecret: deviceSecret,
      entryMode: previous.entryMode,
      kdf: previous.kdf,
    );
  }

  Future<SecretKeyData> _deriveRecoveryKey({
    required VaultRecoveryBinding binding,
    required List<String> questionIds,
    required List<String> answers,
    required Uint8List deviceSecret,
    required List<int> salt,
    required VaultRecoveryKdfParameters kdf,
  }) async {
    final answerInput = _serializeAnswers(questionIds, answers);
    final answerInputKey = SecretKeyData(
      answerInput,
      overwriteWhenDestroyed: true,
    );
    SecretKey? argonKey;
    SecretKeyData? extractedArgonKey;
    SecretKeyData? hkdfInputKey;
    SecretKey? hkdfKey;
    SecretKeyData? extractedHkdfKey;
    final combined = Uint8List(64);
    final hkdfSalt = binding.hkdfSalt();
    try {
      argonKey = await Argon2id(
        memory: kdf.memoryKiB,
        iterations: kdf.iterations,
        parallelism: kdf.parallelism,
        hashLength: kdf.hashLength,
      ).deriveKey(secretKey: answerInputKey, nonce: salt);
      extractedArgonKey = await argonKey.extract();
      combined.setRange(0, 32, extractedArgonKey.bytes);
      combined.setRange(32, 64, deviceSecret);
      hkdfInputKey = SecretKeyData(combined, overwriteWhenDestroyed: true);
      hkdfKey = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: hkdfInputKey,
        nonce: hkdfSalt,
        info: utf8.encode(_recoveryHkdfInfo),
      );
      extractedHkdfKey = await hkdfKey.extract();
      return SecretKeyData(
        Uint8List.fromList(extractedHkdfKey.bytes),
        overwriteWhenDestroyed: true,
      );
    } finally {
      answerInputKey.destroy();
      if (!identical(extractedArgonKey, argonKey)) {
        extractedArgonKey?.destroy();
      }
      argonKey?.destroy();
      hkdfInputKey?.destroy();
      if (!identical(extractedHkdfKey, hkdfKey)) {
        extractedHkdfKey?.destroy();
      }
      hkdfKey?.destroy();
      _erase(combined);
      _erase(hkdfSalt);
    }
  }
}

String normalizeVaultRecoveryAnswer(String answer) => unorm
    .nfkc(answer)
    .trim()
    .replaceAll(RegExp(r'\s+', unicode: true), ' ')
    .toLowerCase();

Uint8List _serializeAnswers(List<String> questionIds, List<String> answers) {
  _validateQuestionIds(questionIds);
  _validateAnswers(answers);
  final normalizedAnswers = answers
      .map(normalizeVaultRecoveryAnswer)
      .toList(growable: false);
  if (normalizedAnswers.any((answer) => answer.isEmpty)) {
    throw ArgumentError('recovery answers cannot be blank');
  }
  return _serializeLengthPrefixed(<String>[
    'ASM_LOCAL_VAULT_RECOVERY_ANSWERS_V1',
    ...<String>[
      for (var index = 0; index < questionIds.length; index++) ...<String>[
        questionIds[index],
        normalizedAnswers[index],
      ],
    ],
  ]);
}

Uint8List _serializeLengthPrefixed(List<String> values) {
  final output = BytesBuilder(copy: false);
  final count = ByteData(4)..setUint32(0, values.length, Endian.big);
  output.add(count.buffer.asUint8List());
  for (final value in values) {
    final encoded = utf8.encode(value);
    final length = ByteData(4)..setUint32(0, encoded.length, Endian.big);
    output
      ..add(length.buffer.asUint8List())
      ..add(encoded);
  }
  return output.takeBytes();
}

void _validateQuestionIds(
  List<String> questionIds, {
  bool formatFailure = false,
}) {
  final pattern = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');
  if (questionIds.length != 3 ||
      questionIds.toSet().length != 3 ||
      questionIds.any(
        (id) =>
            !pattern.hasMatch(id) || !VaultRecoveryQuestionCatalog.contains(id),
      )) {
    if (formatFailure) {
      throw const VaultFormatException();
    }
    throw ArgumentError(
      'exactly three distinct recovery question IDs required',
    );
  }
}

void _validateAnswers(List<String> answers) {
  if (answers.length != 3 ||
      answers.any(
        (answer) =>
            answer.runes.length > 256 ||
            normalizeVaultRecoveryAnswer(answer).isEmpty,
      )) {
    throw ArgumentError('exactly three bounded recovery answers required');
  }
}

void _validateDeviceSecret(Uint8List deviceSecret) {
  if (deviceSecret.length != _recoveryDeviceSecretLength) {
    throw ArgumentError('deviceSecret must contain exactly 32 bytes');
  }
}

Uint8List _randomBytes(int length) {
  final source = SecretKeyData.random(length: length);
  try {
    return Uint8List.fromList(source.bytes);
  } finally {
    source.destroy();
  }
}

Uint8List _decodeFixedBytes(Object? value, int expectedLength) {
  if (value is! String || value.length > 128) {
    throw const VaultFormatException();
  }
  final decoded = Uint8List.fromList(base64Decode(value));
  if (decoded.length != expectedLength) {
    throw const VaultFormatException();
  }
  return decoded;
}

SecretBox _decodeBox(Object? value) {
  if (value is! Map<Object?, Object?> ||
      value['cipher'] != _recoveryAesName ||
      value['box'] is! String) {
    throw const VaultFormatException();
  }
  final encoded = value['box']! as String;
  if (encoded.length > 256) {
    throw const VaultFormatException();
  }
  final concatenated = base64Decode(encoded);
  if (concatenated.length !=
      _recoveryNonceLength + _recoveryDataKeyLength + _recoveryMacLength) {
    throw const VaultFormatException();
  }
  return SecretBox.fromConcatenation(
    concatenated,
    nonceLength: _recoveryNonceLength,
    macLength: _recoveryMacLength,
    copy: true,
  );
}

Map<String, Object?> _encodeBox(SecretBox box) => <String, Object?>{
  'cipher': _recoveryAesName,
  'box': base64Encode(box.concatenation()),
};

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

void _erase(List<int>? bytes) {
  if (bytes == null) {
    return;
  }
  try {
    bytes.fillRange(0, bytes.length, 0);
  } on UnsupportedError {
    // Some platform implementations return immutable buffers.
  }
}
