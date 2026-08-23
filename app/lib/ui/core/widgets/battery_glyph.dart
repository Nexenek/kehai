import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Purely a drawing switch — not the domain's [BatteryGlyphKind] (which
/// also has a `none`); see `resolvePhoneBattery` in
/// `domain/models/ambient_line.dart` for the precedence that decides
/// whether this widget is shown at all.
enum BatteryGlyphVisual { low, charging }

/// Tiny hand-drawn pixel battery glyph — design-language.md's signature
/// element calls for "a tiny low-battery pixel glyph" plus a "charging
/// bolt", shown next to the device-source indicator on the partner card
/// when their phone is low (≤20%, not charging) or actively charging.
class BatteryGlyph extends StatelessWidget {
  const BatteryGlyph({
    super.key,
    required this.kind,
    required this.tooltip,
    this.size = 16,
  });

  final BatteryGlyphVisual kind;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fill = kind == BatteryGlyphVisual.low ? colors.warn : colors.mint;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _BatteryGlyphPainter(
            kind: kind,
            fill: fill,
            outline: colors.ink,
          ),
        ),
      ),
    );
  }
}

class _BatteryGlyphPainter extends CustomPainter {
  _BatteryGlyphPainter({
    required this.kind,
    required this.fill,
    required this.outline,
  });

  final BatteryGlyphVisual kind;
  final Color fill;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08;

    // Battery body (sideways, terminal nub on the right) — same blocky
    // rect style as DeviceGlyph, nearest-sampling per design-language.md.
    final body = Rect.fromLTWH(
      size.width * 0.04,
      size.height * 0.22,
      size.width * 0.76,
      size.height * 0.56,
    );
    canvas.drawRect(body, line);
    final terminal = Rect.fromLTWH(
      size.width * 0.8,
      size.height * 0.38,
      size.width * 0.14,
      size.height * 0.24,
    );
    canvas.drawRect(terminal, Paint()..color = outline);

    if (kind == BatteryGlyphVisual.low) {
      final level = Rect.fromLTWH(
        size.width * 0.09,
        size.height * 0.28,
        size.width * 0.16,
        size.height * 0.44,
      );
      canvas.drawRect(level, Paint()..color = fill);
    } else {
      final level = Rect.fromLTWH(
        size.width * 0.09,
        size.height * 0.28,
        size.width * 0.62,
        size.height * 0.44,
      );
      canvas.drawRect(level, Paint()..color = fill.withValues(alpha: 0.55));
      // bolt, drawn in outline ink so it reads against the mint fill
      final bolt = Path()
        ..moveTo(size.width * 0.46, size.height * 0.16)
        ..lineTo(size.width * 0.28, size.height * 0.54)
        ..lineTo(size.width * 0.42, size.height * 0.54)
        ..lineTo(size.width * 0.34, size.height * 0.86)
        ..lineTo(size.width * 0.58, size.height * 0.44)
        ..lineTo(size.width * 0.44, size.height * 0.44)
        ..close();
      canvas.drawPath(bolt, Paint()..color = outline);
    }
  }

  @override
  bool shouldRepaint(covariant _BatteryGlyphPainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.fill != fill ||
      oldDelegate.outline != outline;
}
