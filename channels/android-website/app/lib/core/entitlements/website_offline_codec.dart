import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'commercial_license_config.dart';
import 'website_license_prototype.dart';
import 'website_license_verifier.dart';

/// Bounded strict JSON keeps duplicate fields from disappearing before validation.
Object? strictOfflineJson(String source) {
  final value = jsonDecode(source);
  var i = 0;
  void whitespace() {
    while (i < source.length && ' \t\n\r'.contains(source[i])) {
      i++;
    }
  }

  String string() {
    final start = i++;
    while (i < source.length) {
      if (source[i] == '\\') {
        i += 2;
        continue;
      }
      if (source[i++] == '"') {
        return jsonDecode(source.substring(start, i)) as String;
      }
    }
    throw const FormatException('Unterminated string');
  }

  late void Function(int) scan;
  scan = (int depth) {
    if (depth > 8) throw const FormatException('Too deeply nested');
    whitespace();
    final first = source[i];
    if (first == '"') {
      string();
      return;
    }
    if (first == '{' || first == '[') {
      i++;
      whitespace();
      final end = first == '{' ? '}' : ']';
      final keys = <String>{};
      var count = 0;
      if (source[i] == end) {
        i++;
        return;
      }
      while (true) {
        whitespace();
        if (++count > 64) throw const FormatException('Too many fields');
        if (first == '{') {
          if (!keys.add(string())) {
            throw const FormatException('Duplicate field');
          }
          whitespace();
          i++; // Colon: the JSON decoder already validated grammar.
        }
        scan(depth + 1);
        whitespace();
        if (source[i++] == end) return;
      }
    }
    while (i < source.length && !',}] \t\n\r'.contains(source[i])) {
      i++;
    }
  };
  scan(0);
  whitespace();
  if (i != source.length) throw const FormatException('Trailing data');
  return value;
}

List<int> decodeOfflineBase64(Object? value, {int maxLength = 32768}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maxLength ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw const FormatException('Invalid Base64URL');
  }
  final raw = base64Url.decode(base64Url.normalize(value));
  if (base64Url.encode(raw).replaceAll('=', '') != value) {
    throw const FormatException('Noncanonical Base64URL');
  }
  return raw;
}

bool _fields(Map<String, dynamic> value, Set<String> fields) =>
    value.length == fields.length && value.keys.every(fields.contains);
bool _positiveTime(Object? value) =>
    value is int && value > 0 && value <= 253402300799;
bool _digest(Object? value) =>
    value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

final class VerifiedWebsiteReceipt {
  const VerifiedWebsiteReceipt({
    required this.orderReference,
    required this.amountMinor,
    required this.currency,
    required this.verifiedAt,
    required this.licenseId,
  });
  final String orderReference;
  final int amountMinor;
  final String currency;

  /// This is a verified payment-record timestamp, never a claimed payment date.
  final DateTime verifiedAt;
  final String licenseId;
}

final class VerifiedWebsiteAuthorization {
  const VerifiedWebsiteAuthorization({
    required this.storageText,
    required this.license,
    required this.licenseId,
    this.receipt,
  });
  final String storageText;
  final String license;
  final String licenseId;
  final VerifiedWebsiteReceipt? receipt;
}

final class OfflineAuthorizationException implements Exception {
  const OfflineAuthorizationException(this.message);
  final String message;
}

final class WebsiteOfflineCodec {
  WebsiteOfflineCodec(this.config)
    : _licenseVerifier = WebsiteLicenseVerifier(
        publicKeys: config.publicKeys,
        applicationId: config.applicationId,
      );
  final CommercialLicenseConfig config;
  final WebsiteLicenseVerifier _licenseVerifier;
  static const prefix = 'CARDOCK_OFFLINE_ACTIVATION_V1\n';
  static const maxBytes = 24576;
  static const receiptContext = 'cardock.website.purchase-receipt.v1\n';
  static const challengeContext = 'cardock.offline-installation-challenge.v1\n';
  static const proofContext = 'cardock.offline-installation-proof.v1\n';

  Future<bool> _signature(Map<String, dynamic> envelope, String context) async {
    if (!_fields(envelope, {'payload', 'signature'})) return false;
    final p = envelope['payload'];
    if (p is! Map<String, dynamic> || p['key_id'] is! String) return false;
    final key = config.publicKeys[p['key_id']];
    if (key == null) return false;
    final signature = decodeOfflineBase64(envelope['signature'], maxLength: 86);
    if (signature.length != 64) return false;
    return Ed25519().verify(
      utf8.encode(context + canonicalWebsiteLicenseJson(p)),
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
      ),
    );
  }

  Future<VerifiedWebsiteAuthorization> verifyAuthorization(
    String input,
    String installation,
  ) async {
    try {
      if (input.length > maxBytes ||
          utf8.encode(input).length > maxBytes ||
          !_digest(installation)) {
        throw const OfflineAuthorizationException('授权内容过长或安装身份无效，请重新复制完整授权。');
      }
      final text = input.trim();
      final wrapped = text.startsWith(prefix);
      final raw = strictOfflineJson(
        wrapped ? text.substring(prefix.length) : text,
      );
      if (raw is! Map<String, dynamic>) throw const FormatException();
      final isBundle =
          wrapped || raw.containsKey('kind') || raw.containsKey('receipt');
      String license;
      Map<String, dynamic>? receipt;
      if (isBundle) {
        if (!_fields(raw, {'kind', 'license', 'receipt'}) ||
            raw['kind'] != 'cardock-offline-activation-v1' ||
            raw['license'] is! String ||
            raw['receipt'] is! Map<String, dynamic>) {
          throw const OfflineAuthorizationException(
            '完整授权格式不正确，请重新复制官网提供的全部内容。',
          );
        }
        license = raw['license'] as String;
        receipt = raw['receipt'] as Map<String, dynamic>;
      } else {
        license = text;
      }
      if (utf8.encode(license).length >
          WebsiteLicenseVerifier.maxCredentialCharacters) {
        throw const FormatException();
      }
      final original = strictOfflineJson(license);
      if (original is! Map<String, dynamic> ||
          original['payload'] is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final lp = original['payload'] as Map<String, dynamic>;
      if (lp['installation_key_sha256'] != installation) {
        throw const OfflineAuthorizationException(
          '此授权不属于当前安装。请在浏览器中恢复已有购买，不要重新付款。',
        );
      }
      if (lp['version'] is! int ||
          !await _licenseVerifier.verify(license, installation)) {
        throw const OfflineAuthorizationException('授权验签未通过，请从官网重新复制完整授权。');
      }
      VerifiedWebsiteReceipt? verifiedReceipt;
      if (receipt != null) {
        final p = receipt['payload'];
        const fields = {
          'version',
          'kind',
          'key_id',
          'application_id',
          'product_id',
          'channel',
          'environment',
          'installation_key_sha256',
          'license_id',
          'license_sha256',
          'order_reference',
          'amount_minor',
          'currency',
          'verified_at',
          'date_source',
          'order_created_at',
          'license_issued_at',
        };
        if (p is! Map<String, dynamic> ||
            !_fields(p, fields) ||
            p['version'] is! int ||
            p['version'] != 1 ||
            p['kind'] != 'cardock.website.purchase-receipt' ||
            p['application_id'] != config.applicationId ||
            p['product_id'] != websiteLicenseProduct ||
            p['channel'] != 'website' ||
            p['environment'] != 'production' ||
            p['installation_key_sha256'] != installation ||
            p['license_id'] != lp['license_id'] ||
            p['key_id'] != lp['key_id'] ||
            !_digest(p['license_sha256']) ||
            p['order_reference'] is! String ||
            !RegExp(
              r'^[A-Za-z0-9_-]{8,80}$',
            ).hasMatch(p['order_reference'] as String) ||
            p['amount_minor'] is! int ||
            p['amount_minor'] != 990 ||
            p['currency'] != 'CNY' ||
            !_positiveTime(p['verified_at']) ||
            !_positiveTime(p['order_created_at']) ||
            !_positiveTime(p['license_issued_at']) ||
            p['license_issued_at'] != lp['issued_at'] ||
            (p['verified_at'] as int) < (p['order_created_at'] as int) ||
            (p['license_issued_at'] as int) < (p['verified_at'] as int) ||
            p['date_source'] != 'verified_at' ||
            !await _signature(receipt, receiptContext)) {
          throw const OfflineAuthorizationException(
            '购买凭证验签或绑定检查未通过，原有授权保持。请重新复制完整授权。',
          );
        }
        final hash = await Sha256().hash(utf8.encode(license));
        final hex = hash.bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        if (hex != p['license_sha256']) {
          throw const OfflineAuthorizationException('购买凭证与授权不匹配，请重新复制完整授权。');
        }
        verifiedReceipt = VerifiedWebsiteReceipt(
          orderReference: p['order_reference'] as String,
          amountMinor: p['amount_minor'] as int,
          currency: p['currency'] as String,
          licenseId: p['license_id'] as String,
          verifiedAt: DateTime.fromMillisecondsSinceEpoch(
            (p['verified_at'] as int) * 1000,
            isUtc: true,
          ),
        );
      }
      return VerifiedWebsiteAuthorization(
        storageText: text,
        license: license,
        licenseId: lp['license_id'] as String,
        receipt: verifiedReceipt,
      );
    } on OfflineAuthorizationException {
      rethrow;
    } on Object {
      throw const OfflineAuthorizationException(
        '未识别到完整授权，请使用官网旁边的复制按钮，再点击“粘贴并激活”。',
      );
    }
  }

  /// A server-authenticated payload still requires the native, locally initiated request.
  Future<Map<String, dynamic>> verifyChallenge(
    String input,
    String installation, {
    DateTime? now,
  }) async {
    try {
      if (input.length > 8192 || utf8.encode(input).length > 8192) {
        throw const FormatException();
      }
      final envelope = strictOfflineJson(input);
      if (envelope is! Map<String, dynamic> ||
          envelope['payload'] is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final p = envelope['payload'] as Map<String, dynamic>;
      const fields = {
        'version',
        'purpose',
        'application_id',
        'channel',
        'installation_key_sha256',
        'request_id',
        'reference',
        'kind',
        'environment',
        'key_id',
        'challenge_id',
        'nonce',
        'issued_at',
        'expires_at',
        'audience',
        'browser_path',
        'browser_context',
      };
      final seconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
      if (!_fields(p, fields) ||
          p['version'] is! int ||
          p['version'] != 1 ||
          p['kind'] != 'cardock.offline-installation-challenge' ||
          p['environment'] != 'production' ||
          p['application_id'] != config.applicationId ||
          p['channel'] != 'website' ||
          p['installation_key_sha256'] != installation ||
          !{
            'purchase',
            'order_lookup',
            'order_manage',
            'license_read',
            'recovery',
          }.contains(p['purpose']) ||
          p['reference'] is! String ||
          p['audience'] != 'https://maskden.com' ||
          p['browser_path'] != '/cardock/offline/return' ||
          p['challenge_id'] is! String ||
          !RegExp(
            r'^[A-Za-z0-9_-]{32}$',
          ).hasMatch(p['challenge_id'] as String) ||
          decodeOfflineBase64(p['request_id'], maxLength: 43).length != 32 ||
          decodeOfflineBase64(p['nonce'], maxLength: 43).length != 32 ||
          decodeOfflineBase64(p['browser_context'], maxLength: 43).length !=
              32 ||
          !_positiveTime(p['issued_at']) ||
          !_positiveTime(p['expires_at']) ||
          (p['issued_at'] as int) > seconds + 60 ||
          (p['expires_at'] as int) <= seconds ||
          (p['expires_at'] as int) - (p['issued_at'] as int) != 300 ||
          !await _signature(envelope, challengeContext)) {
        throw const FormatException();
      }
      final needsReference = {
        'order_manage',
        'license_read',
      }.contains(p['purpose']);
      final reference = p['reference'] as String;
      if (needsReference
          ? !RegExp(r'^[A-Za-z0-9_-]{8,80}$').hasMatch(reference)
          : reference.isNotEmpty) {
        throw const FormatException();
      }
      return p;
    } on Object {
      throw const OfflineAuthorizationException(
        '安装挑战无效或已过期，请从Cardock重新发起并使用同一浏览器。',
      );
    }
  }
}
