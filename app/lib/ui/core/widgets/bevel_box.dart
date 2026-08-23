import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum BevelStyle { raised, sunken }

/// A flat-color box with a hard 2px Win95-style bevel border — light on the
/// "lit" edges, dark on the "shadow" edges (swapped for [BevelStyle.sunken]).
/// No rounding, no Material elevation: this is the building block every
/// pixel-chrome widget (RetroWindow, PixelButton) is made of.
class BevelBox extends StatelessWidget {
  const BevelBox({
    super.key,
    required this.child,
    this.color,
    this.style = BevelStyle.raised,
    this.thickness = 2,
    this.padding,
  });

  final Widget child;
  final Color? color;
  final BevelStyle style;
  final double thickness;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final light = style == BevelStyle.raised
        ? colors.bevelLight
        : colors.bevelDark;
    final dark = style == BevelStyle.raised
        ? colors.bevelDark
        : colors.bevelLight;
    final fill = color ?? colors.surface;

    return CustomPaint(
      painter: _BevelPainter(
        light: light,
        dark: dark,
        thickness: thickness,
        fill: fill,
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.all(thickness),
        child: child,
      ),
    );
  }
}

class _BevelPainter extends CustomPainter {
  _BevelPainter({
    required this.light,
    required this.dark,
    required this.thickness,
    required this.fill,
  });

  final Color light;
  final Color dark;
  final double thickness;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = fill);

    final t = thickness;
    final strokePaint = Paint()..style = PaintingStyle.fill;

    // Top + left = light edge.
    strokePaint.color = light;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, t), strokePaint);
    canvas.drawRect(Rect.fromLTWH(0, 0, t, size.height), strokePaint);

    // Bottom + right = dark edge.
    strokePaint.color = dark;
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - t, size.width, t),
      strokePaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width - t, 0, t, size.height),
      strokePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BevelPainter oldDelegate) {
    return oldDelegate.light != light ||
        oldDelegate.dark != dark ||
        oldDelegate.thickness != thickness ||
        oldDelegate.fill != fill;
  }
}
