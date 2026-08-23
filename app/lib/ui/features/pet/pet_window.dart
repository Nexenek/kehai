import 'package:flutter/material.dart';

import '../../../domain/models/pet.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';
import 'pet_dress_dialog.dart';
import 'pet_rename_dialog.dart';
import 'pet_sprite_view.dart';
import 'pet_view_model.dart';

/// The shared pet's RetroWindow: the painted creature, its name, the one
/// derived state line, and the four care buttons. Both partners act on the
/// same record, so a feed from their side lands here live.
///
/// Self-contained, same as `InstantsWindow` — this batch builds the feature
/// but deliberately does NOT wire it into the home tray/layout (the
/// coordinator owns that composition). A caller just needs a [PetViewModel]
/// wired to real repositories, with `init()` already called.
class PetWindow extends StatelessWidget {
  const PetWindow({
    super.key,
    required this.viewModel,
    this.onClose,
    this.spriteSize = 128,
  });

  final PetViewModel viewModel;

  /// Makes the window's ♥ functional when it's shown inside the desktop
  /// companion drawer; decorative (null) in the other layouts.
  final VoidCallback? onClose;

  final double spriteSize;

  void _openDress(BuildContext context, Pet pet) {
    showPetDressDialog(
      context,
      variant: pet.variant,
      outfit: pet.outfit,
      state: viewModel.state,
      onSave: (look) =>
          viewModel.dress(variant: look.variant, outfit: look.outfit),
    );
  }

  void _openRename(BuildContext context, Pet pet) {
    showPetRenameDialog(context, name: pet.name, onSave: viewModel.rename);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final colors = context.colors;
        final pet = viewModel.pet;

        return RetroWindow(
          title: AppStrings.petTitle,
          onClose: onClose,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pet == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    viewModel.isLoading
                        ? AppStrings.petAdopting
                        : AppStrings.petUnavailable,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body2.copyWith(color: colors.ink),
                  ),
                )
              else
                ..._petBody(context, pet),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _petBody(BuildContext context, Pet pet) {
    final colors = context.colors;
    final state = viewModel.state;

    return [
      Semantics(
        label: '${pet.displayName} — ${state.line}',
        child: Center(
          child: PetSpriteView(
            variant: pet.variant,
            outfit: pet.outfit,
            state: state,
            size: spriteSize,
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        pet.displayName,
        textAlign: TextAlign.center,
        style: AppTextStyles.heading.copyWith(color: colors.ink),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 2),
      Text(
        state.line,
        textAlign: TextAlign.center,
        style: AppTextStyles.body2.copyWith(color: colors.ink),
      ),
      if (viewModel.error != null) ...[
        const SizedBox(height: 6),
        Text(
          viewModel.error!,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(color: colors.accent),
        ),
      ],
      const SizedBox(height: 12),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          Tooltip(
            message: AppStrings.petFeedTooltip,
            child: PixelButton(
              primary: true,
              label: AppStrings.petFeed,
              onPressed: viewModel.feed,
            ),
          ),
          Tooltip(
            message: AppStrings.petPetTooltip,
            child: PixelButton(
              label: AppStrings.petPet,
              onPressed: viewModel.cuddle,
            ),
          ),
          Tooltip(
            message: AppStrings.petDressTooltip,
            child: PixelButton(
              label: AppStrings.petDress,
              onPressed: () => _openDress(context, pet),
            ),
          ),
          Tooltip(
            message: AppStrings.petRenameTooltip,
            child: PixelButton(
              label: AppStrings.petRename,
              onPressed: () => _openRename(context, pet),
            ),
          ),
        ],
      ),
    ];
  }
}
