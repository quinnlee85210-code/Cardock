enum ProductEntitlement { free, purchased }

extension ProductEntitlementRules on ProductEntitlement {
  bool get hasFullVersion => this == ProductEntitlement.purchased;
}

enum PurchaseActionStatus {
  completed,
  externalOpened,
  noPurchaseFound,
  unavailable,
  failed,
}

final class PurchaseActionResult {
  const PurchaseActionResult._({
    required this.status,
    required this.entitlement,
    required this.message,
  });

  const PurchaseActionResult.completed({
    required ProductEntitlement entitlement,
    String message = '已解锁完整版。',
  }) : this._(
         status: PurchaseActionStatus.completed,
         entitlement: entitlement,
         message: message,
       );

  const PurchaseActionResult.externalOpened({
    required ProductEntitlement entitlement,
  }) : this._(
         status: PurchaseActionStatus.externalOpened,
         entitlement: entitlement,
         message: '已打开官网。付款后请导入官网提供的本安装授权。',
       );

  const PurchaseActionResult.noPurchaseFound({
    ProductEntitlement entitlement = ProductEntitlement.free,
    String message = '未查询到可恢复的购买记录。',
  }) : this._(
         status: PurchaseActionStatus.noPurchaseFound,
         entitlement: entitlement,
         message: message,
       );

  const PurchaseActionResult.unavailable({
    ProductEntitlement entitlement = ProductEntitlement.free,
    String message = '正式版支付即将上线',
  }) : this._(
         status: PurchaseActionStatus.unavailable,
         entitlement: entitlement,
         message: message,
       );

  const PurchaseActionResult.failed({
    required ProductEntitlement entitlement,
    String message = '购买状态暂时无法确认，请稍后重试。',
  }) : this._(
         status: PurchaseActionStatus.failed,
         entitlement: entitlement,
         message: message,
       );

  final PurchaseActionStatus status;
  final ProductEntitlement entitlement;
  final String message;

  bool get succeeded => status == PurchaseActionStatus.completed;
}
