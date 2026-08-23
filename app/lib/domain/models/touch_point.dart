import 'dart:ui';

import 'package:flutter/foundation.dart';

/// One `touches` record — a single fingertip position posted while a
/// thumb-kiss press is active (kb/features.md "Thumb-kiss"). Ephemeral by
/// design: the server purges these after an hour, and the UI itself only
/// ever cares about the last second or two (see `thumb_kiss_logic.dart`'s
/// `touchFreshWindow`).
@immutable
class TouchPoint {
  const TouchPoint({
    required this.userId,
    required this.x,
    required this.y,
    required this.at,
  });

  final String userId;

  /// Normalized 0..1 position within the touch area.
  final double x;
  final double y;

  /// When the server recorded this point (`created`, localized).
  final DateTime at;

  Offset get offset => Offset(x, y);

  @override
  bool operator ==(Object other) =>
      other is TouchPoint &&
      other.userId == userId &&
      other.x == x &&
      other.y == y &&
      other.at == at;

  @override
  int get hashCode => Object.hash(userId, x, y, at);

  @override
  String toString() => 'TouchPoint($userId, $x, $y, at: $at)';
}
