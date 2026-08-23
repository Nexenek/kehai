import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/ui/features/doodle/doodle_canvas_state.dart';

void main() {
  DoodleCanvasState makeState() =>
      DoodleCanvasState(color: const Color(0xFF362D3B), brushWidth: 4);

  group('DoodleCanvasState — drawing', () {
    test('starts empty', () {
      final state = makeState();
      expect(state.isEmpty, isTrue);
      expect(state.canUndo, isFalse);
      expect(state.strokes, isEmpty);
    });

    test('startStroke begins a new stroke with the current color/width', () {
      final state = makeState()
        ..setColor(const Color(0xFFB24D89))
        ..setBrushWidth(10)
        ..startStroke(const Offset(1, 1));

      expect(state.strokes, hasLength(1));
      expect(state.strokes.single.color, const Color(0xFFB24D89));
      expect(state.strokes.single.width, 10);
      expect(state.strokes.single.points, [const Offset(1, 1)]);
      expect(state.isEmpty, isFalse);
    });

    test('extendStroke appends points to the in-progress stroke', () {
      final state = makeState()
        ..startStroke(const Offset(0, 0))
        ..extendStroke(const Offset(5, 5))
        ..extendStroke(const Offset(10, 10));

      expect(state.strokes, hasLength(1));
      expect(state.strokes.single.points, [
        const Offset(0, 0),
        const Offset(5, 5),
        const Offset(10, 10),
      ]);
    });

    test('extendStroke without a prior startStroke is a no-op', () {
      final state = makeState()..extendStroke(const Offset(5, 5));
      expect(state.strokes, isEmpty);
    });

    test('endStroke then extendStroke does not resume the old stroke', () {
      final state = makeState()
        ..startStroke(const Offset(0, 0))
        ..endStroke()
        ..extendStroke(const Offset(9, 9));

      expect(state.strokes.single.points, [const Offset(0, 0)]);
    });

    test('a second startStroke begins an independent second stroke', () {
      final state = makeState()
        ..startStroke(const Offset(0, 0))
        ..extendStroke(const Offset(1, 1))
        ..endStroke()
        ..startStroke(const Offset(9, 9));

      expect(state.strokes, hasLength(2));
      expect(state.strokes.first.points, [
        const Offset(0, 0),
        const Offset(1, 1),
      ]);
      expect(state.strokes.last.points, [const Offset(9, 9)]);
    });
  });

  group('DoodleCanvasState — undo/clear', () {
    test('undo pops only the most recent stroke', () {
      final state = makeState()
        ..startStroke(const Offset(0, 0))
        ..endStroke()
        ..startStroke(const Offset(1, 1))
        ..endStroke();

      expect(state.strokes, hasLength(2));
      state.undo();
      expect(state.strokes, hasLength(1));
      expect(state.strokes.single.points, [const Offset(0, 0)]);
    });

    test('undo on an empty canvas is a no-op', () {
      final state = makeState();
      state.undo();
      expect(state.strokes, isEmpty);
      expect(state.canUndo, isFalse);
    });

    test('undo mid-stroke removes the whole in-progress stroke', () {
      final state = makeState()
        ..startStroke(const Offset(0, 0))
        ..extendStroke(const Offset(1, 1));

      state.undo();
      expect(state.strokes, isEmpty);
      // A subsequent extend must not resurrect the removed stroke.
      state.extendStroke(const Offset(2, 2));
      expect(state.strokes, isEmpty);
    });

    test('clear removes every stroke at once', () {
      final state = makeState()
        ..startStroke(const Offset(0, 0))
        ..endStroke()
        ..startStroke(const Offset(1, 1))
        ..endStroke();

      state.clear();
      expect(state.strokes, isEmpty);
      expect(state.canUndo, isFalse);
    });

    test('notifies listeners on undo/clear', () {
      final state = makeState()..startStroke(const Offset(0, 0));
      var notifications = 0;
      state.addListener(() => notifications++);

      state.undo();
      expect(notifications, 1);

      // No-op clear on an already-empty canvas shouldn't notify again.
      state.clear();
      expect(notifications, 1);
    });
  });

  group('DoodleCanvasState — tool state', () {
    test('setColor/setBrushWidth update subsequent strokes, not past ones', () {
      final state = makeState()
        ..startStroke(const Offset(0, 0))
        ..endStroke();

      state
        ..setColor(const Color(0xFFBCD7F0))
        ..setBrushWidth(10)
        ..startStroke(const Offset(1, 1));

      expect(state.strokes.first.color, const Color(0xFF362D3B));
      expect(state.strokes.last.color, const Color(0xFFBCD7F0));
      expect(state.strokes.last.width, 10);
    });
  });
}
