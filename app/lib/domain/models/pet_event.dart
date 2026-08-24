import 'package:flutter/foundation.dart';

/// One row from the shared pet's append-only care log
/// (`pet_events`, server/migrations/6_pet.go) — who did what, and when.
/// The log itself is create-only (no update/delete rules), so a [PetEvent]
/// once read never changes underneath you.
@immutable
class PetEvent {
  const PetEvent({
    required this.id,
    required this.coupleId,
    required this.userId,
    required this.type,
    required this.created,
  });

  final String id;
  final String coupleId;
  final String userId;

  /// One of the server's `pet_events.type` select values — currently
  /// `feed`, `pet`, `dress`, `rename` — kept as a plain string rather than
  /// an enum so a value from a newer/older server just falls back to a
  /// generic line instead of throwing (see the copy table in
  /// `ui/features/pet/pet_history_dialog.dart`).
  final String type;

  final DateTime created;
}
