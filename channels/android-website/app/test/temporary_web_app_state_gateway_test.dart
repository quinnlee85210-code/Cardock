import 'dart:async';

import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/app/temporary_web_app_state_gateway.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_models.dart';
import 'package:account_subscription_manager/core/temporary_web/temporary_web_vault_gateway.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

const _masterPassword = 'TEST-ONLY-MASTER-1234';

void main() {
  test('电脑临时录入达到免费额度时在确认写入处明确拒绝且不丢数据', () async {
    final state = AppState(vaultStore: FakeVaultStore());
    addTearDown(state.dispose);
    final gateway = AppStateTemporaryWebVaultGateway(state);
    await state.initialize();
    await state.createVault(_masterPassword);

    for (var index = 0; index < 5; index += 1) {
      final result = await gateway.addSubscription(
        SubscriptionDraft(
          accountId: null,
          details: SubscriptionDetailsDraft(
            serviceName: '网页订阅$index',
            firstSubscribedOn: DateTime(2026, 8, 1),
            nextRenewalOn: DateTime(2026, 9, 1),
          ),
        ),
      );
      expect(result.disposition, TemporaryWebMutationDisposition.committed);
    }

    final rejected = await gateway.addSubscription(
      SubscriptionDraft(
        accountId: null,
        details: SubscriptionDetailsDraft(
          serviceName: '超额网页订阅',
          firstSubscribedOn: DateTime(2026, 8, 1),
          nextRenewalOn: DateTime(2026, 9, 1),
        ),
      ),
    );

    expect(rejected.disposition, TemporaryWebMutationDisposition.rejected);
    expect(rejected.message, contains('订阅 5/5'));
    expect(rejected.message, contains('手机设置中解锁完整版'));
    expect(state.subscriptions, hasLength(5));
  });

  test('真实 AppState 网关只在完整可写保险库中工作并保留密码编辑语义', () async {
    final state = AppState(vaultStore: FakeVaultStore());
    addTearDown(state.dispose);
    final gateway = AppStateTemporaryWebVaultGateway(state);

    await state.initialize();
    expect(gateway.isEligibleForTemporaryWebSession, isFalse);
    expect(gateway.accessState, TemporaryWebVaultAccessState.invalid);
    expect(await state.createVault(_masterPassword), VaultActionResult.success);
    expect(gateway.isEligibleForTemporaryWebSession, isTrue);
    expect(gateway.accessState, TemporaryWebVaultAccessState.ready);

    final added = await gateway.addAccountAfterPhoneApproval(
      AccountDraft(
        platformName: '网页录入平台',
        password: 'TEST-ONLY-ACCOUNT-PASSWORD',
      ),
      expectedRevision: gateway.revision,
    );
    expect(added.disposition, TemporaryWebMutationDisposition.committed);
    expect(added.recordId, isNotNull);
    expect(gateway.revision, state.localWebRevision);

    final updated = await gateway.updateAccount(
      accountId: added.recordId!,
      draft: AccountDraft(platformName: '网页修改平台'),
      passwordMode: AccountPasswordUpdateMode.preserve,
    );
    expect(updated.disposition, TemporaryWebMutationDisposition.committed);
    expect(state.accounts.single.platformName, '网页修改平台');
    expect(state.accounts.single.password, 'TEST-ONLY-ACCOUNT-PASSWORD');

    final subscription = await gateway.addSubscription(
      SubscriptionDraft(
        accountId: added.recordId!,
        details: SubscriptionDetailsDraft(
          serviceName: '网页订阅',
          firstSubscribedOn: DateTime(2026, 8, 1),
          nextRenewalOn: DateTime(2026, 9, 1),
        ),
      ),
    );
    expect(subscription.disposition, TemporaryWebMutationDisposition.committed);
    expect(state.subscriptions.single.serviceName, '网页订阅');

    state.lock();
    expect(gateway.isEligibleForTemporaryWebSession, isFalse);
    expect(
      gateway.accessState,
      TemporaryWebVaultAccessState.temporarilyUnavailable,
    );
    expect(gateway.readRecords().accounts, isEmpty);
    expect(gateway.readRecords().subscriptions, isEmpty);
  });

  test('写入期间锁定时网关明确返回结果未知而不是伪报失败', () async {
    final store = FakeVaultStore();
    final state = AppState(vaultStore: store);
    addTearDown(state.dispose);
    final gateway = AppStateTemporaryWebVaultGateway(state);

    await state.initialize();
    await state.createVault(_masterPassword);
    final saveGate = Completer<void>();
    store.saveGate = saveGate;

    final pending = gateway.addAccountAfterPhoneApproval(
      AccountDraft(platformName: '写入竞态平台'),
      expectedRevision: gateway.revision,
    );
    await Future<void>.delayed(Duration.zero);
    expect(state.isBusy, isTrue);
    expect(gateway.accessState, TemporaryWebVaultAccessState.invalid);
    state.lock();
    saveGate.complete();

    final result = await pending;
    expect(result.disposition, TemporaryWebMutationDisposition.resultUnknown);
    expect(result.message, contains('核对'));
    expect(gateway.isEligibleForTemporaryWebSession, isFalse);
  });
}
