// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';
import 'dart:io';

import 'package:account_subscription_manager/core/theme/cardock_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('16 套固定 Palette/Material 精确来自 JSON 且 704 项检查通过', () async {
    final tokenRoot =
        jsonDecode(
              await File(
                'tool/theme_v7/spec/theme_tokens_v7.json',
              ).readAsString(),
            )
            as Map<String, Object?>;
    final materialRoot =
        jsonDecode(
              await File(
                'tool/theme_v7/spec/material_profiles_v7.json',
              ).readAsString(),
            )
            as Map<String, Object?>;
    final tokenFamilies = tokenRoot['families']! as List<Object?>;
    final materialFamilies = materialRoot['families']! as List<Object?>;
    expect(tokenFamilies, hasLength(8));
    expect(materialFamilies, hasLength(8));

    var checkCount = 0;
    final failures = <String>[];
    for (var familyIndex = 0; familyIndex < 8; familyIndex += 1) {
      final tokenFamily = tokenFamilies[familyIndex]! as Map<String, Object?>;
      final materialFamily =
          materialFamilies[familyIndex]! as Map<String, Object?>;
      final family = cardockFixedThemeFamilies[familyIndex];
      expect(tokenFamily['id'], family.name);
      expect(materialFamily['id'], family.name);
      final palettes = tokenFamily['palettes']! as Map<String, Object?>;
      final profiles = materialFamily['profiles']! as Map<String, Object?>;

      for (final brightness in Brightness.values) {
        final mode = brightness == Brightness.dark ? 'dark' : 'light';
        final paletteJson = palettes[mode]! as Map<String, Object?>;
        final profileJson = profiles[mode]! as Map<String, Object?>;
        final spec = CardockTokens.spec(family, brightness);
        final runtimeTokens = _paletteTokens(spec.palette);
        expect(runtimeTokens, hasLength(71));
        expect(paletteJson.keys.toList(), runtimeTokens.keys.toList());
        for (final entry in runtimeTokens.entries) {
          expect(
            entry.value.toARGB32(),
            _parseColor(paletteJson[entry.key]! as String).toARGB32(),
            reason: family.name + '/' + mode + '/' + entry.key,
          );
        }
        _expectMaterial(
          family: family,
          mode: mode,
          runtime: spec.material,
          json: profileJson,
        );

        void check(
          String name,
          Color foreground,
          Color background,
          double minimum,
        ) {
          checkCount += 1;
          final ratio = _contrast(foreground, background);
          if (ratio + 1e-9 < minimum) {
            failures.add(
              family.name +
                  '/' +
                  mode +
                  '/' +
                  name +
                  '=' +
                  ratio.toStringAsFixed(4) +
                  '<' +
                  minimum.toString(),
            );
          }
        }

        final p = spec.palette;
        for (final surface in <MapEntry<String, Color>>[
          MapEntry<String, Color>('background', p.background),
          MapEntry<String, Color>('surface', p.surface),
          MapEntry<String, Color>('surfaceAlt', p.surfaceAlt),
        ]) {
          check(
            'textPrimary/' + surface.key,
            p.textPrimary,
            surface.value,
            4.5,
          );
          check(
            'textSecondary/' + surface.key,
            p.textSecondary,
            surface.value,
            4.5,
          );
          check(
            'textTertiary/' + surface.key,
            p.textTertiary,
            surface.value,
            3,
          );
        }
        for (final surface in <MapEntry<String, Color>>[
          MapEntry<String, Color>('background', p.background),
          MapEntry<String, Color>('surface', p.surface),
        ]) {
          check('primary/' + surface.key, p.primary, surface.value, 3);
          check(
            'brandSecondaryContent/' + surface.key,
            p.brandSecondaryContent,
            surface.value,
            3,
          );
        }
        check(
          'navigationActive/surfaceDock',
          p.navigationActive,
          p.surfaceDock,
          3,
        );
        check('focusRing/surface', p.focusRing, p.surface, 3);
        check('actionPrimary/surface', p.actionPrimary, p.surface, 3);
        check('onBrandPrimary/primary', p.onBrandPrimary, p.primary, 4.5);
        check('actionSecondary/surface', p.actionSecondary, p.surface, 4.5);
        check('inputFocus/surface', p.inputFocus, p.surface, 3);
        check('accountAccent/surface', p.accountAccent, p.surface, 3);
        check(
          'accountAccent/accountIconBackground',
          p.accountAccent,
          p.accountIconBackground,
          3,
        );
        for (final entry in <MapEntry<String, Color>>[
          MapEntry<String, Color>('fieldLogin', p.fieldLogin),
          MapEntry<String, Color>('fieldPhone', p.fieldPhone),
          MapEntry<String, Color>('fieldEmail', p.fieldEmail),
          MapEntry<String, Color>('fieldPassword', p.fieldPassword),
          MapEntry<String, Color>('fieldUrl', p.fieldUrl),
        ]) {
          check(entry.key + '/surface', entry.value, p.surface, 3);
        }
        check('subscriptionAccent/surface', p.subscriptionAccent, p.surface, 3);
        check(
          'subscriptionAccent/subscriptionIconBackground',
          p.subscriptionAccent,
          p.subscriptionIconBackground,
          3,
        );
        check('renewalAccent/surface', p.renewalAccent, p.surface, 3);

        for (final endpoint in <MapEntry<String, Color>>[
          MapEntry<String, Color>('overviewStart', p.overviewStart),
          MapEntry<String, Color>('overviewEnd', p.overviewEnd),
        ]) {
          check(
            'gradientContent/' + endpoint.key,
            p.gradientContent,
            endpoint.value,
            4.5,
          );
          check(
            'gradientContent/' + endpoint.key + '/heroPrimaryMetricFill',
            p.gradientContent,
            Color.alphaBlend(
              spec.material.heroPrimaryMetricFill,
              endpoint.value,
            ),
            4.5,
          );
          check(
            'gradientContent/' + endpoint.key + '/heroMiniMetricFill',
            p.gradientContent,
            Color.alphaBlend(spec.material.heroMiniMetricFill, endpoint.value),
            4.5,
          );
        }

        for (final status in <MapEntry<String, Color>>[
          MapEntry<String, Color>('statusNormal', p.statusNormal),
          MapEntry<String, Color>('statusRenewSoon', p.statusRenewSoon),
          MapEntry<String, Color>('statusDanger', p.statusDanger),
          MapEntry<String, Color>('statusCancelled', p.statusCancelled),
          MapEntry<String, Color>('statusPaused', p.statusPaused),
          MapEntry<String, Color>('statusInformation', p.statusInformation),
        ]) {
          check(
            status.key + '/surface',
            status.value,
            p.surface,
            status.key == 'statusDanger' ? 4.5 : 3,
          );
        }

        check(
          'onError/statusDanger',
          _onColor(p.statusDanger),
          p.statusDanger,
          4.5,
        );
        final errorContainer = Color.alphaBlend(
          p.statusDanger.withValues(alpha: 0.14),
          p.surface,
        );
        check(
          'onErrorContainer/errorContainer',
          _readableColor(p.statusDanger, p.textPrimary, <Color>[
            errorContainer,
          ]),
          errorContainer,
          4.5,
        );
        checkCount += 1;
        if (p.statusDanger == p.statusNormal) {
          failures.add(family.name + '/' + mode + '/danger-equals-success');
        }
      }
    }

    expect(checkCount, 704);
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}

Map<String, Color> _paletteTokens(CardockPalette p) => <String, Color>{
  'background': p.background,
  'surface': p.surface,
  'surfaceAlt': p.surfaceAlt,
  'surfaceStrong': p.surfaceStrong,
  'primary': p.primary,
  'primaryPressed': p.primaryPressed,
  'primarySoft': p.primarySoft,
  'textPrimary': p.textPrimary,
  'textSecondary': p.textSecondary,
  'textTertiary': p.textTertiary,
  'border': p.border,
  'divider': p.divider,
  'gradientStart': p.gradientStart,
  'gradientMiddle': p.gradientMiddle,
  'gradientEnd': p.gradientEnd,
  'calmGradientStart': p.calmGradientStart,
  'calmGradientEnd': p.calmGradientEnd,
  'gradientContent': p.gradientContent,
  'shadow': p.shadow,
  'accent': p.accent!,
  'accentWarm': p.accentWarm!,
  'surfaceElevated': p.surfaceElevated,
  'surfaceDock': p.surfaceDock,
  'overlayScrim': p.overlayScrim,
  'borderStrong': p.borderStrong,
  'selectedLayer': p.selectedLayer,
  'pressedLayer': p.pressedLayer,
  'disabledText': p.disabledText,
  'disabledBackground': p.disabledBackground,
  'disabledBorder': p.disabledBorder,
  'focusRing': p.focusRing,
  'brandContainer': p.brandContainer,
  'skeletonBase': p.skeletonBase,
  'skeletonShimmer': p.skeletonShimmer,
  'elevation1': p.elevation1,
  'elevation2': p.elevation2,
  'surfaceTopHighlight': p.surfaceTopHighlight,
  'onBrandPrimary': p.onBrandPrimary,
  'brandPrimaryContent': p.brandPrimaryContent,
  'brandSecondaryDecorative': p.brandSecondaryDecorative,
  'brandSecondaryContent': p.brandSecondaryContent,
  'themeDecorativeAccent': p.themeDecorativeAccent,
  'overviewGlow': p.overviewGlow,
  'navigationActive': p.navigationActive,
  'focus': p.focus,
  'overviewStart': p.overviewStart,
  'overviewEnd': p.overviewEnd,
  'currencyAccent': p.currencyAccent,
  'fieldCurrency': p.fieldCurrency,
  'overviewTimelineAccent': p.overviewTimelineAccent,
  'accountAccent': p.accountAccent,
  'accountIconBackground': p.accountIconBackground,
  'fieldLogin': p.fieldLogin,
  'fieldPhone': p.fieldPhone,
  'fieldEmail': p.fieldEmail,
  'fieldPassword': p.fieldPassword,
  'fieldUrl': p.fieldUrl,
  'fieldSubscription': p.fieldSubscription,
  'fieldNote': p.fieldNote,
  'subscriptionAccent': p.subscriptionAccent,
  'renewalAccent': p.renewalAccent,
  'subscriptionIconBackground': p.subscriptionIconBackground,
  'actionPrimary': p.actionPrimary,
  'actionSecondary': p.actionSecondary,
  'inputFocus': p.inputFocus,
  'statusNormal': p.statusNormal,
  'statusRenewSoon': p.statusRenewSoon,
  'statusDanger': p.statusDanger,
  'statusCancelled': p.statusCancelled,
  'statusPaused': p.statusPaused,
  'statusInformation': p.statusInformation,
};

void _expectMaterial({
  required CardockThemeFamily family,
  required String mode,
  required CardockMaterialProfile runtime,
  required Map<String, Object?> json,
}) {
  final reason = family.name + '/' + mode;
  expect(runtime.kind.name, json['kind'], reason: reason);
  expect(runtime.cardBorderWidth, json['cardBorderWidth'], reason: reason);
  expect(
    runtime.elevatedBorderWidth,
    json['elevatedBorderWidth'],
    reason: reason,
  );
  expect(
    runtime.heroPrimaryMetricFill.toARGB32(),
    _parseColor(json['heroPrimaryMetricFill']! as String).toARGB32(),
    reason: reason,
  );
  expect(
    runtime.heroPrimaryMetricBorder.toARGB32(),
    _parseColor(json['heroPrimaryMetricBorder']! as String).toARGB32(),
    reason: reason,
  );
  expect(
    runtime.heroMiniMetricFill.toARGB32(),
    _parseColor(json['heroMiniMetricFill']! as String).toARGB32(),
    reason: reason,
  );
  expect(
    runtime.heroMiniMetricBorder.toARGB32(),
    _parseColor(json['heroMiniMetricBorder']! as String).toARGB32(),
    reason: reason,
  );
  expect(runtime.textureAsset, json['textureAsset'], reason: reason);
  expect(runtime.textureOpacity, json['textureOpacity'], reason: reason);
  expect(
    runtime.surfaceGradientEnabled,
    json['surfaceGradientEnabled'],
    reason: reason,
  );
  final shadowGroups = <String, List<CardockShadowSpec>>{
    'cardShadows': runtime.cardShadows,
    'elevatedCardShadows': runtime.elevatedCardShadows,
    'heroShadows': runtime.heroShadows,
    'dockShadows': runtime.dockShadows,
  };
  for (final group in shadowGroups.entries) {
    final expected = json[group.key]! as List<Object?>;
    expect(group.value, hasLength(expected.length), reason: reason);
    for (var index = 0; index < expected.length; index += 1) {
      final item = expected[index]! as Map<String, Object?>;
      final actual = group.value[index];
      expect(
        actual.color.toARGB32(),
        _parseColor(item['color']! as String).toARGB32(),
        reason: reason,
      );
      expect(actual.blurRadius, item['blurRadius'], reason: reason);
      expect(actual.spreadRadius, item['spreadRadius'], reason: reason);
      expect(actual.offset.dx, item['dx'], reason: reason);
      expect(actual.offset.dy, item['dy'], reason: reason);
    }
  }
}

Color _parseColor(String value) {
  var raw = value.substring(1);
  if (raw.length == 6) raw = 'FF' + raw;
  return Color(int.parse(raw, radix: 16));
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

Color _onColor(Color background) => _contrast(Colors.white, background) >= 4.5
    ? Colors.white
    : const Color(0xFF101828);

Color _readableColor(Color source, Color fallback, List<Color> backgrounds) {
  if (backgrounds.every((item) => _contrast(source, item) >= 4.5)) {
    return source;
  }
  for (var step = 1; step <= 100; step += 1) {
    final candidate = Color.lerp(source, fallback, step / 100)!;
    if (backgrounds.every((item) => _contrast(candidate, item) >= 4.5)) {
      return candidate;
    }
  }
  return fallback;
}
