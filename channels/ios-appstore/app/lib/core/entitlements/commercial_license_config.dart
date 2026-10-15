import 'dart:convert';
import 'distribution_channel.dart';

/// Public build configuration only. Missing production values never grant access.
final class CommercialLicenseConfig {
  const CommercialLicenseConfig({
    required this.channel,
    this.checkoutUrl = '',
    this.websitePublicKeys = '',
    this.applicationId = 'com.localaccount.account_subscription_manager',
  });
  factory CommercialLicenseConfig.environment() => CommercialLicenseConfig(
    channel: CardockDistributionConfig.channel,
    checkoutUrl: const String.fromEnvironment('CARDOCK_CHECKOUT_URL'),
    websitePublicKeys: const String.fromEnvironment(
      'CARDOCK_WEBSITE_PUBLIC_KEYS',
    ),
    applicationId: const String.fromEnvironment(
      'CARDOCK_APPLICATION_ID',
      defaultValue: 'com.localaccount.account_subscription_manager',
    ),
  );
  final CardockDistributionChannel channel;
  final String checkoutUrl;
  final String websitePublicKeys;
  final String applicationId;

  Uri? get checkout {
    final uri = Uri.tryParse(checkoutUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !uri.host.contains('.') ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasQuery ||
        uri.port != 443 ||
        uri.host.endsWith('.invalid') ||
        uri.host == 'localhost' ||
        RegExp(r'^[0-9.:]+$').hasMatch(uri.host)) {
      return null;
    }
    return uri;
  }

  Map<String, List<int>> get publicKeys {
    try {
      final decoded = jsonDecode(websitePublicKeys);
      if (decoded is! Map<String, dynamic> ||
          decoded.isEmpty ||
          decoded.length > 8) {
        return const {};
      }
      final result = <String, List<int>>{};
      for (final entry in decoded.entries) {
        if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(entry.key) ||
            entry.value is! String) {
          return const {};
        }
        final bytes = base64Url.decode(
          base64Url.normalize(entry.value as String),
        );
        if (bytes.length != 32) return const {};
        result[entry.key] = bytes;
      }
      return result;
    } on Object {
      return const {};
    }
  }
}
