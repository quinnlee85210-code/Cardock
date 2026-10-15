import 'package:account_subscription_manager/core/platform/desktop_icon_controller.dart';
import 'package:account_subscription_manager/core/theme/cardock_theme_types.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('非Android平台不读取也不切换launcher alias', () async {
    const channel = MethodChannel('cardock/launcher_icon/non-android-test');
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls += 1;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final bridge = MethodChannelDesktopIconBridge(
      channel: channel,
      isAndroid: () => false,
    );

    expect(await bridge.getActiveIcon(), isNull);
    await bridge.setIcon(CardockLauncherFamily.mistCoral);

    expect(calls, 0);
  });

  test('Android桥使用冻结通道方法与variant参数并解析当前alias', () async {
    const channel = MethodChannel('cardock/launcher_icon/android-test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method ==
              MethodChannelDesktopIconBridge.getLauncherIconMethod) {
            return 'paperArchive';
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final bridge = MethodChannelDesktopIconBridge(
      channel: channel,
      isAndroid: () => true,
    );

    expect(await bridge.getActiveIcon(), CardockLauncherFamily.paperArchive);
    await bridge.setIcon(CardockLauncherFamily.mistCoral);

    expect(calls, hasLength(2));
    expect(
      calls.first.method,
      MethodChannelDesktopIconBridge.getLauncherIconMethod,
    );
    expect(
      calls.last.method,
      MethodChannelDesktopIconBridge.setLauncherIconMethod,
    );
    expect(calls.last.arguments, <String, Object?>{'variant': 'mistCoral'});
  });

  test('iOS桥使用相同通道方法与variant参数并解析当前alias', () async {
    const channel = MethodChannel('cardock/launcher_icon/ios-test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method ==
              MethodChannelDesktopIconBridge.getLauncherIconMethod) {
            return 'paperArchive';
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final bridge = MethodChannelDesktopIconBridge(
      channel: channel,
      isAndroid: () => false,
      isIOS: () => true,
    );

    expect(await bridge.getActiveIcon(), CardockLauncherFamily.paperArchive);
    await bridge.setIcon(CardockLauncherFamily.mistCoral);

    expect(calls, hasLength(2));
    expect(
      calls.first.method,
      MethodChannelDesktopIconBridge.getLauncherIconMethod,
    );
    expect(
      calls.last.method,
      MethodChannelDesktopIconBridge.setLauncherIconMethod,
    );
    expect(calls.last.arguments, <String, Object?>{'variant': 'mistCoral'});
  });

  test('Android桥将旧三别名标记为必须迁移而非伪装成新主题', () async {
    const channel = MethodChannel('cardock/launcher_icon/legacy-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 'prime');
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final bridge = MethodChannelDesktopIconBridge(
      channel: channel,
      isAndroid: () => true,
    );

    await expectLater(
      bridge.getActiveIcon(),
      throwsA(isA<DesktopIconMigrationRequiredException>()),
    );
  });
  test('Android桥安全拒绝未知或缺失的活动alias值', () async {
    const unknownChannel = MethodChannel(
      'cardock/launcher_icon/unknown-variant-test',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(unknownChannel, (call) async => 'future');
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(unknownChannel, null);
    });
    final unknownBridge = MethodChannelDesktopIconBridge(
      channel: unknownChannel,
      isAndroid: () => true,
    );

    await expectLater(
      unknownBridge.getActiveIcon(),
      throwsA(isA<DesktopIconProtocolException>()),
    );

    const missingChannel = MethodChannel(
      'cardock/launcher_icon/missing-variant-test',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(missingChannel, (call) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(missingChannel, null);
    });
    final missingBridge = MethodChannelDesktopIconBridge(
      channel: missingChannel,
      isAndroid: () => true,
    );

    await expectLater(
      missingBridge.getActiveIcon(),
      throwsA(isA<DesktopIconProtocolException>()),
    );
  });

  test('Android桥拒绝custom且协议类型只包含八套固定launcher', () async {
    expect(CardockLauncherFamily.values, <CardockLauncherFamily>[
      CardockLauncherFamily.ceramicBlue,
      CardockLauncherFamily.sakuraMist,
      CardockLauncherFamily.paperArchive,
      CardockLauncherFamily.lilacMoon,
      CardockLauncherFamily.glacierBlue,
      CardockLauncherFamily.mistCoral,
      CardockLauncherFamily.neonZero,
      CardockLauncherFamily.obsidianGold,
    ]);
    expect(cardockLauncherFamilyFromName('custom'), isNull);

    const channel = MethodChannel('cardock/launcher_icon/custom-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 'custom');
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final bridge = MethodChannelDesktopIconBridge(
      channel: channel,
      isAndroid: () => true,
    );
    await expectLater(
      bridge.getActiveIcon(),
      throwsA(isA<DesktopIconProtocolException>()),
    );
  });
}
