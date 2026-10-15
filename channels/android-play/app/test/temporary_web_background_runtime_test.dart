import 'dart:io';

import 'package:account_subscription_manager/core/platform/temporary_web_runtime_keeper.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('临时网页运行保持桥只发送冻结的 start 与 stop 方法', () async {
    const channel = MethodChannel('cardock/temporary_web_runtime/test');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    const keeper = MethodChannelTemporaryWebRuntimeKeeper(channel);
    await keeper.start();
    await keeper.stop();

    expect(calls.map((call) => call.method), <String>['start', 'stop']);
    expect(calls.every((call) => call.arguments == null), isTrue);
  });

  test('非 Android 空实现可重复启停', () async {
    const keeper = NoopTemporaryWebRuntimeKeeper();
    await keeper.start();
    await keeper.start();
    await keeper.stop();
    await keeper.stop();
  });

  test('普通后台生命周期保留临时连接但仍执行保险库锁定', () async {
    final source = await File(
      'lib/app/account_subscription_app.dart',
    ).readAsString();
    final lifecycle = source.substring(
      source.indexOf('void didChangeAppLifecycleState'),
      source.indexOf('void _lockManually'),
    );

    expect(
      lifecycle,
      isNot(contains('TemporaryWebStopReason.appBackgrounded')),
    );
    expect(lifecycle, contains('_lockAndResetNavigation('));
    expect(lifecycle, contains('stopTemporaryWebSession: false'));
    expect(lifecycle, contains('preserveNavigation: true'));
    expect(lifecycle, contains('state == AppLifecycleState.detached'));
    expect(source, contains('_appState.lock();'));
    expect(
      source,
      contains('_temporaryWebController.handleVaultAccessStateChanged();'),
    );
    expect(source, contains('_showTemporaryWebApprovalDialog'));
    expect(source, contains('useRootNavigator: true'));
    expect(source, contains('barrierDismissible: false'));
    expect(source, contains("'temporary-web-approval-dialog-approve'"));
  });

  test('Flutter Activity 销毁时原生兜底停止临时网页前台服务', () async {
    final source = await File(
      'android/app/src/main/kotlin/com/localaccount/account_subscription_manager/MainActivity.kt',
    ).readAsString();
    final onDestroy = source.substring(
      source.indexOf('override fun onDestroy()'),
      source.indexOf('private class QuickUnlockKeyMissingException'),
    );

    expect(
      onDestroy,
      contains('TemporaryWebForegroundService.stop(applicationContext)'),
    );
  });
}
