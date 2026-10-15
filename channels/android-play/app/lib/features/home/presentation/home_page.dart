import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../../../l10n/translations_records.dart';

import '../../../core/preferences/language_preferences.dart';
import '../../../core/exchange_rates/semiannual_cny_exchange_rates.dart';
import '../../../core/theme/cardock_tokens.dart';
import '../../../shared/widgets/cardock_platform_icon.dart';
import '../../../shared/widgets/cardock_ui.dart';
import '../../accounts/domain/account_record.dart';
import '../../subscriptions/domain/subscription_list_preset.dart';
import '../../subscriptions/domain/subscription_record.dart';
import '../../subscriptions/domain/subscription_expense_record.dart';

/// 返回首页要展示的最近未来续费项目。
///
/// 逾期项目继续由首页逾期统计承接；暂停、取消和到期记录不属于待续费。
/// 同一天的记录保持保险库中的原顺序，避免首页在重建时无故跳位。
List<SubscriptionRecord> upcomingSubscriptionsForHome(
  Iterable<SubscriptionRecord> subscriptions, {
  DateTime? today,
  int limit = 5,
}) {
  if (limit <= 0) {
    return const <SubscriptionRecord>[];
  }
  final date = DateUtils.dateOnly(today ?? DateTime.now());
  final candidates = <({int sourceIndex, SubscriptionRecord subscription})>[];
  var sourceIndex = 0;
  for (final subscription in subscriptions) {
    final currentIndex = sourceIndex;
    sourceIndex += 1;
    final renewalDate = DateUtils.dateOnly(subscription.nextRenewalOn);
    if (subscription.status != SubscriptionStatus.active ||
        renewalDate.isBefore(date)) {
      continue;
    }
    candidates.add((sourceIndex: currentIndex, subscription: subscription));
  }
  candidates.sort((left, right) {
    final dateOrder = DateUtils.dateOnly(
      left.subscription.nextRenewalOn,
    ).compareTo(DateUtils.dateOnly(right.subscription.nextRenewalOn));
    if (dateOrder != 0) {
      return dateOrder;
    }
    return left.sourceIndex.compareTo(right.sourceIndex);
  });
  return List<SubscriptionRecord>.unmodifiable(
    candidates.take(limit).map((candidate) => candidate.subscription),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({
    required this.accounts,
    required this.subscriptions,
    required this.recentAccounts,
    required this.autoLockSeconds,
    required this.onOpenAccount,
    required this.onOpenAccounts,
    required this.onOpenSubscriptions,
    required this.onOpenSubscription,
    required this.onSearch,
    required this.onLock,
    required this.onAddAccount,
    this.onOpenAllSubscriptions,
    this.insightsSummary,
    this.expenses = const [],
    this.onOpenMonthlyExpenses,
    super.key,
  });

  final Widget? insightsSummary;
  final List<SubscriptionExpenseRecord> expenses;
  final VoidCallback? onOpenMonthlyExpenses;
  final List<AccountRecord> accounts;
  final List<SubscriptionRecord> subscriptions;
  final List<AccountRecord> recentAccounts;
  final int autoLockSeconds;
  final ValueChanged<AccountRecord> onOpenAccount;
  final VoidCallback onOpenAccounts;
  final ValueChanged<SubscriptionListPreset> onOpenSubscriptions;
  final VoidCallback? onOpenAllSubscriptions;
  final ValueChanged<SubscriptionRecord> onOpenSubscription;
  final VoidCallback onSearch;
  final VoidCallback? onLock;
  final VoidCallback? onAddAccount;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final thisMonth = expenses
        .where(
          (expense) =>
              !expense.isDeleted &&
              expense.occurredOn.year == today.year &&
              expense.occurredOn.month == today.month,
        )
        .toList();
    final withinThirtyDays = subscriptionsForPreset(
      subscriptions,
      SubscriptionListPreset.renewingWithinThirtyDays,
      today: today,
    );
    final nextMonth = subscriptionsForPreset(
      subscriptions,
      SubscriptionListPreset.renewalsNextMonth,
      today: today,
    );
    final overdue = subscriptionsForPreset(
      subscriptions,
      SubscriptionListPreset.overdue,
      today: today,
    );
    final amountEstimate = CnyAmountEstimate.fromInputs(
      thisMonth.map(
        (expense) => CurrencyAmountInput(
          currency: expense.currency,
          amount: expense.amount,
          refund: expense.kind == SubscriptionExpenseKind.refund,
        ),
      ),
    );
    final nextMonthAmountEstimate = CnyAmountEstimate.fromInputs(
      nextMonth.map(
        (subscription) => CurrencyAmountInput(
          currency: subscription.currency,
          amount: subscription.isFormalSubscription
              ? subscription.amount
              : null,
        ),
      ),
    );
    final disclosedSubscriptions = <CurrencyAmountInput>[
      for (final expense in thisMonth)
        CurrencyAmountInput(currency: expense.currency),
      for (final subscription in nextMonth)
        CurrencyAmountInput(currency: subscription.currency),
    ];
    final usesForeignCurrency = disclosedSubscriptions.any(
      (subscription) => subscription.currency != 'CNY',
    );
    final usesTwd = disclosedSubscriptions.any(
      (subscription) => subscription.currency == 'TWD',
    );
    final excludedAmountCount =
        amountEstimate.excludedCount + nextMonthAmountEstimate.excludedCount;
    final upcoming = upcomingSubscriptionsForHome(subscriptions, today: today);
    final renewalDates =
        withinThirtyDays
            .map(
              (subscription) => DateUtils.dateOnly(subscription.nextRenewalOn),
            )
            .toSet()
            .toList(growable: false)
          ..sort();

    return ListView(
      key: const ValueKey<String>('home-page'),
      padding: const EdgeInsets.fromLTRB(
        CardockLayout.screenHorizontal,
        0,
        CardockLayout.screenHorizontal,
        120,
      ),
      children: [
        _HomeBrandHeader(
          accountCount: accounts.length,
          subscriptionCount: subscriptions.length,
          onSearch: onSearch,
          onLock: onLock,
        ),
        const SizedBox(height: 9),
        _HomeSecurityStrip(autoLockSeconds: autoLockSeconds, onLock: onLock),
        const SizedBox(height: 20),
        _HomeRenewalOverview(
          thisMonthEstimate: amountEstimate,
          nextMonthEstimate: nextMonthAmountEstimate,
          withinThirtyDaysCount: withinThirtyDays.length,
          renewalDates: renewalDates,
          today: today,
          onOpenThisMonth:
              onOpenMonthlyExpenses ??
              () =>
                  onOpenSubscriptions(SubscriptionListPreset.renewalsThisMonth),
          onOpenNextMonth: () =>
              onOpenSubscriptions(SubscriptionListPreset.renewalsNextMonth),
          onOpenThirtyDays: () => onOpenSubscriptions(
            SubscriptionListPreset.renewingWithinThirtyDays,
          ),
        ),
        if (usesForeignCurrency || excludedAmountCount > 0) ...[
          const SizedBox(height: 9),
          _ExchangeRateDisclosure(
            excludedCount: excludedAmountCount,
            usesTwd: usesTwd,
          ),
        ],
        if (overdue.isNotEmpty) ...[
          const SizedBox(height: 12),
          _HomeExceptionStrip(
            count: overdue.length,
            onTap: () => onOpenSubscriptions(SubscriptionListPreset.overdue),
          ),
        ],
        const SizedBox(height: 19),
        _HomeSectionHeader(
          title: context.tr('近期续费'),
          subtitle: upcoming.isEmpty
              ? context.tr('未来30天暂无续费')
              : context.tr('未来{count}项 · 左右滑动查看', <String, Object?>{
                  'count': upcoming.length,
                }),
          action: context.tr('30天明细'),
          onTap: () => onOpenSubscriptions(
            SubscriptionListPreset.renewingWithinThirtyDays,
          ),
        ),
        const SizedBox(height: 9),
        _RenewalTickets(
          subscriptions: upcoming,
          accounts: accounts,
          today: today,
          onOpenSubscription: onOpenSubscription,
        ),
        const SizedBox(height: 18),
        _HomeSectionHeader(
          title: context.tr('最近查看'),
          subtitle: context.tr(
            recentAccounts.isEmpty ? '还没有最近查看的账号' : '继续处理最近访问的账号',
          ),
          action: context.tr('全部账号'),
          onTap: onOpenAccounts,
        ),
        const SizedBox(height: 10),
        _AccountDock(
          accounts: recentAccounts.take(4).toList(growable: false),
          onOpenAccount: onOpenAccount,
          onAddAccount: onAddAccount,
        ),
        ?insightsSummary,
      ],
    );
  }

  static ({String? symbol, String value}) _amountParts(
    BuildContext context,
    CnyAmountEstimate estimate,
  ) {
    if (estimate.lineCount == 0) {
      return (symbol: null, value: context.tr('暂无'));
    }
    if (!estimate.hasConvertedAmount) {
      return (symbol: null, value: context.tr('待换算'));
    }
    return (
      symbol: context.l10n.language == CardockLanguage.simplifiedChinese
          ? '¥'
          : 'CN¥',
      value: _formatAmount(estimate.totalCny),
    );
  }

  static String _formatAmount(double value) {
    final fixed = value.toStringAsFixed(2);
    return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
  }
}

class _ExchangeRateDisclosure extends StatelessWidget {
  const _ExchangeRateDisclosure({
    required this.excludedCount,
    required this.usesTwd,
  });

  final int excludedCount;
  final bool usesTwd;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final details = <String>[
      context.tr('汇率基准：{period}116个官方公布日算术平均', <String, Object?>{
        'period': context.tr(SemiannualCnyExchangeRates.periodLabel),
      }),
      if (usesTwd) context.tr('TWD为114个重合日的官方交叉参考'),
      if (excludedCount > 0)
        context.tr('{count}项未计入', <String, Object?>{'count': excludedCount}),
      context.tr('运行时离线'),
    ];
    final message = details.join(' · ');
    return Semantics(
      label: message,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.currency_exchange_rounded,
              size: 14,
              color: palette.textTertiary,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              translate: false,
              style: TextStyle(
                color: palette.textTertiary,
                fontSize: CardockTypography.caption,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeSecurityStrip extends StatelessWidget {
  const _HomeSecurityStrip({
    required this.autoLockSeconds,
    required this.onLock,
  });

  final int autoLockSeconds;
  final VoidCallback? onLock;

  String _lockLabel(BuildContext context) {
    if (autoLockSeconds <= 0) return context.tr('离开应用后立即锁定');
    if (autoLockSeconds < 60) {
      return context.tr('{count}秒后自动锁定', <String, Object?>{
        'count': autoLockSeconds,
      });
    }
    return context.tr('{count}分钟后自动锁定', <String, Object?>{
      'count': autoLockSeconds ~/ 60,
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final lockLabel = _lockLabel(context);
    return Semantics(
      button: onLock != null,
      label: context.tr('本地加密，{lock}', <String, Object?>{'lock': lockLabel}),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey<String>('home-local-encryption-strip'),
          onTap: onLock,
          borderRadius: BorderRadius.circular(CardockRadius.input),
          child: Ink(
            height: CardockLayout.securityRailHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: palette.statusNormal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(CardockRadius.input),
              border: Border.all(
                color: palette.statusNormal.withValues(alpha: 0.30),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 18,
                  color: palette.statusNormal,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    context.tr('本地加密 · {lock}', <String, Object?>{
                      'lock': lockLabel,
                    }),
                    translate: false,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.adjust_rounded,
                  color: palette.statusNormal,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Size _measureHomeText(
  BuildContext context,
  String text,
  TextStyle style, {
  double maxWidth = double.infinity,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
  )..layout(maxWidth: maxWidth);
  final size = painter.size;
  painter.dispose();
  return size;
}

class _HomeRenewalOverview extends StatelessWidget {
  const _HomeRenewalOverview({
    required this.thisMonthEstimate,
    required this.nextMonthEstimate,
    required this.withinThirtyDaysCount,
    required this.renewalDates,
    required this.today,
    required this.onOpenThisMonth,
    required this.onOpenNextMonth,
    required this.onOpenThirtyDays,
  });

  final CnyAmountEstimate thisMonthEstimate;
  final CnyAmountEstimate nextMonthEstimate;
  final int withinThirtyDaysCount;
  final List<DateTime> renewalDates;
  final DateTime today;
  final VoidCallback onOpenThisMonth;
  final VoidCallback onOpenNextMonth;
  final VoidCallback onOpenThirtyDays;

  @override
  Widget build(BuildContext context) {
    final thisMonthAmount = HomePage._amountParts(context, thisMonthEstimate);
    final nextMonthAmount = HomePage._amountParts(context, nextMonthEstimate);
    final extension = context.cardockTheme;
    final palette = extension.palette;
    final materialProfile = extension.material;
    final heroHeading = palette.gradientContent.withValues(alpha: 0.82);
    final heroSecondary = palette.gradientContent.withValues(alpha: 0.74);
    final heroContent = palette.gradientContent;
    final visibleDates = renewalDates.take(5).toList(growable: false);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final heroTitle = context.tr('30天续费雷达');
    final heroDate = localizedRecordDate(context.l10n.language, today);
    final renewalSummary = visibleDates.isEmpty
        ? context.tr('未来30天暂无具体续费日期')
        : context.tr('最近{date} · {countLabel}', <String, Object?>{
            'date': localizedMonthDay(
              context.l10n.language,
              visibleDates.first,
            ),
            'countLabel': localizedRenewalDayCount(
              context.l10n.language,
              renewalDates.length,
            ),
          });
    final heroTitleStyle = TextStyle(
      color: heroHeading,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    final heroDateStyle = TextStyle(
      color: heroSecondary,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
    final summaryStyle = TextStyle(color: heroSecondary, fontSize: 10);
    final railStyle = TextStyle(fontSize: 8.5);

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth > 36
            ? constraints.maxWidth - 36
            : 1.0;
        final dateSize = _measureHomeText(context, heroDate, heroDateStyle);
        final titleSize = _measureHomeText(context, heroTitle, heroTitleStyle);
        final stackHeroHeading =
            textScale >= 1.8 || titleSize.width + dateSize.width > contentWidth;
        final headerHeight = stackHeroHeading
            ? _measureHomeText(
                    context,
                    heroTitle,
                    heroTitleStyle,
                    maxWidth: contentWidth,
                  ).height +
                  3 +
                  _measureHomeText(
                    context,
                    heroDate,
                    heroDateStyle,
                    maxWidth: contentWidth,
                  ).height
            : (() {
                final titleWidth = contentWidth > dateSize.width
                    ? contentWidth - dateSize.width
                    : 1.0;
                final titleHeight = _measureHomeText(
                  context,
                  heroTitle,
                  heroTitleStyle,
                  maxWidth: titleWidth,
                ).height;
                return titleHeight > dateSize.height
                    ? titleHeight
                    : dateSize.height;
              })();
        final metricHeight =
            (48.0 + ((textScale - 1).clamp(0.0, 1.0) * 34.0)) * 2 + 7;
        final summaryHeight = _measureHomeText(
          context,
          renewalSummary,
          summaryStyle,
          maxWidth: contentWidth,
        ).height;
        var railLabelHeight = 0.0;
        if (visibleDates.isNotEmpty) {
          final railCellWidth = contentWidth / visibleDates.length;
          for (final date in visibleDates) {
            final height = _measureHomeText(
              context,
              localizedMonthDay(context.l10n.language, date),
              railStyle,
              maxWidth: railCellWidth,
            ).height;
            if (height > railLabelHeight) railLabelHeight = height;
          }
        }
        final railHeight = visibleDates.isEmpty
            ? 2.0
            : 13 + 4 + railLabelHeight;
        final baseHeroHeight =
            CardockLayout.heroHeight +
            ((textScale - 1).clamp(0.0, 1.0) * 430.0);
        final contentDrivenHeight =
            30 +
            headerHeight +
            11 +
            metricHeight +
            8 +
            summaryHeight +
            8 +
            railHeight;
        final heroHeight = baseHeroHeight > contentDrivenHeight
            ? baseHeroHeight
            : contentDrivenHeight;

        return SizedBox(
          key: const ValueKey<String>('home-renewal-overview'),
          height: heroHeight + 11,
          child: Stack(
            children: [
              Positioned(
                left: 11,
                right: 11,
                top: 0,
                height: heroHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.surfaceAlt.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(CardockRadius.hero),
                    border: Border.all(
                      color: palette.primary.withValues(alpha: 0.18),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 5,
                right: 5,
                top: 5,
                height: heroHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.overviewStart,
                    borderRadius: BorderRadius.circular(CardockRadius.hero),
                    border: Border.all(
                      color: palette.primary.withValues(alpha: 0.24),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 11,
                height: heroHeight,
                child: Semantics(
                  button: true,
                  label: context
                      .tr('未来30天有{countLabel}续费，打开30天续费明细', <String, Object?>{
                        'countLabel': localizedSubscriptionItemCount(
                          context.l10n.language,
                          withinThirtyDaysCount,
                        ),
                      }),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onOpenThirtyDays,
                      borderRadius: BorderRadius.circular(CardockRadius.hero),
                      child: Ink(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            CardockRadius.hero,
                          ),
                          border: Border.all(
                            color: palette.primary.withValues(alpha: 0.52),
                          ),
                          gradient: palette.overviewGradient,
                          boxShadow: materialProfile.heroShadows
                              .map((layer) => layer.toBoxShadow())
                              .toList(growable: false),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            CardockRadius.hero,
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                left: 0,
                                top: 24,
                                bottom: 24,
                                width: 4,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: palette.primary,
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow:
                                        materialProfile.lineDecorationOpacity >
                                            0
                                        ? <BoxShadow>[
                                            BoxShadow(
                                              color: materialProfile
                                                  .lineGlowColor
                                                  .withValues(
                                                    alpha: materialProfile
                                                        .lineDecorationOpacity,
                                                  ),
                                              blurRadius:
                                                  materialProfile.lineGlowBlur,
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: -18,
                                bottom: -26,
                                child: ExcludeSemantics(
                                  child: Opacity(
                                    opacity:
                                        materialProfile.heroWatermarkOpacity,
                                    child: CardockBrandMark(
                                      showWordmark: false,
                                      iconSize: 126,
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  16,
                                  18,
                                  14,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (stackHeroHeading)
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            heroTitle,
                                            translate: false,
                                            style: heroTitleStyle,
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            heroDate,
                                            translate: false,
                                            style: heroDateStyle,
                                          ),
                                        ],
                                      )
                                    else
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              heroTitle,
                                              translate: false,
                                              style: heroTitleStyle,
                                            ),
                                          ),
                                          Text(
                                            heroDate,
                                            translate: false,
                                            style: heroDateStyle,
                                          ),
                                        ],
                                      ),
                                    const SizedBox(height: 11),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '未来30天',
                                                style: TextStyle(
                                                  color: heroSecondary,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .baseline,
                                                  textBaseline:
                                                      TextBaseline.alphabetic,
                                                  children: [
                                                    Text(
                                                      '$withinThirtyDaysCount',
                                                      translate: false,
                                                      key: const ValueKey<String>(
                                                        'home-metric-renewing-within-thirty-days',
                                                      ),
                                                      style: TextStyle(
                                                        color: heroContent,
                                                        fontSize:
                                                            CardockTypography
                                                                .heroNumber,
                                                        height: 0.95,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontFeatures: <FontFeature>[
                                                          FontFeature.tabularFigures(),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 7),
                                                    Text(
                                                      '项续费',
                                                      style: TextStyle(
                                                        color: heroContent,
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          children: [
                                            _HeroAmountMetric(
                                              key: const ValueKey<String>(
                                                'home-metric-auto-renew-this-month',
                                              ),
                                              label: '本月订阅续费总额',
                                              amount: thisMonthAmount,
                                              onTap: onOpenThisMonth,
                                            ),
                                            const SizedBox(height: 7),
                                            _HeroAmountMetric(
                                              key: const ValueKey<String>(
                                                'home-metric-renewals-next-month',
                                              ),
                                              label: '次月续费总额',
                                              amount: nextMonthAmount,
                                              onTap: onOpenNextMonth,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    Text(
                                      renewalSummary,
                                      translate: false,
                                      style: summaryStyle,
                                    ),
                                    const SizedBox(height: 8),
                                    _RenewalDateRail(dates: visibleDates),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroAmountMetric extends StatelessWidget {
  const _HeroAmountMetric({
    required this.label,
    required this.amount,
    required this.onTap,
    super.key,
  });

  final String label;
  final ({String? symbol, String value}) amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final extension = context.cardockTheme;
    final palette = extension.palette;
    final materialProfile = extension.material;
    final content = palette.gradientContent;
    final secondary = palette.gradientContent.withValues(alpha: 0.74);
    final localizedLabel = context.tr(label);
    return Semantics(
      button: true,
      label: context.tr('{label}，{amount}', <String, Object?>{
        'label': localizedLabel,
        'amount': '${amount.symbol ?? ''}${amount.value}',
      }),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 116,
          height: 48.0 + ((textScale - 1).clamp(0.0, 1.0) * 34.0),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: materialProfile.heroMiniMetricFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: materialProfile.heroMiniMetricBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizedLabel,
                translate: false,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: secondary, fontSize: 8.5),
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (amount.symbol != null)
                    Text(
                      amount.symbol!,
                      translate: false,
                      key: ValueKey<String>(
                        label == '本月订阅续费总额'
                            ? 'home-renewal-primary-symbol'
                            : 'home-renewal-secondary-symbol',
                      ),
                      style: TextStyle(
                        color: secondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      amount.value,
                      translate: false,
                      key: ValueKey<String>(
                        label == '本月订阅续费总额'
                            ? 'home-renewal-primary-value'
                            : 'home-renewal-secondary-value-${amount.value}',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        color: content,
                        fontSize: 16,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        fontFeatures: <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenewalDateRail extends StatelessWidget {
  const _RenewalDateRail({required this.dates});

  final List<DateTime> dates;

  @override
  Widget build(BuildContext context) {
    if (dates.isEmpty) {
      return Container(height: 2, color: Colors.white.withValues(alpha: 0.24));
    }
    final palette = context.cardockTheme.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final halfCell = constraints.maxWidth / dates.length / 2;
        return Stack(
          children: [
            if (dates.length > 1)
              Positioned(
                left: halfCell,
                right: halfCell,
                top: 5.5,
                child: Container(
                  height: 2,
                  color: Colors.white.withValues(alpha: 0.42),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < dates.length; index++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 13,
                            child: Center(
                              child: Container(
                                width: index == 0 ? 13 : 7,
                                height: index == 0 ? 13 : 7,
                                decoration: BoxDecoration(
                                  color: index == 0
                                      ? palette.statusRenewSoon
                                      : palette.brandSecondaryDecorative,
                                  shape: BoxShape.circle,
                                  border: index == 0
                                      ? Border.all(
                                          color: context
                                              .cardockTheme
                                              .material
                                              .timelineEmphasisBorder,
                                          width: 2,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            localizedMonthDay(
                              context.l10n.language,
                              dates[index],
                            ),
                            translate: false,
                            textAlign: TextAlign.center,
                            softWrap: true,
                            style: TextStyle(
                              color: index == 0
                                  ? palette.statusRenewSoon
                                  : palette.gradientContent.withValues(
                                      alpha: 0.78,
                                    ),
                              fontSize: 8.5,
                              fontWeight: index == 0
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _RenewalTickets extends StatelessWidget {
  const _RenewalTickets({
    required this.subscriptions,
    required this.accounts,
    required this.today,
    required this.onOpenSubscription,
  });

  final List<SubscriptionRecord> subscriptions;
  final List<AccountRecord> accounts;
  final DateTime today;
  final ValueChanged<SubscriptionRecord> onOpenSubscription;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    if (subscriptions.isEmpty) {
      return Container(
        key: const ValueKey<String>('home-upcoming-renewals-empty'),
        height: 92,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(CardockRadius.card),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Icon(Icons.event_available_outlined, color: palette.statusNormal),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                '未来30天没有待续费项目',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final accountById = <String, AccountRecord>{
      for (final account in accounts) account.id: account,
    };
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      key: const ValueKey<String>('home-renewal-tickets'),
      height: 147.0 + ((textScale - 1).clamp(0.0, 1.0) * 96.0),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: subscriptions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final subscription = subscriptions[index];
          return _RenewalTicket(
            subscription: subscription,
            account: accountById[subscription.accountId],
            today: today,
            onTap: () => onOpenSubscription(subscription),
          );
        },
      ),
    );
  }
}

class _RenewalTicket extends StatelessWidget {
  const _RenewalTicket({
    required this.subscription,
    required this.account,
    required this.today,
    required this.onTap,
  });

  final SubscriptionRecord subscription;
  final AccountRecord? account;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final days = DateUtils.dateOnly(
      subscription.nextRenewalOn,
    ).difference(DateUtils.dateOnly(today)).inDays;
    final accountSummary = _homeMaskedSummary(context, account);
    final amount = subscription.amount == null
        ? context.tr('金额待补充')
        : '${subscription.currency} ${subscription.amount}';
    final renewalTiming = localizedRenewalTiming(context.l10n.language, days);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final ticketHeight = 147.0 + ((textScale - 1).clamp(0.0, 1.0) * 96.0);
    return Semantics(
      button: true,
      label: context
          .tr('{service}，{account}，{amount}，{renewal}', <String, Object?>{
            'service': subscription.serviceName,
            'account': accountSummary,
            'amount': amount,
            'renewal': renewalTiming,
          }),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>(
            'home-upcoming-subscription-${subscription.id}',
          ),
          onTap: onTap,
          borderRadius: BorderRadius.circular(CardockRadius.card),
          child: Ink(
            width: 294,
            height: ticketHeight,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(CardockRadius.card),
              border: Border.all(
                color: palette.border,
                width: context.cardockTheme.material.cardBorderWidth,
              ),
              boxShadow: context.cardockTheme.material.cardShadows
                  .map((layer) => layer.toBoxShadow())
                  .toList(growable: false),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: palette.primary,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(CardockRadius.card),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 13, 11),
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width:
                                    51.0 +
                                    ((textScale - 1).clamp(0.0, 1.0) * 45.0),
                                height:
                                    59.0 +
                                    ((textScale - 1).clamp(0.0, 1.0) * 70.0),
                                decoration: BoxDecoration(
                                  color: palette.primary,
                                  borderRadius: BorderRadius.circular(
                                    CardockRadius.dateBadge,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      localizedRecordMonth(
                                        context.l10n.language,
                                        subscription.nextRenewalOn.month,
                                      ),
                                      translate: false,
                                      style: TextStyle(
                                        color: palette.onBrandPrimary,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '${subscription.nextRenewalOn.day}',
                                      translate: false,
                                      style: TextStyle(
                                        color: palette.onBrandPrimary,
                                        fontSize: 24,
                                        height: 1,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: const <FontFeature>[
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      subscription.serviceName,
                                      translate: false,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      subscription.planName ?? accountSummary,
                                      translate: false,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: palette.textTertiary,
                                            fontSize: 10,
                                          ),
                                    ),
                                    const Spacer(),
                                    Row(
                                      children: [
                                        CardockResolvedPlatformIcon(
                                          name: subscription.serviceName,
                                          category: account?.category,
                                          size: 24,
                                          role: CardockPlatformIconRole
                                              .subscription,
                                          semanticLabel: context.tr(
                                            '{name}图标',
                                            <String, Object?>{
                                              'name': subscription.serviceName,
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            account?.platformName ??
                                                context.tr('独立订阅'),
                                            translate: false,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: palette.textSecondary,
                                                  fontSize: 10,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 14, color: palette.divider),
                        Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 14,
                              color: palette.statusRenewSoon,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  renewalTiming,
                                  translate: false,
                                  style: TextStyle(
                                    color: palette.statusRenewSoon,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  amount,
                                  translate: false,
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const <FontFeature>[
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _homeMaskedSummary(BuildContext context, AccountRecord? account) {
  if (account == null) return context.tr('独立订阅');
  final value = account.loginAccount ?? account.boundEmail ?? account.username;
  if (value == null || value.isEmpty) return account.platformName;
  if (value.contains('@')) {
    final parts = value.split('@');
    final prefix = parts.first;
    final visible = prefix.length <= 2
        ? prefix.characters.first
        : prefix.substring(0, 2);
    return '$visible•••@${parts.last}';
  }
  if (value.length <= 2) return '${value.characters.first}•';
  return '${value.substring(0, 2)}•••${value.substring(value.length - 2)}';
}

class _HomeExceptionStrip extends StatelessWidget {
  const _HomeExceptionStrip({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final message = context.tr('{countLabel}已逾期或到期，待确认', <String, Object?>{
      'countLabel': localizedSubscriptionItemCount(
        context.l10n.language,
        count,
      ),
    });
    return Semantics(
      button: true,
      label: message,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey<String>('home-renewal-exception-strip'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(CardockRadius.input),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: palette.statusDanger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(CardockRadius.input),
              border: Border.all(
                color: palette.statusDanger.withValues(alpha: 0.28),
              ),
            ),
            child: Row(
              children: [
                CardockSemanticIcon(
                  icon: Icons.error_outline_rounded,
                  color: palette.statusDanger,
                  size: 34,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    translate: false,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.statusDanger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: palette.statusDanger),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeBrandHeader extends StatelessWidget {
  const _HomeBrandHeader({
    required this.accountCount,
    required this.subscriptionCount,
    required this.onSearch,
    required this.onLock,
  });

  final int accountCount;
  final int subscriptionCount;
  final VoidCallback onSearch;
  final VoidCallback? onLock;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final accountLabel = localizedAccountCount(
      context.l10n.language,
      accountCount,
    );
    final subscriptionLabel = localizedSubscriptionCount(
      context.l10n.language,
      subscriptionCount,
    );
    return Semantics(
      header: true,
      label: context.tr(
        '卡坞 · Cardock，{accounts}，{subscriptions}',
        <String, Object?>{
          'accounts': accountLabel,
          'subscriptions': subscriptionLabel,
        },
      ),
      child: SizedBox(
        height:
            CardockLayout.homeHeaderHeight + ((textScale - 1).clamp(0, 1) * 30),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: CardockBrandMark(iconSize: 39),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$accountLabel · $subscriptionLabel',
                    translate: false,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _HomeHeaderAction(
              key: const ValueKey<String>('home-search'),
              icon: Icons.search_rounded,
              tooltip: context.tr('搜索账号'),
              onPressed: onSearch,
            ),
            const SizedBox(width: 8),
            _HomeHeaderAction(
              key: const ValueKey<String>('app-bar-manual-lock'),
              icon: Icons.lock_outline_rounded,
              tooltip: context.tr('立即锁定'),
              onPressed: onLock,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeaderAction extends StatelessWidget {
  const _HomeHeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(
        width: CardockLayout.minimumTapTarget,
        height: CardockLayout.minimumTapTarget,
      ),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: palette.surface.withValues(alpha: 0.8),
        side: BorderSide(color: palette.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CardockRadius.control),
        ),
      ),
      icon: Icon(icon, size: 19),
    );
  }
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final theme = Theme.of(context);
    final titleStyle =
        theme.textTheme.titleMedium ?? DefaultTextStyle.of(context).style;
    final subtitleStyle =
        theme.textTheme.bodySmall?.copyWith(color: palette.textTertiary) ??
        DefaultTextStyle.of(context).style;
    final actionStyle =
        theme.textTheme.labelLarge ?? DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleWidth = _measureHomeText(context, title, titleStyle).width;
        final actionTextWidth = _measureHomeText(
          context,
          action,
          actionStyle,
        ).width;
        // TextButton's horizontal insets are intentionally included so the
        // decision is based on the real tap target rather than glyphs alone.
        final actionButtonWidth = actionTextWidth + 24;
        final shouldStack =
            titleWidth + actionButtonWidth + 12 > constraints.maxWidth;

        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, translate: false, style: titleStyle),
            const SizedBox(height: 3),
            Text(
              subtitle,
              translate: false,
              softWrap: true,
              style: subtitleStyle,
            ),
          ],
        );
        if (!shouldStack) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: heading),
              TextButton(
                onPressed: onTap,
                child: Text(action, translate: false),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading,
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(alignment: Alignment.centerRight),
                child: Text(
                  action,
                  translate: false,
                  softWrap: true,
                  textAlign: TextAlign.end,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AccountDock extends StatelessWidget {
  const _AccountDock({
    required this.accounts,
    required this.onOpenAccount,
    required this.onAddAccount,
  });

  final List<AccountRecord> accounts;
  final ValueChanged<AccountRecord> onOpenAccount;
  final VoidCallback? onAddAccount;

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return _EmptyAccountDockTile(onTap: onAddAccount);
    }
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      key: const ValueKey<String>('home-recent-account-rail'),
      height:
          CardockLayout.dockTileHeight +
          ((textScale - 1).clamp(0.0, 1.0) * 36.0),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: accounts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final account = accounts[index];
          return _DockAccountTile(
            account: account,
            onTap: () => onOpenAccount(account),
          );
        },
      ),
    );
  }
}

class _DockAccountTile extends StatelessWidget {
  const _DockAccountTile({required this.account, required this.onTap});

  final AccountRecord account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return Semantics(
      button: true,
      label: context.tr('打开{name}账号详情', <String, Object?>{
        'name': account.platformName,
      }),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>('home-dock-account-${account.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(CardockRadius.card),
          child: Ink(
            width: 80,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(CardockRadius.card),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CardockResolvedPlatformIcon(
                      key: ValueKey<String>(
                        'home-account-brand-icon-${account.id}',
                      ),
                      name: account.platformName,
                      category: account.category,
                      size: 24,
                      role: CardockPlatformIconRole.account,
                      semanticLabel: context.tr('{name}图标', <String, Object?>{
                        'name': account.platformName,
                      }),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.more_horiz_rounded,
                      size: 13,
                      color: palette.textTertiary,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  account.platformName,
                  translate: false,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  account.category == null
                      ? context.tr('未分类')
                      : localizedAccountCategory(
                          context.l10n.language,
                          account.category!,
                        ),
                  translate: false,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.textTertiary,
                    fontSize: 8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyAccountDockTile extends StatelessWidget {
  const _EmptyAccountDockTile({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return CardockSurfaceCard(
      key: const ValueKey<String>('home-recent-empty'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 330 || textScale >= 1.5;
          final message = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardockSemanticIcon(
                icon: Icons.history_rounded,
                color: palette.statusInformation,
                size: 38,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '从第一张账号卡开始',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '记录平台账号，并关联你的订阅',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final addButton = FilledButton.icon(
            key: const ValueKey<String>('home-add-account-tile'),
            onPressed: onTap,
            icon: const Icon(Icons.add_rounded),
            label: const Text('新增账号'),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [message, const SizedBox(height: 14), addButton],
            );
          }
          return Row(
            children: [
              Expanded(child: message),
              const SizedBox(width: 14),
              addButton,
            ],
          );
        },
      ),
    );
  }
}
