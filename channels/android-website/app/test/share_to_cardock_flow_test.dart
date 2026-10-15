import 'dart:convert';

import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:account_subscription_manager/app/app_state.dart';
import 'package:account_subscription_manager/core/data_import/data_import.dart';
import 'package:account_subscription_manager/core/platform/share_intake_bridge.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/data_import/presentation/app_data_import_ui_controller.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/share_subscription_draft_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

const _masterPassword = 'TEST-ONLY-MASTER-1234';
const _token = '123e4567-e89b-42d3-a456-426614174000';

void main() {
  test('迁移页只显示九个批准来源，同时保留三个禁用适配器 ID', () {
    final state = AppState(vaultStore: FakeVaultStore());
    final controller = AppDataImportUiController(appState: state);
    addTearDown(controller.dispose);
    addTearDown(state.dispose);

    expect(controller.sources.map((source) => source.id).toList(), <String>[
      'auto',
      'chrome_passwords_csv',
      'google_password_manager_csv',
      'bitwarden_csv',
      'onepassword_csv',
      'keepassxc_csv',
      'cardock_accounts_template',
      'cardock_subscriptions_template',
      'generic_tabular',
    ]);
    final registry = ImportSourceRegistry.standard();
    for (final id in <String>[
      'chrome_edge_google_csv',
      'firefox_csv',
      'apple_passwords_csv',
    ]) {
      final adapter = registry.adapterById(id);
      expect(adapter.enabled, isFalse, reason: id);
      expect(adapter.verified, isFalse, reason: id);
    }
  });

  testWidgets('确认页保存前零写入，保存后只落结构化待完善草稿', (tester) async {
    final (state, store) = await _createUnlockedState();
    addTearDown(state.dispose);
    const incomingUrl = 'https://billing.shared-example.test/manage';
    const rawMarker = 'RAW_SENTINEL_MUST_NOT_PERSIST';
    const sourceMarker = 'SOURCE_APP_SENTINEL_MUST_NOT_PERSIST';
    final payload = ShareIntakePayload(
      token: _token,
      title: 'Example subscription',
      subject: sourceMarker,
      text:
          '''
平台: Example
plan: Premium
金额: USD 19.99
monthly
续费日期: 2026-10-31
auto-renew: on
$incomingUrl
private note $rawMarker
'''
              .trim(),
      remainingLifetime: const Duration(minutes: 5),
    );

    await _pumpDraftPage(tester, state: state, payload: payload);
    expect(store.snapshot.pendingSubscriptionDrafts, isEmpty);
    expect(store.saveCalls, 1, reason: '唯一写入应来自预置测试账号');
    expect(
      find.byKey(const ValueKey<String>('share-subscription-draft-page')),
      findsOneWidget,
    );
    expect(find.textContaining(rawMarker), findsNothing, reason: '原文默认收起');
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey<String>('share-plan-field')),
          )
          .controller
          ?.text,
      'Premium',
    );
    final urlField = find.byKey(const ValueKey<String>('share-url-field'));
    await tester.scrollUntilVisible(
      urlField,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(
              const ValueKey<String>('share-subscription-draft-page'),
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      tester.widget<TextFormField>(urlField).controller?.text,
      incomingUrl,
    );

    await tester.tap(find.byKey(const ValueKey<String>('share-draft-save')));
    await tester.pumpAndSettle();

    expect(store.snapshot.subscriptions, isEmpty);
    expect(store.snapshot.pendingSubscriptionDrafts, hasLength(1));
    final draft = store.snapshot.pendingSubscriptionDrafts.single;
    expect(draft.accountId, state.accounts.single.id);
    expect(draft.planName, 'Premium');
    expect(draft.amount, '19.99');
    expect(draft.currency, 'USD');
    expect(draft.billingCycle?.count, 1);
    expect(draft.nextRenewalDate, DateTime(2026, 10, 31));
    expect(draft.autoRenew, isTrue);
    final serialized = jsonEncode(store.snapshot.toEncryptedPayloadJson());
    expect(serialized, isNot(contains(rawMarker)));
    expect(serialized, isNot(contains(sourceMarker)));
    expect(serialized, isNot(contains(incomingUrl)));
    expect(VaultSnapshot.currentSchemaVersion, 15);
  });

  testWidgets('清除和 TTL 过期都退出确认页且不写数据库', (tester) async {
    final (state, store) = await _createUnlockedState();
    addTearDown(state.dispose);
    final writesBefore = store.saveCalls;
    final payload = ShareIntakePayload(
      token: _token,
      text: 'plan: Disposable\nUSD 1.00',
      remainingLifetime: const Duration(minutes: 5),
    );

    await _pumpDraftPage(tester, state: state, payload: payload);
    await tester.tap(find.byKey(const ValueKey<String>('share-draft-clear')));
    await tester.pumpAndSettle();
    expect(store.saveCalls, writesBefore);
    expect(store.snapshot.pendingSubscriptionDrafts, isEmpty);

    final expiring = ShareIntakePayload(
      token: '123e4567-e89b-42d3-a456-426614174001',
      text: 'plan: Expiring',
      remainingLifetime: const Duration(milliseconds: 100),
    );
    await _pumpDraftPage(tester, state: state, payload: expiring);
    await tester.pump(const Duration(milliseconds: 101));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('share-subscription-draft-page')),
      findsNothing,
    );
    expect(store.saveCalls, writesBefore);
    expect(store.snapshot.pendingSubscriptionDrafts, isEmpty);
  });

  testWidgets('锁屏前不消费也不显示原文，解锁后消费一次，后台锁定立即清除', (tester) async {
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(platformName: 'Example'),
    );
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _masterPassword,
      snapshot: VaultSnapshot(
        nextAccountId: 2,
        accounts: <AccountRecord>[account],
      ),
    );
    final bridge = _FakeShareIntakeBridge(
      ShareIntakeResult.accepted(
        ShareIntakePayload(
          token: _token,
          text: 'LOCKED_RAW_SENTINEL\nplatform: Example\nplan: Pro',
          remainingLifetime: const Duration(minutes: 5),
        ),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pumpWidget(
      AccountSubscriptionApp(vaultStore: store, shareIntakeBridge: bridge),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('vault-unlock-page')),
      findsOneWidget,
    );
    expect(bridge.consumeCalls, 0);
    expect(find.textContaining('LOCKED_RAW_SENTINEL'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey<String>('unlock-master-password-field')),
      _masterPassword,
    );
    await tester.tap(find.byKey(const ValueKey<String>('unlock-vault-button')));
    await tester.pumpAndSettle();
    expect(bridge.consumeCalls, 1);
    expect(
      find.byKey(const ValueKey<String>('share-subscription-draft-page')),
      findsOneWidget,
    );
    expect(find.textContaining('LOCKED_RAW_SENTINEL'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('vault-unlock-page')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('share-subscription-draft-page')),
      findsNothing,
    );
    expect(find.textContaining('LOCKED_RAW_SENTINEL'), findsNothing);
    expect(store.snapshot.pendingSubscriptionDrafts, isEmpty);
    expect(bridge.clearCalls, greaterThanOrEqualTo(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    bridge.dispose();
  });
}

Future<(AppState, FakeVaultStore)> _createUnlockedState() async {
  final store = FakeVaultStore();
  final state = AppState(vaultStore: store);
  await state.initialize();
  expect(await state.createVault(_masterPassword), VaultActionResult.success);
  final created = await state.createAccount(
    AccountDraft(
      platformName: 'Example',
      website: 'https://existing-account.example.test',
    ),
  );
  expect(created.saved, isTrue);
  return (state, store);
}

Future<void> _pumpDraftPage(
  WidgetTester tester, {
  required AppState state,
  required ShareIntakePayload payload,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey<String>('open-share-draft-test-page'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => ShareSubscriptionDraftPage(
                  appState: state,
                  payload: payload,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('open-share-draft-test-page')),
  );
  await tester.pumpAndSettle();
}

final class _FakeShareIntakeBridge extends ChangeNotifier
    implements ShareIntakeBridge {
  _FakeShareIntakeBridge(this._pending);

  ShareIntakeResult? _pending;
  int consumeCalls = 0;
  int clearCalls = 0;

  @override
  Future<ShareIntakeResult?> consumePending() async {
    consumeCalls += 1;
    final result = _pending;
    _pending = null;
    return result;
  }

  @override
  Future<void> clearPending() async {
    clearCalls += 1;
    _pending = null;
  }
}
