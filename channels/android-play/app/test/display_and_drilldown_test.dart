import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:account_subscription_manager/core/preferences/record_display_mode.dart';
import 'package:account_subscription_manager/core/preferences/record_sort_mode.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/accounts/presentation/widgets/account_record_card.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_list_preset.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscriptions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

const _testMasterPassword = 'TEST-ONLY-MASTER-1234';

void main() {
  test('schema4 显示偏好为可选字段且新值写回 schema6', () {
    final payload = Map<String, Object?>.from(
      VaultSnapshot.empty().toEncryptedPayloadJson(),
    )..['schemaVersion'] = 4;
    final legacyPreferences =
        Map<String, Object?>.from(
            payload['preferences']! as Map<Object?, Object?>,
          )
          ..remove('accountDisplayMode')
          ..remove('subscriptionDisplayMode')
          ..remove('accountSortMode')
          ..remove('subscriptionSortMode');
    payload['preferences'] = legacyPreferences;

    final restored = VaultSnapshot.fromEncryptedPayloadJson(payload);
    expect(
      restored.preferences.accountDisplayMode,
      RecordDisplayMode.expandedCards,
    );
    expect(
      restored.preferences.subscriptionDisplayMode,
      RecordDisplayMode.expandedCards,
    );
    expect(restored.preferences.accountSortMode, RecordSortMode.oldestAdded);
    expect(
      restored.preferences.subscriptionSortMode,
      RecordSortMode.renewalSoonest,
    );

    final next = restored.copyWith(
      preferences: restored.preferences.copyWith(
        accountDisplayMode: RecordDisplayMode.collapsibleCards,
        subscriptionDisplayMode: RecordDisplayMode.compactList,
        accountSortMode: RecordSortMode.newestAdded,
        subscriptionSortMode: RecordSortMode.nameAscending,
      ),
    );
    final nextPayload = next.toEncryptedPayloadJson();
    expect(nextPayload['schemaVersion'], VaultSnapshot.currentSchemaVersion);
    final nextPreferences = nextPayload['preferences']! as Map<String, Object?>;
    expect(nextPreferences['accountDisplayMode'], 'collapsibleCards');
    expect(nextPreferences['subscriptionDisplayMode'], 'compactList');
    expect(nextPreferences['accountSortMode'], 'newestAdded');
    expect(nextPreferences['subscriptionSortMode'], 'nameAscending');

    nextPreferences['accountDisplayMode'] = 'unknown-mode';
    expect(
      () => VaultSnapshot.fromEncryptedPayloadJson(nextPayload),
      throwsA(isA<VaultFormatException>()),
    );
    nextPreferences['accountDisplayMode'] = 'collapsibleCards';
    nextPreferences['accountSortMode'] = 'unknown-sort';
    expect(
      () => VaultSnapshot.fromEncryptedPayloadJson(nextPayload),
      throwsA(isA<VaultFormatException>()),
    );
  });

  test('自然月续费统计保留已续费卡片并覆盖当月与次月完整日期范围', () {
    final today = DateTime(2026, 7, 10);
    final renewed = _subscription(
      'renewed',
      DateTime(2026, 7, 25),
    ).markRenewed(recordedOn: today);
    final records = <SubscriptionRecord>[
      _subscription('month', DateTime(2026, 7, 15)),
      _subscription('thirty', DateTime(2026, 8, 9)),
      _subscription('thirty-one', DateTime(2026, 8, 10)),
      _subscription('past', DateTime(2026, 7, 9)),
      _subscription('not-auto', DateTime(2026, 7, 20), autoRenew: false),
      _subscription(
        'paused',
        DateTime(2026, 7, 21),
        status: SubscriptionStatus.paused,
      ),
      _subscription(
        'cancelled',
        DateTime(2026, 7, 22),
        status: SubscriptionStatus.cancelled,
      ),
      _subscription(
        'expired',
        DateTime(2026, 8, 1),
        status: SubscriptionStatus.expired,
      ),
      renewed,
    ];

    expect(
      subscriptionsForPreset(
        records,
        SubscriptionListPreset.renewalsThisMonth,
        today: today,
      ).map((record) => record.id),
      ['past', 'month', 'not-auto', 'paused', 'cancelled', 'renewed'],
    );
    expect(
      subscriptionsForPreset(
        records,
        SubscriptionListPreset.renewalsNextMonth,
        today: today,
      ).map((record) => record.id),
      ['expired', 'thirty', 'thirty-one', 'renewed'],
    );
    expect(
      subscriptionsForPreset(
        records,
        SubscriptionListPreset.renewingWithinThirtyDays,
        today: today,
      ).map((record) => record.id),
      ['month', 'not-auto', 'thirty'],
    );
    expect(
      subscriptionsForPreset(
        records,
        SubscriptionListPreset.overdue,
        today: today,
      ).map((record) => record.id),
      ['past', 'expired'],
    );
  });

  testWidgets('账号和订阅可折叠卡片默认收起且紧凑列表可进入详情', (tester) async {
    final account = _account();
    final subscription = _subscription(
      'subscription-1',
      subscriptionDateOnly(DateTime.now()).add(const Duration(days: 5)),
    );
    var accountOpened = 0;
    var subscriptionOpened = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              AccountRecordCard(
                account: account,
                subscriptions: [subscription],
                displayMode: RecordDisplayMode.collapsibleCards,
                onOpen: () => accountOpened += 1,
              ),
              SubscriptionRecordCard(
                subscription: subscription,
                account: account,
                displayMode: RecordDisplayMode.collapsibleCards,
                onOpen: () => subscriptionOpened += 1,
                onEdit: () {},
                onMarkRenewed: null,
                onSnoozeReminder: null,
                onCancelSubscription: null,
                onRestoreSubscription: null,
                onDeleteSubscription: null,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('用户名：已填写'), findsNothing);
    expect(find.text('账号摘要：中•••名 · 1项订阅'), findsOneWidget);
    expect(find.text('用户名：中文用户名'), findsNothing);
    expect(find.textContaining('首次订阅：'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('toggle-account-account-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('toggle-subscription-subscription-1')),
    );
    await tester.pump();
    expect(find.text('用户名：已填写'), findsOneWidget);
    expect(find.text('账号摘要：中•••名 · 1项订阅'), findsOneWidget);
    expect(find.text('用户名：中文用户名'), findsNothing);
    expect(find.textContaining('首次订阅：'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              AccountRecordCard(
                account: account,
                subscriptions: [subscription],
                displayMode: RecordDisplayMode.compactList,
                onOpen: () => accountOpened += 1,
              ),
              SubscriptionRecordCard(
                subscription: subscription,
                account: account,
                displayMode: RecordDisplayMode.compactList,
                onOpen: () => subscriptionOpened += 1,
                onEdit: () {},
                onMarkRenewed: null,
                onSnoozeReminder: null,
                onCancelSubscription: null,
                onRestoreSubscription: null,
                onDeleteSubscription: null,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('account-card-account-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('subscription-card-subscription-1')),
    );
    expect(accountOpened, 1);
    expect(subscriptionOpened, 1);
    expect(find.text('账号摘要：中•••名 · 1项订阅'), findsOneWidget);
    expect(find.text('用户名：中文用户名'), findsNothing);
  });

  testWidgets('订阅页显示总数与V6固定四标签', (tester) async {
    final account = _account();
    final subscription = _subscription(
      'subscription-1',
      subscriptionDateOnly(DateTime.now()).add(const Duration(days: 5)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubscriptionsPage(
            accounts: [account],
            subscriptions: [subscription],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('订阅统计 · 共1个订阅'), findsOneWidget);
    expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isFalse);
    expect(find.text('全部订阅'), findsOneWidget);
    expect(find.text('即将续费'), findsOneWidget);
    expect(find.text('已到期'), findsOneWidget);
    expect(find.text('已取消'), findsOneWidget);
  });

  testWidgets('设置页可分别保存账号与订阅显示方式', (tester) async {
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
    );
    await tester.pumpWidget(AccountSubscriptionApp(vaultStore: store));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('unlock-master-password-field')),
      _testMasterPassword,
    );
    await tester.tap(find.byKey(const ValueKey<String>('unlock-vault-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('nav-settings')));
    await tester.pumpAndSettle();

    final accountSetting = find.byKey(
      const ValueKey<String>('account-display-mode-setting'),
    );
    final settingsScrollable = find.descendant(
      of: find.byKey(const ValueKey<String>('settings-page')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      accountSetting,
      300,
      scrollable: settingsScrollable.first,
    );
    await tester.ensureVisible(accountSetting);
    await tester.pumpAndSettle();
    expect(accountSetting.hitTestable(), findsOneWidget);
    await tester.tap(accountSetting);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('account-display-compactList')),
    );
    await tester.pumpAndSettle();
    expect(
      store.snapshot.preferences.accountDisplayMode,
      RecordDisplayMode.compactList,
    );

    final subscriptionSetting = find.byKey(
      const ValueKey<String>('subscription-display-mode-setting'),
    );
    await tester.scrollUntilVisible(
      subscriptionSetting,
      200,
      scrollable: settingsScrollable.first,
    );
    await tester.ensureVisible(subscriptionSetting);
    await tester.pumpAndSettle();
    expect(subscriptionSetting.hitTestable(), findsOneWidget);
    await tester.tap(subscriptionSetting);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('subscription-display-collapsibleCards'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      store.snapshot.preferences.subscriptionDisplayMode,
      RecordDisplayMode.collapsibleCards,
    );
  });

  testWidgets('360像素窄屏下三种账号与订阅显示方式均无溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final account = AccountRecord.fromDraft(
      id: 'account-1',
      draft: AccountDraft(
        platformName: '一个名称很长的中文测试平台',
        username: '中文用户名',
        category: '非常长的自定义分类名称',
      ),
    );
    final subscription = _subscription(
      'subscription-1',
      subscriptionDateOnly(DateTime.now()).add(const Duration(days: 5)),
    );

    for (final mode in RecordDisplayMode.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AccountRecordCard(
                  account: account,
                  subscriptions: [subscription],
                  displayMode: mode,
                  onOpen: () {},
                  onEdit: () {},
                  onDelete: () {},
                  onAddSubscription: () {},
                ),
                SubscriptionRecordCard(
                  subscription: subscription,
                  account: account,
                  displayMode: mode,
                  onOpen: () {},
                  onEdit: () {},
                  onMarkRenewed: (_) async => true,
                  onSnoozeReminder: (_, _) async => true,
                  onCancelSubscription: (_, {accessEndsOn}) async => true,
                  onRestoreSubscription: (_) async => true,
                  onDeleteSubscription: (_) async => true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: mode.label);
    }
  });

  testWidgets('首页统计可钻取准确列表和详情且账号总数会清除旧筛选', (tester) async {
    final today = subscriptionDateOnly(DateTime.now());
    final account = _account();
    final subscription = _subscription(
      'subscription-1',
      today.add(const Duration(days: 5)),
    );
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
      snapshot: VaultSnapshot(
        nextAccountId: 2,
        accounts: [account],
        nextSubscriptionId: 2,
        subscriptions: [subscription],
      ),
    );

    await tester.pumpWidget(AccountSubscriptionApp(vaultStore: store));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('unlock-master-password-field')),
      _testMasterPassword,
    );
    await tester.tap(find.byKey(const ValueKey<String>('unlock-vault-button')));
    await tester.pumpAndSettle();

    final renewingMetric = find.byKey(
      const ValueKey<String>('home-metric-renewing-within-thirty-days'),
    );
    expect(renewingMetric, findsOneWidget);
    final renderedRenewingMetric = tester.widget<Widget>(renewingMetric) is Text
        ? renewingMetric
        : find.descendant(of: renewingMetric, matching: find.byType(Text));
    expect(renderedRenewingMetric, findsOneWidget);
    expect(tester.widget<Text>(renderedRenewingMetric).data, '1');
    await tester.tap(find.byKey(const ValueKey<String>('home-search')));
    await tester.pumpAndSettle();
    final accountSearch = find.byKey(const ValueKey<String>('account-search'));
    expect(accountSearch, findsOneWidget);
    expect(tester.widget<TextField>(accountSearch).focusNode?.hasFocus, isTrue);
    await tester.tap(find.byKey(const ValueKey<String>('nav-home')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('home-renewal-overview')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('subscription-filter-banner')),
      findsOneWidget,
    );
    expect(find.text('测试订阅'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('subscription-card-subscription-1')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('subscription-details-page')),
      findsOneWidget,
    );
    expect(find.textContaining('首次订阅：'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('edit-subscription-subscription-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('renew-subscription-subscription-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('snooze-subscription-subscription-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('cancel-subscription-subscription-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('delete-subscription-subscription-1')),
      findsOneWidget,
    );
    final detailsBackButton = find.byType(BackButton);
    expect(detailsBackButton, findsOneWidget);
    await tester.tap(detailsBackButton);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('nav-accounts')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('account-search')),
      '不存在的账号',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('account-card-account-1')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey<String>('nav-home')));
    await tester.pumpAndSettle();
    final allAccountsAction = find.text('全部账号');
    await tester.scrollUntilVisible(
      allAccountsAction,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey<String>('home-page')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(
      tester.element(allAccountsAction),
      alignment: 0.35,
    );
    await tester.pumpAndSettle();
    await tester.tap(allAccountsAction);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('accounts-page')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('account-search')),
          )
          .controller!
          .text,
      isEmpty,
    );
    expect(
      find.byKey(const ValueKey<String>('account-card-account-1')),
      findsOneWidget,
    );
  });
}

AccountRecord _account() => AccountRecord.fromDraft(
  id: 'account-1',
  draft: AccountDraft(platformName: '测试平台', username: '中文用户名'),
);

SubscriptionRecord _subscription(
  String id,
  DateTime nextRenewalOn, {
  bool autoRenew = true,
  SubscriptionStatus status = SubscriptionStatus.active,
}) => SubscriptionRecord.fromDraft(
  id: id,
  draft: SubscriptionDraft(
    accountId: 'account-1',
    details: SubscriptionDetailsDraft(
      serviceName: '测试订阅',
      amount: '18.8',
      firstSubscribedOn: DateTime(2025, 1, 1),
      nextRenewalOn: nextRenewalOn,
      autoRenew: autoRenew,
      status: status,
    ),
  ),
);
