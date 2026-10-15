import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const int promoActivationFormatVersion = 1;
const int promoLifetimeEntitlementType = 1;
const int promoInstallationIdLength = 16;
const int promoRequestCodeLength = 8;
const int promoActivationSignatureLength = 64;
const int promoActivationTimestampLength = 8;
const int promoActivationPayloadLength =
    1 + promoRequestCodeLength + 1 + promoActivationTimestampLength;
const int promoActivationByteLength =
    promoActivationPayloadLength + promoActivationSignatureLength;

const String _crockfordAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

enum PromoActivationVerificationStatus {
  valid,
  malformed,
  invalidSignature,
  deviceMismatch,
}

final class PromoActivationVerification {
  const PromoActivationVerification._({
    required this.status,
    this.requestCode,
    this.issuedAtUtc,
    this.canonicalCode,
  });

  const PromoActivationVerification.valid({
    required String requestCode,
    required DateTime issuedAtUtc,
    required String canonicalCode,
  }) : this._(
         status: PromoActivationVerificationStatus.valid,
         requestCode: requestCode,
         issuedAtUtc: issuedAtUtc,
         canonicalCode: canonicalCode,
       );

  const PromoActivationVerification.invalid(
    PromoActivationVerificationStatus status,
  ) : this._(status: status);

  final PromoActivationVerificationStatus status;
  final String? requestCode;
  final DateTime? issuedAtUtc;
  final String? canonicalCode;

  bool get isValid => status == PromoActivationVerificationStatus.valid;
}

Future<String> derivePromoRequestCode(List<int> installationId) async {
  if (installationId.length != promoInstallationIdLength) {
    throw ArgumentError.value(
      installationId.length,
      'installationId.length',
      'must be $promoInstallationIdLength',
    );
  }
  final digest = await Sha256().hash(installationId);
  return crockfordBase32Encode(digest.bytes.take(5).toList(growable: false));
}

String normalizePromoRequestCode(String value) =>
    value.replaceAll(RegExp(r'[\s-]+'), '').toUpperCase();

bool isValidPromoRequestCode(String value) {
  final normalized = normalizePromoRequestCode(value);
  return normalized.length == promoRequestCodeLength &&
      normalized.codeUnits.every(
        (codeUnit) =>
            _crockfordAlphabet.contains(String.fromCharCode(codeUnit)),
      );
}

String normalizePromoActivationCode(String value) =>
    value.replaceAll(RegExp(r'[\s-]+'), '').toUpperCase();

String formatPromoActivationCode(String value, {int groupLength = 5}) {
  final normalized = normalizePromoActivationCode(value);
  if (normalized.isEmpty || groupLength < 1) return normalized;
  final groups = <String>[];
  for (var index = 0; index < normalized.length; index += groupLength) {
    final candidateEnd = index + groupLength;
    final end = candidateEnd < normalized.length
        ? candidateEnd
        : normalized.length;
    groups.add(normalized.substring(index, end));
  }
  return groups.join('-');
}

String crockfordBase32Encode(List<int> bytes) {
  if (bytes.isEmpty) return '';
  final output = StringBuffer();
  var buffer = 0;
  var bitCount = 0;
  for (final byte in bytes) {
    if (byte < 0 || byte > 255) {
      throw ArgumentError.value(byte, 'bytes', 'must contain byte values');
    }
    buffer = (buffer << 8) | byte;
    bitCount += 8;
    while (bitCount >= 5) {
      bitCount -= 5;
      output.write(_crockfordAlphabet[(buffer >> bitCount) & 0x1f]);
      buffer &= (1 << bitCount) - 1;
    }
  }
  if (bitCount > 0) {
    output.write(_crockfordAlphabet[(buffer << (5 - bitCount)) & 0x1f]);
  }
  return output.toString();
}

Uint8List? crockfordBase32Decode(String value) {
  final normalized = normalizePromoActivationCode(value);
  if (normalized.isEmpty) return null;
  final output = BytesBuilder(copy: false);
  var buffer = 0;
  var bitCount = 0;
  for (final character in normalized.codeUnits) {
    final index = _crockfordAlphabet.indexOf(String.fromCharCode(character));
    if (index < 0) return null;
    buffer = (buffer << 5) | index;
    bitCount += 5;
    while (bitCount >= 8) {
      bitCount -= 8;
      output.addByte((buffer >> bitCount) & 0xff);
      buffer &= (1 << bitCount) - 1;
    }
  }
  if (bitCount > 0 && buffer != 0) return null;
  return output.takeBytes();
}

/// Reads the request code only to route a code into signature verification.
///
/// The returned value is untrusted until [PromoActivationVerifier.verify]
/// succeeds.
String? readPromoRequestCodeUnchecked(String activationCode) {
  final decoded = crockfordBase32Decode(activationCode);
  if (decoded == null || decoded.length != promoActivationByteLength) {
    return null;
  }
  try {
    final requestCode = ascii.decode(
      decoded.sublist(1, 1 + promoRequestCodeLength),
    );
    return isValidPromoRequestCode(requestCode) ? requestCode : null;
  } on Object {
    return null;
  }
}

final class PromoActivationIssuer {
  const PromoActivationIssuer([this._algorithm]);

  final Ed25519? _algorithm;

  Future<String> issue({
    required String requestCode,
    required KeyPair keyPair,
    DateTime? issuedAtUtc,
  }) async {
    final normalizedRequest = normalizePromoRequestCode(requestCode);
    if (!isValidPromoRequestCode(normalizedRequest)) {
      throw const FormatException('申请码格式不正确');
    }
    final issuedAt = (issuedAtUtc ?? DateTime.now()).toUtc();
    final seconds = issuedAt.millisecondsSinceEpoch ~/ 1000;
    if (seconds < 0) throw const FormatException('签发时间无效');

    final payload = Uint8List(promoActivationPayloadLength);
    payload[0] = promoActivationFormatVersion;
    payload.setRange(
      1,
      1 + promoRequestCodeLength,
      ascii.encode(normalizedRequest),
    );
    payload[1 + promoRequestCodeLength] = promoLifetimeEntitlementType;
    ByteData.sublistView(
      payload,
    ).setUint64(1 + promoRequestCodeLength + 1, seconds, Endian.big);

    final signature = await (_algorithm ?? Ed25519()).sign(
      payload,
      keyPair: keyPair,
    );
    if (signature.bytes.length != promoActivationSignatureLength) {
      throw StateError('Ed25519 signature length is invalid');
    }
    final encoded = crockfordBase32Encode(<int>[
      ...payload,
      ...signature.bytes,
    ]);
    return formatPromoActivationCode(encoded);
  }
}

final class PromoActivationVerifier {
  PromoActivationVerifier({
    required List<int> publicKeyBytes,
    Ed25519? algorithm,
  }) : _algorithm = algorithm ?? Ed25519(),
       _publicKey = SimplePublicKey(
         _validatedPublicKey(publicKeyBytes),
         type: KeyPairType.ed25519,
       );

  final Ed25519 _algorithm;
  final SimplePublicKey _publicKey;

  List<int> get publicKeyBytes => List<int>.unmodifiable(_publicKey.bytes);

  Future<PromoActivationVerification> verify({
    required String activationCode,
    required String expectedRequestCode,
  }) async {
    final normalized = normalizePromoActivationCode(activationCode);
    final decoded = crockfordBase32Decode(normalized);
    if (decoded == null || decoded.length != promoActivationByteLength) {
      return const PromoActivationVerification.invalid(
        PromoActivationVerificationStatus.malformed,
      );
    }

    final payload = decoded.sublist(0, promoActivationPayloadLength);
    final signatureBytes = decoded.sublist(promoActivationPayloadLength);
    bool signatureValid;
    try {
      signatureValid = await _algorithm.verify(
        payload,
        signature: Signature(signatureBytes, publicKey: _publicKey),
      );
    } on Object {
      signatureValid = false;
    }
    if (!signatureValid) {
      return const PromoActivationVerification.invalid(
        PromoActivationVerificationStatus.invalidSignature,
      );
    }

    if (payload[0] != promoActivationFormatVersion ||
        payload[1 + promoRequestCodeLength] != promoLifetimeEntitlementType) {
      return const PromoActivationVerification.invalid(
        PromoActivationVerificationStatus.malformed,
      );
    }
    String requestCode;
    try {
      requestCode = ascii.decode(
        payload.sublist(1, 1 + promoRequestCodeLength),
      );
    } on Object {
      return const PromoActivationVerification.invalid(
        PromoActivationVerificationStatus.malformed,
      );
    }
    if (!isValidPromoRequestCode(requestCode)) {
      return const PromoActivationVerification.invalid(
        PromoActivationVerificationStatus.malformed,
      );
    }
    if (requestCode != normalizePromoRequestCode(expectedRequestCode)) {
      return const PromoActivationVerification.invalid(
        PromoActivationVerificationStatus.deviceMismatch,
      );
    }

    final seconds = ByteData.sublistView(
      payload,
    ).getUint64(1 + promoRequestCodeLength + 1, Endian.big);
    DateTime issuedAt;
    try {
      issuedAt = DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000,
        isUtc: true,
      );
    } on Object {
      return const PromoActivationVerification.invalid(
        PromoActivationVerificationStatus.malformed,
      );
    }
    return PromoActivationVerification.valid(
      requestCode: requestCode,
      issuedAtUtc: issuedAt,
      canonicalCode: formatPromoActivationCode(normalized),
    );
  }

  static List<int> _validatedPublicKey(List<int> bytes) {
    if (bytes.length != 32 || bytes.any((value) => value < 0 || value > 255)) {
      throw ArgumentError.value(bytes.length, 'publicKeyBytes.length');
    }
    return List<int>.from(bytes);
  }
}
