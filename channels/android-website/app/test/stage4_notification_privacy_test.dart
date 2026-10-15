import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:account_subscription_manager/core/preferences/notification_privacy_preferences.dart';
import 'package:account_subscription_manager/core/preferences/language_preferences.dart';
import 'package:account_subscription_manager/core/notifications/subscription_notification_content.dart';
import 'package:account_subscription_manager/core/notifications/reminder_scheduler.dart';
import 'package:account_subscription_manager/core/storage/vault_rebuild_service.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'stage2_subscription_management_test.dart' as fixture;

class Stage4Gateway implements ReminderNotificationGateway {
  final pending = <int, PendingReminderNotification>{};
  final times = <int, tz.TZDateTime>{};
  final calls = <int>[];
  final canceled = <int>[];
  bool rejectExact = false, failCancel = false, failSchedule = false;
  int cancelAllCalls = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> requestApplicationPermission() async => true;
  @override
  Future<bool> ensureReminderChannelEnabled() async => true;
  @override
  Future<bool> canScheduleExactNotifications() async => true;
  @override
  Future<List<PendingReminderNotification>>
  pendingNotificationRequests() async => pending.values.toList();
  @override
  Future<void> cancel(int id) async {
    if (failCancel) throw StateError('fixture cancel');
    canceled.add(id);
    pending.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    pending.clear();
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {}
  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required bool useExactAlarm,
    String? payload,
  }) async {
    calls.add(id);
    if (rejectExact && useExactAlarm) {
      throw PlatformException(code: 'exact_alarms_not_permitted');
    }
    if (failSchedule) throw StateError('fixture schedule');
    pending[id] = PendingReminderNotification(
      id: id,
      title: title,
      body: body,
      payload: payload,
    );
    times[id] = scheduledDate;
  }
}

LocalReminderScheduler scheduler(Stage4Gateway g, {String zone = 'UTC'}) =>
    LocalReminderScheduler(
      gateway: g,
      now: () => DateTime(2026, 9, 1),
      timeZoneIdentifier: () async => zone,
      targetPlatform: TargetPlatform.android,
    );
void main() {
  for (final language in CardockLanguage.values) {
    for (final level in NotificationPrivacy.values) {
      for (final event in SubscriptionReminderEvent.values) {
        test(
          'notification allowlist ${language.name}/${level.name}/${event.name}',
          () {
            final s = fixture.sub();
            final text = subscriptionNotificationContent(
              summary: SubscriptionPublicSummary.fromSubscription(s, event),
              privacy: level,
              language: language,
            );
            final all = '${text.title}|${text.body}';
            for (final excluded in [
              s.planName,
              s.paymentMethod,
              s.notes,
              s.id,
            ]) {
              if (excluded != null) expect(all, isNot(contains(excluded)));
            }
            expect(
              all.contains(s.serviceName),
              level != NotificationPrivacy.privacy,
            );
            if (level != NotificationPrivacy.fullSummary) {
              expect(all, isNot(contains('120')));
              expect(all, isNot(contains('2026-09-10')));
            }
          },
        );
      }
    }
  }
  for (final bad in [
    '',
    'user@example.invalid',
    'https://private.invalid',
    '+86 13812345678',
    'name\npassword',
    'name\u202e',
  ]) {
    test('unreliable service falls back ${bad.length}', () {
      final text = subscriptionNotificationContent(
        summary: SubscriptionPublicSummary(
          event: SubscriptionReminderEvent.renewal,
          serviceName: bad,
          amount: '99',
          currency: 'USD',
        ),
        privacy: NotificationPrivacy.fullSummary,
        language: CardockLanguage.english,
      );
      expect(text.body, isNot(contains('99')));
      expect(text.body, isNot(contains('USD')));
    });
  }
  test('unknown amount and date are omitted', () {
    final text = subscriptionNotificationContent(
      summary: const SubscriptionPublicSummary(
        event: SubscriptionReminderEvent.renewal,
        serviceName: 'Cloud',
      ),
      privacy: NotificationPrivacy.fullSummary,
      language: CardockLanguage.english,
    );
    expect(text.body, 'Cloud · Renewal approaching');
  });
  for (final value in [
    null,
    {},
    {'version': 2, 'level': 'fullSummary'},
    {'version': 1, 'level': 'invalid'},
    {'version': 1, 'level': 'fullSummary', 'unexpected': true},
  ]) {
    test(
      'preference safe fallback $value',
      () => expect(
        FileNotificationPrivacyStore.decode(value),
        NotificationPrivacy.privacy,
      ),
    );
  }
  test(
    'atomic preference reload ignores interrupted staging and corrupt/future file',
    () async {
      final dir = await Directory.systemTemp.createTemp('stage4-pref-');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileNotificationPrivacyStore(() async => dir);
      expect(await store.read(), NotificationPrivacy.privacy);
      await store.write(NotificationPrivacy.fullSummary);
      expect(await store.read(), NotificationPrivacy.fullSummary);
      final file = File('${dir.path}/${FileNotificationPrivacyStore.fileName}');
      await File('${file.path}.tmp').writeAsString('{');
      expect(await store.read(), NotificationPrivacy.fullSummary);
      await file.writeAsString(
        jsonEncode({'version': 99, 'level': 'fullSummary'}),
      );
      expect(await store.read(), NotificationPrivacy.privacy);
      await file.writeAsString('{');
      expect(await store.read(), NotificationPrivacy.privacy);
      await store.write(NotificationPrivacy.privacy);
      expect(await store.read(), NotificationPrivacy.privacy);
      expect(
        VaultRebuildService.removableName(
          FileNotificationPrivacyStore.fileName,
        ),
        true,
      );
      expect(
        VaultRebuildService.removableName(
          '${FileNotificationPrivacyStore.fileName}.tmp',
        ),
        true,
      );
      expect(
        VaultRebuildService.removableName('Cardock-calendar-20260904.ics'),
        false,
      );
    },
  );
  test(
    'same instant same event groups, remains stable and generic after full disclosure',
    () async {
      final g = Stage4Gateway();
      final actual = scheduler(g)
        ..updatePrivacy(NotificationPrivacy.fullSummary);
      await actual.rescheduleAll([fixture.sub(id: 'a'), fixture.sub(id: 'b')]);
      expect(g.pending.length, 1);
      expect(g.pending.values.single.body, contains('2'));
      expect(g.pending.values.single.body, isNot(contains('Cloud Service')));
      final id = g.pending.keys.single;
      g.calls.clear();
      await actual.rescheduleAll([fixture.sub(id: 'b'), fixture.sub(id: 'a')]);
      expect(g.pending.keys.single, id);
      expect(g.calls, isEmpty);
    },
  );
  test('different business event does not group', () async {
    final g = Stage4Gateway();
    await scheduler(g).rescheduleAll([
      fixture.sub(id: 'a'),
      fixture.sub(
        id: 'b',
        management: SubscriptionManagement(
          reminderRules: [
            SubscriptionReminderRule(
              event: SubscriptionReminderEvent.decision,
              daysBefore: [7],
            ),
          ],
        ),
      ),
    ]);
    expect(g.pending.length, 2);
  });
  test('same event at different times does not group', () async {
    final g = Stage4Gateway();
    await scheduler(g).rescheduleAll([
      fixture.sub(id: 'a'),
      fixture.sub(id: 'b', next: DateTime(2026, 10, 10)),
    ]);
    expect(g.pending.length, 2);
  });
  test(
    'privacy and language rebuild detailed reminders across process restart while keeping foreign/test',
    () async {
      final g = Stage4Gateway();
      final first = scheduler(g)
        ..updatePrivacy(NotificationPrivacy.fullSummary);
      final sub = fixture.sub(next: DateTime(2026, 10, 10));
      await first.rescheduleAll([sub]);
      expect(g.pending.values.single.body, contains('Cloud Service'));
      g.pending[999] = const PendingReminderNotification(
        id: 999,
        title: 'foreign',
        body: 'keep',
      );
      final next = scheduler(g)..updateLanguage(CardockLanguage.english);
      await next.rescheduleAll([sub]);
      expect(g.pending[999]?.body, 'keep');
      expect(g.cancelAllCalls, 0);
      expect(
        g.pending.values
            .where((p) => p.payload == reminderNavigationPayload)
            .single
            .body,
        isNot(contains('Cloud Service')),
      );
      expect(
        g.pending.values
            .where((p) => p.payload == reminderNavigationPayload)
            .single
            .body,
        contains('Renewal'),
      );
    },
  );
  test(
    'exact permission fallback reuses stable id and minimal payload',
    () async {
      final g = Stage4Gateway()..rejectExact = true;
      await scheduler(
        g,
      ).rescheduleAll([fixture.sub(next: DateTime(2026, 10, 10))]);
      expect(g.calls.length, 2);
      expect(g.calls.toSet().length, 1);
      expect(g.pending.values.single.payload, reminderNavigationPayload);
    },
  );
  test(
    'cancel failure retains old plan and retry repairs without cancelAll',
    () async {
      final g = Stage4Gateway(),
          sub = fixture.sub(next: DateTime(2026, 10, 10));
      final s = scheduler(g);
      await s.rescheduleAll([sub]);
      g.failCancel = true;
      s.updatePrivacy(NotificationPrivacy.fullSummary);
      await expectLater(
        s.rescheduleAll([sub]),
        throwsA(isA<ReminderSchedulingException>()),
      );
      g.failCancel = false;
      await s.rescheduleAll([sub]);
      expect(g.pending.length, 1);
      expect(g.pending.values.single.body, contains('Cloud Service'));
    },
  );
}
