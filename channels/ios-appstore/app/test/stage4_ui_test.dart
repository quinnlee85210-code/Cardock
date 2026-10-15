import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/core/theme/cardock_theme_types.dart';
import 'package:account_subscription_manager/core/preferences/notification_privacy_preferences.dart';
import 'package:account_subscription_manager/features/settings/presentation/notification_privacy_card.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/calendar_reminder_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:account_subscription_manager/l10n/translations_stage4.dart';
import 'support/stage4_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Stage4Harness h;
  setUpAll(() async {
    h = await Stage4Harness.create();
    await h.addSubscription();
  });
  tearDownAll(() async {
    await h.dispose();
  });
  test(
    'every Stage 4 source key has explicit English and Japanese translation',
    () {
      expect(
        stage4EnglishTranslations.keys.toSet(),
        stage4JapaneseTranslations.keys.toSet(),
      );
      for (final locale in [const Locale('en'), const Locale('ja')]) {
        final l10n = AppLocalizations(locale);
        final map = locale.languageCode == 'en'
            ? stage4EnglishTranslations
            : stage4JapaneseTranslations;
        for (final entry in map.entries) {
          expect(l10n.translate(entry.key), entry.value, reason: entry.key);
          if (RegExp(r'[\u4e00-\u9fff]').hasMatch(entry.key)) {
            expect(entry.value, isNot(entry.key));
          }
        }
        expect(
          l10n.translate('共 {count} 个事件；提醒：{alarm}', {
            'count': 12,
            'alarm': '1',
          }),
          isNot(contains('{')),
        );
        expect(
          l10n.translate('所选来源：Chrome；实际识别：CSV。文件结构不匹配，尚未生成导入计划；可改用通用映射。'),
          isNot(startsWith('所选')),
        );
      }
    },
  );
  for (final family in CardockThemeFamily.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'stage4 full responsive matrix ${family.name}/${brightness.name}: 3 locales x 4 widths x 4 scales x 2 pages',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final theme = AppTheme.build(family, brightness);
          for (final locale in AppLocalizations.supportedLocales) {
            for (final width in [320.0, 360.0, 393.0, 411.0]) {
              for (final scale in [1.0, 1.3, 1.5, 2.0]) {
                tester.view.physicalSize = Size(
                  width,
                  {
                    320.0: 640.0,
                    360.0: 800.0,
                    393.0: 873.0,
                    411.0: 915.0,
                  }[width]!,
                );
                Widget app(Widget child) => MaterialApp(
                  locale: locale,
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  theme: theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: child,
                );
                final reason = '${locale.languageCode} $width $scale';
                await tester.pumpWidget(
                  app(
                    Scaffold(
                      body: ListView(
                        children: [NotificationPrivacyCard(state: h.state)],
                      ),
                    ),
                  ),
                );
                await tester.pumpAndSettle();
                for (final level in NotificationPrivacy.values) {
                  final target = find.byKey(
                    ValueKey('notification-privacy-${level.name}'),
                  );
                  expect(
                    tester.getSize(target).height,
                    greaterThanOrEqualTo(48),
                    reason: reason,
                  );
                }
                expect(tester.takeException(), isNull, reason: reason);
                await tester.pumpWidget(
                  app(
                    CalendarReminderPage(
                      state: h.state,
                      singleRecordId: h.state.subscriptions.single.id,
                    ),
                  ),
                );
                await tester.pumpAndSettle();
                await tester.scrollUntilVisible(
                  find.byKey(const ValueKey('calendar-insert')),
                  500,
                  maxScrolls: 40,
                );
                expect(tester.takeException(), isNull, reason: reason);
                final button = find.byKey(const ValueKey('calendar-insert'));
                expect(
                  tester.getSize(button).height,
                  greaterThanOrEqualTo(48),
                  reason: reason,
                );
                expect(
                  tester.widget<FilledButton>(button).onPressed,
                  isNotNull,
                );
                await tester.pumpWidget(const SizedBox());
              }
            }
          }
        },
        timeout: const Timeout(Duration(minutes: 4)),
      );
    }
  }
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      'calendar default privacy, one-day alarm, confirmation cancel, new entry reset ${locale.languageCode}',
      (tester) async {
        tester.view.physicalSize = const Size(393, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final l10n = AppLocalizations(locale);
        Widget app() => MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: AppTheme.light(),
          home: CalendarReminderPage(
            state: h.state,
            singleRecordId: h.state.subscriptions.single.id,
          ),
        );
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ListTile>(
                find.byKey(const ValueKey('calendar-privacy-privacy')),
              )
              .selected,
          true,
        );
        await tester.tap(
          find.byKey(const ValueKey('calendar-privacy-fullSummary')),
        );
        await tester.pump();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('calendar-alarm-oneDay')),
          400,
        );
        expect(
          tester
              .widget<ListTile>(
                find.byKey(const ValueKey('calendar-alarm-oneDay')),
              )
              .selected,
          true,
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('calendar-insert')),
          400,
        );
        await tester.tap(find.byKey(const ValueKey('calendar-insert')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(l10n.translate('确认打开系统日历？')), findsOneWidget);
        await tester.tap(find.text(l10n.translate('取消')));
        await tester.pumpAndSettle();
        expect(h.state.isBusy, false);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ListTile>(
                find.byKey(const ValueKey('calendar-privacy-privacy')),
              )
              .selected,
          true,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'notification privacy controls expose labeled selected semantics and Android tap targets',
    (tester) async {
      tester.view.physicalSize = const Size(411, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh', 'CN'),
          theme: AppTheme.light(),
          home: Scaffold(
            body: ListView(children: [NotificationPrivacyCard(state: h.state)]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('notification-privacy-privacy')),
            )
            .label,
        contains('隐私模式'),
      );
      for (final level in NotificationPrivacy.values) {
        final row = find.byKey(ValueKey('notification-privacy-${level.name}'));
        expect(tester.getSize(row).height, inInclusiveRange(48, 52));
      }
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await tester.tap(
        find.byKey(const ValueKey('notification-privacy-serviceName')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(h.state.notificationPrivacy, NotificationPrivacy.privacy);
      handle.dispose();
    },
  );
}
