import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const iosCoreChannel = MethodChannel('cardock/ios_core_v1');

Future<void> prepareIOSPrivateStorage() async {
  if (!Platform.isIOS) return;
  final ready = await iosCoreChannel
      .invokeMethod<bool>('prepareStorage')
      .timeout(const Duration(seconds: 15));
  if (ready != true) throw const FormatException('Private storage unavailable');
}

/// Remove the native cover only after Flutter has rendered its safe foreground UI.
void acknowledgeIOSForegroundFrame() {
  if (!Platform.isIOS) return;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await iosCoreChannel.invokeMethod<void>('frameReady');
    } on Object {
      // Leave the native cover in place when the hand-off fails.
    }
  });
  WidgetsBinding.instance.ensureVisualUpdate();
}

class IOSStorageUnavailableApp extends StatelessWidget {
  const IOSStorageUnavailableApp({super.key, required this.retry});
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) {
    final language =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final (message, action) = switch (language) {
      'zh' => ('暂时无法访问安全存储。请解锁设备后重试，已有数据会保留。', '重试'),
      'ja' => (
        '安全なストレージにアクセスできません。端末のロックを解除して再試行してください。保存済みデータは保持されます。',
        '再試行',
      ),
      _ => (
        'Secure storage is unavailable. Unlock this device and retry. Existing data is preserved.',
        'Retry',
      ),
    };
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: retry, child: Text(action)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
