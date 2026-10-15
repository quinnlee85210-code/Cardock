import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'temporary_web_algorithms.dart';
import 'temporary_web_crypto.dart';

const int trustedLanConnectionCodeEntropyBytes = 8;
const int trustedLanConnectionCodeSymbols = 8;
const int trustedLanPairingPublicKeyLength = 32;
const int trustedLanKeyConfirmationLength = 32;

const String _connectionCodeAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// An eight-letter, one-time connection code for a user-trusted hotspot or LAN.
///
/// The code contains uppercase English letters only and is consumed by a
/// one-shot pairing attempt. It is never used as a password KDF input.
///
/// Security boundary: this protocol deliberately says `TrustedLan`. An active
/// attacker that can replace the HTTP-delivered browser page can read the code
/// as the user types it and then intercept plaintext. Use this only on the
/// user's own hotspot or another trusted private network; it is not a PAKE and
/// must not be represented as hostile-network or public-Wi-Fi protection.
final class TrustedLanConnectionCode {
  TrustedLanConnectionCode._(Uint8List bytes)
    : _bytes = Uint8List.fromList(bytes);

  factory TrustedLanConnectionCode.generate() {
    final random = Random.secure();
    final bytes = Uint8List(trustedLanConnectionCodeEntropyBytes);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _connectionCodeAlphabet.codeUnitAt(
        random.nextInt(_connectionCodeAlphabet.length),
      );
    }
    try {
      return TrustedLanConnectionCode._(bytes);
    } finally {
      _erasePairingBytes(bytes);
    }
  }

  factory TrustedLanConnectionCode.parse(String input) {
    final normalized = input.trim().toUpperCase().replaceAll(
      RegExp(r'[\s-]'),
      '',
    );
    if (normalized.length != trustedLanConnectionCodeSymbols) {
      throw const FormatException(
        'Trusted-LAN connection code must contain 8 uppercase letters.',
      );
    }
    final decoded = Uint8List.fromList(normalized.codeUnits);
    for (final byte in decoded) {
      if (!_connectionCodeAlphabet.contains(String.fromCharCode(byte))) {
        _erasePairingBytes(decoded);
        throw const FormatException(
          'Trusted-LAN connection code contains an invalid symbol.',
        );
      }
    }
    try {
      return TrustedLanConnectionCode._(decoded);
    } finally {
      _erasePairingBytes(decoded);
    }
  }

  final Uint8List _bytes;
  bool _destroyed = false;

  String get compact {
    _ensureAvailable();
    return _encodeConnectionCode(_bytes);
  }

  String get formatted => compact;

  Uint8List extractBytes() {
    _ensureAvailable();
    return Uint8List.fromList(_bytes);
  }

  void destroy() {
    if (_destroyed) {
      return;
    }
    _destroyed = true;
    _erasePairingBytes(_bytes);
  }

  void _ensureAvailable() {
    if (_destroyed) {
      throw StateError('Trusted-LAN connection code has been destroyed.');
    }
  }

  @override
  String toString() => 'TrustedLanConnectionCode(redacted)';
}

enum TrustedLanPairingFailure {
  alreadyUsed,
  cancelled,
  invalidConnectionCode,
  protocolMismatch,
  sessionMismatch,
  keyAgreementFailed,
  keyConfirmationFailed,
}

final class TrustedLanPairingException implements Exception {
  const TrustedLanPairingException(this.failure);

  final TrustedLanPairingFailure failure;

  @override
  String toString() => 'TrustedLanPairingException(${failure.name})';
}

/// Phone-to-browser public handshake data.
final class TrustedLanPhoneHello {
  TrustedLanPhoneHello({
    required this.protocolVersion,
    required List<int> sessionId,
    required List<int> phonePublicKey,
    required List<int> phoneToBrowserNoncePrefix,
    required List<int> browserToPhoneNoncePrefix,
  }) : _sessionId = _pairingExactCopy(
         sessionId,
         trustedLanSessionIdLength,
         'sessionId',
       ),
       _phonePublicKey = _pairingExactCopy(
         phonePublicKey,
         trustedLanPairingPublicKeyLength,
         'phonePublicKey',
       ),
       _phoneToBrowserNoncePrefix = _pairingExactCopy(
         phoneToBrowserNoncePrefix,
         trustedLanNoncePrefixLength,
         'phoneToBrowserNoncePrefix',
       ),
       _browserToPhoneNoncePrefix = _pairingExactCopy(
         browserToPhoneNoncePrefix,
         trustedLanNoncePrefixLength,
         'browserToPhoneNoncePrefix',
       );

  factory TrustedLanPhoneHello.fromJson(Map<String, Object?> json) {
    return TrustedLanPhoneHello(
      protocolVersion: _pairingRequiredString(json, 'v'),
      sessionId: _pairingDecode(
        _pairingRequiredString(json, 'sid'),
        trustedLanSessionIdLength,
        'sid',
      ),
      phonePublicKey: _pairingDecode(
        _pairingRequiredString(json, 'phoneKey'),
        trustedLanPairingPublicKeyLength,
        'phoneKey',
      ),
      phoneToBrowserNoncePrefix: _pairingDecode(
        _pairingRequiredString(json, 'p2bNonce'),
        trustedLanNoncePrefixLength,
        'p2bNonce',
      ),
      browserToPhoneNoncePrefix: _pairingDecode(
        _pairingRequiredString(json, 'b2pNonce'),
        trustedLanNoncePrefixLength,
        'b2pNonce',
      ),
    );
  }

  final String protocolVersion;
  final Uint8List _sessionId;
  final Uint8List _phonePublicKey;
  final Uint8List _phoneToBrowserNoncePrefix;
  final Uint8List _browserToPhoneNoncePrefix;

  Uint8List get sessionId => Uint8List.fromList(_sessionId);
  Uint8List get phonePublicKey => Uint8List.fromList(_phonePublicKey);
  Uint8List get phoneToBrowserNoncePrefix =>
      Uint8List.fromList(_phoneToBrowserNoncePrefix);
  Uint8List get browserToPhoneNoncePrefix =>
      Uint8List.fromList(_browserToPhoneNoncePrefix);

  Map<String, Object?> toJson() => <String, Object?>{
    'v': protocolVersion,
    'sid': _pairingEncode(_sessionId),
    'phoneKey': _pairingEncode(_phonePublicKey),
    'p2bNonce': _pairingEncode(_phoneToBrowserNoncePrefix),
    'b2pNonce': _pairingEncode(_browserToPhoneNoncePrefix),
  };
}

/// Browser-to-phone public key plus browser key confirmation.
final class TrustedLanBrowserHello {
  TrustedLanBrowserHello({
    required this.protocolVersion,
    required List<int> sessionId,
    required List<int> browserPublicKey,
    required List<int> browserConfirmation,
  }) : _sessionId = _pairingExactCopy(
         sessionId,
         trustedLanSessionIdLength,
         'sessionId',
       ),
       _browserPublicKey = _pairingExactCopy(
         browserPublicKey,
         trustedLanPairingPublicKeyLength,
         'browserPublicKey',
       ),
       _browserConfirmation = _pairingExactCopy(
         browserConfirmation,
         trustedLanKeyConfirmationLength,
         'browserConfirmation',
       );

  factory TrustedLanBrowserHello.fromJson(Map<String, Object?> json) {
    return TrustedLanBrowserHello(
      protocolVersion: _pairingRequiredString(json, 'v'),
      sessionId: _pairingDecode(
        _pairingRequiredString(json, 'sid'),
        trustedLanSessionIdLength,
        'sid',
      ),
      browserPublicKey: _pairingDecode(
        _pairingRequiredString(json, 'browserKey'),
        trustedLanPairingPublicKeyLength,
        'browserKey',
      ),
      browserConfirmation: _pairingDecode(
        _pairingRequiredString(json, 'browserConfirm'),
        trustedLanKeyConfirmationLength,
        'browserConfirm',
      ),
    );
  }

  final String protocolVersion;
  final Uint8List _sessionId;
  final Uint8List _browserPublicKey;
  final Uint8List _browserConfirmation;

  Uint8List get sessionId => Uint8List.fromList(_sessionId);
  Uint8List get browserPublicKey => Uint8List.fromList(_browserPublicKey);
  Uint8List get browserConfirmation => Uint8List.fromList(_browserConfirmation);

  Map<String, Object?> toJson() => <String, Object?>{
    'v': protocolVersion,
    'sid': _pairingEncode(_sessionId),
    'browserKey': _pairingEncode(_browserPublicKey),
    'browserConfirm': _pairingEncode(_browserConfirmation),
  };
}

/// Phone-to-browser key confirmation that completes mutual confirmation.
final class TrustedLanPhoneConfirmation {
  TrustedLanPhoneConfirmation({
    required this.protocolVersion,
    required List<int> sessionId,
    required List<int> confirmation,
  }) : _sessionId = _pairingExactCopy(
         sessionId,
         trustedLanSessionIdLength,
         'sessionId',
       ),
       _confirmation = _pairingExactCopy(
         confirmation,
         trustedLanKeyConfirmationLength,
         'confirmation',
       );

  factory TrustedLanPhoneConfirmation.fromJson(Map<String, Object?> json) {
    return TrustedLanPhoneConfirmation(
      protocolVersion: _pairingRequiredString(json, 'v'),
      sessionId: _pairingDecode(
        _pairingRequiredString(json, 'sid'),
        trustedLanSessionIdLength,
        'sid',
      ),
      confirmation: _pairingDecode(
        _pairingRequiredString(json, 'phoneConfirm'),
        trustedLanKeyConfirmationLength,
        'phoneConfirm',
      ),
    );
  }

  final String protocolVersion;
  final Uint8List _sessionId;
  final Uint8List _confirmation;

  Uint8List get sessionId => Uint8List.fromList(_sessionId);
  Uint8List get confirmation => Uint8List.fromList(_confirmation);

  Map<String, Object?> toJson() => <String, Object?>{
    'v': protocolVersion,
    'sid': _pairingEncode(_sessionId),
    'phoneConfirm': _pairingEncode(_confirmation),
  };
}

final class TrustedLanPhonePairingResult {
  const TrustedLanPhonePairingResult({
    required this.confirmation,
    required this.channel,
  });

  final TrustedLanPhoneConfirmation confirmation;
  final TrustedLanSecureChannel channel;
}

/// One-shot phone-side X25519 handshake for a trusted private network.
final class TrustedLanPhonePairing {
  TrustedLanPhonePairing._({
    required this._algorithm,
    required this._keyPair,
    required this._hello,
    required this._connectionCode,
  });

  static Future<TrustedLanPhonePairing> start() async {
    final algorithm = trustedLanX25519();
    final keyPair = await algorithm.newKeyPair();
    try {
      final publicKey = await keyPair.extractPublicKey();
      final code = TrustedLanConnectionCode.generate();
      final codeBytes = code.extractBytes();
      code.destroy();
      final hello = TrustedLanPhoneHello(
        protocolVersion: trustedLanProtocolVersion,
        sessionId: _secureRandomBytes(trustedLanSessionIdLength),
        phonePublicKey: publicKey.bytes,
        phoneToBrowserNoncePrefix: _secureRandomBytes(
          trustedLanNoncePrefixLength,
        ),
        browserToPhoneNoncePrefix: _secureRandomBytes(
          trustedLanNoncePrefixLength,
        ),
      );
      return TrustedLanPhonePairing._(
        algorithm: algorithm,
        keyPair: keyPair,
        hello: hello,
        connectionCode: codeBytes,
      );
    } catch (_) {
      keyPair.destroy();
      rethrow;
    }
  }

  final X25519 _algorithm;
  final SimpleKeyPair _keyPair;
  final TrustedLanPhoneHello _hello;
  final Uint8List _connectionCode;
  bool _used = false;
  bool _cancelled = false;

  TrustedLanPhoneHello get hello => _hello;

  String get formattedConnectionCode {
    _ensurePending();
    return _formatConnectionCode(_connectionCode);
  }

  Future<TrustedLanPhonePairingResult> finish(
    TrustedLanBrowserHello browserHello,
  ) async {
    _ensurePending();
    _used = true;
    _TrustedLanDerivedMaterial? material;
    try {
      _validateProtocol(browserHello.protocolVersion);
      if (!_pairingConstantTimeEquals(
        browserHello._sessionId,
        _hello._sessionId,
      )) {
        throw const TrustedLanPairingException(
          TrustedLanPairingFailure.sessionMismatch,
        );
      }
      final transcriptHash = await _pairingTranscriptHash(
        phoneHello: _hello,
        browserPublicKey: browserHello._browserPublicKey,
      );
      try {
        material = await _deriveTrustedLanMaterial(
          algorithm: _algorithm,
          localKeyPair: _keyPair,
          remotePublicKey: browserHello._browserPublicKey,
          connectionCode: _connectionCode,
          transcriptHash: transcriptHash,
        );
      } finally {
        _erasePairingBytes(transcriptHash);
      }
      final expectedBrowserConfirmation = await material.confirmationFor(
        TrustedLanEndpointRole.browser,
      );
      try {
        if (Mac(expectedBrowserConfirmation) !=
            Mac(browserHello._browserConfirmation)) {
          throw const TrustedLanPairingException(
            TrustedLanPairingFailure.keyConfirmationFailed,
          );
        }
      } finally {
        _erasePairingBytes(expectedBrowserConfirmation);
      }
      final phoneConfirmation = await material.confirmationFor(
        TrustedLanEndpointRole.phone,
      );
      final channel = material.createChannel(
        role: TrustedLanEndpointRole.phone,
        phoneHello: _hello,
      );
      return TrustedLanPhonePairingResult(
        confirmation: TrustedLanPhoneConfirmation(
          protocolVersion: trustedLanProtocolVersion,
          sessionId: _hello._sessionId,
          confirmation: phoneConfirmation,
        ),
        channel: channel,
      );
    } finally {
      material?.destroy();
      _keyPair.destroy();
      _erasePairingBytes(_connectionCode);
    }
  }

  void cancel() {
    if (_used) {
      return;
    }
    _used = true;
    _cancelled = true;
    _keyPair.destroy();
    _erasePairingBytes(_connectionCode);
  }

  void _ensurePending() {
    if (_cancelled) {
      throw const TrustedLanPairingException(
        TrustedLanPairingFailure.cancelled,
      );
    }
    if (_used) {
      throw const TrustedLanPairingException(
        TrustedLanPairingFailure.alreadyUsed,
      );
    }
  }
}

/// One-shot browser-side X25519 handshake for a trusted private network.
final class TrustedLanBrowserPairing {
  TrustedLanBrowserPairing._({
    required this._phoneHello,
    required this._hello,
    required this._material,
  });

  static Future<TrustedLanBrowserPairing> start({
    required TrustedLanPhoneHello phoneHello,
    required String connectionCode,
  }) async {
    _validateProtocol(phoneHello.protocolVersion);
    late TrustedLanConnectionCode parsedCode;
    try {
      parsedCode = TrustedLanConnectionCode.parse(connectionCode);
    } on FormatException {
      throw const TrustedLanPairingException(
        TrustedLanPairingFailure.invalidConnectionCode,
      );
    }
    final codeBytes = parsedCode.extractBytes();
    parsedCode.destroy();
    final algorithm = trustedLanX25519();
    final keyPair = await algorithm.newKeyPair();
    _TrustedLanDerivedMaterial? material;
    try {
      final publicKey = await keyPair.extractPublicKey();
      final transcriptHash = await _pairingTranscriptHash(
        phoneHello: phoneHello,
        browserPublicKey: publicKey.bytes,
      );
      try {
        material = await _deriveTrustedLanMaterial(
          algorithm: algorithm,
          localKeyPair: keyPair,
          remotePublicKey: phoneHello._phonePublicKey,
          connectionCode: codeBytes,
          transcriptHash: transcriptHash,
        );
      } finally {
        _erasePairingBytes(transcriptHash);
      }
      final browserConfirmation = await material.confirmationFor(
        TrustedLanEndpointRole.browser,
      );
      return TrustedLanBrowserPairing._(
        phoneHello: phoneHello,
        hello: TrustedLanBrowserHello(
          protocolVersion: trustedLanProtocolVersion,
          sessionId: phoneHello._sessionId,
          browserPublicKey: publicKey.bytes,
          browserConfirmation: browserConfirmation,
        ),
        material: material,
      );
    } catch (_) {
      material?.destroy();
      rethrow;
    } finally {
      keyPair.destroy();
      _erasePairingBytes(codeBytes);
    }
  }

  final TrustedLanPhoneHello _phoneHello;
  final TrustedLanBrowserHello _hello;
  final _TrustedLanDerivedMaterial _material;
  bool _used = false;
  bool _cancelled = false;

  TrustedLanBrowserHello get hello => _hello;

  Future<TrustedLanSecureChannel> finish(
    TrustedLanPhoneConfirmation phoneConfirmation,
  ) async {
    _ensurePending();
    _used = true;
    try {
      _validateProtocol(phoneConfirmation.protocolVersion);
      if (!_pairingConstantTimeEquals(
        phoneConfirmation._sessionId,
        _phoneHello._sessionId,
      )) {
        throw const TrustedLanPairingException(
          TrustedLanPairingFailure.sessionMismatch,
        );
      }
      final expectedPhoneConfirmation = await _material.confirmationFor(
        TrustedLanEndpointRole.phone,
      );
      try {
        if (Mac(expectedPhoneConfirmation) !=
            Mac(phoneConfirmation._confirmation)) {
          throw const TrustedLanPairingException(
            TrustedLanPairingFailure.keyConfirmationFailed,
          );
        }
      } finally {
        _erasePairingBytes(expectedPhoneConfirmation);
      }
      return _material.createChannel(
        role: TrustedLanEndpointRole.browser,
        phoneHello: _phoneHello,
      );
    } finally {
      _material.destroy();
    }
  }

  void cancel() {
    if (_used) {
      return;
    }
    _used = true;
    _cancelled = true;
    _material.destroy();
  }

  void _ensurePending() {
    if (_cancelled) {
      throw const TrustedLanPairingException(
        TrustedLanPairingFailure.cancelled,
      );
    }
    if (_used) {
      throw const TrustedLanPairingException(
        TrustedLanPairingFailure.alreadyUsed,
      );
    }
  }
}

final class _TrustedLanDerivedMaterial {
  _TrustedLanDerivedMaterial({
    required List<int> transcriptHash,
    required List<int> phoneToBrowserKey,
    required List<int> browserToPhoneKey,
    required List<int> phoneConfirmationKey,
    required List<int> browserConfirmationKey,
  }) : _transcriptHash = Uint8List.fromList(transcriptHash),
       _phoneToBrowserKey = Uint8List.fromList(phoneToBrowserKey),
       _browserToPhoneKey = Uint8List.fromList(browserToPhoneKey),
       _phoneConfirmationKey = Uint8List.fromList(phoneConfirmationKey),
       _browserConfirmationKey = Uint8List.fromList(browserConfirmationKey);

  final Uint8List _transcriptHash;
  final Uint8List _phoneToBrowserKey;
  final Uint8List _browserToPhoneKey;
  final Uint8List _phoneConfirmationKey;
  final Uint8List _browserConfirmationKey;
  bool _destroyed = false;

  Future<Uint8List> confirmationFor(TrustedLanEndpointRole role) async {
    _ensureAvailable();
    final keyBytes = role == TrustedLanEndpointRole.phone
        ? _phoneConfirmationKey
        : _browserConfirmationKey;
    final key = SecretKeyData(
      Uint8List.fromList(keyBytes),
      overwriteWhenDestroyed: true,
    );
    final input = BytesBuilder(copy: false)
      ..add(utf8.encode('cardock/trusted-lan/key-confirmation'))
      ..addByte(0)
      ..add(_transcriptHash)
      ..addByte(role == TrustedLanEndpointRole.phone ? 1 : 2);
    try {
      final mac = await trustedLanHmacSha256().calculateMac(
        input.takeBytes(),
        secretKey: key,
      );
      return Uint8List.fromList(mac.bytes);
    } finally {
      key.destroy();
    }
  }

  TrustedLanSecureChannel createChannel({
    required TrustedLanEndpointRole role,
    required TrustedLanPhoneHello phoneHello,
  }) {
    _ensureAvailable();
    return TrustedLanSecureChannel.fromTrustedLanPairing(
      role: role,
      sessionId: phoneHello._sessionId,
      phoneToBrowserKey: _phoneToBrowserKey,
      browserToPhoneKey: _browserToPhoneKey,
      phoneToBrowserNoncePrefix: phoneHello._phoneToBrowserNoncePrefix,
      browserToPhoneNoncePrefix: phoneHello._browserToPhoneNoncePrefix,
    );
  }

  void destroy() {
    if (_destroyed) {
      return;
    }
    _destroyed = true;
    _erasePairingBytes(_transcriptHash);
    _erasePairingBytes(_phoneToBrowserKey);
    _erasePairingBytes(_browserToPhoneKey);
    _erasePairingBytes(_phoneConfirmationKey);
    _erasePairingBytes(_browserConfirmationKey);
  }

  void _ensureAvailable() {
    if (_destroyed) {
      throw StateError('Trusted-LAN pairing material has been destroyed.');
    }
  }
}

Future<_TrustedLanDerivedMaterial> _deriveTrustedLanMaterial({
  required X25519 algorithm,
  required SimpleKeyPair localKeyPair,
  required List<int> remotePublicKey,
  required List<int> connectionCode,
  required List<int> transcriptHash,
}) async {
  if (remotePublicKey.length != trustedLanPairingPublicKeyLength ||
      connectionCode.length != trustedLanConnectionCodeEntropyBytes ||
      transcriptHash.length != 32) {
    throw const TrustedLanPairingException(
      TrustedLanPairingFailure.keyAgreementFailed,
    );
  }
  SecretKey? sharedSecret;
  SecretKeyData? extractedSharedSecret;
  final sharedSecretBytes = Uint8List(trustedLanPairingPublicKeyLength);
  final masterBytes = Uint8List(
    trustedLanPairingPublicKeyLength + trustedLanConnectionCodeEntropyBytes,
  );
  SecretKeyData? masterKey;
  SecretKeyData? derivedKey;
  Uint8List? derivedBytes;
  try {
    sharedSecret = await algorithm.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: SimplePublicKey(
        remotePublicKey,
        type: KeyPairType.x25519,
      ),
    );
    extractedSharedSecret = await sharedSecret.extract();
    sharedSecretBytes.setAll(0, extractedSharedSecret.bytes);
    var combined = 0;
    for (final byte in sharedSecretBytes) {
      combined |= byte;
    }
    if (combined == 0) {
      throw const TrustedLanPairingException(
        TrustedLanPairingFailure.keyAgreementFailed,
      );
    }

    // Fixed-length IKM: X25519 shared secret (32 bytes) || one-time code
    // (8 bytes). The transcript hash is the HKDF salt, binding both public
    // keys, the session, direction nonce prefixes, and protocol version.
    masterBytes.setRange(0, sharedSecretBytes.length, sharedSecretBytes);
    masterBytes.setRange(
      sharedSecretBytes.length,
      masterBytes.length,
      connectionCode,
    );
    masterKey = SecretKeyData(masterBytes, overwriteWhenDestroyed: true);
    derivedKey =
        await trustedLanHkdfSha256(
          outputLength: 4 * trustedLanAesKeyLength,
        ).deriveKey(
          secretKey: masterKey,
          nonce: transcriptHash,
          info: utf8.encode('cardock/trusted-lan/key-schedule-v1'),
        );
    derivedBytes = Uint8List.fromList(derivedKey.bytes);
    return _TrustedLanDerivedMaterial(
      transcriptHash: transcriptHash,
      phoneToBrowserKey: derivedBytes.sublist(0, 32),
      browserToPhoneKey: derivedBytes.sublist(32, 64),
      phoneConfirmationKey: derivedBytes.sublist(64, 96),
      browserConfirmationKey: derivedBytes.sublist(96, 128),
    );
  } on TrustedLanPairingException {
    rethrow;
  } on ArgumentError {
    throw const TrustedLanPairingException(
      TrustedLanPairingFailure.keyAgreementFailed,
    );
  } finally {
    if (extractedSharedSecret != null &&
        !identical(extractedSharedSecret, sharedSecret)) {
      extractedSharedSecret.destroy();
    }
    sharedSecret?.destroy();
    masterKey?.destroy();
    derivedKey?.destroy();
    _erasePairingBytes(sharedSecretBytes);
    _erasePairingBytes(masterBytes);
    if (derivedBytes != null) {
      _erasePairingBytes(derivedBytes);
    }
  }
}

Future<Uint8List> _pairingTranscriptHash({
  required TrustedLanPhoneHello phoneHello,
  required List<int> browserPublicKey,
}) async {
  if (browserPublicKey.length != trustedLanPairingPublicKeyLength) {
    throw const TrustedLanPairingException(
      TrustedLanPairingFailure.keyAgreementFailed,
    );
  }
  final domain = utf8.encode('cardock/trusted-lan/pairing-transcript');
  final version = utf8.encode(phoneHello.protocolVersion);
  final transcript = BytesBuilder(copy: false)
    ..addByte(domain.length)
    ..add(domain)
    ..addByte(version.length)
    ..add(version)
    ..add(phoneHello._sessionId)
    ..add(phoneHello._phonePublicKey)
    ..add(browserPublicKey)
    ..add(phoneHello._phoneToBrowserNoncePrefix)
    ..add(phoneHello._browserToPhoneNoncePrefix);
  final transcriptBytes = transcript.takeBytes();
  try {
    final hash = await trustedLanSha256().hash(transcriptBytes);
    return Uint8List.fromList(hash.bytes);
  } finally {
    _erasePairingBytes(transcriptBytes);
  }
}

void _validateProtocol(String protocolVersion) {
  if (protocolVersion != trustedLanProtocolVersion) {
    throw const TrustedLanPairingException(
      TrustedLanPairingFailure.protocolMismatch,
    );
  }
}

Uint8List _secureRandomBytes(int length) {
  final random = Random.secure();
  final bytes = Uint8List(length);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

String _encodeConnectionCode(List<int> bytes) {
  if (bytes.length != trustedLanConnectionCodeEntropyBytes) {
    throw ArgumentError.value(
      bytes.length,
      'bytes',
      'Expected $trustedLanConnectionCodeEntropyBytes bytes.',
    );
  }
  for (final byte in bytes) {
    if (!_connectionCodeAlphabet.contains(String.fromCharCode(byte))) {
      throw const FormatException(
        'Trusted-LAN connection code contains an invalid symbol.',
      );
    }
  }
  return String.fromCharCodes(bytes);
}

String _formatConnectionCode(List<int> bytes) => _encodeConnectionCode(bytes);

Uint8List _pairingExactCopy(List<int> bytes, int expectedLength, String name) {
  if (bytes.length != expectedLength) {
    throw ArgumentError.value(
      bytes.length,
      name,
      'Expected $expectedLength bytes.',
    );
  }
  return Uint8List.fromList(bytes);
}

String _pairingRequiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Trusted-LAN pairing field "$key" must be a string.');
  }
  return value;
}

String _pairingEncode(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

Uint8List _pairingDecode(String value, int expectedLength, String name) {
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw FormatException('Invalid trusted-LAN pairing field "$name".');
  }
  late Uint8List result;
  try {
    result = Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
  } on FormatException {
    throw FormatException('Invalid trusted-LAN pairing field "$name".');
  }
  if (result.length != expectedLength) {
    throw FormatException(
      'Trusted-LAN pairing field "$name" must contain $expectedLength bytes.',
    );
  }
  return result;
}

bool _pairingConstantTimeEquals(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  var difference = 0;
  for (var i = 0; i < left.length; i++) {
    difference |= left[i] ^ right[i];
  }
  return difference == 0;
}

void _erasePairingBytes(Uint8List bytes) {
  bytes.fillRange(0, bytes.length, 0);
}
