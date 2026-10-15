import 'dart:async';
import 'package:flutter/services.dart';
import '../../../core/entitlements/distribution_channel.dart';
import '../../../core/entitlements/entitlement_model.dart';
import '../../../core/entitlements/entitlement_service.dart';
import '../../../core/entitlements/website_offline_codec.dart';
import '../../../core/entitlements/website_offline_browser.dart';
import '../../../l10n/localized_material.dart';
import '../../../l10n/context_l10n.dart';
import 'website_purchase_access.dart';

/// Receives complete local material; lifecycle events never query the website.
class WebsitePurchaseCoordinator extends StatefulWidget {
  const WebsitePurchaseCoordinator({
    required this.controller,
    required this.vaultChanges,
    required this.allowed,
    required this.unlocked,
    required this.navigatorKey,
    required this.child,
    super.key,
  });
  final ProductEntitlementController controller;
  final Listenable vaultChanges;
  final bool Function() allowed;
  final bool Function() unlocked;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  @override
  State<WebsitePurchaseCoordinator> createState() =>
      _WebsitePurchaseCoordinatorState();
}

class _WebsitePurchaseCoordinatorState extends State<WebsitePurchaseCoordinator>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('cardock/website_purchase_navigation');
  final _access = WebsitePurchaseAccess();
  Map<String, Object?>? _pending;
  DateTime? _pendingUntil;
  bool _presenting = false;
  bool _scheduled = false;
  bool _foreground = true;
  bool _receiving = false;
  Future<void> _nativeAccess = Future.value();
  bool get _website =>
      widget.controller.distributionChannel ==
      CardockDistributionChannel.website;

  @override
  void initState() {
    super.initState();
    widget.vaultChanges.addListener(_vaultChanged);
    WidgetsBinding.instance.addObserver(this);
    _syncAccess();
    if (_website) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'pendingAvailable') await _consume();
      });
      unawaited(_consume());
    }
  }

  void _syncAccess() {
    _access.update(_website && widget.allowed() && _foreground);
    if (_website) {
      _nativeAccess = WebsiteOfflineBrowser.channel
          .invokeMethod<void>('setWebsiteAccess', {'allowed': _access.allowed})
          .catchError((Object _) {});
    }
  }

  Future<void> _consume() async {
    if (_receiving || !mounted) return;
    _receiving = true;
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'consumeOfflinePending',
      );
      final legacy =
          value == null &&
          await _channel.invokeMethod<bool>('consumePending') == true;
      if (!mounted || (widget.unlocked() && !widget.allowed())) return;
      if (value != null || legacy) {
        // Keep only one bounded item; don't replace a user-visible operation.
        if (!_presenting) {
          _pending = value ?? {'kind': 'navigation', 'text': ''};
          _pendingUntil = DateTime.now().add(const Duration(minutes: 5));
        }
        _schedule();
      }
    } on Object {
      /* Native integration is absent on non-Android hosts. */
    } finally {
      _receiving = false;
    }
  }

  void _vaultChanged() {
    _syncAccess();
    if (widget.unlocked() && !widget.allowed()) {
      _pending = null;
      unawaited(
        _channel
            .invokeMethod<void>('clearOfflinePending')
            .catchError((Object _) {}),
      );
      unawaited(
        WebsiteOfflineBrowser.channel
            .invokeMethod<void>('clearOfflineRequest')
            .catchError((Object _) {}),
      );
    }
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncAccess();
    if (_foreground) {
      unawaited(_consume());
      _schedule();
    }
  }

  void _schedule() {
    if (!_website || _scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted &&
          _foreground &&
          !_presenting &&
          _access.allowed &&
          _pending != null) {
        unawaited(_present());
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _present() async {
    final item = _pending;
    _pending = null;
    if (item == null ||
        _pendingUntil == null ||
        !DateTime.now().isBefore(_pendingUntil!)) {
      return;
    }
    _presenting = true;
    final authorized = _access.lease();
    try {
      await _nativeAccess;
      if (!mounted || !authorized()) return;
      final text = item['text'];
      if (text is! String || text.length > WebsiteOfflineCodec.maxBytes) return;
      PurchaseActionResult? result;
      if (item['kind'] == 'activation') {
        result = await widget.controller.importWebsiteAuthorization(
          text,
          authorized: authorized,
        );
      } else if (item['kind'] == 'challenge') {
        result = await widget.controller.handleWebsiteChallenge(
          text,
          authorized,
        );
      } else if (item['kind'] == 'request' || item['kind'] == 'navigation') {
        final context = widget.navigatorKey.currentContext;
        if (context == null || !context.mounted) return;
        final request = item['kind'] == 'request'
            ? strictOfflineJson(text)
            : {'purpose': 'order_lookup', 'reference': ''};
        if (request is! Map<String, dynamic> ||
            request['purpose'] is! String ||
            request['reference'] is! String) {
          return;
        }
        final purpose = request['purpose'] as String;
        final reference = request['reference'] as String;
        if (!{
          'purchase',
          'recovery',
          'order_lookup',
          'order_manage',
          'license_read',
        }.contains(purpose)) {
          return;
        }
        final title = switch (purpose) {
          'license_read' => '准备此订单的离线授权',
          'order_manage' => '继续此订单',
          'recovery' => '恢复已有购买',
          'purchase' => '在浏览器中购买',
          _ => '在浏览器中查看官网订单',
        };
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(
              reference.isEmpty
                  ? '将打开外部浏览器。Cardock只提供本地安装证明，不访问网络。'
                  : context.tr('订单：{reference}\n将打开外部浏览器并重新证明本次安装。授权仍须离线验签。', {
                      'reference': reference,
                    }),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('继续'),
              ),
            ],
          ),
        );
        if (confirmed == true && authorized()) {
          result = await widget.controller.openWebsiteRequest(
            purpose,
            reference,
            authorized,
          );
        }
      } else if (item['kind'] == 'error') {
        _message('离线材料格式无效，请从官网原订单页重新打开。');
      }
      if (mounted &&
          authorized() &&
          result != null &&
          result.status != PurchaseActionStatus.externalOpened) {
        _message(result.message);
      }
    } on Object {
      if (mounted && authorized()) _message('离线操作未完成，请从官网原订单页重新打开。');
    } finally {
      _presenting = false;
      if (mounted) _schedule();
    }
  }

  void _message(String value) {
    final context = widget.navigatorKey.currentContext;
    if (context != null && _access.allowed) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(context.tr(value))));
    }
  }

  @override
  void dispose() {
    widget.vaultChanges.removeListener(_vaultChanged);
    WidgetsBinding.instance.removeObserver(this);
    _pending = null;
    if (_website) {
      _channel.setMethodCallHandler(null);
      unawaited(
        WebsiteOfflineBrowser.channel
            .invokeMethod<void>('setWebsiteAccess', {'allowed': false})
            .catchError((Object _) {}),
      );
    }
    _access.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      WebsitePurchaseScope(access: _access, child: widget.child);
}
