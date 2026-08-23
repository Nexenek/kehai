import 'package:flutter/material.dart';

import '../../../../domain/day_math.dart';
import '../../../../domain/models/countdown.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bevel_box.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/retro_window.dart';

/// The result of the countdown add/edit dialog — title/date/kaomoji, ready
/// to hand straight to [CountdownsViewModel.addCountdown]/`updateCountdown`.
class CountdownDraft {
  const CountdownDraft({
    required this.title,
    required this.date,
    required this.kaomoji,
  });

  final String title;
  final DateTime date;
  final String kaomoji;
}

/// Shows the RetroWindow-styled add/edit dialog. Pass [existing] to edit
/// (and get a delete button); omit it to create a new countdown.
Future<void> showCountdownDialog(
  BuildContext context, {
  Countdown? existing,
  required ValueChanged<CountdownDraft> onSave,
  VoidCallback? onDelete,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: _CountdownDialogContent(
        existing: existing,
        onSave: onSave,
        onDelete: onDelete,
      ),
    ),
  );
}

class _CountdownDialogContent extends StatefulWidget {
  const _CountdownDialogContent({
    this.existing,
    required this.onSave,
    this.onDelete,
  });

  final Countdown? existing;
  final ValueChanged<CountdownDraft> onSave;
  final VoidCallback? onDelete;

  @override
  State<_CountdownDialogContent> createState() =>
      _CountdownDialogContentState();
}

class _CountdownDialogContentState extends State<_CountdownDialogContent> {
  late final TextEditingController _titleController;
  late final TextEditingController _kaomojiController;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.existing?.title ?? '',
    );
    _kaomojiController = TextEditingController(
      text: widget.existing?.kaomoji ?? '',
    );
    _date =
        widget.existing?.date ?? DateTime.now().add(const Duration(days: 7));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _kaomojiController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    widget.onSave(
      CountdownDraft(
        title: title,
        date: _date,
        kaomoji: _kaomojiController.text.trim(),
      ),
    );
    Navigator.of(context).pop();
  }

  void _delete() {
    widget.onDelete?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isEdit = widget.existing != null;

    return RetroWindow(
      title: isEdit
          ? AppStrings.editCountdownTitle
          : AppStrings.newCountdownTitle,
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.countdownTitleLabel,
            style: AppTextStyles.caption.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _titleController,
            style: AppTextStyles.body1,
            decoration: const InputDecoration(
              hintText: AppStrings.countdownTitleHint,
            ),
            autofocus: !isEdit,
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.countdownDateLabel,
            style: AppTextStyles.caption.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: _pickDate,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: BevelBox(
                color: colors.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                child: Text(
                  friendlyDate(_date),
                  style: AppTextStyles.body1.copyWith(color: colors.ink),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.countdownKaomojiLabel,
            style: AppTextStyles.caption.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _kaomojiController,
            style: AppTextStyles.body1,
            decoration: const InputDecoration(
              hintText: AppStrings.countdownKaomojiHint,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (isEdit)
                PixelButton(
                  label: AppStrings.deleteCountdown,
                  onPressed: _delete,
                ),
              const Spacer(),
              PixelButton(
                primary: true,
                label: AppStrings.saveCountdown,
                onPressed: _save,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
