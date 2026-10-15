import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class ShareIntakePayload {
  ShareIntakePayload({
    required this.token,
    required this.text,
    required this.remainingLifetime,
    this.subject,
    this.title,
  }) {
    if (!_validToken.hasMatch(token) ||
        text.trim().isEmpty ||
        text != text.trim() ||
        text.length > maximumTextLength ||
        !_safeText(text) ||
        _forbiddenUri.hasMatch(text) ||
        remainingLifetime <= Duration.zero ||
        remainingLifetime > maximumLifetime ||
        !_validMetadata(subject) ||
        !_validMetadata(title)) {
      throw const FormatException('Invalid in-memory share payload.');
    }
  }

  static const int maximumTextLength = 20000;
  static const Duration maximumLifetime = Duration(minutes: 5);
  static final RegExp _validToken = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static final RegExp _forbiddenUri = RegExp(
    r'\b(?:content|file|intent|javascript|android-app):'
    r'|\bdata:(?:[a-z][a-z0-9.+-]*/|[a-z][a-z0-9.+-]*;|,)',
    caseSensitive: false,
  );

  final String token;
  final String text;
  final String? subject;
  final String? title;
  final Duration remainingLifetime;

  static bool _validMetadata(String? value) =>
      value == null ||
      (value.isNotEmpty &&
          value == value.trim() &&
          value.length <= 512 &&
          _safeText(value) &&
          !_forbiddenUri.hasMatch(value));

  static bool _safeText(String value) {
    for (final rune in value.runes) {
      final allowedWhitespace = rune == 0x09 || rune == 0x0a || rune == 0x0d;
      if ((rune <= 0x1f && !allowedWhitespace) ||
          (rune >= 0x7f && rune <= 0x9f) ||
          (rune >= 0x202a && rune <= 0x202e) ||
          (rune >= 0x2066 && rune <= 0x2069)) {
        return false;
      }
    }
    return true;
  }
}

final class ShareIntakeResult {
  const ShareIntakeResult.accepted(this.payload)
    : errorCode = null,
      nativeMessage = null;

  const ShareIntakeResult.rejected({
    required this.errorCode,
    this.nativeMessage,
  }) : payload = null;

  final ShareIntakePayload? payload;
  final String? errorCode;
  final String? nativeMessage;

  bool get accepted => payload != null;
}

abstract class ShareIntakeBridge implements Listenable {
  Future<ShareIntakeResult?> consumePending();

  Future<void> clearPending();

  void dispose();
}

final class MethodChannelShareIntakeBridge extends ChangeNotifier
    implements ShareIntakeBridge {
  MethodChannelShareIntakeBridge([
    this._channel = const MethodChannel('cardock/share_intake'),
  ]) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;
  bool _disposed = false;

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'pendingAvailable' && !_disposed) {
      notifyListeners();
    }
    return null;
  }

  @override
  Future<ShareIntakeResult?> consumePending() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'consumePending',
      );
      if (raw == null) return null;
      if (raw['status'] == 'rejected') {
        const allowedKeys = <String>{'status', 'errorCode', 'message'};
        final code = raw['errorCode'];
        final message = raw['message'];
        if (raw.keys.any((key) => !allowedKeys.contains(key)) ||
            code is! String ||
            !RegExp(r'^[A-Z][A-Z0-9_]{0,63}$').hasMatch(code) ||
            (message != null && message is! String)) {
          return const ShareIntakeResult.rejected(
            errorCode: 'INVALID_NATIVE_PAYLOAD',
          );
        }
        return ShareIntakeResult.rejected(
          errorCode: code,
          nativeMessage: message as String?,
        );
      }
      const allowedKeys = <String>{
        'status',
        'token',
        'text',
        'subject',
        'title',
        'remainingLifetimeMilliseconds',
      };
      if (raw.keys.any((key) => !allowedKeys.contains(key)) ||
          raw['status'] != 'accepted' ||
          raw['token'] is! String ||
          raw['text'] is! String ||
          raw['remainingLifetimeMilliseconds'] is! int ||
          (raw['subject'] != null && raw['subject'] is! String) ||
          (raw['title'] != null && raw['title'] is! String)) {
        return const ShareIntakeResult.rejected(
          errorCode: 'INVALID_NATIVE_PAYLOAD',
        );
      }
      try {
        return ShareIntakeResult.accepted(
          ShareIntakePayload(
            token: raw['token']! as String,
            text: raw['text']! as String,
            subject: raw['subject'] as String?,
            title: raw['title'] as String?,
            remainingLifetime: Duration(
              milliseconds: raw['remainingLifetimeMilliseconds']! as int,
            ),
          ),
        );
      } on FormatException {
        return const ShareIntakeResult.rejected(
          errorCode: 'INVALID_NATIVE_PAYLOAD',
        );
      }
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return const ShareIntakeResult.rejected(
        errorCode: 'PLATFORM_BRIDGE_FAILED',
      );
    }
  }

  @override
  Future<void> clearPending() async {
    try {
      await _channel.invokeMethod<void>('clearPending');
    } on MissingPluginException {
      // Non-Android tests and desktop hosts have no native share slot.
    } on PlatformException {
      // Fail closed: no Dart code retains a native payload after this call.
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
