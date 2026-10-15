import 'dart:async';
import 'package:flutter/services.dart';
import 'commercial_license_config.dart';
import 'distribution_channel.dart';
import 'entitlement_model.dart';
import 'purchase_gateway.dart';
import 'website_purchase_error.dart';
import 'website_offline_codec.dart';
import 'website_offline_browser.dart';

abstract interface class WebsiteAuthorizationGateway {
  Future<PurchaseActionResult> importAuthorization(String credential);
}

abstract interface class LicensePlatform {
  Future<Map<String, Object?>> inspect();
  Future<void> saveWebsiteLicense(String credential);
  Future<bool> verifyStore({required bool refresh});
  Future<String> purchaseStore();
  Future<String?> storePrice();
}

abstract interface class WebsiteAuthorizationRemovalPlatform {
  Future<void> removeWebsiteLicense(String expectedCredential);
}

final class MethodChannelLicensePlatform
    implements LicensePlatform, WebsiteAuthorizationRemovalPlatform {
  const MethodChannelLicensePlatform();
  static const _channel = MethodChannel('cardock/commercial_license');
  @override
  Future<Map<String, Object?>> inspect() async => Map<String, Object?>.from(
    await _channel
            .invokeMapMethod<String, Object?>('inspect')
            .timeout(const Duration(seconds: 20)) ??
        const {},
  );
  @override
  Future<void> saveWebsiteLicense(String credential) => _channel
      .invokeMethod<void>('saveWebsiteLicense', {'credential': credential})
      .timeout(const Duration(seconds: 20));
  @override
  Future<void> removeWebsiteLicense(String expectedCredential) => _channel
      .invokeMethod<void>('removeWebsiteLicense', {
        'expectedCredential': expectedCredential,
      })
      .timeout(const Duration(seconds: 20));
  @override
  Future<String> purchaseStore() async =>
      await _channel
          .invokeMethod<String>('purchaseStore')
          .timeout(const Duration(minutes: 6)) ??
      'unavailable';
  @override
  Future<String?> storePrice() => _channel
      .invokeMethod<String>('storePrice')
      .timeout(const Duration(seconds: 30));
  @override
  Future<bool> verifyStore({required bool refresh}) async =>
      await _channel
          .invokeMethod<bool>('verifyStore', {'refresh': refresh})
          .timeout(const Duration(seconds: 45)) ==
      true;
}

final class CommercialPurchaseGateway
    implements
        PurchaseGateway,
        DistributionAwarePurchaseGateway,
        WebsiteAuthorizationGateway {
  CommercialPurchaseGateway({
    required this.config,
    this._platform = const MethodChannelLicensePlatform(),
    Future<bool> Function(Uri)? openCheckout,
    WebsiteOfflineBrowser? offlineBrowser,
  }) : _openCheckout = openCheckout ?? WebsiteOfflineBrowser.open,
       _offlineBrowser = offlineBrowser ?? WebsiteOfflineBrowser(),
       _codec = WebsiteOfflineCodec(config);
  final CommercialLicenseConfig config;
  final LicensePlatform _platform;
  final Future<bool> Function(Uri) _openCheckout;
  final WebsiteOfflineBrowser _offlineBrowser;
  final WebsiteOfflineCodec _codec;
  VerifiedWebsiteReceipt? websiteReceipt;
  final _events = StreamController<ProductEntitlement>.broadcast();
  bool _disposed = false;
  @override
  CardockDistributionChannel get distributionChannel => config.channel;
  @override
  Stream<ProductEntitlement> get entitlementStream => _events.stream;
  bool _trusted(Map<String, Object?> context) =>
      context['trusted'] == true &&
      context['channel'] == distributionChannel.wireValue &&
      context['applicationId'] == config.applicationId &&
      context['installationKeySha256'] is String &&
      RegExp(
        r'^[a-f0-9]{64}$',
      ).hasMatch(context['installationKeySha256'] as String);
  @override
  Future<ProductEntitlement> query() async {
    websiteReceipt = null;
    try {
      final context = await _platform.inspect();
      if (!_trusted(context)) return ProductEntitlement.free;
      if (distributionChannel.isStore) {
        return await _platform.verifyStore(refresh: false)
            ? ProductEntitlement.purchased
            : ProductEntitlement.free;
      }
      if (distributionChannel != CardockDistributionChannel.website) {
        return ProductEntitlement.free;
      }
      websiteReceipt = null;
      final license = context['websiteLicense'];
      if (license is! String) return ProductEntitlement.free;
      final verified = await _codec.verifyAuthorization(
        license,
        context['installationKeySha256'] as String,
      );
      websiteReceipt = verified.receipt;
      return ProductEntitlement.purchased;
    } on Object {
      websiteReceipt = null;
      return ProductEntitlement.free;
    }
  }

  @override
  Future<PurchaseActionResult> purchase() async {
    if (distributionChannel.isStore) {
      try {
        if (!_trusted(await _platform.inspect())) return _denied();
        final outcome = await _platform.purchaseStore();
        final entitlement = await query();
        if (outcome == 'purchased' && entitlement.hasFullVersion) {
          return PurchaseActionResult.completed(entitlement: entitlement);
        }
        return PurchaseActionResult.unavailable(
          entitlement: entitlement,
          message: switch (outcome) {
            'pending' => '付款正在等待确认，完成后可恢复购买。',
            'cancelled' => '已取消付款。',
            _ => '商店购买暂不可用，请稍后重试。',
          },
        );
      } on Object {
        return _denied();
      }
    }
    return openWebsiteRequest('purchase', '', () => true);
  }

  @override
  Future<PurchaseActionResult> restore() async {
    try {
      final context = await _platform.inspect();
      if (!_trusted(context)) return _denied();
      if (distributionChannel.isStore &&
          await _platform.verifyStore(refresh: true)) {
        return const PurchaseActionResult.completed(
          entitlement: ProductEntitlement.purchased,
        );
      }
      if (!distributionChannel.isStore && (await query()).hasFullVersion) {
        return const PurchaseActionResult.completed(
          entitlement: ProductEntitlement.purchased,
        );
      }
      return _denied();
    } on Object {
      return _denied();
    }
  }

  static PurchaseActionResult _denied() =>
      const PurchaseActionResult.noPurchaseFound(
        message: '购买资格暂未确认。请检查商店账号与网络后重试；已有记录和备份仍可使用。',
      );
  @override
  Future<PurchaseActionResult> importAuthorization(
    String credential, {
    bool Function()? authorized,
  }) async {
    final allowed = authorized ?? () => true;
    var failureMessage = '授权验证或保存失败，原有授权保持。请重新复制完整授权。';
    try {
      final digest = await _websiteIdentity(allowed, requireCheckout: false);
      final incoming = await _codec.verifyAuthorization(credential, digest);
      if (!allowed()) throw const WebsitePurchaseException('access');
      final context = await _platform.inspect();
      VerifiedWebsiteAuthorization? previous;
      if (_trusted(context) && context['websiteLicense'] is String) {
        try {
          previous = await _codec.verifyAuthorization(
            context['websiteLicense'] as String,
            digest,
          );
        } on Object {
          /* Invalid previous storage never grants entitlement. */
        }
      }
      if (!allowed()) throw const WebsitePurchaseException('access');
      // Legacy imports cannot discard a previously verified purchase receipt.
      if (previous != null &&
          (previous.storageText == incoming.storageText ||
              (previous.receipt != null && incoming.receipt == null))) {
        websiteReceipt = previous.receipt;
        return const PurchaseActionResult.completed(
          entitlement: ProductEntitlement.purchased,
        );
      }
      await _platform.saveWebsiteLicense(incoming.storageText);
      final saved = await _platform.inspect();
      if (!allowed()) throw const WebsitePurchaseException('access');
      if (!_trusted(saved) ||
          saved['websiteLicense'] != incoming.storageText ||
          saved['installationKeySha256'] != digest) {
        throw const OfflineAuthorizationException('授权未能完整保存，请保留官网标签页并重试。');
      }
      final readback = await _codec.verifyAuthorization(
        saved['websiteLicense'] as String,
        digest,
      );
      if (!allowed()) throw const WebsitePurchaseException('access');
      websiteReceipt = readback.receipt;
      if (!_disposed) _events.add(ProductEntitlement.purchased);
      return PurchaseActionResult.completed(
        entitlement: ProductEntitlement.purchased,
        message: readback.receipt == null ? '已离线验证并激活完整版。' : '已离线激活，购买凭证已保存。',
      );
    } on OfflineAuthorizationException catch (error) {
      failureMessage = error.message;
    } on WebsitePurchaseException catch (error) {
      failureMessage = error.message;
    } on Object {
      /* Native atomic storage restores the prior ciphertext on failure. */
    }
    return PurchaseActionResult.failed(
      entitlement: await query(),
      message: failureMessage,
    );
  }

  Future<PurchaseActionResult> removeWebsiteAuthorization(
    bool Function() authorized,
  ) async {
    try {
      final digest = await _websiteIdentity(authorized, requireCheckout: false);
      final platform = _platform;
      if (platform is! WebsiteAuthorizationRemovalPlatform) {
        throw const WebsitePurchaseException('unsupported');
      }
      final before = await _platform.inspect();
      if (!authorized() ||
          !_trusted(before) ||
          before['installationKeySha256'] != digest) {
        throw const WebsitePurchaseException('access');
      }
      final previous = before['websiteLicense'];
      if (previous is String) {
        await (platform as WebsiteAuthorizationRemovalPlatform)
            .removeWebsiteLicense(previous);
      }
      final saved = await _platform.inspect();
      if (!authorized() ||
          !_trusted(saved) ||
          saved['websiteLicense'] != null ||
          saved['installationKeySha256'] != digest) {
        throw const WebsitePurchaseException('access');
      }
      websiteReceipt = null;
      if (!_disposed) _events.add(ProductEntitlement.free);
      return const PurchaseActionResult.completed(
        entitlement: ProductEntitlement.free,
        message: '已移除本机官网授权，恢复免费版。账号、订阅和安装身份已保留。',
      );
    } on Object {
      return PurchaseActionResult.failed(
        entitlement: await query(),
        message: '未能移除本机官网授权，请保持真实保险库解锁后重试。',
      );
    }
  }

  Future<String> _websiteIdentity(
    bool Function() authorized, {
    bool requireCheckout = true,
  }) async {
    if (!authorized()) throw const WebsitePurchaseException('access');
    if (distributionChannel != CardockDistributionChannel.website ||
        (requireCheckout &&
            config.checkout?.toString() != 'https://maskden.com/cardock/buy') ||
        config.publicKeys.isEmpty) {
      throw const WebsitePurchaseException('unsupported');
    }
    final context = await _platform.inspect();
    if (!authorized()) throw const WebsitePurchaseException('access');
    if (!_trusted(context)) throw const WebsitePurchaseException('identity');
    return context['installationKeySha256'] as String;
  }

  Future<PurchaseActionResult> openWebsiteRequest(
    String purpose,
    String reference,
    bool Function() authorized,
  ) async {
    try {
      final digest = await _websiteIdentity(authorized);
      if (purpose == 'purchase' && reference.isNotEmpty) {
        throw const WebsitePurchaseException('unsupported');
      }
      final bool opened;
      if (purpose == 'purchase') {
        if (!authorized()) throw const WebsitePurchaseException('access');
        opened = await _offlineBrowser.startPurchase(digest);
      } else {
        final target = await _offlineBrowser.begin(digest, purpose, reference);
        if (!authorized()) throw const WebsitePurchaseException('access');
        opened = await _openCheckout(target);
      }
      return opened
          ? PurchaseActionResult.externalOpened(entitlement: await query())
          : PurchaseActionResult.failed(
              entitlement: await query(),
              message: '无法打开外部浏览器，请重试。',
            );
    } on OfflineAuthorizationException catch (error) {
      return PurchaseActionResult.failed(
        entitlement: await query(),
        message: error.message,
      );
    } on Object catch (error) {
      return PurchaseActionResult.unavailable(
        entitlement: await query(),
        message: WebsitePurchaseException.from(error).message,
      );
    }
  }

  Future<PurchaseActionResult> handleWebsiteChallenge(
    String challenge,
    bool Function() authorized,
  ) async {
    try {
      final digest = await _websiteIdentity(authorized);
      final payload = await _codec.verifyChallenge(challenge, digest);
      if (!authorized()) throw const WebsitePurchaseException('access');
      final target = await _offlineBrowser.prove(payload);
      if (!authorized()) throw const WebsitePurchaseException('access');
      return await _openCheckout(target)
          ? PurchaseActionResult.externalOpened(entitlement: await query())
          : PurchaseActionResult.failed(
              entitlement: await query(),
              message: '无法返回原浏览器，请从Cardock重新发起。',
            );
    } on OfflineAuthorizationException catch (error) {
      return PurchaseActionResult.failed(
        entitlement: await query(),
        message: error.message,
      );
    } on Object catch (error) {
      return PurchaseActionResult.failed(
        entitlement: await query(),
        message: WebsitePurchaseException.from(error).message,
      );
    }
  }

  Future<PurchaseActionResult> openWebsiteOrders(
    bool Function() authorized,
  ) async {
    try {
      if (distributionChannel != CardockDistributionChannel.website) {
        throw const WebsitePurchaseException('unsupported');
      }
      if (!authorized()) throw const WebsitePurchaseException('access');
      final opened = await _openCheckout(
        Uri.parse('https://maskden.com/orders?view=remembered'),
      );
      return opened
          ? PurchaseActionResult.externalOpened(entitlement: await query())
          : PurchaseActionResult.failed(
              entitlement: await query(),
              message: '无法打开外部浏览器，请重试。',
            );
    } on Object catch (error) {
      return PurchaseActionResult.unavailable(
        entitlement: await query(),
        message: WebsitePurchaseException.from(error).message,
      );
    }
  }

  Future<PurchaseActionResult> openWebsiteRecovery({
    bool Function()? authorized,
  }) => openWebsiteRequest('recovery', '', authorized ?? () => true);

  Future<String?> loadPrice() async {
    try {
      return distributionChannel.isStore && _trusted(await _platform.inspect())
          ? await _platform.storePrice()
          : null;
    } on Object {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_events.close());
  }
}
