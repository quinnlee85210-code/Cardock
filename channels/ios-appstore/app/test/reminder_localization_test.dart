import 'dart:io';

import 'package:account_subscription_manager/core/notifications/reminder_scheduler.dart';
import 'package:account_subscription_manager/core/preferences/language_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  test(
    'notification copy is complete, private, and distinct in all languages',
    () {
      final copies = <ReminderNotificationCopy>[
        for (final language in CardockLanguage.values)
          reminderNotificationCopyFor(language),
      ];

      for (final copy in copies) {
        expect(copy.channelName, isNotEmpty);
        expect(copy.channelDescription, isNotEmpty);
        expect(copy.privacyTitle, isNotEmpty);
        expect(copy.privacyBody, isNotEmpty);
        expect(copy.testTitle, isNotEmpty);
        expect(copy.immediateTestBody, isNotEmpty);
        expect(copy.scheduledTestBody, isNotEmpty);
        final combined = <String>[
          copy.privacyTitle,
          copy.privacyBody,
          copy.immediateTestBody,
          copy.scheduledTestBody,
        ].join(' ');
        expect(combined, isNot(contains('Netflix')));
        expect(combined, isNot(contains('user@example.com')));
        expect(combined, isNot(contains('19.99')));
      }
      expect(copies.map((copy) => copy.privacyBody).toSet(), hasLength(3));
    },
  );

  test('通知 channel 名称与说明按三种应用语言稳定且保持隐私', () {
    final copies = <CardockLanguage, ReminderNotificationCopy>{
      for (final language in CardockLanguage.values)
        language: reminderNotificationCopyFor(language),
    };

    expect(copies[CardockLanguage.simplifiedChinese]!.channelName, '本机订阅提醒');
    expect(
      copies[CardockLanguage.english]!.channelName,
      'On-device subscription reminders',
    );
    expect(copies[CardockLanguage.japanese]!.channelName, '端末内のサブスクリプション通知');
    expect(
      copies[CardockLanguage.english]!.channelDescription,
      'Reminders for upcoming renewals or expirations',
    );
    expect(
      copies[CardockLanguage.japanese]!.channelDescription,
      '更新日または有効期限が近い記録を端末内で通知します',
    );

    for (final copy in copies.values) {
      final channelCopy = '${copy.channelName} ${copy.channelDescription}';
      expect(channelCopy, isNot(contains('Netflix')));
      expect(channelCopy, isNot(contains('user@example.com')));
      expect(channelCopy, isNot(contains('19.99')));
    }
    expect(
      copies.values.map((copy) => copy.channelName).toSet(),
      hasLength(CardockLanguage.values.length),
    );
  });

  test('Android channel 创建与通知详情均读取当前语言 copy', () {
    final source = File(
      'lib/core/notifications/reminder_scheduler.dart',
    ).readAsStringSync();

    expect(source, contains('AndroidNotificationChannel('));
    expect(
      RegExp(r'_copy\.channelName').allMatches(source).length,
      greaterThanOrEqualTo(3),
    );
    expect(
      RegExp(r'_copy\.channelDescription').allMatches(source).length,
      greaterThanOrEqualTo(3),
    );
    expect(source, contains('void updateLanguage(CardockLanguage language)'));
  });

  test(
    'scheduler defaults to Chinese and can update later notification copy',
    () async {
      final gateway = _RecordingGateway();
      final scheduler = LocalReminderScheduler(
        gateway: gateway,
        timeZoneIdentifier: () async => 'Asia/Shanghai',
      );

      await scheduler.showTestNotification();
      expect(gateway.lastTitle, '通知测试');

      scheduler.updateLanguage(CardockLanguage.english);
      await scheduler.showTestNotification();
      expect(gateway.lastTitle, 'Notification test');
      expect(gateway.lastBody, contains('no account or subscription details'));

      scheduler.updateLanguage(CardockLanguage.japanese);
      await scheduler.scheduleTestReminder(delay: const Duration(minutes: 1));
      expect(gateway.lastTitle, '通知テスト');
      expect(gateway.lastBody, contains('アカウント'));
    },
  );
}

final class _RecordingGateway implements ReminderNotificationGateway {
  String? lastTitle;
  String? lastBody;

  @override
  Future<bool> requestApplicationPermission() async => true;

  @override
  Future<bool> ensureReminderChannelEnabled() async => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> canScheduleExactNotifications() async => false;

  @override
  Future<List<PendingReminderNotification>>
  pendingNotificationRequests() async => const <PendingReminderNotification>[];

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required bool useExactAlarm,
    String? payload,
  }) async {
    lastTitle = title;
    lastBody = body;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    lastTitle = title;
    lastBody = body;
  }

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}
}
