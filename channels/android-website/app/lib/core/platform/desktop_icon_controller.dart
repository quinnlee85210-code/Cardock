import 'dart:io';

import 'package:flutter/services.dart';

import '../theme/cardock_theme_types.dart';

abstract interface class DesktopIconBridge {
  /// Returns the launcher alias currently enabled on Android.
  ///
  /// A null result means launcher-icon switching is not supported on the
  /// current platform. Android protocol errors are reported as exceptions.
  Future<CardockLauncherFamily?> getActiveIcon();

  Future<void> setIcon(CardockLauncherFamily family);
}

final class MethodChannelDesktopIconBridge implements DesktopIconBridge {
  MethodChannelDesktopIconBridge({
    MethodChannel? channel,
    bool Function()? isAndroid,
    bool Function()? isIOS,
  }) : _channel = channel ?? const MethodChannel(channelName),
       _isAndroid = isAndroid ?? _platformIsAndroid,
       _isIOS = isIOS ?? _platformIsIOS;

  static const String channelName = 'cardock/launcher_icon';
  static const String getLauncherIconMethod = 'getLauncherIcon';
  static const String setLauncherIconMethod = 'setLauncherIcon';

  final MethodChannel _channel;
  final bool Function() _isAndroid;
  final bool Function() _isIOS;

  static bool _platformIsAndroid() => Platform.isAndroid;
  static bool _platformIsIOS() => Platform.isIOS;

  @override
  Future<CardockLauncherFamily?> getActiveIcon() async {
    if (!_isAndroid() && !_isIOS()) return null;

    final variant = await _channel.invokeMethod<String>(getLauncherIconMethod);
    if (variant == null) {
      throw const DesktopIconProtocolException(
        'Android launcher icon channel returned no active variant.',
      );
    }
    if (isLegacyCardockLauncherFamilyName(variant)) {
      throw DesktopIconMigrationRequiredException(variant);
    }
    final family = cardockLauncherFamilyFromName(variant);
    if (family != null) return family;
    throw DesktopIconProtocolException(
      'Android launcher icon channel returned an unknown variant: $variant',
    );
  }

  @override
  Future<void> setIcon(CardockLauncherFamily family) async {
    if (!_isAndroid() && !_isIOS()) return;

    await _channel.invokeMethod<void>(setLauncherIconMethod, <String, Object?>{
      'variant': family.name,
    });
  }
}

final class DesktopIconProtocolException implements Exception {
  const DesktopIconProtocolException(this.message);

  final String message;

  @override
  String toString() => 'DesktopIconProtocolException: $message';
}

final class DesktopIconMigrationRequiredException
    extends DesktopIconProtocolException {
  const DesktopIconMigrationRequiredException(this.legacyVariant)
    : super('Android launcher icon uses a legacy alias: $legacyVariant');

  final String legacyVariant;
}
