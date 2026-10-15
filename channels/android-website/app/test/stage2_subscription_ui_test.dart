import 'package:account_subscription_manager/features/subscriptions/presentation/subscription_finance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscription_editor_page.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscription_insights_page.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscription_management_panel.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscriptions_page.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/payment_methods_page.dart';
import 'support/fake_vault_store.dart';

const testPassword = 'TEST-ONLY-STAGE2-Ui123!';
SubscriptionRecord fixture(String id, {bool trial = false}) =>
    SubscriptionRecord.fromDraft(
      id: id,
      draft: SubscriptionDraft(
        accountId: null,
        details: SubscriptionDetailsDraft(
          serviceName: trial
              ? '試用中の長いサービス名 · Long trial subscription'
              : '示例订阅服务 · Example service',
          planName: 'Premium annual plan / 年間プラン',
          firstSubscribedOn: DateTime(2026, 1, 1),
          nextRenewalOn: DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day + 5,
          ),
          amount: '120.0001',
          currency: 'USD',
          management: SubscriptionManagement(
            trial: trial
                ? SubscriptionTrial(
                    startsOn: DateTime.now(),
                    endsOn: DateTime(
                      DateTime.now().year,
                      DateTime.now().month,
                      DateTime.now().day + 4,
                    ),
                    formalAmount: '120',
                    expectedAutoConvert: true,
                    firstPaidOn: DateTime(
                      DateTime.now().year,
                      DateTime.now().month,
                      DateTime.now().day + 5,
                    ),
                  )
                : null,
            reminderRules: [
              SubscriptionReminderRule(
                event: SubscriptionReminderEvent.renewal,
                daysBefore: [3, 0],
              ),
              SubscriptionReminderRule(
                event: SubscriptionReminderEvent.trialEnd,
                daysBefore: [3, 1, 0],
              ),
            ],
            cancellation: SubscriptionCancellationInfo(
              location: '设置 > 管理订阅',
              steps: '打开设置，找到会员管理。\n確認後、解約ボタンを押してください。',
              url: 'https://example.invalid/cancel',
            ),
          ),
        ),
      ),
    );

Future<AppState> stateForTest() async {
  final store = FakeVaultStore(
    configured: true,
    acceptedPassword: testPassword,
    snapshot: VaultSnapshot(
      nextAccountId: 1,
      accounts: [],
      nextSubscriptionId: 3,
      subscriptions: [
        fixture('subscription-1'),
        fixture('subscription-2', trial: true),
      ],
    ),
  );
  final state = AppState(vaultStore: store);
  await state.initialize();
  await state.unlock(testPassword);
  return state;
}

Widget host(
  Widget page, {
  Locale locale = const Locale('zh', 'CN'),
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: page,
);

void main() {
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('en'),
    const Locale('ja'),
  ]) {
    testWidgets(
      'shared finance and icon toolbar ${locale.languageCode} at 320px 200%',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = await stateForTest();
        addTearDown(state.dispose);
        var costs = 0, attention = 0;
        await tester.pumpWidget(
          host(
            Scaffold(
              body: SubscriptionsPage(
                accounts: state.accounts,
                subscriptions: state.subscriptions,
                onOpenCostStats: () => costs++,
                onOpenAttention: () => attention++,
                onSortModeChanged: (_) {},
              ),
            ),
            locale: locale,
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TextButton), findsNothing);
        final expenseButton = find.byKey(
          const ValueKey('open-subscription-cost-stats'),
        );
        final attentionButton = find.byKey(
          const ValueKey('open-subscription-attention'),
        );
        final sort = find.byKey(const ValueKey('subscription-sort-mode-menu'));
        expect(
          tester.getCenter(expenseButton).dy,
          tester.getCenter(attentionButton).dy,
        );
        expect(
          tester.getCenter(attentionButton).dx,
          lessThan(tester.getCenter(sort).dx),
        );
        expect(
          tester.getTopLeft(attentionButton).dy,
          greaterThan(
            tester
                .getBottomLeft(
                  find.byKey(const ValueKey('subscription-search')),
                )
                .dy,
          ),
        );
        await tester.tap(expenseButton);
        await tester.tap(attentionButton);
        expect(costs, 1);
        expect(attention, 1);
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.byKey(const ValueKey('subscription-search')),
          'Example service',
        );
        await tester.pumpAndSettle();
        expect(expenseButton, findsOneWidget);
        expect(attentionButton, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          host(
            SubscriptionFinancePage(state: state, onOpenSubscription: (_) {}),
            locale: locale,
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsOneWidget);
        expect(
          find.byKey(const ValueKey('subscription-cost-stats-page')),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('finance-insights-tab')),
        );
        await tester.tap(find.byKey(const ValueKey('finance-insights-tab')));
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('finance-costs-tab')),
        );
        await tester.tap(find.byKey(const ValueKey('finance-costs-tab')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('add-subscription-expense')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('en'),
    const Locale('ja'),
  ]) {
    for (final dark in [false, true]) {
      testWidgets(
        'new screens ${locale.languageCode} ${dark ? 'dark' : 'light'} 320px 200%',
        (tester) async {
          tester.view.physicalSize = const Size(320, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final originalError = FlutterError.onError;
          FlutterError.onError = (details) {
            FlutterError.dumpErrorToConsole(details);
            originalError?.call(details);
          };
          addTearDown(() => FlutterError.onError = originalError);
          final state = await stateForTest();
          addTearDown(state.dispose);
          Future<void> show(Widget page) async {
            await tester.pumpWidget(
              host(
                page,
                locale: locale,
                brightness: dark ? Brightness.dark : Brightness.light,
                scale: 2,
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }

          await show(
            SubscriptionInsightsPage(state: state, onOpenSubscription: (_) {}),
          );
          await tester.drag(find.byType(ListView).first, const Offset(0, -580));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await show(
            Scaffold(
              body: SubscriptionsPage(
                accounts: state.accounts,
                subscriptions: state.subscriptions,
              ),
            ),
          );
          await tester.enterText(
            find.byKey(const ValueKey('subscription-search')),
            'Example service',
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(
            find.byKey(const ValueKey('subscription-search-filters')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await show(PaymentMethodsPage(state: state));
          await show(
            SubscriptionEditorPage(
              accounts: [],
              existing: state.subscriptions.last,
            ),
          );
          await show(
            Scaffold(
              body: SingleChildScrollView(
                child: SubscriptionManagementPanel(
                  state: state,
                  subscription: state.subscriptions.last,
                ),
              ),
            ),
          );
          await show(SubscriptionAttentionPage(state: state, onOpen: (_) {}));
        },
      );
    }
  }
  testWidgets('search clear restores full set without saving', (tester) async {
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: testPassword,
      snapshot: VaultSnapshot(
        nextAccountId: 1,
        accounts: [],
        nextSubscriptionId: 3,
        subscriptions: [
          fixture('subscription-1'),
          fixture('subscription-2', trial: true),
        ],
      ),
    );
    final state = AppState(vaultStore: store);
    await state.initialize();
    await state.unlock(testPassword);
    addTearDown(state.dispose);
    final before = store.saveCalls;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: SubscriptionsPage(
            accounts: state.accounts,
            subscriptions: state.subscriptions,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('subscription-search')),
      'Example service',
    );
    await tester.pumpAndSettle();
    expect(find.text('匹配 1 条订阅'), findsOneWidget);
    await tester.tap(find.text('清除全部筛选'));
    await tester.pumpAndSettle();
    expect(store.saveCalls, before);
    expect(tester.takeException(), isNull);
  });
  testWidgets('trial conversion unchecked does not record a payment', (
    tester,
  ) async {
    final state = await stateForTest();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      host(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => TrialConversionDialog(
                  state: state,
                  subscription: state.subscriptions.last,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      false,
    );
    await tester.tap(find.text('确认结果'));
    await tester.pumpAndSettle();
    expect(
      state.subscriptions.last.management!.trial!.outcome,
      TrialOutcome.converted,
    );
    expect(state.subscriptionExpenses, isEmpty);
  });
}
