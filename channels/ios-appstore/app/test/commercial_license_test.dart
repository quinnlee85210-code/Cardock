import 'package:account_subscription_manager/core/theme/cardock_theme_types.dart';
import 'dart:convert';
import 'package:account_subscription_manager/core/entitlements/commercial_license_config.dart';
import 'package:account_subscription_manager/core/entitlements/commercial_purchase_gateway.dart';
import 'package:account_subscription_manager/core/entitlements/distribution_channel.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_guard.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_service.dart';
import 'package:account_subscription_manager/core/entitlements/website_license_prototype.dart';
import 'package:account_subscription_manager/core/entitlements/website_license_verifier.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeLicensePlatform implements LicensePlatform {
  String digest = 'a' * 64;
  String channel = 'website';
  String applicationId = 'com.localaccount.account_subscription_manager';
  bool trusted = true;
  String? credential;
  bool store = false;
  bool failWrite = false;
  bool corruptWrite = false;
  int purchaseCalls = 0;
  int restoreCalls = 0;
  String outcome = 'purchased';
  @override
  Future<Map<String, Object?>> inspect() async => {
    'trusted': trusted,
    'channel': channel,
    'applicationId': applicationId,
    'installationKeySha256': digest,
    'websiteLicense': credential,
  };
  @override
  Future<void> saveWebsiteLicense(String value) async {
    if (failWrite) throw StateError('write unavailable');
    credential = corruptWrite ? '{}' : value;
  }

  @override
  Future<bool> verifyStore({required bool refresh}) async {
    if (refresh) restoreCalls++;
    return store;
  }

  @override
  Future<String> purchaseStore() async {
    purchaseCalls++;
    return outcome;
  }

  @override
  Future<String?> storePrice() async => '¥9.90';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SimpleKeyPair key;
  late List<int> publicKey;
  late FakeLicensePlatform platform;
  late CommercialPurchaseGateway gateway;
  late WebsiteLicenseVerifier verifier;
  late Map<String, Object?> payload;
  late List<Uri> urls;
  Future<String> signed([Map<String, Object?>? value]) async {
    final p = value ?? payload;
    final signature = await Ed25519().sign(
      utf8.encode(canonicalWebsiteLicenseJson(p)),
      keyPair: key,
    );
    return jsonEncode({
      'payload': p,
      'signature': base64Url.encode(signature.bytes),
    });
  }

  setUp(() async {
    key = await Ed25519().newKeyPair();
    publicKey = (await key.extractPublicKey()).bytes;
    platform = FakeLicensePlatform();
    urls = [];
    payload = {
      'version': 2,
      'kind': websiteLicenseKind,
      'product_id': websiteLicenseProduct,
      'channel': 'website',
      'environment': 'production',
      'application_id': platform.applicationId,
      'installation_key_sha256': platform.digest,
      'key_id': 'test_public_only',
      'license_id': 'test_license_1234',
      'issued_at': 1788000000,
    };
    verifier = WebsiteLicenseVerifier(
      publicKeys: {'test_public_only': publicKey},
      applicationId: platform.applicationId,
    );
    gateway = CommercialPurchaseGateway(
      config: CommercialLicenseConfig(
        channel: CardockDistributionChannel.website,
        checkoutUrl: 'https://checkout.cardock.example/purchase',
        websitePublicKeys: jsonEncode({
          'test_public_only': base64Url.encode(publicKey),
        }),
      ),
      platform: platform,
      openCheckout: (uri) async {
        urls.add(uri);
        return true;
      },
    );
  });
  tearDown(() => gateway.dispose());
  test('unknown distribution never falls back to development promotion', () {
    expect(
      CardockDistributionConfig.parse('google_plaay'),
      CardockDistributionChannel.unsupported,
    );
  });
  test(
    'valid full-digest production license grants only after persisted readback',
    () async {
      expect(await gateway.query(), ProductEntitlement.free);
      final result = await gateway.importAuthorization(await signed());
      expect(result.succeeded, isTrue);
      expect(await gateway.query(), ProductEntitlement.purchased);
    },
  );
  for (final field in [
    'version',
    'kind',
    'product_id',
    'channel',
    'environment',
    'application_id',
    'installation_key_sha256',
    'key_id',
    'license_id',
    'issued_at',
  ]) {
    test('rejects signed wrong $field', () async {
      final wrong = {
        ...payload,
        field: field == 'version'
            ? 1
            : field == 'issued_at'
            ? -1
            : 'wrong',
      };
      expect(
        await verifier.verify(await signed(wrong), platform.digest),
        isFalse,
      );
    });
  }
  test('tampering without a matching signature is rejected', () async {
    final envelope = jsonDecode(await signed()) as Map<String, dynamic>;
    (envelope['payload'] as Map<String, dynamic>)['license_id'] =
        'altered_license_1234';
    expect(
      await verifier.verify(jsonEncode(envelope), platform.digest),
      isFalse,
    );
  });
  test(
    'copied identifier or license without native key proof cannot grant',
    () async {
      platform.credential = await signed();
      platform.trusted = false;
      expect(await gateway.query(), ProductEntitlement.free);
      expect((await gateway.purchase()).succeeded, isFalse);
      expect(urls, isEmpty);
    },
  );
  test('copied license on another installation is denied', () async {
    platform.credential = await signed();
    platform.digest = 'b' * 64;
    expect(await gateway.query(), ProductEntitlement.free);
  });
  test('malformed and oversized credentials are rejected', () async {
    for (final value in ['[]', '{}', 'x' * 16385]) {
      expect(await verifier.verify(value, platform.digest), isFalse);
    }
  });
  test('failed disk write never grants a new license', () async {
    platform.failWrite = true;
    expect(
      (await gateway.importAuthorization(await signed())).succeeded,
      isFalse,
    );
    expect(await gateway.query(), ProductEntitlement.free);
  });
  test('corrupt persisted readback never grants a new license', () async {
    platform.corruptWrite = true;
    expect(
      (await gateway.importAuthorization(await signed())).succeeded,
      isFalse,
    );
  });
  test('invalid import preserves a previously valid credential', () async {
    final value = await signed();
    platform.credential = value;
    expect(
      (await gateway.importAuthorization('{}')).entitlement,
      ProductEntitlement.purchased,
    );
    expect(platform.credential, value);
  });
  test(
    'website navigation sends public binding only and never counts as payment',
    () async {
      final result = await gateway.purchase();
      expect(result.status, PurchaseActionStatus.externalOpened);
      expect(result.succeeded, isFalse);
      expect(await gateway.query(), ProductEntitlement.free);
      expect(urls.single.host, 'checkout.cardock.example');
      expect(urls.single.queryParameters.keys.toSet(), {
        'installation_key_sha256',
        'application_id',
        'license_version',
      });
    },
  );
  test('missing website config does not launch any browser or grant', () async {
    final empty = CommercialPurchaseGateway(
      config: const CommercialLicenseConfig(
        channel: CardockDistributionChannel.website,
      ),
      platform: platform,
      openCheckout: (uri) async {
        urls.add(uri);
        return true;
      },
    );
    expect((await empty.purchase()).status, PurchaseActionStatus.unavailable);
    expect(urls, isEmpty);
    empty.dispose();
  });
  test('checkout configuration rejects unsafe or redirected URL inputs', () {
    for (final value in [
      '',
      'http://pay.example/buy',
      'https://user:pass@pay.example',
      'https://pay.example?redirect=x',
      'https://pay.example/#x',
      'https://127.0.0.1/pay',
      'https://pay.invalid',
      'https://pay.example:444',
    ]) {
      expect(
        CommercialLicenseConfig(
          channel: CardockDistributionChannel.website,
          checkoutUrl: value,
        ).checkout,
        isNull,
        reason: value,
      );
    }
  });
  for (final channel in [
    CardockDistributionChannel.googlePlay,
    CardockDistributionChannel.appStore,
  ]) {
    test(
      '${channel.wireValue} uses in-app store purchase and independent restore, never website',
      () async {
        platform.channel = channel.wireValue;
        final store = CommercialPurchaseGateway(
          config: CommercialLicenseConfig(channel: channel),
          platform: platform,
          openCheckout: (uri) async {
            urls.add(uri);
            return true;
          },
        );
        expect(await store.query(), ProductEntitlement.free);
        platform.store = true;
        expect((await store.purchase()).succeeded, isTrue);
        expect(platform.purchaseCalls, 1);
        expect(platform.restoreCalls, 0);
        expect((await store.restore()).succeeded, isTrue);
        expect(platform.restoreCalls, 1);
        expect(urls, isEmpty);
        expect(
          (await store.importAuthorization(await signed())).succeeded,
          isFalse,
        );
        store.dispose();
      },
    );
    for (final outcome in ['pending', 'cancelled', 'unavailable']) {
      test('${channel.wireValue} $outcome never grants entitlement', () async {
        platform.channel = channel.wireValue;
        platform.outcome = outcome;
        final store = CommercialPurchaseGateway(
          config: CommercialLicenseConfig(channel: channel),
          platform: platform,
        );
        expect((await store.purchase()).entitlement, ProductEntitlement.free);
        store.dispose();
      });
    }
  }
  test(
    'reported purchase success alone cannot bypass receipt verification',
    () async {
      platform.channel = 'google_play';
      platform.outcome = 'purchased';
      platform.store = false;
      final store = CommercialPurchaseGateway(
        config: const CommercialLicenseConfig(
          channel: CardockDistributionChannel.googlePlay,
        ),
        platform: platform,
      );
      expect((await store.purchase()).succeeded, isFalse);
      store.dispose();
    },
  );
  test(
    'commercial channels reject the old promotion as an alternate grant',
    () async {
      final promo = ValueNotifier(ProductEntitlement.purchased);
      final controller = ProductEntitlementController(
        gateway: gateway,
        promoEntitlementListenable: promo,
      );
      await controller.initialize();
      expect(controller.hasFullVersion, isFalse);
      expect(controller.isPromoActivated, isFalse);
      controller.dispose();
      promo.dispose();
    },
  );
  test(
    'verified license controls business limits and themes while recovery remains available',
    () async {
      const guard = EntitlementGuard();
      final controller = ProductEntitlementController(gateway: gateway);
      await controller.initialize();
      expect(
        guard
            .accountCreation(entitlement: controller.value, currentAccounts: 15)
            .allowed,
        isFalse,
      );
      expect(
        guard
            .subscriptionCreation(
              entitlement: controller.value,
              currentSubscriptions: 5,
            )
            .allowed,
        isFalse,
      );
      final premium = CardockThemeFamily.values.firstWhere(
        (family) => family.isPremium,
      );
      expect(
        guard.canUseTheme(entitlement: controller.value, family: premium),
        isFalse,
      );
      await controller.importWebsiteAuthorization(await signed());
      expect(
        guard
            .accountCreation(entitlement: controller.value, currentAccounts: 99)
            .allowed,
        isTrue,
      );
      expect(
        guard
            .subscriptionCreation(
              entitlement: controller.value,
              currentSubscriptions: 99,
            )
            .allowed,
        isTrue,
      );
      expect(
        guard.canUseTheme(entitlement: controller.value, family: premium),
        isTrue,
      );
      platform.trusted = false;
      await controller.initialize();
      expect(controller.hasFullVersion, isFalse);
      expect(
        guard.canRestoreBackup(
          entitlement: controller.value,
          importedAccounts: 999,
          importedSubscriptions: 999,
        ),
        isTrue,
      );
      controller.dispose();
    },
  );
}
