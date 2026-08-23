import 'package:flutter/material.dart';

import '../../../../domain/models/doodle.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/time_ago.dart';
import '../../../core/widgets/bevel_box.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/retro_window.dart';
import 'mood_picker.dart';

/// My side of the desktop: the mood grid, the little note I'm broadcasting,
/// and the doodle I last sent. Lifted out of home_screen.dart so all three
/// layouts (phone column, companion drawer, wide spread) show the same
/// window without duplicating it.
class MyMoodWindow extends StatelessWidget {
  const MyMoodWindow({
    super.key,
    required this.selectedMoodId,
    required this.onSelectMood,
    required this.noteController,
    required this.onNoteChanged,
    required this.onSaveNote,
    this.myDoodle,
    this.onDeleteDoodle,
    this.onClose,
  });

  final String selectedMoodId;
  final ValueChanged<String> onSelectMood;
  final TextEditingController noteController;
  final ValueChanged<String> onNoteChanged;
  final ValueChanged<String> onSaveNote;
  final Doodle? myDoodle;
  final VoidCallback? onDeleteDoodle;

  /// Wired to the window's ♥ when this is shown inside the companion
  /// drawer; null (decorative) everywhere else.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return RetroWindow(
      title: AppStrings.moodPickerTitle,
      onClose: onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          MoodPicker(selectedId: selectedMoodId, onSelect: onSelectMood),
          const SizedBox(height: 12),
          TextField(
            controller: noteController,
            style: AppTextStyles.body1,
            decoration: const InputDecoration(hintText: AppStrings.noteHint),
            onChanged: onNoteChanged,
            onSubmitted: onSaveNote,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: PixelButton(
              primary: true,
              label: AppStrings.saveNote,
              onPressed: () => onSaveNote(noteController.text),
            ),
          ),
          if (myDoodle != null) ...[
            const SizedBox(height: 12),
            MyDoodleThumbnail(doodle: myDoodle!, onDelete: onDeleteDoodle),
          ],
        ],
      ),
    );
  }
}

/// The "you sent · X ago" thumbnail below the mood picker, with a small ✕
/// to delete it — either partner may delete a doodle, so this mirrors the
/// partner-card one visually but is my own to remove.
class MyDoodleThumbnail extends StatelessWidget {
  const MyDoodleThumbnail({super.key, required this.doodle, this.onDelete});

  final Doodle doodle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        BevelBox(
          style: BevelStyle.sunken,
          padding: const EdgeInsets.all(3),
          child: Image.network(
            doodle.imageUrl,
            width: 48,
            height: 48,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
            errorBuilder: (context, error, stack) =>
                const SizedBox(width: 48, height: 48),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            AppStrings.youSentCaption(relativeTime(doodle.created)),
            style: AppTextStyles.caption.copyWith(color: colors.chromeAlt),
          ),
        ),
        Tooltip(
          message: AppStrings.deleteDoodleTooltip,
          child: GestureDetector(
            onTap: onDelete,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: BevelBox(
                color: colors.surface,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '✕',
                  style: AppTextStyles.caption.copyWith(
                    color: colors.warn,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
