import 'dart:io';

import 'package:account_subscription_manager/core/preferences/record_display_mode.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/accounts/presentation/account_details_page.dart';
import 'package:account_subscription_manager/features/accounts/presentation/widgets/account_record_card.dart';
import 'package:account_subscription_manager/features/home/presentation/home_page.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscriptions_page.dart';
import 'package:account_subscription_manager/shared/widgets/cardock_platform_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('紧凑账号对邮箱、手机号与短用户名脱敏且Semantics不泄露明文', (tester) async {
    final semantics = tester.ensureSemantics();
    final records = <AccountRecord>[
      _account(
        id: 'email',
        platformName: '邮箱平台',
        loginAccount: 'sensitive.mail@example.invalid',
      ),
      _account(id: 'phone', platformName: '手机平台', loginAccount: '13800001234'),
      _account(id: 'short', platformName: '短名平台', username: 'xy'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (final record in records)
                AccountRecordCard(
                  account: record,
                  subscriptions: const [],
                  displayMode: RecordDisplayMode.compactList,
                  onOpen: () {},
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('账号摘要：se•••@example.invalid · 无订阅'), findsOneWidget);
    expect(find.text('账号摘要：138••••1234 · 无订阅'), findsOneWidget);
    expect(find.text('账号摘要：x• · 无订阅'), findsOneWidget);

    final semanticsDump = records
        .map(
          (record) => tester
              .getSemantics(
                find.byKey(ValueKey<String>('account-card-${record.id}')),
              )
              .toStringDeep(),
        )
        .join('\n');
    for (final secret in <String>[
      'sensitive.mail@example.invalid',
      '13800001234',
      'xy',
    ]) {
      expect(find.textContaining(secret), findsNothing, reason: secret);
      expect(semanticsDump, isNot(contains(secret)), reason: secret);
    }
    expect(semanticsDump, contains('se•••@example.invalid'));
    expect(semanticsDump, contains('138••••1234'));
    expect(semanticsDump, contains('x•'));
    final iconSemantics = tester
        .getSemantics(
          find.byKey(const ValueKey<String>('account-brand-icon-email')),
        )
        .toStringDeep();
    expect(iconSemantics, contains('邮箱平台图标'));
    expect(iconSemantics, isNot(contains('账号摘要')));
    expect(iconSemantics, isNot(contains('sensitive.mail')));
    semantics.dispose();
  });

  testWidgets('紧凑行常规字号符合V6高度，200%字体自然增高且不溢出', (tester) async {
    await _setViewport(tester, const Size(320, 1200));
    final account = _account(
      id: 'size',
      platformName: '一个名称较长的平台',
      loginAccount: 'layout@example.invalid',
    );
    final subscription = _subscription(
      id: 'size',
      accountId: account.id,
      status: SubscriptionStatus.cancelled,
    );

    Future<void> pumpCards() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AccountRecordCard(
                account: account,
                subscriptions: [subscription],
                displayMode: RecordDisplayMode.compactList,
                onOpen: () {},
              ),
              const SizedBox(height: 12),
              SubscriptionRecordCard(
                subscription: subscription,
                account: account,
                displayMode: RecordDisplayMode.compactList,
                onOpen: () {},
                onEdit: null,
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

    await pumpCards();
    await tester.pump();
    final accountCard = find.byKey(const ValueKey<String>('account-card-size'));
    final subscriptionCard = find.byKey(
      const ValueKey<String>('subscription-card-size'),
    );
    final accountHeight = tester.getSize(accountCard).height;
    final subscriptionHeight = tester.getSize(subscriptionCard).height;

    expect(accountHeight, 68);
    expect(subscriptionHeight, inInclusiveRange(72, 84));
    expect(
      find.descendant(
        of: subscriptionCard,
        matching: find.byIcon(Icons.block_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: subscriptionCard, matching: find.text('已取消')),
      findsOneWidget,
    );

    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(accountCard).height, greaterThan(accountHeight));
    expect(
      tester.getSize(subscriptionCard).height,
      greaterThan(subscriptionHeight),
    );
  });

  testWidgets('账号、详情、订阅和首页接入名称分类并保留未知字母标回退', (tester) async {
    final known = _account(id: 'apple', platformName: 'Apple', category: '办公');
    final unknown = _account(
      id: 'unknown',
      platformName: 'Qzxv Vnmp',
      category: '未知',
    );
    final knownSubscription = _subscription(
      id: 'known',
      accountId: known.id,
      status: SubscriptionStatus.active,
      serviceName: 'Apple',
    );
    final unknownSubscription = _subscription(
      id: 'unknown',
      accountId: unknown.id,
      status: SubscriptionStatus.active,
      serviceName: 'Qzxv Vnmp',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              AccountRecordCard(
                account: known,
                subscriptions: const [],
                displayMode: RecordDisplayMode.compactList,
              ),
              AccountRecordCard(
                account: unknown,
                subscriptions: const [],
                displayMode: RecordDisplayMode.compactList,
              ),
              SubscriptionRecordCard(
                subscription: knownSubscription,
                account: known,
                displayMode: RecordDisplayMode.compactList,
                onEdit: null,
                onMarkRenewed: null,
                onSnoozeReminder: null,
                onCancelSubscription: null,
                onRestoreSubscription: null,
                onDeleteSubscription: null,
              ),
              SubscriptionRecordCard(
                subscription: unknownSubscription,
                account: unknown,
                displayMode: RecordDisplayMode.compactList,
                onEdit: null,
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
    await tester.pump();

    final accountKnownIcon = tester.widget<CardockResolvedPlatformIcon>(
      find.byKey(const ValueKey<String>('account-brand-icon-apple')),
    );
    expect(accountKnownIcon.name, 'Apple');
    expect(accountKnownIcon.category, '办公');
    expect(accountKnownIcon.size, 38);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('account-brand-icon-unknown')),
        matching: find.text('QV'),
      ),
      findsOneWidget,
    );
    final subscriptionKnownIcon = tester.widget<CardockResolvedPlatformIcon>(
      find.byKey(const ValueKey<String>('subscription-brand-icon-known')),
    );
    expect(subscriptionKnownIcon.name, 'Apple');
    expect(subscriptionKnownIcon.category, isNull);
    expect(subscriptionKnownIcon.size, 36);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('subscription-brand-icon-unknown'),
        ),
        matching: find.text('QV'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AccountDetailsPage(account: known, subscriptions: const []),
      ),
    );
    await tester.pump();
    final detailIcon = tester.widget<CardockResolvedPlatformIcon>(
      find.byKey(const ValueKey<String>('account-detail-brand-icon-apple')),
    );
    expect(detailIcon.name, 'Apple');
    expect(detailIcon.category, '办公');
    expect(detailIcon.size, 48);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          accounts: [known],
          subscriptions: const [],
          recentAccounts: [known],
          autoLockSeconds: 60,
          onOpenAccount: (_) {},
          onOpenAccounts: () {},
          onOpenSubscriptions: (_) {},
          onOpenSubscription: (_) {},
          onSearch: () {},
          onLock: null,
          onAddAccount: () {},
        ),
      ),
    );
    await tester.pump();
    final homeIcon = find.byKey(
      const ValueKey<String>('home-account-brand-icon-apple'),
    );
    final homeScrollable = find.descendant(
      of: find.byKey(const ValueKey<String>('home-page')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.scrollUntilVisible(
      homeIcon,
      400,
      scrollable: homeScrollable.first,
    );
    final homeKnownIcon = tester.widget<CardockResolvedPlatformIcon>(homeIcon);
    expect(homeKnownIcon.name, 'Apple');
    expect(homeKnownIcon.category, '办公');
    expect(homeKnownIcon.size, 24);
  });

  test('模糊匹配结构上只在账号编辑器开启，列表与首页路径不调用', () {
    final editor = File(
      'lib/features/accounts/presentation/account_editor_page.dart',
    ).readAsStringSync();
    expect(
      RegExp(r'includeSuggestions:\s*true').allMatches(editor),
      hasLength(1),
    );
    for (final path in <String>[
      'lib/features/accounts/presentation/widgets/account_record_card.dart',
      'lib/features/accounts/presentation/account_details_page.dart',
      'lib/features/subscriptions/presentation/subscriptions_page.dart',
      'lib/features/home/presentation/home_page.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('includeSuggestions: true')), reason: path);
      expect(source, isNot(contains('CardockBrandMatcher(')), reason: path);
    }
    final resolvedWidget = File(
      'lib/shared/widgets/cardock_platform_icon.dart',
    ).readAsStringSync();
    expect(resolvedWidget, contains('includeSuggestions: false'));
  });
}

AccountRecord _account({
  required String id,
  required String platformName,
  String? category,
  String? username,
  String? loginAccount,
}) => AccountRecord.fromDraft(
  id: id,
  draft: AccountDraft(
    platformName: platformName,
    category: category,
    username: username,
    loginAccount: loginAccount,
  ),
);

SubscriptionRecord _subscription({
  required String id,
  required String accountId,
  required SubscriptionStatus status,
  String serviceName = '名称较长的订阅服务',
}) => SubscriptionRecord.fromDraft(
  id: id,
  draft: SubscriptionDraft(
    accountId: accountId,
    details: SubscriptionDetailsDraft(
      serviceName: serviceName,
      amount: '128.80',
      firstSubscribedOn: DateTime(2026, 1, 1),
      nextRenewalOn: DateTime(2026, 9, 18),
      status: status,
    ),
  ),
);

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
