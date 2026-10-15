import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'temporary_web_algorithms.dart';

/// Version of the record protocol used only on a user-trusted hotspot or LAN.
///
/// This name is deliberately explicit: the HTTP page that drives the browser
/// is not authenticated by TLS and can be replaced by an active local-network
/// attacker. The pairing layer therefore must not be described as protection
/// for hostile networks.
const String trustedLanProtocolVersion = 'cardock-trusted-lan-v1';

const int trustedLanSessionIdLength = 16;
const int trustedLanAesKeyLength = 32;
const int trustedLanNoncePrefixLength = 4;
const int trustedLanNonceLength = 12;
const int trustedLanAuthenticationTagLength = 16;

/// A conservative upper bound for one encrypted application record.
const int trustedLanMaximumPlaintextLength = 4 * 1024 * 1024;

enum TrustedLanEndpointRole { phone, browser }

enum TrustedLanRecordDirection {
  phoneToBrowser('phone_to_browser', 1),
  browserToPhone('browser_to_phone', 2);

  const TrustedLanRecordDirection(this.wireName, this.wireCode);

  final String wireName;
  final int wireCode;

  static TrustedLanRecordDirection fromWireName(String value) {
    for (final direction in values) {
      if (direction.wireName == value) {
        return direction;
      }
    }
    throw FormatException('Unknown trusted-LAN record direction.');
  }
}

enum TrustedLanRecordFailure {
  closed,
  protocolMismatch,
  sessionMismatch,
  directionMismatch,
  counterOutOfOrder,
  counterOverflow,
  invalidNonce,
  invalidFrame,
  authenticationFailed,
  plaintextTooLarge,
}

final class TrustedLanRecordException implements Exception {
  const TrustedLanRecordException(this.failure);

  final TrustedLanRecordFailure failure;

  @override
  String toString() => 'TrustedLanRecordException(${failure.name})';
}

/// A web-portable unsigned 64-bit counter represented as two 32-bit words.
///
/// Dart compiled to JavaScript cannot safely represent every unsigned 64-bit
/// integer as a JavaScript number. Keeping two words avoids precision loss and
/// guarantees that the nonce counter never wraps silently in the browser.
final class TrustedLanCounter64 {
  const TrustedLanCounter64._(this.high, this.low);

  factory TrustedLanCounter64({required int high, required int low}) {
    _checkWord(high, 'high');
    _checkWord(low, 'low');
    return TrustedLanCounter64._(high, low);
  }

  factory TrustedLanCounter64.fromBytes(List<int> bytes) {
    if (bytes.length != 8) {
      throw FormatException('A trusted-LAN counter must contain 8 bytes.');
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    return TrustedLanCounter64(
      high: data.getUint32(0, Endian.big),
      low: data.getUint32(4, Endian.big),
    );
  }

  static const TrustedLanCounter64 zero = TrustedLanCounter64._(0, 0);
  static const TrustedLanCounter64 maximum = TrustedLanCounter64._(
    0xffffffff,
    0xffffffff,
  );

  final int high;
  final int low;

  bool get isMaximum => high == 0xffffffff && low == 0xffffffff;

  TrustedLanCounter64 incremented() {
    if (isMaximum) {
      throw const TrustedLanRecordException(
        TrustedLanRecordFailure.counterOverflow,
      );
    }
    if (low == 0xffffffff) {
      return TrustedLanCounter64._(high + 1, 0);
    }
    return TrustedLanCounter64._(high, low + 1);
  }

  Uint8List toBytes() {
    final result = Uint8List(8);
    final data = ByteData.sublistView(result);
    data.setUint32(0, high, Endian.big);
    data.setUint32(4, low, Endian.big);
    return result;
  }

  static void _checkWord(int value, String name) {
    if (value < 0 || value > 0xffffffff) {
      throw RangeError.range(value, 0, 0xffffffff, name);
    }
  }

  @override
  bool operator ==(Object other) {
    return other is TrustedLanCounter64 &&
        high == other.high &&
        low == other.low;
  }

  @override
  int get hashCode => Object.hash(high, low);

  @override
  String toString() =>
      'TrustedLanCounter64(0x${high.toRadixString(16).padLeft(8, '0')}'
      '${low.toRadixString(16).padLeft(8, '0')})';
}

/// Transport-neutral encrypted record. Binary fields are copied defensively.
final class TrustedLanEncryptedFrame {
  TrustedLanEncryptedFrame({
    required this.protocolVersion,
    required List<int> sessionId,
    required this.direction,
    required this.counter,
    required List<int> nonce,
    required List<int> cipherText,
    required List<int> authenticationTag,
  }) : _sessionId = _copyWithExactLength(
         sessionId,
         trustedLanSessionIdLength,
         'sessionId',
       ),
       _nonce = _copyWithExactLength(nonce, trustedLanNonceLength, 'nonce'),
       _cipherText = Uint8List.fromList(cipherText),
       _authenticationTag = _copyWithExactLength(
         authenticationTag,
         trustedLanAuthenticationTagLength,
         'authenticationTag',
       ) {
    if (_cipherText.length > trustedLanMaximumPlaintextLength) {
      throw const TrustedLanRecordException(
        TrustedLanRecordFailure.invalidFrame,
      );
    }
  }

  factory TrustedLanEncryptedFrame.fromJson(Map<String, Object?> json) {
    final protocolVersion = _requiredString(json, 'v');
    final sessionId = _decodeBase64Url(
      _requiredString(json, 'sid'),
      trustedLanSessionIdLength,
      'sid',
    );
    final direction = TrustedLanRecordDirection.fromWireName(
      _requiredString(json, 'dir'),
    );
    final counter = TrustedLanCounter64.fromBytes(
      _decodeBase64Url(_requiredString(json, 'ctr'), 8, 'ctr'),
    );
    final nonce = _decodeBase64Url(
      _requiredString(json, 'nonce'),
      trustedLanNonceLength,
      'nonce',
    );
    final cipherText = _decodeBase64Url(
      _requiredString(json, 'ct'),
      null,
      'ct',
    );
    final authenticationTag = _decodeBase64Url(
      _requiredString(json, 'tag'),
      trustedLanAuthenticationTagLength,
      'tag',
    );
    return TrustedLanEncryptedFrame(
      protocolVersion: protocolVersion,
      sessionId: sessionId,
      direction: direction,
      counter: counter,
      nonce: nonce,
      cipherText: cipherText,
      authenticationTag: authenticationTag,
    );
  }

  final String protocolVersion;
  final Uint8List _sessionId;
  final TrustedLanRecordDirection direction;
  final TrustedLanCounter64 counter;
  final Uint8List _nonce;
  final Uint8List _cipherText;
  final Uint8List _authenticationTag;

  Uint8List get sessionId => Uint8List.fromList(_sessionId);
  Uint8List get nonce => Uint8List.fromList(_nonce);
  Uint8List get cipherText => Uint8List.fromList(_cipherText);
  Uint8List get authenticationTag => Uint8List.fromList(_authenticationTag);

  Map<String, Object?> toJson() => <String, Object?>{
    'v': protocolVersion,
    'sid': _encodeBase64Url(_sessionId),
    'dir': direction.wireName,
    'ctr': _encodeBase64Url(counter.toBytes()),
    'nonce': _encodeBase64Url(_nonce),
    'ct': _encodeBase64Url(_cipherText),
    'tag': _encodeBase64Url(_authenticationTag),
  };

  TrustedLanEncryptedFrame copyWith({
    String? protocolVersion,
    List<int>? sessionId,
    TrustedLanRecordDirection? direction,
    TrustedLanCounter64? counter,
    List<int>? nonce,
    List<int>? cipherText,
    List<int>? authenticationTag,
  }) {
    return TrustedLanEncryptedFrame(
      protocolVersion: protocolVersion ?? this.protocolVersion,
      sessionId: sessionId ?? _sessionId,
      direction: direction ?? this.direction,
      counter: counter ?? this.counter,
      nonce: nonce ?? _nonce,
      cipherText: cipherText ?? _cipherText,
      authenticationTag: authenticationTag ?? _authenticationTag,
    );
  }
}

/// Stateful AES-256-GCM record layer created by trusted-LAN pairing.
///
/// Sending and receiving are serialized independently. A failed authentication
/// does not advance the receive counter, while a send counter is reserved
/// before encryption so a nonce can never be reused after an uncertain error.
final class TrustedLanSecureChannel {
  TrustedLanSecureChannel.fromTrustedLanPairing({
    required this.role,
    required List<int> sessionId,
    required List<int> phoneToBrowserKey,
    required List<int> browserToPhoneKey,
    required List<int> phoneToBrowserNoncePrefix,
    required List<int> browserToPhoneNoncePrefix,
    AesGcm? cipher,
  }) : _sessionId = _copyWithExactLength(
         sessionId,
         trustedLanSessionIdLength,
         'sessionId',
       ),
       _cipher = cipher ?? trustedLanAes256Gcm(),
       _sendKey = SecretKeyData(
         _copyWithExactLength(
           role == TrustedLanEndpointRole.phone
               ? phoneToBrowserKey
               : browserToPhoneKey,
           trustedLanAesKeyLength,
           'sendKey',
         ),
         overwriteWhenDestroyed: true,
       ),
       _receiveKey = SecretKeyData(
         _copyWithExactLength(
           role == TrustedLanEndpointRole.phone
               ? browserToPhoneKey
               : phoneToBrowserKey,
           trustedLanAesKeyLength,
           'receiveKey',
         ),
         overwriteWhenDestroyed: true,
       ),
       _sendNoncePrefix = _copyWithExactLength(
         role == TrustedLanEndpointRole.phone
             ? phoneToBrowserNoncePrefix
             : browserToPhoneNoncePrefix,
         trustedLanNoncePrefixLength,
         'sendNoncePrefix',
       ),
       _receiveNoncePrefix = _copyWithExactLength(
         role == TrustedLanEndpointRole.phone
             ? browserToPhoneNoncePrefix
             : phoneToBrowserNoncePrefix,
         trustedLanNoncePrefixLength,
         'receiveNoncePrefix',
       );

  final TrustedLanEndpointRole role;
  final Uint8List _sessionId;
  final AesGcm _cipher;
  final SecretKeyData _sendKey;
  final SecretKeyData _receiveKey;
  final Uint8List _sendNoncePrefix;
  final Uint8List _receiveNoncePrefix;

  TrustedLanCounter64 _nextSendCounter = TrustedLanCounter64.zero;
  TrustedLanCounter64 _nextReceiveCounter = TrustedLanCounter64.zero;
  bool _sendCounterExhausted = false;
  bool _receiveCounterExhausted = false;
  bool _acceptingOperations = true;
  bool _destroyed = false;
  Future<void> _sendTail = Future<void>.value();
  Future<void> _receiveTail = Future<void>.value();
  Future<void>? _destroyFuture;

  Uint8List get sessionId => Uint8List.fromList(_sessionId);

  TrustedLanRecordDirection get sendDirection =>
      role == TrustedLanEndpointRole.phone
      ? TrustedLanRecordDirection.phoneToBrowser
      : TrustedLanRecordDirection.browserToPhone;

  TrustedLanRecordDirection get receiveDirection =>
      role == TrustedLanEndpointRole.phone
      ? TrustedLanRecordDirection.browserToPhone
      : TrustedLanRecordDirection.phoneToBrowser;

  Future<TrustedLanEncryptedFrame> encrypt(List<int> plaintext) {
    if (!_acceptingOperations) {
      return Future<TrustedLanEncryptedFrame>.error(
        const TrustedLanRecordException(TrustedLanRecordFailure.closed),
      );
    }
    if (plaintext.length > trustedLanMaximumPlaintextLength) {
      return Future<TrustedLanEncryptedFrame>.error(
        const TrustedLanRecordException(
          TrustedLanRecordFailure.plaintextTooLarge,
        ),
      );
    }
    final clearTextCopy = Uint8List.fromList(plaintext);
    final completer = Completer<TrustedLanEncryptedFrame>();
    _sendTail = _sendTail.then((_) async {
      try {
        completer.complete(await _encryptNow(clearTextCopy));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _erase(clearTextCopy);
      }
    });
    return completer.future;
  }

  Future<Uint8List> decrypt(TrustedLanEncryptedFrame frame) {
    if (!_acceptingOperations) {
      return Future<Uint8List>.error(
        const TrustedLanRecordException(TrustedLanRecordFailure.closed),
      );
    }
    final completer = Completer<Uint8List>();
    _receiveTail = _receiveTail.then((_) async {
      try {
        completer.complete(await _decryptNow(frame));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> destroy() {
    final existing = _destroyFuture;
    if (existing != null) {
      return existing;
    }
    _acceptingOperations = false;
    final completer = Completer<void>();
    _destroyFuture = completer.future;
    () async {
      try {
        await Future.wait(<Future<void>>[_sendTail, _receiveTail]);
        if (!_destroyed) {
          _destroyed = true;
          _sendKey.destroy();
          _receiveKey.destroy();
          _erase(_sessionId);
          _erase(_sendNoncePrefix);
          _erase(_receiveNoncePrefix);
        }
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }();
    return completer.future;
  }

  Future<TrustedLanEncryptedFrame> _encryptNow(Uint8List plaintext) async {
    _ensureNotDestroyed();
    if (plaintext.length > trustedLanMaximumPlaintextLength) {
      throw const TrustedLanRecordException(
        TrustedLanRecordFailure.plaintextTooLarge,
      );
    }
    final counter = _reserveSendCounter();
    final nonce = _nonceFor(_sendNoncePrefix, counter);
    final aad = _recordAad(
      sessionId: _sessionId,
      direction: sendDirection,
      counter: counter,
    );
    try {
      final box = await _cipher.encrypt(
        plaintext,
        secretKey: _sendKey,
        nonce: nonce,
        aad: aad,
      );
      return TrustedLanEncryptedFrame(
        protocolVersion: trustedLanProtocolVersion,
        sessionId: _sessionId,
        direction: sendDirection,
        counter: counter,
        nonce: nonce,
        cipherText: box.cipherText,
        authenticationTag: box.mac.bytes,
      );
    } finally {
      _erase(nonce);
      _erase(aad);
    }
  }

  Future<Uint8List> _decryptNow(TrustedLanEncryptedFrame frame) async {
    _ensureNotDestroyed();
    if (frame.protocolVersion != trustedLanProtocolVersion) {
      throw const TrustedLanRecordException(
        TrustedLanRecordFailure.protocolMismatch,
      );
    }
    if (!_constantTimeEquals(frame._sessionId, _sessionId)) {
      throw const TrustedLanRecordException(
        TrustedLanRecordFailure.sessionMismatch,
      );
    }
    if (frame.direction != receiveDirection) {
      throw const TrustedLanRecordException(
        TrustedLanRecordFailure.directionMismatch,
      );
    }
    if (_receiveCounterExhausted) {
      throw const TrustedLanRecordException(
        TrustedLanRecordFailure.counterOverflow,
      );
    }
    if (frame.counter != _nextReceiveCounter) {
      throw const TrustedLanRecordException(
        TrustedLanRecordFailure.counterOutOfOrder,
      );
    }
    if (frame._cipherText.length > trustedLanMaximumPlaintextLength) {
      throw const TrustedLanRecordException(
        TrustedLanRecordFailure.invalidFrame,
      );
    }
    final expectedNonce = _nonceFor(_receiveNoncePrefix, frame.counter);
    if (!_constantTimeEquals(frame._nonce, expectedNonce)) {
      _erase(expectedNonce);
      throw const TrustedLanRecordException(
        TrustedLanRecordFailure.invalidNonce,
      );
    }
    final aad = _recordAad(
      sessionId: _sessionId,
      direction: frame.direction,
      counter: frame.counter,
    );
    try {
      final clearText = await _cipher.decrypt(
        SecretBox(
          frame._cipherText,
          nonce: expectedNonce,
          mac: Mac(frame._authenticationTag),
        ),
        secretKey: _receiveKey,
        aad: aad,
      );
      _advanceReceiveCounter(frame.counter);
      return Uint8List.fromList(clearText);
    } on SecretBoxAuthenticationError {
      throw const TrustedLanRecordException(
        TrustedLanRecordFailure.authenticationFailed,
      );
    } finally {
      _erase(expectedNonce);
      _erase(aad);
    }
  }

  TrustedLanCounter64 _reserveSendCounter() {
    if (_sendCounterExhausted) {
      throw const TrustedLanRecordException(
        TrustedLanRecordFailure.counterOverflow,
      );
    }
    final current = _nextSendCounter;
    if (current.isMaximum) {
      _sendCounterExhausted = true;
    } else {
      _nextSendCounter = current.incremented();
    }
    return current;
  }

  void _advanceReceiveCounter(TrustedLanCounter64 current) {
    if (current.isMaximum) {
      _receiveCounterExhausted = true;
    } else {
      _nextReceiveCounter = current.incremented();
    }
  }

  void _ensureNotDestroyed() {
    if (_destroyed) {
      throw const TrustedLanRecordException(TrustedLanRecordFailure.closed);
    }
  }
}

Uint8List _recordAad({
  required List<int> sessionId,
  required TrustedLanRecordDirection direction,
  required TrustedLanCounter64 counter,
}) {
  final domain = utf8.encode('cardock/trusted-lan/record-aad');
  final version = utf8.encode(trustedLanProtocolVersion);
  final builder = BytesBuilder(copy: false)
    ..addByte(domain.length)
    ..add(domain)
    ..addByte(version.length)
    ..add(version)
    ..add(sessionId)
    ..addByte(direction.wireCode)
    ..add(counter.toBytes());
  return builder.takeBytes();
}

Uint8List _nonceFor(List<int> prefix, TrustedLanCounter64 counter) {
  final result = Uint8List(trustedLanNonceLength);
  result.setRange(0, trustedLanNoncePrefixLength, prefix);
  result.setRange(
    trustedLanNoncePrefixLength,
    result.length,
    counter.toBytes(),
  );
  return result;
}

Uint8List _copyWithExactLength(
  List<int> bytes,
  int expectedLength,
  String name,
) {
  if (bytes.length != expectedLength) {
    throw ArgumentError.value(
      bytes.length,
      name,
      'Expected $expectedLength bytes.',
    );
  }
  return Uint8List.fromList(bytes);
}

bool _constantTimeEquals(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  var difference = 0;
  for (var i = 0; i < left.length; i++) {
    difference |= left[i] ^ right[i];
  }
  return difference == 0;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Trusted-LAN frame field "$key" must be a string.');
  }
  return value;
}

String _encodeBase64Url(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

Uint8List _decodeBase64Url(String value, int? expectedLength, String name) {
  if (!RegExp(r'^[A-Za-z0-9_-]*$').hasMatch(value)) {
    throw FormatException('Invalid base64url in trusted-LAN field "$name".');
  }
  final maximumEncodedLength =
      ((expectedLength ?? trustedLanMaximumPlaintextLength) * 4 + 2) ~/ 3;
  if (value.length > maximumEncodedLength) {
    throw FormatException('Trusted-LAN field "$name" is too large.');
  }
  late Uint8List result;
  try {
    result = Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
  } on FormatException {
    throw FormatException('Invalid base64url in trusted-LAN field "$name".');
  }
  if (expectedLength != null && result.length != expectedLength) {
    throw FormatException(
      'Trusted-LAN field "$name" must contain $expectedLength bytes.',
    );
  }
  if (result.length > trustedLanMaximumPlaintextLength) {
    throw const FormatException('Trusted-LAN binary field is too large.');
  }
  return result;
}

void _erase(Uint8List bytes) {
  bytes.fillRange(0, bytes.length, 0);
}
