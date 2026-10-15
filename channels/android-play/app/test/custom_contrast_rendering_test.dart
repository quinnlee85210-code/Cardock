import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/core/theme/cardock_tokens.dart';
import 'package:account_subscription_manager/core/theme/custom_theme.dart';
import 'package:account_subscription_manager/features/home/presentation/home_page.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/shared/widgets/cardock_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Custom 默认值在实际总览合成面、日期徽标和错误正文上满足对比度', () {
    expect(CardockCustomTheme.defaults.validate(), isEmpty);

    for (final brightness in Brightness.values) {
      final colors = CardockCustomTheme.defaults.colorsFor(brightness);
      final overviewContent = cardockOnGradientColorFor(
        colors.overviewStart,
        colors.overviewEnd,
      );
      for (final endpoint in <Color>[
        colors.overviewStart,
        colors.overviewEnd,
      ]) {
        final primaryMetricSurface = Color.alphaBlend(
          Colors.black.withValues(alpha: 0.18),
          endpoint,
        );
        final miniMetricSurface = Color.alphaBlend(
          Colors.white.withValues(alpha: 0.10),
          endpoint,
        );
        expect(
          cardockContrastRatio(overviewContent, primaryMetricSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          cardockContrastRatio(overviewContent, miniMetricSurface),
          greaterThanOrEqualTo(4.5),
        );
      }

      final badgeContent = cardockOnColorFor(colors.brandPrimary);
      expect(
        cardockContrastRatio(badgeContent, colors.brandPrimary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        cardockContrastRatio(
          badgeContent,
          cardockContrastPressedColorFor(colors.brandPrimary),
        ),
        greaterThanOrEqualTo(4.5),
      );

      final theme = AppTheme.build(CardockThemeFamily.custom, brightness);
      final palette = theme.extension<CardockThemeExtension>()!.palette;
      expect(palette.textTertiary, colors.textSecondary);
      for (final surface in <Color>[
        palette.background,
        palette.surface,
        palette.surfaceAlt,
      ]) {
        expect(
          cardockContrastRatio(theme.colorScheme.error, surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });

  test('保存校验覆盖总览实际合成面与日期徽标前景', () {
    final invalidOverview = CardockCustomTheme.defaults.copyWith(
      light: CardockCustomTheme.defaults.light.copyWith(
        overviewStart: const Color(0xFF767676),
        overviewEnd: const Color(0xFF767676),
      ),
    );
    expect(
      invalidOverview.validate().map((issue) => issue.token),
      contains('light.homeOverview.overviewStart/miniMetricOnColor'),
    );

    final invalidBadge = CardockCustomTheme.defaults.copyWith(
      light: CardockCustomTheme.defaults.light.copyWith(
        brandPrimary: const Color(0xFF777777),
      ),
    );
    expect(
      invalidBadge.validate().map((issue) => issue.token),
      contains('light.brandNavigation.brandPrimary/dateBadgeOnColor'),
    );
  });

  testWidgets('Custom 总览小字号使用不透明可读前景且固定主题保持原透明度', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<Color?> pumpAndRead(CardockThemeFamily family) async {
      final theme = AppTheme.light(family: family);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SizedBox(
              width: 390,
              child: CardockOverviewDock(
                metrics: _metrics(),
                dateLabel: '2026年8月2日',
                earliestLabel: '最近续费：8月8日',
                timelineLabel: '8月15日',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return _renderedText(tester, find.text('本月金额')).style?.color;
    }

    final customTheme = AppTheme.light(family: CardockThemeFamily.custom);
    final customPalette = customTheme
        .extension<CardockThemeExtension>()!
        .palette;
    expect(
      await pumpAndRead(CardockThemeFamily.custom),
      customPalette.gradientContent,
    );

    final fixedTheme = AppTheme.light(family: CardockThemeFamily.ceramicBlue);
    final fixedPalette = fixedTheme.extension<CardockThemeExtension>()!.palette;
    expect(
      await pumpAndRead(CardockThemeFamily.ceramicBlue),
      fixedPalette.gradientContent.withValues(alpha: 0.7),
    );
  });

  testWidgets('V6深色雷达金额保持白色主数字与较小次级币种符号', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<(TextStyle?, TextStyle?)> pumpAndRead(
      CardockThemeFamily family,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(family: family),
          home: Scaffold(
            body: HomePage(
              accounts: const [],
              subscriptions: <SubscriptionRecord>[_subscription()],
              recentAccounts: const [],
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
      await tester.pumpAndSettle();
      return (
        _renderedText(
          tester,
          find.byKey(const ValueKey<String>('home-renewal-primary-symbol')),
        ).style,
        _renderedText(
          tester,
          find.byKey(const ValueKey<String>('home-renewal-primary-value')),
        ).style,
      );
    }

    for (final family in [
      CardockThemeFamily.custom,
      CardockThemeFamily.ceramicBlue,
    ]) {
      final styles = await pumpAndRead(family);
      final palette = AppTheme.light(
        family: family,
      ).extension<CardockThemeExtension>()!.palette;
      expect(styles.$1?.color, palette.gradientContent.withValues(alpha: 0.74));
      expect(styles.$2?.color, palette.gradientContent);
      expect(styles.$1!.fontSize!, lessThan(styles.$2!.fontSize!));
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

List<CardockOverviewMetric> _metrics() => <CardockOverviewMetric>[
  CardockOverviewMetric(
    id: 'all-active',
    label: '有效订阅',
    value: '3项',
    onTap: () {},
  ),
  CardockOverviewMetric(
    id: 'renewing-within-thirty-days',
    label: '30天内续费',
    value: '2项',
    onTap: () {},
  ),
  CardockOverviewMetric(
    id: 'auto-renew-this-month',
    label: '本月金额',
    value: 'CNY 18.80',
    onTap: () {},
  ),
  CardockOverviewMetric(
    id: 'renewals-next-month',
    label: '次月续费总额',
    value: '¥18.80',
    onTap: () {},
  ),
];

SubscriptionRecord _subscription() {
  final today = DateTime.now();
  return SubscriptionRecord.fromDraft(
    id: 'contrast-subscription',
    draft: SubscriptionDraft(
      accountId: 'missing-account',
      details: SubscriptionDetailsDraft(
        serviceName: '对比度测试订阅',
        amount: '18.8',
        currency: 'CNY',
        firstSubscribedOn: today.subtract(const Duration(days: 30)),
        nextRenewalOn: today,
      ),
    ),
  );
}
