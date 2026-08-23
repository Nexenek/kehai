import 'package:flutter/material.dart';

import '../../../../domain/models/countdown.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/retro_window.dart';
import '../view_models/countdowns_view_model.dart';
import 'anniversary_chip.dart';
import 'countdown_dialog.dart';
import 'countdown_row.dart';

/// The "countdowns" RetroWindow: the together-days chip, the sorted list of
/// countdown rows (nearest upcoming highlighted), and the add button.
class CountdownsWindow extends StatelessWidget {
  const CountdownsWindow({super.key, required this.viewModel});

  final CountdownsViewModel viewModel;

  void _openDialog(BuildContext context, {Countdown? existing}) {
    showCountdownDialog(
      context,
      existing: existing,
      onSave: (draft) {
        if (existing != null) {
          viewModel.updateCountdown(
            existing.id,
            title: draft.title,
            date: draft.date,
            kaomoji: draft.kaomoji,
          );
        } else {
          viewModel.addCountdown(
            title: draft.title,
            date: draft.date,
            kaomoji: draft.kaomoji,
          );
        }
      },
      onDelete: existing != null
          ? () => viewModel.deleteCountdown(existing.id)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final nearest = viewModel.nearestUpcoming;
    final list = viewModel.sorted;

    return RetroWindow(
      title: AppStrings.countdownsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnniversaryChip(
            anniversary: viewModel.anniversary,
            onTap: () => showAnniversaryDialog(
              context,
              existing: viewModel.anniversary,
              onSave: viewModel.setAnniversary,
            ),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                AppStrings.countdownsEmpty,
                style: AppTextStyles.body2.copyWith(color: colors.ink),
              ),
            )
          else
            ...list.map(
              (c) => CountdownRow(
                countdown: c,
                highlighted: nearest != null && c.id == nearest.id,
                onTap: () => _openDialog(context, existing: c),
              ),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: PixelButton(
              primary: true,
              icon: Icons.favorite,
              label: AppStrings.addCountdown,
              onPressed: () => _openDialog(context),
            ),
          ),
        ],
      ),
    );
  }
}
