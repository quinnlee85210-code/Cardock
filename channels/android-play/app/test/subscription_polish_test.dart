import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/exchange_rates/semiannual_cny_exchange_rates.dart';
import 'package:account_subscription_manager/core/preferences/record_sort_mode.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_cost_summary.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_expense_record.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscriptions_page.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscription_cost_stats_page.dart';
import 'package:account_subscription_manager/features/home/presentation/home_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_vault_store.dart';

final _day = DateTime(2026, 9, 19);
SubscriptionDraft _draft({
  String amount = '20',
  SubscriptionCycleUnit cycle = SubscriptionCycleUnit.month,
  DateTime? next,
  String? account,
}) => SubscriptionDraft(
  accountId: account,
  details: SubscriptionDetailsDraft(
    serviceName: 'Cloud plan',
    amount: amount,
    currency: 'CNY',
    firstSubscribedOn: DateTime(2026, 8, 19),
    nextRenewalOn: next ?? _day,
    cycleUnit: cycle,
  ),
);
Future<AppState> _state(FakeVaultStore store, {DateTime? now}) async {
  final state = AppState(vaultStore: store, now: () => now ?? _day);
  addTearDown(state.dispose);
  await state.initialize();
  expect(
    await state.createVault('TEST-ONLY-POLISH-1234'),
    VaultActionResult.success,
  );
  await state.addSubscription(_draft());
  return state;
}

SubscriptionCostAnalysis _analysis(AppState state) =>
    SubscriptionCostAnalysis.build(
      subscriptions: state.subscriptions,
      expenses: state.subscriptionExpenseLedger,
      range: SubscriptionCostRange(startMonth: _day, endMonth: _day),
      today: _day,
    );
SubscriptionExpenseDraft _payment(
  SubscriptionRecord sub, {
  String amount = '200',
}) => SubscriptionExpenseDraft(
  subscriptionId: sub.id,
  serviceName: sub.serviceName,
  occurredOn: _day,
  amount: amount,
  currency: 'CNY',
  kind: SubscriptionExpenseKind.payment,
);
void main() {
  test(
    'monthly to annual payment uses payment month and preserves earlier entries',
    () async {
      final state = await _state(FakeVaultStore());
      final id = state.subscriptions.single.id;
      final entry = state.subscriptionExpenses.single.toEncryptedPayloadJson();
      expect(
        await state.updateSubscription(
          subscriptionId: id,
          draft: _draft(amount: '200', cycle: SubscriptionCycleUnit.year),
        ),
        isTrue,
      );
      final annual = state.subscriptions.single;
      expect(
        await state.markSubscriptionRenewed(annual, expense: _payment(annual)),
        isTrue,
      );
      expect(state.subscriptions.single.nextRenewalOn, DateTime(2027, 9, 19));
      expect(state.subscriptionExpenses.first.toEncryptedPayloadJson(), entry);
      expect(
        _analysis(state)
            .currencyTotals(SubscriptionCostBasis.confirmed)
            .single
            .formattedAmount,
        '200',
      );
      // A stale callback cannot renew the updated subscription a second time.
      expect(
        await state.markSubscriptionRenewed(annual, expense: _payment(annual)),
        isFalse,
      );
      expect(state.subscriptionExpenses, hasLength(2));
    },
  );

  test(
    'correction and deletion persist without refilling the deleted renewal',
    () async {
      final store = FakeVaultStore();
      final state = await _state(store);
      final original = state.subscriptions.single;
      await state.markSubscriptionRenewed(
        original,
        expense: _payment(original),
      );
      var line = _analysis(
        state,
      ).forBasis(SubscriptionCostBasis.confirmed).single;
      expect(
        await state.correctSubscriptionCost(
          line,
          _payment(original, amount: '180'),
        ),
        isTrue,
      );
      line = _analysis(state).forBasis(SubscriptionCostBasis.confirmed).single;
      expect(line.amount, '180');
      expect(await state.correctSubscriptionCost(line, null), isTrue);
      expect(
        _analysis(state).forBasis(SubscriptionCostBasis.confirmed),
        isEmpty,
      );
      expect(state.subscriptions.single.nextRenewalOn, DateTime(2026, 10, 19));
      final restored = VaultSnapshot.fromEncryptedPayloadJson(
        store.snapshot.toEncryptedPayloadJson(),
      );
      expect(
        restored.subscriptionExpenses.where((e) => e.isDeleted),
        hasLength(1),
      );
      final rebuilt = SubscriptionCostAnalysis.build(
        subscriptions: restored.subscriptions,
        expenses: restored.subscriptionExpenses,
        range: SubscriptionCostRange(startMonth: _day, endMonth: _day),
        today: _day,
      );
      expect(rebuilt.forBasis(SubscriptionCostBasis.confirmed), isEmpty);
      await state.updateSubscription(
        subscriptionId: original.id,
        draft: _draft(next: DateTime(2026, 10, 19)),
      );
      expect(
        _analysis(state).forBasis(SubscriptionCostBasis.confirmed),
        isEmpty,
      );
    },
  );

  test(
    'inferred past charges can be corrected and deleted without returning',
    () async {
      final now = DateTime(2026, 9, 20);
      final state = await _state(FakeVaultStore(), now: now);
      await state.updateSubscription(
        subscriptionId: state.subscriptions.single.id,
        draft: _draft(next: DateTime(2026, 10, 19)),
      );
      SubscriptionCostAnalysis analyze() => SubscriptionCostAnalysis.build(
        subscriptions: state.subscriptions,
        expenses: state.subscriptionExpenseLedger,
        range: SubscriptionCostRange(startMonth: _day, endMonth: _day),
        today: now,
      );
      final line = analyze().forBasis(SubscriptionCostBasis.confirmed).single;
      expect(line.fromSchedule, isTrue);
      expect(
        await state.correctSubscriptionCost(
          line,
          _payment(state.subscriptions.single, amount: '25'),
        ),
        isTrue,
      );
      final edited = analyze().forBasis(SubscriptionCostBasis.confirmed).single;
      expect(edited.amount, '25');
      expect(edited.expenseId, isNotNull);
      expect(await state.correctSubscriptionCost(edited, null), isTrue);
      expect(analyze().forBasis(SubscriptionCostBasis.confirmed), isEmpty);
      expect(await state.correctSubscriptionCost(line, null), isFalse);
    },
  );

  test(
    'failed correction and locked access retain original ledger and schedule',
    () async {
      final store = FakeVaultStore();
      final state = await _state(store);
      await state.markSubscriptionRenewed(state.subscriptions.single);
      final line = _analysis(
        state,
      ).forBasis(SubscriptionCostBasis.confirmed).single;
      final before = store.snapshot.toEncryptedPayloadJson();
      store.failSaves = true;
      expect(await state.correctSubscriptionCost(line, null), isFalse);
      expect(store.snapshot.toEncryptedPayloadJson(), before);
      expect(state.subscriptionExpenses, hasLength(2));
      store.failSaves = false;
      state.lock();
      expect(await state.correctSubscriptionCost(line, null), isFalse);
      expect(store.snapshot.toEncryptedPayloadJson(), before);
    },
  );

  test(
    'schema14 defaults deletion false and schema15 validates flags and refuses future',
    () {
      final sub = SubscriptionRecord.fromDraft(
        id: 'subscription-1',
        draft: _draft(),
      );
      final expense = SubscriptionExpenseRecord.fromDraft(
        id: 'expense-1',
        draft: _payment(sub),
      );
      final old = VaultSnapshot(
        nextAccountId: 1,
        accounts: const [],
        nextSubscriptionId: 2,
        subscriptions: [sub],
        nextExpenseId: 2,
        subscriptionExpenses: [expense],
      ).toEncryptedPayloadJson();
      old['schemaVersion'] = 14;
      ((old['subscriptionExpenses'] as List).single as Map).remove('isDeleted');
      final migrated = VaultSnapshot.fromEncryptedPayloadJson(old);
      expect(migrated.requiresSchemaUpgrade, isTrue);
      expect(migrated.subscriptionExpenses.single.isDeleted, isFalse);
      expect(migrated.subscriptionExpenses.single.amount, '200');
      final saved = migrated.toEncryptedPayloadJson();
      expect(saved['schemaVersion'], 15);
      ((saved['subscriptionExpenses'] as List).single as Map)['isDeleted'] =
          'false';
      expect(
        () => VaultSnapshot.fromEncryptedPayloadJson(saved),
        throwsA(isA<VaultFormatException>()),
      );
      expect(
        () => VaultSnapshot.fromEncryptedPayloadJson({'schemaVersion': 16}),
        throwsA(isA<VaultUnsupportedSchemaVersionException>()),
      );
    },
  );

  test(
    'account category sorts categories then distinct accounts and independent entries last',
    () {
      final a = AccountRecord.fromDraft(
        id: 'a',
        draft: AccountDraft(
          platformName: 'Same',
          category: 'A',
          loginAccount: 'a@example.invalid',
        ),
      );
      final b = AccountRecord.fromDraft(
        id: 'b',
        draft: AccountDraft(
          platformName: 'Same',
          category: 'A',
          loginAccount: 'b@example.invalid',
        ),
      );
      final c = AccountRecord.fromDraft(
        id: 'c',
        draft: AccountDraft(platformName: 'Cloud', category: 'B'),
      );
      final records = [
        for (final id in ['c', 'a', 'b', null])
          SubscriptionRecord.fromDraft(
            id: 'sub-$id',
            draft: _draft(account: id),
          ),
      ];
      final sorted = sortSubscriptionsForDisplay(
        subscriptions: records,
        sortMode: RecordSortMode.accountCategory,
        accounts: [c, b, a],
      );
      expect(sorted.map((s) => s.accountId), ['a', 'b', 'c', null]);
      final preferences = VaultPreferences(
        subscriptionSortMode: RecordSortMode.accountCategory,
      );
      final snapshot = VaultSnapshot.empty().copyWith(preferences: preferences);
      expect(
        VaultSnapshot.fromEncryptedPayloadJson(
          snapshot.toEncryptedPayloadJson(),
        ).preferences.subscriptionSortMode,
        RecordSortMode.accountCategory,
      );
    },
  );

  testWidgets(
    'home counts annual payments by paid month, refunds, deleted subscriptions and ledger drilldown',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final today = DateUtils.dateOnly(DateTime.now());
      var opened = false;
      final annual = SubscriptionRecord.fromDraft(
        id: 'annual',
        draft: _draft(
          amount: '200',
          cycle: SubscriptionCycleUnit.year,
          next: DateTime(today.year + 1, today.month, today.day),
        ),
      );
      SubscriptionExpenseRecord entry(
        String id,
        String amount, {
        SubscriptionExpenseKind kind = SubscriptionExpenseKind.payment,
        bool deleted = false,
      }) => SubscriptionExpenseRecord.fromDraft(
        id: id,
        isDeleted: deleted,
        draft: SubscriptionExpenseDraft(
          subscriptionId: null,
          serviceName: 'Archived',
          occurredOn: today,
          amount: amount,
          currency: 'CNY',
          kind: kind,
        ),
      );
      final expenses = [
        entry('1', '200'),
        entry('2', '20', kind: SubscriptionExpenseKind.refund),
        entry('3', '200', deleted: true),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomePage(
              accounts: const [],
              subscriptions: [annual],
              recentAccounts: const [],
              expenses: expenses,
              autoLockSeconds: 60,
              onOpenAccount: (_) {},
              onOpenAccounts: () {},
              onOpenSubscriptions: (_) {},
              onOpenSubscription: (_) {},
              onSearch: () {},
              onLock: () {},
              onAddAccount: () {},
              onOpenMonthlyExpenses: () => opened = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final metric = find.byKey(
        const ValueKey('home-metric-auto-renew-this-month'),
      );
      expect(
        find.descendant(of: metric, matching: find.text('180')),
        findsOneWidget,
      );
      await tester.tap(metric);
      expect(opened, isTrue);
      expect(
        CnyAmountEstimate.fromInputs([
          const CurrencyAmountInput(currency: 'CNY', amount: '-1'),
        ]).excludedCount,
        1,
      );
    },
  );

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('en'),
    const Locale('ja'),
  ]) {
    testWidgets('same-day second renewal cancel and explicit proceed $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sub = SubscriptionRecord.fromDraft(
        id: 'annual',
        draft: _draft(amount: '200', cycle: SubscriptionCycleUnit.year),
      ).markRenewed();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SubscriptionRecordCard(
                showFullDetails: true,
                subscription: sub,
                account: null,
                onMarkRenewed: (_) async {
                  calls++;
                  return true;
                },
                onSnoozeReminder: null,
                onCancelSubscription: null,
                onRestoreSubscription: null,
                onDeleteSubscription: null,
              ),
            ),
          ),
        ),
      );
      final button = find.byKey(const ValueKey('renew-subscription-annual'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('same-day-renewal-confirmation')),
        findsOneWidget,
      );
      expect(calls, 0);
      Navigator.of(
        tester.element(find.byKey(const ValueKey('confirm-repeat-renewal'))),
      ).pop(false);
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-repeat-renewal')));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      final confirm = find.descendant(
        of: dialog,
        matching: find.byType(FilledButton),
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(calls, 1);
    });
  }

  testWidgets(
    'expense row edit saves one record and delete requires confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final expense = SubscriptionExpenseRecord.fromDraft(
        id: 'expense-1',
        draft: SubscriptionExpenseDraft(
          subscriptionId: null,
          serviceName: 'Archived',
          occurredOn: _day,
          amount: '200',
          currency: 'CNY',
          kind: SubscriptionExpenseKind.payment,
        ),
      );
      SubscriptionExpenseDraft? edited;
      var deletions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SubscriptionCostStatsPage(
            subscriptions: const [],
            expenses: [expense],
            today: _day,
            onAddExpense: (_) async => true,
            onEditExpense: (line, draft) async {
              expect(line.expenseId, expense.id);
              edited = draft;
              return true;
            },
            onDeleteExpense: (_) async {
              deletions++;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final group = find.byKey(
        const ValueKey('cost-group-confirmed-month-2026-09'),
      );
      await tester.ensureVisible(group);
      await tester.tap(group);
      await tester.pumpAndSettle();
      final edit = find.byKey(const ValueKey('edit-expense-expense-1'));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expense-amount')),
        '180',
      );
      final save = find.byKey(const ValueKey('save-expense'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(edited?.amount, '180');
      expect(edited?.subscriptionId, isNull);
      final remove = find.byKey(const ValueKey('delete-expense-expense-1'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(deletions, 0);
      await tester.tap(find.byKey(const ValueKey('confirm-delete-expense')));
      await tester.pumpAndSettle();
      expect(deletions, 1);
    },
  );
}
