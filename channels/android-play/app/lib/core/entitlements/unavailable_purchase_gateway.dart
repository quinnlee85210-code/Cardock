import 'dart:async';

import 'distribution_channel.dart';
import 'entitlement_model.dart';
import 'purchase_gateway.dart';

/// Fail-closed boundary for channel builds whose real payment adapter is absent.
final class UnavailablePurchaseGateway
    implements PurchaseGateway, DistributionAwarePurchaseGateway {
  const UnavailablePurchaseGateway(this.distributionChannel);

  @override
  final CardockDistributionChannel distributionChannel;

  @override
  Stream<ProductEntitlement> get entitlementStream => const Stream.empty();

  @override
  Future<ProductEntitlement> query() async => ProductEntitlement.free;

  @override
  Future<PurchaseActionResult> purchase() async =>
      PurchaseActionResult.unavailable(
        message: switch (distributionChannel) {
          CardockDistributionChannel.website => '官网真实购买与生产授权尚未配置。',
          CardockDistributionChannel.googlePlay => 'Google Play 一次性内购尚未配置。',
          CardockDistributionChannel.appStore => 'App Store 一次性内购尚未配置。',
          CardockDistributionChannel.unsupported => '无法验证此安装，请从官方渠道获取应用。',
          CardockDistributionChannel.development => '正式版支付即将上线',
        },
      );

  @override
  Future<PurchaseActionResult> restore() async =>
      PurchaseActionResult.unavailable(
        message: switch (distributionChannel) {
          CardockDistributionChannel.website => '官网购买恢复尚未接入当前 Release。',
          CardockDistributionChannel.googlePlay =>
            'Google Play 购买恢复尚未接入当前 Release。',
          CardockDistributionChannel.appStore => 'App Store 一次性内购尚未配置。',
          CardockDistributionChannel.unsupported => '无法验证此安装，请从官方渠道获取应用。',
          CardockDistributionChannel.development => '正式版支付即将上线',
        },
      );

  @override
  void dispose() {}
}
