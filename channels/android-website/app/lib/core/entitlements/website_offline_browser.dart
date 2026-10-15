import 'dart:convert';
import 'package:flutter/services.dart';
import 'website_license_prototype.dart';
import 'website_offline_codec.dart';

/// Local method channels plus explicit external-browser navigation; no HTTP client.
class WebsiteOfflineBrowser {
  WebsiteOfflineBrowser({
    Future<Map<String, Object?>> Function(String, String)? beginRequest,
    Future<Map<String, Object?>> Function(String)? signChallenge,
    Future<bool> Function(String)? startPurchase,
  }) : _begin = beginRequest ?? _nativeBegin,
       _sign = signChallenge ?? _nativeSign,
       _purchase = startPurchase ?? _nativePurchase;
  static const channel = MethodChannel('cardock/commercial_license');
  final Future<Map<String, Object?>> Function(String, String) _begin;
  final Future<Map<String, Object?>> Function(String) _sign;
  final Future<bool> Function(String) _purchase;

  static Future<bool> _nativePurchase(String installation) async =>
      await channel.invokeMethod<bool>('startOfflinePurchase', {
        'installationKeySha256': installation,
      }) ==
      true;

  Future<bool> startPurchase(String installation) =>
      _purchase(installation).timeout(const Duration(seconds: 20));

  static Future<Map<String, Object?>> _nativeBegin(
    String purpose,
    String reference,
  ) async =>
      await channel.invokeMapMethod<String, Object?>('beginOfflineRequest', {
        'purpose': purpose,
        'reference': reference,
      }) ??
      {};
  static Future<Map<String, Object?>> _nativeSign(String payload) async =>
      await channel.invokeMapMethod<String, Object?>('signOfflineChallenge', {
        'payload': payload,
      }) ??
      {};
  static Future<bool> open(Uri uri) async =>
      await channel.invokeMethod<bool>('openOfflineBrowser', {
        'url': uri.toString(),
      }) ==
      true;

  Future<Uri> begin(
    String installation,
    String purpose,
    String reference,
  ) async {
    final request = await _begin(
      purpose,
      reference,
    ).timeout(const Duration(seconds: 20));
    const fields = {
      'version',
      'application_id',
      'channel',
      'installation_key_sha256',
      'request_id',
      'purpose',
      'reference',
    };
    if (request.length != fields.length ||
        !request.keys.every(fields.contains) ||
        request['version'] is! int ||
        request['version'] != 1 ||
        request['application_id'] !=
            'com.localaccount.account_subscription_manager' ||
        request['channel'] != 'website' ||
        request['installation_key_sha256'] != installation ||
        request['purpose'] != purpose ||
        request['reference'] != reference ||
        decodeOfflineBase64(request['request_id'], maxLength: 43).length !=
            32) {
      throw const OfflineAuthorizationException('无法准备本地安装证明，请回到Cardock重试。');
    }
    return _url('/cardock/offline', 'request', request);
  }

  Future<Uri> prove(Map<String, dynamic> payload) async {
    final proof = await _sign(
      canonicalWebsiteLicenseJson(payload),
    ).timeout(const Duration(seconds: 20));
    if (proof.length != 3 ||
        !proof.keys.every(
          {'challenge_id', 'public_key', 'signature'}.contains,
        ) ||
        proof['challenge_id'] != payload['challenge_id'] ||
        decodeOfflineBase64(proof['public_key'], maxLength: 128).length != 91) {
      throw const OfflineAuthorizationException('本地安装证明失败，请从Cardock重新发起。');
    }
    final signature = decodeOfflineBase64(proof['signature'], maxLength: 128);
    if (signature.length < 64 || signature.length > 80) {
      throw const OfflineAuthorizationException('本地安装证明失败，请从Cardock重新发起。');
    }
    return _url('/cardock/offline/return', 'proof', proof);
  }

  static Uri _url(String path, String name, Map<String, Object?> value) {
    final encoded = base64Url
        .encode(utf8.encode(canonicalWebsiteLicenseJson(value)))
        .replaceAll('=', '');
    return Uri.parse('https://maskden.com$path#$name=$encoded');
  }
}
