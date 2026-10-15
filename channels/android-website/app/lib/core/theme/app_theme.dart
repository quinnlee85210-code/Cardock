import 'package:flutter/material.dart';

import 'cardock_tokens.dart';
import 'custom_theme.dart';

abstract final class AppTheme {
  static ThemeData light({
    CardockThemeFamily family = cardockDefaultThemeFamily,
    CardockCustomTheme customTheme = CardockCustomTheme.defaults,
  }) => build(family, Brightness.light, customTheme: customTheme);

  static ThemeData dark({
    CardockThemeFamily family = cardockDefaultThemeFamily,
    CardockCustomTheme customTheme = CardockCustomTheme.defaults,
  }) => build(family, Brightness.dark, customTheme: customTheme);

  static ThemeData build(
    CardockThemeFamily family,
    Brightness brightness, {
    CardockCustomTheme customTheme = CardockCustomTheme.defaults,
  }) {
    final spec = CardockTokens.spec(
      family,
      brightness,
      customTheme: customTheme,
    );
    final palette = spec.palette;
    final material = spec.material;
    final onActionPrimary = palette.actionPrimary == palette.primary
        ? palette.onBrandPrimary
        : _readableForeground(
            palette.actionPrimary,
            darkForeground: const Color(0xFF111827),
          );
    final secondary = palette.brandSecondaryContent;
    final onSecondary = _readableForeground(
      secondary,
      darkForeground: palette.textPrimary,
    );
    final danger = family == CardockThemeFamily.custom
        ? cardockReadableTextColorFor(
            palette.statusDanger,
            fallback: palette.textPrimary,
            backgrounds: <Color>[
              palette.background,
              palette.surface,
              palette.surfaceAlt,
            ],
          )
        : palette.statusDanger;
    final onDanger = cardockOnColorFor(danger);
    final errorContainer = Color.alphaBlend(
      danger.withValues(alpha: 0.14),
      palette.surface,
    );
    final onErrorContainer = cardockReadableTextColorFor(
      danger,
      fallback: palette.textPrimary,
      backgrounds: <Color>[errorContainer],
    );
    final actionPressed = palette.actionPrimary == palette.primary
        ? palette.primaryPressed
        : Color.lerp(
            palette.actionPrimary,
            palette.actionPrimary.computeLuminance() > 0.45
                ? Colors.black
                : Colors.white,
            0.16,
          )!;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.primary,
      onPrimary: palette.onBrandPrimary,
      primaryContainer: palette.primarySoft,
      onPrimaryContainer: palette.textPrimary,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: Color.alphaBlend(
        palette.brandContainer,
        palette.surface,
      ),
      onSecondaryContainer: palette.textPrimary,
      error: danger,
      onError: onDanger,
      errorContainer: errorContainer,
      onErrorContainer: onErrorContainer,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      surfaceContainerLowest: palette.surface,
      surfaceContainerLow: palette.surfaceAlt,
      surfaceContainer: palette.surfaceAlt,
      surfaceContainerHigh: palette.surfaceElevated,
      surfaceContainerHighest: palette.surfaceElevated,
      onSurfaceVariant: palette.textSecondary,
      outline: palette.border,
      outlineVariant: palette.divider,
      shadow: palette.shadow,
      scrim: palette.overlayScrim,
      inverseSurface: palette.textPrimary,
      onInverseSurface: palette.background,
      inversePrimary: palette.primary,
      surfaceTint: Colors.transparent,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      dividerColor: palette.divider,
      focusColor: palette.focusRing.withValues(alpha: 0.12),
      hoverColor: palette.selectedLayer,
      splashColor: palette.pressedLayer,
      disabledColor: palette.disabledText,
      fontFamilyFallback: const <String>[
        'Inter',
        'Noto Sans CJK SC',
        'Noto Sans SC',
      ],
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    final textTheme = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        color: palette.textPrimary,
        fontSize: 28,
        height: 1.15,
        fontWeight: FontWeight.w700,
        leadingDistribution: TextLeadingDistribution.even,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        color: palette.textPrimary,
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w700,
        leadingDistribution: TextLeadingDistribution.even,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        color: palette.textPrimary,
        fontSize: CardockTypography.pageTitle,
        height: 1.3,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
        leadingDistribution: TextLeadingDistribution.even,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        color: palette.textPrimary,
        fontSize: CardockTypography.sectionTitle,
        height: 1.35,
        fontWeight: FontWeight.w700,
        leadingDistribution: TextLeadingDistribution.even,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        color: palette.textPrimary,
        fontSize: CardockTypography.cardTitle,
        height: 1.45,
        fontWeight: FontWeight.w700,
        leadingDistribution: TextLeadingDistribution.even,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        color: palette.textPrimary,
        fontSize: 15,
        height: 1.5,
        leadingDistribution: TextLeadingDistribution.even,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        color: palette.textPrimary,
        fontSize: CardockTypography.body,
        height: 1.5,
        leadingDistribution: TextLeadingDistribution.even,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        color: palette.textSecondary,
        fontSize: CardockTypography.caption,
        height: 1.5,
        fontWeight: FontWeight.w500,
        leadingDistribution: TextLeadingDistribution.even,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w600,
        leadingDistribution: TextLeadingDistribution.even,
      ),
      labelMedium: base.textTheme.labelMedium?.copyWith(
        fontSize: CardockTypography.caption,
        height: 1.35,
        fontWeight: FontWeight.w700,
        leadingDistribution: TextLeadingDistribution.even,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 64,
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        elevation: 0,
        shadowColor: material.cardShadows.isEmpty
            ? Colors.transparent
            : material.cardShadows.first.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CardockRadius.card),
          side: BorderSide(
            color: palette.border,
            width: material.cardBorderWidth,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: palette.divider, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: _inputBorder(palette.border),
        enabledBorder: _inputBorder(palette.borderStrong),
        disabledBorder: _inputBorder(palette.disabledBorder),
        focusedBorder: _inputBorder(palette.focusRing, width: 1.5),
        errorBorder: _inputBorder(danger),
        focusedErrorBorder: _inputBorder(danger, width: 1.5),
        hintStyle: TextStyle(
          color: palette.textTertiary,
          fontSize: 14,
          height: 1.35,
        ),
        labelStyle: TextStyle(
          color: palette.textSecondary,
          fontSize: 13,
          height: 1.3,
        ),
        helperStyle: TextStyle(
          color: palette.textSecondary,
          fontSize: 12,
          height: 1.4,
        ),
        errorStyle: TextStyle(
          color: danger,
          fontSize: 12,
          height: 1.4,
          fontWeight: FontWeight.w500,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll<Size>(Size(48, 50)),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.disabled)) {
              return palette.disabledBackground;
            }
            if (states.contains(WidgetState.pressed)) {
              return actionPressed;
            }
            return palette.actionPrimary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.disabled)) {
              return palette.disabledText;
            }
            return onActionPrimary;
          }),
          elevation: const WidgetStatePropertyAll<double>(0),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CardockRadius.control),
            ),
          ),
          textStyle: const WidgetStatePropertyAll<TextStyle>(
            TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll<Size>(Size(48, 50)),
          foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.disabled)) {
              return palette.disabledText;
            }
            return palette.actionSecondary;
          }),
          side: WidgetStateProperty.resolveWith<BorderSide>((states) {
            return BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? palette.disabledBorder
                  : palette.borderStrong,
            );
          }),
          overlayColor: WidgetStatePropertyAll<Color>(palette.pressedLayer),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CardockRadius.control),
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: family == CardockThemeFamily.custom
              ? palette.actionSecondary
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CardockRadius.control),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: palette.surface,
        selectedColor: Color.alphaBlend(palette.selectedLayer, palette.surface),
        side: BorderSide(color: palette.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CardockRadius.pill),
        ),
        labelStyle: TextStyle(color: palette.textSecondary),
        secondaryLabelStyle: TextStyle(
          color: palette.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 8,
        horizontalTitleGap: 12,
        titleTextStyle: textTheme.titleSmall,
        subtitleTextStyle: textTheme.bodySmall,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: CardockLayout.bottomNavigationHeight,
        elevation: 0,
        backgroundColor: palette.surfaceDock,
        indicatorColor: palette.selectedLayer,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? palette.navigationActive
                : palette.textTertiary,
            fontSize: CardockTypography.navigation,
            height: 1.2,
            fontWeight: FontWeight.w700,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? palette.navigationActive
                : palette.textTertiary,
            size: 22,
          );
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: material.fabElevation,
        highlightElevation: material.fabHighlightElevation,
        backgroundColor: palette.actionPrimary,
        foregroundColor: onActionPrimary,
        sizeConstraints: const BoxConstraints.tightFor(
          width: CardockLayout.floatingActionButtonSize,
          height: CardockLayout.floatingActionButtonSize,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            CardockRadius.floatingActionButton,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CardockRadius.largeCard),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: palette.surfaceElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(CardockRadius.bottomSheet),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.textPrimary,
        contentTextStyle: TextStyle(color: palette.background),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CardockRadius.control),
        ),
      ),
      bannerTheme: MaterialBannerThemeData(
        backgroundColor: palette.surfaceAlt,
        dividerColor: palette.border,
        contentTextStyle: textTheme.bodyMedium,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CardockRadius.control),
          side: BorderSide(color: palette.border),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        CardockThemeExtension(
          family: family,
          palette: palette,
          material: material,
        ),
      ],
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(CardockRadius.input),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static Color _readableForeground(
    Color background, {
    required Color darkForeground,
  }) {
    return background.computeLuminance() > 0.19 ? darkForeground : Colors.white;
  }
}
