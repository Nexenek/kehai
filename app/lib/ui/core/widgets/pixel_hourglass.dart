import 'package:flutter/material.dart';

/// A hand-drawn 7×9 pixel hourglass — the countdowns glyph.
///
/// Drawn rather than typed:/land in whatever emoji font the OS happens
/// to have and come out full-colour and round-cornered, which is exactly the
/// opposite of the crisp nearest-neighbour look design-language.md asks for.
/// A handful of aligned rects always renders sharp, at any scale, on every
/// platform.
class PixelHourglass extends StatelessWidget {
  const PixelHourglass({super.key, required this.color, this.pixel = 2});

  final Color color;

  /// Size of one "pixel" — keep it a whole number so edges stay on-grid.
  final double pixel;

  static const List<String> _rows = <String>[
    '#######',
    '.#####.',
    '..###..',
    '...#...',
    '...#...',
    '..#.#..',
    '.#...#.',
    '#.....#',
    '#######',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _rows.first.length * pixel,
      height: _rows.length * pixel,
      child: CustomPaint(
        painter: _HourglassPainter(color: color, pixel: pixel),
      ),
    );
  }
}

class _HourglassPainter extends CustomPainter {
  const _HourglassPainter({required this.color, required this.pixel});

  final Color color;
  final double pixel;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = 0; y < PixelHourglass._rows.length; y++) {
      final row = PixelHourglass._rows[y];
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
  bool shouldRepaint(_HourglassPainter old) =>
      old.color != color || old.pixel != pixel;
}
