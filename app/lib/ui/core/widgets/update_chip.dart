import 'package:flutter/material.dart';

import '../../../data/services/update_service.dart';
import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// "a newer Kehai is here" — said in exactly one line, in the same slot and
/// the same voice as [OfflineBadge].
///
/// A status, not an alarm: no dialog, no snooze, no "remind me later". One
/// pixel square and a sentence you can tap or ignore, and it will still be
/// there tomorrow. The tap does the whole thing — download, verify, install
/// — and the same line turns into the progress readout, so the update never
/// takes over the screen it interrupted.
///
/// Purely presentational: it takes a [stage] rather than the service, so
/// every state it can be in is one `pumpWidget` away (update_chip_test.dart).
class UpdateChip extends StatelessWidget {
  const UpdateChip({
    super.key,
    required this.stage,
    this.version,
    this.progress = 0,
    this.onTap,
  });

  /// Matched to [OfflineBadge.dotSize] on purpose — the two share a slot,
  /// and can be on screen at the same time.
  static const double dotSize = 7;

  final UpdateStage stage;
  final String? version;
  final double progress;
  final Future<void> Function()? onTap;

  /// The one line, or null when this stage has nothing worth saying (idle,
  /// checking — the daily check must be invisible).
  static String? labelFor(
    UpdateStage stage, {
    String? version,
    double progress = 0,
  }) => switch (stage) {
    UpdateStage.available =>
      version == null ? null : AppStrings.updateAvailable(version),
    UpdateStage.downloading => AppStrings.updateDownloading(
      (progress.clamp(0.0, 1.0) * 100).floor(),
    ),
    UpdateStage.readyToApply => AppStrings.updateReady,
    UpdateStage.applying => AppStrings.updateApplying,
    UpdateStage.failed => AppStrings.updateFailed,
    UpdateStage.idle || UpdateStage.checking => null,
  };

  /// Only the two ends of the sequence are tappable: an offer to accept, or
  /// a failure to retry. Mid-download there is nothing a tap could mean.
  static bool isTappable(UpdateStage stage) =>
      stage == UpdateStage.available || stage == UpdateStage.failed;

  @override
  Widget build(BuildContext context) {
    final label = labelFor(stage, version: version, progress: progress);
    if (label == null) return const SizedBox.shrink();

    final colors = context.colors;
    final dotColor = stage == UpdateStage.failed ? colors.warn : colors.accent;

    final row = Row(
      key: const Key('update-chip'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: dotSize, height: dotSize, color: dotColor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: colors.ink.withValues(alpha: 0.75),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    if (!isTappable(stage) || onTap == null) {
      return Tooltip(message: AppStrings.updateChipTooltip, child: row);
    }
    return Tooltip(
      message: AppStrings.updateChipTooltip,
      child: InkWell(
        key: const Key('update-chip-tap'),
        onTap: () => onTap!(),
        // Enough to hit on a phone without turning a status line into a
        // button-shaped thing.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: row,
        ),
      ),
    );
  }
}
