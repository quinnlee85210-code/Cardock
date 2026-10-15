import 'temporary_web_controller.dart';
import 'temporary_web_models.dart';

/// Website builds instantiate only this non-network implementation.
final class OfflineTemporaryWebTransport implements TemporaryWebTransport {
  @override
  Future<TemporaryWebTransportBinding> start({
    required String address,
    required TemporaryWebCommandHandler onCommand,
    required void Function(String remoteAddress) onPaired,
    required void Function(Object error) onFatalError,
  }) async => throw UnsupportedError('The website app has no network access.');
  @override
  void revoke() {}
  @override
  Future<void> stop() async {}
}

final class OfflineTemporaryWebAddressProvider
    implements TemporaryWebAddressProvider {
  const OfflineTemporaryWebAddressProvider();
  @override
  Future<List<TemporaryWebAddress>> listPrivateIpv4Addresses() async =>
      const [];
  @override
  Future<bool> isStillAvailable(String address) async => false;
}
