import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

const DartSha256 _sha256 = DartSha256();
const DartHmac _hmacSha256 = DartHmac(_sha256);
final Random _secureRandom = Random.secure();

X25519 trustedLanX25519() => DartX25519(random: _secureRandom);

AesGcm trustedLanAes256Gcm() =>
    DartAesGcm(secretKeyLength: 32, random: _secureRandom);

Hmac trustedLanHmacSha256() => _hmacSha256;

Hkdf trustedLanHkdfSha256({required int outputLength}) =>
    DartHkdf(hmac: _hmacSha256, outputLength: outputLength);

Sha256 trustedLanSha256() => _sha256;
