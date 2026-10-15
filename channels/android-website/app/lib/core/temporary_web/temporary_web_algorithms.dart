import 'package:cryptography/cryptography.dart';

import 'temporary_web_algorithms_io.dart'
    if (dart.library.js_interop) 'temporary_web_algorithms_web.dart'
    as implementation;

/// Cryptographic implementations used by the trusted-LAN protocol.
///
/// Browser pages served from a phone use a private-LAN HTTP origin, which is
/// not a secure browser context. The web implementation therefore selects the
/// package's pure-Dart algorithms directly instead of initializing WebCrypto.
X25519 trustedLanX25519() => implementation.trustedLanX25519();

AesGcm trustedLanAes256Gcm() => implementation.trustedLanAes256Gcm();

Hmac trustedLanHmacSha256() => implementation.trustedLanHmacSha256();

Hkdf trustedLanHkdfSha256({required int outputLength}) =>
    implementation.trustedLanHkdfSha256(outputLength: outputLength);

Sha256 trustedLanSha256() => implementation.trustedLanSha256();
