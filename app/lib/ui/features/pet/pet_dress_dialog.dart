import 'package:flutter/material.dart';

import '../../../domain/models/pet.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/bevel_box.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';
import 'pet_sprite_view.dart';
import 'pet_state.dart';

/// What the dress-up dialog hands back.
class PetLook {
  const PetLook({required this.variant, required this.outfit});

  final PetVariant variant;
  final PetOutfit outfit;
}

/// The [dress ▾] picker: which creature, and what they're wearing, with a
/// live painted preview so you see the change before you commit it.
Future<void> showPetDressDialog(
  BuildContext context, {
  required PetVariant variant,
  required PetOutfit outfit,
  required PetState state,
  required ValueChanged<PetLook> onSave,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: _PetDressContent(
        variant: variant,
        outfit: outfit,
        state: state,
        onSave: onSave,
      ),
    ),
  );
}

class _PetDressContent extends StatefulWidget {
  const _PetDressContent({
    required this.variant,
    required this.outfit,
    required this.state,
    required this.onSave,
  });

  final PetVariant variant;
  final PetOutfit outfit;
  final PetState state;
  final ValueChanged<PetLook> onSave;

  @override
  State<_PetDressContent> createState() => _PetDressContentState();
}

class _PetDressContentState extends State<_PetDressContent> {
  late PetVariant _variant = widget.variant;
  late PetOutfit _outfit = widget.outfit;

  void _save() {
    widget.onSave(PetLook(variant: _variant, outfit: _outfit));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return RetroWindow(
      title: AppStrings.petDressTitle,
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: PetSpriteView(
              variant: _variant,
              outfit: _outfit,
              state: widget.state,
              size: 96,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.petVariantLabel,
            style: AppTextStyles.caption.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in PetVariant.values)
                _ChoiceChip(
                  label: option.label,
                  selected: option == _variant,
                  onTap: () => setState(() => _variant = option),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.petOutfitLabel,
            style: AppTextStyles.caption.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in PetOutfit.values)
                _ChoiceChip(
                  label: option.label,
                  selected: option == _outfit,
                  onTap: () => setState(() => _outfit = option),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: PixelButton(
              primary: true,
              label: AppStrings.petDressSave,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}

/// A chunky selectable bevel chip — sunken when picked, with a ✓ so the
/// selection never rides on color alone (design-language.md a11y floor).
class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: BevelBox(
            color: selected ? colors.chrome : colors.surface,
            style: selected ? BevelStyle.sunken : BevelStyle.raised,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              selected ? '$label ✓' : label,
              style: AppTextStyles.button.copyWith(color: colors.ink),
            ),
          ),
        ),
      ),
    );
  }
}
