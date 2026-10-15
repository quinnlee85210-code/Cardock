import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/home/presentation/home_page.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_cost_summary.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscription_cost_stats_page.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscription_editor_page.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscription_form_fields.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscriptions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

// Two controls for the Play 84 report dated 2026-09-23. No device/user data.
void main() {
  for (final amountEntered in [true, false]) {
    testWidgets(
      amountEntered
          ? 'Play84 USD49.90 amount survives editor, save, reload, list, home and statistics'
          : 'Play84 numeric plan with empty amount reproduces report without losing money',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final today = DateTime(2026, 9, 23);
        final account = AccountRecord.fromDraft(
          id: 'account-1',
          draft: AccountDraft(platformName: 'Netflix'),
        );
        final initial = SubscriptionFormController(today: today);
        final initialFields = initial.exportEditorFields();
        initial.dispose();
        SubscriptionDraft? submitted;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  submitted = await Navigator.of(context)
                      .push<SubscriptionDraft>(
                        MaterialPageRoute(
                          builder: (_) => SubscriptionEditorPage(
                            accounts: [account],
                            initialAccountId: account.id,
                            initialDraft: {
                              'accountId': account.id,
                              'subscription': initialFields,
                            },
                          ),
                        ),
                      );
                },
                child: const Text('Open editor'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open editor'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('subscription-service-name')),
          'Premium_Plan',
        );
        await tester.enterText(
          find.byKey(const ValueKey('subscription-plan-name')),
          amountEntered ? 'Annual' : '49.90',
        );
        if (amountEntered) {
          await tester.enterText(
            find.byKey(const ValueKey('subscription-amount')),
            '49.90',
          );
        }
        await tester.tap(find.byKey(const ValueKey('subscription-currency')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('USD').last);
        await tester.pumpAndSettle();
        final cycle = find.byKey(const ValueKey('subscription-cycle-preset'));
        await tester.ensureVisible(cycle);
        await tester.tap(cycle);
        await tester.pumpAndSettle();
        await tester.tap(find.text('每年').last);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('save-subscription-button')),
        );
        await tester.pumpAndSettle();
        expect(submitted, isNotNull);
        expect(submitted!.details.amount, amountEntered ? '49.90' : null);
        expect(submitted!.details.planName, amountEntered ? 'Annual' : '49.90');
        expect(submitted!.details.currency, 'USD');
        expect(submitted!.details.nextRenewalOn, DateTime(2027, 9, 23));

        const password = 'TEST-ONLY-REPORT-1234';
        final store = FakeVaultStore(
          configured: true,
          acceptedPassword: password,
          snapshot: VaultSnapshot(accounts: [account], nextAccountId: 2),
        );
        final state = AppState(vaultStore: store, now: () => today);
        addTearDown(state.dispose);
        await state.initialize();
        expect(await state.unlock(password), VaultActionResult.success);
        expect(await state.addSubscription(submitted!), isTrue);
        final reloaded = VaultSnapshot.fromEncryptedPayloadJson(
          store.snapshot.toEncryptedPayloadJson(),
        );
        final sub = reloaded.subscriptions.single;
        expect(sub.amount, amountEntered ? '49.90' : null);
        expect(sub.planName, amountEntered ? 'Annual' : '49.90');
        expect(sub.currency, 'USD');
        final editing = SubscriptionFormController(initial: sub.details);
        expect(editing.amountController.text, amountEntered ? '49.90' : '');
        expect(
          editing.planNameController.text,
          amountEntered ? 'Annual' : '49.90',
        );
        editing.dispose();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SubscriptionsPage(
                accounts: reloaded.accounts,
                subscriptions: reloaded.subscriptions,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(amountEntered ? 'USD 49.90' : '金额未填写'), findsWidgets);
        expect(find.text(amountEntered ? '金额未填写' : 'USD 49.90'), findsNothing);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomePage(
                accounts: reloaded.accounts,
                subscriptions: reloaded.subscriptions,
                recentAccounts: const [],
                autoLockSeconds: 60,
                onOpenAccount: (_) {},
                onOpenAccounts: () {},
                onOpenSubscriptions: (_) {},
                onOpenSubscription: (_) {},
                onSearch: () {},
                onLock: () {},
                onAddAccount: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final ticket = find.byKey(
          ValueKey('home-upcoming-subscription-${sub.id}'),
        );
        await tester.ensureVisible(ticket);
        expect(
          find.descendant(
            of: ticket,
            matching: find.text(amountEntered ? 'USD 49.90' : '金额待补充'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: ticket,
            matching: find.text(amountEntered ? 'Annual' : '49.90'),
          ),
          findsOneWidget,
        );

        final analysis = SubscriptionCostAnalysis.build(
          subscriptions: reloaded.subscriptions,
          expenses: reloaded.subscriptionExpenses,
          range: SubscriptionCostRange(
            startMonth: today,
            endMonth: DateTime(2027, 9),
          ),
          today: today,
        );
        for (final basis in SubscriptionCostBasis.values) {
          final totals = analysis.currencyTotals(basis);
          if (amountEntered) {
            expect(totals.single.currency, 'USD');
            expect(totals.single.scaledAmount, BigInt.from(499000));
            expect(analysis.cnyEstimate(basis).missingAmountCount, 0);
          } else {
            expect(totals, isEmpty);
            expect(
              analysis.cnyEstimate(basis).missingAmountCount,
              greaterThan(0),
            );
          }
        }
        await tester.pumpWidget(
          MaterialApp(
            home: SubscriptionCostStatsPage(
              subscriptions: reloaded.subscriptions,
              expenses: reloaded.subscriptionExpenses,
              accounts: reloaded.accounts,
              today: today,
            ),
          ),
        );
        await tester.pumpAndSettle();
        // This page defaults to 2026: the future 2027 renewal is outside it.
        // Scope the assertion to the confirmed USD row, not the empty future card.
        final usdTotal = find.byKey(
          const ValueKey('cost-total-confirmed-currency-USD'),
        );
        expect(usdTotal, amountEntered ? findsOneWidget : findsNothing);
        if (amountEntered) {
          expect(
            find.descendant(of: usdTotal, matching: find.text('49.9')),
            findsOneWidget,
          );
        } else {
          expect(find.text('暂无可合计的原币金额'), findsWidgets);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
