import 'package:flutter/material.dart';

import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// "we can't see the server right now", said as quietly as it deserves: a
/// small warn-coloured pixel square and one lowercase word.
///
/// A square rather than a circle because everything else here is drawn on
/// the same pixel grid ([DeviceGlyph], [PixelHeart]) and a lone anti-aliased
/// dot would be the one soft edge on the screen. Shown only while
/// [AppController.online] is false — the app carries on working from what
/// it already has, so this is a status line, never an alert.
class OfflineBadge extends StatelessWidget {
  const OfflineBadge({super.key});

  /// Small enough to read as a dot at the end of a sentence rather than as
  /// a button.
  static const double dotSize = 7;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: AppStrings.offlineBadgeTooltip,
      child: Row(
        key: const Key('offline-badge'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: dotSize, height: dotSize, color: colors.warn),
          const SizedBox(width: 6),
          Text(
            AppStrings.offlineBadge,
            style: AppTextStyles.caption.copyWith(
              color: colors.ink.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
