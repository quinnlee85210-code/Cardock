import 'dart:io';

import 'package:flutter/services.dart';

/// Controls the Android window-level screenshot and recording protection.
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
  }) : _channel = channel ?? const MethodChannel(channelName),
       _isAndroid = isAndroid ?? _platformIsAndroid;

  static const String channelName = 'cardock/screen_protection';
  static const String getSecureFlagMethod = 'getSecureFlag';
  static const String setSecureFlagMethod = 'setSecureFlag';

  final MethodChannel _channel;
  final bool Function() _isAndroid;

  static bool _platformIsAndroid() => Platform.isAndroid;

  @override
  Future<bool> readEnabled() async {
    if (!_isAndroid()) return true;
    final value = await _channel.invokeMethod<bool>(getSecureFlagMethod);
    if (value == null) {
      throw const ScreenProtectionProtocolException(
        'Android screen protection channel returned no preference value.',
      );
    }
    return value;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    if (!_isAndroid()) return;
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
