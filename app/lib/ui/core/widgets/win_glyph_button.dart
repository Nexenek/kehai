import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'bevel_box.dart';

/// The little bevelled pixel glyph that lives in a window title bar — ★, ♥,
/// ✦. One implementation so the app's own title bar and every [RetroWindow]
/// wear identical chrome (design-language.md: "tiny pixel close/min buttons
/// that wink: min = ★, close = ♥").
class WinGlyphButton extends StatelessWidget {
  const WinGlyphButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    this.onTap,
    this.active = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
  });

  final String glyph;
  final String tooltip;

  /// Null makes the glyph decorative — no cursor change, no tap.
  final VoidCallback? onTap;

  /// Toggled-on look: sunken and accent-filled, so state doesn't rely on
  /// colour alone.
  final bool active;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: onTap != null,
        toggled: active,
        label: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: MouseRegion(
            cursor: onTap != null
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            child: BevelBox(
              color: active ? colors.accent : colors.surface,
              style: active ? BevelStyle.sunken : BevelStyle.raised,
              padding: padding,
              child: Text(
                glyph,
                style: AppTextStyles.caption.copyWith(
                  color: active ? colors.surface : colors.accent,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
