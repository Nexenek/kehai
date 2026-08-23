import 'package:flutter/material.dart';

import '../../../../domain/day_math.dart';
import '../../../../domain/models/countdown.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bevel_box.dart';

/// One row in the countdowns list: title (+ optional decorative kaomoji),
/// the friendly date, and the big pixel day-count ("in 42 days" /
/// "today!! ✧" / "42 days ago"). [highlighted] paints the row in the
/// accent color for the nearest upcoming countdown.
class CountdownRow extends StatelessWidget {
  const CountdownRow({
    super.key,
    required this.countdown,
    this.highlighted = false,
    this.onTap,
    this.now,
  });

  final Countdown countdown;
  final bool highlighted;
  final VoidCallback? onTap;

  /// Injectable "now" for tests — defaults to [DateTime.now] at build time.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final days = daysUntil(countdown.date, now: now);
    final label = countdownDayLabel(days);
    final fg = highlighted ? colors.surface : colors.ink;

    return Semantics(
      button: onTap != null,
      label: '${countdown.title}, $label',
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: BevelBox(
              color: highlighted ? colors.accent : colors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            if (countdown.kaomoji.isNotEmpty) ...[
                              Text(
                                countdown.kaomoji,
                                style: AppTextStyles.caption.copyWith(
                                  color: fg,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                countdown.title,
                                style: AppTextStyles.body2.copyWith(
                                  color: fg,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          friendlyDate(countdown.date),
                          style: AppTextStyles.caption.copyWith(
                            color: highlighted
                                ? colors.surface.withValues(alpha: 0.85)
                                : colors.chromeAlt,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    textAlign: TextAlign.right,
                    style: AppTextStyles.heading.copyWith(
                      fontSize: 15,
                      color: highlighted ? colors.surface : colors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
