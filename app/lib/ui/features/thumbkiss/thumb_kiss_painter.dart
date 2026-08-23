import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Paints the thumb-kiss touch area: my fingertip and the partner's as
/// soft glowing blobs, plus the "met" warm flash + sparkle burst. Pure
/// paint logic over already-resolved values (no PocketBase/controller
/// access) so [ThumbKissWindow] stays the only place that has to know
/// about the view model.
class ThumbKissPainter extends CustomPainter {
  const ThumbKissPainter({
    required this.myTouch,
    required this.partnerTouch,
    required this.isMet,
    required this.myColor,
    required this.partnerColor,
    required this.flashColor,
    required this.sparklePhase,
  });

  /// Normalized (0..1) position, or null while not present.
  final Offset? myTouch;
  final Offset? partnerTouch;

  final bool isMet;
  final Color myColor;
  final Color partnerColor;
  final Color flashColor;

  /// 0..1 progress of the current sparkle-burst cycle; 0 when not met.
  final double sparklePhase;

  @override
  void paint(Canvas canvas, Size size) {
    if (isMet) {
      final flashAlpha = (0.28 * (1 - sparklePhase)).clamp(0.0, 0.28);
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = flashColor.withValues(alpha: flashAlpha),
      );
    }

    final mine = myTouch;
    final theirs = partnerTouch;
    if (theirs != null) _drawBlob(canvas, size, theirs, partnerColor);
    if (mine != null) _drawBlob(canvas, size, mine, myColor);

    if (isMet && mine != null && theirs != null) {
      final midpoint = Offset(
        (mine.dx + theirs.dx) / 2 * size.width,
        (mine.dy + theirs.dy) / 2 * size.height,
      );
      _drawSparkles(canvas, midpoint, size, sparklePhase);
    }
  }

  void _drawBlob(Canvas canvas, Size size, Offset normalized, Color color) {
    final center = Offset(
      normalized.dx * size.width,
      normalized.dy * size.height,
    );
    final glowRadius = math.min(size.width, size.height) * 0.14;

    canvas.drawCircle(
      center,
      glowRadius,
      Paint()
        ..color = color.withValues(alpha: 0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawCircle(
      center,
      glowRadius * 0.5,
      Paint()..color = color.withValues(alpha: 0.9),
    );
  }

  void _drawSparkles(Canvas canvas, Offset center, Size size, double phase) {
    const count = 8;
    final radius = math.min(size.width, size.height) * (0.05 + phase * 0.22);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: (1 - phase).clamp(0.0, 1.0));
    for (var i = 0; i < count; i++) {
      final angle = (2 * math.pi / count) * i;
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(point, 2.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ThumbKissPainter oldDelegate) =>
      oldDelegate.myTouch != myTouch ||
      oldDelegate.partnerTouch != partnerTouch ||
      oldDelegate.isMet != isMet ||
      oldDelegate.sparklePhase != sparklePhase;
}
