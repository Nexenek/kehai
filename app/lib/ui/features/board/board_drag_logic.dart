import 'dart:math';
import 'dart:ui' show Offset, Size;

/// Pure logic behind the shared board's drag-to-arrange interaction
/// (kb/features.md "Shared board"; kb/design-language.md's desktop-metaphor
/// "power-user wink: they genuinely rearrange") — position clamping, the
/// bring-to-front z-assignment, the create-time hand-placed tilt, and the
/// throttle-on-drag-end decision. No Flutter widgets, no PocketBase:
/// plain-value unit testable, [BoardViewModel] is the only caller.

/// Clamps a normalized board coordinate into the visible board (0..1).
double clampBoardCoordinate(double v) => v.clamp(0.0, 1.0);

/// Clamps a normalized board position into the visible board on both axes.
Offset clampBoardPosition(Offset position) => Offset(
  clampBoardCoordinate(position.dx),
  clampBoardCoordinate(position.dy),
);

/// Converts a drag's pixel delta (since the drag started, or since the last
/// update — either way, added onto [start]) into the item's new
/// *normalized* position, clamped to the board. [boardSize] is the board
/// surface's own rendered size, so dragging tracks 1:1 under the
/// finger/cursor regardless of the item's own size or the board's aspect
/// ratio. A degenerate (zero or negative) [boardSize] leaves the position
/// unchanged rather than dividing by zero.
Offset dragBoardPosition({
  required Offset start,
  required Offset pixelDelta,
  required Size boardSize,
}) {
  if (boardSize.width <= 0 || boardSize.height <= 0) {
    return clampBoardPosition(start);
  }
  return clampBoardPosition(
    start +
        Offset(pixelDelta.dx / boardSize.width, pixelDelta.dy / boardSize.height),
  );
}

/// Clamps a hand-placed tilt into the server's allowed range.
double clampBoardRotation(double degrees) => degrees.clamp(-30.0, 30.0);

/// Bring-to-front: the z to give an item just grabbed or freshly created,
/// so it draws above everything else already on the board. An empty board
/// starts at 1 (not 0) so a single item always reads as "on top of the felt
/// backing", not "tied with nothing".
double nextBoardZ(Iterable<double> existingZ) {
  double? max;
  for (final z in existingZ) {
    if (max == null || z > max) max = z;
  }
  return (max ?? 0) + 1;
}

/// Random tilt range applied on create for the hand-placed feel — well
/// inside the server's -30..30 range, so it's deliberately much smaller
/// than what a partner could later drag an item to.
const boardCreateTiltRange = 8.0;

/// A small random tilt for a freshly-placed item. [random] is injected so
/// this stays a pure, seedable function under test.
double randomBoardTilt(Random random, {double range = boardCreateTiltRange}) =>
    (random.nextDouble() * 2 - 1) * range;

/// Drag lifecycle phases for a single board item.
enum BoardDragPhase { start, update, end, cancel }

/// Does a drag event at [phase] persist the item's position to the server?
/// Only `end` does — `start` just bumps z locally and `update` just moves
/// the item locally, so a fast or long drag never spams the repository
/// with a write per frame (brief: "throttled — don't spam saves mid-drag;
/// save on drag end"). A `cancel`led drag (e.g. interrupted mid-gesture)
/// never persists either — whatever the item's last-saved position was
/// stands.
bool shouldPersistBoardDrag(BoardDragPhase phase) =>
    phase == BoardDragPhase.end;
