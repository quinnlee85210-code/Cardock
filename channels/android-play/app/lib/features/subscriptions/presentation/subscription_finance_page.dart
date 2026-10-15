import '../../../app/app_state.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../domain/subscription_record.dart';
import 'payment_methods_page.dart';
import 'subscription_cost_stats_page.dart';
import 'subscription_insights_page.dart';

/// The shared destination of the subscription toolbar's single cost entry.
class SubscriptionFinancePage extends StatelessWidget {
  const SubscriptionFinancePage({
    required this.state,
    required this.onOpenSubscription,
    this.initialTab = 0,
    this.currentMonth = false,
    super.key,
  });

  final AppState state;
  final ValueChanged<SubscriptionRecord> onOpenSubscription;
  final int initialTab;
  final bool currentMonth;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    initialIndex: initialTab,
    child: ListenableBuilder(
      listenable: state,
      builder: (context, _) => Scaffold(
        key: const ValueKey('subscription-finance-page'),
        appBar: AppBar(
          title: const Text('订阅费用统计'),
          actions: [
            if (!state.hasSubscriptionOnlyAccess)
              IconButton(
                tooltip: context.tr('管理支付方式'),
                icon: const Icon(Icons.account_balance_wallet_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) => PaymentMethodsPage(state: state),
                  ),
                ),
              ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(key: ValueKey('finance-costs-tab'), child: Text('费用统计')),
              Tab(key: ValueKey('finance-insights-tab'), child: Text('费用洞察')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            SubscriptionCostStatsPage(
              embedded: true,
              accounts: state.accounts,
              subscriptions: state.subscriptions,
              expenses: state.subscriptionExpenseLedger,
              currentMonth: currentMonth,
              ledgerOnly: currentMonth,
              onEditExpense: state.hasSubscriptionOnlyAccess
                  ? null
                  : state.correctSubscriptionCost,
              onDeleteExpense: state.hasSubscriptionOnlyAccess
                  ? null
                  : (line) => state.correctSubscriptionCost(line, null),
              paymentMethods: state.paymentMethods,
              onAddExpense: state.hasSubscriptionOnlyAccess
                  ? null
                  : state.recordSubscriptionExpense,
            ),
            SubscriptionInsightsPage(
              embedded: true,
              state: state,
              onOpenSubscription: onOpenSubscription,
            ),
          ],
        ),
      ),
    ),
  );
}
