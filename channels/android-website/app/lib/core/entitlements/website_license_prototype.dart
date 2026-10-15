import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const String websiteLicenseKind = 'cardock.website.installation-license';
const String websiteLicenseProduct = 'cardock.full.lifetime';
const String websiteLicenseChannel = 'website';
const int websiteLicenseVersion = 1;

enum WebsiteLicenseVerificationStatus {
  validPrototype,
  prototypeTrustDisabled,
  malformed,
  unsupportedVersion,
  wrongKind,
  wrongProduct,
  wrongChannel,
  unknownKey,
  wrongInstallation,
  invalidSignature,
}

final class WebsiteLicenseVerificationResult {
  const WebsiteLicenseVerificationResult(this.status, {this.payload});

  final WebsiteLicenseVerificationStatus status;
  final Map<String, Object?>? payload;

  bool get isValidPrototype =>
      status == WebsiteLicenseVerificationStatus.validPrototype;
}

/// Offline verifier for the website-license protocol prototype.
///
/// It is deliberately not connected to [ProductEntitlementController]. A
/// caller must opt into prototype trust, so the current production app cannot
/// grant a real entitlement from the development signing key.
final class WebsiteLicensePrototypeVerifier {
  WebsiteLicensePrototypeVerifier({
    required this.prototypeTrustEnabled,
    required Map<String, Uint8List> publicKeysById,
  }) : _publicKeysById = Map<String, Uint8List>.unmodifiable(
         publicKeysById.map(
           (key, value) =>
               MapEntry<String, Uint8List>(key, Uint8List.fromList(value)),
         ),
       );

  final bool prototypeTrustEnabled;
  final Map<String, Uint8List> _publicKeysById;

  Future<WebsiteLicenseVerificationResult> verify({
    required String credentialJson,
    required String expectedInstallationKeySha256,
  }) async {
    if (!prototypeTrustEnabled) {
      return const WebsiteLicenseVerificationResult(
        WebsiteLicenseVerificationStatus.prototypeTrustDisabled,
      );
    }

    late final Map<String, Object?> envelope;
    late final Map<String, Object?> payload;
    late final Uint8List signatureBytes;
    try {
      final decoded = jsonDecode(credentialJson);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Credential must be an object.');
      }
      envelope = decoded;
      final rawPayload = envelope['payload'];
      if (rawPayload is! Map<String, Object?>) {
        throw const FormatException('Payload must be an object.');
      }
      payload = rawPayload;
      signatureBytes = _decodeBase64Url(envelope['signature']);
    } on Object {
      return const WebsiteLicenseVerificationResult(
        WebsiteLicenseVerificationStatus.malformed,
      );
    }

    if (payload['version'] != websiteLicenseVersion) {
      return const WebsiteLicenseVerificationResult(
        WebsiteLicenseVerificationStatus.unsupportedVersion,
      );
    }
    if (payload['kind'] != websiteLicenseKind) {
      return const WebsiteLicenseVerificationResult(
        WebsiteLicenseVerificationStatus.wrongKind,
      );
    }
    if (payload['product_id'] != websiteLicenseProduct) {
      return const WebsiteLicenseVerificationResult(
        WebsiteLicenseVerificationStatus.wrongProduct,
      );
    }
    if (payload['channel'] != websiteLicenseChannel) {
      return const WebsiteLicenseVerificationResult(
        WebsiteLicenseVerificationStatus.wrongChannel,
      );
    }
    if (payload['installation_key_sha256'] != expectedInstallationKeySha256) {
      return const WebsiteLicenseVerificationResult(
        WebsiteLicenseVerificationStatus.wrongInstallation,
      );
    }

    final keyId = payload['key_id'];
    if (keyId is! String || !_publicKeysById.containsKey(keyId)) {
      return const WebsiteLicenseVerificationResult(
        WebsiteLicenseVerificationStatus.unknownKey,
      );
    }

    final isValid = await Ed25519().verify(
      utf8.encode(canonicalWebsiteLicenseJson(payload)),
      signature: Signature(
        signatureBytes,
        publicKey: SimplePublicKey(
          _publicKeysById[keyId]!,
          type: KeyPairType.ed25519,
        ),
      ),
    );
    return WebsiteLicenseVerificationResult(
      isValid
          ? WebsiteLicenseVerificationStatus.validPrototype
          : WebsiteLicenseVerificationStatus.invalidSignature,
      payload: isValid ? Map<String, Object?>.unmodifiable(payload) : null,
    );
  }
}

String canonicalWebsiteLicenseJson(Map<String, Object?> value) =>
    jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map<String, Object?>) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      sorted[entry.key] = _canonicalize(entry.value);
    }
    return sorted;
  }
  if (value is List<Object?>) {
    return value.map<Object?>(_canonicalize).toList(growable: false);
  }
  return value;
}

Uint8List _decodeBase64Url(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('Signature is missing.');
  }
  final padding = '=' * ((4 - value.length % 4) % 4);
  return Uint8List.fromList(base64Url.decode('$value$padding'));
}
