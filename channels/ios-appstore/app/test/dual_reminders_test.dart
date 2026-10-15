import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/notifications/reminder_scheduler.dart';
import 'package:account_subscription_manager/core/storage/portable_backup_codec.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'stage2_subscription_management_test.dart' as fixture;
import 'stage4_notification_privacy_test.dart' show Stage4Gateway;
import 'support/fake_vault_store.dart';
import 'support/recording_reminder_scheduler.dart';

const first = 12 * 60 + 30;
const second = 17 * 60;
List<SubscriptionReminderOccurrence> points(
  SubscriptionRecord record, {
  DateTime? now,
  int firstTime = first,
  int secondTime = second,
}) => subscriptionReminderOccurrences(
  record,
  reminderTimeMinutes: firstTime,
  secondReminderTimeMinutes: secondTime,
  now: now ?? DateTime(2026, 9, 1),
);
LocalReminderScheduler scheduler(
  Stage4Gateway gateway, {
  TargetPlatform platform = TargetPlatform.android,
  DateTime? now,
  String zone = 'Asia/Shanghai',
}) => LocalReminderScheduler(
  gateway: gateway,
  targetPlatform: platform,
  now: () => now ?? DateTime(2026, 9, 1),
  timeZoneIdentifier: () async => zone,
);

void main() {
  test(
    'schema13 migration is atomic and a failed second-time save leaves the plan intact',
    () async {
      const password = 'TEST-ONLY-MASTER-1234';
      final raw =
          fixture
              .vault([fixture.sub()])
              .copyWith(
                preferences: const VaultPreferences(
                  defaultReminderTimeMinutes: 545,
                ),
              )
              .toEncryptedPayloadJson()
            ..['schemaVersion'] = 13;
      (raw['preferences'] as Map).remove('secondReminderTimeMinutes');
      final old = VaultSnapshot.fromEncryptedPayloadJson(raw);
      final store = FakeVaultStore(
        configured: true,
        acceptedPassword: password,
        snapshot: old,
      )..failSaves = true;
      final recorder = RecordingReminderScheduler();
      final state = AppState(vaultStore: store, reminderScheduler: recorder);
      addTearDown(state.dispose);
      await state.initialize();
      expect(await state.unlock(password), isNot(VaultActionResult.success));
      expect(identical(store.snapshot, old), isTrue);
      expect(store.saveCalls, 0);
      expect(recorder.rescheduleCalls, isEmpty);
      store.failSaves = false;
      expect(await state.unlock(password), VaultActionResult.success);
      expect(store.saveCalls, 1);
      expect(state.preferences.defaultReminderTimeMinutes, 545);
      expect(state.preferences.secondReminderTimeMinutes, second);
      state.lock();
      expect(await state.unlock(password), VaultActionResult.success);
      expect(store.saveCalls, 1);
      await state.setNotificationsEnabled(true);
      recorder.reset();
      store.failSaves = true;
      expect(
        await state.updatePreferences(
          state.preferences.copyWith(secondReminderTimeMinutes: 1100),
        ),
        isFalse,
      );
      expect(store.snapshot.preferences.secondReminderTimeMinutes, second);
      expect(state.preferences.secondReminderTimeMinutes, second);
      expect(recorder.rescheduleCalls, isEmpty);
    },
  );

  test(
    'new preferences default to 12:30 and 17:00 with notifications still opt-in',
    () {
      const p = VaultPreferences();
      expect(p.defaultReminderTimeMinutes, first);
      expect(p.secondReminderTimeMinutes, second);
      expect(p.notificationsEnabled, isFalse);
    },
  );
  for (final version in [4, 8, 12, 13]) {
    test('schema $version upgrade retains records and saved first time', () {
      final source =
          VaultSnapshot(
            nextAccountId: 2,
            accounts: [
              AccountRecord.fromDraft(
                id: 'account-1',
                draft: AccountDraft(platformName: 'Migration fixture'),
              ),
            ],
            nextSubscriptionId: 2,
            subscriptions: [fixture.sub(account: 'account-1')],
          ).copyWith(
            preferences: const VaultPreferences(
              defaultReminderTimeMinutes: 545,
              defaultCurrency: 'JPY',
            ),
          );
      final old = source.toEncryptedPayloadJson()..['schemaVersion'] = version;
      (old['preferences'] as Map).remove('secondReminderTimeMinutes');
      if (version < 9) {
        ((old['subscriptions'] as List).single as Map).remove(
          'expenseCategory',
        );
      }
      final restored = VaultSnapshot.fromEncryptedPayloadJson(old);
      expect(restored.requiresSchemaUpgrade, isTrue);
      expect(restored.preferences.defaultReminderTimeMinutes, 545);
      expect(restored.preferences.secondReminderTimeMinutes, second);
      expect(restored.preferences.defaultCurrency, 'JPY');
      expect(
        restored.subscriptions.single.serviceName,
        source.subscriptions.single.serviceName,
      );
      expect(
        restored.subscriptions.single.amount,
        source.subscriptions.single.amount,
      );
      expect(restored.toEncryptedPayloadJson()['schemaVersion'], 15);
      expect(
        VaultSnapshot.fromEncryptedPayloadJson(
          restored.toEncryptedPayloadJson(),
        ).requiresSchemaUpgrade,
        isFalse,
      );
    });
  }
  for (final invalid in [null, -1, 1440, '17:00', 1020.0]) {
    test(
      'schema 14 rejects malformed second time $invalid (${invalid.runtimeType})',
      () {
        final json = VaultSnapshot.empty().toEncryptedPayloadJson();
        (json['preferences'] as Map)['secondReminderTimeMinutes'] = invalid;
        expect(
          () => VaultSnapshot.fromEncryptedPayloadJson(json),
          throwsA(isA<VaultFormatException>()),
        );
      },
    );
  }
  test('schema 14 requires its new field and future schemas refuse early', () {
    final json = VaultSnapshot.empty().toEncryptedPayloadJson();
    (json['preferences'] as Map).remove('secondReminderTimeMinutes');
    expect(
      () => VaultSnapshot.fromEncryptedPayloadJson(json),
      throwsA(isA<VaultFormatException>()),
    );
    expect(
      () => VaultSnapshot.fromEncryptedPayloadJson({'schemaVersion': 16}),
      throwsA(isA<VaultUnsupportedSchemaVersionException>()),
    );
  });
  test(
    'two custom times survive encrypted portable backup and copyWith',
    () async {
      final source = fixture
          .vault([fixture.sub()])
          .copyWith(
            preferences: const VaultPreferences(
              defaultReminderTimeMinutes: 65,
              secondReminderTimeMinutes: 1439,
            ).copyWith(defaultCurrency: 'USD'),
          );
      final codec = PortableBackupCodec();
      const password = 'Test-Only-Backup-Cobalt-74!River';
      final bytes = await codec.encryptV2(
        snapshot: source,
        backupMasterPassword: password,
      );
      final restored = await codec.read(
        bytes: bytes,
        backupMasterPassword: password,
      );
      expect(
        restored.snapshot.toEncryptedPayloadJson(),
        source.toEncryptedPayloadJson(),
      );
      expect(restored.inspection.sourceSchemaVersion, 15);
    },
  );
  test(
    'ordinary reminders have two unique stable IDs on the reminder date',
    () {
      final record = fixture.sub();
      final result = points(record);
      expect(result.map((p) => p.at), [
        DateTime(2026, 9, 3, 12, 30),
        DateTime(2026, 9, 3, 17),
      ]);
      expect(result.first.id, reminderNotificationId(record.id));
      expect(result.map((p) => p.id).toSet(), hasLength(2));
      expect(
        subscriptionReminderIds(record.id),
        containsAll(result.map((p) => p.id)),
      );
      expect(points(record).map((p) => p.id), result.map((p) => p.id));
    },
  );
  test('after the first time the second reminder remains scheduled today', () {
    final remaining = points(fixture.sub(), now: DateTime(2026, 9, 3, 13));
    expect(remaining.single.at, DateTime(2026, 9, 3, 17));
    expect(points(fixture.sub(), now: DateTime(2026, 9, 3, 17)), isEmpty);
  });
  test(
    'equal times deduplicate and reversed times sort without changing identities',
    () {
      expect(points(fixture.sub(), firstTime: second), hasLength(1));
      final result = points(fixture.sub(), firstTime: 1439, secondTime: 0);
      expect(result.map((p) => p.at.hour * 60 + p.at.minute), [0, 1439]);
      expect(result.last.id, reminderNotificationId(fixture.sub().id));
    },
  );
  test(
    'every configured lead day receives both times for renewals and trials',
    () {
      for (final trial in [false, true]) {
        final result = points(
          fixture.sub(
            management: SubscriptionManagement(
              trial: trial ? fixture.trial() : null,
              reminderRules: [
                SubscriptionReminderRule(
                  event: trial
                      ? SubscriptionReminderEvent.trialEnd
                      : SubscriptionReminderEvent.renewal,
                  daysBefore: [3, 1, 0],
                ),
              ],
            ),
          ),
        );
        expect(result, hasLength(6));
        expect(result.map((p) => p.id).toSet(), hasLength(6));
        expect(result.map((p) => p.at.day), [7, 7, 9, 9, 10, 10]);
      }
    },
  );
  test(
    'date snooze receives two times; exact snooze stays one UTC instant',
    () {
      expect(
        points(fixture.sub().snoozeReminderUntil(DateTime(2026, 9, 5))),
        hasLength(2),
      );
      final exact = DateTime.utc(2026, 9, 5, 4, 7);
      final result = points(
        fixture.sub().snoozeReminder(
          SubscriptionSnoozeTarget.exactInstant(exact),
        ),
      );
      expect(result.single.at, exact);
      expect(result.single.exactInstant, isTrue);
    },
  );
  test('canceled subscriptions receive neither reminder', () {
    expect(
      points(fixture.sub().cancel(cancelledOn: DateTime(2026, 9, 1))),
      isEmpty,
    );
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform schedules both slots, preserves privacy, and reconciles edits and cancellation',
      () async {
        final g = Stage4Gateway();
        final s = scheduler(g, platform: platform);
        await s.rescheduleAll(
          [fixture.sub()],
          reminderTimeMinutes: first,
          secondReminderTimeMinutes: second,
        );
        final ids = g.pending.keys.toSet();
        expect(ids, hasLength(2));
        expect(g.times.values.map((t) => t.hour * 60 + t.minute), [
          first,
          second,
        ]);
        expect(
          g.pending.values.every((p) => p.payload == reminderNavigationPayload),
          isTrue,
        );
        expect(
          g.pending.values.any((p) => p.body!.contains('Cloud Service')),
          isFalse,
        );
        g.calls.clear();
        await s.rescheduleAll(
          [fixture.sub()],
          reminderTimeMinutes: first,
          secondReminderTimeMinutes: second,
        );
        expect(g.calls, isEmpty);
        await s.rescheduleAll(
          [fixture.sub()],
          reminderTimeMinutes: first,
          secondReminderTimeMinutes: 18 * 60,
        );
        expect(g.calls, hasLength(1));
        expect(g.pending.keys.toSet(), ids);
        await s.cancel(fixture.sub().id);
        expect(g.pending, isEmpty);
      },
    );
    test(
      '$platform groups each time separately and retains both after a fresh scheduler starts',
      () async {
        final g = Stage4Gateway();
        final records = [fixture.sub(), fixture.sub(id: 'subscription-2')];
        await scheduler(g, platform: platform).rescheduleAll(
          records,
          reminderTimeMinutes: first,
          secondReminderTimeMinutes: second,
        );
        expect(g.pending, hasLength(2));
        await scheduler(g, platform: platform).rescheduleAll(
          records,
          reminderTimeMinutes: first,
          secondReminderTimeMinutes: second,
        );
        expect(g.pending, hasLength(2));
        await scheduler(
          g,
          platform: platform,
        ).rescheduleAll([], secondReminderTimeMinutes: second);
        expect(g.pending, isEmpty);
      },
    );
  }
  test(
    'iOS keeps earliest 60 points and reserves a slot for password review',
    () async {
      final g = Stage4Gateway();
      final s = scheduler(g, platform: TargetPlatform.iOS);
      final records = List.generate(
        50,
        (i) => fixture.sub(
          id: 'subscription-${i + 1}',
          next: DateTime(2026, 9, 10 + i),
        ),
      );
      await s.rescheduleAll(
        records,
        reminderTimeMinutes: first,
        secondReminderTimeMinutes: second,
        passwordReviewAtUtc: DateTime.utc(2026, 9, 2),
      );
      expect(g.pending, hasLength(60));
      expect(g.pending, contains(passwordReviewReminderNotificationId));
      final businessTimes = g.times.entries
          .where((e) => e.key != passwordReviewReminderNotificationId)
          .map((e) => e.value)
          .toList();
      expect(businessTimes.first.day, 3);
      expect(businessTimes.first.hour, 12);
      expect(businessTimes[1].hour, 17);
    },
  );
  test(
    'local wall clock times respect daylight saving at the target date',
    () async {
      final g = Stage4Gateway();
      final s = scheduler(g, zone: 'America/New_York');
      await s.rescheduleAll(
        [fixture.sub(next: DateTime(2026, 11, 8))],
        reminderTimeMinutes: first,
        secondReminderTimeMinutes: second,
      );
      expect(g.times.values.map((t) => t.hour * 60 + t.minute), [
        first,
        second,
      ]);
      expect(g.times.values.map((t) => t.timeZoneOffset).toSet(), {
        const Duration(hours: -5),
      });
    },
  );
  test(
    'invalid second slot fails before clearing an existing system plan',
    () async {
      final g = Stage4Gateway();
      final s = scheduler(g);
      await s.rescheduleAll([fixture.sub()], secondReminderTimeMinutes: second);
      final ids = g.pending.keys.toSet();
      await expectLater(
        s.rescheduleAll([fixture.sub()], secondReminderTimeMinutes: 1440),
        throwsArgumentError,
      );
      expect(g.pending.keys.toSet(), ids);
      expect(g.canceled, isEmpty);
    },
  );
  test(
    'AppState saves second-only edits, retries scheduling failure and restores both after restart',
    () async {
      const password = 'TEST-ONLY-MASTER-1234';
      final store = FakeVaultStore(
        configured: true,
        acceptedPassword: password,
      );
      final recorder = RecordingReminderScheduler();
      var state = AppState(vaultStore: store, reminderScheduler: recorder);
      addTearDown(() => state.dispose());
      await state.initialize();
      await state.unlock(password);
      await state.setNotificationsEnabled(true);
      expect(recorder.rescheduleCalls.last.reminderTimeMinutes, first);
      expect(recorder.rescheduleCalls.last.secondReminderTimeMinutes, second);
      recorder.reset();
      recorder.failOn = ReminderSchedulerOperation.rescheduleAll;
      expect(
        await state.updatePreferences(
          state.preferences.copyWith(secondReminderTimeMinutes: 1110),
        ),
        isTrue,
      );
      expect(store.snapshot.preferences.secondReminderTimeMinutes, 1110);
      expect(store.notificationReconciliation, isNotNull);
      state.lock();
      state.dispose();
      recorder.reset();
      state = AppState(vaultStore: store, reminderScheduler: recorder);
      await state.initialize();
      await state.unlock(password);
      await Future<void>.delayed(Duration.zero);
      expect(state.preferences.secondReminderTimeMinutes, 1110);
      expect(recorder.rescheduleCalls.last.reminderTimeMinutes, first);
      expect(recorder.rescheduleCalls.last.secondReminderTimeMinutes, 1110);
    },
  );
}
