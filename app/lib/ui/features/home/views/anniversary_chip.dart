import 'package:flutter/material.dart';

import '../../../../domain/day_math.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bevel_box.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/retro_window.dart';

/// The "together N days ♡" chip at the top of the countdowns window, or a
/// "set your day ♡" empty-state prompt the first time. Tapping either opens
/// [showAnniversaryDialog].
class AnniversaryChip extends StatelessWidget {
  const AnniversaryChip({super.key, required this.anniversary, required this.onTap, this.now});

  final DateTime? anniversary;
  final VoidCallback onTap;

  /// Injectable "now" for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final anniversary = this.anniversary;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: BevelBox(
          color: anniversary != null ? colors.mint : colors.chrome,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  anniversary != null
                      ? AppStrings.togetherDays(daysTogether(anniversary, now: now))
                      : AppStrings.setAnniversary,
                  style: AppTextStyles.body2.copyWith(color: colors.ink, fontWeight: FontWeight.bold),
                ),
              ),
              if (anniversary != null)
                Text(
                  '✎', // ✎ pencil — small edit affordance, same glyph
                  // vocabulary as RetroWindow's ★/♥ decorations.
                  style: AppTextStyles.caption.copyWith(color: colors.ink),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the RetroWindow-styled "when did you two get together?" dialog.
Future<void> showAnniversaryDialog(
  BuildContext context, {
  DateTime? existing,
  required ValueChanged<DateTime> onSave,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: _AnniversaryDialogContent(existing: existing, onSave: onSave),
    ),
  );
}

class _AnniversaryDialogContent extends StatefulWidget {
  const _AnniversaryDialogContent({this.existing, required this.onSave});

  final DateTime? existing;
  final ValueChanged<DateTime> onSave;

  @override
  State<_AnniversaryDialogContent> createState() => _AnniversaryDialogContentState();
}

class _AnniversaryDialogContentState extends State<_AnniversaryDialogContent> {
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _date = widget.existing ?? DateTime.now();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1970),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save() {
    widget.onSave(_date);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return RetroWindow(
      title: AppStrings.anniversaryDialogTitle,
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(AppStrings.anniversaryDialogBody, style: AppTextStyles.body2.copyWith(color: colors.ink)),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _pickDate,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: BevelBox(
                color: colors.surface,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                child: Text(friendlyDate(_date), style: AppTextStyles.body1.copyWith(color: colors.ink)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: PixelButton(primary: true, label: AppStrings.saveAnniversary, onPressed: _save),
          ),
        ],
      ),
    );
  }
}
