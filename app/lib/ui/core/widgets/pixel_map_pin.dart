import 'package:flutter/material.dart';

/// A hand-drawn 7×8 pixel map pin — the tray glyph for the "where we are"
/// section.
///
/// Same reasoning as [PixelHourglass]:/📍 land in whatever emoji font the
/// OS happens to ship, full-colour and round-cornered, which is the
/// opposite of the crisp nearest-neighbour look design-language.md asks
/// for. A handful of on-grid rects always renders sharp.
class PixelMapPin extends StatelessWidget {
  const PixelMapPin({super.key, required this.color, this.pixel = 2});

  final Color color;

  /// Size of one "pixel" — keep it a whole number so edges stay on-grid.
  final double pixel;

  static const List<String> _rows = <String>[
    '..###..',
    '.#####.',
    '##...##',
    '##...##',
    '##...##',
    '.#####.',
    '..###..',
    '...#...',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _rows.first.length * pixel,
      height: _rows.length * pixel,
      child: CustomPaint(painter: _MapPinPainter(color: color, pixel: pixel)),
    );
  }
}

class _MapPinPainter extends CustomPainter {
  const _MapPinPainter({required this.color, required this.pixel});

  final Color color;
  final double pixel;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = 0; y < PixelMapPin._rows.length; y++) {
      final row = PixelMapPin._rows[y];
      for (var x = 0; x < row.length; x++) {
        if (row[x] != '#') continue;
        canvas.drawRect(
          Rect.fromLTWH(x * pixel, y * pixel, pixel, pixel),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MapPinPainter old) =>
      old.color != color || old.pixel != pixel;
}
