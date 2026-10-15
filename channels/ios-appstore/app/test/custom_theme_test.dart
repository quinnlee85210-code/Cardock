import 'package:account_subscription_manager/core/theme/cardock_theme_types.dart';
import 'package:account_subscription_manager/core/theme/custom_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('安全默认为Custom V2且保留七组31个token', () {
    const theme = CardockCustomTheme.defaults;
    final json = theme.toJson();
    final light = json['light']! as Map<String, Object>;

    expect(json['schemaVersion'], 2);
    expect(json['launcherFallback'], 'ceramicBlue');
    expect(json['quickControls'], <String, Object>{
      'accentHue': 232.0,
      'chromaPreset': 'standard',
      'backgroundDepth': 'deep',
      'neutralTemperature': 'neutral',
    });
    expect((light['foundation']! as Map<String, Object>), hasLength(6));
    expect((light['brandNavigation']! as Map<String, Object>), hasLength(4));
    expect((light['homeOverview']! as Map<String, Object>), hasLength(3));
    final accounts = light['accounts']! as Map<String, Object>;
    expect(accounts, hasLength(3));
    expect(accounts['fieldPalette']! as List<Object>, hasLength(5));
    expect((light['subscriptions']! as Map<String, Object>), hasLength(3));
    expect((light['formsActions']! as Map<String, Object>), hasLength(3));
    expect((light['semanticStates']! as Map<String, Object>), hasLength(5));
    expect(6 + 4 + 3 + 2 + 5 + 3 + 3 + 5, 31);
    expect(theme.validate(), isEmpty);
    expect(theme.colorsFor(Brightness.light), theme.light);
    expect(theme.colorsFor(Brightness.dark), theme.dark);
  });

  test('V4原浅色低对比度值会返回精确问题而安全默认已修正', () {
    final original = CardockCustomTheme.tryParse(<String, Object>{
      'schemaVersion': 1,
      'launcherFallback': 'standard',
      'light': <String, Object>{
        'foundation': <String, Object>{'border': '#D8DFEC'},
        'brandNavigation': <String, Object>{
          'brandSecondary': '#20B7C9',
          'focus': '#20B7C9',
        },
        'accounts': <String, Object>{
          'fieldPalette': <Object>[
            '#4C7DF0',
            '#27B877',
            '#8B65E8',
            '#F2A33A',
            '#18A7C6',
          ],
        },
        'semanticStates': <String, Object>{
          'success': '#2DBE7F',
          'warning': '#E99A34',
        },
      },
    });

    final issues = original.validate();
    expect(issues.length, greaterThanOrEqualTo(8));
    expect(
      issues.map((issue) => issue.token),
      contains('light.foundation.border/surface'),
    );
    expect(
      issues.map((issue) => issue.token),
      contains('light.brandNavigation.brandSecondary/background'),
    );
    expect(
      issues.map((issue) => issue.token),
      contains('light.accounts.fieldPalette[1]/surface'),
    );
    expect(issues.every((issue) => issue.ratio < issue.required), isTrue);
    expect(CardockCustomTheme.defaults.validate(), isEmpty);
  });

  test('浅深色31 token与launcherFallback JSON往返且输出严格大写RRGGBB', () {
    final original = CardockCustomTheme.defaults.copyWith(
      launcherFallback: CardockLauncherFamily.mistCoral,
      quickSettings: const CardockCustomQuickSettings(
        accentHue: 38,
        chromaPreset: CardockCustomChromaPreset.vivid,
        backgroundDepth: CardockCustomBackgroundDepth.oled,
        neutralTemperature: CardockCustomNeutralTemperature.warm,
      ),
      light: CardockCustomTheme.defaults.light.copyWith(
        background: const Color(0xFFEEF2FA),
        fieldEmail: const Color(0xFF7651D2),
      ),
      dark: CardockCustomTheme.defaults.dark.copyWith(
        background: const Color(0xFF101827),
        fieldEmail: const Color(0xFFC09BFF),
      ),
    );

    final json = original.toJson();
    final restored = CardockCustomTheme.tryParse(json);

    expect(restored, original);
    expect(restored.launcherFallback, CardockLauncherFamily.mistCoral);
    expect(restored.quickSettings, original.quickSettings);
    final light = json['light']! as Map<String, Object>;
    final foundation = light['foundation']! as Map<String, Object>;
    final accounts = light['accounts']! as Map<String, Object>;
    expect(foundation['background'], '#EEF2FA');
    expect((accounts['fieldPalette']! as List<Object>)[2], '#7651D2');
  });

  test('schema1缺组缺token与非法HEX逐token回退且合法小写HEX可读取', () {
    final parsed = CardockCustomTheme.tryParse(<String, Object>{
      'schemaVersion': 1,
      'launcherFallback': 'future',
      'light': <String, Object>{
        'foundation': <String, Object>{
          'background': '#abcdef',
          'surface': '#FFF',
          'text': '#FFFFFFFF',
          'border': '7F8CA0',
        },
        'accounts': <String, Object>{
          'fieldPalette': <Object>['#123456', '#xyzxyz', '#ABCDEF'],
        },
      },
    });

    expect(parsed.launcherFallback, CardockLauncherFamily.ceramicBlue);
    expect(parsed.light.background, const Color(0xFFABCDEF));
    expect(parsed.light.surface, CardockCustomTheme.defaults.light.surface);
    expect(parsed.light.text, CardockCustomTheme.defaults.light.text);
    expect(parsed.light.border, CardockCustomTheme.defaults.light.border);
    expect(parsed.light.fieldLogin, const Color(0xFF123456));
    expect(
      parsed.light.fieldPhone,
      CardockCustomTheme.defaults.light.fieldPhone,
    );
    expect(parsed.light.fieldEmail, const Color(0xFFABCDEF));
    expect(
      parsed.light.fieldPassword,
      CardockCustomTheme.defaults.light.fieldPassword,
    );
    expect(parsed.dark, CardockCustomTheme.defaults.dark);
  });

  test('缺少或未来schemaVersion均只解析已知路径并逐token安全回退', () {
    final current = CardockCustomTheme.tryParse(<String, Object>{
      'light': <String, Object>{
        'foundation': <String, Object>{'background': '#123456'},
      },
    });
    final future = CardockCustomTheme.tryParse(<String, Object>{
      'schemaVersion': 99,
      'launcherFallback': 'vivid',
      'light': <String, Object>{
        'foundation': <String, Object>{'background': '#123456'},
      },
    });

    expect(current.light.background, const Color(0xFF123456));
    expect(future.launcherFallback, CardockLauncherFamily.mistCoral);
    expect(future.light.background, const Color(0xFF123456));
    expect(future.light.surface, CardockCustomTheme.defaults.light.surface);
    expect(future.dark, CardockCustomTheme.defaults.dark);
    expect(CardockCustomTheme.tryParse('broken'), CardockCustomTheme.defaults);
  });

  test('对比度与danger等于success返回亮度组和精确token ratio required', () {
    const sameState = Color(0xFF147F58);
    final invalid = CardockCustomTheme.defaults.copyWith(
      light: CardockCustomTheme.defaults.light.copyWith(
        text: Colors.white,
        danger: sameState,
        success: sameState,
      ),
    );

    final issues = validateCustomTheme(invalid);
    final textIssue = issues.firstWhere(
      (issue) => issue.token == 'light.foundation.text/background',
    );
    final semanticIssue = issues.firstWhere(
      (issue) => issue.token == 'light.semanticStates.danger/success',
    );

    expect(textIssue.required, 4.5);
    expect(textIssue.ratio, lessThan(4.5));
    expect(textIssue.editableToken, 'light.foundation.text');
    expect(textIssue.foregroundHex, '#FFFFFF');
    expect(textIssue.backgroundHex, '#F5F7FC');
    expect(textIssue.recommendedHex, '#142033');
    expect(semanticIssue.ratio, 1.0);
    expect(semanticIssue.required, 1.01);
  });

  test('Custom V1迁移保留已知颜色且逐项回退V2快速控件', () {
    final migrated = CardockCustomTheme.tryParse(<String, Object>{
      'schemaVersion': 1,
      'launcherFallback': 'prime',
      'quickControls': <String, Object>{
        'accentHue': double.nan,
        'chromaPreset': 'future',
        'backgroundDepth': 'oled',
        'neutralTemperature': 'warm',
      },
      'light': <String, Object>{
        'foundation': <String, Object>{
          'background': '#ABCDEF',
          'surface': 'broken',
        },
      },
    });

    expect(migrated.launcherFallback, CardockLauncherFamily.obsidianGold);
    expect(migrated.light.background, const Color(0xFFABCDEF));
    expect(migrated.light.surface, CardockCustomTheme.defaults.light.surface);
    expect(migrated.quickSettings.accentHue, 232);
    expect(
      migrated.quickSettings.chromaPreset,
      CardockCustomChromaPreset.standard,
    );
    expect(
      migrated.quickSettings.backgroundDepth,
      CardockCustomBackgroundDepth.oled,
    );
    expect(
      migrated.quickSettings.neutralTemperature,
      CardockCustomNeutralTemperature.warm,
    );
    expect(migrated.toJson()['schemaVersion'], 2);
  });

  test('四项快速控件在色相与全枚举组合下均自动夹取为可保存主题', () {
    for (final hue in <double>[0, 60, 120, 180, 232, 300, 360]) {
      for (final chroma in CardockCustomChromaPreset.values) {
        for (final depth in CardockCustomBackgroundDepth.values) {
          for (final temperature in CardockCustomNeutralTemperature.values) {
            final quick = CardockCustomQuickSettings(
              accentHue: hue,
              chromaPreset: chroma,
              backgroundDepth: depth,
              neutralTemperature: temperature,
            );
            final theme = cardockGenerateQuickTheme(
              quickSettings: quick,
              launcherFallback: CardockLauncherFamily.mistCoral,
            );

            expect(theme.quickSettings, quick);
            expect(theme.launcherFallback, CardockLauncherFamily.mistCoral);
            expect(
              theme.validate(),
              isEmpty,
              reason: '$hue/$chroma/$depth/$temperature',
            );
          }
        }
      }
    }
  });

  test('单模块重置和自动修正不影响quick、launcher与无关模块', () {
    const quick = CardockCustomQuickSettings(
      accentHue: 18,
      chromaPreset: CardockCustomChromaPreset.soft,
    );
    final invalid = CardockCustomTheme.defaults.copyWith(
      launcherFallback: CardockLauncherFamily.obsidianGold,
      quickSettings: quick,
      light: CardockCustomTheme.defaults.light.copyWith(
        text: Colors.white,
        accountAccent: const Color(0xFF943428),
      ),
    );
    final reset = cardockResetCustomGroup(
      invalid,
      brightness: Brightness.light,
      group: CardockCustomColorGroup.foundation,
    );
    final fixed = cardockAutoFixCustomTheme(invalid);

    expect(reset.light.text, CardockCustomTheme.defaults.light.text);
    expect(reset.light.accountAccent, invalid.light.accountAccent);
    expect(fixed.validate(), isEmpty);
    expect(fixed.light.accountAccent, invalid.light.accountAccent);
    expect(fixed.quickSettings, quick);
    expect(fixed.launcherFallback, CardockLauncherFamily.obsidianGold);
  });

  test('按真实按钮文字、语义图标底色与状态胶囊渲染结果拦截临界色', () {
    const borderline = Color(0xFF686868);
    final invalid = CardockCustomTheme.defaults.copyWith(
      dark: CardockCustomTheme.defaults.dark.copyWith(
        actionSecondary: borderline,
        fieldLogin: borderline,
        neutral: borderline,
      ),
    );

    final issues = invalid.validate();
    final secondary = issues.firstWhere(
      (issue) => issue.token == 'dark.formsActions.actionSecondary/surface',
    );
    final semanticIcon = issues.firstWhere(
      (issue) =>
          issue.token == 'dark.accounts.fieldPalette[0]/semanticIconBackground',
    );
    final statusPill = issues.firstWhere(
      (issue) => issue.token == 'dark.semanticStates.neutral/pillBackground',
    );

    expect(secondary.required, 4.5);
    expect(semanticIcon.required, 3.0);
    expect(statusPill.required, 4.5);
    expect(secondary.ratio, lessThan(secondary.required));
    expect(semanticIcon.ratio, lessThan(semanticIcon.required));
    expect(statusPill.ratio, lessThan(statusPill.required));
  });
}
