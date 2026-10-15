import 'dart:async';
import 'dart:io';
import 'package:account_subscription_manager/core/storage/auto_backup_controller.dart';
import 'package:account_subscription_manager/core/storage/portable_backup_codec.dart';
import 'package:account_subscription_manager/core/storage/vault_rebuild_service.dart';
import 'stage1_safety_integration_test.dart' show RebuildNative;
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/calendar/calendar_reminder.dart';
import 'package:account_subscription_manager/core/platform/calendar_bridge.dart';
import 'package:account_subscription_manager/core/preferences/notification_privacy_preferences.dart';
import 'package:account_subscription_manager/core/preferences/language_preferences.dart';
import 'package:account_subscription_manager/core/storage/layered_vault_store.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/data_import/presentation/app_data_import_ui_controller.dart';
import 'package:account_subscription_manager/features/data_import/presentation/data_import_ui_controller.dart';
import 'stage1_backup_export_test.dart' show MemoryDocuments;
import 'support/stage4_harness.dart';
import 'support/recording_reminder_scheduler.dart';

class FaultPrivacy implements NotificationPrivacyStore {
  NotificationPrivacy value = NotificationPrivacy.privacy;
  bool fail = false;
  @override
  Future<NotificationPrivacy> read() async => value;
  @override
  Future<void> write(NotificationPrivacy level) async {
    if (fail) throw StateError('synthetic write failure');
    value = level;
  }
}

class IntentRecorder implements CalendarBridge {
  int calls = 0;
  CalendarInsertResult result = CalendarInsertResult.unavailable;
  @override
  Future<CalendarInsertResult> insert(
    CalendarEventProjection event, {
    required NotificationPrivacy privacy,
    required CardockLanguage language,
    required CalendarAlarm alarm,
  }) async {
    calls++;
    return result;
  }
}

CalendarReminderPlan? calendarPlan(Stage4Harness h) => h.state.projectCalendar(
  singleRecordId: h.state.subscriptions.isEmpty
      ? 'missing'
      : h.state.subscriptions.first.id,
);
Future<bool> openCalendar(
  Stage4Harness h, {
  CalendarReminderPlan? plan,
  bool confirmed = true,
}) async =>
    await h.state.insertCalendar(
      plan ?? calendarPlan(h)!,
      privacy: NotificationPrivacy.fullSummary,
      language: CardockLanguage.english,
      disclosureConfirmed: confirmed,
      bridge: IntentRecorder()..result = CalendarInsertResult.opened,
    ) ==
    CalendarInsertResult.opened;
Uint8List browserCsv(String rows) =>
    Uint8List.fromList(utf8.encode('name,url,username,password,note\r\n$rows'));
Future<void> confirm(AppDataImportUiController c) async {
  for (
    var n = 0;
    n < 8 &&
        c.state.step.index < DataImportWizardStep.confirmation.index &&
        c.state.errorMessage == null;
    n++
  ) {
    await c.next();
  }
  expect(c.state.errorMessage, isNull);
  expect(c.state.step, DataImportWizardStep.confirmation);
  c.setFinalConfirmation(true);
  await c.commit();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'device privacy confirmation, persistence failure, real-vault revision and selective reconciliation',
    () async {
      final pref = FaultPrivacy();
      final h = await Stage4Harness.create(privacy: pref);
      addTearDown(h.dispose);
      await h.state.refreshReminderScheduleForReliability(contentOnly: true);
      h.reminders.reset();
      final revision = h.state.localWebRevision;
      expect(
        await h.state.setNotificationPrivacy(NotificationPrivacy.fullSummary),
        false,
      );
      expect(pref.value, NotificationPrivacy.privacy);
      expect(
        await h.state.setNotificationPrivacy(
          NotificationPrivacy.serviceName,
          riskConfirmed: true,
        ),
        true,
      );
      expect(h.state.localWebRevision, revision);
      expect(h.reminders.cancelAllCalls, 0);
      pref.fail = true;
      expect(
        await h.state.setNotificationPrivacy(
          NotificationPrivacy.fullSummary,
          riskConfirmed: true,
        ),
        false,
      );
      expect(h.state.notificationPrivacy, NotificationPrivacy.serviceName);
      pref.fail = false;
      expect(
        await h.state.setNotificationPrivacy(NotificationPrivacy.privacy),
        true,
      );
      expect(pref.value, NotificationPrivacy.privacy);
      expect(h.reminders.cancelAllCalls, 0);
      h.state.lock();
      expect(
        await h.state.setNotificationPrivacy(
          NotificationPrivacy.fullSummary,
          riskConfirmed: true,
        ),
        false,
      );
    },
  );
  test(
    'privacy outbox failure remains retryable without changing business records',
    () async {
      final h = await Stage4Harness.create();
      addTearDown(h.dispose);
      await h.addSubscription();
      await h.state.updatePreferences(
        h.state.preferences.copyWith(notificationsEnabled: true),
      );
      final revision = h.state.localWebRevision;
      h.reminders.failOn = ReminderSchedulerOperation.rescheduleAll;
      expect(
        await h.state.setNotificationPrivacy(
          NotificationPrivacy.serviceName,
          riskConfirmed: true,
        ),
        true,
      );
      expect(h.state.warningMessage, isNotNull);
      expect(h.state.localWebRevision, revision);
      h.reminders.failOn = null;
      expect(
        await h.state.refreshReminderScheduleForReliability(contentOnly: true),
        true,
      );
      expect(h.state.subscriptions.length, 1);
    },
  );
  test(
    'real and decoy calendars have isolated bindings; device privacy unavailable in decoy',
    () async {
      final h = await Stage4Harness.create();
      addTearDown(h.dispose);
      await h.addSubscription();
      final real = calendarPlan(h)!;
      expect(
        await h.state.createDecoyVault(
          currentMasterPassword: stage4Master,
          decoyPassword: stage4Decoy,
        ),
        true,
      );
      h.state.lock();
      expect(await h.state.unlock(stage4Decoy), VaultActionResult.success);
      expect(h.state.hasFullVaultAccess, true);
      expect(h.state.canManageSecurity, false);
      expect(h.state.canChangeNotificationPrivacy, false);
      expect(h.state.canOpenCalendar, true);
      expect(calendarPlan(h)!.events, isEmpty);
      expect(await openCalendar(h, plan: real), false);
      await h.addSubscription();
      final decoy = calendarPlan(h)!;
      expect(decoy.vaultBindingId, isNot(real.vaultBindingId));
      expect(await openCalendar(h), true);
      h.state.lock();
      await h.state.unlock(stage4Master);
      expect(calendarPlan(h)!.vaultBindingId, real.vaultBindingId);
      expect(await openCalendar(h, plan: decoy), false);
    },
  );
  test(
    'subscription-only biometric view rejects calendar and privacy mutation and CSV writes',
    () async {
      final h = await Stage4Harness.create();
      addTearDown(h.dispose);
      await h.addSubscription();
      final real = calendarPlan(h)!;
      expect(
        await h.state.enableQuickUnlock(
          stage4Master,
          scope: QuickUnlockScope.subscriptionsOnly,
        ),
        true,
      );
      h.state.lock();
      expect(await h.state.unlockWithQuickUnlock(), VaultActionResult.success);
      expect(h.state.hasFullVaultAccess, false);
      expect(h.state.canOpenCalendar, false);
      expect(calendarPlan(h), isNull);
      expect(await openCalendar(h, plan: real), false);
      expect(
        await h.state.setNotificationPrivacy(
          NotificationPrivacy.serviceName,
          riskConfirmed: true,
        ),
        false,
      );
      final c = AppDataImportUiController(appState: h.state);
      addTearDown(c.dispose);
      await c.loadFile(
        fileName: 'synthetic.csv',
        bytes: browserCsv('A,https://example.invalid,a,p,n'),
      );
      expect(c.state.canWrite, false);
      expect(c.state.rows, isEmpty);
    },
  );
  test(
    'single calendar opening preserves business revision and rejects stale plans',
    () async {
      final h = await Stage4Harness.create();
      addTearDown(h.dispose);
      await h.addSubscription();
      final revision = h.state.localWebRevision;
      expect(await openCalendar(h, confirmed: false), false);
      expect(await openCalendar(h), true);
      expect(h.state.localWebRevision, revision);
      final stale = calendarPlan(h)!;
      await h.state.createAccount(
        AccountDraft(platformName: 'Synthetic account'),
      );
      expect(await openCalendar(h, plan: stale), false);
      expect(h.state.subscriptions, hasLength(1));
    },
  );
  test(
    'single calendar intent has explicit consent and unavailable/failed outcomes; no implicit save claim',
    () async {
      final h = await Stage4Harness.create();
      addTearDown(h.dispose);
      await h.addSubscription();
      final plan = h.state.projectCalendar(
        singleRecordId: h.state.subscriptions.single.id,
      )!;
      final bridge = IntentRecorder();
      Future<CalendarInsertResult> insert(bool consent) =>
          h.state.insertCalendar(
            plan,
            privacy: NotificationPrivacy.privacy,
            language: CardockLanguage.english,
            disclosureConfirmed: consent,
            bridge: bridge,
          );
      expect(await insert(false), CalendarInsertResult.failed);
      expect(bridge.calls, 0);
      expect(await insert(true), CalendarInsertResult.unavailable);
      bridge.result = CalendarInsertResult.opened;
      expect(await insert(true), CalendarInsertResult.opened);
      h.state.lock();
      expect(await insert(true), CalendarInsertResult.failed);
      expect(bridge.calls, 2);
    },
  );
  test(
    'Android calendar bridge sends only allowlisted fields and handles missing plugin without raw errors',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Map<Object?, Object?>? args;
      messenger.setMockMethodCallHandler(AndroidCalendarBridge.channel, (
        call,
      ) async {
        args = call.arguments as Map<Object?, Object?>;
        return 'opened';
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          AndroidCalendarBridge.channel,
          null,
        ),
      );
      final h = await Stage4Harness.create();
      addTearDown(h.dispose);
      await h.addSubscription();
      final event = calendarPlan(h)!.events.first;
      expect(
        await const AndroidCalendarBridge().insert(
          event,
          privacy: NotificationPrivacy.privacy,
          language: CardockLanguage.english,
          alarm: CalendarAlarm.sevenDays,
        ),
        CalendarInsertResult.opened,
      );
      expect(args!.keys.toSet(), {'title', 'begin', 'end', 'alarmDays'});
      expect(args!['alarmDays'], 7);
      expect((args!['end'] as int) - (args!['begin'] as int), 86400000);
      messenger.setMockMethodCallHandler(
        AndroidCalendarBridge.channel,
        (_) async => throw PlatformException(code: 'synthetic'),
      );
      expect(
        await const AndroidCalendarBridge().insert(
          event,
          privacy: NotificationPrivacy.privacy,
          language: CardockLanguage.english,
          alarm: CalendarAlarm.none,
        ),
        CalendarInsertResult.failed,
      );
    },
  );
  for (final source in [
    'chrome_passwords_csv',
    'google_password_manager_csv',
  ]) {
    test(
      '$source imports exact password and same-domain different logins, clears raw memory, supports rollback',
      () async {
        final h = await Stage4Harness.create();
        addTearDown(h.dispose);
        final c = AppDataImportUiController(appState: h.state);
        addTearDown(c.dispose);
        await c.selectSource(source);
        final bytes = browserCsv(
          'Example,https://example.invalid,one,"  =TEST-only  ",note\r\nExample,https://example.invalid,two,second,',
        );
        await c.loadFile(fileName: 'synthetic.csv', bytes: bytes);
        expect(bytes.every((b) => b == 0), true);
        expect(c.state.rows.length, 2);
        expect(
          c.state.rows.every(
            (r) =>
                r.passwordStatus == DataImportPasswordStatus.encryptedForImport,
          ),
          true,
        );
        await confirm(c);
        expect(h.state.accounts.length, 2);
        expect(h.state.accounts.first.password, '  =TEST-only  ');
        expect(h.state.accounts.map((a) => a.loginAccount), ['one', 'two']);
        expect(c.state.rows, isEmpty);
        expect(c.state.fileName, isNull);
        expect(await h.state.undoLastBatchImport(), true);
        expect(h.state.accounts, isEmpty);
      },
    );
    test(
      '$source header mismatch creates no plan; explicit generic fallback and lock clears document',
      () async {
        final h = await Stage4Harness.create();
        addTearDown(h.dispose);
        final c = AppDataImportUiController(appState: h.state);
        addTearDown(c.dispose);
        await c.selectSource(source);
        await c.loadFile(
          fileName: 'synthetic.csv',
          bytes: Uint8List.fromList(
            utf8.encode(
              'platform_name,login_account,password\nExample,user,synthetic',
            ),
          ),
        );
        expect(c.state.sourceMismatch, true);
        expect(c.state.planSummary, isNull);
        expect(h.state.accounts, isEmpty);
        await c.useGenericMapping();
        expect(c.state.sourceMismatch, false);
        expect(c.state.rows.length, 1);
        h.state.lock();
        expect(c.state.rows, isEmpty);
        expect(c.state.mappings, isEmpty);
        expect(c.state.fileName, isNull);
      },
    );
  }
  for (final password in ['', '******', '••••••', '[redacted]']) {
    test(
      'browser empty or masked "$password" never overwrites existing password or history',
      () async {
        final h = await Stage4Harness.create();
        addTearDown(h.dispose);
        await h.state.createAccount(
          AccountDraft(
            platformName: 'Example',
            loginAccount: 'one',
            website: 'https://example.invalid',
            password: 'TEST-ONLY-existing',
          ),
        );
        final before = h.state.accounts.single.passwordChangeHistory.length;
        final c = AppDataImportUiController(appState: h.state);
        addTearDown(c.dispose);
        await c.loadFile(
          fileName: 'synthetic.csv',
          bytes: browserCsv(
            'Example,https://example.invalid,one,$password,note',
          ),
        );
        await c.next();
        await c.next();
        await c.next();
        final row = c.state.rows.single;
        expect(
          row.passwordStatus,
          isNot(DataImportPasswordStatus.maskedReviewRequired),
        );
        c.setDuplicateResolution(
          row.id,
          DataImportDuplicateResolution.mergeMissingFields,
        );
        await confirm(c);
        expect(h.state.accounts.single.password, 'TEST-ONLY-existing');
        expect(h.state.accounts.single.passwordChangeHistory.length, before);
        expect(c.state.commitSummary!.preservedPasswords, 1);
        expect(await h.state.undoLastBatchImport(), true);
        expect(h.state.accounts.single.password, 'TEST-ONLY-existing');
      },
    );
  }
  test(
    'browser valid explicit password replacement adds one history entry; rollback restores exact original',
    () async {
      final h = await Stage4Harness.create();
      addTearDown(h.dispose);
      await h.state.createAccount(
        AccountDraft(
          platformName: 'Example',
          loginAccount: 'one',
          website: 'https://example.invalid',
          password: 'TEST-ONLY-before',
          notes: 'before',
        ),
      );
      final original = h.state.accounts.single;
      final c = AppDataImportUiController(appState: h.state);
      addTearDown(c.dispose);
      await c.loadFile(
        fileName: 'synthetic.csv',
        bytes: browserCsv(
          'Example,https://example.invalid,one,TEST-ONLY-after,after',
        ),
      );
      await c.next();
      await c.next();
      await c.next();
      final row = c.state.rows.single;
      c.setDuplicateResolution(
        row.id,
        DataImportDuplicateResolution.fieldByField,
      );
      for (final field in row.fieldComparisons.values) {
        c.setDuplicateFieldChoice(
          row.id,
          field.fieldName,
          field.fieldName == 'password',
        );
      }
      await confirm(c);
      expect(h.state.accounts.single.password, 'TEST-ONLY-after');
      expect(h.state.accounts.single.notes, 'before');
      expect(
        h.state.accounts.single.passwordChangeHistory.length,
        original.passwordChangeHistory.length + 1,
      );
      expect(await h.state.undoLastBatchImport(), true);
      expect(h.state.accounts.single.password, original.password);
      expect(h.state.accounts.single.notes, original.notes);
      expect(
        h.state.accounts.single.passwordChangeHistory.length,
        original.passwordChangeHistory.length,
      );
    },
  );
  test('browser free quota rejects 16 new accounts atomically', () async {
    final h = await Stage4Harness.create();
    addTearDown(h.dispose);
    final c = AppDataImportUiController(appState: h.state);
    addTearDown(c.dispose);
    await c.loadFile(
      fileName: 'synthetic.csv',
      bytes: browserCsv(
        List.generate(
          16,
          (i) => 'Service$i,https://example$i.invalid,user$i,TEST-ONLY,n',
        ).join('\r\n'),
      ),
    );
    for (
      var i = 0;
      i < 6 &&
          c.state.errorMessage == null &&
          c.state.step != DataImportWizardStep.confirmation;
      i++
    ) {
      await c.next();
    }
    c.setFinalConfirmation(true);
    await c.commit();
    expect(h.state.accounts, isEmpty);
    expect(c.state.commitSummary, isNull);
    expect(c.state.errorMessage, isNotNull);
  });

  test(
    'five-minute sensitive session deadline clears loaded CSV, mapping, previews and authority',
    () async {
      final h = await Stage4Harness.create();
      addTearDown(h.dispose);
      late void Function() expire;
      late Duration duration;
      final c = AppDataImportUiController(
        appState: h.state,
        timerFactory: (d, callback) {
          duration = d;
          expire = callback;
          return Timer(const Duration(days: 1), () {});
        },
      );
      addTearDown(c.dispose);
      await c.loadFile(
        fileName: 'synthetic.csv',
        bytes: browserCsv('Example,https://example.invalid,one,TEST-ONLY,note'),
      );
      expect(c.state.rows.length, 1);
      expect(duration, const Duration(minutes: 5));
      expire();
      expect(c.state.rows, isEmpty);
      expect(c.state.mappings, isEmpty);
      expect(c.state.fileName, isNull);
      expect(c.state.planSummary, isNull);
      await c.commit();
      expect(h.state.accounts, isEmpty);
    },
  );

  test(
    'browser source only accepts explicitly selected CSV extension; other formats stay generic',
    () async {
      final h = await Stage4Harness.create();
      addTearDown(h.dispose);
      final c = AppDataImportUiController(appState: h.state);
      addTearDown(c.dispose);
      await c.selectSource('chrome_passwords_csv');
      await c.loadFile(
        fileName: 'synthetic.txt',
        bytes: browserCsv(
          'Example,https://example.invalid,user,TEST-ONLY,note',
        ),
      );
      expect(c.state.sourceMismatch, true);
      expect(c.state.rows, isEmpty);
      await c.useGenericMapping();
      expect(c.state.rows.length, 1);
      expect(h.state.accounts, isEmpty);
    },
  );

  test(
    'device privacy does not dirty or write enabled automatic business backup',
    () async {
      final h = await Stage4Harness.create();
      addTearDown(h.dispose);
      h.state.lock();
      final docs = MemoryDocuments();
      final backup = AutoBackupController(
        storage: docs,
        now: () => DateTime.utc(2026, 9, 4),
      );
      final state = AppState(vaultStore: h.store, autoBackupController: backup);
      addTearDown(state.dispose);
      await state.initialize();
      await state.unlock(stage4Master);
      expect(
        await state.configureAutoBackup(
          tree: 'tree',
          backupPassword: stage4Master,
          confirmation: stage4Master,
          currentPassword: stage4Master,
        ),
        true,
      );
      final count = docs.creates;
      final dirty = backup.status.dirtySince;
      final written = backup.status.lastWritten;
      expect(
        await state.setNotificationPrivacy(
          NotificationPrivacy.fullSummary,
          riskConfirmed: true,
        ),
        true,
      );
      expect(
        await state.setNotificationPrivacy(NotificationPrivacy.privacy),
        true,
      );
      expect(docs.creates, count);
      expect(backup.status.dirtySince, dirty);
      expect(backup.status.lastWritten, written);
      final restored = await PortableBackupCodec().read(
        bytes: docs.files.values.single,
        backupMasterPassword: stage4Master,
      );
      final payload = jsonEncode(restored.snapshot.toEncryptedPayloadJson());
      expect(payload, isNot(contains('notificationPrivacy')));
      expect(payload, isNot(contains('fullSummary')));
    },
  );
  test(
    'controlled rebuild resets file and in-memory notification privacy while preserving external ICS',
    () async {
      final h = await Stage4Harness.create();
      addTearDown(h.dispose);
      h.state.lock();
      final prefs = FileNotificationPrivacyStore(() async => h.directory);
      await prefs.write(NotificationPrivacy.fullSummary);
      final external = File(
        '${h.directory.path}/Cardock-calendar-synthetic.ics',
      );
      await external.writeAsString('BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n');
      final service = VaultRebuildService(
        directory: () async => h.directory,
        platform: RebuildNative(),
        reminders: h.reminders,
      );
      final state = AppState(
        vaultStore: h.store,
        rebuildService: service,
        notificationPrivacyStore: prefs,
      );
      addTearDown(state.dispose);
      await state.initialize();
      expect(state.notificationPrivacy, NotificationPrivacy.fullSummary);
      expect(
        await state.rebuildLocalVault(
          authorization: const RebuildAuthorization(
            'test-only',
            unsecured: false,
          ),
          phrase: '删除本机Cardock数据',
        ),
        true,
      );
      expect(state.notificationPrivacy, NotificationPrivacy.privacy);
      expect(await prefs.read(), NotificationPrivacy.privacy);
      expect(
        await external.readAsString(),
        'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n',
      );
    },
  );
  for (final existing in [null, 'TEST-ONLY-same']) {
    test(
      'browser ${existing == null ? 'first stored' : 'identical'} password does not fabricate change history',
      () async {
        final h = await Stage4Harness.create();
        addTearDown(h.dispose);
        await h.state.createAccount(
          AccountDraft(
            platformName: 'Example',
            loginAccount: 'one',
            website: 'https://example.invalid',
            password: existing,
          ),
        );
        final c = AppDataImportUiController(appState: h.state);
        addTearDown(c.dispose);
        await c.loadFile(
          fileName: 'synthetic.csv',
          bytes: browserCsv(
            'Example,https://example.invalid,one,TEST-ONLY-same,note',
          ),
        );
        await c.next();
        await c.next();
        await c.next();
        final row = c.state.rows.single;
        c.setDuplicateResolution(
          row.id,
          DataImportDuplicateResolution.fieldByField,
        );
        c.setDuplicateFieldChoice(row.id, 'password', true);
        await confirm(c);
        expect(h.state.accounts.single.password, 'TEST-ONLY-same');
        expect(h.state.accounts.single.passwordChangeHistory, isEmpty);
        expect(await h.state.undoLastBatchImport(), true);
        expect(h.state.accounts.single.password, existing);
      },
    );
  }
  test(
    'calendar projection excludes a trashed record and stale plan cannot open it',
    () async {
      final h = await Stage4Harness.create();
      addTearDown(h.dispose);
      await h.addSubscription();
      final before = calendarPlan(h)!;
      expect(before.events, isNotEmpty);
      expect(
        await h.state.deleteSubscription(h.state.subscriptions.single.id),
        true,
      );
      expect(h.state.trashSubscriptions.length, 1);
      expect(calendarPlan(h)!.events, isEmpty);
      expect(await openCalendar(h, plan: before), false);
    },
  );
}
