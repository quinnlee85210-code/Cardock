import '../../features/subscriptions/domain/subscription_record.dart';
import 'vault_contract.dart';

/// Pure deterministic normalization. Only the existing authorized save path writes.
/// ASCII case folding deliberately does not merge synonyms or translated names.
VaultSnapshot normalizeSubscriptionMetadata(VaultSnapshot source) {
  final methods = [...source.paymentMethods];
  final byName = {
    for (final p in methods) normalizedPaymentMethodName(p.name): p,
  };
  final ids = methods.map((p) => p.id).toSet();
  var sequence = 1;
  SubscriptionRecord upgrade(SubscriptionRecord sub) {
    String? methodId = sub.management?.paymentMethodId;
    if (methodId != null &&
        methods.where((p) => p.id == methodId).firstOrNull?.name !=
            sub.paymentMethod) {
      methodId = null;
    }
    if (methodId == null && sub.paymentMethod?.trim().isNotEmpty == true) {
      final name = sub.paymentMethod!.trim();
      final key = normalizedPaymentMethodName(name);
      var method = byName[key];
      if (method == null) {
        while (ids.contains('payment-$sequence')) {
          sequence++;
        }
        method = PaymentMethodRecord(id: 'payment-${sequence++}', name: name);
        methods.add(method);
        ids.add(method.id);
        byName[key] = method;
      }
      methodId = method.id;
    }
    final old = sub.management;
    var management =
        old ??
        SubscriptionManagement(
          reminderRules: sub.reminderEnabled
              ? [
                  SubscriptionReminderRule(
                    event: SubscriptionReminderEvent.renewal,
                    daysBefore: [sub.reminderDaysBefore],
                  ),
                ]
              : [],
          historyIncomplete: true,
          compatibilityBaseline: sub.amount == null
              ? null
              : SubscriptionPricePoint(
                  id: 'legacy-baseline',
                  effectiveOn: DateTime(1970),
                  amount: sub.amount!,
                  currency: sub.currency,
                  cycleCount: sub.cycleCount,
                  cycleUnit: sub.cycleUnit,
                  kind: PriceChangeKind.baseline,
                  createdAt: DateTime.utc(1970),
                  note: '兼容基线；生效日期与创建时间未知，不代表确定历史',
                ),
        );
    // An unchanged legacy workflow has no dated price evidence. Preserve its
    // established calculation when its current amount is edited; explicit
    // price-history edits use the immutable dated timeline instead.
    if (management.trial == null &&
        management.priceHistory.isEmpty &&
        sub.amount != null &&
        (management.compatibilityBaseline?.amount != sub.amount ||
            management.compatibilityBaseline?.currency != sub.currency ||
            management.compatibilityBaseline?.cycleCount != sub.cycleCount ||
            management.compatibilityBaseline?.cycleUnit != sub.cycleUnit)) {
      management = management.copyWith(
        compatibilityBaseline: SubscriptionPricePoint(
          id: 'legacy-baseline',
          effectiveOn: DateTime(1970),
          amount: sub.amount!,
          currency: sub.currency,
          cycleCount: sub.cycleCount,
          cycleUnit: sub.cycleUnit,
          kind: PriceChangeKind.baseline,
          createdAt: DateTime.utc(1970),
        ),
      );
    }
    return sub.withManagement(
      management.copyWith(
        paymentMethodId: methodId,
        clearPaymentMethod: methodId == null,
      ),
    );
  }

  final subscriptions = source.subscriptions.map(upgrade).toList();
  final trash = source.trashSubscriptions
      .map(
        (t) => TrashSubscription(
          record: upgrade(t.record),
          deletedAtUtc: t.deletedAtUtc,
          batchId: t.batchId,
        ),
      )
      .toList();
  return source.copyWith(
    subscriptions: subscriptions,
    trashSubscriptions: trash,
    paymentMethods: methods,
  );
}
