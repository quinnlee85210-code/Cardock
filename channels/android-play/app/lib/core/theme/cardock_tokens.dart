// ignore_for_file: prefer_initializing_formals

import 'package:flutter/material.dart';

import 'cardock_material_profile.dart';
import 'cardock_theme_types.dart';
import 'custom_theme.dart';

export 'cardock_material_profile.dart';
export 'cardock_theme_types.dart';

part 'cardock_fixed_theme_registry.dart';

abstract final class CardockLayout {
  static const double referenceWidth = 390;
  static const double referenceHeight = 844;
  static const double screenHorizontal = 22;
  static const double dockHorizontal = 16;
  static const double safeTop = 28;
  static const double topSectionGap = 20;
  static const double moduleGap = 20;
  static const double moduleGapLarge = 24;
  static const double cardGap = 12;
  static const double cardPadding = 16;
  static const double cardPaddingLarge = 20;
  static const double bottomNavigationHeight = 62;
  static const double dockTopScrimHeight = 24;
  static const double centerActionOverhang = 14;
  static const double minimumTapTarget = 48;

  static const double homeHeaderHeight = 60;
  static const double securityRailHeight = 42;
  static const double heroHeight = 234;
  static const double heroPadding = 18;
  static const double renewalSpotlightMinHeight = 128;
  static const double renewalDateBadgeWidth = 58;
  static const double renewalDateBadgeHeight = 72;
  static const double dockTileHeight = 70;
  static const double floatingActionButtonSize = 52;
}

abstract final class CardockRadius {
  static const double small = 8;
  static const double icon = small;
  static const double control = 11;
  static const double input = 15;
  static const double card = 17;
  static const double largeCard = 23;
  static const double dateBadge = 15;
  static const double floatingActionButton = 26;
  static const double hero = 26;
  static const double bottomSheet = 24;
  static const double pill = 999;
}

abstract final class CardockTypography {
  static const double brand = 22;
  static const double pageTitle = 24;
  static const double sectionTitle = 18;
  static const double heroNumber = 58;
  static const double secondaryAmount = 18;
  static const double currencySymbolScale = 0.62;
  static const double cardTitle = 15;
  static const double body = 12.5;
  static const double caption = 9.5;
  static const double navigation = 11;
}

abstract final class CardockMotion {
  static const Duration quick = Duration(milliseconds: 180);
  static const Duration component = Duration(milliseconds: 240);
  static const Duration page = Duration(milliseconds: 320);
  static const Duration themeTransition = quick;
  static const Duration logoCrossfade = quick;
  static const Duration launcherIconFeedback = quick;
  static const Duration cardExpand = component;
  static const Duration bottomSheet = component;
  static const Duration splashDock = page;
  static const Curve standard = Cubic(0.2, 0, 0, 1);

  static Duration resolve(BuildContext context, Duration duration) {
    return MediaQuery.maybeOf(context)?.disableAnimations == true
        ? Duration.zero
        : duration;
  }
}

@immutable
class CardockPalette {
  const CardockPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceStrong,
    required this.primary,
    required this.primaryPressed,
    required this.primarySoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.divider,
    required this.gradientStart,
    required this.gradientMiddle,
    required this.gradientEnd,
    required this.calmGradientStart,
    required this.calmGradientEnd,
    required this.gradientContent,
    required this.shadow,
    this.accent,
    this.accentWarm,
    Color? surfaceElevated,
    Color? surfaceDock,
    Color? overlayScrim,
    Color? borderStrong,
    Color? selectedLayer,
    Color? pressedLayer,
    Color? disabledText,
    Color? disabledBackground,
    Color? disabledBorder,
    Color? focusRing,
    Color? brandContainer,
    Color? skeletonBase,
    Color? skeletonShimmer,
    Color? elevation1,
    Color? elevation2,
    Color? surfaceTopHighlight,
    Color? onBrandPrimary,
    Color? brandPrimaryContent,
    Color? brandSecondaryDecorative,
    Color? brandSecondaryContent,
    Color? themeDecorativeAccent,
    Color? overviewGlow,
    Color? navigationActive,
    Color? focus,
    Color? overviewStart,
    Color? overviewEnd,
    Color? currencyAccent,
    Color? fieldCurrency,
    Color? overviewTimelineAccent,
    Color? accountAccent,
    Color? accountIconBackground,
    Color? fieldLogin,
    Color? fieldPhone,
    Color? fieldEmail,
    Color? fieldPassword,
    Color? fieldUrl,
    Color? fieldSubscription,
    Color? fieldNote,
    Color? subscriptionAccent,
    Color? renewalAccent,
    Color? subscriptionIconBackground,
    Color? actionPrimary,
    Color? actionSecondary,
    Color? inputFocus,
    Color? statusNormal,
    Color? statusRenewSoon,
    Color? statusDanger,
    Color? statusCancelled,
    Color? statusPaused,
    Color? statusInformation,
  }) : _surfaceElevated = surfaceElevated,
       _surfaceDock = surfaceDock,
       _overlayScrim = overlayScrim,
       _borderStrong = borderStrong,
       _selectedLayer = selectedLayer,
       _pressedLayer = pressedLayer,
       _disabledText = disabledText,
       _disabledBackground = disabledBackground,
       _disabledBorder = disabledBorder,
       _focusRing = focusRing,
       _brandContainer = brandContainer,
       _skeletonBase = skeletonBase,
       _skeletonShimmer = skeletonShimmer,
       _elevation1 = elevation1,
       _elevation2 = elevation2,
       _surfaceTopHighlight = surfaceTopHighlight,
       _onBrandPrimary = onBrandPrimary,
       _brandPrimaryContent = brandPrimaryContent,
       _brandSecondaryDecorative = brandSecondaryDecorative,
       _brandSecondaryContent = brandSecondaryContent,
       _themeDecorativeAccent = themeDecorativeAccent,
       _overviewGlow = overviewGlow,
       _navigationActive = navigationActive,
       _focus = focus,
       _overviewStart = overviewStart,
       _overviewEnd = overviewEnd,
       _currencyAccent = currencyAccent,
       _fieldCurrency = fieldCurrency,
       _overviewTimelineAccent = overviewTimelineAccent,
       _accountAccent = accountAccent,
       _accountIconBackground = accountIconBackground,
       _fieldLogin = fieldLogin,
       _fieldPhone = fieldPhone,
       _fieldEmail = fieldEmail,
       _fieldPassword = fieldPassword,
       _fieldUrl = fieldUrl,
       _fieldSubscription = fieldSubscription,
       _fieldNote = fieldNote,
       _subscriptionAccent = subscriptionAccent,
       _renewalAccent = renewalAccent,
       _subscriptionIconBackground = subscriptionIconBackground,
       _actionPrimary = actionPrimary,
       _actionSecondary = actionSecondary,
       _inputFocus = inputFocus,
       _statusNormal = statusNormal,
       _statusRenewSoon = statusRenewSoon,
       _statusDanger = statusDanger,
       _statusCancelled = statusCancelled,
       _statusPaused = statusPaused,
       _statusInformation = statusInformation;

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceStrong;
  final Color primary;
  final Color primaryPressed;
  final Color primarySoft;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color border;
  final Color divider;
  final Color gradientStart;
  final Color gradientMiddle;
  final Color gradientEnd;
  final Color calmGradientStart;
  final Color calmGradientEnd;
  final Color gradientContent;
  final Color shadow;
  final Color? accent;
  final Color? accentWarm;
  final Color? _surfaceElevated;
  final Color? _surfaceDock;
  final Color? _overlayScrim;
  final Color? _borderStrong;
  final Color? _selectedLayer;
  final Color? _pressedLayer;
  final Color? _disabledText;
  final Color? _disabledBackground;
  final Color? _disabledBorder;
  final Color? _focusRing;
  final Color? _brandContainer;
  final Color? _skeletonBase;
  final Color? _skeletonShimmer;
  final Color? _elevation1;
  final Color? _elevation2;
  final Color? _surfaceTopHighlight;
  final Color? _onBrandPrimary;
  final Color? _brandPrimaryContent;
  final Color? _brandSecondaryDecorative;
  final Color? _brandSecondaryContent;
  final Color? _themeDecorativeAccent;
  final Color? _overviewGlow;
  final Color? _navigationActive;
  final Color? _focus;
  final Color? _overviewStart;
  final Color? _overviewEnd;
  final Color? _currencyAccent;
  final Color? _fieldCurrency;
  final Color? _overviewTimelineAccent;
  final Color? _accountAccent;
  final Color? _accountIconBackground;
  final Color? _fieldLogin;
  final Color? _fieldPhone;
  final Color? _fieldEmail;
  final Color? _fieldPassword;
  final Color? _fieldUrl;
  final Color? _fieldSubscription;
  final Color? _fieldNote;
  final Color? _subscriptionAccent;
  final Color? _renewalAccent;
  final Color? _subscriptionIconBackground;
  final Color? _actionPrimary;
  final Color? _actionSecondary;
  final Color? _inputFocus;
  final Color? _statusNormal;
  final Color? _statusRenewSoon;
  final Color? _statusDanger;
  final Color? _statusCancelled;
  final Color? _statusPaused;
  final Color? _statusInformation;

  Color get surfaceElevated => _surfaceElevated ?? surfaceStrong;
  Color get surfaceDock => _surfaceDock ?? surface;
  Color get overlayScrim => _overlayScrim ?? const Color(0x99000000);
  Color get borderStrong => _borderStrong ?? border;
  Color get selectedLayer => _selectedLayer ?? primarySoft;
  Color get pressedLayer => _pressedLayer ?? primary.withValues(alpha: 0.08);
  Color get disabledText => _disabledText ?? textTertiary;
  Color get disabledBackground =>
      _disabledBackground ?? textPrimary.withValues(alpha: 0.04);
  Color get disabledBorder => _disabledBorder ?? border;
  Color get focusRing => _focusRing ?? focus;
  Color get brandContainer => _brandContainer ?? primarySoft;
  Color get skeletonBase => _skeletonBase ?? surfaceAlt;
  Color get skeletonShimmer => _skeletonShimmer ?? surfaceElevated;
  Color get elevation1 => _elevation1 ?? shadow.withValues(alpha: 0.08);
  Color get elevation2 => _elevation2 ?? shadow.withValues(alpha: 0.13);
  Color get surfaceTopHighlight => _surfaceTopHighlight ?? Colors.transparent;
  Color get onBrandPrimary =>
      _onBrandPrimary ??
      (primary.computeLuminance() > 0.42
          ? const Color(0xFF08101D)
          : Colors.white);
  Color get brandPrimaryContent => _brandPrimaryContent ?? primary;
  Color get brandSecondaryDecorative =>
      _brandSecondaryDecorative ?? accent ?? primary;
  Color get brandSecondaryContent =>
      _brandSecondaryContent ?? accent ?? primary;
  Color get themeDecorativeAccent =>
      _themeDecorativeAccent ?? accent ?? primary;
  Color get overviewGlow => _overviewGlow ?? primary.withValues(alpha: 0.16);
  Color get brandSecondary => brandSecondaryContent;
  Color get navigationActive => _navigationActive ?? primary;
  Color get focus => _focus ?? primary;
  Color get overviewStart => _overviewStart ?? gradientStart;
  Color get overviewEnd => _overviewEnd ?? gradientEnd;
  Color get currencyAccent => _currencyAccent ?? gradientContent;
  Color get fieldCurrency => _fieldCurrency ?? CardockTokens.fieldLogin;
  Color get overviewTimelineAccent =>
      _overviewTimelineAccent ?? accentWarm ?? CardockTokens.statusRenewSoon;
  Color get accountAccent => _accountAccent ?? primary;
  Color get accountIconBackground => _accountIconBackground ?? primary;
  Color get fieldLogin => _fieldLogin ?? CardockTokens.fieldLogin;
  Color get fieldPhone => _fieldPhone ?? CardockTokens.fieldPhone;
  Color get fieldEmail => _fieldEmail ?? CardockTokens.fieldEmail;
  Color get fieldPassword => _fieldPassword ?? CardockTokens.fieldPassword;
  Color get fieldUrl => _fieldUrl ?? CardockTokens.fieldUrl;
  Color get fieldSubscription =>
      _fieldSubscription ?? CardockTokens.fieldSubscription;
  Color get fieldNote => _fieldNote ?? CardockTokens.fieldNote;
  Color get subscriptionAccent =>
      _subscriptionAccent ?? CardockTokens.fieldSubscription;
  Color get renewalAccent => _renewalAccent ?? CardockTokens.statusRenewSoon;
  Color get subscriptionIconBackground =>
      _subscriptionIconBackground ?? CardockTokens.fieldSubscription;
  Color get actionPrimary => _actionPrimary ?? primary;
  Color get actionSecondary => _actionSecondary ?? primary;
  Color get inputFocus => _inputFocus ?? primary;
  Color get statusNormal => _statusNormal ?? CardockTokens.statusNormal;
  Color get statusRenewSoon =>
      _statusRenewSoon ?? CardockTokens.statusRenewSoon;
  Color get statusDanger => _statusDanger ?? CardockTokens.statusDanger;
  Color get statusCancelled =>
      _statusCancelled ?? CardockTokens.statusCancelled;
  Color get statusPaused => _statusPaused ?? CardockTokens.statusPaused;
  Color get statusInformation =>
      _statusInformation ?? CardockTokens.statusInformation;

  LinearGradient get brandGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[gradientStart, gradientMiddle, gradientEnd],
  );

  LinearGradient get calmGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[calmGradientStart, calmGradientEnd],
  );

  LinearGradient get overviewGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _overviewStart == null && _overviewEnd == null
        ? <Color>[gradientStart, gradientMiddle, gradientEnd]
        : <Color>[
            overviewStart,
            Color.lerp(overviewStart, overviewEnd, 0.5)!,
            overviewEnd,
          ],
  );

  static CardockPalette lerp(
    CardockPalette left,
    CardockPalette right,
    double t,
  ) {
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return CardockPalette(
      background: mix(left.background, right.background),
      surface: mix(left.surface, right.surface),
      surfaceAlt: mix(left.surfaceAlt, right.surfaceAlt),
      surfaceStrong: mix(left.surfaceStrong, right.surfaceStrong),
      primary: mix(left.primary, right.primary),
      primaryPressed: mix(left.primaryPressed, right.primaryPressed),
      primarySoft: mix(left.primarySoft, right.primarySoft),
      textPrimary: mix(left.textPrimary, right.textPrimary),
      textSecondary: mix(left.textSecondary, right.textSecondary),
      textTertiary: mix(left.textTertiary, right.textTertiary),
      border: mix(left.border, right.border),
      divider: mix(left.divider, right.divider),
      gradientStart: mix(left.gradientStart, right.gradientStart),
      gradientMiddle: mix(left.gradientMiddle, right.gradientMiddle),
      gradientEnd: mix(left.gradientEnd, right.gradientEnd),
      calmGradientStart: mix(left.calmGradientStart, right.calmGradientStart),
      calmGradientEnd: mix(left.calmGradientEnd, right.calmGradientEnd),
      gradientContent: mix(left.gradientContent, right.gradientContent),
      shadow: mix(left.shadow, right.shadow),
      accent: left.accent == null || right.accent == null
          ? (t < 0.5 ? left.accent : right.accent)
          : mix(left.accent!, right.accent!),
      accentWarm: left.accentWarm == null || right.accentWarm == null
          ? (t < 0.5 ? left.accentWarm : right.accentWarm)
          : mix(left.accentWarm!, right.accentWarm!),
      surfaceElevated: mix(left.surfaceElevated, right.surfaceElevated),
      surfaceDock: mix(left.surfaceDock, right.surfaceDock),
      overlayScrim: mix(left.overlayScrim, right.overlayScrim),
      borderStrong: mix(left.borderStrong, right.borderStrong),
      selectedLayer: mix(left.selectedLayer, right.selectedLayer),
      pressedLayer: mix(left.pressedLayer, right.pressedLayer),
      disabledText: mix(left.disabledText, right.disabledText),
      disabledBackground: mix(
        left.disabledBackground,
        right.disabledBackground,
      ),
      disabledBorder: mix(left.disabledBorder, right.disabledBorder),
      focusRing: mix(left.focusRing, right.focusRing),
      brandContainer: mix(left.brandContainer, right.brandContainer),
      skeletonBase: mix(left.skeletonBase, right.skeletonBase),
      skeletonShimmer: mix(left.skeletonShimmer, right.skeletonShimmer),
      elevation1: mix(left.elevation1, right.elevation1),
      elevation2: mix(left.elevation2, right.elevation2),
      surfaceTopHighlight: mix(
        left.surfaceTopHighlight,
        right.surfaceTopHighlight,
      ),
      onBrandPrimary: mix(left.onBrandPrimary, right.onBrandPrimary),
      brandPrimaryContent: mix(
        left.brandPrimaryContent,
        right.brandPrimaryContent,
      ),
      brandSecondaryDecorative: mix(
        left.brandSecondaryDecorative,
        right.brandSecondaryDecorative,
      ),
      brandSecondaryContent: mix(
        left.brandSecondaryContent,
        right.brandSecondaryContent,
      ),
      themeDecorativeAccent: mix(
        left.themeDecorativeAccent,
        right.themeDecorativeAccent,
      ),
      overviewGlow: mix(left.overviewGlow, right.overviewGlow),
      navigationActive: mix(left.navigationActive, right.navigationActive),
      focus: mix(left.focus, right.focus),
      overviewStart: mix(left.overviewStart, right.overviewStart),
      overviewEnd: mix(left.overviewEnd, right.overviewEnd),
      currencyAccent: mix(left.currencyAccent, right.currencyAccent),
      fieldCurrency: mix(left.fieldCurrency, right.fieldCurrency),
      overviewTimelineAccent: mix(
        left.overviewTimelineAccent,
        right.overviewTimelineAccent,
      ),
      accountAccent: mix(left.accountAccent, right.accountAccent),
      accountIconBackground: mix(
        left.accountIconBackground,
        right.accountIconBackground,
      ),
      fieldLogin: mix(left.fieldLogin, right.fieldLogin),
      fieldPhone: mix(left.fieldPhone, right.fieldPhone),
      fieldEmail: mix(left.fieldEmail, right.fieldEmail),
      fieldPassword: mix(left.fieldPassword, right.fieldPassword),
      fieldUrl: mix(left.fieldUrl, right.fieldUrl),
      fieldSubscription: mix(left.fieldSubscription, right.fieldSubscription),
      fieldNote: mix(left.fieldNote, right.fieldNote),
      subscriptionAccent: mix(
        left.subscriptionAccent,
        right.subscriptionAccent,
      ),
      renewalAccent: mix(left.renewalAccent, right.renewalAccent),
      subscriptionIconBackground: mix(
        left.subscriptionIconBackground,
        right.subscriptionIconBackground,
      ),
      actionPrimary: mix(left.actionPrimary, right.actionPrimary),
      actionSecondary: mix(left.actionSecondary, right.actionSecondary),
      inputFocus: mix(left.inputFocus, right.inputFocus),
      statusNormal: mix(left.statusNormal, right.statusNormal),
      statusRenewSoon: mix(left.statusRenewSoon, right.statusRenewSoon),
      statusDanger: mix(left.statusDanger, right.statusDanger),
      statusCancelled: mix(left.statusCancelled, right.statusCancelled),
      statusPaused: mix(left.statusPaused, right.statusPaused),
      statusInformation: mix(left.statusInformation, right.statusInformation),
    );
  }
}

@immutable
class CardockThemeSpec {
  const CardockThemeSpec({required this.palette, required this.material});

  final CardockPalette palette;
  final CardockMaterialProfile material;
}

abstract final class CardockTokens {
  static const Color fieldLogin = Color(0xFF4C86FF);
  static const Color fieldPhone = Color(0xFF35C97A);
  static const Color fieldEmail = Color(0xFF9A65F7);
  static const Color fieldPassword = Color(0xFFF5A524);
  static const Color fieldUrl = Color(0xFF1AB5C9);
  static const Color fieldSubscription = Color(0xFF6E6AF4);
  static const Color fieldNote = Color(0xFF718096);

  static const Color statusNormal = Color(0xFF58E5A8);
  static const Color statusRenewSoon = Color(0xFFFFBE62);
  static const Color statusDanger = Color(0xFFFF718A);
  static const Color statusCancelled = Color(0xFF8F9AB0);
  static const Color statusPaused = Color(0xFFB07CFF);
  static const Color statusInformation = Color(0xFF5B8CFF);

  static CardockThemeSpec spec(
    CardockThemeFamily family,
    Brightness brightness, {
    CardockCustomTheme customTheme = CardockCustomTheme.defaults,
  }) {
    if (family == CardockThemeFamily.custom) {
      return CardockThemeSpec(
        palette: _customPalette(customTheme.colorsFor(brightness)),
        material: CardockMaterialProfiles.custom(brightness),
      );
    }
    return CardockFixedThemeRegistry.resolve(family, brightness);
  }

  static CardockPalette palette(
    CardockThemeFamily family,
    Brightness brightness, {
    CardockCustomTheme customTheme = CardockCustomTheme.defaults,
  }) => spec(family, brightness, customTheme: customTheme).palette;

  static CardockMaterialProfile materialProfile(
    CardockThemeFamily family,
    Brightness brightness, {
    CardockCustomTheme customTheme = CardockCustomTheme.defaults,
  }) => spec(family, brightness, customTheme: customTheme).material;
  static CardockPalette _customPalette(CardockCustomColors colors) {
    final dark = colors.background.computeLuminance() < 0.2;
    final middle = Color.lerp(colors.overviewStart, colors.overviewEnd, 0.5)!;
    final primaryPressed = Color.lerp(
      colors.brandPrimary,
      colors.brandPrimary.computeLuminance() > 0.45
          ? Colors.black
          : Colors.white,
      0.16,
    )!;
    final primarySoft = Color.alphaBlend(
      colors.brandPrimary.withValues(alpha: 0.15),
      colors.surface,
    );
    final overviewContent = cardockOnGradientColorFor(
      colors.overviewStart,
      colors.overviewEnd,
    );
    return CardockPalette(
      background: colors.background,
      surface: colors.surface,
      surfaceAlt: colors.surfaceAlt,
      surfaceStrong: Color.lerp(colors.surfaceAlt, colors.brandPrimary, 0.06)!,
      primary: colors.brandPrimary,
      primaryPressed: primaryPressed,
      primarySoft: primarySoft,
      textPrimary: colors.text,
      textSecondary: colors.textSecondary,
      // Custom's secondary text is already validated at 4.5:1 on every
      // foundation surface. Reusing it keeps hints and unselected navigation
      // readable; fixed theme families retain their historical tertiary color.
      textTertiary: colors.textSecondary,
      border: colors.border,
      divider: colors.border.withValues(alpha: 0.72),
      gradientStart: colors.overviewStart,
      gradientMiddle: middle,
      gradientEnd: colors.overviewEnd,
      calmGradientStart: colors.surfaceAlt,
      calmGradientEnd: Color.lerp(
        colors.surfaceAlt,
        colors.brandSecondary,
        0.08,
      )!,
      gradientContent: overviewContent,
      shadow: colors.text,
      accent: colors.brandSecondary,
      accentWarm: colors.renewalAccent,
      surfaceElevated: Color.lerp(
        colors.surfaceAlt,
        dark ? Colors.white : colors.text,
        dark ? 0.06 : 0.025,
      )!,
      surfaceDock: colors.surface,
      overlayScrim: Colors.black.withValues(alpha: dark ? 0.60 : 0.44),
      borderStrong: colors.border.withValues(alpha: 1),
      selectedLayer: colors.brandPrimary.withValues(alpha: dark ? 0.12 : 0.09),
      pressedLayer: colors.text.withValues(alpha: dark ? 0.06 : 0.08),
      disabledText: colors.textSecondary.withValues(alpha: 0.72),
      disabledBackground: colors.text.withValues(alpha: 0.04),
      disabledBorder: colors.border.withValues(alpha: 0.72),
      focusRing: colors.focus,
      brandContainer: colors.brandPrimary.withValues(alpha: dark ? 0.09 : 0.08),
      skeletonBase: Color.lerp(colors.surfaceAlt, colors.text, 0.06)!,
      skeletonShimmer: Color.lerp(colors.surfaceAlt, colors.text, 0.12)!,
      elevation1: Colors.black.withValues(alpha: dark ? 0.40 : 0.08),
      elevation2: Colors.black.withValues(alpha: dark ? 0.54 : 0.13),
      surfaceTopHighlight: dark
          ? Colors.white.withValues(alpha: 0.07)
          : Colors.transparent,
      onBrandPrimary: cardockOnColorFor(colors.brandPrimary),
      brandPrimaryContent: colors.brandPrimary,
      brandSecondaryDecorative: colors.brandSecondary,
      brandSecondaryContent: colors.brandSecondary,
      themeDecorativeAccent: colors.brandSecondary,
      overviewGlow: colors.brandPrimary.withValues(alpha: dark ? 0.22 : 0.16),
      navigationActive: colors.navigationActive,
      focus: colors.focus,
      overviewStart: colors.overviewStart,
      overviewEnd: colors.overviewEnd,
      currencyAccent: colors.currencyAccent,
      fieldCurrency: colors.subscriptionAccent,
      overviewTimelineAccent: colors.renewalAccent,
      accountAccent: colors.accountAccent,
      accountIconBackground: colors.accountIconBackground,
      fieldLogin: colors.fieldLogin,
      fieldPhone: colors.fieldPhone,
      fieldEmail: colors.fieldEmail,
      fieldPassword: colors.fieldPassword,
      fieldUrl: colors.fieldUrl,
      fieldSubscription: colors.subscriptionAccent,
      fieldNote: colors.neutral,
      subscriptionAccent: colors.subscriptionAccent,
      renewalAccent: colors.renewalAccent,
      subscriptionIconBackground: colors.subscriptionIconBackground,
      actionPrimary: colors.actionPrimary,
      actionSecondary: colors.actionSecondary,
      inputFocus: colors.inputFocus,
      statusNormal: colors.success,
      statusRenewSoon: colors.warning,
      statusDanger: colors.danger,
      statusCancelled: colors.neutral,
      statusPaused: colors.paused,
      statusInformation: colors.neutral,
    );
  }
}

@immutable
class CardockThemeExtension extends ThemeExtension<CardockThemeExtension> {
  const CardockThemeExtension({
    required this.family,
    required this.palette,
    required this.material,
  });

  final CardockThemeFamily family;
  final CardockPalette palette;
  final CardockMaterialProfile material;

  @override
  CardockThemeExtension copyWith({
    CardockThemeFamily? family,
    CardockPalette? palette,
    CardockMaterialProfile? material,
  }) {
    return CardockThemeExtension(
      family: family ?? this.family,
      palette: palette ?? this.palette,
      material: material ?? this.material,
    );
  }

  @override
  CardockThemeExtension lerp(covariant CardockThemeExtension? other, double t) {
    if (other == null) return this;
    return CardockThemeExtension(
      family: t < 0.5 ? family : other.family,
      palette: CardockPalette.lerp(palette, other.palette, t),
      material: t < 0.5 ? material : other.material,
    );
  }
}

extension CardockThemeContext on BuildContext {
  CardockThemeExtension get cardockTheme {
    final theme = Theme.of(this);
    final fallback = CardockTokens.spec(
      cardockDefaultThemeFamily,
      theme.brightness,
    );
    return theme.extension<CardockThemeExtension>() ??
        CardockThemeExtension(
          family: cardockDefaultThemeFamily,
          palette: fallback.palette,
          material: fallback.material,
        );
  }
}
