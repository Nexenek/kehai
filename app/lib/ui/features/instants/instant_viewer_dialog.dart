import 'package:flutter/material.dart';

import '../../../domain/models/instant.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/time_ago.dart';
import '../../core/widgets/bevel_box.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';

/// Shows [instant] full-size over a dark scrim: caption (if any) and a
/// delete button — either partner may delete any instant per
/// kb/contracts.md ("delete couple-scoped", not author-scoped), so
/// [onDelete] is always offered, not just for "my own" instants like
/// doodles.
Future<void> showInstantViewerDialog(
  BuildContext context, {
  required Instant instant,
  required bool isMine,
  VoidCallback? onDelete,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black87,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: _InstantViewerContent(
        instant: instant,
        isMine: isMine,
        onDelete: onDelete,
      ),
    ),
  );
}

class _InstantViewerContent extends StatelessWidget {
  const _InstantViewerContent({
    required this.instant,
    required this.isMine,
    this.onDelete,
  });

  final Instant instant;
  final bool isMine;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final relative = relativeTime(instant.created);
    final title = isMine
        ? AppStrings.youSentCaption(relative)
        : AppStrings.fromThemCaption(relative);

    return RetroWindow(
      title: title,
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: BevelBox(
              style: BevelStyle.sunken,
              padding: const EdgeInsets.all(4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 480,
                  maxHeight: 480,
                ),
                child: Image.network(
                  instant.imageUrl,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stack) => SizedBox(
                    width: 240,
                    height: 240,
                    child: Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: colors.chromeAlt,
                      ),
                    ),
                  ),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      width: 240,
                      height: 240,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  },
                ),
              ),
            ),
          ),
          if (instant.caption.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              instant.caption,
              style: AppTextStyles.body2.copyWith(color: colors.ink),
            ),
          ],
          if (onDelete != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: PixelButton(
                label: AppStrings.deleteInstantTooltip,
                onPressed: () {
                  onDelete!();
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
