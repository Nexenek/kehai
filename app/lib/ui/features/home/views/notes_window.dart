import 'package:flutter/material.dart';

import '../../../../domain/models/note.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/retro_window.dart';
import '../view_models/notes_view_model.dart';
import 'note_card.dart';
import 'note_dialog.dart';

/// The "notes" RetroWindow: a wrap grid of sticky notes (pinned first) and
/// the add button.
class NotesWindow extends StatelessWidget {
  const NotesWindow({super.key, required this.viewModel, this.onClose});

  final NotesViewModel viewModel;

  /// Makes the window's ♥ functional when it's shown inside the desktop
  /// companion drawer; decorative (null) in the other layouts.
  final VoidCallback? onClose;

  void _openDialog(BuildContext context, {Note? existing}) {
    showNoteDialog(
      context,
      existing: existing,
      onSave: (draft) {
        if (existing != null) {
          viewModel.updateNote(
            existing.id,
            title: draft.title,
            body: draft.body,
            color: draft.color,
            pinned: draft.pinned,
          );
        } else {
          viewModel.addNote(
            title: draft.title,
            body: draft.body,
            color: draft.color,
            pinned: draft.pinned,
          );
        }
      },
      onDelete: existing != null
          ? () => viewModel.deleteNote(existing.id)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final notes = viewModel.sorted;

    return RetroWindow(
      title: AppStrings.notesTitle,
      onClose: onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (notes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                AppStrings.notesEmpty,
                style: AppTextStyles.body2.copyWith(color: colors.ink),
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: notes
                  .map(
                    (n) => NoteCard(
                      note: n,
                      onTap: () => _openDialog(context, existing: n),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: PixelButton(
              primary: true,
              icon: Icons.favorite,
              label: AppStrings.addNote,
              onPressed: () => _openDialog(context),
            ),
          ),
        ],
      ),
    );
  }
}
