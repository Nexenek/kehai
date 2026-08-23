import 'package:flutter/material.dart';

import '../../../../domain/models/note.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bevel_box.dart';

/// One sticky note tile in the notes grid — its pastel color, a tiny pixel
/// pin glyph when pinned, title, and a body preview.
class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.note, this.onTap});

  final Note note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fill = note.color.colorOf(colors);
    final title = note.title.isEmpty ? AppStrings.untitledNote : note.title;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: 150,
          height: 120,
          child: BevelBox(
            color: fill,
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (note.pinned) ...[
                      Text('✦', style: AppTextStyles.caption.copyWith(color: colors.ink)),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        style: AppTextStyles.body2.copyWith(color: colors.ink, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    note.body,
                    style: AppTextStyles.caption.copyWith(color: colors.ink),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
