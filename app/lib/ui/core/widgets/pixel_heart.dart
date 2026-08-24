/// A tiny painted pixel heart that beats at a real BPM — smartwatch vitals'
/// "living touch of their partner" (kb/features.md). Same construction as
/// the pet's sprite (`ui/features/pet/pet_painter.dart`): a flat pixel grid
/// painted as grid-snapped rects, nearest-neighbour crisp by never
/// antialiasing an edge, with an ink outline pass so it reads on any
/// background (the mini window can be genuinely transparent).
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 7×7 heart, drawn small on purpose — this rides next to a line of text,
/// never as a centrepiece.
const List<String> heartPixelGrid = [
  '.##.##.',
  '#######',
  '#######',
  '#######',
  '.#####.',
  '..###..',
  '...#...',
];

/// Builds the heart's cell grid (row-major), null where nothing is drawn —
/// split out from the painter so the shape is unit-testable without a
/// canvas, same as `buildPetCells`.
List<Color?> buildHeartCells({required Color fill, required Color outline}) {
  final size = heartPixelGrid.length;
  final cells = List<Color?>.filled(size * size, null);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if (heartPixelGrid[y][x] == '#') cells[y * size + x] = fill;
    }
  }

  // Ink outline: every empty cell touching a filled one.
  final outlined = List<Color?>.of(cells);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if (cells[y * size + x] != null) continue;
      final touching =
          (x > 0 && cells[y * size + x - 1] != null) ||
          (x < size - 1 && cells[y * size + x + 1] != null) ||
          (y > 0 && cells[(y - 1) * size + x] != null) ||
          (y < size - 1 && cells[(y + 1) * size + x] != null);
      if (touching) outlined[y * size + x] = outline;
    }
  }
  return outlined;
}

/// The heartbeat curve for one cycle, `t` in `[0, 1)`: two quick bumps near
/// the start — a bigger "lub", a smaller "dub" — then rest for the back
/// half of the cycle, the way a real systole/diastole reads rather than a
/// single smooth sine pulse. Pure and directly testable.
double heartBeatScale(double t) {
  double bump(double center, double halfWidth, double height) {
    final distance = (t - center).abs();
    if (distance >= halfWidth) return 0;
    return height * (1 - distance / halfWidth);
  }

  final lub = bump(0.10, 0.08, 0.22);
  final dub = bump(0.28, 0.10, 0.12);
  return 1.0 + lub + dub;
}

/// Paints a prebuilt heart cell grid, scaled about its own centre by
/// [beatScale] — the grid is drawn inset within [size] (one cell of margin
/// on every side, at the base scale) so the beat's bump-up never clips
/// against the box it was given.
class PixelHeartPainter extends CustomPainter {
  const PixelHeartPainter({
    required this.fill,
    required this.outline,
    this.beatScale = 1.0,
  });

  final Color fill;
  final Color outline;
  final double beatScale;

  @override
  void paint(Canvas canvas, Size size) {
    final cells = buildHeartCells(fill: fill, outline: outline);
    final gridSize = heartPixelGrid.length;
    // +2 cells of headroom so a ~1.3x beat peak still fits inside `size`.
    final baseCell = size.shortestSide / (gridSize + 2);
    final cell = baseCell * beatScale;
    final dx = (size.width - cell * gridSize) / 2;
    final dy = (size.height - cell * gridSize) / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final color = cells[y * gridSize + x];
        if (color == null) continue;
        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(dx + x * cell, dy + y * cell, cell + 0.5, cell + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant PixelHeartPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.outline != outline ||
      oldDelegate.beatScale != beatScale;
}

/// A small beating pixel heart — the display half of the smartwatch-vitals
/// wave. Beats once every `60000 / bpm` ms, matching [heartBeatScale]'s
/// lub-dub curve to the partner's real heart rate. Callers gate presence
/// entirely on freshness themselves (`HeartRateSample.isFresh`) — this
/// widget just draws whatever [bpm] it's handed and assumes it's current.
///
/// Respects the OS reduced-motion setting (design-language.md's "Motion":
/// "Respect reduced-motion OS setting: swap animations for instant states")
/// by holding a single still frame instead of pulsing — read directly off
/// [MediaQuery], the same way `PetSpriteView` does, so callers don't have to
/// thread it through themselves.
class PixelHeart extends StatefulWidget {
  const PixelHeart({super.key, required this.bpm, this.size = 14});

  final int bpm;
  final double size;

  @override
  State<PixelHeart> createState() => _PixelHeartState();
}

class _PixelHeartState extends State<PixelHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _periodFor(widget.bpm),
  );

  static Duration _periodFor(int bpm) =>
      Duration(milliseconds: (60000 / bpm).round());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncController({required bool still}) {
    if (still) {
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 0;
      return;
    }
    final period = _periodFor(widget.bpm);
    if (_controller.duration != period || !_controller.isAnimating) {
      _controller
        ..duration = period
        ..repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final still = MediaQuery.disableAnimationsOf(context);
    _syncController(still: still);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: PixelHeartPainter(
          fill: colors.accent,
          outline: colors.ink,
          beatScale: still ? 1.0 : heartBeatScale(_controller.value),
        ),
      ),
    );
  }
}
