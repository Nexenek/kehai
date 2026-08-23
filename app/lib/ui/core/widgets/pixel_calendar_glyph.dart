import 'package:flutter/material.dart';

/// A hand-drawn 9×9 pixel calendar page (two binder rings, a header bar, a
/// row of date-grid dashes, and a small heart) — the tray glyph for the
/// calendar section.
///
/// Same reasoning as [PixelHourglass]/[PixelMapPin]: a typed 📅/🗓 glyph
/// lands in whatever emoji font the OS ships and comes out full-colour and
/// round-cornered, the opposite of the crisp nearest-neighbour look
/// design-language.md asks for. A handful of on-grid rects always renders
/// sharp. Deliberately not the plain '▦' text glyph the board section
/// already uses — the tray would otherwise show two identical tiles.
class PixelCalendarGlyph extends StatelessWidget {
  const PixelCalendarGlyph({super.key, required this.color, this.pixel = 2});

  final Color color;

  /// Size of one "pixel" — keep it a whole number so edges stay on-grid.
  final double pixel;

  static const List<String> _rows = <String>[
    '.##...##.',
    '#########',
    '#.......#',
    '#.#.#.#.#',
    '#.......#',
    '#..#.#..#',
    '#.#####.#',
    '#..###..#',
    '#########',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _rows.first.length * pixel,
      height: _rows.length * pixel,
      child: CustomPaint(
        painter: _PixelCalendarGlyphPainter(color: color, pixel: pixel),
      ),
    );
  }
}

class _PixelCalendarGlyphPainter extends CustomPainter {
  const _PixelCalendarGlyphPainter({required this.color, required this.pixel});

  final Color color;
  final double pixel;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = 0; y < PixelCalendarGlyph._rows.length; y++) {
      final row = PixelCalendarGlyph._rows[y];
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
  bool shouldRepaint(_PixelCalendarGlyphPainter old) =>
      old.color != color || old.pixel != pixel;
}
