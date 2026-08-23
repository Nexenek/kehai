import 'package:flutter/material.dart';

import '../../../../domain/models/ghost_state.dart';
import '../../../../domain/models/location_point.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/retro_window.dart';
import 'couple_map.dart';
import 'ghost_controls.dart';

/// "where we are" — the map section.
///
/// Read-only by design (kb/contracts.md): the app never sends a location,
/// it draws the points OwnTracks already gave the server. The one thing it
/// *does* write is my own pause, at the bottom.
class LocationWindow extends StatelessWidget {
  const LocationWindow({
    super.key,
    required this.partnerName,
    required this.myPoint,
    required this.partnerPoint,
    required this.myGhost,
    required this.partnerGhost,
    required this.distanceLine,
    required this.onChooseGhost,
    this.ghostBusy = false,
    this.errorText,
    this.onClose,
    this.now,
    this.mapHeight = 220,
  });

  final String partnerName;
  final LocationPoint? myPoint;
  final LocationPoint? partnerPoint;
  final GhostState myGhost;
  final GhostState partnerGhost;

  /// Pre-formatted "~X km apart ♡" — null when the contract says to hide it
  /// (see [formatDistanceApart]).
  final String? distanceLine;

  final ValueChanged<GhostOption?> onChooseGhost;
  final bool ghostBusy;
  final String? errorText;
  final VoidCallback? onClose;
  final DateTime? now;
  final double mapHeight;

  String get _partnerLabel =>
      partnerName.isEmpty ? AppStrings.partnerCardTitleFallback : partnerName;

  String? get _partnerGhostLine => switch (partnerGhost.kind) {
    GhostKind.off => null,
    GhostKind.indefinite => AppStrings.partnerGhostIndefinite(_partnerLabel),
    GhostKind.until => AppStrings.partnerGhostUntil(
      _partnerLabel,
      formatGhostUntil(partnerGhost.until!, now: now),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasAnyPoint = myPoint != null || partnerPoint != null;
    final ghostLine = _partnerGhostLine;

    return RetroWindow(
      key: const Key('location-window'),
      title: AppStrings.locationTitle,
      onClose: onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasAnyPoint)
            CoupleMap(
              height: mapHeight,
              people: [
                MapPerson(
                  name: AppStrings.locationYou,
                  point: myPoint,
                  isMe: true,
                ),
                MapPerson(
                  name: _partnerLabel,
                  point: partnerPoint,
                  isMe: false,
                ),
              ],
            )
          else
            _EmptyMap(height: mapHeight),
          if (distanceLine != null) ...[
            const SizedBox(height: 10),
            Text(
              distanceLine!,
              key: const Key('location-distance'),
              style: AppTextStyles.body1.copyWith(color: colors.accent),
            ),
          ],
          if (ghostLine != null) ...[
            const SizedBox(height: 6),
            Text(
              ghostLine,
              key: const Key('partner-ghost-line'),
              style: AppTextStyles.body2.copyWith(color: colors.accent2),
            ),
          ],
          const SizedBox(height: 12),
          GhostControls(
            state: myGhost,
            onChoose: onChooseGhost,
            busy: ghostBusy,
            now: now,
          ),
          if (errorText != null) ...[
            const SizedBox(height: 6),
            Text(
              errorText!,
              style: AppTextStyles.caption.copyWith(color: colors.accent),
            ),
          ],
        ],
      ),
    );
  }
}

/// What the window says before anything has ever been reported — including
/// the whole time the server's `locations` collection doesn't exist yet.
class _EmptyMap extends StatelessWidget {
  const _EmptyMap({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: height,
      child: Container(
        color: colors.bg,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppStrings.locationEmpty,
              key: const Key('location-empty'),
              style: AppTextStyles.kaomojiMedium.copyWith(color: colors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.locationEmptyHint,
              style: AppTextStyles.caption.copyWith(color: colors.chromeAlt),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
