import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/platform/notification_reliability.dart';
import 'package:account_subscription_manager/features/settings/presentation/notification_reliability_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_vault_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'iOS notification permissions use the native channel and preserve unknown Android fields',
    () async {
      const channel = MethodChannel(
        'cardock/notification_reliability/followup',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'inspect'
            ? {'manufacturer': 'Apple', 'applicationNotificationsEnabled': true}
            : true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final service = MethodChannelNotificationReliabilityService(
        channel: channel,
        isAndroid: () => false,
        isIOS: () => true,
      );
      final status = await service.inspect();
      expect(status.applicationNotificationsEnabled, isTrue);
      expect(status.androidApiLevel, isNull);
      expect(status.batteryOptimizationExempt, isNull);
      expect(
        await service.openSettings(
          NotificationSettingsTarget.applicationNotifications,
        ),
        isTrue,
      );
      expect(calls.last.arguments, {'target': 'applicationNotifications'});
    },
  );

  testWidgets(
    'iPhone notification page replaces Android controls and gives a manual path when opening fails',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.binding.setSurfaceSize(const Size(900, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final service = MemoryNotificationReliabilityService(
          openSettingsResult: false,
        );
        final state = AppState(
          vaultStore: FakeVaultStore(),
          notificationReliabilityService: service,
        );
        addTearDown(state.dispose);
        await state.initialize();
        expect(await state.createVault('Elm-8!Qa'), VaultActionResult.success);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: NotificationReliabilityPage(appState: state),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('打开通道设置'), findsNothing);
        expect(find.text('打开电池优化'), findsNothing);
        expect(find.text('允许精确提醒'), findsNothing);
        expect(
          find.byKey(const ValueKey('notification-ios-focus-guidance')),
          findsOneWidget,
        );
        await tester.tap(find.text('打开通知设置'));
        await tester.pumpAndSettle();
        expect(service.openedTargets, [
          NotificationSettingsTarget.applicationNotifications,
        ]);
        expect(
          find.textContaining('请打开 iPhone 设置 > 通知 > Cardock'),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
