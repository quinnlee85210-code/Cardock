import '../../features/accounts/domain/account_record.dart';
import '../../features/subscriptions/domain/subscription_record.dart';
import 'temporary_web_models.dart';

final class TemporaryWebVaultRecords {
  const TemporaryWebVaultRecords({
    required this.revision,
    required this.accounts,
    required this.subscriptions,
  });

  final int revision;
  final List<AccountRecord> accounts;
  final List<SubscriptionRecord> subscriptions;
}

enum TemporaryWebVaultAccessState { ready, temporarilyUnavailable, invalid }

abstract interface class TemporaryWebVaultAccessStateProvider {
  TemporaryWebVaultAccessState get accessState;
}

abstract interface class TemporaryWebVaultGateway {
  bool get isEligibleForTemporaryWebSession;

  String? get vaultBindingId;

  int get revision;

  TemporaryWebVaultRecords readRecords();

  Future<TemporaryWebMutationResult> addAccount(AccountDraft draft);

  Future<TemporaryWebMutationResult> updateAccount({
    required String accountId,
    required AccountDraft draft,
    required AccountPasswordUpdateMode passwordMode,
  });

  Future<TemporaryWebMutationResult> deleteAccount(String accountId);

  Future<TemporaryWebMutationResult> addSubscription(SubscriptionDraft draft);

  Future<TemporaryWebMutationResult> updateSubscription({
    required String subscriptionId,
    required SubscriptionDraft draft,
  });

  Future<TemporaryWebMutationResult> deleteSubscription(String subscriptionId);
}

/// Called only from phone approval, never from a browser-supplied flag.
/// A gateway without this interface must reject account creation.
abstract interface class TemporaryWebPhoneApprovedAccountGateway {
  List<String> duplicateAccountLabels(AccountDraft draft);
  Future<TemporaryWebMutationResult> addAccountAfterPhoneApproval(
    AccountDraft draft, {
    required int expectedRevision,
  });
}

extension TemporaryWebVaultGatewayAccess on TemporaryWebVaultGateway {
  /// Returns the richer access state when the gateway supports it while
  /// retaining compatibility with existing boolean-only gateway fakes.
  TemporaryWebVaultAccessState get accessState {
    final gateway = this;
    if (gateway is TemporaryWebVaultAccessStateProvider) {
      return (gateway as TemporaryWebVaultAccessStateProvider).accessState;
    }
    return gateway.isEligibleForTemporaryWebSession
        ? TemporaryWebVaultAccessState.ready
        : TemporaryWebVaultAccessState.invalid;
  }
}
