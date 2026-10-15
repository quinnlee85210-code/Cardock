import 'package:flutter/material.dart';

enum CardockMaterialKind {
  standard,
  ceramicNeumorphic,
  sakuraGlow,
  paperInk,
  lilacSatin,
  glacierGlass,
  mistSoft3d,
  neonLine,
  obsidianMetal,
}

@immutable
class CardockShadowSpec {
  const CardockShadowSpec({
    required this.color,
    required this.blurRadius,
    required this.spreadRadius,
    required this.offset,
  });

  final Color color;
  final double blurRadius;
  final double spreadRadius;
  final Offset offset;

  BoxShadow toBoxShadow() => BoxShadow(
    color: color,
    blurRadius: blurRadius,
    spreadRadius: spreadRadius,
    offset: offset,
  );
}

@immutable
class CardockMaterialProfile {
  const CardockMaterialProfile({
    required this.kind,
    required this.cardBorderWidth,
    required this.elevatedBorderWidth,
    required this.cardShadows,
    required this.elevatedCardShadows,
    required this.heroShadows,
    required this.dockShadows,
    required this.surfaceHighlightOpacity,
    required this.surfaceHighlightStop,
    required this.heroPrimaryMetricFill,
    required this.heroPrimaryMetricBorder,
    required this.heroMiniMetricFill,
    required this.heroMiniMetricBorder,
    required this.heroWatermarkOpacity,
    required this.timelineEmphasisBorder,
    required this.textureAsset,
    required this.textureOpacity,
    required this.lineGlowColor,
    required this.lineGlowBlur,
    required this.lineDecorationOpacity,
    required this.fabElevation,
    required this.fabHighlightElevation,
    required this.surfaceGradientEnabled,
  });

  final CardockMaterialKind kind;
  final double cardBorderWidth;
  final double elevatedBorderWidth;
  final List<CardockShadowSpec> cardShadows;
  final List<CardockShadowSpec> elevatedCardShadows;
  final List<CardockShadowSpec> heroShadows;
  final List<CardockShadowSpec> dockShadows;
  final double surfaceHighlightOpacity;
  final double surfaceHighlightStop;
  final Color heroPrimaryMetricFill;
  final Color heroPrimaryMetricBorder;
  final Color heroMiniMetricFill;
  final Color heroMiniMetricBorder;
  final double heroWatermarkOpacity;
  final Color timelineEmphasisBorder;
  final String? textureAsset;
  final double textureOpacity;
  final Color lineGlowColor;
  final double lineGlowBlur;
  final double lineDecorationOpacity;
  final double fabElevation;
  final double fabHighlightElevation;
  final bool surfaceGradientEnabled;

  List<BoxShadow> shadows({required bool elevated}) =>
      (elevated ? elevatedCardShadows : cardShadows)
          .map((layer) => layer.toBoxShadow())
          .toList(growable: false);
}

/// Custom keeps its existing color schema v2 and receives a neutral material.
/// Do not serialize material parameters into Custom JSON in this task.
abstract final class CardockMaterialProfiles {
  static const CardockMaterialProfile customLight = CardockMaterialProfile(
    kind: CardockMaterialKind.standard,
    cardBorderWidth: 1,
    elevatedBorderWidth: 1,
    cardShadows: <CardockShadowSpec>[
      CardockShadowSpec(
        color: Color(0x24142033),
        blurRadius: 16,
        spreadRadius: 0,
        offset: Offset(0, 5),
      ),
    ],
    elevatedCardShadows: <CardockShadowSpec>[
      CardockShadowSpec(
        color: Color(0x38142033),
        blurRadius: 24,
        spreadRadius: 0,
        offset: Offset(0, 8),
      ),
    ],
    heroShadows: <CardockShadowSpec>[
      CardockShadowSpec(
        color: Color(0x384B66E6),
        blurRadius: 48,
        spreadRadius: 0,
        offset: Offset(0, 20),
      ),
    ],
    dockShadows: <CardockShadowSpec>[],
    surfaceHighlightOpacity: 0.55,
    surfaceHighlightStop: 0.12,
    heroPrimaryMetricFill: Color(0x2E000000),
    heroPrimaryMetricBorder: Color(0x1CFFFFFF),
    heroMiniMetricFill: Color(0x1AFFFFFF),
    heroMiniMetricBorder: Color(0x1FFFFFFF),
    heroWatermarkOpacity: 0.075,
    timelineEmphasisBorder: Colors.white,
    textureAsset: null,
    textureOpacity: 0,
    lineGlowColor: Colors.transparent,
    lineGlowBlur: 0,
    lineDecorationOpacity: 0,
    fabElevation: 5,
    fabHighlightElevation: 2,
    surfaceGradientEnabled: true,
  );

  static const CardockMaterialProfile customDark = CardockMaterialProfile(
    kind: CardockMaterialKind.standard,
    cardBorderWidth: 1,
    elevatedBorderWidth: 1,
    cardShadows: <CardockShadowSpec>[
      CardockShadowSpec(
        color: Color(0x99000000),
        blurRadius: 18,
        spreadRadius: 0,
        offset: Offset(0, 6),
      ),
    ],
    elevatedCardShadows: <CardockShadowSpec>[
      CardockShadowSpec(
        color: Color(0xCC000000),
        blurRadius: 26,
        spreadRadius: 0,
        offset: Offset(0, 9),
      ),
    ],
    heroShadows: <CardockShadowSpec>[
      CardockShadowSpec(
        color: Color(0x99000000),
        blurRadius: 48,
        spreadRadius: 0,
        offset: Offset(0, 20),
      ),
    ],
    dockShadows: <CardockShadowSpec>[],
    surfaceHighlightOpacity: 0.07,
    surfaceHighlightStop: 0.12,
    heroPrimaryMetricFill: Color(0x2E000000),
    heroPrimaryMetricBorder: Color(0x1CFFFFFF),
    heroMiniMetricFill: Color(0x1AFFFFFF),
    heroMiniMetricBorder: Color(0x1FFFFFFF),
    heroWatermarkOpacity: 0.075,
    timelineEmphasisBorder: Colors.white,
    textureAsset: null,
    textureOpacity: 0,
    lineGlowColor: Colors.transparent,
    lineGlowBlur: 0,
    lineDecorationOpacity: 0,
    fabElevation: 5,
    fabHighlightElevation: 2,
    surfaceGradientEnabled: true,
  );

  static CardockMaterialProfile custom(Brightness brightness) =>
      brightness == Brightness.dark ? customDark : customLight;
}
