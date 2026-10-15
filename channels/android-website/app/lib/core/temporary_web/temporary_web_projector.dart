import '../../features/accounts/domain/account_record.dart';
import '../../features/subscriptions/domain/subscription_record.dart';
import 'temporary_web_models.dart';
import 'temporary_web_vault_gateway.dart';

final class TemporaryWebRecordProjector {
  const TemporaryWebRecordProjector();

  Map<String, Object?> project({
    required TemporaryWebVaultRecords records,
    required TemporaryWebSessionPolicy policy,
    required Set<String> sessionAccountIds,
    required Set<String> sessionSubscriptionIds,
  }) {
    final subscriptionsByAccount = <String, int>{};
    for (final subscription in records.subscriptions) {
      final accountId = subscription.accountId;
      if (accountId == null) continue;
      subscriptionsByAccount.update(
        accountId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    final accounts = <Map<String, Object?>>[];
    for (final account in records.accounts) {
      final isCurrent = sessionAccountIds.contains(account.id);
      if (!isCurrent &&
          policy.historyMode == TemporaryWebHistoryMode.currentSessionOnly) {
        continue;
      }
      accounts.add(
        _account(
          account,
          isCurrent: isCurrent,
          historyMode: policy.historyMode,
          allowHistoryEditing: policy.allowHistoryEditing,
          allowHistoricalPasswordReveal: policy.allowHistoricalPasswordReveal,
          subscriptionCount: subscriptionsByAccount[account.id] ?? 0,
        ),
      );
    }

    final visibleAccountIds = <String>{
      for (final account in accounts) account['id']! as String,
    };
    final subscriptions = <Map<String, Object?>>[];
    for (final subscription in records.subscriptions) {
      final isCurrent = sessionSubscriptionIds.contains(subscription.id);
      if (!isCurrent &&
          policy.historyMode == TemporaryWebHistoryMode.currentSessionOnly) {
        continue;
      }
      if (subscription.accountId != null &&
          !visibleAccountIds.contains(subscription.accountId)) {
        continue;
      }
      subscriptions.add(
        _subscription(
          subscription,
          isCurrent: isCurrent,
          historyMode: policy.historyMode,
          allowHistoryEditing: policy.allowHistoryEditing,
        ),
      );
    }

    return <String, Object?>{
      'revision': records.revision,
      'historyMode': policy.historyMode.name,
      'allowHistoryEditing': policy.allowHistoryEditing,
      'allowHistoricalPasswordReveal': policy.allowHistoricalPasswordReveal,
      'accountCategories': accountCategoryOptions(records.accounts),
      'accounts': accounts,
      'subscriptions': subscriptions,
    };
  }

  Map<String, Object?> _account(
    AccountRecord account, {
    required bool isCurrent,
    required TemporaryWebHistoryMode historyMode,
    required bool allowHistoryEditing,
    required bool allowHistoricalPasswordReveal,
    required int subscriptionCount,
  }) {
    final result = <String, Object?>{
      'id': account.id,
      'platformName': account.platformName,
      'category': account.category,
      'subscriptionCount': subscriptionCount,
      'isCurrentSession': isCurrent,
      'canEdit':
          isCurrent ||
          (historyMode == TemporaryWebHistoryMode.details &&
              allowHistoryEditing),
      'deleteNeedsPhoneApproval': !isCurrent,
    };
    if (!isCurrent && allowHistoricalPasswordReveal) {
      result['hasPassword'] = account.password != null;
    }
    if (isCurrent || historyMode == TemporaryWebHistoryMode.details) {
      result.addAll(<String, Object?>{
        'loginAccount': account.loginAccount,
        'username': account.username,
        'boundPhone': account.boundPhone,
        'boundEmail': account.boundEmail,
        'website': account.website,
        'notes': account.notes,
        'customFields': [
          for (final field in account.customFields)
            {
              ...field.toJson(),
              'value': field.isSensitive ? '' : field.value,
              'valueState': field.isSensitive ? 'redacted' : 'present',
            },
        ],
      });
    }
    if (isCurrent) {
      result['password'] = account.password;
    }
    return result;
  }

  Map<String, Object?> _subscription(
    SubscriptionRecord subscription, {
    required bool isCurrent,
    required TemporaryWebHistoryMode historyMode,
    required bool allowHistoryEditing,
  }) {
    final result = <String, Object?>{
      'id': subscription.id,
      'accountId': subscription.accountId,
      'serviceName': subscription.serviceName,
      'nextRenewalOn': formatSubscriptionDate(subscription.nextRenewalOn),
      'status': subscription.status.name,
      'isCurrentSession': isCurrent,
      'canEdit':
          isCurrent ||
          (historyMode == TemporaryWebHistoryMode.details &&
              allowHistoryEditing),
      'deleteNeedsPhoneApproval': !isCurrent,
    };
    if (isCurrent || historyMode == TemporaryWebHistoryMode.details) {
      result.addAll(<String, Object?>{
        'planName': subscription.planName,
        'amount': subscription.amount,
        'currency': subscription.currency,
        'firstSubscribedOn': formatSubscriptionDate(
          subscription.firstSubscribedOn,
        ),
        'cycleCount': subscription.cycleCount,
        'cycleUnit': subscription.cycleUnit.name,
        'autoRenew': subscription.autoRenew,
        'paymentMethod': subscription.paymentMethod,
        'reminderDaysBefore': subscription.reminderDaysBefore,
        'reminderEnabled': subscription.reminderEnabled,
      });
    }
    return result;
  }
}
