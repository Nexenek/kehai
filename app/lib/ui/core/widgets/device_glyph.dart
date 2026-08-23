import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum DeviceGlyphKind { phone, desktop }

/// Tiny hand-drawn pixel phone/monitor glyph, lit (mint, full opacity) when
/// that device kind has a recent heartbeat, dim otherwise. This is the
/// "device-source indicator" from design-language.md's signature element.
class DeviceGlyph extends StatelessWidget {
  const DeviceGlyph({
    super.key,
    required this.kind,
    required this.lit,
    required this.tooltip,
    this.size = 18,
  });

  final DeviceGlyphKind kind;
  final bool lit;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = lit ? colors.mint : colors.chromeAlt.withValues(alpha: 0.6);
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _DeviceGlyphPainter(kind: kind, color: color, outline: colors.ink),
        ),
      ),
    );
  }
}

class _DeviceGlyphPainter extends CustomPainter {
  _DeviceGlyphPainter({required this.kind, required this.color, required this.outline});

  final DeviceGlyphKind kind;
  final Color color;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    final line = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08;

    if (kind == DeviceGlyphKind.phone) {
      final rect = Rect.fromLTWH(
        size.width * 0.28,
        size.height * 0.06,
        size.width * 0.44,
        size.height * 0.88,
      );
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, line);
      // notch
      canvas.drawRect(
        Rect.fromLTWH(size.width * 0.42, size.height * 0.12, size.width * 0.16, size.height * 0.03),
        Paint()..color = outline,
      );
    } else {
      final screen = Rect.fromLTWH(
        size.width * 0.06,
        size.height * 0.08,
        size.width * 0.88,
        size.height * 0.6,
      );
      canvas.drawRect(screen, fill);
      canvas.drawRect(screen, line);
      // stand
      final stand = Rect.fromLTWH(
        size.width * 0.42,
        size.height * 0.68,
        size.width * 0.16,
        size.height * 0.14,
      );
      canvas.drawRect(stand, fill);
      final base = Rect.fromLTWH(
        size.width * 0.26,
        size.height * 0.84,
        size.width * 0.48,
        size.height * 0.1,
      );
      canvas.drawRect(base, fill);
      canvas.drawRect(base, line);
    }
  }

  @override
  bool shouldRepaint(covariant _DeviceGlyphPainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color || oldDelegate.outline != outline;
  }
}
