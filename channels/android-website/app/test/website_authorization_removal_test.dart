import 'dart:convert';
import 'dart:io';
import 'package:account_subscription_manager/core/entitlements/commercial_license_config.dart';
import 'package:account_subscription_manager/core/entitlements/commercial_purchase_gateway.dart';
import 'package:account_subscription_manager/core/entitlements/distribution_channel.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_service.dart';
import 'package:account_subscription_manager/features/product/presentation/website_purchase_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'commercial_license_test.dart' show FakeLicensePlatform;
import 'website_purchase_gateway_test.dart' show NoHttp;

class RemovalPlatform extends FakeLicensePlatform
    implements WebsiteAuthorizationRemovalPlatform {
  int calls = 0;
  bool fail = false;
  bool retain = false;
  String? backup;
  @override
  Future<void> removeWebsiteLicense(String expectedCredential) async {
    calls++;
    if (fail || credential != expectedCredential) {
      throw StateError('not removed');
    }
    backup = credential;
    if (!retain) credential = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = jsonDecode(
    File('test/fixtures/offline-server-v1.synthetic.json').readAsStringSync(),
  );
  late RemovalPlatform platform;
  late CommercialPurchaseGateway gateway;
  late ProductEntitlementController controller;
  late WebsitePurchaseAccess access;
  setUp(() async {
    platform = RemovalPlatform()
      ..digest = fixture['installation']
      ..credential = fixture['activation'];
    gateway = CommercialPurchaseGateway(
      config: CommercialLicenseConfig(
        channel: CardockDistributionChannel.website,
        websitePublicKeys: jsonEncode(fixture['public_keys']),
      ),
      platform: platform,
    );
    controller = ProductEntitlementController(gateway: gateway);
    access = WebsitePurchaseAccess()..update(true);
    await controller.initialize();
  });
  tearDown(() {
    controller.dispose();
    access.dispose();
  });
  test(
    'local removal backs up credential, clears entitlement and preserves installation; no network',
    () async {
      expect(controller.hasFullVersion, isTrue);
      await HttpOverrides.runZoned(() async {
        final result = await controller.removeWebsiteAuthorization(
          access.lease(),
        );
        expect(result.succeeded, isTrue);
        expect(controller.hasFullVersion, isFalse);
        expect(platform.backup, fixture['activation']);
        expect(platform.digest, fixture['installation']);
        expect(platform.calls, 1);
        expect(gateway.websiteReceipt, isNull);
        expect(await gateway.query(), ProductEntitlement.free);
        expect(
          (await controller.removeWebsiteAuthorization(
            access.lease(),
          )).succeeded,
          isTrue,
        );
        expect(platform.calls, 1);
      }, createHttpClient: NoHttp().createHttpClient);
    },
  );
  for (final failure in [
    'locked',
    'lease-expired',
    'wrong-channel',
    'untrusted',
    'write-failed',
    'readback-retained',
  ]) {
    test(
      'removal refuses $failure and preserves active authorization',
      () async {
        final lease = access.lease();
        if (failure == 'locked') access.update(false);
        if (failure == 'lease-expired') {
          access.update(false);
          access.update(true);
        }
        if (failure == 'wrong-channel') platform.channel = 'google_play';
        if (failure == 'untrusted') platform.trusted = false;
        if (failure == 'write-failed') platform.fail = true;
        if (failure == 'readback-retained') platform.retain = true;
        final result = await controller.removeWebsiteAuthorization(lease);
        expect(result.succeeded, isFalse);
        expect(platform.credential, fixture['activation']);
        expect(
          platform.calls,
          ['write-failed', 'readback-retained'].contains(failure) ? 1 : 0,
        );
      },
    );
  }
}
