import 'dart:io';

import 'package:flutter/services.dart';

/// Controls Android screenshot protection or iOS app-switcher preview privacy.
///
/// The preference itself is non-sensitive and is stored by Android so it can
/// be applied before Flutter renders its first frame. Business vault data and
/// passwords never pass through this channel.
abstract interface class ScreenProtectionService {
  Future<bool> readEnabled();

  Future<void> setEnabled(bool enabled);
}

final class MethodChannelScreenProtectionService
    implements ScreenProtectionService {
  MethodChannelScreenProtectionService({
    MethodChannel? channel,
    bool Function()? isAndroid,
    bool Function()? isIOS,
  }) : _channel = channel ?? const MethodChannel(channelName),
       _isAndroid = isAndroid ?? _platformIsAndroid,
       _isIOS = isIOS ?? _platformIsIOS;

  static const String channelName = 'cardock/screen_protection';
  static const String getSecureFlagMethod = 'getSecureFlag';
  static const String setSecureFlagMethod = 'setSecureFlag';

  final MethodChannel _channel;
  final bool Function() _isAndroid;
  final bool Function() _isIOS;

  static bool _platformIsIOS() => Platform.isIOS;

  static bool _platformIsAndroid() => Platform.isAndroid;

  @override
  Future<bool> readEnabled() async {
    if (!_isAndroid() && !_isIOS()) return true;
    final value = await _channel.invokeMethod<bool>(getSecureFlagMethod);
    if (value == null) {
      throw const ScreenProtectionProtocolException(
        'Screen protection channel returned no preference value.',
      );
    }
    return value;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    if (!_isAndroid() && !_isIOS()) return;
    await _channel.invokeMethod<void>(setSecureFlagMethod, <String, Object?>{
      'enabled': enabled,
    });
  }
}

final class MemoryScreenProtectionService implements ScreenProtectionService {
  MemoryScreenProtectionService({this.enabled = true});

  bool enabled;
  int readCalls = 0;
  int writeCalls = 0;

  @override
  Future<bool> readEnabled() async {
    readCalls += 1;
    return enabled;
  }

  @override
  Future<void> setEnabled(bool value) async {
    writeCalls += 1;
    enabled = value;
  }
}

final class ScreenProtectionProtocolException implements Exception {
  const ScreenProtectionProtocolException(this.message);

  final String message;

  @override
  String toString() => 'ScreenProtectionProtocolException: $message';
}
