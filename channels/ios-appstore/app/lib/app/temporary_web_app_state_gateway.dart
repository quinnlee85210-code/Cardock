import '../core/entitlements/entitlement_guard.dart';
import '../core/temporary_web/temporary_web_models.dart';
import '../core/temporary_web/temporary_web_vault_gateway.dart';
import '../features/accounts/domain/account_record.dart';
import '../features/subscriptions/domain/subscription_record.dart';
import 'app_state.dart';

final class AppStateTemporaryWebVaultGateway
    implements
        TemporaryWebVaultGateway,
        TemporaryWebVaultAccessStateProvider,
        TemporaryWebPhoneApprovedAccountGateway {
  const AppStateTemporaryWebVaultGateway(this._appState);

  final AppState _appState;

  @override
  bool get isEligibleForTemporaryWebSession =>
      accessState == TemporaryWebVaultAccessState.ready;

  @override
  String? get vaultBindingId => _appState.temporaryWebVaultBindingId;

  @override
  TemporaryWebVaultAccessState get accessState {
    if (_appState.vaultPhase == VaultPhase.locked) {
      return TemporaryWebVaultAccessState.temporarilyUnavailable;
    }
    if (_appState.isBusy) return TemporaryWebVaultAccessState.invalid;
    if (_appState.vaultPhase != VaultPhase.unlocked ||
        !_appState.hasFullVaultAccess ||
        !_appState.canManageSecurity ||
        _appState.localWebRevision < 0) {
      return TemporaryWebVaultAccessState.invalid;
    }
    return TemporaryWebVaultAccessState.ready;
  }

  @override
  int get revision => _appState.localWebRevision;

  @override
  TemporaryWebVaultRecords readRecords() => TemporaryWebVaultRecords(
    revision: revision,
    accounts: List<AccountRecord>.unmodifiable(_appState.accounts),
    subscriptions: List<SubscriptionRecord>.unmodifiable(
      _appState.subscriptions,
    ),
  );

  @override
  List<String> duplicateAccountLabels(AccountDraft draft) => [
    for (final candidate in _appState.findAccountDuplicates(draft))
      '${candidate.inTrash ? '回收站' : '活动账号'} · ${candidate.account.platformName}',
  ];

  @override
  Future<TemporaryWebMutationResult> addAccountAfterPhoneApproval(
    AccountDraft draft, {
    required int expectedRevision,
  }) async {
    if (expectedRevision != revision || !isEligibleForTemporaryWebSession) {
      return TemporaryWebMutationResult.rejected(
        revision: revision,
        message: '记录已发生变化，请在网页刷新后重新提交。',
      );
    }
    return _addAccount(draft, approvedRevision: expectedRevision);
  }

  @override
  Future<TemporaryWebMutationResult> addAccount(AccountDraft draft) async =>
      TemporaryWebMutationResult.rejected(
        revision: revision,
        message: '新增账号必须在手机批准。',
      );

  Future<TemporaryWebMutationResult> _addAccount(
    AccountDraft draft, {
    required int approvedRevision,
  }) async {
    final beforeIds = <String>{for (final item in _appState.accounts) item.id};
    final result = await _appState.createAccount(
      draft,
      duplicateApprovedRevision: approvedRevision,
    );
    if (result.status == RecordCreationStatus.limitReached) {
      return _limitReachedResult(result.limit!);
    }
    if (!result.saved) return _failedResult('账号未能保存。');
    final added = _appState.accounts
        .where((item) => !beforeIds.contains(item.id))
        .toList(growable: false);
    if (added.length != 1) {
      return TemporaryWebMutationResult.unknown(
        revision: revision,
        message: '保存结果无法唯一确认，请在手机端核对。',
      );
    }
    return TemporaryWebMutationResult.committed(
      revision: revision,
      recordId: added.single.id,
    );
  }

  @override
  Future<TemporaryWebMutationResult> updateAccount({
    required String accountId,
    required AccountDraft draft,
    required AccountPasswordUpdateMode passwordMode,
  }) async {
    final saved = await _appState.updateAccount(
      accountId: accountId,
      draft: draft,
      passwordMode: passwordMode,
    );
    return saved
        ? TemporaryWebMutationResult.committed(
            revision: revision,
            recordId: accountId,
          )
        : _failedResult('账号修改未能保存。');
  }

  @override
  Future<TemporaryWebMutationResult> deleteAccount(String accountId) async {
    final saved = await _appState.deleteAccount(accountId);
    return saved
        ? TemporaryWebMutationResult.committed(revision: revision)
        : _failedResult('账号删除结果未确认。');
  }

  @override
  Future<TemporaryWebMutationResult> addSubscription(
    SubscriptionDraft draft,
  ) async {
    final beforeIds = <String>{
      for (final item in _appState.subscriptions) item.id,
    };
    final result = await _appState.createSubscription(draft);
    if (result.status == RecordCreationStatus.limitReached) {
      return _limitReachedResult(result.limit!);
    }
    if (!result.saved) return _failedResult('订阅未能保存。');
    final added = _appState.subscriptions
        .where((item) => !beforeIds.contains(item.id))
        .toList(growable: false);
    if (added.length != 1) {
      return TemporaryWebMutationResult.unknown(
        revision: revision,
        message: '保存结果无法唯一确认，请在手机端核对。',
      );
    }
    return TemporaryWebMutationResult.committed(
      revision: revision,
      recordId: added.single.id,
    );
  }

  @override
  Future<TemporaryWebMutationResult> updateSubscription({
    required String subscriptionId,
    required SubscriptionDraft draft,
  }) async {
    final saved = await _appState.updateSubscription(
      subscriptionId: subscriptionId,
      draft: draft,
    );
    return saved
        ? TemporaryWebMutationResult.committed(
            revision: revision,
            recordId: subscriptionId,
          )
        : _failedResult('订阅修改未能保存。');
  }

  @override
  Future<TemporaryWebMutationResult> deleteSubscription(
    String subscriptionId,
  ) async {
    final saved = await _appState.deleteSubscription(subscriptionId);
    return saved
        ? TemporaryWebMutationResult.committed(revision: revision)
        : _failedResult('订阅删除结果未确认。');
  }

  TemporaryWebMutationResult _failedResult(String rejectedMessage) {
    if (!_appState.isEligibleForTemporaryWebSession) {
      return TemporaryWebMutationResult.unknown(
        revision: revision,
        message: '手机保险库状态在写入期间发生变化，请解锁后核对结果。',
      );
    }
    return TemporaryWebMutationResult.rejected(
      revision: revision,
      message: rejectedMessage,
    );
  }

  TemporaryWebMutationResult _limitReachedResult(
    EntitlementLimitDecision decision,
  ) => TemporaryWebMutationResult.rejected(
    revision: revision,
    message:
        '免费版${decision.recordType == LimitedRecordType.account ? '账户' : '订阅'}数量已达上限'
        '（${decision.usageLabel}）；请在手机设置中解锁完整版后重试。',
  );
}
