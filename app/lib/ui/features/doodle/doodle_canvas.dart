import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'doodle_canvas_painter.dart';
import 'doodle_canvas_state.dart';

/// The square freehand drawing surface: plain white "paper" with a subtle
/// pixel-grid texture, driven straight off [state] via pan gestures. All
/// drawing logic lives on [state] (see [DoodleCanvasState]) — this widget
/// is just gesture-plumbing + painting.
class DoodleCanvas extends StatelessWidget {
  const DoodleCanvas({super.key, required this.state, this.size = 320});

  final DoodleCanvasState state;
  final double size;

  Offset _clamp(Offset point) =>
      Offset(point.dx.clamp(0, size), point.dy.clamp(0, size));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onPanStart: (details) => state.startStroke(_clamp(details.localPosition)),
      onPanUpdate: (details) =>
          state.extendStroke(_clamp(details.localPosition)),
      onPanEnd: (_) => state.endStroke(),
      onPanCancel: state.endStroke,
      child: MouseRegion(
        cursor: SystemMouseCursors.precise,
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => ClipRect(
            child: SizedBox(
              width: size,
              height: size,
              child: ColoredBox(
                color: Colors.white,
                child: CustomPaint(
                  size: Size(size, size),
                  painter: _GridPainter(
                    color: colors.chromeAlt.withValues(alpha: 0.3),
                  ),
                  foregroundPainter: DoodleCanvasPainter(state.strokes),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Faint fixed-step grid drawn under the strokes — texture only, never part
/// of the exported PNG (the export re-renders straight from [Stroke] data,
/// see `doodle_png_export.dart`).
class _GridPainter extends CustomPainter {
  const _GridPainter({required this.color});

  final Color color;
  static const _step = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = _step; x < size.width; x += _step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = _step; y < size.height; y += _step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.color != color;
}
