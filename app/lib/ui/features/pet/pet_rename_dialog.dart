import 'package:flutter/material.dart';

import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';

/// The [rename] dialog. Capped at the server's 30 characters; leaving it
/// blank simply puts "kehai-chan" back.
Future<void> showPetRenameDialog(
  BuildContext context, {
  required String name,
  required ValueChanged<String> onSave,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: _PetRenameContent(name: name, onSave: onSave),
    ),
  );
}

class _PetRenameContent extends StatefulWidget {
  const _PetRenameContent({required this.name, required this.onSave});

  final String name;
  final ValueChanged<String> onSave;

  @override
  State<_PetRenameContent> createState() => _PetRenameContentState();
}

class _PetRenameContentState extends State<_PetRenameContent> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.name,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(_controller.text.trim());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return RetroWindow(
      title: AppStrings.petRenameTitle,
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.petNameLabel,
            style: AppTextStyles.caption.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _controller,
            style: AppTextStyles.body1,
            maxLength: 30,
            autofocus: true,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(hintText: AppStrings.petNameHint),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: PixelButton(
              primary: true,
              label: AppStrings.petRenameSave,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}
