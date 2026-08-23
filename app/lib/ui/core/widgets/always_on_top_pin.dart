import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/services/desktop_window_service.dart';
import '../strings/app_strings.dart';
import 'win_glyph_button.dart';

/// The ✦ pin in our title bar: keeps the companion window above everything
/// else. Honest tooltip — on Wayland the compositor may take the request and
/// do nothing with it (kb/platform-desktop.md).
class AlwaysOnTopPin extends StatelessWidget {
  const AlwaysOnTopPin({super.key, this.pinned, this.onToggle});

  /// Test seams — both default to the app-wide [DesktopWindowService].
  final ValueListenable<bool>? pinned;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final service = DesktopWindowService.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: pinned ?? service.alwaysOnTop,
      builder: (context, isPinned, _) => WinGlyphButton(
        glyph: '✦',
        tooltip: isPinned
            ? AppStrings.alwaysOnTopOnTooltip
            : AppStrings.alwaysOnTopOffTooltip,
        active: isPinned,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        onTap: onToggle ?? service.toggleAlwaysOnTop,
      ),
    );
  }
}
