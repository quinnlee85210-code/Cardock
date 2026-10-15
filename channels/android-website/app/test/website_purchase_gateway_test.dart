import 'dart:convert';
import 'dart:io';
import 'package:account_subscription_manager/core/entitlements/commercial_license_config.dart';
import 'package:account_subscription_manager/core/entitlements/commercial_purchase_gateway.dart';
import 'package:account_subscription_manager/core/entitlements/distribution_channel.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/entitlements/website_offline_browser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'commercial_license_test.dart' show FakeLicensePlatform;

class FakeOfflineBrowser {
  int beginCalls = 0;
  int purchaseCalls = 0;
  int openCalls = 0;
  Uri? opened;
  Object? error;
  void Function()? onBegin;
  String digest = 'a' * 64;
  WebsiteOfflineBrowser get bridge => WebsiteOfflineBrowser(
    startPurchase: (installation) async {
      expect(installation, digest);
      purchaseCalls++;
      if (error != null) throw error!;
      return true;
    },
    beginRequest: (purpose, reference) async {
      beginCalls++;
      onBegin?.call();
      if (error != null) throw error!;
      return {
        'version': 1,
        'application_id': 'com.localaccount.account_subscription_manager',
        'channel': 'website',
        'installation_key_sha256': digest,
        'request_id': base64Url.encode(List.filled(32, 2)).replaceAll('=', ''),
        'purpose': purpose,
        'reference': reference,
      };
    },
  );
  Future<bool> open(Uri uri) async {
    openCalls++;
    opened = uri;
    return true;
  }
}

class NoHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('APP attempted HTTP');
}

CommercialLicenseConfig offlineTestConfig([
  CardockDistributionChannel channel = CardockDistributionChannel.website,
]) => CommercialLicenseConfig(
  channel: channel,
  checkoutUrl: 'https://maskden.com/cardock/buy',
  websitePublicKeys: jsonEncode({'test': base64Url.encode(List.filled(32, 1))}),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeLicensePlatform platform;
  late FakeOfflineBrowser browser;
  late CommercialPurchaseGateway gateway;
  setUp(() {
    platform = FakeLicensePlatform();
    browser = FakeOfflineBrowser()..digest = platform.digest;
    gateway = CommercialPurchaseGateway(
      config: offlineTestConfig(),
      platform: platform,
      offlineBrowser: browser.bridge,
      openCheckout: browser.open,
    );
  });
  tearDown(() => gateway.dispose());
  test(
    'purchase lookup and recovery only prepare a local request and open a fixed browser',
    () async {
      await HttpOverrides.runZoned(() async {
        expect(await gateway.query(), ProductEntitlement.free);
        expect(browser.beginCalls, 0);
        for (final purpose in [
          'order_lookup',
          'recovery',
          'order_manage',
          'license_read',
        ]) {
          final reference = ['order_manage', 'license_read'].contains(purpose)
              ? '20260912001'
              : '';
          final result = await gateway.openWebsiteRequest(
            purpose,
            reference,
            () => true,
          );
          expect(result.status, PurchaseActionStatus.externalOpened);
          final uri = browser.opened!;
          expect(uri.origin, 'https://maskden.com');
          expect(uri.path, '/cardock/offline');
          expect(uri.query, isEmpty);
          final data = jsonDecode(
            utf8.decode(
              base64Url.decode(base64Url.normalize(uri.fragment.substring(8))),
            ),
          );
          expect(data['purpose'], purpose);
          expect(data['reference'], reference);
          expect(data['installation_key_sha256'], platform.digest);
        }
        expect(browser.openCalls, 4);
        expect(platform.credential, isNull);
      }, createHttpClient: (context) => throw StateError('APP attempted HTTP'));
    },
  );
  test(
    'purchase uses one native launch, never the challenge browser round trip',
    () async {
      await HttpOverrides.runZoned(() async {
        final result = await gateway.openWebsiteRequest(
          'purchase',
          '',
          () => true,
        );
        expect(result.status, PurchaseActionStatus.externalOpened);
        expect(result.entitlement, ProductEntitlement.free);
        expect(browser.purchaseCalls, 1);
        expect(browser.beginCalls, 0);
        expect(browser.openCalls, 0);
        expect(platform.credential, isNull);
        await gateway.openWebsiteRequest('purchase', '', () => false);
        await gateway.openWebsiteRequest('purchase', '20260914001', () => true);
        expect(browser.purchaseCalls, 1);
      }, createHttpClient: (_) => throw StateError('APP attempted HTTP'));
    },
  );
  test(
    'locking while local identity proof is prepared prevents browser opening',
    () async {
      var allowed = true;
      browser.onBegin = () => allowed = false;
      final r = await gateway.openWebsiteRequest(
        'order_lookup',
        '',
        () => allowed,
      );
      expect(r.succeeded, isFalse);
      expect(browser.openCalls, 0);
      expect(platform.credential, isNull);
    },
  );
  test(
    'closed access and wrong channels cannot prepare a website request',
    () async {
      await gateway.openWebsiteOrders(() => false);
      expect(browser.beginCalls, 0);
      for (final c in [
        CardockDistributionChannel.googlePlay,
        CardockDistributionChannel.appStore,
      ]) {
        final other = CommercialPurchaseGateway(
          config: offlineTestConfig(c),
          platform: platform,
          offlineBrowser: browser.bridge,
          openCheckout: browser.open,
        );
        expect((await other.openWebsiteOrders(() => true)).succeeded, isFalse);
        other.dispose();
      }
      expect(browser.beginCalls, 0);
      expect(browser.openCalls, 0);
    },
  );
  test('wrong installation result is rejected before navigation', () async {
    browser.digest = 'b' * 64;
    expect(
      (await gateway.openWebsiteRequest(
        'order_lookup',
        '',
        () => true,
      )).succeeded,
      isFalse,
    );
    expect(browser.openCalls, 0);
  });
  test(
    'local failure does not overwrite existing stored authorization',
    () async {
      platform.credential = 'existing-encrypted-slot-fixture';
      browser.error = StateError('local failure');
      await gateway.openWebsiteRequest('order_lookup', '', () => true);
      expect(platform.credential, 'existing-encrypted-slot-fixture');
      expect(browser.openCalls, 0);
    },
  );
}
