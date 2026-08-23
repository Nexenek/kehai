import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

/// Builds the two [ThemeData] instances (light/dark) for the app. Keeps
/// Material's default elevation/rounding switched off everywhere — the
/// retro-OS look comes from [RetroWindow]/[BevelBox], not Material shadows.
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: c.bg,
      fontFamily: AppTextStyles.body,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.accent,
        onPrimary: c.surface,
        secondary: c.accent2,
        onSecondary: c.ink,
        surface: c.surface,
        onSurface: c.ink,
        error: c.warn,
        onError: c.ink,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: c.chromeAlt,
      // Sharp corners everywhere — no default Material rounding.
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.ink, width: 2),
          borderRadius: BorderRadius.zero,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      textTheme: const TextTheme(
        titleLarge: AppTextStyles.heading,
        bodyLarge: AppTextStyles.body1,
        bodyMedium: AppTextStyles.body2,
        bodySmall: AppTextStyles.caption,
        labelLarge: AppTextStyles.button,
      ).apply(bodyColor: c.ink, displayColor: c.ink),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: c.ink, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: c.ink, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: c.accent, width: 2),
        ),
        labelStyle: AppTextStyles.body2.copyWith(color: c.ink),
        hintStyle: AppTextStyles.body2.copyWith(
          color: c.ink.withValues(alpha: 0.45),
        ),
      ),
      // Dotted pixel focus outline (design-language.md accessibility floor).
      focusColor: c.accent,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accent2.withValues(alpha: 0.4),
        selectionHandleColor: c.accent,
      ),
    );

    return base.copyWith(extensions: [AppColorsTheme(c)]);
  }
}
