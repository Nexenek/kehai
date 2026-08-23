import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/instant.dart';

/// Maps a raw `instants` [RecordModel] to an [Instant]. Split out as a
/// top-level function (rather than a private method, unlike
/// [DoodleRepository]'s `_fromRecord`) so the mapping is unit-testable
/// without spinning up a fake collection — `pb.files.getUrl` is pure
/// string-building, so a bare `PocketBase(baseUrl)` plus a hand-built
/// [RecordModel] is enough.
Instant instantFromRecord(PocketBase pb, RecordModel r) => Instant(
  id: r.id,
  coupleId: r.get<String>('couple'),
  authorId: r.get<String>('author'),
  imageUrl: pb.files.getUrl(r, r.get<String>('image')).toString(),
  caption: r.get<String>('caption'),
  created:
      DateTime.tryParse(r.get<String>('created'))?.toLocal() ?? DateTime.now(),
);

/// One page of the reverse-chronological instants feed.
class InstantsPage {
  const InstantsPage({required this.items, required this.hasMore});

  final List<Instant> items;
  final bool hasMore;

  static const empty = InstantsPage(items: [], hasMore: false);
}

/// `instants` — a quick photo shared through the day (kb/contracts.md
/// "Instants"). Couple-scoped visibility + "author must be me" + "either
/// partner can delete" are enforced server-side; this repository just talks
/// to the collection. Immutable (no `update` — see [Instant]'s doc comment).
///
/// The server collection was being built in parallel with this app code as
/// of the contract lock (2026-08-23) — until it lands, PocketBase answers
/// calls against `instants` with a 404. Every method here treats that as
/// "nothing yet" instead of crashing, so the feed just shows its empty
/// state until the server catches up.
class InstantRepository {
  InstantRepository(this._pb);

  final PocketBase _pb;

  static const perPage = 30;

  Instant _fromRecord(RecordModel r) => instantFromRecord(_pb, r);

  /// The most recent [page] of instants for [coupleId], newest first.
  Future<InstantsPage> list(String coupleId, {int page = 1}) async {
    try {
      final result = await _pb
          .collection('instants')
          .getList(
            page: page,
            perPage: perPage,
            filter: 'couple = "$coupleId"',
            sort: '-created',
          );
      return InstantsPage(
        items: result.items.map(_fromRecord).toList(),
        hasMore: result.page < result.totalPages,
      );
    } on ClientException catch (e) {
      if (e.statusCode == 404) return InstantsPage.empty;
      rethrow;
    }
  }

  /// Uploads [imageBytes] as a new instant. [authorId] must be the caller's
  /// own user id — the server rejects anything else. [caption] may be
  /// empty; [filename] just needs a sensible extension (jpg/png/webp) for
  /// PocketBase to infer content type.
  Future<void> create({
    required String coupleId,
    required String authorId,
    required Uint8List imageBytes,
    required String filename,
    String caption = '',
  }) {
    return _pb
        .collection('instants')
        .create(
          body: {'couple': coupleId, 'author': authorId, 'caption': caption},
          files: [
            http.MultipartFile.fromBytes(
              'image',
              imageBytes,
              filename: filename,
            ),
          ],
        );
  }

  Future<void> delete(String id) => _pb.collection('instants').delete(id);

  /// Fires on create/delete alike (instants are immutable, so no 'update'
  /// action ever arrives) — see [DoodleRepository.subscribe] for why the
  /// raw action string is exposed. Swallows a subscribe failure (e.g. the
  /// collection not existing yet server-side) into a no-op unsubscribe
  /// rather than throwing, matching [list]'s "nothing yet" handling.
  Future<UnsubscribeFunc> subscribe(
    void Function(String action, Instant instant) onChange,
  ) async {
    try {
      return await _pb.collection('instants').subscribe('*', (e) {
        if (e.record != null) onChange(e.action, _fromRecord(e.record!));
      });
    } catch (_) {
      return () async {};
    }
  }
}
