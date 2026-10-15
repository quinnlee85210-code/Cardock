import 'package:account_subscription_manager/core/temporary_web/temporary_web_controller.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_models.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_vault_gateway.dart';
import 'package:account_subscription_manager/core/platform/sensitive_clipboard.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/settings/presentation/temporary_web_session_page.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const backgroundConnectionNotice =
      '普通锁屏、返回 Home、切换应用或接听来电时，电脑连接会继续保留；Android 会显示一条不含账号、密码或订阅内容的低敏前台服务通知。\n\n'
      '保险库锁定后，电脑仍可继续填写尚未提交的内容；保存或导入会暂停，需回到Cardock并解锁手机后继续。\n\n'
      '只要应用进程仍在，正常使用中仅手机主动断开或所选连接时间到达会结束；划掉Cardock、强制停止、应用进程死亡或手机关机会使服务自然不可用。';

  testWidgets('默认权限最小，用户可分别选历史范围与两个独立开关', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final transport = _PageTransport();
    final clipboard = _PageClipboard();
    final controller = TemporaryWebSessionController(
      const _PageGateway(),
      transport,
      const _PageAddressProvider(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: TemporaryWebSessionPage(
          controller: controller,
          sensitiveClipboard: clipboard,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('仅本次'), findsOneWidget);
    expect(find.text('历史摘要'), findsOneWidget);
    expect(find.text('历史详情'), findsOneWidget);
    expect(find.textContaining('不会访问公网、云或中继'), findsOneWidget);
    expect(find.textContaining('浏览器无痕/隐私窗口'), findsOneWidget);
    expect(find.textContaining('不能保证电脑绝对不留痕'), findsOneWidget);
    expect(find.textContaining('锁屏、返回 Home、切换应用或接听来电'), findsOneWidget);
    expect(find.textContaining('保存或导入会暂停'), findsOneWidget);
    expect(find.textContaining('低敏前台服务通知'), findsOneWidget);
    expect(find.textContaining('划掉Cardock'), findsOneWidget);

    var historyEditing = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey<String>('temporary-web-history-edit')),
    );
    var passwordReveal = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey<String>('temporary-web-password-reveal')),
    );
    expect(historyEditing.value, isFalse);
    expect(historyEditing.onChanged, isNull);
    expect(passwordReveal.value, isFalse);
    expect(passwordReveal.onChanged, isNull);

    await tester.scrollUntilVisible(
      find.text('历史摘要'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('历史摘要'));
    await tester.pump();
    await tester.tap(find.text('历史摘要'));
    await tester.pump();
    historyEditing = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey<String>('temporary-web-history-edit')),
    );
    passwordReveal = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey<String>('temporary-web-password-reveal')),
    );
    expect(historyEditing.onChanged, isNull);
    expect(passwordReveal.onChanged, isNotNull);

    await tester.scrollUntilVisible(
      find.text('历史详情'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('历史详情'));
    await tester.pump();
    await tester.tap(find.text('历史详情'));
    await tester.pump();
    historyEditing = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey<String>('temporary-web-history-edit')),
    );
    expect(historyEditing.onChanged, isNotNull);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('temporary-web-connection-duration')),
      240,
    );
    expect(find.textContaining('默认 5 分钟'), findsOneWidget);
    expect(find.textContaining('从开启服务时开始计时'), findsOneWidget);
    final timeoutField = find.byKey(
      const ValueKey<String>('temporary-web-connection-duration'),
    );
    expect(
      tester.state<FormFieldState<Duration>>(timeoutField).value,
      const Duration(minutes: 5),
    );
    await tester.tap(timeoutField);
    await tester.pumpAndSettle();
    expect(find.text('30 分钟'), findsOneWidget);
    await tester.tap(find.text('30 分钟').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('temporary-web-start')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('temporary-web-start')));
    await tester.pumpAndSettle();

    expect(find.text('192.168.43.1:43123'), findsOneWidget);
    expect(find.textContaining('无需输入 http://'), findsOneWidget);
    expect(find.text('ABCDEFGH'), findsOneWidget);
    expect(find.textContaining('不使用二维码'), findsOneWidget);
    expect(find.textContaining('浏览器无痕/隐私窗口'), findsOneWidget);
    expect(find.textContaining('锁屏、返回 Home、切换应用或接听来电'), findsOneWidget);
    expect(
      controller.snapshot.policy.connectionDuration,
      const Duration(minutes: 30),
    );
    expect(
      controller.snapshot.policy.historyMode,
      TemporaryWebHistoryMode.details,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('temporary-web-copy-code')),
    );
    await tester.pump();
    expect(clipboard.text, 'ABCDEFGH');
    expect(clipboard.label, '一次性连接码');
    expect(clipboard.clearAfter, const Duration(seconds: 60));
    expect(find.textContaining('60 秒后尽力清理剪贴板'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.pump();
  });

  test('后台连接边界提供英语和日语翻译', () {
    final english = const AppLocalizations(
      Locale('en'),
    ).translate(backgroundConnectionNotice);
    final japanese = const AppLocalizations(
      Locale('ja'),
    ).translate(backgroundConnectionNotice);

    expect(english, contains('taking a call keeps the PC connection alive'));
    expect(english, contains('saving or importing pauses'));
    expect(english, contains('normal use ends the connection only'));
    expect(japanese, contains('着信への応答では、PCとの接続は維持されます'));
    expect(japanese, contains('保存またはインポートは一時停止'));
    expect(japanese, contains('通常の使用で接続が終了するのは'));
  });
}

final class _PageClipboard implements SensitiveClipboard {
  String? text;
  String? label;
  Duration? clearAfter;

  @override
  Future<void> copySensitive({
    required String text,
    required String label,
    Duration clearAfter = const Duration(seconds: 60),
  }) async {
    this.text = text;
    this.label = label;
    this.clearAfter = clearAfter;
  }
}

final class _PageTransport implements TemporaryWebTransport {
  @override
  void revoke() {}

  @override
  Future<TemporaryWebTransportBinding> start({
    required String address,
    required TemporaryWebCommandHandler onCommand,
    required void Function(String remoteAddress) onPaired,
    required void Function(Object error) onFatalError,
  }) async => const TemporaryWebTransportBinding(
    port: 43123,
    formattedConnectionCode: 'ABCDEFGH',
  );

  @override
  Future<void> stop() async {}
}

final class _PageAddressProvider implements TemporaryWebAddressProvider {
  const _PageAddressProvider();

  @override
  Future<bool> isStillAvailable(String address) async =>
      address == '192.168.43.1';

  @override
  Future<List<TemporaryWebAddress>> listPrivateIpv4Addresses() async =>
      const <TemporaryWebAddress>[
        TemporaryWebAddress(address: '192.168.43.1', interfaceName: 'wlan0'),
      ];
}

final class _PageGateway implements TemporaryWebVaultGateway {
  const _PageGateway();

  @override
  bool get isEligibleForTemporaryWebSession => true;

  @override
  String? get vaultBindingId => 'fake-vault';

  @override
  int get revision => 1;

  @override
  TemporaryWebVaultRecords readRecords() => const TemporaryWebVaultRecords(
    revision: 1,
    accounts: <AccountRecord>[],
    subscriptions: <SubscriptionRecord>[],
  );

  @override
  Future<TemporaryWebMutationResult> addAccount(AccountDraft draft) =>
      throw UnimplementedError();

  @override
  Future<TemporaryWebMutationResult> addSubscription(SubscriptionDraft draft) =>
      throw UnimplementedError();

  @override
  Future<TemporaryWebMutationResult> deleteAccount(String accountId) =>
      throw UnimplementedError();

  @override
  Future<TemporaryWebMutationResult> deleteSubscription(
    String subscriptionId,
  ) => throw UnimplementedError();

  @override
  Future<TemporaryWebMutationResult> updateAccount({
    required String accountId,
    required AccountDraft draft,
    required AccountPasswordUpdateMode passwordMode,
  }) => throw UnimplementedError();

  @override
  Future<TemporaryWebMutationResult> updateSubscription({
    required String subscriptionId,
    required SubscriptionDraft draft,
  }) => throw UnimplementedError();
}
