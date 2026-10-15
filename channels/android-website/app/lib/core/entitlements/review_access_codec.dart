import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'promo_activation_codec.dart'
    show crockfordBase32Encode, crockfordBase32Decode;

/// CR1 + canonical Crockford base32(payload || Ed25519 signature).
/// Payload: format, key id, purpose(review), channel(Play), scope(full),
/// SHA256(applicationId), and a random 16-byte credential id. No expiry or device id.
const reviewAccessPayloadLength = 53;
const reviewAccessCodeLength = 191;
const reviewAccessDomain = 'Cardock/free-review-access/Ed25519/v1\u0000';
const reviewAccessApplicationId =
    'com.localaccount.account_subscription_manager';

final class ReviewAccessVerifier {
  ReviewAccessVerifier({
    required List<int> publicKey,
    this.applicationId = reviewAccessApplicationId,
    this.channel = 'google_play',
  }) : _publicKey = List<int>.unmodifiable(publicKey);
  final List<int> _publicKey;
  final String applicationId;
  final String channel;

  Future<bool> verify(String credential) async {
    if (credential.length != reviewAccessCodeLength ||
        !credential.startsWith('CR1') ||
        !RegExp(r'^[0-9A-HJKMNP-TV-Z]+$').hasMatch(credential) ||
        channel != 'google_play' ||
        _publicKey.length != 32) {
      return false;
    }
    try {
      final bytes = crockfordBase32Decode(credential.substring(3));
      if (bytes == null ||
          bytes.length != reviewAccessPayloadLength + 64 ||
          crockfordBase32Encode(bytes) != credential.substring(3)) {
        return false;
      }
      final payload = bytes.sublist(0, reviewAccessPayloadLength);
      for (var i = 0; i < 5; i++) {
        if (payload[i] != 1) return false;
      }
      final audience = (await Sha256().hash(utf8.encode(applicationId))).bytes;
      for (var i = 0; i < 32; i++) {
        if (payload[5 + i] != audience[i]) return false;
      }
      return await Ed25519().verify(
        [...utf8.encode(reviewAccessDomain), ...payload],
        signature: Signature(
          bytes.sublist(reviewAccessPayloadLength),
          publicKey: SimplePublicKey(_publicKey, type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      return false;
    }
  }
}
