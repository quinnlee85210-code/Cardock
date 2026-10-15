import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:account_subscription_manager/core/preferences/record_display_mode.dart';
import 'package:account_subscription_manager/core/preferences/record_sort_mode.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/accounts/presentation/accounts_page.dart';
import 'package:account_subscription_manager/features/home/presentation/home_page.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscriptions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

const _testMasterPassword = 'TEST-ONLY-MASTER-1234';

void main() {
  testWidgets(
    '3 US云居 5 邮箱 2 币圈 produce one chip per category after adding records',
    (tester) async {
      final accounts = [
        for (var i = 0; i < 3; i++)
          _account('us-$i', 'US-$i', category: 'US云居'),
        for (var i = 0; i < 5; i++)
          _account('mail-$i', 'Mail-$i', category: '邮箱'),
        for (var i = 0; i < 2; i++)
          _account('coin-$i', 'Coin-$i', category: '币圈'),
      ];
      Future<void> render() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountsPage(
              accounts: List.of(accounts),
              subscriptions: const [],
              onAddAccount: () {},
            ),
          ),
        ),
      );
      await render();
      await tester.pumpAndSettle();
      for (final name in ['US云居', '邮箱', '币圈']) {
        expect(
          find.byKey(ValueKey('account-category-filter-$name')),
          findsOneWidget,
        );
      }
      accounts.add(_account('us-4', 'US-4', category: 'us云居'));
      await render();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('account-category-filter-US云居')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('account-category-filter-us云居')),
        findsNothing,
      );
      final chip = find.byKey(const ValueKey('account-category-filter-US云居'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(
        groupAccountsByCategory(
          accounts,
        ).where((g) => g.label == 'US云居').single.accounts,
        hasLength(4),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('排序模式存储值只接受已知选项', () {
    for (final mode in RecordSortMode.values) {
      expect(recordSortModeFromStorage(mode.storageValue), mode);
    }
    expect(recordSortModeFromStorage('future-mode'), isNull);
    expect(recordSortModeFromStorage(1), isNull);
  });

  test('账号排序使用最近正常续费日且并列时保持添加顺序', () {
    final accounts = <AccountRecord>[
      _account('account-1', 'Zulu'),
      _account('account-2', 'Alpha'),
      _account('account-3', 'No subscription'),
    ];
    final subscriptions = <SubscriptionRecord>[
      _subscription(
        'subscription-1',
        accountId: 'account-1',
        serviceName: 'Later',
        nextRenewalOn: DateTime(2026, 9, 20),
      ),
      _subscription(
        'subscription-2',
        accountId: 'account-2',
        serviceName: 'Sooner',
        nextRenewalOn: DateTime(2026, 8, 20),
      ),
      _subscription(
        'subscription-3',
        accountId: 'account-3',
        serviceName: 'Cancelled',
        nextRenewalOn: DateTime(2026, 8, 10),
        status: SubscriptionStatus.cancelled,
      ),
    ];

    Iterable<String> ids(RecordSortMode mode) => sortAccountsForDisplay(
      accounts: accounts,
      subscriptions: subscriptions,
      sortMode: mode,
    ).map((record) => record.id);

    expect(ids(RecordSortMode.renewalSoonest), [
      'account-2',
      'account-1',
      'account-3',
    ]);
    expect(ids(RecordSortMode.newestAdded), [
      'account-3',
      'account-2',
      'account-1',
    ]);
    expect(ids(RecordSortMode.oldestAdded), [
      'account-1',
      'account-2',
      'account-3',
    ]);
    expect(ids(RecordSortMode.nameAscending), [
      'account-2',
      'account-3',
      'account-1',
    ]);
  });

  test('相同账号分类只生成一个分组并保留组内排序', () {
    final accounts = <AccountRecord>[
      _account('account-1', '邮箱一', category: '邮箱'),
      _account('account-2', '邮箱二', category: '邮箱'),
      _account('account-3', '邮箱三', category: '邮箱'),
      _account('account-4', '邮箱四', category: '邮箱'),
      _account('account-5', '办公一', category: '办公'),
      _account('account-6', '未分类一'),
    ];

    final groups = groupAccountsByCategory(accounts);
    expect(groups.map((group) => group.label), <String>['邮箱', '办公', '未分类']);
    expect(groups.first.accounts.map((account) => account.id), <String>[
      'account-1',
      'account-2',
      'account-3',
      'account-4',
    ]);
  });

  testWidgets('账号页用单一分类标题承载同类账号并随搜索更新数量', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 2000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final accounts = <AccountRecord>[
      _account('account-1', '邮箱一', category: '邮箱'),
      _account('account-2', '邮箱二', category: '邮箱'),
      _account('account-3', '邮箱三', category: '邮箱'),
      _account('account-4', '邮箱四', category: '邮箱'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountsPage(
            accounts: accounts,
            subscriptions: const <SubscriptionRecord>[],
            onAddAccount: () {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('account-category-group-邮箱')),
      findsOneWidget,
    );
    expect(find.text('4个账号'), findsOneWidget);
    for (final account in accounts) {
      expect(
        find.byKey(ValueKey<String>('account-card-${account.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('account-category-pill-${account.id}')),
        findsNothing,
      );
    }

    await tester.enterText(
      find.byKey(const ValueKey<String>('account-search')),
      '邮箱三',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('account-category-group-邮箱')),
      findsOneWidget,
    );
    expect(find.text('1个账号'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('account-card-account-3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('account-card-account-1')),
      findsNothing,
    );
  });

  for (final displayMode in RecordDisplayMode.values) {
    testWidgets('账号分类可折叠展开且不改变 ${displayMode.name} 单卡显示模式', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 2000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final accounts = <AccountRecord>[
        _account('account-email', '邮箱一', category: '邮箱'),
        _account('account-office', '办公一', category: '办公'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountsPage(
              accounts: accounts,
              subscriptions: const <SubscriptionRecord>[],
              displayMode: displayMode,
              onAddAccount: () {},
            ),
          ),
        ),
      );

      final emailGroup = find.byKey(
        const ValueKey<String>('account-category-group-邮箱'),
      );
      final emailToggle = find.byKey(
        const ValueKey<String>('account-category-toggle-邮箱'),
      );
      final emailCard = find.byKey(
        const ValueKey<String>('account-card-account-email'),
      );
      final officeCard = find.byKey(
        const ValueKey<String>('account-card-account-office'),
      );

      expect(emailGroup, findsOneWidget);
      expect(emailToggle, findsOneWidget);
      expect(emailCard, findsOneWidget);
      expect(officeCard, findsOneWidget);

      await tester.tap(emailGroup);
      await tester.pump();
      expect(emailCard, findsNothing);
      expect(officeCard, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('account-category-group-办公')),
        findsOneWidget,
      );

      await tester.tap(emailGroup);
      await tester.pump();
      expect(emailCard, findsOneWidget);

      await tester.tap(emailGroup);
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey<String>('account-search')),
        '邮箱一',
      );
      await tester.pump();
      expect(emailCard, findsOneWidget);
    });
  }

  test('订阅排序支持续费日、添加顺序和名称，且待处理优先时已取消排在最后', () {
    final subscriptions = <SubscriptionRecord>[
      _subscription(
        'subscription-1',
        serviceName: 'Zulu',
        nextRenewalOn: DateTime(2026, 9, 20),
      ),
      _subscription(
        'subscription-2',
        serviceName: 'Alpha',
        nextRenewalOn: DateTime(2026, 8, 20),
      ),
      _subscription(
        'subscription-3',
        serviceName: 'Beta',
        nextRenewalOn: DateTime(2026, 8, 20),
      ),
      _subscription(
        'subscription-4',
        serviceName: 'Cancelled early date',
        nextRenewalOn: DateTime(2026, 8, 1),
        status: SubscriptionStatus.cancelled,
      ),
    ];

    Iterable<String> ids(RecordSortMode mode) => sortSubscriptionsForDisplay(
      subscriptions: subscriptions,
      sortMode: mode,
    ).map((record) => record.id);

    expect(ids(RecordSortMode.renewalSoonest), [
      'subscription-2',
      'subscription-3',
      'subscription-1',
      'subscription-4',
    ]);
    expect(ids(RecordSortMode.newestAdded), [
      'subscription-4',
      'subscription-3',
      'subscription-2',
      'subscription-1',
    ]);
    expect(ids(RecordSortMode.oldestAdded), [
      'subscription-1',
      'subscription-2',
      'subscription-3',
      'subscription-4',
    ]);
    expect(ids(RecordSortMode.nameAscending), [
      'subscription-2',
      'subscription-3',
      'subscription-4',
      'subscription-1',
    ]);
  });

  test('首页近期续费覆盖0/1/5/>5项并过滤状态，同日保持原顺序', () {
    final today = DateTime(2026, 8, 2);
    final eligible = <SubscriptionRecord>[
      _subscription('today', serviceName: 'Today', nextRenewalOn: today),
      _subscription(
        'tomorrow',
        serviceName: 'Tomorrow',
        nextRenewalOn: today.add(const Duration(days: 1)),
      ),
      _subscription(
        'same-day-a',
        serviceName: 'Same day A',
        nextRenewalOn: today.add(const Duration(days: 2)),
      ),
      _subscription(
        'same-day-b',
        serviceName: 'Same day B',
        nextRenewalOn: today.add(const Duration(days: 2)),
      ),
      _subscription(
        'beyond-thirty-days',
        serviceName: 'Beyond thirty days',
        nextRenewalOn: today.add(const Duration(days: 45)),
      ),
      _subscription(
        'sixth',
        serviceName: 'Sixth',
        nextRenewalOn: today.add(const Duration(days: 90)),
      ),
    ];
    final excluded = <SubscriptionRecord>[
      _subscription(
        'overdue',
        serviceName: 'Overdue',
        nextRenewalOn: today.subtract(const Duration(days: 1)),
      ),
      _subscription(
        'paused',
        serviceName: 'Paused',
        nextRenewalOn: today,
        status: SubscriptionStatus.paused,
      ),
      _subscription(
        'cancelled',
        serviceName: 'Cancelled',
        nextRenewalOn: today,
        status: SubscriptionStatus.cancelled,
      ),
      _subscription(
        'expired',
        serviceName: 'Expired',
        nextRenewalOn: today,
        status: SubscriptionStatus.expired,
      ),
    ];

    Iterable<String> ids(Iterable<SubscriptionRecord> records) =>
        upcomingSubscriptionsForHome(
          records,
          today: today,
        ).map((record) => record.id);

    expect(ids(const <SubscriptionRecord>[]), isEmpty);
    expect(ids([eligible.first]), ['today']);
    expect(ids(eligible.take(5)), [
      'today',
      'tomorrow',
      'same-day-a',
      'same-day-b',
      'beyond-thirty-days',
    ]);
    expect(ids([...excluded, ...eligible.reversed]), [
      'today',
      'tomorrow',
      'same-day-b',
      'same-day-a',
      'beyond-thirty-days',
    ]);
    expect(
      upcomingSubscriptionsForHome(
        [...excluded, ...eligible],
        today: today,
        limit: 10,
      ).map((record) => record.id),
      [
        'today',
        'tomorrow',
        'same-day-a',
        'same-day-b',
        'beyond-thirty-days',
        'sixth',
      ],
    );
  });

  testWidgets('账号和订阅页排序菜单返回明确选择', (tester) async {
    final account = _account('account-1', '测试平台');
    final subscription = _subscription(
      'subscription-1',
      serviceName: '测试订阅',
      nextRenewalOn: DateTime(2026, 9, 20),
    );
    var accountMode = RecordSortMode.oldestAdded;
    var subscriptionMode = RecordSortMode.renewalSoonest;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PageView(
              children: [
                AccountsPage(
                  accounts: [account],
                  subscriptions: [subscription],
                  displayMode: RecordDisplayMode.compactList,
                  sortMode: accountMode,
                  onSortModeChanged: (mode) =>
                      setState(() => accountMode = mode),
                  onAddAccount: () {},
                ),
                SubscriptionsPage(
                  accounts: [account],
                  subscriptions: [subscription],
                  displayMode: RecordDisplayMode.compactList,
                  sortMode: subscriptionMode,
                  onSortModeChanged: (mode) =>
                      setState(() => subscriptionMode = mode),
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
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('account-sort-mode-menu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('account-sort-newestAdded')),
    );
    await tester.pumpAndSettle();
    expect(accountMode, RecordSortMode.newestAdded);
    expect(
      find.byKey(const ValueKey('account-category-filter-全部')),
      findsOneWidget,
    );

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('subscription-sort-mode-menu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('subscription-sort-nameAscending')),
    );
    await tester.pumpAndSettle();
    expect(subscriptionMode, RecordSortMode.nameAscending);
    expect(find.text('排序：名称顺序'), findsOneWidget);
  });

  testWidgets('订阅只读视图明确说明排序需真实主密码', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubscriptionsPage(
            accounts: const [],
            subscriptions: const [],
            onSortModeChanged: null,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('subscription-sort-read-only-hint')),
      findsOneWidget,
    );
    expect(find.textContaining('真实主密码解锁'), findsOneWidget);
  });

  testWidgets('AppShell保存订阅排序后锁定并重新解锁仍保留', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
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

    await tester.tap(find.byKey(const ValueKey<String>('nav-subscriptions')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('subscription-sort-mode-menu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('subscription-sort-nameAscending')),
    );
    await tester.pumpAndSettle();
    expect(
      store.snapshot.preferences.subscriptionSortMode,
      RecordSortMode.nameAscending,
    );

    await tester.tap(find.byKey(const ValueKey<String>('nav-settings')));
    await tester.pumpAndSettle();
    final lockTile = find.descendant(
      of: find.byKey(const ValueKey<String>('settings-page')),
      matching: find.widgetWithText(ListTile, '立即锁定'),
    );
    expect(lockTile, findsOneWidget);
    await tester.ensureVisible(lockTile);
    await tester.tap(lockTile);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('unlock-master-password-field')),
      _testMasterPassword,
    );
    await tester.tap(find.byKey(const ValueKey<String>('unlock-vault-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('nav-subscriptions')));
    await tester.pumpAndSettle();

    expect(find.text('排序：名称顺序'), findsOneWidget);
  });

  testWidgets('V6首页显示本地安全条、叠层续费雷达与续费票据，仅有异常时显示提示条', (tester) async {
    final today = subscriptionDateOnly(DateTime.now());
    final account = _account('account-1', '测试平台');
    final subscriptions = <SubscriptionRecord>[
      _subscription(
        'subscription-current',
        serviceName: '本月订阅',
        nextRenewalOn: today,
      ),
      _subscription(
        'subscription-overdue',
        serviceName: '逾期订阅',
        nextRenewalOn: today.subtract(const Duration(days: 1)),
      ),
    ];
    final store = FakeVaultStore(
      configured: true,
      acceptedPassword: _testMasterPassword,
      snapshot: VaultSnapshot(
        nextAccountId: 2,
        accounts: [account],
        nextSubscriptionId: 3,
        subscriptions: subscriptions,
        recentAccountIds: [account.id],
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

    expect(find.textContaining('本地加密 ·'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('home-renewal-overview')),
      findsOneWidget,
    );
    final homePage = find.byKey(const ValueKey<String>('home-page'));
    final homeScrollable = find.descendant(
      of: homePage,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('home-renewal-tickets')),
      220,
      scrollable: homeScrollable.first,
    );
    expect(
      find.byKey(const ValueKey<String>('home-renewal-tickets')),
      findsOneWidget,
    );
    final recentAccount = find.byKey(
      const ValueKey<String>('home-dock-account-account-1'),
    );
    await tester.scrollUntilVisible(
      recentAccount,
      220,
      scrollable: homeScrollable.first,
    );
    expect(recentAccount, findsOneWidget);
    final exceptionStrip = find.byKey(
      const ValueKey<String>('home-renewal-exception-strip'),
    );
    await tester.scrollUntilVisible(
      exceptionStrip,
      -220,
      scrollable: homeScrollable.first,
    );
    await tester.pumpAndSettle();
    await tester.tap(exceptionStrip);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('subscription-filter-banner')),
      findsOneWidget,
    );
    expect(find.text('逾期订阅'), findsOneWidget);
  });

  testWidgets('V6首页无最近查看时显示指定引导并复用新增账号动作', (tester) async {
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

    final homePage = find.byKey(const ValueKey<String>('home-page'));
    final homeScrollable = find.descendant(
      of: homePage,
      matching: find.byType(Scrollable),
    );
    final recentEmpty = find.byKey(const ValueKey<String>('home-recent-empty'));
    await tester.scrollUntilVisible(
      recentEmpty,
      220,
      scrollable: homeScrollable,
    );
    expect(find.text('从第一张账号卡开始'), findsOneWidget);
    expect(find.text('记录平台账号，并关联你的订阅'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('home-renewal-exception-strip')),
      findsNothing,
    );

    final addAccount = find.byKey(
      const ValueKey<String>('home-add-account-tile'),
    );
    await Scrollable.ensureVisible(tester.element(addAccount), alignment: 0.35);
    await tester.pumpAndSettle();
    await tester.tap(addAccount);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('account-editor-page')),
      findsOneWidget,
    );
  });
}

AccountRecord _account(String id, String platformName, {String? category}) =>
    AccountRecord.fromDraft(
      id: id,
      draft: AccountDraft(platformName: platformName, category: category),
    );

SubscriptionRecord _subscription(
  String id, {
  String accountId = 'account-1',
  required String serviceName,
  required DateTime nextRenewalOn,
  SubscriptionStatus status = SubscriptionStatus.active,
}) => SubscriptionRecord.fromDraft(
  id: id,
  draft: SubscriptionDraft(
    accountId: accountId,
    details: SubscriptionDetailsDraft(
      serviceName: serviceName,
      firstSubscribedOn: DateTime(2025, 1, 1),
      nextRenewalOn: nextRenewalOn,
      status: status,
    ),
  ),
);
