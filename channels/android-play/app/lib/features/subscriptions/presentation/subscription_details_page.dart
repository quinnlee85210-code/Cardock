import '../../../l10n/localized_material.dart';

import '../../../core/preferences/record_display_mode.dart';
import '../../accounts/domain/account_record.dart';
import '../domain/subscription_record.dart';
import 'subscriptions_page.dart';

typedef SubscriptionLookup = SubscriptionRecord? Function(String id);
typedef SubscriptionAccountLookup = AccountRecord? Function(String? id);

class SubscriptionDetailsPage extends StatelessWidget {
  const SubscriptionDetailsPage({
    required this.subscriptionId,
    this.managementBuilder,
    required this.recordsListenable,
    required this.findSubscription,
    required this.findAccount,
    this.onEditSubscription,
    required this.onMarkRenewed,
    this.onMarkRenewedWithExpense,
    required this.onSnoozeReminder,
    required this.onCancelSubscription,
    required this.onRestoreSubscription,
    required this.onDeleteSubscription,
    super.key,
  });

  final String subscriptionId;
  final Widget Function(SubscriptionRecord)? managementBuilder;
  final Listenable recordsListenable;
  final SubscriptionLookup findSubscription;
  final SubscriptionAccountLookup findAccount;
  final ValueChanged<SubscriptionRecord>? onEditSubscription;
  final SubscriptionRecordAction? onMarkRenewed;
  final SubscriptionRenewalAction? onMarkRenewedWithExpense;
  final SubscriptionSnoozeAction? onSnoozeReminder;
  final SubscriptionCancelAction? onCancelSubscription;
  final SubscriptionRecordAction? onRestoreSubscription;
  final SubscriptionRecordAction? onDeleteSubscription;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('订阅详情')),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: recordsListenable,
          builder: (context, child) {
            final subscription = findSubscription(subscriptionId);
            if (subscription == null) {
              return const Center(
                key: ValueKey<String>('subscription-details-deleted'),
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('这条订阅记录已删除或不可用。'),
                ),
              );
            }
            return ListView(
              key: const ValueKey<String>('subscription-details-page'),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                SubscriptionRecordCard(
                  subscription: subscription,
                  account: findAccount(subscription.accountId),
                  displayMode: RecordDisplayMode.expandedCards,
                  showFullDetails: true,
                  onEdit: onEditSubscription == null
                      ? null
                      : () => onEditSubscription!(subscription),
                  onMarkRenewed: onMarkRenewed,
                  onMarkRenewedWithExpense: subscription.isUnresolvedTrial
                      ? null
                      : onMarkRenewedWithExpense,
                  onSnoozeReminder: onSnoozeReminder,
                  onCancelSubscription: onCancelSubscription,
                  onRestoreSubscription: onRestoreSubscription,
                  onDeleteSubscription: onDeleteSubscription,
                ),
                if (managementBuilder != null) managementBuilder!(subscription),
              ],
            );
          },
        ),
      ),
    );
  }
}
