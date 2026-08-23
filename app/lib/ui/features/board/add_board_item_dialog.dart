import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../domain/models/note_color.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/bevel_box.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';
import 'board_image_prep.dart';
import 'board_stickers.dart';
import 'board_view_model.dart';

/// The board's "add" mini-menu — [note ✎] [photo ◉] [sticker ♥︎] — each
/// button opening its own small RetroWindow flow that ends by calling the
/// matching [BoardViewModel] add method.
Future<void> showAddBoardItemMenu(
  BuildContext context, {
  required BoardViewModel viewModel,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: _AddMenuContent(viewModel: viewModel),
    ),
  );
}

class _AddMenuContent extends StatelessWidget {
  const _AddMenuContent({required this.viewModel});

  final BoardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return RetroWindow(
      title: AppStrings.boardAddMenuTitle,
      onClose: () => Navigator.of(context).pop(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PixelButton(
            icon: Icons.edit_outlined,
            label: AppStrings.boardAddNote,
            onPressed: () {
              Navigator.of(context).pop();
              _showNoteSheet(context);
            },
          ),
          const SizedBox(width: 8),
          PixelButton(
            icon: Icons.photo_camera_outlined,
            label: AppStrings.boardAddPhoto,
            onPressed: () {
              Navigator.of(context).pop();
              _showPhotoSheet(context);
            },
          ),
          const SizedBox(width: 8),
          PixelButton(
            icon: Icons.favorite_border,
            label: AppStrings.boardAddSticker,
            onPressed: () {
              Navigator.of(context).pop();
              _showStickerSheet(context);
            },
          ),
        ],
      ),
    );
  }

  void _showNoteSheet(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: _BoardNoteSheet(viewModel: viewModel),
      ),
    );
  }

  void _showPhotoSheet(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: _BoardPhotoSheet(viewModel: viewModel),
      ),
    );
  }

  void _showStickerSheet(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: _BoardStickerSheet(viewModel: viewModel),
      ),
    );
  }
}

/// Text ≤500 chars + the standard sticky-note pastel picker (same colors as
/// `notes.color`, reusing [NoteColor]).
class _BoardNoteSheet extends StatefulWidget {
  const _BoardNoteSheet({required this.viewModel});

  final BoardViewModel viewModel;

  @override
  State<_BoardNoteSheet> createState() => _BoardNoteSheetState();
}

class _BoardNoteSheetState extends State<_BoardNoteSheet> {
  final _controller = TextEditingController();
  NoteColor _color = NoteColor.pink;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.viewModel.addNote(text: text, color: _color);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return RetroWindow(
      title: AppStrings.boardNoteDialogTitle,
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            style: AppTextStyles.body1,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: 500,
            decoration: const InputDecoration(hintText: AppStrings.noteBodyHint),
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: PixelButton(
              primary: true,
              label: AppStrings.saveNoteButton,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pick-a-photo flow, same shape as `send_instant_dialog.dart`'s picker but
/// without a caption — a board photo is just the picture.
class _BoardPhotoSheet extends StatefulWidget {
  const _BoardPhotoSheet({required this.viewModel});

  final BoardViewModel viewModel;

  @override
  State<_BoardPhotoSheet> createState() => _BoardPhotoSheetState();
}

class _BoardPhotoSheetState extends State<_BoardPhotoSheet> {
  final _picker = ImagePicker();

  XFile? _picked;
  Uint8List? _previewBytes;
  bool _picking = false;
  bool _uploading = false;
  String? _error;

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final file = await _picker.pickImage(source: source);
      if (file == null) {
        if (mounted) setState(() => _picking = false);
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _picked = file;
        _previewBytes = bytes;
        _picking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _error = AppStrings.instantPickFailed;
      });
    }
  }

  Future<void> _submit() async {
    final picked = _picked;
    final bytes = _previewBytes;
    if (picked == null || bytes == null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final prepared = await prepareBoardImage(bytes);
      final filename = boardPhotoUploadFilename(
        prepared.downscaled,
        picked.name,
      );
      await widget.viewModel.addPhoto(
        imageBytes: prepared.bytes,
        filename: filename,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = AppStrings.instantSendFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final busy = _picking || _uploading;
    final isAndroid = !kIsWeb && Platform.isAndroid;

    return RetroWindow(
      title: AppStrings.boardPhotoDialogTitle,
      onClose: busy ? null : () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: BevelBox(
              style: BevelStyle.sunken,
              padding: const EdgeInsets.all(4),
              child: SizedBox(
                width: 220,
                height: 220,
                child: _previewBytes == null
                    ? Center(
                        child: Icon(
                          Icons.photo_camera_outlined,
                          size: 48,
                          color: colors.chromeAlt,
                        ),
                      )
                    : Image.memory(
                        _previewBytes!,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_picked == null)
            isAndroid
                ? Row(
                    children: [
                      PixelButton(
                        icon: Icons.camera_alt_outlined,
                        label: AppStrings.instantCaptureCamera,
                        onPressed: _picking
                            ? null
                            : () => _pick(ImageSource.camera),
                      ),
                      const SizedBox(width: 8),
                      PixelButton(
                        icon: Icons.photo_library_outlined,
                        label: AppStrings.instantCaptureGallery,
                        onPressed: _picking
                            ? null
                            : () => _pick(ImageSource.gallery),
                      ),
                    ],
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: PixelButton(
                      icon: Icons.photo_library_outlined,
                      label: AppStrings.instantChoosePhoto,
                      onPressed: _picking
                          ? null
                          : () => _pick(ImageSource.gallery),
                    ),
                  )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: PixelButton(
                label: AppStrings.instantChangePhoto,
                onPressed: busy ? null : () => _pick(ImageSource.gallery),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Spacer(),
              PixelButton(
                primary: true,
                label: _uploading
                    ? AppStrings.instantSending
                    : AppStrings.instantSend,
                onPressed: (busy || _picked == null) ? null : _submit,
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: AppTextStyles.caption.copyWith(color: colors.warn),
            ),
          ],
        ],
      ),
    );
  }
}

/// The curated glyph/kaomoji grid — tap one to pin it.
class _BoardStickerSheet extends StatelessWidget {
  const _BoardStickerSheet({required this.viewModel});

  final BoardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return RetroWindow(
      title: AppStrings.boardStickerDialogTitle,
      onClose: () => Navigator.of(context).pop(),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: BoardStickerCatalog.all.map((sticker) {
          return GestureDetector(
            onTap: () {
              viewModel.addSticker(sticker.glyph);
              Navigator.of(context).pop();
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Semantics(
                button: true,
                label: sticker.label,
                child: BevelBox(
                  padding: const EdgeInsets.all(10),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Text(
                        sticker.glyph,
                        style: AppTextStyles.kaomojiMedium.copyWith(
                          color: colors.ink,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
