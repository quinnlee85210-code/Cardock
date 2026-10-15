import 'package:flutter/services.dart';

abstract interface class SensitiveClipboard {
  Future<void> copySensitive({
    required String text,
    required String label,
    Duration clearAfter = const Duration(seconds: 60),
  });
}

final class PlatformSensitiveClipboard implements SensitiveClipboard {
  const PlatformSensitiveClipboard({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'account_subscription_manager/sensitive_clipboard';

  final MethodChannel _channel;

  @override
  Future<void> copySensitive({
    required String text,
    required String label,
    Duration clearAfter = const Duration(seconds: 60),
  }) async {
    if (text.isEmpty) {
      throw ArgumentError('不能复制空内容');
    }
    final clearAfterSeconds = clearAfter.inSeconds.clamp(0, 300);
    await _channel.invokeMethod<void>('copySensitive', <String, Object>{
      'text': text,
      'label': label,
      'clearAfterSeconds': clearAfterSeconds,
    });
  }
}
