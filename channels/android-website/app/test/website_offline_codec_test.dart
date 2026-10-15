import 'dart:convert';
import 'package:account_subscription_manager/core/entitlements/commercial_license_config.dart';
import 'package:account_subscription_manager/core/entitlements/commercial_purchase_gateway.dart';
import 'package:account_subscription_manager/core/entitlements/distribution_channel.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/entitlements/website_license_prototype.dart';
import 'package:account_subscription_manager/core/entitlements/website_offline_codec.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'commercial_license_test.dart' show FakeLicensePlatform;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SimpleKeyPair key;
  late CommercialLicenseConfig config;
  late WebsiteOfflineCodec codec;
  late FakeLicensePlatform platform;
  late CommercialPurchaseGateway gateway;
  const time = 1789000000;
  const keyId = 'offline_synthetic_only';
  String encode(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  Future<Map<String, dynamic>> envelope(
    Map<String, dynamic> payload,
    String context,
  ) async => {
    'payload': payload,
    'signature': encode(
      (await Ed25519().sign(
        utf8.encode(context + canonicalWebsiteLicenseJson(payload)),
        keyPair: key,
      )).bytes,
    ),
  };
  Future<String> license({String? id, int issuedAt = time}) async => jsonEncode(
    await envelope({
      'version': 2,
      'kind': websiteLicenseKind,
      'product_id': websiteLicenseProduct,
      'channel': 'website',
      'environment': 'production',
      'application_id': platform.applicationId,
      'installation_key_sha256': platform.digest,
      'key_id': keyId,
      'license_id': id ?? 'synthetic_license_001',
      'issued_at': issuedAt,
    }, ''),
  );
  Future<String> bundle({
    String? original,
    Map<String, dynamic> changes = const {},
  }) async {
    final raw = original ?? await license();
    final lp =
        (jsonDecode(raw) as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    final hash = await Sha256().hash(utf8.encode(raw));
    final receipt = await envelope({
      'version': 1,
      'kind': 'cardock.website.purchase-receipt',
      'key_id': keyId,
      'application_id': platform.applicationId,
      'product_id': websiteLicenseProduct,
      'channel': 'website',
      'environment': 'production',
      'installation_key_sha256': platform.digest,
      'license_id': lp['license_id'],
      'license_sha256': hash.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      'order_reference': '20260914001',
      'amount_minor': 990,
      'currency': 'CNY',
      'verified_at': time - 10,
      'date_source': 'verified_at',
      'order_created_at': time - 100,
      'license_issued_at': lp['issued_at'],
      ...changes,
    }, WebsiteOfflineCodec.receiptContext);
    return WebsiteOfflineCodec.prefix +
        jsonEncode({
          'kind': 'cardock-offline-activation-v1',
          'license': raw,
          'receipt': receipt,
        });
  }

  Future<String> challenge({Map<String, dynamic> changes = const {}}) async =>
      jsonEncode(
        await envelope({
          'version': 1,
          'purpose': 'purchase',
          'application_id': platform.applicationId,
          'channel': 'website',
          'installation_key_sha256': platform.digest,
          'request_id': encode(List.filled(32, 1)),
          'reference': '',
          'kind': 'cardock.offline-installation-challenge',
          'environment': 'production',
          'key_id': keyId,
          'challenge_id': 'c' * 32,
          'nonce': encode(List.filled(32, 2)),
          'issued_at': time - 5,
          'expires_at': time + 295,
          'audience': 'https://maskden.com',
          'browser_path': '/cardock/offline/return',
          'browser_context': encode(List.filled(32, 3)),
          ...changes,
        }, WebsiteOfflineCodec.challengeContext),
      );
  DateTime now() =>
      DateTime.fromMillisecondsSinceEpoch(time * 1000, isUtc: true);

  setUp(() async {
    key = await Ed25519().newKeyPair();
    platform = FakeLicensePlatform();
    config = CommercialLicenseConfig(
      channel: CardockDistributionChannel.website,
      checkoutUrl: 'https://maskden.com/cardock/buy',
      websitePublicKeys: jsonEncode({
        keyId: encode((await key.extractPublicKey()).bytes),
      }),
    );
    codec = WebsiteOfflineCodec(config);
    gateway = CommercialPurchaseGateway(config: config, platform: platform);
  });
  tearDown(() => gateway.dispose());

  test(
    'complete signed bundle preserves original bytes and trusted receipt after offline reload',
    () async {
      final original = await license();
      final text = await bundle(original: original);
      final parsed = await codec.verifyAuthorization(text, platform.digest);
      expect(parsed.license, original);
      expect(parsed.receipt!.orderReference, '20260914001');
      expect(parsed.receipt!.amountMinor, 990);
      expect(
        parsed.receipt!.verifiedAt.millisecondsSinceEpoch,
        (time - 10) * 1000,
      );
      expect(
        (await gateway.importAuthorization(
          text,
          authorized: () => true,
        )).succeeded,
        isTrue,
      );
      expect(platform.credential, text);
      expect(gateway.websiteReceipt!.orderReference, '20260914001');
      final restarted = CommercialPurchaseGateway(
        config: config,
        platform: platform,
      );
      addTearDown(restarted.dispose);
      expect(await restarted.query(), ProductEntitlement.purchased);
      expect(restarted.websiteReceipt!.amountMinor, 990);
    },
  );

  test(
    'legacy license remains supported and cannot discard a rich receipt',
    () async {
      final original = await license();
      expect((await gateway.importAuthorization(original)).succeeded, isTrue);
      expect(gateway.websiteReceipt, isNull);
      final text = await bundle(original: original);
      expect((await gateway.importAuthorization(text)).succeeded, isTrue);
      expect(platform.credential, text);
      expect((await gateway.importAuthorization(original)).succeeded, isTrue);
      expect(platform.credential, text);
      expect(gateway.websiteReceipt!.orderReference, '20260914001');
    },
  );

  test(
    'invalid receipt cannot downgrade to a valid standalone license or overwrite old state',
    () async {
      final good = await bundle();
      await gateway.importAuthorization(good);
      final raw =
          jsonDecode(good.substring(WebsiteOfflineCodec.prefix.length))
              as Map<String, dynamic>;
      (raw['receipt'] as Map<String, dynamic>)['signature'] = encode(
        List.filled(64, 0),
      );
      final bad = WebsiteOfflineCodec.prefix + jsonEncode(raw);
      final result = await gateway.importAuthorization(bad);
      expect(result.succeeded, isFalse);
      expect(result.entitlement, ProductEntitlement.purchased);
      expect(platform.credential, good);
      expect(gateway.websiteReceipt!.orderReference, '20260914001');
    },
  );

  for (final changes in <Map<String, dynamic>>[
    {'amount_minor': 991},
    {'amount_minor': true},
    {'currency': 'USD'},
    {'verified_at': time + 1},
    {'verified_at': time - 101},
    {'date_source': 'issued_at'},
    {'date_source': 'customer_claim'},
    {'license_id': 'another_license'},
    {'license_sha256': '0' * 64},
    {'installation_key_sha256': 'b' * 64},
    {'application_id': 'other.app'},
    {'product_id': 'other.product'},
    {'environment': 'test'},
    {'channel': 'google_play'},
    {'key_id': 'unknown_key'},
    {'order_reference': '<script>'},
    {'version': 1.0},
    {'paid_at': 'customer typed date'},
    {'admin_secret': 'not allowed'},
  ]) {
    test(
      'signed invalid receipt fields rejected: ${changes.keys.first} ${changes.values.first}',
      () async {
        final text = await bundle(changes: changes);
        await expectLater(
          codec.verifyAuthorization(text, platform.digest),
          throwsA(isA<OfflineAuthorizationException>()),
        );
      },
    );
  }

  test('license whitespace change still breaks receipt hash binding', () async {
    final text = await bundle();
    final raw =
        jsonDecode(text.substring(WebsiteOfflineCodec.prefix.length))
            as Map<String, dynamic>;
    raw['license'] = ' ${raw['license']}';
    await expectLater(
      codec.verifyAuthorization(
        WebsiteOfflineCodec.prefix + jsonEncode(raw),
        platform.digest,
      ),
      throwsA(isA<OfflineAuthorizationException>()),
    );
  });

  test(
    'duplicate fields malformed UTF structure unsupported wrapper and excessive length rejected',
    () async {
      final text = await bundle();
      final old = await license();
      for (final bad in [
        text.replaceFirst('"kind":', '"kind":"ignored","kind":'),
        old.replaceFirst('"payload":', '"signature":"ignored","payload":'),
        text.replaceFirst(
          'cardock-offline-activation-v1',
          'cardock-offline-activation-v2',
        ),
        'x' * (WebsiteOfflineCodec.maxBytes + 1),
        jsonEncode({
          'kind': 'cardock-offline-activation-v1',
          'license': old,
          'receipt': null,
        }),
        '[[]]',
        '{"payload":NaN}',
      ]) {
        await expectLater(
          codec.verifyAuthorization(bad, platform.digest),
          throwsA(isA<OfflineAuthorizationException>()),
        );
      }
    },
  );

  test(
    'failed atomic save and access loss keep previous license and receipt',
    () async {
      final old = await bundle();
      await gateway.importAuthorization(old);
      platform.failWrite = true;
      final newer = await bundle(
        original: await license(id: 'synthetic_license_002'),
      );
      expect((await gateway.importAuthorization(newer)).succeeded, isFalse);
      expect(platform.credential, old);
      platform.failWrite = false;
      expect(
        (await gateway.importAuthorization(
          newer,
          authorized: () => false,
        )).succeeded,
        isFalse,
      );
      expect(platform.credential, old);
      expect(gateway.websiteReceipt!.orderReference, '20260914001');
    },
  );

  test('tampered saved receipt never grants after restart', () async {
    platform.credential = await bundle(changes: {'license_sha256': 'f' * 64});
    expect(await gateway.query(), ProductEntitlement.free);
    expect(gateway.websiteReceipt, isNull);
  });

  test(
    'server challenge is authenticated offline with a distinct context',
    () async {
      final text = await challenge();
      final payload = await codec.verifyChallenge(
        text,
        platform.digest,
        now: now(),
      );
      expect(payload['purpose'], 'purchase');
      final raw = jsonDecode(text) as Map<String, dynamic>;
      final wrongContext = await envelope(
        raw['payload'] as Map<String, dynamic>,
        WebsiteOfflineCodec.receiptContext,
      );
      await expectLater(
        codec.verifyChallenge(
          jsonEncode(wrongContext),
          platform.digest,
          now: now(),
        ),
        throwsA(isA<OfflineAuthorizationException>()),
      );
    },
  );

  for (final changes in <Map<String, dynamic>>[
    {'purpose': 'admin'},
    {'purpose': 'license_read'},
    {'reference': '20260914001'},
    {'audience': 'https://evil.invalid'},
    {'browser_path': '/admin'},
    {'issued_at': time + 61, 'expires_at': time + 361},
    {'expires_at': time},
    {'expires_at': time + 296},
    {'installation_key_sha256': 'b' * 64},
    {'nonce': 'n' * 44},
    {'request_id': 'r' * 42},
    {'key_id': 'unknown'},
    {'version': true},
    {'extra': 'field'},
  ]) {
    test('invalid signed challenge rejected: ${changes.keys.first}', () async {
      await expectLater(
        codec.verifyChallenge(
          await challenge(changes: changes),
          platform.digest,
          now: now(),
        ),
        throwsA(isA<OfflineAuthorizationException>()),
      );
    });
  }

  test(
    'strict JSON allows harmless whitespace and rejects escaped duplicate keys',
    () {
      expect(strictOfflineJson(' { "a" : 1, "b" : [true,null,"x"] } '), {
        'a': 1,
        'b': [true, null, 'x'],
      });
      expect(
        () => strictOfflineJson(r'{"a":1,"\u0061":2}'),
        throwsFormatException,
      );
      expect(() => decodeOfflineBase64('AA='), throwsFormatException);
    },
  );
}
