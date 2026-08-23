import 'package:flutter/material.dart';

import '../../../domain/models/shared_file.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/time_ago.dart';
import '../../core/widgets/bevel_box.dart';
import 'file_type_glyph.dart';

/// One row in the shared-files list: pixel type-glyph, label, a
/// "who · Xago" caption, and a small ✕ delete affordance. Tapping the row
/// body opens/downloads the file; both a long-press on the row and a tap
/// on the ✕ ask [onDeleteRequest] to confirm — the caller (files_window.dart)
/// owns the actual confirm dialog, same dumb-view split as `CountdownRow`.
///
/// File size isn't shown: PocketBase's file field only stores the filename
/// on the record, not its byte size, so displaying one cheaply would mean
/// either a HEAD request per row (not cheap for a list) or a bespoke
/// server-side size field populated by a custom upload hook — out of scope
/// for this v1 pass. See `SharedFile`'s doc comment for the field shape.
class FileRow extends StatelessWidget {
  const FileRow({
    super.key,
    required this.file,
    required this.isMine,
    required this.isOpening,
    required this.onOpen,
    required this.onDeleteRequest,
  });

  final SharedFile file;
  final bool isMine;
  final bool isOpening;
  final VoidCallback onOpen;
  final VoidCallback onDeleteRequest;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final relative = relativeTime(file.created);
    final caption = isMine
        ? AppStrings.filesYouCaption(relative)
        : AppStrings.filesThemCaption(relative);
    final glyph = sharedFileGlyph(file.extension);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: BevelBox(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: isOpening ? null : onOpen,
                onLongPress: onDeleteRequest,
                child: MouseRegion(
                  cursor: isOpening
                      ? SystemMouseCursors.wait
                      : SystemMouseCursors.click,
                  child: Semantics(
                    button: true,
                    label: '${file.displayLabel}, $caption',
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          glyph,
                          style: AppTextStyles.heading.copyWith(
                            fontSize: 16,
                            color: colors.accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                file.displayLabel,
                                style: AppTextStyles.body2.copyWith(
                                  color: colors.ink,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                caption,
                                style: AppTextStyles.caption.copyWith(
                                  color: colors.chromeAlt,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isOpening) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.accent,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDeleteRequest,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Semantics(
                  button: true,
                  label: AppStrings.filesDeleteTooltip,
                  child: BevelBox(
                    color: colors.warn,
                    padding: const EdgeInsets.all(3),
                    child: Icon(Icons.close, size: 12, color: colors.ink),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
