import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import '../../domain/art_scene.dart';

/// Maps a raw `art_layers` [RecordModel] to an [ArtLayer]. Top-level (see
/// [InstantRepository]'s `instantFromRecord` for why) so the mapping —
/// including the defensive `conditions` parse — is unit-testable without a
/// live collection.
///
/// A record whose `slot` isn't one this app knows about (an older client, a
/// hand-edited row) maps to null rather than throwing: the compositor just
/// never sees it.
ArtLayer? artLayerFromRecord(PocketBase pb, RecordModel r) {
  final slot = ArtSlot.tryParse(r.get<String>('slot', ''));
  if (slot == null) return null;
  final imageField = r.get<String>('image', '');
  if (imageField.isEmpty) return null;

  return ArtLayer(
    id: r.id,
    coupleId: r.get<String>('couple', ''),
    slot: slot,
    name: r.get<String>('name', ''),
    imageUrl: pb.files.getUrl(r, imageField).toString(),
    sort: r.get<double>('sort', 0),
    // `conditions` is a JSON field: PocketBase hands it back decoded when
    // it can and as a raw string otherwise, and it's free-form either way —
    // ArtConditions.fromJson takes `Object?` and never throws.
    conditions: ArtConditions.fromJson(r.data['conditions']),
  );
}

/// `art_layers` — the paper-doll art the couple draws for each other
/// (ADR-13, server/migrations/10_art.go). Ownership is fully shared
/// server-side, so this repository never distinguishes who uploaded what.
///
/// Like the other picture collections, every call treats a 404 as "no art
/// yet" instead of an error, so a client pointed at a server that hasn't
/// run migration 10 shows the kaomoji fallback rather than crashing.
class ArtRepository {
  ArtRepository(this._pb);

  final PocketBase _pb;

  /// Every layer the couple has, unsorted — [resolveArtScene] and
  /// [artLayersInSlot] impose their own order.
  Future<List<ArtLayer>> fetchAll(String coupleId) async {
    try {
      final records = await _pb
          .collection('art_layers')
          .getFullList(filter: 'couple = "$coupleId"', sort: 'sort');
      return records
          .map((r) => artLayerFromRecord(_pb, r))
          .nonNulls
          .toList(growable: false);
    } on ClientException catch (e) {
      if (e.statusCode == 404) return const [];
      rethrow;
    }
  }

  /// Uploads one drawn layer. [imageBytes] must be a PNG — enforced
  /// client-side before we get here (see `art_image_prep.dart`) so the
  /// artist gets a sentence instead of a 400.
  Future<void> create({
    required String coupleId,
    required ArtSlot slot,
    required String name,
    required Uint8List imageBytes,
    required String filename,
    ArtConditions conditions = ArtConditions.any,
    double sort = 0,
  }) {
    return _pb
        .collection('art_layers')
        .create(
          body: {
            'couple': coupleId,
            'slot': slot.name,
            'name': name,
            'sort': sort,
            'conditions': conditions.toJson(),
          },
          files: [
            http.MultipartFile.fromBytes(
              'image',
              imageBytes,
              filename: filename,
            ),
          ],
        );
  }

  /// Edits a layer's metadata. The drawing itself is never edited in place
  /// — redrawing means uploading a new layer and deleting the old one, so
  /// there's no half-updated state where the name says one thing and the
  /// picture shows another.
  Future<void> update(
    String id, {
    String? name,
    ArtConditions? conditions,
    double? sort,
  }) {
    return _pb
        .collection('art_layers')
        .update(
          id,
          body: {
            // Only the keys the caller actually passed are sent, so a
            // rename never clobbers conditions and a reorder never
            // clobbers a name.
            'name': ?name,
            if (conditions != null) 'conditions': conditions.toJson(),
            'sort': ?sort,
          },
        );
  }

  Future<void> delete(String id) => _pb.collection('art_layers').delete(id);

  /// Fires on create/update/delete alike — this is what makes new art show
  /// up in the *other* partner's window while the artist is still drawing.
  /// A subscribe failure (no such collection yet) degrades to a no-op
  /// unsubscribe, matching the other realtime repositories.
  Future<UnsubscribeFunc> subscribe(
    void Function(String action, ArtLayer layer) onChange,
  ) async {
    try {
      return await _pb.collection('art_layers').subscribe('*', (e) {
        final record = e.record;
        if (record == null) return;
        final layer = artLayerFromRecord(_pb, record);
        if (layer != null) onChange(e.action, layer);
      });
    } catch (_) {
      return () async {};
    }
  }
}
