import 'package:account_subscription_manager/core/preferences/language_preferences.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/accounts/presentation/widgets/account_record_card.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:account_subscription_manager/l10n/translations_records.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('默认保险分类保持稳定中文值并按语言显示', () {
    expect(accountCategories, contains('保险'));
    expect(
      localizedAccountCategory(CardockLanguage.simplifiedChinese, '保险'),
      '保险',
    );
    expect(
      localizedAccountCategory(CardockLanguage.english, '保险'),
      'Insurance',
    );
    expect(localizedAccountCategory(CardockLanguage.japanese, '保险'), '保険');
  });

  test('英语和日语数量 helper 覆盖 0、1、2 边界', () {
    final cases =
        <
          ({
            String name,
            String Function(CardockLanguage, int) format,
            List<String> english,
            List<String> japanese,
          })
        >[
          (
            name: 'account',
            format: localizedAccountCount,
            english: const <String>['0 accounts', '1 account', '2 accounts'],
            japanese: const <String>['0件のアカウント', '1件のアカウント', '2件のアカウント'],
          ),
          (
            name: 'subscription',
            format: localizedSubscriptionCount,
            english: const <String>[
              '0 subscriptions',
              '1 subscription',
              '2 subscriptions',
            ],
            japanese: const <String>[
              '0件のサブスクリプション',
              '1件のサブスクリプション',
              '2件のサブスクリプション',
            ],
          ),
          (
            name: 'subscription item',
            format: localizedSubscriptionItemCount,
            english: const <String>[
              '0 subscriptions',
              '1 subscription',
              '2 subscriptions',
            ],
            japanese: const <String>[
              '0件のサブスクリプション',
              '1件のサブスクリプション',
              '2件のサブスクリプション',
            ],
          ),
          (
            name: 'renewal date',
            format: localizedRenewalDayCount,
            english: const <String>[
              '0 renewal dates',
              '1 renewal date',
              '2 renewal dates',
            ],
            japanese: const <String>['0件の更新日', '1件の更新日', '2件の更新日'],
          ),
          (
            name: 'record',
            format: localizedRecordCount,
            english: const <String>['0 records', '1 record', '2 records'],
            japanese: const <String>['0件', '1件', '2件'],
          ),
          (
            name: 'days before',
            format: localizedDaysBefore,
            english: const <String>[
              '0 days before',
              '1 day before',
              '2 days before',
            ],
            japanese: const <String>['0日前', '1日前', '2日前'],
          ),
          (
            name: 'renewal history',
            format: localizedRenewalHistoryCount,
            english: const <String>[
              'Recorded 0 times',
              'Recorded once',
              'Recorded 2 times',
            ],
            japanese: const <String>['0回記録済み', '1回記録済み', '2回記録済み'],
          ),
        ];

    for (final testCase in cases) {
      for (var count = 0; count <= 2; count += 1) {
        expect(
          testCase.format(CardockLanguage.english, count),
          testCase.english[count],
          reason: '${testCase.name} English count=$count',
        );
        expect(
          testCase.format(CardockLanguage.japanese, count),
          testCase.japanese[count],
          reason: '${testCase.name} Japanese count=$count',
        );
      }
    }

    expect(localizedRenewalTiming(CardockLanguage.english, 0), 'Renews today');
    expect(
      localizedRenewalTiming(CardockLanguage.english, 1),
      'Renews in 1 day',
    );
    expect(
      localizedRenewalTiming(CardockLanguage.english, 2),
      'Renews in 2 days',
    );
    expect(localizedRenewalTiming(CardockLanguage.japanese, 0), '本日更新');
    expect(localizedRenewalTiming(CardockLanguage.japanese, 1), '1日後に更新');
    expect(localizedRenewalTiming(CardockLanguage.japanese, 2), '2日後に更新');
  });

  test('英语和日语四种订阅周期覆盖单数与复数', () {
    final cases =
        <
          ({
            SubscriptionCycleUnit unit,
            String englishOne,
            String englishTwo,
            String japaneseOne,
            String japaneseTwo,
          })
        >[
          (
            unit: SubscriptionCycleUnit.day,
            englishOne: 'Every day',
            englishTwo: 'Every 2 days',
            japaneseOne: '毎日',
            japaneseTwo: '2日ごと',
          ),
          (
            unit: SubscriptionCycleUnit.week,
            englishOne: 'Every week',
            englishTwo: 'Every 2 weeks',
            japaneseOne: '毎週',
            japaneseTwo: '2週間ごと',
          ),
          (
            unit: SubscriptionCycleUnit.month,
            englishOne: 'Every month',
            englishTwo: 'Every 2 months',
            japaneseOne: '毎月',
            japaneseTwo: '2か月ごと',
          ),
          (
            unit: SubscriptionCycleUnit.year,
            englishOne: 'Every year',
            englishTwo: 'Every 2 years',
            japaneseOne: '毎年',
            japaneseTwo: '2年ごと',
          ),
        ];

    for (final testCase in cases) {
      expect(
        localizedSubscriptionCycle(CardockLanguage.english, testCase.unit, 1),
        testCase.englishOne,
      );
      expect(
        localizedSubscriptionCycle(CardockLanguage.english, testCase.unit, 2),
        testCase.englishTwo,
      );
      expect(
        localizedSubscriptionCycle(CardockLanguage.japanese, testCase.unit, 1),
        testCase.japaneseOne,
      );
      expect(
        localizedSubscriptionCycle(CardockLanguage.japanese, testCase.unit, 2),
        testCase.japaneseTwo,
      );
    }
  });

  test('日期 helper 覆盖年末和闰日且不受时分秒影响', () {
    final yearEnd = DateTime(2026, 12, 31, 23, 59, 59);
    final leapDay = DateTime(2028, 2, 29, 12, 30);

    expect(
      localizedRecordDate(CardockLanguage.english, yearEnd),
      'Dec 31, 2026',
    );
    expect(
      localizedRecordDate(CardockLanguage.english, leapDay),
      'Feb 29, 2028',
    );
    expect(
      localizedRecordDate(CardockLanguage.simplifiedChinese, leapDay),
      '2028年2月29日',
    );
    expect(
      localizedRecordDate(CardockLanguage.japanese, yearEnd),
      '2026年12月31日',
    );
    expect(
      localizedRecordDate(CardockLanguage.japanese, leapDay),
      '2028年2月29日',
    );
    expect(localizedMonthDay(CardockLanguage.english, leapDay), 'Feb 29');
    expect(localizedMonthDay(CardockLanguage.japanese, leapDay), '2月29日');
  });

  test('日语订阅状态和单周期用语符合实际语法', () {
    expect(
      localizedSubscriptionStatus(
        CardockLanguage.japanese,
        SubscriptionStatus.cancelled,
      ),
      '解約済み',
    );
    expect(
      localizedSubscriptionCycle(
        CardockLanguage.japanese,
        SubscriptionCycleUnit.day,
        1,
      ),
      '毎日',
    );
    expect(
      localizedSubscriptionCycle(
        CardockLanguage.japanese,
        SubscriptionCycleUnit.week,
        1,
      ),
      '毎週',
    );
    expect(
      localizedSubscriptionCycle(
        CardockLanguage.japanese,
        SubscriptionCycleUnit.month,
        1,
      ),
      '毎月',
    );
    expect(
      localizedSubscriptionCycle(
        CardockLanguage.japanese,
        SubscriptionCycleUnit.year,
        1,
      ),
      '毎年',
    );
    expect(
      localizedSubscriptionCycle(
        CardockLanguage.japanese,
        SubscriptionCycleUnit.month,
        3,
      ),
      '3か月ごと',
    );
  });

  test('日期、数量与 CNY 汇总标题按三种语言显示', () {
    final date = DateTime(2026, 1, 5);
    expect(localizedRecordDate(CardockLanguage.english, date), 'Jan 5, 2026');
    expect(localizedRecordDate(CardockLanguage.japanese, date), '2026年1月5日');
    expect(localizedAccountCount(CardockLanguage.simplifiedChinese, 1), '1个账号');
    expect(
      localizedSubscriptionCount(CardockLanguage.simplifiedChinese, 0),
      '0个订阅',
    );
    expect(
      localizedSubscriptionItemCount(CardockLanguage.simplifiedChinese, 1),
      '1项订阅',
    );
    expect(localizedAccountCount(CardockLanguage.english, 1), '1 account');
    expect(localizedAccountCount(CardockLanguage.english, 2), '2 accounts');
    expect(
      localizedSubscriptionCount(CardockLanguage.english, 1),
      '1 subscription',
    );
    expect(
      localizedSubscriptionCount(CardockLanguage.english, 2),
      '2 subscriptions',
    );
    expect(
      localizedSubscriptionItemCount(CardockLanguage.english, 1),
      '1 subscription',
    );
    expect(
      localizedSubscriptionCount(CardockLanguage.japanese, 2),
      '2件のサブスクリプション',
    );
    expect(
      const AppLocalizations(
        Locale('zh', 'CN'),
      ).translate('订阅统计 · 共{countLabel}', <String, Object?>{
        'countLabel': localizedSubscriptionCount(
          CardockLanguage.simplifiedChinese,
          1,
        ),
      }),
      '订阅统计 · 共1个订阅',
    );
    expect(
      const AppLocalizations(Locale('en')).translate(
        '订阅统计 · 共{countLabel}',
        <String, Object?>{
          'countLabel': localizedSubscriptionCount(CardockLanguage.english, 1),
        },
      ),
      'Subscription summary · 1 subscription',
    );
    expect(
      const AppLocalizations(Locale('ja')).translate(
        '订阅统计 · 共{countLabel}',
        <String, Object?>{
          'countLabel': localizedSubscriptionCount(CardockLanguage.japanese, 1),
        },
      ),
      'サブスクリプション概要 · 1件のサブスクリプション',
    );
    expect(recordsEnglishTranslations['本月订阅续费总额'], contains('CNY'));
    expect(recordsJapaneseTranslations['本月订阅续费总额'], contains('CNY'));
  });

  test('恢复问题只按稳定 ID 本地化，不改写 ID 或持久化枚举值', () {
    const questionId = 'childhood_city';
    expect(
      localizedVaultRecoveryQuestion(CardockLanguage.english, questionId),
      'Which city did you live in the longest as a child?',
    );
    expect(questionId, 'childhood_city');

    final record = SubscriptionRecord.fromDraft(
      id: 'subscription-1',
      draft: SubscriptionDraft(
        accountId: null,
        details: SubscriptionDetailsDraft(
          serviceName: '用户服务',
          firstSubscribedOn: DateTime(2026, 1, 1),
          nextRenewalOn: DateTime(2026, 4, 1),
          cycleCount: 3,
          cycleUnit: SubscriptionCycleUnit.month,
          status: SubscriptionStatus.cancelled,
        ),
      ),
    );
    final payload = record.toEncryptedPayloadJson();
    expect(payload['cycleCount'], 3);
    expect(payload['cycleUnit'], 'month');
    expect(payload['status'], 'cancelled');
    expect(payload['nextRenewalOn'], '2026-04-01');
  });

  testWidgets('平台名即使等于 UI key 也保持用户原文', (tester) async {
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: '首页', loginAccount: '已取消'),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: AccountRecordCard(
            account: account,
            subscriptions: const <SubscriptionRecord>[],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsWidgets);
    expect(find.text('Home'), findsNothing);
  });
}
