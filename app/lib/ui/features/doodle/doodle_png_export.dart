import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'doodle_canvas_painter.dart';
import 'stroke.dart';

/// Renders [strokes] — drawn against a white [logicalSize]×[logicalSize]
/// square, matching [DoodleCanvas]'s paper — to PNG bytes at [pixelRatio]x
/// resolution. Builds the picture straight from the stroke data via
/// [ui.PictureRecorder] rather than capturing the live widget tree, so it
/// works the same regardless of what's still mounted.
Future<Uint8List> renderStrokesToPng(
  List<Stroke> strokes, {
  double logicalSize = 320,
  double pixelRatio = 2,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, logicalSize, logicalSize),
    Paint()..color = Colors.white,
  );
  DoodleCanvasPainter(strokes).paint(canvas, Size(logicalSize, logicalSize));

  final picture = recorder.endRecording();
  final pixelSize = (logicalSize * pixelRatio).round();
  final image = await picture.toImage(pixelSize, pixelSize);
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw StateError('failed to encode doodle PNG');
    return byteData.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
