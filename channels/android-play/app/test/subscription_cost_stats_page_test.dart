import 'package:account_subscription_manager/features/subscriptions/domain/subscription_expense_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscription_cost_stats_page.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:account_subscription_manager/l10n/translations_records.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('en'),
    const Locale('ja'),
  ]) {
    testWidgets('日期无法衔接时显式列出未计入账期且不修改原订阅 $locale', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final account = AccountRecord.fromDraft(
        id: 'gap-account',
        draft: AccountDraft(
          platformName: 'Gap platform',
          category: 'Work',
          loginAccount: 'gap-account@example.invalid',
        ),
      );
      final subscription = SubscriptionRecord.fromDraft(
        id: 'gap-subscription',
        draft: SubscriptionDraft(
          accountId: account.id,
          details: SubscriptionDetailsDraft(
            serviceName: 'Gap subscription',
            planName: 'Monthly plan',
            amount: '55',
            currency: 'CNY',
            firstSubscribedOn: DateTime(2026, 1, 10),
            nextRenewalOn: DateTime(2026, 9, 11),
          ),
        ),
      );
      final original = subscription.toEncryptedPayloadJson();
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SubscriptionCostStatsPage(
            accounts: [account],
            subscriptions: [subscription],
            expenses: const [],
            today: DateTime(2026, 9, 3),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final noticeTitle = find.byKey(
        const ValueKey('cost-uncounted-periods-title'),
      );
      await tester.scrollUntilVisible(
        noticeTitle,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(noticeTitle),
        alignment: 0.25,
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(tester.element(noticeTitle));
      final warning = l10n.translate('部分账期暂未计入');
      expect(find.text(warning), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cost-basis-confirmed')),
          matching: find.text(warning),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cost-basis-futureEstimate')),
          matching: find.text(warning),
        ),
        findsNothing,
      );
      expect(
        find.text(l10n.translate('保存的日期无法按当前周期衔接，需核对原记录；总额暂不含这些账期。')),
        findsOneWidget,
      );
      await tester.tap(noticeTitle);
      await tester.pumpAndSettle();
      final gap = find.byKey(
        const ValueKey('cost-gap-gap-subscription-2026-02-10'),
      );
      expect(gap, findsOneWidget);
      expect(
        find.descendant(of: gap, matching: find.text('Gap subscription')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: gap,
          matching: find.textContaining('gap-account@example.invalid'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: gap,
          matching: find.text(
            l10n.translate('未计入区间：{start} 至 {end}', {
              'start': localizedRecordDate(
                l10n.language,
                DateTime(2026, 2, 10),
              ),
              'end': localizedRecordDate(l10n.language, DateTime(2026, 9, 2)),
            }),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cost-total-confirmed-currency-CNY')),
          matching: find.text('55'),
        ),
        findsOneWidget,
      );
      expect(subscription.toEncryptedPayloadJson(), original);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('en'),
    const Locale('ja'),
  ]) {
    testWidgets('汇总与月分类每币种独立显示，长金额和周期明细无裁切 $locale', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final account = AccountRecord.fromDraft(
        id: 'layout-account',
        draft: AccountDraft(
          platformName: 'Layout service',
          category: 'Work',
          loginAccount: 'layout-account@example.invalid',
        ),
      );
      const longAmount = '987654321098.4321';
      final subscriptions = [
        for (final (currency, amount, count, unit, plan) in [
          ('CNY', longAmount, 1, SubscriptionCycleUnit.month, 'Monthly plan'),
          ('USD', '89.5', 3, SubscriptionCycleUnit.month, 'Quarterly plan'),
          ('JPY', '12000', 1, SubscriptionCycleUnit.year, 'Annual plan'),
        ])
          SubscriptionRecord.fromDraft(
            id: 'layout-$currency',
            draft: SubscriptionDraft(
              accountId: account.id,
              details: SubscriptionDetailsDraft(
                serviceName: 'Layout $currency',
                planName: plan,
                amount: amount,
                currency: currency,
                cycleCount: count,
                cycleUnit: unit,
                expenseCategory: 'Layout category',
                firstSubscribedOn: DateTime(2026, 8, 10),
                nextRenewalOn: DateTime(2026, 10, 10),
              ),
            ),
          ),
      ];
      final expenses = [
        for (final subscription in subscriptions)
          SubscriptionExpenseRecord.fromDraft(
            id: 'expense-${subscription.id}',
            accountLabel:
                'Work · Layout service · layout-account@example.invalid',
            draft: SubscriptionExpenseDraft(
              subscriptionId: subscription.id,
              accountId: account.id,
              serviceName: subscription.serviceName,
              occurredOn: DateTime(2026, 8, 10),
              scheduledRenewalOn: DateTime(2026, 8, 10),
              amount: subscription.amount!,
              currency: subscription.currency,
              kind: SubscriptionExpenseKind.payment,
              expenseCategory: 'Layout category',
            ),
            recordedAtUtc: DateTime.utc(2026, 8, 10),
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SubscriptionCostStatsPage(
            accounts: [account],
            subscriptions: subscriptions,
            expenses: expenses,
            today: DateTime(2026, 9, 3),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pageScroll = find.byType(Scrollable).first;

      Future<void> showKey(String key) async {
        final target = find.byKey(ValueKey(key));
        if (target.evaluate().isEmpty) {
          tester.state<ScrollableState>(pageScroll).position.jumpTo(0);
          await tester.pumpAndSettle();
          if (target.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              target,
              250,
              scrollable: pageScroll,
              maxScrolls: 100,
            );
            await tester.pumpAndSettle();
          }
        }
        await Scrollable.ensureVisible(tester.element(target), alignment: 0.25);
        await tester.pumpAndSettle();
      }

      Future<void> tapKey(String key) async {
        await showKey(key);
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
      }

      void expectSeparateCurrencyRows(String prefix) {
        final rectangles = <Rect>[];
        for (final currency in ['CNY', 'JPY', 'USD']) {
          final row = find.byKey(ValueKey('$prefix-currency-$currency'));
          expect(row, findsOneWidget);
          expect(
            find.descendant(of: row, matching: find.text(currency)),
            findsOneWidget,
          );
          final rect = tester.getRect(row);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
          rectangles.add(rect);
        }
        for (var index = 1; index < rectangles.length; index += 1) {
          expect(
            rectangles[index].top,
            greaterThanOrEqualTo(rectangles[index - 1].bottom),
          );
        }
        expect(tester.takeException(), isNull);
      }

      await showKey('cost-basis-title-confirmed');
      expectSeparateCurrencyRows('cost-total-confirmed');
      final amountText = find.descendant(
        of: find.byKey(const ValueKey('cost-total-confirmed-currency-CNY')),
        matching: find.byType(Text),
      );
      for (final text in tester.widgetList<Text>(amountText)) {
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        expect(text.maxLines, isNull);
      }
      await showKey('cost-basis-title-futureEstimate');
      expectSeparateCurrencyRows('cost-total-futureEstimate');

      const august = 'cost-group-confirmed-month-2026-08';
      await tapKey('$august-title');
      expectSeparateCurrencyRows('$august-total');
      final group = find.byKey(const ValueKey(august));
      expect(
        find.descendant(
          of: group,
          matching: find.textContaining('layout-account@example.invalid'),
        ),
        findsNWidgets(3),
      );
      for (final plan in ['Monthly plan', 'Quarterly plan', 'Annual plan']) {
        expect(
          find.descendant(of: group, matching: find.text(plan)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: group, matching: find.text(longAmount)),
        findsWidgets,
      );
      final l10n = AppLocalizations.of(tester.element(group));
      for (final (unit, count) in [
        (SubscriptionCycleUnit.month, 1),
        (SubscriptionCycleUnit.month, 3),
        (SubscriptionCycleUnit.year, 1),
      ]) {
        final cycle = localizedSubscriptionCycle(l10n.language, unit, count);
        expect(
          find.descendant(
            of: group,
            matching: find.text(
              l10n.translate('计费周期：{cycle}', {'cycle': cycle}),
            ),
          ),
          findsOneWidget,
        );
      }
      await tapKey('cost-breakdown-category');
      const category = 'cost-group-confirmed-category-Layout category';
      await showKey('$category-title');
      expectSeparateCurrencyRows('$category-total');

      await tapKey('cost-basis-title-futureEstimate');
      const futureCategory =
          'cost-group-futureEstimate-category-Layout category';
      await showKey('$futureCategory-title');
      expectSeparateCurrencyRows('$futureCategory-total');
      await tapKey('cost-breakdown-month');
      const october = 'cost-group-futureEstimate-month-2026-10';
      await tapKey('$october-title');
      expectSeparateCurrencyRows('$october-total');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey(october)),
          matching: find.text('Quarterly plan'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('en'),
    const Locale('ja'),
  ]) {
    testWidgets('同名服务按分类与账号选择，切换账号清理关联；小屏大字 $locale', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final accounts = [
        for (var i = 1; i <= 2; i++)
          AccountRecord.fromDraft(
            id: 'a$i',
            draft: AccountDraft(
              platformName: 'Same platform',
              category: 'Work',
              loginAccount: 'user$i@example.invalid',
            ),
          ),
      ];
      SubscriptionRecord subscription(
        String id,
        String accountId,
        String plan,
        String amount,
      ) => SubscriptionRecord.fromDraft(
        id: id,
        draft: SubscriptionDraft(
          accountId: accountId,
          details: SubscriptionDetailsDraft(
            serviceName: 'Same service',
            planName: plan,
            amount: amount,
            currency: 'CNY',
            firstSubscribedOn: DateTime(2026, 9, 1),
            nextRenewalOn: DateTime(2026, 10, 1),
          ),
        ),
      );
      SubscriptionExpenseDraft? submitted;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SubscriptionCostStatsPage(
            subscriptions: [
              subscription('s1', 'a1', 'Basic', '10'),
              subscription('s2', 'a1', 'Pro', '20'),
              subscription('s3', 'a2', 'Other', '30'),
            ],
            expenses: const [],
            accounts: accounts,
            today: DateTime(2026, 9, 3),
            onAddExpense: (draft) async {
              submitted = draft;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tapKey(String key) async {
        final target = find.byKey(ValueKey(key));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await tapKey('add-subscription-expense');
      await tapKey('expense-account-field');
      await tapKey('subscription-account-category-category:work');
      expect(find.text('user1@example.invalid'), findsOneWidget);
      expect(find.text('user2@example.invalid'), findsOneWidget);
      await tapKey('subscription-account-option-a2');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('expense-amount')))
            .controller!
            .text,
        '30',
      );
      await tapKey('expense-account-field');
      await tapKey('subscription-account-category-category:work');
      await tapKey('subscription-account-option-a1');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('expense-amount')))
            .controller!
            .text,
        isEmpty,
      );
      await tapKey('expense-subscription-field');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('expense-pick-s1')),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expense-pick-s1')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('expense-pick-s2')),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expense-pick-s2')), findsOneWidget);
      expect(find.byKey(const ValueKey('expense-pick-s3')), findsNothing);
      expect(find.textContaining('Pro'), findsWidgets);
      await tapKey('expense-pick-s2');
      await tester.ensureVisible(find.byKey(const ValueKey('expense-amount')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('expense-amount')), '5');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tapKey('save-expense');
      expect(submitted!.accountId, 'a1');
      expect(submitted!.subscriptionId, 's2');
      expect(submitted!.amount, '5');
      expect(submitted!.kind, SubscriptionExpenseKind.refund);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('新增确认费用成功后当前统计页立即从0条刷新为1条', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final expenses = <SubscriptionExpenseRecord>[];
    SubscriptionExpenseDraft? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: SubscriptionCostStatsPage(
          subscriptions: const <SubscriptionRecord>[],
          expenses: expenses,
          today: DateTime(2026, 6, 15),
          onAddExpense: (draft) async {
            submitted = draft;
            expenses.add(
              SubscriptionExpenseRecord.fromDraft(
                id: 'expense-1',
                draft: draft,
                recordedAtUtc: DateTime.utc(2026, 6, 15, 8),
              ),
            );
            return true;
          },
        ),
      ),
    );

    expect(find.text('1条记录'), findsNothing);
    expect(find.text('0条记录'), findsNWidgets(2));

    await tester.tap(
      find.byKey(const ValueKey<String>('add-subscription-expense')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('expense-service-name')),
      '本机测试订阅',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('expense-amount')),
      '12.5',
    );
    final saveButton = find.byKey(const ValueKey<String>('save-expense'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(submitted?.serviceName, '本机测试订阅');
    expect(submitted?.amount, '12.5');
    expect(submitted?.currency, 'CNY');
    expect(expenses, hasLength(1));
    expect(find.text('1条记录'), findsOneWidget);
    expect(find.text('0条记录'), findsOneWidget);
    expect(submitted!.kind, SubscriptionExpenseKind.refund);
    expect(find.text('-12.5'), findsWidgets);
    expect(find.text('旧记录估算'), findsNothing);
  });
}
