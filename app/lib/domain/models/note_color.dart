import 'package:flutter/material.dart';

import '../../ui/core/theme/app_colors.dart';

/// Sticky-note pastel color. Not in [AppColors] itself — this is a mapping
/// from the `notes.color` select values to theme tokens (plus one one-off
/// constant for "butter", which has no existing token).
enum NoteColor {
  pink,
  lavender,
  mint,
  sky,
  butter;

  static NoteColor fromString(String? value) => NoteColor.values.firstWhere(
        (c) => c.name == value,
        orElse: () => NoteColor.pink,
      );

  /// Resolves against the current theme so light/dark both stay on-token
  /// (only [butter] is a fixed constant — see design-language.md's palette
  /// table, which has no "butter" entry).
  Color colorOf(AppColors colors) => switch (this) {
        NoteColor.pink => colors.chrome,
        // "chromeAlt/accent2 tint" — lighten accent2 toward the surface so
        // it reads as a pastel lavender sticky note in both themes.
        NoteColor.lavender => Color.lerp(colors.accent2, colors.surface, 0.55)!,
        NoteColor.mint => colors.mint,
        NoteColor.sky => colors.sky,
        NoteColor.butter => butterConstant,
      };

  /// One-off pastel butter-yellow — not on the design-language.md palette,
  /// added here per the notes spec ("butter=#f7e8b0").
  static const butterConstant = Color(0xFFF7E8B0);
}
