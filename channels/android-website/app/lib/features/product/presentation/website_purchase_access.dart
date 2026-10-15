import 'package:flutter/widgets.dart';

import '../../../core/entitlements/entitlement_model.dart';

/// An in-memory authorization lease is invalidated by every lock/access change.
class WebsitePurchaseAccess extends ChangeNotifier {
  bool _allowed = false;
  int _epoch = 0;
  DateTime? _returnUntil;
  bool get allowed => _allowed;

  void update(bool allowed) {
    if (_allowed == allowed) return;
    _allowed = allowed;
    _epoch++;
    if (!allowed) _returnUntil = null;
    notifyListeners();
  }

  bool Function() lease() {
    final epoch = _epoch;
    return () => _allowed && epoch == _epoch;
  }

  void browserResult(PurchaseActionResult result) {
    if (_allowed && result.status == PurchaseActionStatus.externalOpened) {
      _returnUntil = DateTime.now().add(const Duration(minutes: 10));
    }
  }

  bool consumeReturn() {
    final expiry = _returnUntil;
    _returnUntil = null;
    return _allowed && expiry != null && DateTime.now().isBefore(expiry);
  }

  @override
  void dispose() {
    _allowed = false;
    _epoch++;
    _returnUntil = null;
    super.dispose();
  }
}

class WebsitePurchaseScope extends InheritedNotifier<WebsitePurchaseAccess> {
  const WebsitePurchaseScope({
    required WebsitePurchaseAccess access,
    required super.child,
    super.key,
  }) : super(notifier: access);
  static WebsitePurchaseAccess? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WebsitePurchaseScope>()
      ?.notifier;
}
