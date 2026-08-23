import 'dart:ui';

/// One freehand pen-down-to-pen-up stroke: an ordered list of points in the
/// canvas's local coordinate space, plus the color/width it was drawn with.
/// Pure data — no Flutter widget/gesture dependency — so it's trivial to
/// unit-test alongside [DoodleCanvasState].
class Stroke {
  Stroke({required this.color, required this.width, List<Offset>? points})
    : points = points ?? <Offset>[];

  final Color color;
  final double width;
  final List<Offset> points;

  void addPoint(Offset point) => points.add(point);
}
