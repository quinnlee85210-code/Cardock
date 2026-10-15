import 'dart:convert';
import 'dart:io';
import 'package:account_subscription_manager/core/entitlements/commercial_license_config.dart';
import 'package:account_subscription_manager/core/entitlements/distribution_channel.dart';
import 'package:account_subscription_manager/core/entitlements/website_offline_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Python worker signature and canonical bytes verify in the Dart APP codec',
    () async {
      final fixture = jsonDecode(
        await File(
          'test/fixtures/offline-server-v1.synthetic.json',
        ).readAsString(),
      );
      final codec = WebsiteOfflineCodec(
        CommercialLicenseConfig(
          channel: CardockDistributionChannel.website,
          websitePublicKeys: jsonEncode(fixture['public_keys']),
        ),
      );
      final verified = await codec.verifyAuthorization(
        fixture['activation'],
        fixture['installation'],
      );
      expect(verified.storageText, fixture['activation']);
      expect(verified.receipt!.orderReference, fixture['reference']);
      expect(verified.receipt!.amountMinor, 990);
      expect(verified.receipt!.currency, 'CNY');
      final bundle = jsonDecode(
        (fixture['activation'] as String).substring(
          WebsiteOfflineCodec.prefix.length,
        ),
      );
      expect(
        verified.receipt!.verifiedAt.millisecondsSinceEpoch ~/ 1000,
        bundle['receipt']['payload']['verified_at'],
      );
    },
  );
}
