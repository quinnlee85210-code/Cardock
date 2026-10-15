import 'package:flutter/services.dart';

import '../preferences/language_preferences.dart';

/// Keeps Android-owned prompts and MethodChannel messages aligned with the
/// language selected inside Cardock, independent of the system locale.
final class CardockPlatformLanguageBridge {
  const CardockPlatformLanguageBridge();

  static const MethodChannel _channel = MethodChannel(
    'cardock/platform_language',
  );

  Future<void> updateLanguage(CardockLanguage language) =>
      _channel.invokeMethod<void>('setLanguage', <String, Object?>{
        'language': language.storageCode,
      });
}
