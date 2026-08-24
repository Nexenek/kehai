import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// Paints the mood jar itself: a pixel glass outline with a subtle pastel
/// shine, filled with one little bead per (recent) mood entry.
/// [beadColors] must be oldest-first — beads are packed in rows from the
/// bottom of the jar upward, so the last color in the list ends up both
/// the highest in the pile *and* the last thing drawn (on top of anything
/// it overlaps), which is what "newest on top" means for a flat 2D pile.
///
/// No physics, no per-bead random jitter beyond alternating round/square —
/// a "simple deterministic packing" per spec, not a bead simulation.
class JarPainter extends CustomPainter {
  const JarPainter({
    required this.beadColors,
    required this.ink,
    required this.shine,
  });

  final List<Color> beadColors;
  final Color ink;
  final Color shine;

  /// Only the most recent beads are drawn — the jar is a keepsake glance,
  /// not a bar chart, and past this many rows the pile just reads as noise
  /// at window scale anyway. The list rows below still show everything.
  static const int maxBeadsDrawn = 64;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // A squat jar: narrow neck up top, wide body below — drawn as plain
    // pixel rects (no rounding), per design-language.md's crisp-corners
    // rule.
    final neckWidth = w * 0.30;
    final neckHeight = h * 0.16;
    final neckRect = Rect.fromLTWH(
      (w - neckWidth) / 2,
      0,
      neckWidth,
      neckHeight,
    );
    final bodyRect = Rect.fromLTWH(
      w * 0.06,
      neckHeight,
      w * 0.88,
      h - neckHeight - h * 0.02,
    );

    final glassFill = Paint()..color = shine.withValues(alpha: 0.12);
    canvas.drawRect(bodyRect, glassFill);
    canvas.drawRect(neckRect, glassFill);

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ink;
    canvas.drawRect(neckRect, outline);
    canvas.drawRect(bodyRect, outline);
    // The lip: a short wider bar where the neck meets the body reads as
    // the jar's rim without needing a curve.
    canvas.drawRect(
      Rect.fromLTWH(
        (w - neckWidth * 1.4) / 2,
        neckHeight - 3,
        neckWidth * 1.4,
        3,
      ),
      Paint()..color = ink,
    );

    // Subtle pastel shine: one thin translucent strip near the inside-left
    // edge of the glass — "subtle", not a highlight sweep.
    canvas.drawRect(
      Rect.fromLTWH(
        bodyRect.left + 6,
        bodyRect.top + 6,
        4,
        bodyRect.height - 12,
      ),
      Paint()..color = shine.withValues(alpha: 0.4),
    );

    if (beadColors.isEmpty) return;

    final shown = beadColors.length > maxBeadsDrawn
        ? beadColors.sublist(beadColors.length - maxBeadsDrawn)
        : beadColors;

    final inner = bodyRect.deflate(5);
    if (inner.width <= 0 || inner.height <= 0) return;

    const desiredBeadPx = 14.0;
    final columns = (inner.width / desiredBeadPx).floor().clamp(3, 12);
    final beadSize = inner.width / columns;

    canvas.save();
    canvas.clipRect(bodyRect.deflate(2));
    for (var i = 0; i < shown.length; i++) {
      final row = i ~/ columns; // row 0 = bottom-most row, filled first
      final col = i % columns;
      final cx = inner.left + col * beadSize + beadSize / 2;
      final cy = inner.bottom - row * beadSize - beadSize / 2;
      if (cy < inner.top) break; // pile overflowed the glass — stop drawing
      final paint = Paint()..color = shown[i];
      final radius = beadSize * 0.36;
      if (i.isEven) {
        canvas.drawCircle(Offset(cx, cy), radius, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(cx, cy),
            width: radius * 1.8,
            height: radius * 1.8,
          ),
          paint,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant JarPainter oldDelegate) =>
      oldDelegate.ink != ink ||
      oldDelegate.shine != shine ||
      !listEquals(oldDelegate.beadColors, beadColors);
}
