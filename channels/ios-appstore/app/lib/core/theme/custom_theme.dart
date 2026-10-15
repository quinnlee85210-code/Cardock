import 'package:flutter/material.dart';

import 'cardock_theme_types.dart';

enum CardockCustomChromaPreset { soft, standard, vivid }

extension CardockCustomChromaPresetLabel on CardockCustomChromaPreset {
  String get label => switch (this) {
    CardockCustomChromaPreset.soft => '柔和',
    CardockCustomChromaPreset.standard => '标准',
    CardockCustomChromaPreset.vivid => '浓郁',
  };
}

enum CardockCustomBackgroundDepth { deep, deeper, oled }

extension CardockCustomBackgroundDepthLabel on CardockCustomBackgroundDepth {
  String get label => switch (this) {
    CardockCustomBackgroundDepth.deep => '深',
    CardockCustomBackgroundDepth.deeper => '极深',
    CardockCustomBackgroundDepth.oled => 'OLED',
  };
}

enum CardockCustomNeutralTemperature { cool, neutral, warm }

extension CardockCustomNeutralTemperatureLabel
    on CardockCustomNeutralTemperature {
  String get label => switch (this) {
    CardockCustomNeutralTemperature.cool => '冷',
    CardockCustomNeutralTemperature.neutral => '中',
    CardockCustomNeutralTemperature.warm => '暖',
  };
}

/// The four safe, user-facing controls introduced by the V5 Custom editor.
///
/// They live inside the Custom child schema. The top-level appearance format
/// deliberately remains V3, and old Custom V1 payloads simply receive these
/// defaults while retaining every recognized color token.
@immutable
class CardockCustomQuickSettings {
  const CardockCustomQuickSettings({
    this.accentHue = 232,
    this.chromaPreset = CardockCustomChromaPreset.standard,
    this.backgroundDepth = CardockCustomBackgroundDepth.deep,
    this.neutralTemperature = CardockCustomNeutralTemperature.neutral,
  });

  static const CardockCustomQuickSettings defaults =
      CardockCustomQuickSettings();

  final double accentHue;
  final CardockCustomChromaPreset chromaPreset;
  final CardockCustomBackgroundDepth backgroundDepth;
  final CardockCustomNeutralTemperature neutralTemperature;

  CardockCustomQuickSettings copyWith({
    double? accentHue,
    CardockCustomChromaPreset? chromaPreset,
    CardockCustomBackgroundDepth? backgroundDepth,
    CardockCustomNeutralTemperature? neutralTemperature,
  }) {
    return CardockCustomQuickSettings(
      accentHue: accentHue ?? this.accentHue,
      chromaPreset: chromaPreset ?? this.chromaPreset,
      backgroundDepth: backgroundDepth ?? this.backgroundDepth,
      neutralTemperature: neutralTemperature ?? this.neutralTemperature,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'accentHue': accentHue,
    'chromaPreset': chromaPreset.name,
    'backgroundDepth': backgroundDepth.name,
    'neutralTemperature': neutralTemperature.name,
  };

  static CardockCustomQuickSettings tryParse(Object? value) {
    final map = _asMap(value);
    if (map == null) return defaults;
    final rawHue = map['accentHue'];
    final parsedHue = rawHue is num ? rawHue.toDouble() : null;
    final safeHue =
        parsedHue != null &&
            parsedHue.isFinite &&
            parsedHue >= 0 &&
            parsedHue <= 360
        ? parsedHue
        : defaults.accentHue;
    return CardockCustomQuickSettings(
      accentHue: safeHue,
      chromaPreset:
          _enumFromName(
            CardockCustomChromaPreset.values,
            map['chromaPreset'],
          ) ??
          defaults.chromaPreset,
      backgroundDepth:
          _enumFromName(
            CardockCustomBackgroundDepth.values,
            map['backgroundDepth'],
          ) ??
          defaults.backgroundDepth,
      neutralTemperature:
          _enumFromName(
            CardockCustomNeutralTemperature.values,
            map['neutralTemperature'],
          ) ??
          defaults.neutralTemperature,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CardockCustomQuickSettings &&
          accentHue == other.accentHue &&
          chromaPreset == other.chromaPreset &&
          backgroundDepth == other.backgroundDepth &&
          neutralTemperature == other.neutralTemperature;

  @override
  int get hashCode =>
      Object.hash(accentHue, chromaPreset, backgroundDepth, neutralTemperature);
}

enum CardockCustomColorGroup {
  foundation,
  brandNavigation,
  homeOverview,
  accounts,
  subscriptions,
  formsActions,
  semanticStates,
}

@immutable
class CardockCustomTheme {
  const CardockCustomTheme({
    required this.launcherFallback,
    required this.light,
    required this.dark,
    this.quickSettings = CardockCustomQuickSettings.defaults,
  });

  static const int schemaVersion = 2;

  /// A contrast-safe refinement of the V4 visual defaults.
  ///
  /// The handoff's original light accents contain several colors below 3:1
  /// against their rendered surfaces. These values retain the same hues while
  /// being safe to save under [validateCustomTheme].
  static const CardockCustomTheme defaults = CardockCustomTheme(
    launcherFallback: CardockLauncherFamily.ceramicBlue,
    light: CardockCustomColors(
      background: Color(0xFFF5F7FC),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFEDF1F8),
      text: Color(0xFF142033),
      textSecondary: Color(0xFF5D6A7F),
      border: Color(0xFF7F8CA0),
      brandPrimary: Color(0xFF5967E8),
      brandSecondary: Color(0xFF137F8D),
      navigationActive: Color(0xFF5967E8),
      focus: Color(0xFF137F8D),
      overviewStart: Color(0xFF4858D6),
      overviewEnd: Color(0xFF12697A),
      currencyAccent: Color(0xFFFFF0C2),
      accountAccent: Color(0xFFD45B4E),
      accountIconBackground: Color(0xFFFDECE8),
      fieldLogin: Color(0xFF4C7DF0),
      fieldPhone: Color(0xFF15865A),
      fieldEmail: Color(0xFF8B65E8),
      fieldPassword: Color(0xFFA66400),
      fieldUrl: Color(0xFF087F96),
      subscriptionAccent: Color(0xFF0D8D82),
      renewalAccent: Color(0xFFA76008),
      subscriptionIconBackground: Color(0xFFE8F7F4),
      actionPrimary: Color(0xFF5967E8),
      actionSecondary: Color(0xFF137F8D),
      inputFocus: Color(0xFF5967E8),
      success: Color(0xFF147F58),
      warning: Color(0xFFA76008),
      danger: Color(0xFFE45968),
      paused: Color(0xFF8A67DD),
      neutral: Color(0xFF7B879D),
    ),
    dark: CardockCustomColors(
      background: Color(0xFF0C1220),
      surface: Color(0xFF141D2D),
      surfaceAlt: Color(0xFF1B2638),
      text: Color(0xFFF5F7FB),
      textSecondary: Color(0xFFA7B1C2),
      border: Color(0xFF637590),
      brandPrimary: Color(0xFF8490FF),
      brandSecondary: Color(0xFF4DD5E2),
      navigationActive: Color(0xFF8490FF),
      focus: Color(0xFF4DD5E2),
      overviewStart: Color(0xFF29336D),
      overviewEnd: Color(0xFF14566A),
      currencyAccent: Color(0xFFF4B95E),
      accountAccent: Color(0xFFFF8E7C),
      accountIconBackground: Color(0xFF39232A),
      fieldLogin: Color(0xFF75A0FF),
      fieldPhone: Color(0xFF54D49B),
      fieldEmail: Color(0xFFB08CF5),
      fieldPassword: Color(0xFFF5BB61),
      fieldUrl: Color(0xFF50C7DB),
      subscriptionAccent: Color(0xFF5DDEC9),
      renewalAccent: Color(0xFFF4B95E),
      subscriptionIconBackground: Color(0xFF183632),
      actionPrimary: Color(0xFF8490FF),
      actionSecondary: Color(0xFF4DD5E2),
      inputFocus: Color(0xFF8490FF),
      success: Color(0xFF53D89A),
      warning: Color(0xFFF4B95E),
      danger: Color(0xFFFF7E8C),
      paused: Color(0xFFB08CF5),
      neutral: Color(0xFF98A5B8),
    ),
  );

  final CardockLauncherFamily launcherFallback;
  final CardockCustomColors light;
  final CardockCustomColors dark;
  final CardockCustomQuickSettings quickSettings;

  CardockCustomColors colorsFor(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  CardockCustomTheme copyWith({
    CardockLauncherFamily? launcherFallback,
    CardockCustomColors? light,
    CardockCustomColors? dark,
    CardockCustomQuickSettings? quickSettings,
  }) {
    return CardockCustomTheme(
      launcherFallback: launcherFallback ?? this.launcherFallback,
      light: light ?? this.light,
      dark: dark ?? this.dark,
      quickSettings: quickSettings ?? this.quickSettings,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'schemaVersion': schemaVersion,
    'launcherFallback': launcherFallback.name,
    'quickControls': quickSettings.toJson(),
    'light': light.toJson(),
    'dark': dark.toJson(),
  };

  /// Parses recognized token paths defensively. Missing, malformed, or
  /// future-schema values fall back one token at a time; unknown fields are
  /// ignored, so a future editor cannot make the current app fail at startup.
  static CardockCustomTheme tryParse(Object? value) {
    final map = _asMap(value);
    if (map == null) return defaults;

    return CardockCustomTheme(
      launcherFallback:
          cardockLauncherFamilyFromName(map['launcherFallback']) ??
          defaults.launcherFallback,
      quickSettings: CardockCustomQuickSettings.tryParse(map['quickControls']),
      light: CardockCustomColors.tryParse(
        map['light'],
        fallback: defaults.light,
      ),
      dark: CardockCustomColors.tryParse(map['dark'], fallback: defaults.dark),
    );
  }

  List<CardockContrastIssue> validate() => validateCustomTheme(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CardockCustomTheme &&
          launcherFallback == other.launcherFallback &&
          quickSettings == other.quickSettings &&
          light == other.light &&
          dark == other.dark;

  @override
  int get hashCode => Object.hash(launcherFallback, quickSettings, light, dark);
}

@immutable
class CardockCustomColors {
  const CardockCustomColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.text,
    required this.textSecondary,
    required this.border,
    required this.brandPrimary,
    required this.brandSecondary,
    required this.navigationActive,
    required this.focus,
    required this.overviewStart,
    required this.overviewEnd,
    required this.currencyAccent,
    required this.accountAccent,
    required this.accountIconBackground,
    required this.fieldLogin,
    required this.fieldPhone,
    required this.fieldEmail,
    required this.fieldPassword,
    required this.fieldUrl,
    required this.subscriptionAccent,
    required this.renewalAccent,
    required this.subscriptionIconBackground,
    required this.actionPrimary,
    required this.actionSecondary,
    required this.inputFocus,
    required this.success,
    required this.warning,
    required this.danger,
    required this.paused,
    required this.neutral,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color text;
  final Color textSecondary;
  final Color border;
  final Color brandPrimary;
  final Color brandSecondary;
  final Color navigationActive;
  final Color focus;
  final Color overviewStart;
  final Color overviewEnd;
  final Color currencyAccent;
  final Color accountAccent;
  final Color accountIconBackground;
  final Color fieldLogin;
  final Color fieldPhone;
  final Color fieldEmail;
  final Color fieldPassword;
  final Color fieldUrl;
  final Color subscriptionAccent;
  final Color renewalAccent;
  final Color subscriptionIconBackground;
  final Color actionPrimary;
  final Color actionSecondary;
  final Color inputFocus;
  final Color success;
  final Color warning;
  final Color danger;
  final Color paused;
  final Color neutral;

  List<Color> get fieldPalette => <Color>[
    fieldLogin,
    fieldPhone,
    fieldEmail,
    fieldPassword,
    fieldUrl,
  ];

  CardockCustomColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? text,
    Color? textSecondary,
    Color? border,
    Color? brandPrimary,
    Color? brandSecondary,
    Color? navigationActive,
    Color? focus,
    Color? overviewStart,
    Color? overviewEnd,
    Color? currencyAccent,
    Color? accountAccent,
    Color? accountIconBackground,
    Color? fieldLogin,
    Color? fieldPhone,
    Color? fieldEmail,
    Color? fieldPassword,
    Color? fieldUrl,
    Color? subscriptionAccent,
    Color? renewalAccent,
    Color? subscriptionIconBackground,
    Color? actionPrimary,
    Color? actionSecondary,
    Color? inputFocus,
    Color? success,
    Color? warning,
    Color? danger,
    Color? paused,
    Color? neutral,
  }) {
    return CardockCustomColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
      brandPrimary: brandPrimary ?? this.brandPrimary,
      brandSecondary: brandSecondary ?? this.brandSecondary,
      navigationActive: navigationActive ?? this.navigationActive,
      focus: focus ?? this.focus,
      overviewStart: overviewStart ?? this.overviewStart,
      overviewEnd: overviewEnd ?? this.overviewEnd,
      currencyAccent: currencyAccent ?? this.currencyAccent,
      accountAccent: accountAccent ?? this.accountAccent,
      accountIconBackground:
          accountIconBackground ?? this.accountIconBackground,
      fieldLogin: fieldLogin ?? this.fieldLogin,
      fieldPhone: fieldPhone ?? this.fieldPhone,
      fieldEmail: fieldEmail ?? this.fieldEmail,
      fieldPassword: fieldPassword ?? this.fieldPassword,
      fieldUrl: fieldUrl ?? this.fieldUrl,
      subscriptionAccent: subscriptionAccent ?? this.subscriptionAccent,
      renewalAccent: renewalAccent ?? this.renewalAccent,
      subscriptionIconBackground:
          subscriptionIconBackground ?? this.subscriptionIconBackground,
      actionPrimary: actionPrimary ?? this.actionPrimary,
      actionSecondary: actionSecondary ?? this.actionSecondary,
      inputFocus: inputFocus ?? this.inputFocus,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      paused: paused ?? this.paused,
      neutral: neutral ?? this.neutral,
    );
  }

  /// Replaces exactly one advanced editor group and leaves every other token
  /// untouched. This powers both per-module reset and conservative auto-fix.
  CardockCustomColors copyGroupFrom(
    CardockCustomColors source,
    CardockCustomColorGroup group,
  ) {
    return switch (group) {
      CardockCustomColorGroup.foundation => copyWith(
        background: source.background,
        surface: source.surface,
        surfaceAlt: source.surfaceAlt,
        text: source.text,
        textSecondary: source.textSecondary,
        border: source.border,
      ),
      CardockCustomColorGroup.brandNavigation => copyWith(
        brandPrimary: source.brandPrimary,
        brandSecondary: source.brandSecondary,
        navigationActive: source.navigationActive,
        focus: source.focus,
      ),
      CardockCustomColorGroup.homeOverview => copyWith(
        overviewStart: source.overviewStart,
        overviewEnd: source.overviewEnd,
        currencyAccent: source.currencyAccent,
      ),
      CardockCustomColorGroup.accounts => copyWith(
        accountAccent: source.accountAccent,
        accountIconBackground: source.accountIconBackground,
        fieldLogin: source.fieldLogin,
        fieldPhone: source.fieldPhone,
        fieldEmail: source.fieldEmail,
        fieldPassword: source.fieldPassword,
        fieldUrl: source.fieldUrl,
      ),
      CardockCustomColorGroup.subscriptions => copyWith(
        subscriptionAccent: source.subscriptionAccent,
        renewalAccent: source.renewalAccent,
        subscriptionIconBackground: source.subscriptionIconBackground,
      ),
      CardockCustomColorGroup.formsActions => copyWith(
        actionPrimary: source.actionPrimary,
        actionSecondary: source.actionSecondary,
        inputFocus: source.inputFocus,
      ),
      CardockCustomColorGroup.semanticStates => copyWith(
        success: source.success,
        warning: source.warning,
        danger: source.danger,
        paused: source.paused,
        neutral: source.neutral,
      ),
    };
  }

  Map<String, Object> toJson() => <String, Object>{
    'foundation': <String, Object>{
      'background': _colorToHex(background),
      'surface': _colorToHex(surface),
      'surfaceAlt': _colorToHex(surfaceAlt),
      'text': _colorToHex(text),
      'textSecondary': _colorToHex(textSecondary),
      'border': _colorToHex(border),
    },
    'brandNavigation': <String, Object>{
      'brandPrimary': _colorToHex(brandPrimary),
      'brandSecondary': _colorToHex(brandSecondary),
      'navigationActive': _colorToHex(navigationActive),
      'focus': _colorToHex(focus),
    },
    'homeOverview': <String, Object>{
      'overviewStart': _colorToHex(overviewStart),
      'overviewEnd': _colorToHex(overviewEnd),
      'currencyAccent': _colorToHex(currencyAccent),
    },
    'accounts': <String, Object>{
      'accountAccent': _colorToHex(accountAccent),
      'accountIconBackground': _colorToHex(accountIconBackground),
      'fieldPalette': fieldPalette.map(_colorToHex).toList(growable: false),
    },
    'subscriptions': <String, Object>{
      'subscriptionAccent': _colorToHex(subscriptionAccent),
      'renewalAccent': _colorToHex(renewalAccent),
      'subscriptionIconBackground': _colorToHex(subscriptionIconBackground),
    },
    'formsActions': <String, Object>{
      'actionPrimary': _colorToHex(actionPrimary),
      'actionSecondary': _colorToHex(actionSecondary),
      'inputFocus': _colorToHex(inputFocus),
    },
    'semanticStates': <String, Object>{
      'success': _colorToHex(success),
      'warning': _colorToHex(warning),
      'danger': _colorToHex(danger),
      'paused': _colorToHex(paused),
      'neutral': _colorToHex(neutral),
    },
  };

  static CardockCustomColors tryParse(
    Object? value, {
    required CardockCustomColors fallback,
  }) {
    final root = _asMap(value);
    final foundation = _childMap(root, 'foundation');
    final brand = _childMap(root, 'brandNavigation');
    final overview = _childMap(root, 'homeOverview');
    final accounts = _childMap(root, 'accounts');
    final subscriptions = _childMap(root, 'subscriptions');
    final forms = _childMap(root, 'formsActions');
    final states = _childMap(root, 'semanticStates');
    final rawFields = accounts?['fieldPalette'];
    final fields = rawFields is List<Object?> ? rawFields : const <Object?>[];

    Color read(
      Map<Object?, Object?>? group,
      String token,
      Color tokenFallback,
    ) => _parseHexColor(group?[token]) ?? tokenFallback;

    Color readField(int index, Color tokenFallback) => index < fields.length
        ? _parseHexColor(fields[index]) ?? tokenFallback
        : tokenFallback;

    return CardockCustomColors(
      background: read(foundation, 'background', fallback.background),
      surface: read(foundation, 'surface', fallback.surface),
      surfaceAlt: read(foundation, 'surfaceAlt', fallback.surfaceAlt),
      text: read(foundation, 'text', fallback.text),
      textSecondary: read(foundation, 'textSecondary', fallback.textSecondary),
      border: read(foundation, 'border', fallback.border),
      brandPrimary: read(brand, 'brandPrimary', fallback.brandPrimary),
      brandSecondary: read(brand, 'brandSecondary', fallback.brandSecondary),
      navigationActive: read(
        brand,
        'navigationActive',
        fallback.navigationActive,
      ),
      focus: read(brand, 'focus', fallback.focus),
      overviewStart: read(overview, 'overviewStart', fallback.overviewStart),
      overviewEnd: read(overview, 'overviewEnd', fallback.overviewEnd),
      currencyAccent: read(overview, 'currencyAccent', fallback.currencyAccent),
      accountAccent: read(accounts, 'accountAccent', fallback.accountAccent),
      accountIconBackground: read(
        accounts,
        'accountIconBackground',
        fallback.accountIconBackground,
      ),
      fieldLogin: readField(0, fallback.fieldLogin),
      fieldPhone: readField(1, fallback.fieldPhone),
      fieldEmail: readField(2, fallback.fieldEmail),
      fieldPassword: readField(3, fallback.fieldPassword),
      fieldUrl: readField(4, fallback.fieldUrl),
      subscriptionAccent: read(
        subscriptions,
        'subscriptionAccent',
        fallback.subscriptionAccent,
      ),
      renewalAccent: read(
        subscriptions,
        'renewalAccent',
        fallback.renewalAccent,
      ),
      subscriptionIconBackground: read(
        subscriptions,
        'subscriptionIconBackground',
        fallback.subscriptionIconBackground,
      ),
      actionPrimary: read(forms, 'actionPrimary', fallback.actionPrimary),
      actionSecondary: read(forms, 'actionSecondary', fallback.actionSecondary),
      inputFocus: read(forms, 'inputFocus', fallback.inputFocus),
      success: read(states, 'success', fallback.success),
      warning: read(states, 'warning', fallback.warning),
      danger: read(states, 'danger', fallback.danger),
      paused: read(states, 'paused', fallback.paused),
      neutral: read(states, 'neutral', fallback.neutral),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CardockCustomColors &&
          background == other.background &&
          surface == other.surface &&
          surfaceAlt == other.surfaceAlt &&
          text == other.text &&
          textSecondary == other.textSecondary &&
          border == other.border &&
          brandPrimary == other.brandPrimary &&
          brandSecondary == other.brandSecondary &&
          navigationActive == other.navigationActive &&
          focus == other.focus &&
          overviewStart == other.overviewStart &&
          overviewEnd == other.overviewEnd &&
          currencyAccent == other.currencyAccent &&
          accountAccent == other.accountAccent &&
          accountIconBackground == other.accountIconBackground &&
          fieldLogin == other.fieldLogin &&
          fieldPhone == other.fieldPhone &&
          fieldEmail == other.fieldEmail &&
          fieldPassword == other.fieldPassword &&
          fieldUrl == other.fieldUrl &&
          subscriptionAccent == other.subscriptionAccent &&
          renewalAccent == other.renewalAccent &&
          subscriptionIconBackground == other.subscriptionIconBackground &&
          actionPrimary == other.actionPrimary &&
          actionSecondary == other.actionSecondary &&
          inputFocus == other.inputFocus &&
          success == other.success &&
          warning == other.warning &&
          danger == other.danger &&
          paused == other.paused &&
          neutral == other.neutral;

  @override
  int get hashCode => Object.hashAll(<Object>[
    background,
    surface,
    surfaceAlt,
    text,
    textSecondary,
    border,
    brandPrimary,
    brandSecondary,
    navigationActive,
    focus,
    overviewStart,
    overviewEnd,
    currencyAccent,
    accountAccent,
    accountIconBackground,
    fieldLogin,
    fieldPhone,
    fieldEmail,
    fieldPassword,
    fieldUrl,
    subscriptionAccent,
    renewalAccent,
    subscriptionIconBackground,
    actionPrimary,
    actionSecondary,
    inputFocus,
    success,
    warning,
    danger,
    paused,
    neutral,
  ]);
}

/// Derives both brightness modes from the four V5 quick controls.
///
/// Generated values are validated through the same policy as manual colors.
/// Any combination that falls outside a safe contrast range is conservatively
/// clamped group-by-group, without touching the launcher fallback.
CardockCustomTheme cardockGenerateQuickTheme({
  required CardockCustomQuickSettings quickSettings,
  required CardockLauncherFamily launcherFallback,
}) {
  final generated = CardockCustomTheme(
    launcherFallback: launcherFallback,
    quickSettings: quickSettings,
    light: _generateQuickColors(quickSettings, Brightness.light),
    dark: _generateQuickColors(quickSettings, Brightness.dark),
  );
  return cardockAutoFixCustomTheme(generated);
}

CardockCustomColors _generateQuickColors(
  CardockCustomQuickSettings settings,
  Brightness brightness,
) {
  final dark = brightness == Brightness.dark;
  final fallback = dark
      ? CardockCustomTheme.defaults.dark
      : CardockCustomTheme.defaults.light;
  final foundation = _quickFoundation(settings, brightness);
  final saturation = switch (settings.chromaPreset) {
    CardockCustomChromaPreset.soft => 0.42,
    CardockCustomChromaPreset.standard => 0.60,
    CardockCustomChromaPreset.vivid => 0.76,
  };
  final hue = _normalizedHue(settings.accentHue);
  final readableFallback = dark ? Colors.white : const Color(0xFF101828);
  final accentSurfaces = <Color>[
    foundation.background,
    foundation.surface,
    foundation.surfaceAlt,
  ];

  Color accent(double offset, {double minimum = 3, double? lightness}) {
    final raw = HSLColor.fromAHSL(
      1,
      _normalizedHue(hue + offset),
      saturation,
      lightness ?? (dark ? 0.68 : 0.40),
    ).toColor();
    return cardockReadableTextColorFor(
      raw,
      fallback: readableFallback,
      backgrounds: accentSurfaces,
      minimum: minimum,
    );
  }

  final primary = accent(0);
  final secondary = accent(32, minimum: 4.5);
  final account = accent(18);
  final subscription = accent(142);
  final renewal = accent(70);
  final fieldColors = <Color>[
    accent(0),
    accent(132),
    accent(282),
    accent(58),
    accent(176),
  ];
  final overviewStart = HSLColor.fromAHSL(
    1,
    hue,
    saturation,
    dark ? 0.27 : 0.36,
  ).toColor();
  final overviewEnd = HSLColor.fromAHSL(
    1,
    _normalizedHue(hue + 30),
    (saturation * 0.86).clamp(0, 1),
    dark ? 0.19 : 0.27,
  ).toColor();
  final overviewForeground = cardockOnGradientColorFor(
    overviewStart,
    overviewEnd,
  );

  return fallback.copyWith(
    background: foundation.background,
    surface: foundation.surface,
    surfaceAlt: foundation.surfaceAlt,
    text: foundation.text,
    textSecondary: foundation.textSecondary,
    border: foundation.border,
    brandPrimary: primary,
    brandSecondary: secondary,
    navigationActive: primary,
    focus: secondary,
    overviewStart: overviewStart,
    overviewEnd: overviewEnd,
    // Legacy read compatibility only. V5 main amounts inherit primary text.
    currencyAccent: overviewForeground,
    accountAccent: account,
    accountIconBackground: Color.alphaBlend(
      account.withValues(alpha: dark ? 0.16 : 0.08),
      foundation.surface,
    ),
    fieldLogin: fieldColors[0],
    fieldPhone: fieldColors[1],
    fieldEmail: fieldColors[2],
    fieldPassword: fieldColors[3],
    fieldUrl: fieldColors[4],
    subscriptionAccent: subscription,
    renewalAccent: renewal,
    subscriptionIconBackground: Color.alphaBlend(
      subscription.withValues(alpha: dark ? 0.16 : 0.08),
      foundation.surface,
    ),
    actionPrimary: primary,
    actionSecondary: secondary,
    inputFocus: primary,
  );
}

({
  Color background,
  Color surface,
  Color surfaceAlt,
  Color text,
  Color textSecondary,
  Color border,
})
_quickFoundation(CardockCustomQuickSettings settings, Brightness brightness) {
  if (brightness == Brightness.light) {
    return switch (settings.neutralTemperature) {
      CardockCustomNeutralTemperature.cool => (
        background: const Color(0xFFF4F7FB),
        surface: const Color(0xFFFFFFFF),
        surfaceAlt: const Color(0xFFEAF0F7),
        text: const Color(0xFF162033),
        textSecondary: const Color(0xFF536174),
        border: const Color(0xFF7A8798),
      ),
      CardockCustomNeutralTemperature.neutral => (
        background: const Color(0xFFF6F7F8),
        surface: const Color(0xFFFFFFFF),
        surfaceAlt: const Color(0xFFEEEFF1),
        text: const Color(0xFF1B2028),
        textSecondary: const Color(0xFF59616D),
        border: const Color(0xFF7E8792),
      ),
      CardockCustomNeutralTemperature.warm => (
        background: const Color(0xFFFAF7F2),
        surface: const Color(0xFFFFFDFC),
        surfaceAlt: const Color(0xFFF2ECE4),
        text: const Color(0xFF28211C),
        textSecondary: const Color(0xFF685E56),
        border: const Color(0xFF8C8177),
      ),
    };
  }

  final depth = settings.backgroundDepth;
  return switch (settings.neutralTemperature) {
    CardockCustomNeutralTemperature.cool => switch (depth) {
      CardockCustomBackgroundDepth.deep => (
        background: const Color(0xFF0B111B),
        surface: const Color(0xFF131D29),
        surfaceAlt: const Color(0xFF1B2939),
        text: const Color(0xFFF4F7FB),
        textSecondary: const Color(0xFFB4BECC),
        border: const Color(0xFF69788D),
      ),
      CardockCustomBackgroundDepth.deeper => (
        background: const Color(0xFF070B12),
        surface: const Color(0xFF0E1721),
        surfaceAlt: const Color(0xFF172331),
        text: const Color(0xFFF4F7FB),
        textSecondary: const Color(0xFFB4BECC),
        border: const Color(0xFF637388),
      ),
      CardockCustomBackgroundDepth.oled => (
        background: const Color(0xFF000000),
        surface: const Color(0xFF0A1118),
        surfaceAlt: const Color(0xFF121D28),
        text: const Color(0xFFF4F7FB),
        textSecondary: const Color(0xFFB4BECC),
        border: const Color(0xFF5F7084),
      ),
    },
    CardockCustomNeutralTemperature.neutral => switch (depth) {
      CardockCustomBackgroundDepth.deep => (
        background: const Color(0xFF101113),
        surface: const Color(0xFF1A1C1F),
        surfaceAlt: const Color(0xFF25282C),
        text: const Color(0xFFF5F6F7),
        textSecondary: const Color(0xFFB8BDC4),
        border: const Color(0xFF737A84),
      ),
      CardockCustomBackgroundDepth.deeper => (
        background: const Color(0xFF090A0B),
        surface: const Color(0xFF141517),
        surfaceAlt: const Color(0xFF202225),
        text: const Color(0xFFF5F6F7),
        textSecondary: const Color(0xFFB8BDC4),
        border: const Color(0xFF6C737D),
      ),
      CardockCustomBackgroundDepth.oled => (
        background: const Color(0xFF000000),
        surface: const Color(0xFF0D0E10),
        surfaceAlt: const Color(0xFF191B1E),
        text: const Color(0xFFF5F6F7),
        textSecondary: const Color(0xFFB8BDC4),
        border: const Color(0xFF686F78),
      ),
    },
    CardockCustomNeutralTemperature.warm => switch (depth) {
      CardockCustomBackgroundDepth.deep => (
        background: const Color(0xFF15110F),
        surface: const Color(0xFF211B18),
        surfaceAlt: const Color(0xFF2E2621),
        text: const Color(0xFFF8F5F2),
        textSecondary: const Color(0xFFC4B9B0),
        border: const Color(0xFF81746A),
      ),
      CardockCustomBackgroundDepth.deeper => (
        background: const Color(0xFF0D0A08),
        surface: const Color(0xFF191411),
        surfaceAlt: const Color(0xFF261E1A),
        text: const Color(0xFFF8F5F2),
        textSecondary: const Color(0xFFC4B9B0),
        border: const Color(0xFF796D64),
      ),
      CardockCustomBackgroundDepth.oled => (
        background: const Color(0xFF000000),
        surface: const Color(0xFF110D0B),
        surfaceAlt: const Color(0xFF201915),
        text: const Color(0xFFF8F5F2),
        textSecondary: const Color(0xFFC4B9B0),
        border: const Color(0xFF73675F),
      ),
    },
  };
}

double _normalizedHue(double value) {
  final normalized = value % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}

@immutable
class CardockContrastIssue {
  const CardockContrastIssue({
    required this.token,
    required this.editableToken,
    required this.foreground,
    required this.background,
    required this.ratio,
    required this.required,
    required this.recommendedColor,
  });

  final String token;
  final String editableToken;
  final Color foreground;
  final Color background;
  final double ratio;
  final double required;
  final Color recommendedColor;

  String get foregroundHex => cardockColorHex(foreground);
  String get backgroundHex => cardockColorHex(background);
  String get recommendedHex => cardockColorHex(recommendedColor);

  @override
  String toString() =>
      'CardockContrastIssue($token: ${ratio.toStringAsFixed(2)} / $required)';
}

final class CardockCustomThemeValidationException implements Exception {
  CardockCustomThemeValidationException(Iterable<CardockContrastIssue> issues)
    : issues = List<CardockContrastIssue>.unmodifiable(issues);

  final List<CardockContrastIssue> issues;

  @override
  String toString() =>
      'CardockCustomThemeValidationException(${issues.length} issues)';
}

double cardockContrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

Color cardockOnColorFor(Color background) {
  const dark = Color(0xFF101828);
  return cardockContrastRatio(Colors.white, background) >= 4.5
      ? Colors.white
      : dark;
}

/// Moves a pressed background away from its readable foreground so the
/// pressed state cannot reduce contrast. This is used only by Custom widgets;
/// the three fixed theme families keep their historical pressed colors.
Color cardockContrastPressedColorFor(Color background) {
  final foreground = cardockOnColorFor(background);
  final target = foreground.toARGB32() == Colors.white.toARGB32()
      ? Colors.black
      : Colors.white;
  return Color.lerp(background, target, 0.16)!;
}

/// Retains as much of [source] as possible while moving it toward an already
/// validated foundation text color until it is readable on every surface.
Color cardockReadableTextColorFor(
  Color source, {
  required Color fallback,
  required Iterable<Color> backgrounds,
  double minimum = 4.5,
}) {
  final surfaces = backgrounds.toList(growable: false);

  bool passes(Color candidate) => surfaces.every(
    (surface) => cardockContrastRatio(candidate, surface) >= minimum,
  );

  if (passes(source)) return source;
  for (var step = 1; step <= 100; step++) {
    final candidate = Color.lerp(source, fallback, step / 100)!;
    if (passes(candidate)) return candidate;
  }
  return fallback;
}

/// Chooses one foreground that remains readable across both ends of a
/// gradient. This is intentionally stricter than choosing a color per stop,
/// because overview text is rendered once over the whole gradient.
Color cardockOnGradientColorFor(Color start, Color end) {
  const dark = Color(0xFF101828);
  final whiteMinimum = <double>[
    cardockContrastRatio(Colors.white, start),
    cardockContrastRatio(Colors.white, end),
  ].reduce((left, right) => left < right ? left : right);
  final darkMinimum = <double>[
    cardockContrastRatio(dark, start),
    cardockContrastRatio(dark, end),
  ].reduce((left, right) => left < right ? left : right);
  return whiteMinimum >= darkMinimum ? Colors.white : dark;
}

List<CardockContrastIssue> validateCustomTheme(CardockCustomTheme theme) {
  return <CardockContrastIssue>[
    ..._validateCustomColors(theme.light, prefix: 'light.'),
    ..._validateCustomColors(theme.dark, prefix: 'dark.'),
  ];
}

List<CardockContrastIssue> _validateCustomColors(
  CardockCustomColors colors, {
  required String prefix,
}) {
  final issues = <CardockContrastIssue>[];
  final darkMode = prefix.startsWith('dark.');

  void check(String token, Color foreground, Color background, double minimum) {
    final ratio = cardockContrastRatio(foreground, background);
    if (ratio < minimum) {
      final editableToken = token.split('/').first;
      issues.add(
        CardockContrastIssue(
          token: '$prefix$token',
          editableToken: '$prefix$editableToken',
          foreground: foreground,
          background: background,
          ratio: ratio,
          required: minimum,
          recommendedColor:
              _recommendedTokenColor(
                darkMode
                    ? CardockCustomTheme.defaults.dark
                    : CardockCustomTheme.defaults.light,
                editableToken,
              ) ??
              foreground,
        ),
      );
    }
  }

  for (final entry in <(String, Color)>[
    ('background', colors.background),
    ('surface', colors.surface),
    ('surfaceAlt', colors.surfaceAlt),
  ]) {
    check('foundation.text/${entry.$1}', colors.text, entry.$2, 4.5);
    check(
      'foundation.textSecondary/${entry.$1}',
      colors.textSecondary,
      entry.$2,
      4.5,
    );
    check('foundation.border/${entry.$1}', colors.border, entry.$2, 3.0);
  }

  check(
    'brandNavigation.brandPrimary/background',
    colors.brandPrimary,
    colors.background,
    3.0,
  );
  check(
    'brandNavigation.brandSecondary/background',
    colors.brandSecondary,
    colors.background,
    3.0,
  );
  check(
    'brandNavigation.navigationActive/surface',
    colors.navigationActive,
    colors.surface,
    3.0,
  );
  check('brandNavigation.focus/surface', colors.focus, colors.surface, 3.0);

  final dateBadgeContent = cardockOnColorFor(colors.brandPrimary);
  final dateBadgePressed = cardockContrastPressedColorFor(colors.brandPrimary);
  check(
    'brandNavigation.brandPrimary/dateBadgeOnColor',
    dateBadgeContent,
    colors.brandPrimary,
    4.5,
  );
  check(
    'brandNavigation.brandPrimary/dateBadgePressedOnColor',
    dateBadgeContent,
    dateBadgePressed,
    4.5,
  );

  final overviewContent = cardockOnGradientColorFor(
    colors.overviewStart,
    colors.overviewEnd,
  );
  check(
    'homeOverview.overviewStart/onColor',
    overviewContent,
    colors.overviewStart,
    4.5,
  );
  check(
    'homeOverview.overviewEnd/onColor',
    overviewContent,
    colors.overviewEnd,
    4.5,
  );
  check(
    'homeOverview.currencyAccent/overviewStart',
    colors.currencyAccent,
    colors.overviewStart,
    3.0,
  );
  check(
    'homeOverview.currencyAccent/overviewEnd',
    colors.currencyAccent,
    colors.overviewEnd,
    3.0,
  );
  for (final entry in <(String, Color)>[
    ('overviewStart', colors.overviewStart),
    ('overviewEnd', colors.overviewEnd),
  ]) {
    final primaryMetricSurface = Color.alphaBlend(
      Colors.black.withValues(alpha: 0.18),
      entry.$2,
    );
    final miniMetricSurface = Color.alphaBlend(
      Colors.white.withValues(alpha: 0.10),
      entry.$2,
    );
    check(
      'homeOverview.${entry.$1}/primaryMetricOnColor',
      overviewContent,
      primaryMetricSurface,
      4.5,
    );
    check(
      'homeOverview.${entry.$1}/miniMetricOnColor',
      overviewContent,
      miniMetricSurface,
      4.5,
    );
  }

  check(
    'accounts.accountAccent/surface',
    colors.accountAccent,
    colors.surface,
    3.0,
  );
  check(
    'accounts.accountAccent/accountIconBackground',
    colors.accountAccent,
    colors.accountIconBackground,
    3.0,
  );
  for (final entry in <(String, Color)>[
    ('fieldPalette[0]', colors.fieldLogin),
    ('fieldPalette[1]', colors.fieldPhone),
    ('fieldPalette[2]', colors.fieldEmail),
    ('fieldPalette[3]', colors.fieldPassword),
    ('fieldPalette[4]', colors.fieldUrl),
  ]) {
    check('accounts.${entry.$1}/surface', entry.$2, colors.surface, 3.0);
    final iconBackground = Color.alphaBlend(
      entry.$2.withValues(alpha: darkMode ? 0.22 : 0.14),
      colors.surface,
    );
    check(
      'accounts.${entry.$1}/semanticIconBackground',
      entry.$2,
      iconBackground,
      3.0,
    );
  }

  check(
    'subscriptions.subscriptionAccent/surface',
    colors.subscriptionAccent,
    colors.surface,
    3.0,
  );
  check(
    'subscriptions.renewalAccent/surface',
    colors.renewalAccent,
    colors.surface,
    3.0,
  );
  check(
    'subscriptions.subscriptionAccent/subscriptionIconBackground',
    colors.subscriptionAccent,
    colors.subscriptionIconBackground,
    3.0,
  );

  check(
    'formsActions.actionPrimary/surface',
    colors.actionPrimary,
    colors.surface,
    3.0,
  );
  check(
    'formsActions.actionPrimary/onColor',
    cardockOnColorFor(colors.actionPrimary),
    colors.actionPrimary,
    4.5,
  );
  check(
    'formsActions.actionSecondary/surface',
    colors.actionSecondary,
    colors.surface,
    4.5,
  );
  check(
    'formsActions.inputFocus/surface',
    colors.inputFocus,
    colors.surface,
    3.0,
  );

  for (final entry in <(String, Color)>[
    ('success', colors.success),
    ('warning', colors.warning),
    ('danger', colors.danger),
    ('paused', colors.paused),
    ('neutral', colors.neutral),
  ]) {
    check('semanticStates.${entry.$1}/surface', entry.$2, colors.surface, 3.0);
    final renderedColor = darkMode
        ? entry.$2
        : Color.alphaBlend(Colors.black.withValues(alpha: 0.24), entry.$2);
    final pillBackground = Color.alphaBlend(
      renderedColor.withValues(alpha: 0.14),
      colors.surface,
    );
    check(
      'semanticStates.${entry.$1}/pillBackground',
      renderedColor,
      pillBackground,
      4.5,
    );
  }
  final readableErrorText = cardockReadableTextColorFor(
    colors.danger,
    fallback: colors.text,
    backgrounds: <Color>[colors.background, colors.surface, colors.surfaceAlt],
  );
  for (final entry in <(String, Color)>[
    ('background', colors.background),
    ('surface', colors.surface),
    ('surfaceAlt', colors.surfaceAlt),
  ]) {
    check(
      'semanticStates.danger/readableText/${entry.$1}',
      readableErrorText,
      entry.$2,
      4.5,
    );
  }
  if (colors.danger.toARGB32() == colors.success.toARGB32()) {
    issues.add(
      CardockContrastIssue(
        token: '${prefix}semanticStates.danger/success',
        editableToken: '${prefix}semanticStates.danger',
        foreground: colors.danger,
        background: colors.success,
        ratio: 1.0,
        required: 1.01,
        recommendedColor: darkMode
            ? CardockCustomTheme.defaults.dark.danger
            : CardockCustomTheme.defaults.light.danger,
      ),
    );
  }

  return issues;
}

/// Resets one advanced group in one brightness mode to the safe Custom
/// defaults. Fixed theme families are not involved in this operation.
CardockCustomTheme cardockResetCustomGroup(
  CardockCustomTheme theme, {
  required Brightness brightness,
  required CardockCustomColorGroup group,
}) {
  if (brightness == Brightness.dark) {
    return theme.copyWith(
      dark: theme.dark.copyGroupFrom(CardockCustomTheme.defaults.dark, group),
    );
  }
  return theme.copyWith(
    light: theme.light.copyGroupFrom(CardockCustomTheme.defaults.light, group),
  );
}

/// Applies a conservative, deterministic repair to every failing contrast
/// group. Unaffected modules, quick-control metadata, and launcher fallback
/// remain intact. If custom cross-group interactions still cannot be made
/// valid, only the affected brightness mode falls back to its safe defaults.
CardockCustomTheme cardockAutoFixCustomTheme(CardockCustomTheme theme) {
  var repaired = theme;
  for (var pass = 0; pass < 4; pass++) {
    final issues = repaired.validate();
    if (issues.isEmpty) return repaired;

    var next = repaired;
    for (final issue in issues) {
      final group = _groupFromIssue(issue);
      if (group == null) continue;
      next = cardockResetCustomGroup(
        next,
        brightness: issue.token.startsWith('dark.')
            ? Brightness.dark
            : Brightness.light,
        group: group,
      );
    }
    if (next == repaired) break;
    repaired = next;
  }

  final remaining = repaired.validate();
  if (remaining.isEmpty) return repaired;
  final resetLight = remaining.any((issue) => issue.token.startsWith('light.'));
  final resetDark = remaining.any((issue) => issue.token.startsWith('dark.'));
  return repaired.copyWith(
    light: resetLight ? CardockCustomTheme.defaults.light : repaired.light,
    dark: resetDark ? CardockCustomTheme.defaults.dark : repaired.dark,
  );
}

CardockCustomColorGroup? _groupFromIssue(CardockContrastIssue issue) {
  final segments = issue.editableToken.split('.');
  if (segments.length < 3) return null;
  return _enumFromName(CardockCustomColorGroup.values, segments[1]);
}

Color? _recommendedTokenColor(CardockCustomColors colors, String token) {
  return switch (token) {
    'foundation.background' => colors.background,
    'foundation.surface' => colors.surface,
    'foundation.surfaceAlt' => colors.surfaceAlt,
    'foundation.text' => colors.text,
    'foundation.textSecondary' => colors.textSecondary,
    'foundation.border' => colors.border,
    'brandNavigation.brandPrimary' => colors.brandPrimary,
    'brandNavigation.brandSecondary' => colors.brandSecondary,
    'brandNavigation.navigationActive' => colors.navigationActive,
    'brandNavigation.focus' => colors.focus,
    'homeOverview.overviewStart' => colors.overviewStart,
    'homeOverview.overviewEnd' => colors.overviewEnd,
    'homeOverview.currencyAccent' => colors.currencyAccent,
    'accounts.accountAccent' => colors.accountAccent,
    'accounts.accountIconBackground' => colors.accountIconBackground,
    'accounts.fieldPalette[0]' => colors.fieldLogin,
    'accounts.fieldPalette[1]' => colors.fieldPhone,
    'accounts.fieldPalette[2]' => colors.fieldEmail,
    'accounts.fieldPalette[3]' => colors.fieldPassword,
    'accounts.fieldPalette[4]' => colors.fieldUrl,
    'subscriptions.subscriptionAccent' => colors.subscriptionAccent,
    'subscriptions.renewalAccent' => colors.renewalAccent,
    'subscriptions.subscriptionIconBackground' =>
      colors.subscriptionIconBackground,
    'formsActions.actionPrimary' => colors.actionPrimary,
    'formsActions.actionSecondary' => colors.actionSecondary,
    'formsActions.inputFocus' => colors.inputFocus,
    'semanticStates.success' => colors.success,
    'semanticStates.warning' => colors.warning,
    'semanticStates.danger' => colors.danger,
    'semanticStates.paused' => colors.paused,
    'semanticStates.neutral' => colors.neutral,
    _ => null,
  };
}

String cardockColorHex(Color color) => _colorToHex(color);

Map<Object?, Object?>? _asMap(Object? value) =>
    value is Map<Object?, Object?> ? value : null;

Map<Object?, Object?>? _childMap(Map<Object?, Object?>? parent, String key) =>
    _asMap(parent?[key]);

Color? _parseHexColor(Object? value) {
  if (value is! String || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value)) {
    return null;
  }
  return Color(int.parse('FF${value.substring(1)}', radix: 16));
}

String _colorToHex(Color color) {
  final rgb = color.toARGB32() & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

T? _enumFromName<T extends Enum>(Iterable<T> values, Object? value) {
  if (value is! String) return null;
  for (final entry in values) {
    if (entry.name == value) return entry;
  }
  return null;
}
