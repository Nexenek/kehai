import 'package:flutter/material.dart';

import '../../../domain/models/instant.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/time_ago.dart';
import '../../core/widgets/bevel_box.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';
import 'instant_viewer_dialog.dart';
import 'instants_view_model.dart';
import 'send_instant_dialog.dart';

/// The "instants" RetroWindow: a reverse-chronological photo grid plus the
/// "send an instant" button. Self-contained, same as `NotesWindow` — this
/// batch builds the feature but does NOT wire it into the home tray/layout
/// (another agent owns that composition this round); a caller just needs
/// an [InstantsViewModel] wired to real repositories.
class InstantsWindow extends StatelessWidget {
  const InstantsWindow({super.key, required this.viewModel, this.onClose});

  final InstantsViewModel viewModel;

  /// Makes the window's ♥ functional when it's shown inside the desktop
  /// companion drawer; decorative (null) in the other layouts.
  final VoidCallback? onClose;

  void _openSendDialog(BuildContext context) {
    showSendInstantDialog(
      context,
      onSend: ({required imageBytes, required filename, required caption}) =>
          viewModel.send(
            imageBytes: imageBytes,
            filename: filename,
            caption: caption,
          ),
    );
  }

  void _openViewer(BuildContext context, Instant instant, bool isMine) {
    showInstantViewerDialog(
      context,
      instant: instant,
      isMine: isMine,
      onDelete: () => viewModel.deleteInstant(instant.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final colors = context.colors;
        final instants = viewModel.instants;
        final showEmpty = instants.isEmpty && !viewModel.isLoading;

        return RetroWindow(
          title: AppStrings.instantsTitle,
          onClose: onClose,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    AppStrings.instantsEmpty,
                    style: AppTextStyles.body2.copyWith(color: colors.ink),
                  ),
                )
              else
                _InstantGrid(
                  instants: instants,
                  myUserId: viewModel.myUserId,
                  onTap: (instant, isMine) =>
                      _openViewer(context, instant, isMine),
                ),
              if (viewModel.hasMore) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.center,
                  child: PixelButton(
                    label: AppStrings.instantsLoadMore,
                    onPressed: viewModel.isLoadingMore
                        ? null
                        : viewModel.loadMore,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: PixelButton(
                  primary: true,
                  icon: Icons.camera_alt,
                  label: AppStrings.sendInstant,
                  onPressed: () => _openSendDialog(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Lays [instants] out 2-3 per row depending on the available width — a
/// `Wrap` (content-height, matches `NotesWindow`'s grid) whose tile width
/// is computed from a `LayoutBuilder` rather than a fixed `GridView`
/// column count, since this window's height isn't otherwise bounded.
class _InstantGrid extends StatelessWidget {
  const _InstantGrid({
    required this.instants,
    required this.myUserId,
    required this.onTap,
  });

  final List<Instant> instants;
  final String myUserId;
  final void Function(Instant instant, bool isMine) onTap;

  static const _spacing = 8.0;
  static const _minTileWidth = 96.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _minTileWidth * 2 + _spacing;
        final columns =
            (((width + _spacing) / (_minTileWidth + _spacing)).floor()).clamp(
              2,
              3,
            );
        final tileWidth = (width - _spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: _spacing,
          runSpacing: _spacing,
          children: [
            for (final instant in instants)
              SizedBox(
                width: tileWidth,
                child: _InstantTile(
                  instant: instant,
                  isMine: instant.authorId == myUserId,
                  onTap: () => onTap(instant, instant.authorId == myUserId),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InstantTile extends StatelessWidget {
  const _InstantTile({
    required this.instant,
    required this.isMine,
    required this.onTap,
  });

  final Instant instant;
  final bool isMine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Author tint: mine vs. theirs, per the design language's "statuses
    // conveyed by icon+text not color alone" — the strip also carries the
    // "Xm ago" text, so color is never the only signal.
    final tint = isMine ? colors.accent : colors.accent2;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          label:
              '${relativeTime(instant.created)}'
              '${instant.caption.isNotEmpty ? ' · ${instant.caption}' : ''}',
          child: BevelBox(
            style: BevelStyle.sunken,
            padding: const EdgeInsets.all(3),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    instant.imageUrl,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stack) =>
                        ColoredBox(color: colors.chromeAlt),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return ColoredBox(color: colors.chromeAlt);
                    },
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.85),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Text(
                          relativeTime(instant.created),
                          style: AppTextStyles.caption.copyWith(
                            color: colors.surface,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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
