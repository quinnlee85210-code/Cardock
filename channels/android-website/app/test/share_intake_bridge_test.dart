import 'package:account_subscription_manager/core/platform/share_intake_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cardock/share_intake_test');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('平台桥接受通过二次校验的内存负载', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'consumePending');
          return <String, Object?>{
            'status': 'accepted',
            'token': '123e4567-e89b-42d3-a456-426614174000',
            'text': 'plan: Pro',
            'subject': 'Example',
            'title': null,
            'remainingLifetimeMilliseconds': 299999,
          };
        });
    final bridge = MethodChannelShareIntakeBridge(channel);
    addTearDown(bridge.dispose);

    final result = await bridge.consumePending();
    expect(result?.accepted, isTrue);
    expect(result?.payload?.text, 'plan: Pro');
    expect(
      result?.payload?.remainingLifetime,
      const Duration(milliseconds: 299999),
    );
  });

  test('畸形 token、超长 TTL、控制字符和错误字段类型均失败关闭', () async {
    final responses = <Map<String, Object?>>[
      <String, Object?>{
        'status': 'accepted',
        'token': 'not-a-token',
        'text': 'plain',
        'remainingLifetimeMilliseconds': 1000,
      },
      <String, Object?>{
        'status': 'accepted',
        'token': '123e4567-e89b-42d3-a456-426614174000',
        'text': 'plain',
        'remainingLifetimeMilliseconds': 300001,
      },
      <String, Object?>{
        'status': 'accepted',
        'token': '123e4567-e89b-42d3-a456-426614174000',
        'text': 'unsafe\u0000text',
        'remainingLifetimeMilliseconds': 1000,
      },
      <String, Object?>{
        'status': 'accepted',
        'token': '123e4567-e89b-42d3-a456-426614174000',
        'text': 42,
        'remainingLifetimeMilliseconds': 1000,
      },
      <String, Object?>{
        'status': 'accepted',
        'token': '123e4567-e89b-42d3-a456-426614174000',
        'text': 'data:text/html,<script>alert(1)</script>',
        'remainingLifetimeMilliseconds': 1000,
      },
      <String, Object?>{
        'status': 'accepted',
        'token': '123e4567-e89b-42d3-a456-426614174000',
        'text': 'plain',
        'remainingLifetimeMilliseconds': 1000,
        'sourceApp': 'must-not-cross-bridge',
      },
    ];
    var index = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => responses[index++]);
    final bridge = MethodChannelShareIntakeBridge(channel);
    addTearDown(bridge.dispose);

    for (var count = 0; count < responses.length; count += 1) {
      final result = await bridge.consumePending();
      expect(result?.accepted, isFalse);
      expect(result?.errorCode, 'INVALID_NATIVE_PAYLOAD');
    }
  });

  test('原生拒绝结果只传递错误码且 clearPending 可调用', () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          if (call.method == 'consumePending') {
            return <String, Object?>{
              'status': 'rejected',
              'errorCode': 'UNSUPPORTED_URI',
              'message': 'unsupported',
            };
          }
          return null;
        });
    final bridge = MethodChannelShareIntakeBridge(channel);
    addTearDown(bridge.dispose);

    final result = await bridge.consumePending();
    expect(result?.accepted, isFalse);
    expect(result?.errorCode, 'UNSUPPORTED_URI');
    await bridge.clearPending();
    expect(methods, <String>['consumePending', 'clearPending']);
  });
}
