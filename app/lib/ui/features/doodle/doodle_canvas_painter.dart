import 'package:flutter/material.dart';

import 'stroke.dart';

/// Paints [strokes] as polylines with round caps/joins — a plain freehand
/// pen look, no smoothing/interpolation for v1. Shared between the live
/// on-screen canvas and the offscreen PNG export so what you draw is
/// exactly what gets sent (see `doodle_png_export.dart`).
class DoodleCanvasPainter extends CustomPainter {
  const DoodleCanvasPainter(this.strokes);

  final List<Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        // A tap without a drag — draw a dot so it isn't invisible.
        canvas.drawCircle(
          stroke.points.first,
          stroke.width / 2,
          paint..style = PaintingStyle.fill,
        );
        continue;
      }

      final path = Path()
        ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant DoodleCanvasPainter oldDelegate) => true;
}
