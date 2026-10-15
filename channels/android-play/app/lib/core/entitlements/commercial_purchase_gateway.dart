import 'dart:async';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'commercial_license_config.dart';
import 'distribution_channel.dart';
import 'entitlement_model.dart';
import 'purchase_gateway.dart';
import 'website_license_verifier.dart';

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

final class MethodChannelLicensePlatform implements LicensePlatform {
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
  }) : _openCheckout = openCheckout ?? _launch,
       _verifier = WebsiteLicenseVerifier(
         publicKeys: config.publicKeys,
         applicationId: config.applicationId,
       );
  final CommercialLicenseConfig config;
  final LicensePlatform _platform;
  final Future<bool> Function(Uri) _openCheckout;
  final WebsiteLicenseVerifier _verifier;
  final _events = StreamController<ProductEntitlement>.broadcast();
  bool _disposed = false;
  static Future<bool> _launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
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
      final license = context['websiteLicense'];
      return license is String &&
              await _verifier.verify(
                license,
                context['installationKeySha256'] as String,
              )
          ? ProductEntitlement.purchased
          : ProductEntitlement.free;
    } on Object {
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
    try {
      final context = await _platform.inspect();
      if (!_trusted(context)) {
        return const PurchaseActionResult.unavailable(
          message: '无法验证此安装，请从官方渠道获取应用。',
        );
      }
      final url = config.checkout;
      if (distributionChannel != CardockDistributionChannel.website ||
          url == null ||
          config.publicKeys.isEmpty) {
        return const PurchaseActionResult.unavailable(
          message: '官网购买尚未开放，请稍后再试。',
        );
      }
      // Only the public installation digest is sent; a browser return cannot grant a license.
      final target = url.replace(
        queryParameters: {
          'installation_key_sha256': context['installationKeySha256'] as String,
          'application_id': config.applicationId,
          'license_version': '2',
        },
      );
      final opened = await _openCheckout(target);
      final entitlement = await query();
      return opened
          ? PurchaseActionResult.externalOpened(entitlement: entitlement)
          : PurchaseActionResult.failed(
              entitlement: entitlement,
              message: '无法打开官网，请稍后再试。',
            );
    } on Object {
      return const PurchaseActionResult.unavailable(
        message: '无法验证此安装，请从官方渠道获取应用。',
      );
    }
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
  Future<PurchaseActionResult> importAuthorization(String credential) async {
    try {
      final context = await _platform.inspect();
      if (distributionChannel == CardockDistributionChannel.website &&
          _trusted(context) &&
          await _verifier.verify(
            credential,
            context['installationKeySha256'] as String,
          )) {
        await _platform.saveWebsiteLicense(credential);
        // Read back through the same verification path before granting anything.
        if ((await query()).hasFullVersion) {
          if (!_disposed) _events.add(ProductEntitlement.purchased);
          return const PurchaseActionResult.completed(
            entitlement: ProductEntitlement.purchased,
          );
        }
      }
    } on Object {
      /* Keep user data and any previously valid credential intact. */
    }
    return PurchaseActionResult.failed(
      entitlement: await query(),
      message: '授权无效或不属于此安装，请核对官网提供的授权。',
    );
  }

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
