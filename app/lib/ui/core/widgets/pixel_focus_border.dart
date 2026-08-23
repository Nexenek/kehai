import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Wraps [child] with a dotted pixel outline when it has keyboard focus —
/// "visible keyboard focus (dotted pixel outline, very Win95)" per the
/// accessibility floor in design-language.md. Wrap any Focus-able control
/// (buttons, fields) that doesn't already draw its own focus ring.
class PixelFocusBorder extends StatelessWidget {
  const PixelFocusBorder({super.key, required this.focused, required this.child});

  final bool focused;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!focused) return child;
    return CustomPaint(
      foregroundPainter: _DottedBorderPainter(color: context.colors.accent),
      child: child,
    );
  }
}

class _DottedBorderPainter extends CustomPainter {
  _DottedBorderPainter({required this.color});

  final Color color;
  static const double dash = 3;
  static const double gap = 2;
  static const double inset = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final rect = Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2);

    void dashLine(Offset start, Offset end) {
      final total = (end - start).distance;
      final dir = (end - start) / total;
      var covered = 0.0;
      while (covered < total) {
        final segStart = start + dir * covered;
        final segLen = (covered + dash) > total ? total - covered : dash;
        final segEnd = start + dir * (covered + segLen);
        canvas.drawLine(segStart, segEnd, paint..strokeWidth = 2);
        covered += dash + gap;
      }
    }

    dashLine(rect.topLeft, rect.topRight);
    dashLine(rect.topRight, rect.bottomRight);
    dashLine(rect.bottomRight, rect.bottomLeft);
    dashLine(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant _DottedBorderPainter oldDelegate) => oldDelegate.color != color;
}
