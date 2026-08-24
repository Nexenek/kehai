import 'package:flutter/foundation.dart';

/// A single `mood_entries` bead — one row per mood *change* (see
/// server/moodjar.go: note-only edits don't append a new one). Read-only
/// from the client's side: entries are written by a server hook and purged
/// after 90 days (server/migrations/15_moodjar.go), so this model has no
/// `copyWith`/mutation story — it's a keepsake snapshot, not something the
/// app edits.
@immutable
class MoodEntry {
  const MoodEntry({
    required this.id,
    required this.coupleId,
    required this.userId,
    required this.mood,
    required this.note,
    required this.created,
  });

  final String id;
  final String coupleId;

  /// Who was feeling it. Compare against `AuthRepository.currentUserId` to
  /// tell "you" from "partner" — the jar has exactly two possible authors,
  /// same as every other shared-content window.
  final String userId;

  /// [MoodCatalog] id string — an older/foreign value is possible (a future
  /// mood added after this client shipped) and must never crash a render;
  /// see `MoodCatalog.byId`'s doc comment and the jar window's fallback.
  final String mood;

  /// Whatever note was set on the status at the moment the mood changed —
  /// may be empty.
  final String note;

  /// Local time the bead was dropped.
  final DateTime created;
}
