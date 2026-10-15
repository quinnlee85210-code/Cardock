import '../../l10n/context_l10n.dart';
import '../../l10n/localized_material.dart';

import '../../core/theme/cardock_tokens.dart';
import 'cardock_brand_symbol.dart';

class CardockBrandMark extends StatelessWidget {
  const CardockBrandMark({
    this.showWordmark = true,
    this.iconSize = 32,
    super.key,
  });

  final bool showWordmark;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = context.cardockTheme;
    final brightness = Theme.of(context).brightness;
    return Semantics(
      label: 'Cardock',
      container: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: CardockMotion.resolve(
              context,
              CardockMotion.logoCrossfade,
            ),
            child: CardockBrandSymbol(
              key: ValueKey<String>('${theme.family.name}-$brightness'),
              size: iconSize,
            ),
          ),
          if (showWordmark) ...[
            const SizedBox(width: 10),
            Text(
              'Cardock',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: CardockTypography.brand,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class CardockSurfaceCard extends StatelessWidget {
  const CardockSurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(CardockLayout.cardPadding),
    this.onTap,
    this.semanticLabel,
    this.elevated = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final extension = context.cardockTheme;
    final palette = extension.palette;
    final materialProfile = extension.material;
    final surface = elevated ? palette.surfaceElevated : palette.surface;
    final content = Padding(padding: padding, child: child);
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: materialProfile.surfaceGradientEnabled ? null : surface,
          gradient: materialProfile.surfaceGradientEnabled
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: <double>[0, materialProfile.surfaceHighlightStop],
                  colors: <Color>[
                    Color.alphaBlend(
                      palette.surfaceTopHighlight.withValues(
                        alpha: materialProfile.surfaceHighlightOpacity,
                      ),
                      surface,
                    ),
                    surface,
                  ],
                )
              : null,
          image: materialProfile.textureAsset == null
              ? null
              : DecorationImage(
                  image: AssetImage(materialProfile.textureAsset!),
                  onError: (error, stackTrace) {},
                  repeat: ImageRepeat.repeat,
                  fit: BoxFit.none,
                  opacity: materialProfile.textureOpacity,
                ),
          borderRadius: BorderRadius.circular(CardockRadius.card),
          border: Border.all(
            color: palette.border,
            width: elevated
                ? materialProfile.elevatedBorderWidth
                : materialProfile.cardBorderWidth,
          ),
          boxShadow: materialProfile.shadows(elevated: elevated),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: onTap == null
              ? content
              : InkWell(
                  borderRadius: BorderRadius.circular(CardockRadius.card),
                  overlayColor: WidgetStatePropertyAll<Color>(
                    palette.pressedLayer,
                  ),
                  onTap: onTap,
                  child: content,
                ),
        ),
      ),
    );
  }
}

class CardockSemanticIcon extends StatelessWidget {
  const CardockSemanticIcon({
    required this.icon,
    required this.color,
    this.size = 29,
    super.key,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(CardockRadius.icon),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.55, color: color),
    );
  }
}

enum CardockVisualStatus {
  normal,
  renewSoon,
  renewToday,
  expired,
  cancelled,
  paused,
  information,
}

class CardockStatusPill extends StatelessWidget {
  const CardockStatusPill({
    required this.status,
    required this.label,
    super.key,
  });

  final CardockVisualStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final (semanticColor, icon) = switch (status) {
      CardockVisualStatus.normal => (
        palette.statusNormal,
        Icons.check_circle_outline_rounded,
      ),
      CardockVisualStatus.renewSoon => (
        palette.statusRenewSoon,
        Icons.schedule_rounded,
      ),
      CardockVisualStatus.renewToday => (
        palette.statusDanger,
        Icons.today_rounded,
      ),
      CardockVisualStatus.expired => (
        palette.statusDanger,
        Icons.error_outline_rounded,
      ),
      CardockVisualStatus.cancelled => (
        palette.statusCancelled,
        Icons.block_rounded,
      ),
      CardockVisualStatus.paused => (
        palette.statusPaused,
        Icons.pause_circle_outline_rounded,
      ),
      CardockVisualStatus.information => (
        palette.statusInformation,
        Icons.info_outline_rounded,
      ),
    };
    final color = Theme.of(context).brightness == Brightness.light
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.24), semanticColor)
        : semanticColor;
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(CardockRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              translate: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

@immutable
class CardockOverviewMetric {
  const CardockOverviewMetric({
    required this.id,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String id;
  final String label;
  final String value;
  final VoidCallback onTap;
}

class CardockOverviewDock extends StatelessWidget {
  const CardockOverviewDock({
    required this.metrics,
    required this.dateLabel,
    required this.earliestLabel,
    this.timelineLabel,
    this.timelineProgress = 0,
    this.title = '今日概览',
    super.key,
  }) : assert(metrics.length == 4);

  final List<CardockOverviewMetric> metrics;
  final String title;
  final String dateLabel;
  final String earliestLabel;
  final String? timelineLabel;
  final double timelineProgress;

  @override
  Widget build(BuildContext context) {
    final extension = context.cardockTheme;
    final palette = extension.palette;
    final materialProfile = extension.material;
    final custom = extension.family == CardockThemeFamily.custom;
    final brightness = Theme.of(context).brightness;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final height =
        CardockLayout.heroHeight + ((textScale - 1).clamp(0, 1) * 200);
    final renewalMetric = _metric('renewing-within-thirty-days');
    final debitMetric = _metric('auto-renew-this-month');
    final nextMonthMetric = _metric('renewals-next-month');
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: palette.overviewGradient,
        borderRadius: BorderRadius.circular(CardockRadius.hero),
        boxShadow: materialProfile.heroShadows
            .map((layer) => layer.toBoxShadow())
            .toList(growable: false),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CardockRadius.hero),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              right: -26,
              bottom: -38,
              width: 190,
              height: 190,
              child: Opacity(
                opacity: materialProfile.heroWatermarkOpacity,
                child: CardockBrandSymbol(
                  key: ValueKey<String>(
                    'overview-${extension.family.name}-$brightness',
                  ),
                  size: 190,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(CardockLayout.heroPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            title,
                            translate: false,
                            maxLines: 1,
                            style: TextStyle(
                              color: palette.gradientContent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            dateLabel,
                            translate: false,
                            maxLines: 1,
                            style: TextStyle(
                              color: custom
                                  ? palette.gradientContent
                                  : palette.gradientContent.withValues(
                                      alpha: 0.7,
                                    ),
                              fontSize: CardockTypography.caption,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 128,
                          child: _OverviewPrimaryMetric(
                            metric: renewalMetric,
                            earliestLabel: earliestLabel,
                            color: palette.gradientContent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 92,
                          child: Column(
                            children: [
                              Expanded(
                                child: _OverviewMiniMetric(
                                  metric: debitMetric,
                                  color: palette.gradientContent,
                                  valueColor: palette.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 9),
                              Expanded(
                                child: _OverviewMiniMetric(
                                  metric: nextMonthMetric,
                                  color: palette.gradientContent,
                                  emphasize: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _RenewalTimeline(
                    progress: timelineProgress,
                    middleLabel: timelineLabel,
                    color: palette.gradientContent,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  CardockOverviewMetric _metric(String id) =>
      metrics.firstWhere((metric) => metric.id == id);
}

class _OverviewPrimaryMetric extends StatelessWidget {
  const _OverviewPrimaryMetric({
    required this.metric,
    required this.earliestLabel,
    required this.color,
  });

  final CardockOverviewMetric metric;
  final String earliestLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final extension = context.cardockTheme;
    final custom = extension.family == CardockThemeFamily.custom;
    final materialProfile = extension.material;
    return Semantics(
      button: true,
      label: context.tr('{label}，{value}，{detail}', <String, Object?>{
        'label': metric.label,
        'value': metric.value,
        'detail': earliestLabel,
      }),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>('home-metric-${metric.id}'),
          onTap: metric.onTap,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: materialProfile.heroPrimaryMetricFill,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: materialProfile.heroPrimaryMetricBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '未来 30 天',
                  style: TextStyle(
                    color: custom ? color : color.withValues(alpha: 0.72),
                    fontSize: CardockTypography.caption,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _numericMetricValue(metric.value),
                            translate: false,
                            style: TextStyle(
                              color: color,
                              fontSize: CardockTypography.heroNumber,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -3,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          '项待续费',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color:
                            context.cardockTheme.palette.overviewTimelineAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        earliestLabel,
                        translate: false,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: custom ? color : color.withValues(alpha: 0.82),
                          fontSize: CardockTypography.caption,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewMiniMetric extends StatelessWidget {
  const _OverviewMiniMetric({
    required this.metric,
    required this.color,
    this.valueColor,
    this.emphasize = false,
  });

  final CardockOverviewMetric metric;
  final Color color;
  final Color? valueColor;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final extension = context.cardockTheme;
    final custom = extension.family == CardockThemeFamily.custom;
    final materialProfile = extension.material;
    return Semantics(
      button: true,
      label: context.tr('{label}，{value}', <String, Object?>{
        'label': metric.label,
        'value': metric.value,
      }),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>('home-metric-${metric.id}'),
          onTap: metric.onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: materialProfile.heroMiniMetricFill,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: materialProfile.heroMiniMetricBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  translate: false,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: custom ? color : color.withValues(alpha: 0.7),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      metric.value,
                      translate: false,
                      style: TextStyle(
                        color: valueColor ?? color,
                        fontSize: emphasize ? 22 : 16,
                        fontWeight: FontWeight.w700,
                      ),
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

class _RenewalTimeline extends StatelessWidget {
  const _RenewalTimeline({
    required this.progress,
    required this.middleLabel,
    required this.color,
  });

  final double progress;
  final String? middleLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final normalized = progress.clamp(0.02, 0.98);
    final labelColor = context.cardockTheme.family == CardockThemeFamily.custom
        ? color
        : color.withValues(alpha: 0.72);
    return SizedBox(
      height: 25,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final markerLeft = (constraints.maxWidth - 12) * normalized;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 4,
                right: 4,
                top: 4,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(CardockRadius.pill),
                  ),
                ),
              ),
              Positioned(left: 0, top: 0, child: _TimelineDot(color: color)),
              Positioned(
                left: markerLeft,
                top: -1,
                child: _TimelineDot(
                  color: context.cardockTheme.palette.overviewTimelineAccent,
                  emphasized: true,
                ),
              ),
              Positioned(right: 0, top: 0, child: _TimelineDot(color: color)),
              Positioned(
                left: 0,
                right: 0,
                top: 11,
                child: Row(
                  children: [
                    Expanded(child: Text('今天', style: _labelStyle(labelColor))),
                    Expanded(
                      child: Text(
                        middleLabel ?? '近期',
                        translate: middleLabel == null,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: _labelStyle(labelColor),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '30天+',
                        textAlign: TextAlign.end,
                        style: _labelStyle(labelColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  TextStyle _labelStyle(Color color) =>
      TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w600);
}

class _TimelineDot extends StatelessWidget {
  const _TimelineDot({required this.color, this.emphasized = false});

  final Color color;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final size = emphasized ? 12.0 : 8.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: emphasized
            ? Border.all(
                color: context.cardockTheme.material.timelineEmphasisBorder,
                width: 3,
              )
            : null,
        boxShadow: emphasized
            ? <BoxShadow>[
                BoxShadow(
                  color: context.cardockTheme.material.lineGlowColor,
                  blurRadius: context.cardockTheme.material.lineGlowBlur,
                  spreadRadius: 5,
                ),
              ]
            : null,
      ),
    );
  }
}

class CardockFieldRow extends StatelessWidget {
  const CardockFieldRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.trailing,
    this.maxLines = 3,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final Widget? trailing;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardockSemanticIcon(icon: icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(
                  value,
                  translate: false,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

String _numericMetricValue(String value) {
  final match = RegExp(r'[-+]?\d+(?:[.,]\d+)?').firstMatch(value);
  return match?.group(0) ?? value;
}

class CardockSettingsGroup extends StatelessWidget {
  const CardockSettingsGroup({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CardockLayout.topSectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          CardockSurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < children.length; index += 1) ...[
                  children[index],
                  if (index != children.length - 1)
                    const Divider(height: 1, indent: 58),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
