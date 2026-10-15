import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/theme/cardock_tokens.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_expense_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

const _testMasterPassword = 'TEST-ONLY-MASTER-1234';

void main() {
  testWidgets('首页把本月多币种金额折算为人民币并披露离线汇率口径', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final today = subscriptionDateOnly(DateTime.now());
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: '测试平台'),
    );
    final subscriptions = <SubscriptionRecord>[
      _subscription('subscription-1', today, amount: '10', currency: 'CNY'),
      _subscription('subscription-2', today, amount: '2', currency: 'USD'),
      _subscription('subscription-3', today, amount: '3', currency: 'TWD'),
      _subscription('subscription-4', today, currency: 'EUR'),
      _subscription('subscription-5', today, amount: '4', currency: 'CUSTOM'),
    ];
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
      snapshot: VaultSnapshot(
        nextAccountId: 2,
        accounts: [account],
        nextSubscriptionId: 6,
        subscriptions: subscriptions,
        nextExpenseId: 6,
        subscriptionExpenses: [
          for (final sub in subscriptions.where((s) => s.amount != null))
            SubscriptionExpenseRecord.fromDraft(
              id: 'expense-${subscriptions.indexOf(sub) + 1}',
              draft: SubscriptionExpenseDraft(
                subscriptionId: sub.id,
                serviceName: sub.serviceName,
                occurredOn: today,
                amount: sub.amount!,
                currency: sub.currency,
                kind: SubscriptionExpenseKind.payment,
              ),
            ),
        ],
      ),
    );

    await tester.pumpWidget(AccountSubscriptionApp(vaultStore: store));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('unlock-master-password-field')),
      _testMasterPassword,
    );
    await tester.tap(find.byKey(const ValueKey<String>('unlock-vault-button')));
    await tester.pumpAndSettle();

    final thisMonthMetric = find.byKey(
      const ValueKey<String>('home-metric-auto-renew-this-month'),
    );
    final currencySymbol = find.descendant(
      of: thisMonthMetric,
      matching: find.text('¥'),
    );
    final amountValue = find.descendant(
      of: thisMonthMetric,
      matching: find.text('24.44'),
    );
    expect(currencySymbol, findsOneWidget);
    expect(amountValue, findsOneWidget);
    final symbolText = tester.widget<Text>(currencySymbol);
    final amountText = tester.widget<Text>(amountValue);
    final palette = Theme.of(
      tester.element(thisMonthMetric),
    ).extension<CardockThemeExtension>()!.palette;
    expect(
      symbolText.style!.color,
      palette.gradientContent.withValues(alpha: 0.74),
    );
    expect(amountText.style!.color, palette.gradientContent);
    expect(
      symbolText.style!.fontSize! / amountText.style!.fontSize!,
      closeTo(CardockTypography.currencySymbolScale, 0.01),
    );
    expect(find.textContaining('2026上半年116个官方公布日算术平均'), findsOneWidget);
    expect(find.textContaining('TWD为114个重合日的官方交叉参考'), findsOneWidget);
    expect(find.textContaining('1项未计入'), findsOneWidget);
  });

  testWidgets('已记录续费的卡片同时保留在本月合计并进入次月合计', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final today = subscriptionDateOnly(DateTime.now());
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: '测试平台'),
    );
    final renewed = _subscription(
      'subscription-renewed',
      today,
      amount: '10',
      currency: 'CNY',
    ).markRenewed(recordedOn: today);
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
      snapshot: VaultSnapshot(
        nextAccountId: 2,
        accounts: [account],
        nextSubscriptionId: 2,
        subscriptions: [renewed],
        nextExpenseId: 2,
        subscriptionExpenses: [
          SubscriptionExpenseRecord.fromDraft(
            id: 'expense-1',
            draft: SubscriptionExpenseDraft(
              subscriptionId: renewed.id,
              serviceName: renewed.serviceName,
              occurredOn: today,
              amount: '10',
              currency: 'CNY',
              kind: SubscriptionExpenseKind.payment,
            ),
          ),
        ],
      ),
    );

    await tester.pumpWidget(AccountSubscriptionApp(vaultStore: store));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('unlock-master-password-field')),
      _testMasterPassword,
    );
    await tester.tap(find.byKey(const ValueKey<String>('unlock-vault-button')));
    await tester.pumpAndSettle();

    expect(find.text('本月订阅续费总额'), findsOneWidget);
    expect(find.text('次月续费总额'), findsOneWidget);
    // A renewal date can also show day 10; assert each amount in its own metric.
    for (final metricKey in const [
      'home-metric-auto-renew-this-month',
      'home-metric-renewals-next-month',
    ]) {
      final metric = find.byKey(ValueKey<String>(metricKey));
      expect(metric, findsOneWidget);
      expect(
        find.descendant(of: metric, matching: find.text('10')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: metric, matching: find.text('10.00')),
        findsNothing,
      );
    }
  });
}

SubscriptionRecord _subscription(
  String id,
  DateTime renewalDate, {
  String? amount,
  required String currency,
}) => SubscriptionRecord.fromDraft(
  id: id,
  draft: SubscriptionDraft(
    accountId: 'account-1',
    details: SubscriptionDetailsDraft(
      serviceName: '测试订阅$id',
      amount: amount,
      currency: currency,
      firstSubscribedOn: renewalDate.subtract(const Duration(days: 1)),
      nextRenewalOn: renewalDate,
    ),
  ),
);
