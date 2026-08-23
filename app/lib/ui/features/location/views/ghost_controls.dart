import 'package:flutter/material.dart';

import '../../../../domain/models/ghost_state.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/pixel_button.dart';

/// My own location sharing switch: where it stands right now, plus the four
/// one-tap options from ADR-6 (1 h / until tomorrow / until I turn it on /
/// sharing on).
///
/// The copy carries the design rule that makes ghost mode acceptable at all
/// (design-language.md: "Privacy controls use honest language"): pausing is
/// stated plainly, the partner is told, and nothing here nags anyone for
/// choosing it.
class GhostControls extends StatelessWidget {
  const GhostControls({
    super.key,
    required this.state,
    required this.onChoose,
    this.busy = false,
    this.now,
  });

  /// My resolved ghost state — see [resolveGhostState].
  final GhostState state;

  /// `null` is "sharing on"; the rest are the quick pauses.
  final ValueChanged<GhostOption?> onChoose;

  /// True while a change is in flight, so a double tap can't race itself.
  final bool busy;

  /// Injectable clock, so [formatGhostUntil] is deterministic in tests.
  final DateTime? now;

  String get _stateLabel => switch (state.kind) {
    GhostKind.off => AppStrings.ghostRowSharing,
    GhostKind.indefinite => AppStrings.ghostRowPausedIndefinite,
    GhostKind.until => AppStrings.ghostRowPausedUntil(
      formatGhostUntil(state.until!, now: now),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final paused = state.isActive;

    return Column(
      key: const Key('ghost-controls'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _stateLabel,
          key: const Key('ghost-state-label'),
          style: AppTextStyles.body2.copyWith(
            color: paused ? colors.accent2 : colors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _GhostButton(
              buttonKey: const Key('ghost-1h'),
              label: AppStrings.ghostPauseHour,
              tooltip: AppStrings.ghostPauseHourTooltip,
              onPressed: busy ? null : () => onChoose(GhostOption.hour),
            ),
            _GhostButton(
              buttonKey: const Key('ghost-tomorrow'),
              label: AppStrings.ghostPauseTomorrow,
              tooltip: AppStrings.ghostPauseTomorrowTooltip,
              onPressed: busy ? null : () => onChoose(GhostOption.untilTomorrow),
            ),
            _GhostButton(
              buttonKey: const Key('ghost-indefinite'),
              label: AppStrings.ghostPauseIndefinite,
              tooltip: AppStrings.ghostPauseIndefiniteTooltip,
              onPressed: busy ? null : () => onChoose(GhostOption.indefinite),
            ),
            _GhostButton(
              buttonKey: const Key('ghost-resume'),
              label: AppStrings.ghostResume,
              tooltip: AppStrings.ghostResumeTooltip,
              primary: true,
              // Already sharing: nothing to turn back on. Disabled rather
              // than hidden, so the row never changes shape under a thumb.
              onPressed: (busy || !paused) ? null : () => onChoose(null),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          AppStrings.ghostExplainer,
          style: AppTextStyles.caption.copyWith(color: colors.chromeAlt),
        ),
      ],
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.buttonKey,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.primary = false,
  });

  final Key buttonKey;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      // Deliberately not [PixelButton.dense]: these are thumb targets in a
      // drawer, and the accessibility floor is 44px even when the art is
      // tiny (design-language.md).
      child: PixelButton(
        key: buttonKey,
        label: label,
        primary: primary,
        onPressed: onPressed,
      ),
    );
  }
}
