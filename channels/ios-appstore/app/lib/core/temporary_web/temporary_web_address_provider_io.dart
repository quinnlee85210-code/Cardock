import 'dart:io';

import 'package:flutter/services.dart';

import 'temporary_web_controller.dart';
import 'temporary_web_models.dart';

final class IoTemporaryWebAddressProvider
    implements TemporaryWebAddressProvider {
  const IoTemporaryWebAddressProvider({this.isIOS});
  final bool? isIOS;
  static const _iosChannel = MethodChannel('cardock/ios_local_network_v1');

  @override
  Future<List<TemporaryWebAddress>> listPrivateIpv4Addresses() async {
    if (isIOS ?? Platform.isIOS) {
      // The native bridge identifies Wi-Fi through Network.framework, not en* names.
      final raw = await _iosChannel.invokeListMethod<Object?>('listAddresses');
      final results = <TemporaryWebAddress>[];
      final seen = <String>{};
      for (final item in raw ?? const <Object?>[]) {
        if (item is! Map) continue;
        final value = item['address'];
        final name = item['interfaceName'];
        if (value is! String || name is! String || name.isEmpty) continue;
        final address = InternetAddress.tryParse(value);
        if (address == null ||
            address.type != InternetAddressType.IPv4 ||
            !TemporaryWebAddressPolicy.isPrivateOrLinkLocalIpv4(
              address.rawAddress,
            ) ||
            !seen.add(address.address)) {
          continue;
        }
        results.add(
          TemporaryWebAddress(address: address.address, interfaceName: name),
        );
      }
      return results;
    }
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: true,
    );
    final results = <TemporaryWebAddress>[];
    final seen = <String>{};
    for (final interface in interfaces) {
      if (!TemporaryWebAddressPolicy.isTrustedWirelessInterfaceName(
        interface.name,
      )) {
        continue;
      }
      for (final address in interface.addresses) {
        if (!TemporaryWebAddressPolicy.isPrivateOrLinkLocalIpv4(
          address.rawAddress,
        )) {
          continue;
        }
        if (!seen.add(address.address)) continue;
        results.add(
          TemporaryWebAddress(
            address: address.address,
            interfaceName: interface.name,
          ),
        );
      }
    }
    results.sort((left, right) {
      final addressOrder = left.address.compareTo(right.address);
      return addressOrder != 0
          ? addressOrder
          : left.interfaceName.compareTo(right.interfaceName);
    });
    return results;
  }

  @override
  Future<bool> isStillAvailable(String address) async {
    final candidates = await listPrivateIpv4Addresses();
    return candidates.any((candidate) => candidate.address == address);
  }
}

/// Fail-closed address policy for the Android-first trusted wireless flow.
///
/// Cellular, VPN, Ethernet, USB-tether and CGNAT interfaces are intentionally
/// not accepted even when they happen to use an RFC 1918 address.
final class TemporaryWebAddressPolicy {
  const TemporaryWebAddressPolicy._();

  static bool isTrustedWirelessInterfaceName(String name) {
    final normalized = name.trim().toLowerCase();
    return RegExp(r'^(?:wlan|swlan|wifi)[a-z0-9_.-]*$').hasMatch(normalized) ||
        RegExp(r'^(?:ap|softap)[0-9]*$').hasMatch(normalized);
  }

  static bool isPrivateOrLinkLocalIpv4(List<int> bytes) {
    if (bytes.length != 4) return false;
    final first = bytes[0];
    final second = bytes[1];
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168) ||
        (first == 169 && second == 254);
  }
}
