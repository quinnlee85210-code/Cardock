import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/notifications/reminder_scheduler.dart';
import 'support/stage4_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final cold in [false, true]) {
    test(
      'opaque notification ${cold ? 'cold launch' : 'running callback'} waits for authentication and uses current empty vault',
      () async {
        final h = await Stage4Harness.create();
        addTearDown(h.dispose);
        h.state.lock();
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const channel = MethodChannel(
          'dexterous.com/flutter/local_notifications',
        );
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getNotificationAppLaunchDetails') {
            return {
              'notificationLaunchedApp': cold,
              'notificationResponse': {
                'id': 7,
                'payload': reminderNavigationPayload,
                'notificationResponseType': 0,
              },
            };
          }
          if (call.method == 'pendingNotificationRequests') return <Object>[];
          return true;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final scheduler = LocalReminderScheduler(
          timeZoneIdentifier: () async => 'UTC',
          now: () => DateTime(2026, 9, 4),
        );
        final state = AppState(
          vaultStore: h.store,
          reminderScheduler: scheduler,
          now: () => DateTime(2026, 9, 4),
        );
        addTearDown(state.dispose);
        await state.initialize();
        Future<void> response(String payload) async {
          final done = Completer<void>();
          ServicesBinding.instance.channelBuffers.push(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('didReceiveNotificationResponse', {
                'id': 7,
                'payload': payload,
                'notificationResponseType': 0,
              }),
            ),
            (_) => done.complete(),
          );
          await done.future;
        }

        if (!cold) {
          await response('foreign-opaque-payload');
          expect(state.consumeReminderOpenRequest(), false);
          await response(reminderNavigationPayload);
        }
        expect(state.isUnlocked, false);
        expect(state.consumeReminderOpenRequest(), false);
        expect(state.subscriptions, isEmpty);
        expect(await state.unlock(stage4Master), VaultActionResult.success);
        expect(state.consumeReminderOpenRequest(), true);
        expect(state.consumeReminderOpenRequest(), false);
        // No record ID is accepted or looked up: even a deleted/empty vault has a valid safe destination.
        expect(state.subscriptions, isEmpty);
        expect(state.accounts, isEmpty);
      },
    );
  }
}
