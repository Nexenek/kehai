import 'package:flutter/material.dart';

import '../../../../domain/models/mood.dart';
import '../../../../domain/models/partner_status.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/time_ago.dart';
import '../../../core/widgets/retro_window.dart';
import 'device_indicator.dart';

/// The signature partner window: mood kaomoji, note, "updated X ago", and
/// the device-source indicator glyphs.
class PartnerCard extends StatelessWidget {
  const PartnerCard({
    super.key,
    required this.partnerName,
    required this.status,
    required this.phoneOnline,
    required this.desktopOnline,
  });

  final String partnerName;
  final PartnerStatus? status;
  final bool phoneOnline;
  final bool desktopOnline;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = status != null ? MoodCatalog.byId(status!.moodId) : null;

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
