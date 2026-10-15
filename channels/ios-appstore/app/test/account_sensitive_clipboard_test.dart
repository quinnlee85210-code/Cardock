import 'package:account_subscription_manager/core/platform/sensitive_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('敏感剪贴板只通过专用原生通道并携带限时清除参数', () async {
    const channel = MethodChannel(PlatformSensitiveClipboard.channelName);
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await const PlatformSensitiveClipboard().copySensitive(
      text: '测试密码🙂',
      label: '登录密码',
      clearAfter: const Duration(seconds: 45),
    );

    expect(captured?.method, 'copySensitive');
    expect(captured?.arguments, <String, Object>{
      'text': '测试密码🙂',
      'label': '登录密码',
      'clearAfterSeconds': 45,
    });
  });

  test('空内容拒绝复制且清除时间限制在五分钟内', () async {
    const channel = MethodChannel(PlatformSensitiveClipboard.channelName);
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(
      () => const PlatformSensitiveClipboard().copySensitive(
        text: '',
        label: '空内容',
      ),
      throwsArgumentError,
    );
    await const PlatformSensitiveClipboard().copySensitive(
      text: '内容',
      label: '字段',
      clearAfter: const Duration(hours: 1),
    );
    expect(
      (captured?.arguments as Map<Object?, Object?>)['clearAfterSeconds'],
      300,
    );
  });
}
