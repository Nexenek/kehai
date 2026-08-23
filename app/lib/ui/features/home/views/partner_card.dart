import 'package:flutter/material.dart';

import '../../../../domain/models/ambient_line.dart';
import '../../../../domain/models/doodle.dart';
import '../../../../domain/models/mood.dart';
import '../../../../domain/models/partner_status.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/time_ago.dart';
import '../../../core/widgets/battery_glyph.dart';
import '../../../core/widgets/bevel_box.dart';
import '../../../core/widgets/pixel_button.dart';
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
    this.partnerDoodle,
    this.onSendDoodle,
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

  /// Most recent doodle authored by the partner (not mine), if any.
  final Doodle? partnerDoodle;

  /// Opens the doodle canvas — wired to both the always-available header
  /// affordance and the "draw back" button shown next to [partnerDoodle].
  final VoidCallback? onSendDoodle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = status != null ? MoodCatalog.byId(status!.moodId) : null;
    final line = ambientLine;

    return RetroWindow(
      title: partnerName.isEmpty
          ? AppStrings.partnerCardTitleFallback
          : partnerName,
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
                  style: AppTextStyles.kaomojiLarge.copyWith(
                    color: mood?.colorOf(colors) ?? colors.ink,
                  ),
                ),
              ),
              if (batteryInfo.kind != BatteryGlyphKind.none) ...[
                BatteryGlyph(
                  kind: batteryInfo.kind == BatteryGlyphKind.low
                      ? BatteryGlyphVisual.low
                      : BatteryGlyphVisual.charging,
                  tooltip: batteryInfo.tooltip,
                ),
                const SizedBox(width: 6),
              ],
              DeviceIndicator(
                phoneOnline: phoneOnline,
                desktopOnline: desktopOnline,
              ),
              if (onSendDoodle != null) ...[
                const SizedBox(width: 6),
                _DoodleAffordance(onTap: onSendDoodle!),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (mood != null)
            Text(
              mood.label,
              style: AppTextStyles.body2.copyWith(color: colors.ink),
            ),
          if (status != null && status!.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              status!.note,
              style: AppTextStyles.body2.copyWith(color: colors.ink),
            ),
          ],
          if (line != null) ...[
            const SizedBox(height: 6),
            Text(
              line.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body2.copyWith(
                color: line.kind == AmbientLineKind.nowPlaying
                    ? colors.accent2
                    : colors.ink,
                fontStyle: line.kind == AmbientLineKind.away
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ],
          if (partnerDoodle != null) ...[
            const SizedBox(height: 10),
            _PartnerDoodle(doodle: partnerDoodle!, onDrawBack: onSendDoodle),
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

/// Small always-available header button that opens the doodle canvas —
/// styled like [RetroWindow]'s decorative title-bar glyphs but functional.
class _DoodleAffordance extends StatelessWidget {
  const _DoodleAffordance({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: AppStrings.sendDoodleTooltip,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: BevelBox(
            color: colors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            child: Text(
              '✎',
              style: AppTextStyles.caption.copyWith(
                color: colors.accent,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The partner's most recent doodle: a pixel-crisp thumbnail in a sunken
/// frame, "from them · X ago" caption, and a "draw back" button.
class _PartnerDoodle extends StatelessWidget {
  const _PartnerDoodle({required this.doodle, this.onDrawBack});

  final Doodle doodle;
  final VoidCallback? onDrawBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BevelBox(
          style: BevelStyle.sunken,
          padding: const EdgeInsets.all(4),
          child: Image.network(
            doodle.imageUrl,
            width: 140,
            height: 140,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
            errorBuilder: (context, error, stack) =>
                const SizedBox(width: 140, height: 140),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppStrings.fromThemCaption(relativeTime(doodle.created)),
                style: AppTextStyles.caption.copyWith(color: colors.chromeAlt),
              ),
              if (onDrawBack != null) ...[
                const SizedBox(height: 8),
                PixelButton(
                  label: AppStrings.drawBackButton,
                  onPressed: onDrawBack,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
