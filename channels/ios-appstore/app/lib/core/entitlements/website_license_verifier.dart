import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'website_license_prototype.dart'
    show canonicalWebsiteLicenseJson, websiteLicenseKind, websiteLicenseProduct;

/// Production v2 is deliberately separated from the development v1 issuer.
final class WebsiteLicenseVerifier {
  WebsiteLicenseVerifier({
    required Map<String, List<int>> publicKeys,
    required this.applicationId,
  }) : _keys = {
         for (final e in publicKeys.entries)
           e.key: List<int>.unmodifiable(e.value),
       };
  static const maxCredentialCharacters = 16384;
  final Map<String, List<int>> _keys;
  final String applicationId;
  Future<bool> verify(String credential, String installationSha256) async {
    if (credential.length > maxCredentialCharacters ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(installationSha256)) {
      return false;
    }
    try {
      final envelope = jsonDecode(credential);
      if (envelope is! Map<String, dynamic> || envelope.length != 2) {
        return false;
      }
      final p = envelope['payload'];
      if (p is! Map<String, dynamic> ||
          p.length != 10 ||
          p['version'] != 2 ||
          p['kind'] != websiteLicenseKind ||
          p['product_id'] != websiteLicenseProduct ||
          p['channel'] != 'website' ||
          p['application_id'] != applicationId ||
          p['environment'] != 'production' ||
          p['installation_key_sha256'] != installationSha256 ||
          p['license_id'] is! String ||
          !RegExp(
            r'^[A-Za-z0-9_-]{8,128}$',
          ).hasMatch(p['license_id'] as String) ||
          p['issued_at'] is! int ||
          (p['issued_at'] as int) <= 0 ||
          p['key_id'] is! String ||
          !_keys.containsKey(p['key_id']) ||
          envelope['signature'] is! String) {
        return false;
      }
      final signature = base64Url.decode(
        base64Url.normalize(envelope['signature'] as String),
      );
      final key = _keys[p['key_id']]!;
      if (signature.length != 64 || key.length != 32) return false;
      return await Ed25519().verify(
        utf8.encode(canonicalWebsiteLicenseJson(p)),
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      return false;
    }
  }
}
