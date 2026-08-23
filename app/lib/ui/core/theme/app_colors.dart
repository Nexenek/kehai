import 'package:flutter/material.dart';

/// Design tokens from kb/design-language.md — the "pastel pixel love-terminal"
/// palette. Do not introduce ad-hoc colors elsewhere; extend this file
/// instead so the whole app stays on-palette.
class AppColors {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.chrome,
    required this.chromeAlt,
    required this.accent,
    required this.accent2,
    required this.ink,
    required this.mint,
    required this.sky,
    required this.warn,
    required this.bevelLight,
    required this.bevelDark,
  });

  final Color bg;
  final Color surface;
  final Color chrome;
  final Color chromeAlt;
  final Color accent;
  final Color accent2;
  final Color ink;
  final Color mint;
  final Color sky;
  final Color warn;

  /// Bevel highlight/shadow used to fake the raised Win95 border effect.
  final Color bevelLight;
  final Color bevelDark;

  static const light = AppColors(
    bg: Color(0xFFFDF3F8),
    surface: Color(0xFFFFFFFF),
    chrome: Color(0xFFF4CBDC),
    chromeAlt: Color(0xFFCCB5C8),
    accent: Color(0xFFB24D89),
    accent2: Color(0xFFAF87BA),
    ink: Color(0xFF362D3B),
    mint: Color(0xFFBFE8D8),
    sky: Color(0xFFBCD7F0),
    warn: Color(0xFFE8B4B8),
    bevelLight: Color(0xFFFFFFFF),
    bevelDark: Color(0xFF9C8497),
  );

  /// Dark "night" theme: deep plum bg, desaturated pastel chrome, glowing
  /// accents. Per design-language.md this is a draft — tune against real
  /// screens in a later design pass.
  static const dark = AppColors(
    bg: Color(0xFF241F2A),
    surface: Color(0xFF362D3B),
    chrome: Color(0xFF5C4A57),
    chromeAlt: Color(0xFF4A3F4C),
    accent: Color(0xFFD98BB8),
    accent2: Color(0xFFC7A6D1),
    ink: Color(0xFFF1E6EE),
    mint: Color(0xFF8FCBB4),
    sky: Color(0xFF93B8DE),
    warn: Color(0xFFE39BA0),
    bevelLight: Color(0xFF6E5C69),
    bevelDark: Color(0xFF150F19),
  );
}

extension AppColorsContext on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColorsTheme>()?.colors ?? AppColors.light;
}

/// Wraps [AppColors] as a [ThemeExtension] so it can ride along with
/// [ThemeData] and be looked up via [AppColorsContext].
class AppColorsTheme extends ThemeExtension<AppColorsTheme> {
  const AppColorsTheme(this.colors);

  final AppColors colors;

  @override
  AppColorsTheme copyWith({AppColors? colors}) =>
      AppColorsTheme(colors ?? this.colors);

  @override
  AppColorsTheme lerp(ThemeExtension<AppColorsTheme>? other, double t) {
    if (other is! AppColorsTheme) return this;
    // Pixel aesthetic — snap instead of blend.
    return t < 0.5 ? this : other;
  }
}
