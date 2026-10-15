import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:account_subscription_manager/core/notifications/reminder_scheduler.dart';
import 'package:account_subscription_manager/core/preferences/language_preferences.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('根应用将语言即时同步到页面、通知调度器和 Android 原生桥', (tester) async {
    const channel = MethodChannel('cardock/platform_language');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final nativeLanguageCodes = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'setLanguage');
      final arguments = Map<Object?, Object?>.from(call.arguments as Map);
      nativeLanguageCodes.add(arguments['language']! as String);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final languageController = CardockLanguageController(
      store: MemoryLanguagePreferencesStore(),
    );
    await languageController.load();
    addTearDown(languageController.dispose);
    final scheduler = _LanguageRecordingScheduler();

    await tester.pumpWidget(
      AccountSubscriptionApp(
        vaultStore: FakeVaultStore(configured: false),
        reminderScheduler: scheduler,
        languageController: languageController,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('创建加密库'), findsOneWidget);
    expect(scheduler.languages.last, CardockLanguage.simplifiedChinese);
    expect(nativeLanguageCodes.last, 'zh_CN');

    await languageController.setLanguage(CardockLanguage.english);
    await tester.pumpAndSettle();
    expect(find.text('Create vault'), findsOneWidget);
    expect(scheduler.languages.last, CardockLanguage.english);
    expect(nativeLanguageCodes.last, 'en');

    await languageController.setLanguage(CardockLanguage.japanese);
    await tester.pumpAndSettle();
    expect(find.text('保管庫を作成'), findsOneWidget);
    expect(scheduler.languages.last, CardockLanguage.japanese);
    expect(nativeLanguageCodes.last, 'ja');
  });
}

final class _LanguageRecordingScheduler
    implements ReminderScheduler, LanguageAwareReminderScheduler {
  final List<CardockLanguage> languages = <CardockLanguage>[];

  @override
  void updateLanguage(CardockLanguage language) {
    languages.add(language);
  }

  @override
  Future<void> cancel(String subscriptionId) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<int> pendingReminderCount() async => 0;

  @override
  Future<ReminderPermissionStatus> requestPermission() async =>
      ReminderPermissionStatus.applicationNotificationsDisabled;

  @override
  Future<void> rescheduleAll(
    Iterable<SubscriptionRecord> subscriptions, {
    int reminderTimeMinutes = 12 * 60 + 30,
    int? secondReminderTimeMinutes,
    DateTime? passwordReviewAtUtc,
  }) async {}

  @override
  Future<void> schedule(
    SubscriptionRecord subscription, {
    int reminderTimeMinutes = 12 * 60 + 30,
    int? secondReminderTimeMinutes,
  }) async {}

  @override
  Future<void> scheduleTestReminder({
    Duration delay = const Duration(minutes: 1),
  }) async {}

  @override
  Future<void> showTestNotification() async {}
}
