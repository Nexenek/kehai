import 'package:flutter/material.dart';

/// A chunky hand-drawn pixel heart, used as a map pin.
///
/// Drawn as rects rather than typed as ♥ or shipped as a PNG, for the same
/// reason [PixelHourglass] is: emoji hearts arrive in whatever font the OS
/// has (full-colour, round-cornered, differently sized per platform), and
/// design-language.md wants crisp nearest-neighbour edges at every scale.
/// No image assets needed, and it tints to any accent colour.
///
/// The heart already tapers to a single pixel at the bottom, so that point
/// *is* the pin tip — place the marker with `Alignment.topCenter` and the
/// tip lands exactly on the coordinate.
class PixelHeartPin extends StatelessWidget {
  const PixelHeartPin({
    super.key,
    required this.color,
    required this.outline,
    this.pixel = 3,
    this.semanticLabel,
  });

  /// Fill colour — the partner accents (`accent` for me, `accent2` for
  /// them) so the two pins are told apart at a glance. Never *only* by
  /// colour, though: each pin carries its own name chip (a11y floor).
  final Color color;

  /// The 1-pixel silhouette border, so a pastel pin stays visible over pale
  /// map tiles. `ink` in practice.
  final Color outline;

  /// Size of one "pixel" — keep it a whole number so edges stay on-grid.
  final double pixel;

  final String? semanticLabel;

  static const List<String> _rows = <String>[
    '.##.##.',
    '#######',
    '#######',
    '.#####.',
    '..###..',
    '...#...',
  ];

  /// The silhouette plus the one-cell outline ring around it.
  static const int _gridWidth = 7 + 2;
  static const int _gridHeight = 6 + 2;

  static double widthFor(double pixel) => _gridWidth * pixel;
  static double heightFor(double pixel) => _gridHeight * pixel;

  @override
  Widget build(BuildContext context) {
    final pin = SizedBox(
      width: widthFor(pixel),
      height: heightFor(pixel),
      child: CustomPaint(
        painter: _HeartPinPainter(
          color: color,
          outline: outline,
          pixel: pixel,
        ),
      ),
    );
    final label = semanticLabel;
    return label == null ? pin : Semantics(label: label, child: pin);
  }
}

class _HeartPinPainter extends CustomPainter {
  const _HeartPinPainter({
    required this.color,
    required this.outline,
    required this.pixel,
  });

  final Color color;
  final Color outline;
  final double pixel;

  static bool _filled(int x, int y) {
    if (y < 0 || y >= PixelHeartPin._rows.length) return false;
    final row = PixelHeartPin._rows[y];
    if (x < 0 || x >= row.length) return false;
    return row[x] == '#';
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()..color = color;
    final outlinePaint = Paint()..color = outline;

    // The heart sits inset by one cell; every empty cell orthogonally
    // touching it becomes outline, which gives a symmetric 1px border
    // without hand-drawing a second matrix.
    for (var gy = 0; gy < PixelHeartPin._gridHeight; gy++) {
      for (var gx = 0; gx < PixelHeartPin._gridWidth; gx++) {
        final x = gx - 1;
        final y = gy - 1;
        final rect = Rect.fromLTWH(gx * pixel, gy * pixel, pixel, pixel);
        if (_filled(x, y)) {
          canvas.drawRect(rect, fillPaint);
          continue;
        }
        final touches =
            _filled(x - 1, y) ||
            _filled(x + 1, y) ||
            _filled(x, y - 1) ||
            _filled(x, y + 1);
        if (touches) canvas.drawRect(rect, outlinePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_HeartPinPainter old) =>
      old.color != color || old.outline != outline || old.pixel != pixel;
}
