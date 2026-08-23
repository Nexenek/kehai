import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/bevel_box.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';
import 'instant_image_prep.dart';

/// Shows the RetroWindow-styled "send an instant" capture dialog.
///
/// [onSend] does the actual upload — the dialog only knows how to pick a
/// photo, downscale it if needed, and await the result, so the repository
/// call (and the couple/author ids it needs) stays with whoever opens this,
/// per the app's dumb-view/smart-viewmodel split (see
/// `doodle_canvas_dialog.dart`'s `showDoodleCanvasDialog`).
Future<void> showSendInstantDialog(
  BuildContext context, {
  required Future<void> Function({
    required Uint8List imageBytes,
    required String filename,
    required String caption,
  })
  onSend,
}) async {
  final sent = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: _SendInstantDialogContent(onSend: onSend),
    ),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(AppStrings.instantSent)));
  }
}

class _SendInstantDialogContent extends StatefulWidget {
  const _SendInstantDialogContent({required this.onSend});

  final Future<void> Function({
    required Uint8List imageBytes,
    required String filename,
    required String caption,
  })
  onSend;

  @override
  State<_SendInstantDialogContent> createState() =>
      _SendInstantDialogContentState();
}

class _SendInstantDialogContentState extends State<_SendInstantDialogContent> {
  final _picker = ImagePicker();
  final _captionController = TextEditingController();

  XFile? _picked;
  Uint8List? _previewBytes;
  bool _picking = false;
  bool _uploading = false;
  String? _error;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

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
      final prepared = await prepareInstantImage(bytes);
      final filename = instantUploadFilename(prepared.downscaled, picked.name);
      await widget.onSend(
        imageBytes: prepared.bytes,
        filename: filename,
        caption: _captionController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
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

    return RetroWindow(
      title: AppStrings.sendInstantDialogTitle,
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
                width: 240,
                height: 240,
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
                        // Photos aren't pixel art — render them normally
                        // rather than the nearest-neighbor look used for
                        // doodles/sprites (design-language.md's crispness
                        // rule is about UI chrome, not real photos).
                        filterQuality: FilterQuality.medium,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_picked == null)
            _PickButtons(picking: _picking, onPick: _pick)
          else
            Align(
              alignment: Alignment.centerLeft,
              child: PixelButton(
                label: AppStrings.instantChangePhoto,
                onPressed: busy ? null : () => _pick(ImageSource.gallery),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            AppStrings.instantCaptionHint,
            style: AppTextStyles.caption.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _captionController,
            style: AppTextStyles.body1,
            maxLength: instantCaptionMaxLength,
            maxLines: 2,
            enabled: !busy,
            decoration: const InputDecoration(
              hintText: AppStrings.instantCaptionHint,
            ),
          ),
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

/// Android gets camera-or-gallery; every other platform (desktop) only
/// gets gallery — `image_picker`'s desktop backend is a plain file
/// selector, there's no camera source to offer there.
class _PickButtons extends StatelessWidget {
  const _PickButtons({required this.picking, required this.onPick});

  final bool picking;
  final ValueChanged<ImageSource> onPick;

  @override
  Widget build(BuildContext context) {
    final isAndroid = !kIsWeb && Platform.isAndroid;
    if (!isAndroid) {
      return Align(
        alignment: Alignment.centerLeft,
        child: PixelButton(
          icon: Icons.photo_library_outlined,
          label: AppStrings.instantChoosePhoto,
          onPressed: picking ? null : () => onPick(ImageSource.gallery),
        ),
      );
    }
    return Row(
      children: [
        PixelButton(
          icon: Icons.camera_alt_outlined,
          label: AppStrings.instantCaptureCamera,
          onPressed: picking ? null : () => onPick(ImageSource.camera),
        ),
        const SizedBox(width: 8),
        PixelButton(
          icon: Icons.photo_library_outlined,
          label: AppStrings.instantCaptureGallery,
          onPressed: picking ? null : () => onPick(ImageSource.gallery),
        ),
      ],
    );
  }
}
