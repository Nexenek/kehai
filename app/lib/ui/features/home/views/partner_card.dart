import 'package:flutter/material.dart';

import '../../../../domain/models/ambient_line.dart';
import '../../../../domain/models/mood.dart';
import '../../../../domain/models/partner_status.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/time_ago.dart';
import '../../../core/widgets/battery_glyph.dart';
import '../../../core/widgets/retro_window.dart';
import 'device_indicator.dart';

/// The signature partner window: mood kaomoji, note, "updated X ago", the
/// device-source indicator glyphs, and (kb/platform-desktop.md's
/// "Telemetry contract") the ambient line + battery glyph.
class PartnerCard extends StatelessWidget {
  const PartnerCard({
    super.key,
    required this.partnerName,
    required this.status,
    required this.phoneOnline,
    required this.desktopOnline,
    this.ambientLine,
    this.batteryInfo = BatteryGlyphInfo.none,
  });

  final String partnerName;
  final PartnerStatus? status;
  final bool phoneOnline;
  final bool desktopOnline;

  /// Precedence-resolved ambient line (now_playing/activity/presence/away)
  /// — see [resolveAmbientLine]. Null falls back to the existing offline
  /// state (no extra row).
  final AmbientLine? ambientLine;

  /// Partner's phone low-battery/charging glyph — see [resolvePhoneBattery].
  final BatteryGlyphInfo batteryInfo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = status != null ? MoodCatalog.byId(status!.moodId) : null;
    final line = ambientLine;

    return RetroWindow(
      title: partnerName.isEmpty ? AppStrings.partnerCardTitleFallback : partnerName,
      width: 380,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  mood?.kaomoji ?? '(. .)',
                  style: AppTextStyles.kaomojiLarge.copyWith(color: mood?.colorOf(colors) ?? colors.ink),
                ),
              ),
              if (batteryInfo.kind != BatteryGlyphKind.none) ...[
                BatteryGlyph(
                  kind: batteryInfo.kind == BatteryGlyphKind.low ? BatteryGlyphVisual.low : BatteryGlyphVisual.charging,
                  tooltip: batteryInfo.tooltip,
                ),
                const SizedBox(width: 6),
              ],
              DeviceIndicator(phoneOnline: phoneOnline, desktopOnline: desktopOnline),
            ],
          ),
          const SizedBox(height: 8),
          if (mood != null)
            Text(mood.label, style: AppTextStyles.body2.copyWith(color: colors.ink)),
          if (status != null && status!.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(status!.note, style: AppTextStyles.body2.copyWith(color: colors.ink)),
          ],
          if (line != null) ...[
            const SizedBox(height: 6),
            Text(
              line.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body2.copyWith(
                color: line.kind == AmbientLineKind.nowPlaying ? colors.accent2 : colors.ink,
                fontStyle: line.kind == AmbientLineKind.away ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            status != null ? timeAgo(status!.updated) : '',
            style: AppTextStyles.caption.copyWith(color: colors.chromeAlt),
          ),
        ],
      ),
    );
  }
}
