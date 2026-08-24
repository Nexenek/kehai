import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/mood_entry.dart';

/// Maps a raw `mood_entries` [RecordModel] to a [MoodEntry]. Split out as a
/// top-level function (see `board_repository.dart`'s `boardItemFromRecord`
/// doc comment for why) so the mapping is unit-testable without a live
/// collection.
MoodEntry moodEntryFromRecord(RecordModel r) => MoodEntry(
  id: r.id,
  coupleId: r.get<String>('couple'),
  userId: r.get<String>('user'),
  mood: r.get<String>('mood'),
  note: r.get<String>('note', ''),
  created:
      DateTime.tryParse(r.get<String>('created'))?.toLocal() ?? DateTime.now(),
);

/// `mood_entries` — the mood jar (kb/features.md "Mood jar / mood
/// history"): read + realtime-subscribe only. The collection is entirely
/// server-written (server/moodjar.go appends a bead whenever a status's
/// mood actually changes, server/migrations/15_moodjar.go blocks
/// create/update/delete for everyone else), so there is deliberately no
/// create/update/delete here — the jar is a keepsake of what already
/// happened, not something the app fills in.
class MoodJarRepository {
  MoodJarRepository(this._pb);

  final PocketBase _pb;

  static const defaultLimit = 200;

  MoodEntry _fromRecord(RecordModel r) => moodEntryFromRecord(r);

  /// The most recent [limit] beads for [coupleId], newest first — plenty
  /// for a jar that's a season of feelings, not an archive (90-day purge,
  /// see server/moodjar.go's `moodEntryRetention`).
  Future<List<MoodEntry>> fetchRecent(
    String coupleId, {
    int limit = defaultLimit,
  }) async {
    try {
      final result = await _pb
          .collection('mood_entries')
          .getList(
            page: 1,
            perPage: limit,
            filter: 'couple = "$coupleId"',
            sort: '-created',
          );
      return result.items.map(_fromRecord).toList();
    } on ClientException catch (e) {
      if (e.statusCode == 404) return const [];
      rethrow;
    }
  }

  /// Fires on every new bead in the couple. There's nothing to reconcile
  /// beyond "add it" — beads are never updated (a mood-only compare, no
  /// note-only edits reach this collection) and deletion only ever happens
  /// via the purge cron, which the jar doesn't need to react to live.
  ///
  /// Swallows a subscribe failure into a no-op unsubscribe, matching every
  /// other realtime repository here (older servers without this
  /// migration).
  Future<UnsubscribeFunc> subscribe(
    void Function(MoodEntry entry) onEntry,
  ) async {
    try {
      return await _pb.collection('mood_entries').subscribe('*', (e) {
        if (e.record != null) onEntry(_fromRecord(e.record!));
      });
    } catch (_) {
      return () async {};
    }
  }
}
