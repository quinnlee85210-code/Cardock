import 'package:account_subscription_manager/core/preferences/record_display_mode.dart';
import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/core/theme/cardock_tokens.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/accounts/presentation/account_details_page.dart';
import 'package:account_subscription_manager/features/accounts/presentation/widgets/account_record_card.dart';
import 'package:account_subscription_manager/features/home/presentation/home_page.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscriptions_page.dart';
import 'package:account_subscription_manager/shared/widgets/cardock_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Custom 账号、订阅、续费与状态色进入关键组件', (tester) async {
    final theme = AppTheme.light(family: CardockThemeFamily.custom);
    final palette = theme.extension<CardockThemeExtension>()!.palette;
    final account = _account();
    final subscription = _subscription().cancel(
      cancelledOn: DateTime(2026, 8, 2),
      accessEndsOn: DateTime(2026, 9, 2),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                AccountRecordCard(
                  account: account,
                  subscriptions: const [],
                  displayMode: RecordDisplayMode.expandedCards,
                ),
                SubscriptionRecordCard(
                  subscription: subscription,
                  account: account,
                  displayMode: RecordDisplayMode.expandedCards,
                  showFullDetails: true,
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

    final accountIcon = find.byKey(
      const ValueKey<String>('account-brand-icon-account-1'),
    );
    final accountInitial = _renderedText(
      tester,
      find.descendant(
        of: accountIcon,
        matching: find.byKey(const ValueKey<String>('brand-monogram')),
      ),
    );
    expect(accountInitial.style?.color, palette.accountAccent);
    expect(
      _platformIconDecoration(tester, accountIcon).color,
      palette.accountIconBackground,
    );
    final subscriptionIcon = find.byKey(
      const ValueKey<String>('subscription-brand-icon-subscription-1'),
    );
    final subscriptionInitial = _renderedText(
      tester,
      find.descendant(
        of: subscriptionIcon,
        matching: find.byKey(const ValueKey<String>('brand-monogram')),
      ),
    );
    expect(subscriptionInitial.style?.color, palette.subscriptionAccent);
    expect(
      _platformIconDecoration(tester, subscriptionIcon).color,
      palette.subscriptionIconBackground,
    );

    final filledIcon = tester.widget<Icon>(
      find
          .descendant(
            of: find.byKey(
              const ValueKey<String>('subscription-card-subscription-1'),
            ),
            matching: find.byIcon(Icons.block_rounded),
          )
          .first,
    );
    expect(
      filledIcon.color,
      Color.alphaBlend(
        Colors.black.withValues(alpha: 0.24),
        palette.statusCancelled,
      ),
    );

    expect(_fieldColor(tester, '首次订阅：'), palette.fieldSubscription);
    expect(_fieldColor(tester, '下次续费：'), palette.renewalAccent);
    expect(_fieldColor(tester, '金额：'), palette.fieldCurrency);
    expect(_fieldColor(tester, '本机记录取消：'), palette.statusCancelled);
    expect(_fieldColor(tester, '权益截止：'), palette.statusDanger);
  });

  testWidgets('Custom 首页账号坞位读取账号图标底色', (tester) async {
    final theme = AppTheme.light(family: CardockThemeFamily.custom);
    final palette = theme.extension<CardockThemeExtension>()!.palette;
    final account = _account();

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: HomePage(
            accounts: [account],
            subscriptions: const [],
            recentAccounts: [account],
            autoLockSeconds: 60,
            onOpenAccount: (_) {},
            onOpenAccounts: () {},
            onOpenSubscriptions: (_) {},
            onOpenSubscription: (_) {},
            onSearch: () {},
            onLock: () {},
            onAddAccount: () {},
          ),
        ),
      ),
    );
    final amountMetric = find.byKey(
      const ValueKey<String>('home-metric-auto-renew-this-month'),
    );
    final amountText = _renderedText(
      tester,
      find.descendant(of: amountMetric, matching: find.text('暂无')),
    );
    expect(amountText.style?.color, Colors.white);

    await tester.drag(
      find.byKey(const ValueKey<String>('home-page')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();

    final dockAccount = find.byKey(
      const ValueKey<String>('home-dock-account-account-1'),
    );
    expect(dockAccount, findsOneWidget);
    final dockIcon = find.descendant(
      of: dockAccount,
      matching: find.byKey(
        const ValueKey<String>('home-account-brand-icon-account-1'),
      ),
    );
    final dockInitial = _renderedText(
      tester,
      find.descendant(
        of: dockIcon,
        matching: find.byKey(const ValueKey<String>('brand-monogram')),
      ),
    );
    expect(dockInitial.style?.color, palette.accountAccent);
    expect(
      _platformIconDecoration(tester, dockIcon).color,
      palette.accountIconBackground,
    );
  });

  testWidgets('Custom 账号紧凑列表和详情均读取账号图标底色', (tester) async {
    final theme = AppTheme.light(family: CardockThemeFamily.custom);
    final palette = theme.extension<CardockThemeExtension>()!.palette;
    final account = _account();

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: AccountRecordCard(
            account: account,
            subscriptions: const [],
            displayMode: RecordDisplayMode.compactList,
          ),
        ),
      ),
    );
    var accountIcon = find.byKey(
      const ValueKey<String>('account-brand-icon-account-1'),
    );
    expect(
      _platformIconDecoration(tester, accountIcon).color,
      palette.accountIconBackground,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: AccountDetailsPage(account: account, subscriptions: const []),
      ),
    );
    await tester.pump();
    accountIcon = find.byKey(
      const ValueKey<String>('account-detail-brand-icon-account-1'),
    );
    expect(
      _platformIconDecoration(tester, accountIcon).color,
      palette.accountIconBackground,
    );
  });

  testWidgets('固定三主题把账号语义色映射到离线品牌回退图标', (tester) async {
    final account = _account();
    for (final family in <CardockThemeFamily>[
      CardockThemeFamily.ceramicBlue,
      CardockThemeFamily.obsidianGold,
      CardockThemeFamily.mistCoral,
    ]) {
      final theme = AppTheme.light(family: family);
      final palette = theme.extension<CardockThemeExtension>()!.palette;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: AccountRecordCard(
              account: account,
              subscriptions: const [],
              displayMode: RecordDisplayMode.expandedCards,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final accountIcon = find.byKey(
        const ValueKey<String>('account-brand-icon-account-1'),
      );
      expect(
        _platformIconDecoration(tester, accountIcon).color,
        palette.accountIconBackground,
        reason: family.name,
      );
      final monogram = _renderedText(
        tester,
        find.descendant(
          of: accountIcon,
          matching: find.byKey(const ValueKey<String>('brand-monogram')),
        ),
      );
      expect(
        monogram.style?.color,
        _contrastRatio(palette.accountAccent, palette.accountIconBackground) >=
                3
            ? palette.accountAccent
            : palette.textPrimary,
        reason: family.name,
      );
    }
  });
}

Text _renderedText(WidgetTester tester, Finder finder) {
  final widget = tester.widget<Widget>(finder);
  if (widget is Text) {
    return widget;
  }
  final renderedText = find.descendant(of: finder, matching: find.byType(Text));
  expect(renderedText, findsOneWidget);
  return tester.widget<Text>(renderedText);
}

BoxDecoration _platformIconDecoration(WidgetTester tester, Finder scope) =>
    tester
            .widget<Container>(
              find.descendant(
                of: scope,
                matching: find.byKey(
                  const ValueKey<String>('cardock-platform-icon-container'),
                ),
              ),
            )
            .decoration!
        as BoxDecoration;

double _contrastRatio(Color left, Color right) {
  final lighter = left.computeLuminance() > right.computeLuminance()
      ? left.computeLuminance()
      : right.computeLuminance();
  final darker = left.computeLuminance() < right.computeLuminance()
      ? left.computeLuminance()
      : right.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}

Color _fieldColor(WidgetTester tester, String label) {
  final row = tester.widget<CardockFieldRow>(
    find.byWidgetPredicate(
      (widget) => widget is CardockFieldRow && widget.label == label,
    ),
  );
  return row.color;
}

AccountRecord _account() => AccountRecord.fromDraft(
  id: 'account-1',
  draft: AccountDraft(
    platformName: 'QV',
    username: '测试用户',
    loginAccount: 'alpha@example.test',
    boundPhone: '13800000000',
    boundEmail: 'alpha@example.test',
    password: 'test-only-password',
    website: 'https://example.test',
    notes: '本地测试备注',
  ),
);

SubscriptionRecord _subscription() => SubscriptionRecord.fromDraft(
  id: 'subscription-1',
  draft: SubscriptionDraft(
    accountId: 'account-1',
    details: SubscriptionDetailsDraft(
      serviceName: '测试订阅',
      amount: '18.8',
      currency: 'CNY',
      paymentMethod: '本地测试支付方式',
      firstSubscribedOn: DateTime(2026, 1, 2),
      nextRenewalOn: DateTime(2026, 9, 2),
    ),
  ),
);
