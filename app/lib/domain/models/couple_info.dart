import 'package:flutter/foundation.dart';

/// Result of POST /api/couple/create — held onto locally just long enough
/// to show the invite code; the couple id also lives on the user's PB
/// record after that.
@immutable
class CoupleInfo {
  const CoupleInfo({
    required this.coupleId,
    required this.name,
    required this.inviteCode,
  });

  final String coupleId;
  final String name;
  final String inviteCode;

  factory CoupleInfo.fromJson(Map<String, dynamic> json) => CoupleInfo(
    coupleId: json['couple_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    inviteCode: json['invite_code'] as String? ?? '',
  );
}

/// Clean view of the partner's `users` record (name, and the one field
/// they share with us on purpose — the rest of their auth record isn't our
/// business).
@immutable
class Partner {
  const Partner({required this.id, required this.name, this.ghostUntil});

  final String id;
  final String name;

  /// Their `users.ghost_until` — the honest location pause (kb/contracts.md
  /// "Ghost mode"). Deliberately visible to us: the whole design is that a
  /// paused location says so instead of quietly going stale. Null means
  /// they're not paused. Read it through [resolveGhostState].
  final DateTime? ghostUntil;

  Partner copyWith({DateTime? ghostUntil, bool clearGhostUntil = false}) =>
      Partner(
        id: id,
        name: name,
        ghostUntil: clearGhostUntil ? null : (ghostUntil ?? this.ghostUntil),
      );
}
