import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/pet.dart';
import '../../domain/models/pet_event.dart';

/// Maps a raw `pets` [RecordModel] to a [Pet]. Top-level (like
/// `instantFromRecord`) so the mapping is unit-testable without a server.
Pet petFromRecord(RecordModel r) => Pet(
  id: r.id,
  coupleId: r.get<String>('couple'),
  name: r.get<String>('name'),
  variant: PetVariant.fromString(r.get<String>('variant')),
  outfit: PetOutfit.fromString(r.get<String>('outfit')),
  fedAt: _parseDate(r.get<String>('fed_at')),
  petAt: _parseDate(r.get<String>('pet_at')),
);

/// Maps a raw `pet_events` [RecordModel] to a [PetEvent]. Same
/// top-level-for-testability shape as [petFromRecord].
PetEvent petEventFromRecord(RecordModel r) => PetEvent(
  id: r.id,
  coupleId: r.get<String>('couple'),
  userId: r.get<String>('user'),
  type: r.get<String>('type'),
  created:
      DateTime.tryParse(r.get<String>('created'))?.toLocal() ?? DateTime.now(),
);

DateTime? _parseDate(String raw) =>
    raw.isEmpty ? null : DateTime.tryParse(raw)?.toLocal();

/// The one shared pet per couple, plus its append-only care log
/// (server/migrations/6_pet.go).
///
/// Every care action is a plain update to the single `pets` row — both
/// partners write the same record, so "who fed them last" is simply
/// whoever's write landed last, and realtime carries it to the other side
/// within a moment. Each action also appends a `pet_events` row so a future
/// pet-history view has something to read; that append is best-effort and
/// never blocks (or fails) the action itself.
///
/// Like [InstantRepository], a missing collection (older server) is treated
/// as "no pet yet" rather than an exception, so the window falls back to its
/// gentle empty state instead of throwing.
class PetRepository {
  PetRepository(this._pb);

  final PocketBase _pb;

  /// The couple's pet, or null if they haven't adopted one yet.
  Future<Pet?> fetch(String coupleId) async {
    try {
      final records = await _pb
          .collection('pets')
          .getList(page: 1, perPage: 1, filter: 'couple = "$coupleId"');
      if (records.items.isEmpty) return null;
      return petFromRecord(records.items.first);
    } on ClientException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Fetches the couple's pet, adopting one if there isn't one yet.
  ///
  /// Adoption stamps `fed_at`/`pet_at` to now so a brand-new pet starts off
  /// full and cosy rather than in the wistful "dreaming of snacks" state.
  /// If both partners open the app at the same second, the unique index on
  /// `couple` rejects the loser's create — so a failed create re-reads and
  /// returns the partner's pet instead of surfacing an error.
  Future<Pet?> getOrCreate(String coupleId, {DateTime? now}) async {
    final existing = await fetch(coupleId);
    if (existing != null) return existing;

    final stamp = (now ?? DateTime.now()).toUtc().toIso8601String();
    try {
      final record = await _pb
          .collection('pets')
          .create(
            body: {
              'couple': coupleId,
              'name': '',
              'variant': PetVariant.blob.name,
              'outfit': PetOutfit.none.name,
              'fed_at': stamp,
              'pet_at': stamp,
            },
          );
      return petFromRecord(record);
    } on ClientException catch (e) {
      if (e.statusCode == 404) return null;
      // Lost the adoption race (or any other write refusal) — if a pet
      // exists now, it's ours either way.
      return fetch(coupleId);
    }
  }

  /// A snack ♡ — bumps `fed_at`.
  Future<Pet> feed(Pet pet, {required String userId, DateTime? now}) => _care(
    pet,
    userId: userId,
    type: 'feed',
    body: {'fed_at': (now ?? DateTime.now()).toUtc().toIso8601String()},
  );

  /// A cuddle — bumps `pet_at`.
  Future<Pet> cuddle(Pet pet, {required String userId, DateTime? now}) => _care(
    pet,
    userId: userId,
    type: 'pet',
    body: {'pet_at': (now ?? DateTime.now()).toUtc().toIso8601String()},
  );

  /// Changes the painted look — variant and/or accessory.
  Future<Pet> dress(
    Pet pet, {
    required String userId,
    required PetVariant variant,
    required PetOutfit outfit,
  }) => _care(
    pet,
    userId: userId,
    type: 'dress',
    body: {'variant': variant.name, 'outfit': outfit.name},
  );

  /// Renames the pet. Trimmed and capped at the server's 30 characters; an
  /// empty name is allowed and simply falls back to [Pet.displayName].
  Future<Pet> rename(Pet pet, {required String userId, required String name}) {
    final trimmed = name.trim();
    return _care(
      pet,
      userId: userId,
      type: 'rename',
      body: {'name': trimmed.length > 30 ? trimmed.substring(0, 30) : trimmed},
    );
  }

  Future<Pet> _care(
    Pet pet, {
    required String userId,
    required String type,
    required Map<String, Object?> body,
  }) async {
    final record = await _pb.collection('pets').update(pet.id, body: body);
    await _logEvent(coupleId: pet.coupleId, userId: userId, type: type);
    return petFromRecord(record);
  }

  /// The couple's care-log events, newest first — the "story" behind the
  /// pet (server/migrations/6_pet.go doc comment: "the raw material for a
  /// future 'pet history' view"). [limit] defaults to a generous single
  /// page rather than real pagination; this is a glanceable recap, not a
  /// feed to scroll forever. Same "missing collection = nothing yet"
  /// handling as [fetch].
  Future<List<PetEvent>> fetchEvents(String coupleId, {int limit = 100}) async {
    try {
      final records = await _pb
          .collection('pet_events')
          .getList(
            page: 1,
            perPage: limit,
            filter: 'couple = "$coupleId"',
            sort: '-created',
          );
      return records.items.map(petEventFromRecord).toList();
    } on ClientException catch (e) {
      if (e.statusCode == 404) return [];
      rethrow;
    }
  }

  /// Appends to the care log. Deliberately swallowing failures: a lost log
  /// row must never make a feed look like it failed.
  Future<void> _logEvent({
    required String coupleId,
    required String userId,
    required String type,
  }) async {
    if (userId.isEmpty) return;
    try {
      await _pb
          .collection('pet_events')
          .create(body: {'couple': coupleId, 'user': userId, 'type': type});
    } catch (_) {
      // Best effort only — see doc comment.
    }
  }

  /// Live updates for the couple's pet: fires whenever either partner feeds,
  /// pets, dresses or renames it. Swallows a subscribe failure into a no-op
  /// unsubscribe (collection not there yet), matching [fetch].
  Future<UnsubscribeFunc> subscribe(void Function(Pet pet) onChange) async {
    try {
      return await _pb.collection('pets').subscribe('*', (e) {
        final record = e.record;
        if (record != null && e.action != 'delete') {
          onChange(petFromRecord(record));
        }
      });
    } catch (_) {
      return () async {};
    }
  }
}
