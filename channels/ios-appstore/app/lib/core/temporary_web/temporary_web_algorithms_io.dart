import 'package:cryptography/cryptography.dart';

X25519 trustedLanX25519() => X25519();

AesGcm trustedLanAes256Gcm() => AesGcm.with256bits();

Hmac trustedLanHmacSha256() => Hmac.sha256();

Hkdf trustedLanHkdfSha256({required int outputLength}) =>
    Hkdf(hmac: Hmac.sha256(), outputLength: outputLength);

Sha256 trustedLanSha256() => Sha256();
