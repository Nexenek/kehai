import 'package:flutter/material.dart';

import '../../../app_controller.dart';
import '../../../data/services/desktop_window_service.dart';
import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'always_on_top_pin.dart';
import 'pixel_button.dart';
import 'win_glyph_button.dart';

/// Our own window title bar, drawn in place of the OS one on desktop.
///
/// The whole app is one Win95-parody window (design-language.md), so the
/// frame around it should be ours too: chrome-pink strip, pixel title, and
/// real controls — ★ minimizes, ♥ closes, ✦ pins on top. Dragging the strip
/// moves the window; double-clicking it maximizes/restores, like every
/// title bar since 1995.
///
/// Desktop only — Android never sees this.
class KehaiTitleBar extends StatelessWidget {
  const KehaiTitleBar({
    super.key,
    this.onMinimize,
    this.onClose,
    this.onToggleMaximize,
    this.onDragStart,
    this.pin = const AlwaysOnTopPin(),
    this.showLogOut,
  });

  /// Window controls. All default to the real window; tests pass their own.
  final VoidCallback? onMinimize;
  final VoidCallback? onClose;
  final VoidCallback? onToggleMaximize;
  final VoidCallback? onDragStart;

  /// The ✦ pin, or null to leave it out.
  final Widget? pin;

  /// Whether to offer "log out" here. Defaults to "only once you're actually
  /// logged in and home" — it's meaningless mid-onboarding.
  final bool? showLogOut;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final service = DesktopWindowService.instance;
    final controller = AppScope.of(context);
    final logOutVisible = showLogOut ?? (controller.stage == AppStage.home);

    return Container(
      color: colors.chrome,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => (onDragStart ?? service.startDragging)(),
              onDoubleTap: onToggleMaximize ?? service.toggleMaximize,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  AppStrings.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleBar.copyWith(color: colors.ink),
                ),
              ),
            ),
          ),
          if (logOutVisible) ...[
            PixelButton(
              label: AppStrings.logOut,
              dense: true,
              onPressed: () => AppScope.of(context, listen: false).logOut(),
            ),
            const SizedBox(width: 8),
          ],
          if (pin != null) ...[pin!, const SizedBox(width: 6)],
          WinGlyphButton(
            glyph: '★',
            tooltip: AppStrings.minimizeTooltip,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            onTap: onMinimize ?? service.minimize,
          ),
          const SizedBox(width: 6),
          WinGlyphButton(
            glyph: '♥',
            tooltip: AppStrings.closeWindowTooltip,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            onTap: onClose ?? service.close,
          ),
        ],
      ),
    );
  }
}
