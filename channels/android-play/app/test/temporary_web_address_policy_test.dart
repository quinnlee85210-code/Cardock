import 'package:account_subscription_manager/core/temporary_web/temporary_web_address_provider_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('只接受 Android 常见 Wi-Fi 与热点接口名', () {
    for (final name in <String>[
      'wlan0',
      'wlan1',
      'swlan0',
      'wifi0',
      'ap0',
      'softap1',
    ]) {
      expect(
        TemporaryWebAddressPolicy.isTrustedWirelessInterfaceName(name),
        isTrue,
        reason: name,
      );
    }

    for (final name in <String>[
      'rmnet_data0',
      'ccmni0',
      'wwan0',
      'mobile0',
      'radio0',
      'tun0',
      'tap0',
      'ppp0',
      'eth0',
      'rndis0',
    ]) {
      expect(
        TemporaryWebAddressPolicy.isTrustedWirelessInterfaceName(name),
        isFalse,
        reason: name,
      );
    }
  });

  test('只接受 RFC1918 与 IPv4 链路本地地址，拒绝 CGNAT 和公网', () {
    for (final address in <List<int>>[
      <int>[10, 0, 0, 1],
      <int>[172, 16, 0, 1],
      <int>[172, 31, 255, 254],
      <int>[192, 168, 43, 1],
      <int>[169, 254, 10, 20],
    ]) {
      expect(
        TemporaryWebAddressPolicy.isPrivateOrLinkLocalIpv4(address),
        isTrue,
        reason: address.toString(),
      );
    }

    for (final address in <List<int>>[
      <int>[100, 64, 0, 1],
      <int>[100, 127, 255, 254],
      <int>[172, 15, 255, 255],
      <int>[172, 32, 0, 1],
      <int>[8, 8, 8, 8],
      <int>[127, 0, 0, 1],
      <int>[192, 168, 1],
    ]) {
      expect(
        TemporaryWebAddressPolicy.isPrivateOrLinkLocalIpv4(address),
        isFalse,
        reason: address.toString(),
      );
    }
  });
}
