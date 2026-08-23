import 'package:flutter/material.dart';

import '../../../domain/models/shared_file.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';

/// A shared file is deleted for both partners at once (couple-scoped
/// delete, same as doodles/instants) and — unlike those two, which are
/// small/replaceable — a file might represent real effort to have gotten
/// into the drive in the first place. So unlike the rest of the app's
/// direct-delete affordances (`BoardWindow`'s ✕, `InstantsWindow`'s delete
/// button), this one is the app's first confirm-before-delete step: shows
/// [file]'s label and waits for an explicit "delete" tap before resolving
/// `true`. Resolves `false`/`null` on cancel or dismiss.
Future<bool> showDeleteFileConfirmDialog(
  BuildContext context, {
  required SharedFile file,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: _DeleteFileConfirmContent(file: file),
    ),
  );
  return confirmed ?? false;
}

class _DeleteFileConfirmContent extends StatelessWidget {
  const _DeleteFileConfirmContent({required this.file});

  final SharedFile file;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return RetroWindow(
      title: AppStrings.filesDeleteConfirmTitle,
      onClose: () => Navigator.of(context).pop(false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.filesDeleteConfirmBody(file.displayLabel),
            style: AppTextStyles.body2.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Spacer(),
              PixelButton(
                label: AppStrings.filesDeleteConfirmCancel,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(width: 8),
              PixelButton(
                primary: true,
                label: AppStrings.filesDeleteConfirmDelete,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
