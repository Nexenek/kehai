import 'package:flutter/material.dart';

import '../../../../domain/models/note.dart';
import '../../../../domain/models/note_color.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bevel_box.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/retro_window.dart';

/// The result of the note add/edit dialog — ready to hand straight to
/// [NotesViewModel.addNote]/`updateNote`.
class NoteDraft {
  const NoteDraft({
    required this.title,
    required this.body,
    required this.color,
    required this.pinned,
  });

  final String title;
  final String body;
  final NoteColor color;
  final bool pinned;
}

/// Shows the RetroWindow-styled add/edit dialog. Pass [existing] to edit
/// (and get a delete button); omit it to create a new note.
Future<void> showNoteDialog(
  BuildContext context, {
  Note? existing,
  required ValueChanged<NoteDraft> onSave,
  VoidCallback? onDelete,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: _NoteDialogContent(
        existing: existing,
        onSave: onSave,
        onDelete: onDelete,
      ),
    ),
  );
}

class _NoteDialogContent extends StatefulWidget {
  const _NoteDialogContent({
    this.existing,
    required this.onSave,
    this.onDelete,
  });

  final Note? existing;
  final ValueChanged<NoteDraft> onSave;
  final VoidCallback? onDelete;

  @override
  State<_NoteDialogContent> createState() => _NoteDialogContentState();
}

class _NoteDialogContentState extends State<_NoteDialogContent> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late NoteColor _color;
  late bool _pinned;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.existing?.title ?? '',
    );
    _bodyController = TextEditingController(text: widget.existing?.body ?? '');
    _color = widget.existing?.color ?? NoteColor.pink;
    _pinned = widget.existing?.pinned ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(
      NoteDraft(
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        color: _color,
        pinned: _pinned,
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
      title: isEdit ? AppStrings.editNoteTitle : AppStrings.newNoteTitle,
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.noteTitleLabel,
            style: AppTextStyles.caption.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _titleController,
            style: AppTextStyles.body1,
            decoration: const InputDecoration(
              hintText: AppStrings.noteTitleHint,
            ),
            autofocus: !isEdit,
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.noteBodyLabel,
            style: AppTextStyles.caption.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _bodyController,
            style: AppTextStyles.body1,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: AppStrings.noteBodyHint,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.noteColorLabel,
            style: AppTextStyles.caption.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 6),
          Row(
            children: NoteColor.values.map((c) {
              final selected = c == _color;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Semantics(
                      button: true,
                      selected: selected,
                      label: c.name,
                      child: BevelBox(
                        color: c.colorOf(colors),
                        style: selected ? BevelStyle.sunken : BevelStyle.raised,
                        thickness: selected ? 3 : 2,
                        padding: const EdgeInsets.all(10),
                        child: const SizedBox(width: 16, height: 16),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() => _pinned = !_pinned),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Semantics(
                button: true,
                selected: _pinned,
                label: AppStrings.notePinLabel,
                child: BevelBox(
                  color: _pinned ? colors.chrome : colors.surface,
                  style: _pinned ? BevelStyle.sunken : BevelStyle.raised,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '✦',
                        style: AppTextStyles.caption.copyWith(
                          color: colors.ink,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        AppStrings.notePinLabel,
                        style: AppTextStyles.caption.copyWith(
                          color: colors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (isEdit)
                PixelButton(
                  label: AppStrings.deleteNoteButton,
                  onPressed: _delete,
                ),
              const Spacer(),
              PixelButton(
                primary: true,
                label: AppStrings.saveNoteButton,
                onPressed: _save,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
