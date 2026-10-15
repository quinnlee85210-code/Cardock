import 'package:flutter/services.dart';

/// Safe local messages. Website network requests belong to the external browser.
final class WebsitePurchaseException implements Exception {
  const WebsitePurchaseException(this.code);
  final String code;
  String get message => switch (code) {
    'access' => '请正常解锁Cardock后重试；原有授权保持。',
    'CHECKOUT_BROWSER' => '无法打开外部浏览器，请确认手机已安装并启用浏览器。',
    'CHECKOUT_ACCESS' => '请正常解锁Cardock后重试；原有授权保持。',
    'CHECKOUT_PREPARE' => '本地购买证明准备失败（P01），请重新打开Cardock后重试；已有数据和授权保持。',
    'identity' => '安装签名身份不匹配，请从官网获取正式版本。',
    'unsupported' => '请使用官网正式版本的购买入口，或手动粘贴完整授权。',
    _ => '本地购买操作未完成，请从Cardock重新发起；原有授权保持。',
  };
  static WebsitePurchaseException from(Object error) =>
      error is WebsitePurchaseException
      ? error
      : error is PlatformException && error.code.startsWith('CHECKOUT_')
      ? WebsitePurchaseException(error.code)
      : const WebsitePurchaseException('unavailable');
  @override
  String toString() => 'WebsitePurchaseException($code)';
}
