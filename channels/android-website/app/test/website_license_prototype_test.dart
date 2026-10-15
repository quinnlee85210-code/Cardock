import 'dart:convert';
import 'dart:typed_data';

import 'package:account_subscription_manager/core/entitlements/website_license_prototype.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const installationHash =
      '1d64add2a6388367c9b0da823351af986f286094d175585f56dffae6905f0cc1';

  Future<({String credential, Uint8List publicKey})> signedCredential({
    String channel = websiteLicenseChannel,
    String installationKeySha256 = installationHash,
    int version = websiteLicenseVersion,
  }) async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final payload = <String, Object?>{
      'version': version,
      'kind': websiteLicenseKind,
      'key_id': 'dev-test-key',
      'license_id': 'lic-demo-1',
      'order_reference': 'CARD-DEMO-0001',
      'product_id': websiteLicenseProduct,
      'channel': channel,
      'installation_key_sha256': installationKeySha256,
      'issued_at': '2026-09-05T00:00:00Z',
      'slot_limit': 10,
      'slot_ordinal': 1,
      'slots_remaining_at_issue': 9,
      'policy_status': 'candidate',
    };
    final signature = await algorithm.sign(
      utf8.encode(canonicalWebsiteLicenseJson(payload)),
      keyPair: keyPair,
    );
    final encoded = base64Url.encode(signature.bytes).replaceAll('=', '');
    return (
      credential: jsonEncode(<String, Object?>{
        'payload': payload,
        'signature': encoded,
      }),
      publicKey: Uint8List.fromList(publicKey.bytes),
    );
  }

  test('prototype trust is fail-closed by default', () async {
    final fixture = await signedCredential();
    final verifier = WebsiteLicensePrototypeVerifier(
      prototypeTrustEnabled: false,
      publicKeysById: <String, Uint8List>{'dev-test-key': fixture.publicKey},
    );

    final result = await verifier.verify(
      credentialJson: fixture.credential,
      expectedInstallationKeySha256: installationHash,
    );

    expect(
      result.status,
      WebsiteLicenseVerificationStatus.prototypeTrustDisabled,
    );
  });

  test(
    'valid development credential verifies only for bound installation',
    () async {
      final fixture = await signedCredential();
      final verifier = WebsiteLicensePrototypeVerifier(
        prototypeTrustEnabled: true,
        publicKeysById: <String, Uint8List>{'dev-test-key': fixture.publicKey},
      );

      final valid = await verifier.verify(
        credentialJson: fixture.credential,
        expectedInstallationKeySha256: installationHash,
      );
      final copied = await verifier.verify(
        credentialJson: fixture.credential,
        expectedInstallationKeySha256: List.filled(64, '0').join(),
      );

      expect(valid.status, WebsiteLicenseVerificationStatus.validPrototype);
      expect(copied.status, WebsiteLicenseVerificationStatus.wrongInstallation);
    },
  );

  test('tampering and wrong channel cannot verify', () async {
    final fixture = await signedCredential();
    final verifier = WebsiteLicensePrototypeVerifier(
      prototypeTrustEnabled: true,
      publicKeysById: <String, Uint8List>{'dev-test-key': fixture.publicKey},
    );
    final envelope = jsonDecode(fixture.credential) as Map<String, Object?>;
    final payload = Map<String, Object?>.from(
      envelope['payload']! as Map<String, Object?>,
    )..['slot_limit'] = 999;
    final tampered = jsonEncode(<String, Object?>{
      'payload': payload,
      'signature': envelope['signature'],
    });

    final tamperResult = await verifier.verify(
      credentialJson: tampered,
      expectedInstallationKeySha256: installationHash,
    );
    expect(
      tamperResult.status,
      WebsiteLicenseVerificationStatus.invalidSignature,
    );

    final wrongChannelFixture = await signedCredential(channel: 'google_play');
    final wrongChannelVerifier = WebsiteLicensePrototypeVerifier(
      prototypeTrustEnabled: true,
      publicKeysById: <String, Uint8List>{
        'dev-test-key': wrongChannelFixture.publicKey,
      },
    );
    final wrongChannel = await wrongChannelVerifier.verify(
      credentialJson: wrongChannelFixture.credential,
      expectedInstallationKeySha256: installationHash,
    );
    expect(wrongChannel.status, WebsiteLicenseVerificationStatus.wrongChannel);
  });

  test('unknown future version is rejected before signature trust', () async {
    final fixture = await signedCredential(version: 2);
    final verifier = WebsiteLicensePrototypeVerifier(
      prototypeTrustEnabled: true,
      publicKeysById: <String, Uint8List>{'dev-test-key': fixture.publicKey},
    );

    final result = await verifier.verify(
      credentialJson: fixture.credential,
      expectedInstallationKeySha256: installationHash,
    );
    expect(result.status, WebsiteLicenseVerificationStatus.unsupportedVersion);
  });
}
