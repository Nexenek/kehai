import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/bevel_box.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';
import 'doodle_canvas.dart';
import 'doodle_canvas_state.dart';
import 'doodle_png_export.dart';

/// Shows the RetroWindow-styled "draw something for them ♡" canvas dialog.
///
/// [onSend] does the actual upload — the dialog only knows how to turn
/// strokes into PNG bytes and await the result, so the repository call
/// (and the couple/author ids it needs) stays with whoever opens this,
/// per the app's dumb-view/smart-viewmodel split.
Future<void> showDoodleCanvasDialog(
  BuildContext context, {
  required Future<void> Function(Uint8List pngBytes) onSend,
}) async {
  final sent = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: _DoodleCanvasDialogContent(onSend: onSend),
    ),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(AppStrings.doodleSent)));
  }
}

class _DoodleCanvasDialogContent extends StatefulWidget {
  const _DoodleCanvasDialogContent({required this.onSend});

  final Future<void> Function(Uint8List pngBytes) onSend;

  @override
  State<_DoodleCanvasDialogContent> createState() =>
      _DoodleCanvasDialogContentState();
}

class _DoodleCanvasDialogContentState
    extends State<_DoodleCanvasDialogContent> {
  static const _brushSmall = 4.0;
  static const _brushBig = 10.0;

  late final DoodleCanvasState _state = DoodleCanvasState(
    color: const Color(
      0xFF362D3B,
    ), // AppColors.light.ink — a sane default regardless of theme.
    brushWidth: _brushSmall,
  );

  bool _uploading = false;
  String? _error;

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final png = await renderStrokesToPng(_state.strokes);
      await widget.onSend(png);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = AppStrings.doodleSendFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final swatches = <Color>[
      colors.ink,
      colors.accent,
      colors.accent2,
      colors.mint,
      colors.sky,
      colors.warn,
    ];

    return RetroWindow(
      title: AppStrings.doodleDialogTitle,
      onClose: _uploading ? null : () => Navigator.of(context).pop(),
      child: ListenableBuilder(
        listenable: _state,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: BevelBox(
                style: BevelStyle.sunken,
                padding: EdgeInsets.zero,
                child: DoodleCanvas(state: _state),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final swatch in swatches) ...[
                  _ColorSwatch(
                    color: swatch,
                    selected: _state.color == swatch,
                    onTap: () => _state.setColor(swatch),
                  ),
                  const SizedBox(width: 6),
                ],
                const Spacer(),
                _BrushDot(
                  diameter: 8,
                  tooltip: AppStrings.brushSmallTooltip,
                  selected: _state.brushWidth == _brushSmall,
                  color: colors.ink,
                  onTap: () => _state.setBrushWidth(_brushSmall),
                ),
                const SizedBox(width: 6),
                _BrushDot(
                  diameter: 16,
                  tooltip: AppStrings.brushBigTooltip,
                  selected: _state.brushWidth == _brushBig,
                  color: colors.ink,
                  onTap: () => _state.setBrushWidth(_brushBig),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                PixelButton(
                  label: AppStrings.doodleUndo,
                  onPressed: (_state.canUndo && !_uploading)
                      ? _state.undo
                      : null,
                ),
                const SizedBox(width: 8),
                PixelButton(
                  label: AppStrings.doodleClear,
                  onPressed: (!_state.isEmpty && !_uploading)
                      ? _state.clear
                      : null,
                ),
                const Spacer(),
                PixelButton(
                  primary: true,
                  label: _uploading
                      ? AppStrings.doodleSending
                      : AppStrings.doodleSend,
                  onPressed: (_uploading || _state.isEmpty) ? null : _submit,
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
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          selected: selected,
          child: BevelBox(
            color: color,
            style: selected ? BevelStyle.sunken : BevelStyle.raised,
            thickness: selected ? 3 : 2,
            padding: const EdgeInsets.all(8),
            child: const SizedBox(width: 14, height: 14),
          ),
        ),
      ),
    );
  }
}

class _BrushDot extends StatelessWidget {
  const _BrushDot({
    required this.diameter,
    required this.tooltip,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final double diameter;
  final String tooltip;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Semantics(
            button: true,
            selected: selected,
            label: tooltip,
            child: BevelBox(
              color: selected ? colors.chrome : colors.surface,
              style: selected ? BevelStyle.sunken : BevelStyle.raised,
              padding: const EdgeInsets.all(6),
              child: Center(
                child: Container(
                  width: diameter,
                  height: diameter,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
