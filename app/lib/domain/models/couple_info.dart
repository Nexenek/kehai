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

/// Clean view of the partner's `users` record (name + couple only — the
/// rest of their auth record isn't our business).
@immutable
class Partner {
  const Partner({required this.id, required this.name});

  final String id;
  final String name;
}
