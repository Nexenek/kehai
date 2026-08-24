/// The curtain itself: two painted drape halves plus a scalloped valance,
/// drawn as flat rects/paths — no gradients, no anti-aliasing tricks — per
/// design-language.md's painted-pixel rule (see `pet_painter.dart` for the
/// same idea over a 16×16 grid; a curtain has no fixed grid, so this paints
/// its pleats as proportional bands instead).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One drape half. [rightSide] mirrors the pleat phase so the two halves
/// read as one continuous curtain rather than two copies of the same panel.
class PortalDrapePainter extends CustomPainter {
  const PortalDrapePainter({
    required this.fill,
    required this.pleatShade,
    required this.valance,
    required this.ink,
    required this.rightSide,
    this.sway = 0,
  });

  final Color fill;
  final Color pleatShade;
  final Color valance;
  final Color ink;
  final bool rightSide;

  /// -1..1: the idle sway's current offset, in pixels of horizontal drift
  /// at the drape's outer (loose) edge. Zero when reduced motion applies or
  /// the curtain isn't idle — see `portal_call_screen.dart`.
  final double sway;

  static const _pleats = 5;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final valanceHeight = math.min(size.height * 0.08, 28.0);
    final bodyTop = valanceHeight;
    final bodyRect = Rect.fromLTWH(
      0,
      bodyTop,
      size.width,
      size.height - bodyTop,
    );

    // The loose (openable) edge is the inner edge — left drape's right
    // side, right drape's left side. Sway drifts that edge only, so the
    // curtain reads as fabric hanging from a fixed rod rather than the
    // whole panel sliding.
    final swayDx = sway;
    final path = Path();
    if (rightSide) {
      path.moveTo(0, bodyTop);
      path.lineTo(size.width, bodyTop);
      path.lineTo(size.width, size.height);
      path.lineTo(swayDx.abs(), size.height);
      path.close();
    } else {
      path.moveTo(0, bodyTop);
      path.lineTo(size.width, bodyTop);
      path.lineTo(size.width - swayDx.abs(), size.height);
      path.lineTo(0, size.height);
      path.close();
    }
    canvas.drawPath(path, Paint()..color = fill);

    // Pleats: alternating shaded vertical bands, clipped to the swayed
    // body shape so they never poke out past the drifted edge.
    canvas.save();
    canvas.clipPath(path);
    final pleatWidth = size.width / _pleats;
    final pleatPaint = Paint()..color = pleatShade;
    for (var i = 0; i < _pleats; i++) {
      final shaded = rightSide ? i.isEven : i.isOdd;
      if (!shaded) continue;
      canvas.drawRect(
        Rect.fromLTWH(i * pleatWidth, bodyTop, pleatWidth, bodyRect.height),
        pleatPaint,
      );
    }
    canvas.restore();

    // Valance: a solid band across the top with a scalloped lower edge —
    // a row of half-circles painted in the body colour "bite" into the
    // valance colour, chunky and pixel-flat rather than smoothed.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, valanceHeight),
      Paint()..color = valance,
    );
    const teeth = 3;
    final toothWidth = size.width / teeth;
    for (var i = 0; i < teeth; i++) {
      final cx = (i + 0.5) * toothWidth;
      canvas.drawCircle(
        Offset(cx, valanceHeight),
        toothWidth * 0.42,
        Paint()..color = fill,
      );
    }

    // Ink outline — the "painted, not photographic" edge every pixel
    // widget in this app carries.
    final outline = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Offset.zero & size, outline);
    canvas.drawLine(
      Offset(0, valanceHeight),
      Offset(size.width, valanceHeight),
      outline,
    );
  }

  @override
  bool shouldRepaint(covariant PortalDrapePainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.pleatShade != pleatShade ||
      oldDelegate.valance != valance ||
      oldDelegate.ink != ink ||
      oldDelegate.rightSide != rightSide ||
      oldDelegate.sway != sway;
}
