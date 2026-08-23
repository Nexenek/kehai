import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/doodle/doodle_canvas.dart';
import 'package:couples_app/ui/features/doodle/doodle_canvas_state.dart';

void main() {
  testWidgets(
    'dragging across the canvas registers a stroke, and undo removes it',
    (tester) async {
      final state = DoodleCanvasState(color: Colors.black, brushWidth: 4);
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(child: DoodleCanvas(state: state)),
          ),
        ),
      );

      expect(state.strokes, isEmpty);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(DoodleCanvas)),
      );
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(20, 0));
      await gesture.up();
      await tester.pump();

      expect(state.strokes, hasLength(1));
      expect(state.strokes.single.points.length, greaterThan(1));

      state.undo();
      await tester.pump();

      expect(state.strokes, isEmpty);
    },
  );

  testWidgets(
    'a plain tap (no drag) still registers as a single-point stroke',
    (tester) async {
      final state = DoodleCanvasState(color: Colors.black, brushWidth: 4);
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(child: DoodleCanvas(state: state)),
          ),
        ),
      );

      await tester.tapAt(tester.getCenter(find.byType(DoodleCanvas)));
      await tester.pump();

      expect(state.strokes, hasLength(1));
      expect(state.strokes.single.points, hasLength(1));
    },
  );
}
