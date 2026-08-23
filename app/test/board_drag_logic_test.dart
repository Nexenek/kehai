import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/ui/features/board/board_drag_logic.dart';

void main() {
  group('clampBoardCoordinate / clampBoardPosition', () {
    test('leaves in-range values untouched', () {
      expect(clampBoardCoordinate(0.4), 0.4);
      expect(clampBoardCoordinate(0), 0);
      expect(clampBoardCoordinate(1), 1);
    });

    test('clamps below 0 up to 0', () {
      expect(clampBoardCoordinate(-0.3), 0);
    });

    test('clamps above 1 down to 1', () {
      expect(clampBoardCoordinate(1.7), 1);
    });

    test('clamps each axis of a position independently', () {
      final clamped = clampBoardPosition(const Offset(-0.2, 1.5));
      expect(clamped.dx, 0);
      expect(clamped.dy, 1);
    });
  });

  group('dragBoardPosition', () {
    test('converts a pixel delta into a proportional normalized delta', () {
      final result = dragBoardPosition(
        start: const Offset(0.5, 0.5),
        pixelDelta: const Offset(20, -10),
        boardSize: const Size(200, 100),
      );
      // 20px of a 200px-wide board = 0.1 of the normalized width.
      expect(result.dx, closeTo(0.6, 1e-9));
      // -10px of a 100px-tall board = -0.1 of the normalized height.
      expect(result.dy, closeTo(0.4, 1e-9));
    });

    test('clamps the result to the board edges', () {
      final result = dragBoardPosition(
        start: const Offset(0.95, 0.05),
        pixelDelta: const Offset(1000, -1000),
        boardSize: const Size(200, 200),
      );
      expect(result.dx, 1);
      expect(result.dy, 0);
    });

    test('a degenerate board size leaves the (clamped) start untouched', () {
      final result = dragBoardPosition(
        start: const Offset(1.5, 0.3),
        pixelDelta: const Offset(50, 50),
        boardSize: Size.zero,
      );
      // Never divides by zero — and still clamps the start itself.
      expect(result.dx, 1);
      expect(result.dy, closeTo(0.3, 1e-9));
    });
  });

  group('clampBoardRotation', () {
    test('leaves in-range tilts untouched', () {
      expect(clampBoardRotation(10), 10);
    });

    test('clamps to the server\'s -30..30 range', () {
      expect(clampBoardRotation(-45), -30);
      expect(clampBoardRotation(45), 30);
    });
  });

  group('nextBoardZ', () {
    test('an empty board starts at 1', () {
      expect(nextBoardZ(const []), 1);
    });

    test('bumps one past the current highest z', () {
      expect(nextBoardZ([1, 5, 3]), 6);
    });

    test('handles a single existing item', () {
      expect(nextBoardZ([2]), 3);
    });
  });

  group('randomBoardTilt', () {
    test('always stays within the requested range', () {
      final random = Random(7);
      for (var i = 0; i < 200; i++) {
        final tilt = randomBoardTilt(random, range: 8);
        expect(tilt, inInclusiveRange(-8.0, 8.0));
      }
    });

    test('a zero seed range always returns zero', () {
      final random = Random(1);
      expect(randomBoardTilt(random, range: 0), 0);
    });
  });

  group('shouldPersistBoardDrag', () {
    test('only the end phase persists', () {
      expect(shouldPersistBoardDrag(BoardDragPhase.start), isFalse);
      expect(shouldPersistBoardDrag(BoardDragPhase.update), isFalse);
      expect(shouldPersistBoardDrag(BoardDragPhase.cancel), isFalse);
      expect(shouldPersistBoardDrag(BoardDragPhase.end), isTrue);
    });

    test('a long drag never persists mid-gesture, only once at the end', () {
      // Simulate a drag with many intermediate updates — only the final
      // `end` event should ever be counted as a persist.
      final phases = [
        BoardDragPhase.start,
        ...List.filled(50, BoardDragPhase.update),
        BoardDragPhase.end,
      ];
      final persistCount = phases.where(shouldPersistBoardDrag).length;
      expect(persistCount, 1);
    });
  });
}
