import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'win_glyph_button.dart';

/// The signature Win95-parody window frame used for every card/dialog in
/// the app (design-language.md: "Windows-9x-parody frames: every
/// card/dialog is a window"). Title bar in chrome pink with decorative
/// pixel ♥ close / ★ min buttons, 2px raised bevel border, sharp corners.
class RetroWindow extends StatelessWidget {
  const RetroWindow({
    super.key,
    required this.title,
    required this.child,
    this.onClose,
    this.onMinimize,
    this.padding = const EdgeInsets.all(16),
    this.width,
  });

  final String title;
  final Widget child;

  /// Decorative for v1 — pass a callback to make close/min functional.
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final EdgeInsetsGeometry padding;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: width,
      constraints: const BoxConstraints(minWidth: 0),
      decoration: BoxDecoration(
        border: Border.all(color: colors.ink, width: 2),
        color: colors.surface,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TitleBar(title: title, onClose: onClose, onMinimize: onMinimize),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.title, this.onClose, this.onMinimize});

  final String title;
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      color: colors.chrome,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.titleBar.copyWith(color: colors.ink),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          WinGlyphButton(
            glyph: '★',
            tooltip: onMinimize == null ? 'minimize (decorative)' : 'minimize',
            onTap: onMinimize,
          ),
          const SizedBox(width: 6),
          WinGlyphButton(
            glyph: '♥',
            tooltip: onClose == null ? 'close (decorative)' : 'close',
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}
