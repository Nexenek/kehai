import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'stroke.dart';

/// Pure freehand-drawing state for the doodle canvas: the stroke list plus
/// the currently-picked color/brush width, and undo/clear. Deliberately
/// independent of any gesture-detector/painter widget so the drawing logic
/// itself is unit-testable without pumping a widget tree (per the "test the
/// state object, not raw gestures" note on this feature).
class DoodleCanvasState extends ChangeNotifier {
  DoodleCanvasState({required Color color, required double brushWidth})
    : _color = color,
      _brushWidth = brushWidth;

  Color _color;
  double _brushWidth;
  final List<Stroke> _strokes = <Stroke>[];
  Stroke? _current;

  /// Read-only snapshot — callers can't mutate strokes except through
  /// [startStroke]/[extendStroke]/[undo]/[clear].
  List<Stroke> get strokes => List.unmodifiable(_strokes);
  Color get color => _color;
  double get brushWidth => _brushWidth;
  bool get isEmpty => _strokes.isEmpty;
  bool get canUndo => _strokes.isNotEmpty;

  void setColor(Color color) {
    if (color == _color) return;
    _color = color;
    notifyListeners();
  }

  void setBrushWidth(double width) {
    if (width == _brushWidth) return;
    _brushWidth = width;
    notifyListeners();
  }

  /// Begins a new stroke at [point] using the current color/brush width.
  void startStroke(Offset point) {
    final stroke = Stroke(color: _color, width: _brushWidth)..addPoint(point);
    _strokes.add(stroke);
    _current = stroke;
    notifyListeners();
  }

  /// Appends [point] to the in-progress stroke. No-op if nothing is
  /// in-progress (e.g. a stray drag event after [endStroke]).
  void extendStroke(Offset point) {
    final current = _current;
    if (current == null) return;
    current.addPoint(point);
    notifyListeners();
  }

  void endStroke() {
    _current = null;
  }

  /// Pops the most recent stroke entirely (not point-by-point).
  void undo() {
    if (_strokes.isEmpty) return;
    _strokes.removeLast();
    _current = null;
    notifyListeners();
  }

  void clear() {
    if (_strokes.isEmpty) return;
    _strokes.clear();
    _current = null;
    notifyListeners();
  }
}
