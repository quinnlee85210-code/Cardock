import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/platform/screen_protection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('内存偏好默认开启并持久保存切换值', () async {
    final service = MemoryScreenProtectionService();

    expect(await service.readEnabled(), isTrue);
    await service.setEnabled(false);
    expect(await service.readEnabled(), isFalse);
    expect(service.writeCalls, 1);
  });

  test('Android MethodChannel 使用冻结方法与布尔参数', () async {
    const channel = MethodChannel('cardock/screen_protection/test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method ==
              MethodChannelScreenProtectionService.getSecureFlagMethod) {
            return false;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final service = MethodChannelScreenProtectionService(
      channel: channel,
      isAndroid: () => true,
    );

    expect(await service.readEnabled(), isFalse);
    await service.setEnabled(true);

    expect(calls, hasLength(2));
    expect(
      calls.first.method,
      MethodChannelScreenProtectionService.getSecureFlagMethod,
    );
    expect(
      calls.last.method,
      MethodChannelScreenProtectionService.setSecureFlagMethod,
    );
    expect(calls.last.arguments, <String, Object?>{'enabled': true});
  });

  test('iOS persists switcher privacy through the native channel', () async {
    const channel = MethodChannel('cardock/screen_protection/ios-test');
    var persisted = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getSecureFlag') return persisted;
          persisted = (call.arguments as Map)['enabled'] as bool;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final service = MethodChannelScreenProtectionService(
      channel: channel,
      isAndroid: () => false,
      isIOS: () => true,
    );
    expect(await service.readEnabled(), true);
    await service.setEnabled(false);
    expect(await service.readEnabled(), false);
    await service.setEnabled(true);
    expect(await service.readEnabled(), true);
  });

  test('AppState 从注入服务读取并立即持久化防截屏设置', () async {
    final service = MemoryScreenProtectionService(enabled: false);
    final state = AppState(
      vaultStore: FakeVaultStore(),
      screenProtectionService: service,
    );
    addTearDown(state.dispose);

    await state.initialize();
    expect(state.screenProtectionEnabled, isFalse);
    expect(service.readCalls, 1);

    expect(await state.setScreenProtectionEnabled(true), isTrue);
    expect(state.screenProtectionEnabled, isTrue);
    expect(service.enabled, isTrue);
    expect(service.writeCalls, 1);
  });
}
