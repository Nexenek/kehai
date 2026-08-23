import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../domain/models/ambient_line.dart';
import '../../../../domain/models/device_status.dart';
import '../../../../domain/models/doodle.dart';
import '../../../../domain/models/mood.dart';
import '../../../../domain/models/partner_status.dart';
import '../../../../domain/models/utc_offset.dart';
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
class PartnerCard extends StatefulWidget {
  const PartnerCard({
    super.key,
    required this.partnerName,
    required this.status,
    required this.phoneOnline,
    required this.desktopOnline,
    this.ambientLine,
    this.batteryInfo = BatteryGlyphInfo.none,
    this.distanceLine,
    this.partnerDoodle,
    this.onSendDoodle,
    this.partnerDevices = const [],
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

  /// "~4.2 km apart ♡" (kb/contracts.md "Distance-apart"), already resolved
  /// by [formatDistanceApart] — null whenever it should be hidden (stale or
  /// missing points, paused partner). Deliberately quiet: it's a small line
  /// under the ambient one, not a headline.
  final String? distanceLine;

  /// Most recent doodle authored by the partner (not mine), if any.
  final Doodle? partnerDoodle;

  /// Opens the doodle canvas — wired to both the always-available header
  /// affordance and the "draw back" button shown next to [partnerDoodle].
  final VoidCallback? onSendDoodle;

  /// The partner's `devices` records — used only to derive the "what time
  /// is it there" line (kb/features.md "Timezone dual clocks") via
  /// [resolvePartnerUtcOffset]. Defaults to empty so existing callers keep
  /// compiling unchanged; the line simply stays hidden until a caller
  /// starts passing the partner's device list.
  final List<DeviceStatus> partnerDevices;

  @override
  State<PartnerCard> createState() => _PartnerCardState();
}

class _PartnerCardState extends State<PartnerCard> {
  Timer? _clockTicker;

  @override
  void initState() {
    super.initState();
    // Ticks the dual-clock line forward once a minute — nothing else on
    // this card needs a timer of its own (everything else re-renders off
    // of `ListenableBuilder`/prop changes upstream).
    _clockTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final status = widget.status;
    final mood = status != null ? MoodCatalog.byId(status.moodId) : null;
    final line = widget.ambientLine;
    final batteryInfo = widget.batteryInfo;
    final distanceLine = widget.distanceLine;
    final partnerDoodle = widget.partnerDoodle;
    final partnerName = widget.partnerName;
    final phoneOnline = widget.phoneOnline;
    final desktopOnline = widget.desktopOnline;
    final onSendDoodle = widget.onSendDoodle;
    final dualClockLine = resolveDualClockLine(
      mine: UtcOffset.now(),
      theirs: resolvePartnerUtcOffset(widget.partnerDevices),
      nowUtc: DateTime.now().toUtc(),
    );

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
                _DoodleAffordance(onTap: onSendDoodle),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (mood != null)
            Text(
              mood.label,
              style: AppTextStyles.body2.copyWith(color: colors.ink),
            ),
          if (status != null && status.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              status.note,
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
          if (distanceLine != null) ...[
            const SizedBox(height: 4),
            Text(
              distanceLine,
              key: const Key('partner-distance-line'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(color: colors.accent2),
            ),
          ],
          if (dualClockLine != null) ...[
            const SizedBox(height: 4),
            Text(
              dualClockLine,
              key: const Key('partner-dual-clock-line'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(color: colors.accent2),
            ),
          ],
          if (partnerDoodle != null) ...[
            const SizedBox(height: 10),
            _PartnerDoodle(doodle: partnerDoodle, onDrawBack: onSendDoodle),
          ],
          const SizedBox(height: 10),
          Text(
            status != null ? timeAgo(status.updated) : '',
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
