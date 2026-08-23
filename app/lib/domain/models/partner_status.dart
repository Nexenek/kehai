import 'package:flutter/foundation.dart';

/// Where a status update / heartbeat originated. Mirrors the `kind` values
/// accepted by POST /api/heartbeat and the `source_kind` field on
/// `statuses`.
enum SourceKind {
  phone,
  desktop,
  tablet,
  portal;

  static SourceKind fromString(String? value) {
    return SourceKind.values.firstWhere(
      (k) => k.name == value,
      orElse: () => SourceKind.desktop,
    );
  }
}

/// Clean domain representation of a `statuses` record — one per user,
/// upserted on every mood change.
@immutable
class PartnerStatus {
  const PartnerStatus({
    required this.userId,
    required this.moodId,
    required this.note,
    required this.sourceKind,
    required this.updated,
  });

  final String userId;
  final String moodId;
  final String note;
  final SourceKind sourceKind;
  final DateTime updated;
}
