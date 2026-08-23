import 'package:file_selector/file_selector.dart' show XFile, openFile;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/models/shared_file.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';
import 'delete_file_confirm_dialog.dart';
import 'file_row.dart';
import 'files_view_model.dart';
import 'shared_file_upload_limits.dart';

/// The "our files" RetroWindow: the couple's shared drive
/// (kb/features.md "Shared file storage") — a plain list of uploaded
/// files, an upload button, and per-row open/delete. Self-contained, same
/// as `InstantsWindow`/`BoardWindow`: this batch builds the feature but
/// does NOT wire it into the home tray/layout (another agent owns that
/// composition this round); a caller just needs a [FilesViewModel] wired
/// to real repositories.
///
/// "Open" (tapping a row) doesn't do anything file-type-aware itself — it
/// mints a tokenized download URL (`FilesViewModel.downloadUrl`) and hands
/// it to `url_launcher`, which opens it in the platform's browser/handler.
/// The browser then decides preview-vs-download by content type, same as
/// clicking any other file link on the web; this app never tries to
/// render a PDF/video/whatever inline.
class FilesWindow extends StatelessWidget {
  const FilesWindow({super.key, required this.viewModel, this.onClose});

  final FilesViewModel viewModel;

  /// Makes the window's ♥ functional when it's shown inside the desktop
  /// companion drawer; decorative (null) in the other layouts.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) =>
          _FilesWindowBody(viewModel: viewModel, onClose: onClose),
    );
  }
}

class _FilesWindowBody extends StatefulWidget {
  const _FilesWindowBody({required this.viewModel, this.onClose});

  final FilesViewModel viewModel;
  final VoidCallback? onClose;

  @override
  State<_FilesWindowBody> createState() => _FilesWindowBodyState();
}

class _FilesWindowBodyState extends State<_FilesWindowBody> {
  bool _uploading = false;
  String? _openingId;
  String? _error;

  /// Picking uses `file_selector`'s `openFile` on every platform this app
  /// ships on (desktop *and* Android) — unlike the instants/board photo
  /// pickers, which branch on Android for a camera option via
  /// `image_picker`, a shared file has no "capture" source, so there's
  /// nothing to branch on.
  Future<void> _pickAndUpload() async {
    setState(() => _error = null);

    XFile? picked;
    try {
      picked = await openFile();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = AppStrings.filesPickFailed);
      return;
    }
    if (picked == null) return; // user cancelled — not an error

    final length = await picked.length();
    if (!isWithinSharedFileUploadLimit(length)) {
      if (!mounted) return;
      setState(() => _error = AppStrings.filesTooBig);
      return;
    }

    setState(() => _uploading = true);
    try {
      // Streamed straight from the picked file (`openRead()`), never fully
      // buffered into memory — see `SharedFileRepository.create`'s doc
      // comment.
      await widget.viewModel.upload(
        stream: picked.openRead(),
        length: length,
        filename: picked.name,
        label: picked.name,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = AppStrings.filesUploadFailed);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _open(SharedFile file) async {
    setState(() {
      _error = null;
      _openingId = file.id;
    });
    final url = await widget.viewModel.downloadUrl(file);
    if (!mounted) return;

    if (url == null) {
      setState(() {
        _openingId = null;
        _error = AppStrings.filesOpenFailed;
      });
      return;
    }

    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    setState(() {
      _openingId = null;
      if (!opened) _error = AppStrings.filesOpenFailed;
    });
  }

  Future<void> _confirmDelete(SharedFile file) async {
    final confirmed = await showDeleteFileConfirmDialog(context, file: file);
    if (confirmed) widget.viewModel.deleteFile(file.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final viewModel = widget.viewModel;
    final files = viewModel.files;
    final showEmpty = files.isEmpty && !viewModel.isLoading;

    return RetroWindow(
      title: AppStrings.filesTitle,
      onClose: widget.onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                AppStrings.filesEmpty,
                style: AppTextStyles.body2.copyWith(color: colors.ink),
              ),
            )
          else
            ...files.map(
              (f) => FileRow(
                file: f,
                isMine: f.uploadedBy == viewModel.myUserId,
                isOpening: _openingId == f.id,
                onOpen: () => _open(f),
                onDeleteRequest: () => _confirmDelete(f),
              ),
            ),
          if (viewModel.hasMore) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.center,
              child: PixelButton(
                label: AppStrings.filesLoadMore,
                onPressed: viewModel.isLoadingMore ? null : viewModel.loadMore,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: AppTextStyles.caption.copyWith(color: colors.warn),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_uploading) ...[
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                PixelButton(
                  primary: true,
                  icon: Icons.upload_file,
                  label: _uploading
                      ? AppStrings.filesUploading
                      : AppStrings.filesUpload,
                  onPressed: _uploading ? null : _pickAndUpload,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
