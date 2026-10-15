import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'entitlement_model.dart';
import 'promo_activation_codec.dart';
import 'promo_activation_store.dart';

enum PromoActivationActionStatus {
  activated,
  malformed,
  deviceMismatch,
  unavailable,
}

final class PromoActivationActionResult {
  const PromoActivationActionResult(this.status, this.message);

  final PromoActivationActionStatus status;
  final String message;

  bool get succeeded => status == PromoActivationActionStatus.activated;
}

typedef PromoInstallationIdGenerator = Uint8List Function();

final class PromoActivationController extends ChangeNotifier
    implements ValueListenable<ProductEntitlement> {
  PromoActivationController({
    required this.store,
    required this.verifier,
    PromoInstallationIdGenerator? installationIdGenerator,
  }) : _installationIdGenerator =
           installationIdGenerator ?? _generateInstallationId;

  final PromoActivationStore store;
  final PromoActivationVerifier verifier;
  final PromoInstallationIdGenerator _installationIdGenerator;
  PromoActivationRecord? _record;
  ProductEntitlement _value = ProductEntitlement.free;
  String? _requestCode;
  bool _initialized = false;
  bool _busy = false;
  bool _disposed = false;

  @override
  ProductEntitlement get value => _value;
  bool get isInitialized => _initialized;
  bool get isBusy => _busy;
  bool get isActivated => _value.hasFullVersion;
  String? get requestCode => _requestCode;

  Future<void> initialize() async {
    if (_initialized || _busy) return;
    _busy = true;
    _notifyIfActive();
    try {
      var record = await store.read();
      if (record == null) {
        record = PromoActivationRecord(
          installationId: _installationIdGenerator(),
        );
        await store.write(record);
      }
      _record = record;
      _requestCode = await derivePromoRequestCode(record.installationId);
      final activationCode = record.activationCode;
      if (activationCode != null && activationCode.isNotEmpty) {
        final verification = await verifier.verify(
          activationCode: activationCode,
          expectedRequestCode: _requestCode!,
        );
        _value = verification.isValid
            ? ProductEntitlement.purchased
            : ProductEntitlement.free;
      } else {
        _value = ProductEntitlement.free;
      }
    } on Object {
      _record = null;
      _requestCode = null;
      _value = ProductEntitlement.free;
    } finally {
      _busy = false;
      _initialized = true;
      _notifyIfActive();
    }
  }

  Future<PromoActivationActionResult> activate(String activationCode) async {
    final requestCode = _requestCode;
    final record = _record;
    if (!_initialized || requestCode == null || record == null || _busy) {
      return const PromoActivationActionResult(
        PromoActivationActionStatus.unavailable,
        '本机申请码尚未准备好，请稍后重试。',
      );
    }
    _busy = true;
    _notifyIfActive();
    try {
      final verification = await verifier.verify(
        activationCode: activationCode,
        expectedRequestCode: requestCode,
      );
      if (verification.status ==
          PromoActivationVerificationStatus.deviceMismatch) {
        return const PromoActivationActionResult(
          PromoActivationActionStatus.deviceMismatch,
          '此码不属于本设备。',
        );
      }
      if (!verification.isValid) {
        return const PromoActivationActionResult(
          PromoActivationActionStatus.malformed,
          '激活码格式不正确或签名无效。',
        );
      }
      final next = record.copyWith(activationCode: verification.canonicalCode!);
      await store.write(next);
      _record = next;
      _value = ProductEntitlement.purchased;
      _notifyIfActive();
      return const PromoActivationActionResult(
        PromoActivationActionStatus.activated,
        '已激活永久完整版。',
      );
    } on Object {
      return const PromoActivationActionResult(
        PromoActivationActionStatus.unavailable,
        '激活状态暂时无法保存，请重试。',
      );
    } finally {
      _busy = false;
      _notifyIfActive();
    }
  }

  static Uint8List _generateInstallationId() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(
        promoInstallationIdLength,
        (_) => random.nextInt(256),
        growable: false,
      ),
    );
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class PromoActivationScope
    extends InheritedNotifier<PromoActivationController> {
  const PromoActivationScope({
    required PromoActivationController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static PromoActivationController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'PromoActivationScope is missing.');
    return controller!;
  }

  static PromoActivationController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PromoActivationScope>()
      ?.notifier;
}
