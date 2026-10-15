import 'dart:io';

import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/core/theme/cardock_tokens.dart';
import 'package:account_subscription_manager/shared/widgets/cardock_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('八套固定主题浅深材质均完整且类型互不串用', () {
    final kinds = <CardockMaterialKind>{};
    for (final family in cardockFixedThemeFamilies) {
      final light = CardockTokens.spec(family, Brightness.light);
      final dark = CardockTokens.spec(family, Brightness.dark);
      expect(light.material.kind, dark.material.kind, reason: family.name);
      expect(light.material.cardBorderWidth, greaterThan(0));
      expect(dark.material.cardBorderWidth, greaterThan(0));
      expect(light.material.cardShadows, isNotEmpty);
      expect(dark.material.cardShadows, isNotEmpty);
      expect(light.material.heroShadows, isNotEmpty);
      expect(dark.material.heroShadows, isNotEmpty);
      kinds.add(light.material.kind);
    }
    expect(kinds, hasLength(8));
  });

  test('仅 Paper Archive 使用唯一纸张纹理 production asset', () async {
    for (final family in cardockFixedThemeFamilies) {
      for (final brightness in Brightness.values) {
        final asset = CardockTokens.spec(
          family,
          brightness,
        ).material.textureAsset;
        if (family == CardockThemeFamily.paperArchive) {
          expect(asset, 'assets/theme/paper_grain_128.webp');
        } else {
          expect(asset, isNull, reason: '${family.name}/$brightness');
        }
      }
    }
    final file = File('assets/theme/paper_grain_128.webp');
    expect(await file.exists(), isTrue);
    expect(await file.length(), 19662);
  });

  test('Neon Zero 深色保持 OLED 黑主导且文字不被全染绿', () {
    final spec = CardockTokens.spec(
      CardockThemeFamily.neonZero,
      Brightness.dark,
    );
    expect(spec.palette.background, const Color(0xFF000000));
    expect(spec.palette.primary, const Color(0xFF24EC8C));
    expect(spec.palette.textPrimary, isNot(spec.palette.primary));
    expect(spec.palette.textSecondary, isNot(spec.palette.primary));
    expect(spec.material.kind, CardockMaterialKind.neonLine);
    expect(spec.material.surfaceGradientEnabled, isFalse);
  });

  test('Obsidian Gold 深色无紫色主轴且金色只用于焦点', () {
    final palette = CardockTokens.palette(
      CardockThemeFamily.obsidianGold,
      Brightness.dark,
    );
    expect(palette.background, const Color(0xFF06090E));
    expect(palette.surface, const Color(0xFF10151B));
    expect(palette.primary, const Color(0xFFE2B653));
    expect(palette.textPrimary, isNot(palette.primary));
    expect(palette.statusDanger, isNot(palette.primary));
  });

  testWidgets('纹理资源解码不可用时 SurfaceCard 仍保留基础表面', (tester) async {
    final base = CardockTokens.spec(
      CardockThemeFamily.paperArchive,
      Brightness.light,
    );
    final missing = _withTexture(
      base.material,
      'assets/theme/does-not-exist.webp',
    );
    final theme = AppTheme.light(family: CardockThemeFamily.paperArchive)
        .copyWith(
          extensions: <ThemeExtension<dynamic>>[
            CardockThemeExtension(
              family: CardockThemeFamily.paperArchive,
              palette: base.palette,
              material: missing,
            ),
          ],
        );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(body: CardockSurfaceCard(child: Text('基础表面仍可用'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('基础表面仍可用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

CardockMaterialProfile _withTexture(
  CardockMaterialProfile source,
  String textureAsset,
) => CardockMaterialProfile(
  kind: source.kind,
  cardBorderWidth: source.cardBorderWidth,
  elevatedBorderWidth: source.elevatedBorderWidth,
  cardShadows: source.cardShadows,
  elevatedCardShadows: source.elevatedCardShadows,
  heroShadows: source.heroShadows,
  dockShadows: source.dockShadows,
  surfaceHighlightOpacity: source.surfaceHighlightOpacity,
  surfaceHighlightStop: source.surfaceHighlightStop,
  heroPrimaryMetricFill: source.heroPrimaryMetricFill,
  heroPrimaryMetricBorder: source.heroPrimaryMetricBorder,
  heroMiniMetricFill: source.heroMiniMetricFill,
  heroMiniMetricBorder: source.heroMiniMetricBorder,
  heroWatermarkOpacity: source.heroWatermarkOpacity,
  timelineEmphasisBorder: source.timelineEmphasisBorder,
  textureAsset: textureAsset,
  textureOpacity: source.textureOpacity,
  lineGlowColor: source.lineGlowColor,
  lineGlowBlur: source.lineGlowBlur,
  lineDecorationOpacity: source.lineDecorationOpacity,
  fabElevation: source.fabElevation,
  fabHighlightElevation: source.fabHighlightElevation,
  surfaceGradientEnabled: source.surfaceGradientEnabled,
);
