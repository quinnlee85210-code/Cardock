import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/core/theme/cardock_tokens.dart';
import 'package:account_subscription_manager/core/theme/custom_theme.dart';
import 'package:account_subscription_manager/shared/widgets/cardock_brand_symbol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V7 固定主题 registry、顺序、材质与 launcher 映射完整', () {
    expect(cardockFixedThemeFamilies, const <CardockThemeFamily>[
      CardockThemeFamily.ceramicBlue,
      CardockThemeFamily.sakuraMist,
      CardockThemeFamily.paperArchive,
      CardockThemeFamily.lilacMoon,
      CardockThemeFamily.glacierBlue,
      CardockThemeFamily.mistCoral,
      CardockThemeFamily.neonZero,
      CardockThemeFamily.obsidianGold,
    ]);
    expect(cardockSelectableThemeFamilies, <CardockThemeFamily>[
      ...cardockFixedThemeFamilies,
      CardockThemeFamily.custom,
    ]);

    final specs = <CardockThemeSpec>[];
    for (final family in cardockFixedThemeFamilies) {
      expect(family.isFixed, isTrue);
      expect(family.usesRuntimeBrandMark, isTrue);
      expect(family.recommendedLauncherFamily, isNotNull);
      for (final brightness in Brightness.values) {
        final spec = CardockTokens.spec(family, brightness);
        specs.add(spec);
        expect(CardockTokens.palette(family, brightness), same(spec.palette));
        expect(
          CardockTokens.materialProfile(family, brightness),
          same(spec.material),
        );
      }
    }
    expect(specs, hasLength(16));
    expect(
      specs.map((spec) => spec.material.kind).toSet(),
      containsAll(<CardockMaterialKind>[
        CardockMaterialKind.ceramicNeumorphic,
        CardockMaterialKind.sakuraGlow,
        CardockMaterialKind.paperInk,
        CardockMaterialKind.lilacSatin,
        CardockMaterialKind.glacierGlass,
        CardockMaterialKind.mistSoft3d,
        CardockMaterialKind.neonLine,
        CardockMaterialKind.obsidianMetal,
      ]),
    );
  });

  test('Paper Archive 唯一免费，其余七套固定主题与 Custom 均为完整版', () {
    expect(CardockThemeFamily.paperArchive.isPremium, isFalse);
    for (final family in cardockSelectableThemeFamilies.where(
      (family) => family != CardockThemeFamily.paperArchive,
    )) {
      expect(family.isPremium, isTrue, reason: family.name);
    }
  });

  test('八套固定主题与桌面图标一一对应，自定义主题保留保存的回退', () {
    final expected = <CardockThemeFamily, CardockLauncherFamily>{
      CardockThemeFamily.ceramicBlue: CardockLauncherFamily.ceramicBlue,
      CardockThemeFamily.sakuraMist: CardockLauncherFamily.sakuraMist,
      CardockThemeFamily.paperArchive: CardockLauncherFamily.paperArchive,
      CardockThemeFamily.lilacMoon: CardockLauncherFamily.lilacMoon,
      CardockThemeFamily.glacierBlue: CardockLauncherFamily.glacierBlue,
      CardockThemeFamily.mistCoral: CardockLauncherFamily.mistCoral,
      CardockThemeFamily.neonZero: CardockLauncherFamily.neonZero,
      CardockThemeFamily.obsidianGold: CardockLauncherFamily.obsidianGold,
    };
    for (final entry in expected.entries) {
      expect(entry.key.recommendedLauncherFamily, entry.value);
      expect(
        resolveCardockLauncherFamily(
          themeFamily: entry.key,
          customFallback: CardockLauncherFamily.mistCoral,
        ),
        entry.value,
      );
    }
    expect(CardockThemeFamily.custom.recommendedLauncherFamily, isNull);
    expect(
      resolveCardockLauncherFamily(
        themeFamily: CardockThemeFamily.custom,
        customFallback: CardockLauncherFamily.mistCoral,
      ),
      CardockLauncherFamily.mistCoral,
    );
  });

  test('ThemeData 同时注入 palette 与 material，Material error 前景可读', () {
    for (final family in cardockSelectableThemeFamilies) {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.build(
          family,
          brightness,
          customTheme: CardockCustomTheme.defaults,
        );
        final extension = theme.extension<CardockThemeExtension>();
        expect(extension, isNotNull, reason: '${family.name}/$brightness');
        expect(extension!.family, family);
        expect(extension.palette, isNotNull);
        expect(extension.material, isNotNull);
        expect(
          _contrast(theme.colorScheme.onError, theme.colorScheme.error),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(
            theme.colorScheme.onErrorContainer,
            theme.colorScheme.errorContainer,
          ),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });

  testWidgets('八套固定主题与 Custom 的应用内标识均为 Logo C painter', (tester) async {
    for (final family in cardockSelectableThemeFamilies) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(family: family),
          home: Scaffold(
            body: CardockBrandSymbol(
              key: ValueKey<String>('logo-${family.name}'),
              family: family,
              brightness: Brightness.light,
              size: 48,
            ),
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsWidgets, reason: family.name);
      expect(
        find.descendant(
          of: find.byKey(ValueKey<String>('logo-${family.name}')),
          matching: find.byType(Image),
        ),
        findsNothing,
        reason: family.name,
      );
    }
  });
}

double _contrast(Color first, Color second) {
  double luminance(Color color) => color.computeLuminance();
  final a = luminance(first);
  final b = luminance(second);
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}
